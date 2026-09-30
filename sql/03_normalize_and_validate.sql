BEGIN;

-- Safely parse timestamps.
-- Invalid input returns NULL rather than stopping the entire batch.
CREATE OR REPLACE FUNCTION integration.try_timestamptz(
    input_value text
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN NULLIF(BTRIM(input_value), '')::timestamptz;
EXCEPTION
    WHEN invalid_datetime_format
      OR datetime_field_overflow
    THEN
        RETURN NULL;
END;
$$;

CREATE OR REPLACE VIEW integration.validated_bookings AS
WITH normalized AS (
    SELECT
        s.batch_id,
        s.source_row_id,
        s.book_ref_raw,
        s.book_date_raw,
        s.total_amount_raw,
        s.source_updated_at,

        NULLIF(
            UPPER(BTRIM(s.book_ref_raw)),
            ''
        ) AS normalized_book_ref,

        NULLIF(
            BTRIM(s.total_amount_raw),
            ''
        ) AS amount_text,

        integration.try_timestamptz(
            s.book_date_raw
        ) AS parsed_book_date

    FROM integration.staging_bookings AS s
),

parsed AS (
    SELECT
        n.*,

        -- Limit length and validate the format before casting.
        -- Accepted examples: 100, 100.50, -100.00.
        CASE
            WHEN LENGTH(n.amount_text) <= 15
             AND n.amount_text ~ '^-?[0-9]+([.][0-9]{1,2})?$'
            THEN n.amount_text::numeric
            ELSE NULL
        END AS parsed_amount

    FROM normalized AS n
),

reference_checked AS (
    SELECT
        p.*,
        r.book_ref AS reference_book_ref,
        r.book_date AS reference_book_date,
        r.total_amount AS expected_amount,

        -- Check identity and ordering fields before deduplication.
        CASE
            WHEN p.normalized_book_ref IS NULL
                THEN 'MISSING_BOOK_REF'

            WHEN r.book_ref IS NULL
                THEN 'UNKNOWN_BOOK_REF'

            WHEN p.source_updated_at IS NULL
                THEN 'MISSING_UPDATE_TIMESTAMP'

            ELSE NULL
        END AS preliminary_issue

    FROM parsed AS p

    LEFT JOIN integration.reference_bookings AS r
        ON r.book_ref = p.normalized_book_ref
),

ranked_candidates AS (
    SELECT
        batch_id,
        source_row_id,

        ROW_NUMBER() OVER (
            PARTITION BY batch_id, normalized_book_ref
            ORDER BY
                source_updated_at DESC,
                source_row_id DESC
        ) AS candidate_rank

    FROM reference_checked

    WHERE preliminary_issue IS NULL
),

evaluated AS (
    SELECT
        rc.*,
        rk.candidate_rank,

        CASE
            WHEN rc.preliminary_issue IS NOT NULL
                THEN rc.preliminary_issue

            WHEN rk.candidate_rank > 1
                THEN 'OLDER_OR_TIED_CANDIDATE'

            WHEN NULLIF(BTRIM(rc.book_date_raw), '') IS NULL
                THEN 'MISSING_BOOK_DATE'

            WHEN rc.parsed_book_date IS NULL
                THEN 'INVALID_BOOK_DATE'

            WHEN rc.parsed_book_date <> rc.reference_book_date
                THEN 'BOOK_DATE_MISMATCH'

            WHEN rc.amount_text IS NULL
                THEN 'MISSING_AMOUNT'

            WHEN rc.parsed_amount IS NULL
                THEN 'INVALID_AMOUNT_FORMAT'

            WHEN rc.parsed_amount < 0
                THEN 'NEGATIVE_AMOUNT'

            WHEN rc.parsed_amount <> rc.expected_amount
                THEN 'TOTAL_MISMATCH'

            ELSE 'VALID_LATEST_CANDIDATE'
        END AS reason_code

    FROM reference_checked AS rc

    LEFT JOIN ranked_candidates AS rk
        ON rk.batch_id = rc.batch_id
       AND rk.source_row_id = rc.source_row_id
)

SELECT
    batch_id,
    source_row_id,
    book_ref_raw,
    normalized_book_ref,
    parsed_book_date AS book_date,
    parsed_amount AS total_amount,
    expected_amount,
    source_updated_at,
    candidate_rank,

    CASE
        WHEN preliminary_issue IS NOT NULL
            THEN 'rejected'

        WHEN candidate_rank > 1
            THEN 'superseded'

        WHEN reason_code = 'VALID_LATEST_CANDIDATE'
            THEN 'accepted'

        ELSE 'rejected'
    END AS disposition,

    reason_code

FROM evaluated;

COMMIT;

SELECT
    batch_id,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE disposition = 'accepted'
    ) AS accepted_rows,
    COUNT(*) FILTER (
        WHERE disposition = 'rejected'
    ) AS rejected_rows,
    COUNT(*) FILTER (
        WHERE disposition = 'superseded'
    ) AS superseded_rows
FROM integration.validated_bookings
GROUP BY batch_id
ORDER BY batch_id;

SELECT
    source_row_id,
    book_ref_raw,
    total_amount,
    expected_amount,
    reason_code
FROM integration.validated_bookings
WHERE batch_id = 1
  AND disposition = 'rejected'
ORDER BY source_row_id;

SELECT
    source_row_id,
    normalized_book_ref,
    source_updated_at,
    candidate_rank,
    total_amount,
    expected_amount,
    disposition,
    reason_code
FROM integration.validated_bookings
WHERE batch_id = 1
  AND source_row_id IN (20, 21, 22, 220, 221, 222)
ORDER BY normalized_book_ref, candidate_rank;
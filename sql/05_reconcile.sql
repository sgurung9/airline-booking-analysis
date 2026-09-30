-- Reconcile destination records against the reference,
-- accepted updates, saved classifications, and audit summaries.

WITH latest_accepted AS (
    SELECT
        normalized_book_ref,
        book_date,
        total_amount,
        source_updated_at,
        batch_id,

        ROW_NUMBER() OVER (
            PARTITION BY normalized_book_ref
            ORDER BY
                source_updated_at DESC,
                batch_id DESC,
                source_row_id DESC
        ) AS update_rank

    FROM integration.validated_bookings
    WHERE disposition = 'accepted'
),

checks AS (
    -- Every reference booking should be present after both batches.
    SELECT
        '01_missing_destination_bookings' AS check_name,
        COUNT(*) AS failure_count
    FROM integration.reference_bookings AS r
    LEFT JOIN integration.clean_bookings AS c
        ON c.book_ref = r.book_ref
    WHERE c.book_ref IS NULL

    UNION ALL

    -- The destination should contain no unknown booking references.
    SELECT
        '02_unexpected_destination_bookings',
        COUNT(*)
    FROM integration.clean_bookings AS c
    LEFT JOIN integration.reference_bookings AS r
        ON r.book_ref = c.book_ref
    WHERE r.book_ref IS NULL

    UNION ALL

    -- Confirm destination amounts and dates match the reference.
    SELECT
        '03_reference_value_mismatches',
        COUNT(*)
    FROM integration.clean_bookings AS c
    JOIN integration.reference_bookings AS r
        ON r.book_ref = c.book_ref
    WHERE c.total_amount IS DISTINCT FROM r.total_amount
       OR c.book_date IS DISTINCT FROM r.book_date

    UNION ALL

    -- Confirm the destination reflects the newest accepted update.
    -- This detects older updates overwriting newer records.
    SELECT
        '04_latest_update_mismatches',
        COUNT(*)
    FROM latest_accepted AS a
    LEFT JOIN integration.clean_bookings AS c
        ON c.book_ref = a.normalized_book_ref
    WHERE a.update_rank = 1
      AND (
          c.book_ref IS NULL
          OR c.source_updated_at
              IS DISTINCT FROM a.source_updated_at
          OR c.total_amount IS DISTINCT FROM a.total_amount
          OR c.book_date IS DISTINCT FROM a.book_date
          OR c.last_batch_id IS DISTINCT FROM a.batch_id
      )

    UNION ALL

    -- Every incoming row should have a saved disposition.
    SELECT
        '05_missing_record_dispositions',
        COUNT(*)
    FROM integration.staging_bookings AS s
    LEFT JOIN integration.record_dispositions AS d
        ON d.batch_id = s.batch_id
       AND d.source_row_id = s.source_row_id
    WHERE d.source_row_id IS NULL

    UNION ALL

    -- Saved classifications should agree with the validation view.
    SELECT
        '06_disposition_mismatches',
        COUNT(*)
    FROM integration.validated_bookings AS v
    JOIN integration.record_dispositions AS d
        ON d.batch_id = v.batch_id
       AND d.source_row_id = v.source_row_id
    WHERE d.disposition IS DISTINCT FROM v.disposition
       OR d.reason_code IS DISTINCT FROM v.reason_code
       OR d.normalized_book_ref
           IS DISTINCT FROM v.normalized_book_ref

    UNION ALL

    -- Every staged batch should have a completion audit.
    SELECT
        '07_missing_batch_audits',
        COUNT(*)
    FROM (
        SELECT DISTINCT batch_id
        FROM integration.staging_bookings
    ) AS s
    LEFT JOIN integration.import_audit AS a
        ON a.batch_id = s.batch_id
    WHERE a.batch_id IS NULL

    UNION ALL

    -- Audit counts should agree with the actual classifications.
    SELECT
        '08_audit_classification_mismatches',
        COUNT(*)
    FROM integration.import_audit AS a
    LEFT JOIN (
        SELECT
            batch_id,
            COUNT(*) AS staged_count,
            COUNT(*) FILTER (
                WHERE disposition = 'accepted'
            ) AS accepted_count,
            COUNT(*) FILTER (
                WHERE disposition = 'rejected'
            ) AS rejected_count,
            COUNT(*) FILTER (
                WHERE disposition = 'superseded'
            ) AS superseded_count
        FROM integration.validated_bookings
        GROUP BY batch_id
    ) AS v
        ON v.batch_id = a.batch_id
    WHERE a.staged_count IS DISTINCT FROM v.staged_count
       OR a.accepted_count IS DISTINCT FROM v.accepted_count
       OR a.rejected_count IS DISTINCT FROM v.rejected_count
       OR a.superseded_count IS DISTINCT FROM v.superseded_count

    UNION ALL

    -- Check uniqueness explicitly, although the primary key enforces it.
    SELECT
        '09_duplicate_destination_keys',
        COUNT(*)
    FROM (
        SELECT book_ref
        FROM integration.clean_bookings
        GROUP BY book_ref
        HAVING COUNT(*) > 1
    ) AS duplicates
)

SELECT
    check_name,
    failure_count,
    CASE
        WHEN failure_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM checks
ORDER BY check_name;

SELECT
    batch_id,
    source_row_id,
    normalized_book_ref,
    candidate_rank,
    total_amount,
    expected_amount,
    source_updated_at,
    disposition,
    reason_code
FROM integration.validated_bookings
ORDER BY batch_id, source_row_id;
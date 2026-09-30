-- Reusable batch loader.
-- A completed batch is skipped when requested again.
CREATE OR REPLACE PROCEDURE integration.load_batch(
    p_batch_id integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staged      integer;
    v_accepted    integer;
    v_rejected    integer;
    v_superseded  integer;
    v_inserted    integer;
    v_updated     integer;
    v_unchanged   integer;
BEGIN
    -- Serialize destination writes and keep inputs stable during loading.
    LOCK TABLE integration.clean_bookings,
               integration.record_dispositions,
               integration.import_audit
        IN SHARE ROW EXCLUSIVE MODE;

    LOCK TABLE integration.staging_bookings,
               integration.reference_bookings
        IN SHARE MODE;

    IF EXISTS (
        SELECT 1
        FROM integration.import_audit
        WHERE batch_id = p_batch_id
    ) THEN
        RAISE NOTICE 'Batch % already completed; skipped.',
            p_batch_id;
        RETURN;
    END IF;

    SELECT COUNT(*)
    INTO v_staged
    FROM integration.staging_bookings
    WHERE batch_id = p_batch_id;

    IF v_staged = 0 THEN
        RAISE EXCEPTION 'Batch % has no staging records.',
            p_batch_id;
    END IF;

    SELECT
        COUNT(*) FILTER (WHERE disposition = 'accepted'),
        COUNT(*) FILTER (WHERE disposition = 'rejected'),
        COUNT(*) FILTER (WHERE disposition = 'superseded')
    INTO
        v_accepted,
        v_rejected,
        v_superseded
    FROM integration.validated_bookings
    WHERE batch_id = p_batch_id;

    -- Determine destination actions before changing the destination.
    SELECT
        COUNT(*) FILTER (
            WHERE c.book_ref IS NULL
        ),
        COUNT(*) FILTER (
            WHERE c.book_ref IS NOT NULL
              AND v.source_updated_at > c.source_updated_at
        ),
        COUNT(*) FILTER (
            WHERE c.book_ref IS NOT NULL
              AND v.source_updated_at <= c.source_updated_at
        )
    INTO
        v_inserted,
        v_updated,
        v_unchanged
    FROM integration.validated_bookings AS v
    LEFT JOIN integration.clean_bookings AS c
        ON c.book_ref = v.normalized_book_ref
    WHERE v.batch_id = p_batch_id
      AND v.disposition = 'accepted';

    -- Store one classification for every incoming row.
    INSERT INTO integration.record_dispositions (
        batch_id,
        source_row_id,
        normalized_book_ref,
        disposition,
        reason_code,
        details
    )
    SELECT
        batch_id,
        source_row_id,
        normalized_book_ref,
        disposition,
        reason_code,
        FORMAT(
            'candidate_rank=%s; incoming_amount=%s; expected_amount=%s',
            candidate_rank,
            total_amount,
            expected_amount
        )
    FROM integration.validated_bookings
    WHERE batch_id = p_batch_id;

    -- Insert missing bookings or update only with a newer timestamp.
    INSERT INTO integration.clean_bookings AS destination (
        book_ref,
        book_date,
        total_amount,
        source_updated_at,
        last_batch_id
    )
    SELECT
        normalized_book_ref,
        book_date,
        total_amount,
        source_updated_at,
        batch_id
    FROM integration.validated_bookings
    WHERE batch_id = p_batch_id
      AND disposition = 'accepted'

    ON CONFLICT (book_ref)
    DO UPDATE SET
        book_date = EXCLUDED.book_date,
        total_amount = EXCLUDED.total_amount,
        source_updated_at = EXCLUDED.source_updated_at,
        last_batch_id = EXCLUDED.last_batch_id,
        loaded_at = CURRENT_TIMESTAMP

    WHERE EXCLUDED.source_updated_at >
          destination.source_updated_at;

    -- Constraints verify that classification/action counts balance.
    INSERT INTO integration.import_audit (
        batch_id,
        staged_count,
        accepted_count,
        rejected_count,
        superseded_count,
        inserted_count,
        updated_count,
        unchanged_count
    )
    VALUES (
        p_batch_id,
        v_staged,
        v_accepted,
        v_rejected,
        v_superseded,
        v_inserted,
        v_updated,
        v_unchanged
    );

    RAISE NOTICE
        'Batch % completed: % inserted, % updated, % unchanged.',
        p_batch_id, v_inserted, v_updated, v_unchanged;
END;
$$;

-- Each batch commits independently.
-- An unexpected error rolls back that batch's changes.
BEGIN;
CALL integration.load_batch(1);
COMMIT;

BEGIN;
CALL integration.load_batch(2);
COMMIT;

SELECT
    batch_id,
    staged_count,
    accepted_count,
    rejected_count,
    superseded_count,
    inserted_count,
    updated_count,
    unchanged_count
FROM integration.import_audit
ORDER BY batch_id;

SELECT COUNT(*) AS destination_bookings
FROM integration.clean_bookings;

BEGIN;
CALL integration.load_batch(2);
COMMIT;

SELECT
    (SELECT COUNT(*)
     FROM integration.clean_bookings) AS destination_records,

    (SELECT COUNT(*)
     FROM integration.record_dispositions) AS classified_records,

    (SELECT COUNT(*)
     FROM integration.import_audit) AS completed_batches;
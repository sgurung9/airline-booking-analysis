BEGIN;

-- Use a newer timestamp so this test would update a destination record.
INSERT INTO integration.staging_bookings (
    batch_id,
    source_row_id,
    book_ref_raw,
    book_date_raw,
    total_amount_raw,
    source_updated_at
)
SELECT
    99,
    1,
    book_ref,
    book_date::text,
    total_amount::text,
    TIMESTAMPTZ '2026-09-03 09:00:00+00'
FROM integration.reference_bookings
ORDER BY book_ref
LIMIT 1;

COMMIT;

-- Store the destination's current state for comparison after rollback.
CREATE TEMP TABLE rollback_before AS
SELECT c.*
FROM integration.clean_bookings AS c
JOIN integration.staging_bookings AS s
    ON s.book_ref_raw = c.book_ref
WHERE s.batch_id = 99;

BEGIN;

CALL integration.load_batch(99);

-- Intentional failure: destination amounts cannot be negative.
UPDATE integration.clean_bookings
SET total_amount = -1
WHERE book_ref IN (
    SELECT book_ref
    FROM rollback_before
);

ROLLBACK;


SELECT
    NOT EXISTS (
        SELECT 1
        FROM integration.clean_bookings AS c
        JOIN rollback_before AS b
            ON b.book_ref = c.book_ref
        WHERE ROW(
            c.book_date,
            c.total_amount,
            c.source_updated_at,
            c.last_batch_id,
            c.loaded_at
        ) IS DISTINCT FROM ROW(
            b.book_date,
            b.total_amount,
            b.source_updated_at,
            b.last_batch_id,
            b.loaded_at
        )
    ) AS destination_unchanged,

    NOT EXISTS (
        SELECT 1
        FROM integration.record_dispositions
        WHERE batch_id = 99
    ) AS dispositions_rolled_back,

    NOT EXISTS (
        SELECT 1
        FROM integration.import_audit
        WHERE batch_id = 99
    ) AS audit_rolled_back;


DELETE FROM integration.staging_bookings
WHERE batch_id = 99;

DROP TABLE rollback_before;
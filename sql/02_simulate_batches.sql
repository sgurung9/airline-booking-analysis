BEGIN;

-- Batch 1: 200 source bookings with controlled data issues.
WITH numbered_bookings AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY book_ref) AS row_num
    FROM integration.reference_bookings
)
INSERT INTO integration.staging_bookings (
    batch_id,
    source_row_id,
    book_ref_raw,
    book_date_raw,
    total_amount_raw,
    source_updated_at
)
SELECT
    1,
    row_num::integer,

    CASE
        WHEN row_num = 1 THEN NULL
        WHEN row_num = 2 THEN 'ZZZZZZ'
        WHEN row_num BETWEEN 9 AND 12
            THEN ' ' || LOWER(book_ref) || ' '
        ELSE book_ref
    END,

    book_date::text,

    CASE
        WHEN row_num = 3 THEN ''
        WHEN row_num = 4 THEN 'not_available'
        WHEN row_num = 5 THEN '-100.00'
        WHEN row_num = 6 THEN (total_amount + 25)::text
        ELSE total_amount::text
    END,

    CASE
        WHEN row_num = 7 THEN NULL
        ELSE TIMESTAMPTZ '2026-09-01 09:00:00+00'
    END
FROM numbered_bookings;

-- Add three competing updates.
-- Booking 20: latest valid update wins.
-- Booking 21: latest update is invalid; do not fall back to the older row.
-- Booking 22: identical timestamps; higher source_row_id wins.
WITH numbered_bookings AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY book_ref) AS row_num
    FROM integration.reference_bookings
)
INSERT INTO integration.staging_bookings (
    batch_id,
    source_row_id,
    book_ref_raw,
    book_date_raw,
    total_amount_raw,
    source_updated_at
)
SELECT
    1,
    (200 + row_num)::integer,
    book_ref,
    book_date::text,

    CASE
        WHEN row_num = 21 THEN (total_amount + 50)::text
        ELSE total_amount::text
    END,

    CASE
        WHEN row_num = 22
            THEN TIMESTAMPTZ '2026-09-01 09:00:00+00'
        ELSE TIMESTAMPTZ '2026-09-01 10:00:00+00'
    END
FROM numbered_bookings
WHERE row_num IN (20, 21, 22);

-- Batch 2:
-- Rows 1–7 correct the initial rejected records.
-- Row 21 corrects the invalid latest update.
-- Rows 30–34 contain newer valid updates.
-- Rows 35–39 contain older updates that must not overwrite the destination.
WITH numbered_bookings AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY book_ref) AS row_num
    FROM integration.reference_bookings
)
INSERT INTO integration.staging_bookings (
    batch_id,
    source_row_id,
    book_ref_raw,
    book_date_raw,
    total_amount_raw,
    source_updated_at
)
SELECT
    2,
    row_num::integer,
    book_ref,
    book_date::text,
    total_amount::text,

    CASE
        WHEN row_num BETWEEN 35 AND 39
            THEN TIMESTAMPTZ '2026-08-31 09:00:00+00'
        ELSE TIMESTAMPTZ '2026-09-02 09:00:00+00'
    END
FROM numbered_bookings
WHERE row_num BETWEEN 1 AND 7
   OR row_num = 21
   OR row_num BETWEEN 30 AND 39;

COMMIT;

SELECT
    batch_id,
    COUNT(*) AS incoming_rows,
    COUNT(*) FILTER (
        WHERE book_ref_raw IS NULL
    ) AS missing_booking_references,
    COUNT(*) FILTER (
        WHERE source_updated_at IS NULL
    ) AS missing_update_timestamps
FROM integration.staging_bookings
GROUP BY batch_id
ORDER BY batch_id;

SELECT *
FROM integration.staging_bookings
WHERE batch_id = 1
  AND (
      source_row_id BETWEEN 1 AND 12
      OR source_row_id IN (20, 21, 22, 220, 221, 222)
  )
ORDER BY source_row_id;
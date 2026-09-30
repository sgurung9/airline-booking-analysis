BEGIN;

CREATE SCHEMA IF NOT EXISTS integration;

-- Reference sample: verify booking totals against ticket-flight charges.
-- Aggregate flight charges at booking level before selecting the sample.
CREATE TABLE integration.reference_bookings AS
WITH calculated_totals AS (
    SELECT
        t.book_ref,
        SUM(tf.amount) AS calculated_amount
    FROM bookings.tickets AS t
    JOIN bookings.ticket_flights AS tf
        ON tf.ticket_no = t.ticket_no
    GROUP BY t.book_ref
)
SELECT
    b.book_ref::varchar(6) AS book_ref,
    b.book_date,
    b.total_amount,
    ct.calculated_amount
FROM bookings.bookings AS b
JOIN calculated_totals AS ct
    ON ct.book_ref = b.book_ref
WHERE b.total_amount = ct.calculated_amount
ORDER BY b.book_ref
LIMIT 200;

ALTER TABLE integration.reference_bookings
    ADD PRIMARY KEY (book_ref);

-- Raw incoming data: text columns intentionally allow malformed values.
CREATE TABLE integration.staging_bookings (
    batch_id            integer NOT NULL,
    source_row_id       integer NOT NULL,
    book_ref_raw        text,
    book_date_raw       text,
    total_amount_raw    text,
    source_updated_at   timestamptz,
    PRIMARY KEY (batch_id, source_row_id)
);

-- Accepted destination records.
CREATE TABLE integration.clean_bookings (
    book_ref            varchar(6) PRIMARY KEY,
    book_date           timestamptz NOT NULL,
    total_amount        numeric(12, 2) NOT NULL
                        CHECK (total_amount >= 0),
    source_updated_at   timestamptz NOT NULL,
    last_batch_id       integer NOT NULL,
    loaded_at           timestamptz NOT NULL
                        DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (book_ref)
        REFERENCES integration.reference_bookings (book_ref)
);

-- One classification per incoming row.
CREATE TABLE integration.record_dispositions (
    batch_id            integer NOT NULL,
    source_row_id       integer NOT NULL,
    normalized_book_ref text,
    disposition         text NOT NULL
                        CHECK (
                            disposition IN (
                                'accepted',
                                'rejected',
                                'superseded'
                            )
                        ),
    reason_code         text NOT NULL,
    details             text,
    processed_at        timestamptz NOT NULL
                        DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (batch_id, source_row_id),
    FOREIGN KEY (batch_id, source_row_id)
        REFERENCES integration.staging_bookings (
            batch_id,
            source_row_id
        )
);

-- One summary per batch.
CREATE TABLE integration.import_audit (
    batch_id            integer PRIMARY KEY,
    staged_count        integer NOT NULL CHECK (staged_count >= 0),
    accepted_count      integer NOT NULL CHECK (accepted_count >= 0),
    rejected_count      integer NOT NULL CHECK (rejected_count >= 0),
    superseded_count    integer NOT NULL CHECK (superseded_count >= 0),
    inserted_count      integer NOT NULL CHECK (inserted_count >= 0),
    updated_count       integer NOT NULL CHECK (updated_count >= 0),
    unchanged_count     integer NOT NULL CHECK (unchanged_count >= 0),
    processed_at        timestamptz NOT NULL
                        DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        staged_count =
        accepted_count + rejected_count + superseded_count
    ),
    CHECK (
        accepted_count =
        inserted_count + updated_count + unchanged_count
    )
);

COMMIT;

SELECT
    COUNT(*) AS reference_booking_count,
    COUNT(*) FILTER (
        WHERE total_amount <> calculated_amount
    ) AS mismatched_totals,
    COUNT(DISTINCT book_ref) AS unique_booking_count
FROM integration.reference_bookings;
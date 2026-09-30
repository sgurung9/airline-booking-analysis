-- Chart 1: incoming records by validation outcome.
SELECT
    batch_id,
    accepted_count AS accepted,
    rejected_count AS rejected,
    superseded_count AS superseded
FROM integration.import_audit
ORDER BY batch_id;

-- Chart 2: how accepted records affected the destination.
SELECT
    batch_id,
    inserted_count AS inserted,
    updated_count AS updated,
    unchanged_count AS unchanged
FROM integration.import_audit
ORDER BY batch_id;
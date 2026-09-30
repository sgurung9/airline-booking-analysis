# airline-booking-analysis

# ✈️ Airline Booking Import and Reconciliation — PostgreSQL

![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL-blue)
![SQL](https://img.shields.io/badge/Language-SQL-orange)
![Status](https://img.shields.io/badge/Status-In%20Progress-yellow)

A scenario-based **airline booking data integration project** using PostgreSQL to investigate import errors, resolve competing updates, load accepted records, and reconcile source and destination data.

The project uses the **Postgres Professional Airlines demonstration database** as a reference dataset. Separate staging batches simulate incoming updates with intentionally introduced data problems. The focus is on SQL troubleshooting, data quality, transactional loading, and reproducible verification.

> **Project status:** This README describes the intended implementation. SQL scripts, screenshots, and measured results will be added as the project is completed. Features listed below are planned until verified by the completion checklist.

---

## 📌 Table of Contents

- [Project Overview](#-project-overview)
- [Objectives](#-objectives)
- [Data Source](#-data-source)
- [Import Scenario](#-import-scenario)
- [Database Architecture](#-database-architecture)
- [Database Entities](#-database-entities)
- [Key Relationships](#-key-relationships)
- [Technologies Used](#-technologies-used)
- [Project Structure](#-project-structure)
- [SQL Features](#-sql-features)
- [Data Processing Workflow](#-data-processing-workflow)
- [Validation and Business Rules](#-validation-and-business-rules)
- [Transaction Control](#-transaction-control)
- [Exception Reporting](#-exception-reporting)
- [Troubleshooting Case](#-troubleshooting-case)
- [Test Cases](#-test-cases)
- [Results and Visuals](#-results-and-visuals)
- [How to Run](#-how-to-run)
- [Learning Outcomes](#-learning-outcomes)
- [Completion Checklist](#-completion-checklist)
- [Limitations](#-limitations)
- [Author](#-author)

---

## 📖 Project Overview

An analytical system needs dependable booking data before it can produce trustworthy reports. Incoming files may contain missing identifiers, duplicate updates, inconsistent formatting, or totals that disagree with the underlying ticket records.

This project builds a small SQL workflow that preserves incoming data, explains rejected records, and verifies successful loading. It separates data quality errors from database execution failures and distinguishes accepted records from records that actually change the destination.

## 🎯 Objectives

- Understand the grain and relationships of booking, ticket, and flight-segment tables.
- Extract a reproducible sample of approximately 200 bookings.
- Simulate two import batches containing known data quality issues.
- Normalize identifiers without losing the original input values.
- Use window functions to select the latest update deterministically.
- Generate actionable exception reports.
- Load valid records with transactional UPSERT logic.
- Reconcile counts and amounts across processing stages.
- Verify that repeated imports do not create duplicate destination or exception records.
- Explain one troubleshooting case using diagnostic SQL and before-and-after evidence.

## 📚 Data Source

**Provider:** Postgres Professional  
**Dataset:** Airlines demonstration database, 2017 English small version  
**Format:** PostgreSQL SQL dump inside `demo-small-en.zip`

- [Download and installation instructions](https://postgrespro.com/docs/postgrespro/13/demodb-bookings-installation.html)
- [Database overview and schema documentation](https://postgrespro.com/docs/postgrespro/13/demodb-bookings.html)
- [Booking examples](https://postgrespro.com/docs/postgrespro/12/demodb-usage.html)

The small download contains one month of demonstration airline data. It is a simulated database, not a live airline system or real customer transaction feed. The 2017 version uses `ticket_flights`; the newer 2025 version has a different schema and is not the version targeted here.

The source database is distributed under the PostgreSQL license. Preserve the source attribution and applicable license when redistributing extracted sample data. Project-created batches, timestamps, and injected errors should be labeled as simulated additions.

## 🧩 Import Scenario

A travel reporting system receives recurring booking updates. The first batch populates an empty destination; the second contains unchanged bookings, newer updates, and intentional errors.

The reference ticket-flight amounts are treated as authoritative for this simulation. A changed incoming amount is accepted only when it matches the associated reference total. This deliberately simplified rule tests reconciliation; it does not model all legitimate airline repricing or refund scenarios.

## 🗄️ Database Architecture

Use a separate `integration` schema for the project objects. Keep the source `bookings` schema unchanged.

| Layer | Purpose |
|---|---|
| Reference | Source bookings, tickets, and ticket-flight amounts |
| Staging | Original incoming rows and simulated update metadata |
| Validation | Normalized values, update ranking, and issue flags |
| Destination | Latest accepted booking state |
| Exceptions | Rejected and superseded input records |
| Audit | Batch-level processing and reconciliation summaries |

## 📊 Database Entities

| Table | Grain | Important fields |
|---|---|---|
| `bookings.bookings` | One booking | `book_ref`, `book_date`, `total_amount` |
| `bookings.tickets` | One ticket | `ticket_no`, `book_ref` |
| `bookings.ticket_flights` | One ticket-flight segment | `ticket_no`, `flight_id`, `amount` |
| `integration.bookings_staging` | One incoming row | `batch_id`, `source_row_id`, raw booking fields, `source_updated_at` |
| `integration.bookings_clean` | One accepted booking | `book_ref`, booking fields, `source_updated_at`, latest batch |
| `integration.booking_exceptions` | One exception per input row | `batch_id`, `source_row_id`, disposition, primary reason, issue details |
| `integration.import_audit` | One summary per batch | Counts, processing status, reconciliation results |

Incoming identifiers should use a permissive text type. Apply strict identifier and amount requirements only after validation. Use a primary key on destination `book_ref` and a unique key on exception `(batch_id, source_row_id)`.

## 🔗 Key Relationships

| Relationship | Join key | Cardinality |
|---|---|---|
| Bookings → tickets | `book_ref` | One to many |
| Tickets → ticket flights | `ticket_no` | One to many |
| Normalized staging → reference bookings | `book_ref` | Many incoming updates to one booking |
| Staging → exceptions | `batch_id`, `source_row_id` | One to zero or one primary exception |

Aggregate ticket-flight amounts to booking level **before** joining the result to staging. Otherwise, one-to-many joins can multiply booking-level totals.

## 🛠️ Technologies Used

| Category | Tool |
|---|---|
| Database | PostgreSQL |
| Language | SQL |
| Database client | `psql`, pgAdmin, or DBeaver — record the client actually used |
| Version control and hosting | Git and GitHub |
| Optional visualization | Excel or Python — record the tool actually used |

## 📁 Project Structure

The following files are the planned repository deliverables. Add each file when its implementation is ready.

| Path | Contents |
|---|---|
| `README.md` | Project overview, execution instructions, and results |
| `sql/01_setup.sql` | Project schema, tables, and deterministic reference sample |
| `sql/02_simulate_batches.sql` | Two batches and controlled errors |
| `sql/03_normalize_and_validate.sql` | Normalization, ranking, validation, and row dispositions |
| `sql/04_load.sql` | Transactional loading, exceptions, and batch audit |
| `sql/05_reconcile.sql` | Counts, amount checks, and repeatability verification |
| `docs/data_dictionary.md` | Field definitions, types, keys, and calculation rules |
| `docs/troubleshooting.md` | Diagnostic queries, root cause, correction, and verification |
| `results/validation_report.csv` | Rejected and superseded records with reasons |
| `results/reconciliation_summary.csv` | Batch counts and verification outcomes |
| `screenshots/01_validation.png` | Validation query and output |
| `screenshots/02_deduplication.png` | Window-function logic and selected records |
| `screenshots/03_reconciliation.png` | Final checks and repeated-import results |
| `visualizations/rejected_records_by_reason.png` | Rejections grouped by primary reason |
| `.gitignore` | Excludes credentials, local configuration, and large dumps |

## ⚙️ SQL Features

| Planned feature | Application |
|---|---|
| Multi-table joins | Trace booking totals to ticket-flight amounts |
| CTEs | Separate normalization, ranking, and validation stages |
| `ROW_NUMBER()` | Select the latest update with a deterministic tie-breaker |
| `CASE` | Assign primary rejection reasons |
| Aggregation and `HAVING` | Detect mismatches and summarize exceptions |
| Constraints | Protect destination identifiers and amounts |
| `INSERT ... ON CONFLICT` | Insert new bookings or apply newer updates |
| Transactions | Commit related loading operations together |
| Anti-joins | Identify records missing from reference or destination tables |
| Reconciliation queries | Verify counts, values, and rerun behavior |

Stored procedures, triggers, loops, and performance improvements are not claimed unless separately implemented and tested.

## 🔄 Data Processing Workflow

1. Inspect source table grain, keys, and sample records.
2. Extract a deterministic sample using ordered booking identifiers.
3. Create project tables in the `integration` schema.
4. Generate two labeled import batches and introduce known errors.
5. Trim identifiers and convert blanks to NULL while preserving raw values.
6. Rank updates within each batch and booking identifier.
7. Validate the latest candidates against reference bookings and aggregated amounts.
8. Assign accepted, superseded, or rejected dispositions.
9. Load accepted candidates, retain exceptions, and update batch summaries.
10. Reconcile results and repeat the import to verify idempotency.
11. Export evidence and document a troubleshooting case.

## 🔍 Validation and Business Rules

| Condition | Handling |
|---|---|
| Blank or missing identifier | Reject as `MISSING_BOOKING_ID` |
| Unknown booking reference | Reject as `UNKNOWN_BOOKING` |
| Missing amount | Reject as `MISSING_AMOUNT` |
| Negative amount | Reject as `NEGATIVE_AMOUNT` |
| Amount differs from reference total | Reject as `AMOUNT_MISMATCH` |
| Missing update timestamp | Reject as `MISSING_UPDATE_TIMESTAMP` |
| Multiple updates within a batch | Retain the latest candidate; mark older rows `SUPERSEDED` |
| Invalid latest candidate | Reject for review; do not silently fall back to an older row |
| Incoming update older than destination | Accept if valid, but do not overwrite newer destination state |

Use `source_updated_at DESC, source_row_id DESC` as the ranking order. Validate missing identifiers and timestamps before selecting eligible update candidates. Define a fixed priority for primary error reasons so counts are mutually exclusive; additional issue flags can still be retained.

## 🔐 Transaction Control

The load script should place destination writes, exception writes, and audit updates inside one transaction. An unexpected SQL failure should roll back the related writes. Expected data validation failures are recorded as rejected rows, not treated as database execution errors.

Run scripts with `psql -v ON_ERROR_STOP=1` so processing stops when an unexpected SQL error occurs. Do not claim failed-transaction logs survive rollback unless logging is separately designed and tested.

## 📝 Exception Reporting

Each exception should record the batch, source row, raw identifier, normalized identifier, disposition, primary error code, and enough detail to explain the problem.

Use `(batch_id, source_row_id)` to prevent duplicate exception entries on reruns. Preserve staged rows rather than deleting evidence of failed imports.

## 🛠️ Troubleshooting Case

**Planned case: inflated totals caused by joining at the wrong grain.**

Demonstrate how summing booking totals after joining bookings to multiple tickets and segments can overcount amounts. Then aggregate segment amounts at booking level before comparing totals.

The write-up should include the faulty demonstration query, observed output, corrected query, and verified before-and-after values. Label the faulty query as an intentional example rather than the production workflow.

## 🧪 Test Cases

| Test | Expected outcome |
|---|---|
| Valid initial booking | Inserted successfully |
| Identifier with surrounding whitespace | Normalized and matched |
| Missing identifier | Rejected with a specific reason |
| Unknown identifier | Rejected |
| Missing or negative amount | Rejected |
| Incorrect booking total | Rejected as amount mismatch |
| Duplicate updates | One latest candidate; older rows superseded |
| Equal update timestamps | Stable selection using source-row tie-breaker |
| Invalid latest update | Rejected without fallback |
| Newer valid update | Destination updated |
| Older update than destination | Newer destination retained |
| Repeated batch | No duplicate destination or exception rows |
| Forced SQL failure during load | Related writes rolled back |
| Count reconciliation | Every input row has one disposition |

## 📊 Results and Visuals

**Results are pending execution.** Replace the placeholders with measured values and add the actual output files.

| Metric | Verified result |
|---|---|
| Batches processed | `[N]` |
| Input rows | `[N]` |
| Accepted rows | `[N]` |
| Superseded rows | `[N]` |
| Rejected rows | `[N]` |
| Inserted / updated / unchanged | `[N] / [N] / [N]` |
| New duplicate destination records after rerun | `[N]` |
| New duplicate exception records after rerun | `[N]` |

Required count relationship:

**Input rows = accepted rows + superseded rows + rejected rows.**

For accepted rows, report inserts, updates, and unchanged outcomes separately. Do not sum the same batch's counts twice when demonstrating a rerun.

### Screenshots

Capture readable SQL and its output, with a short caption explaining the result. Uncomment each image link only after adding the corresponding file.

<!-- ![Validation SQL and exception output](screenshots/01_validation.png) -->
<!-- ![Latest-update selection using ROW_NUMBER](screenshots/02_deduplication.png) -->
<!-- ![Reconciliation and repeat-import verification](screenshots/03_reconciliation.png) -->

### Data Quality Chart

Create a bar chart of rejected records grouped by primary error code. Exclude superseded rows from this chart, or present them as a clearly separate category.

<!-- ![Rejected records by primary reason](visualizations/rejected_records_by_reason.png) -->

## ▶️ How to Run

These instructions describe the planned file sequence. They become runnable once the listed SQL scripts are added.

1. Install PostgreSQL and choose a SQL client.
2. Download and unzip the **2017 English small** source database.
3. Restore the extracted SQL file using `psql`. The supplied script recreates a database named `demo`; use an isolated development environment.
4. Clone or download this repository and open its root directory.
5. Run the project scripts in order:

```bash
psql -U YOUR_USER -d demo -v ON_ERROR_STOP=1 -f sql/01_setup.sql
psql -U YOUR_USER -d demo -v ON_ERROR_STOP=1 -f sql/02_simulate_batches.sql
psql -U YOUR_USER -d demo -v ON_ERROR_STOP=1 -f sql/03_normalize_and_validate.sql
psql -U YOUR_USER -d demo -v ON_ERROR_STOP=1 -f sql/04_load.sql
psql -U YOUR_USER -d demo -v ON_ERROR_STOP=1 -f sql/05_reconcile.sql
```

6. Rerun the **load and reconciliation** scripts against the same staging rows. Do not rerun setup for this test, since resetting the destination would invalidate the rerun check.
7. Export validation and reconciliation results to CSV, then add screenshots and the chart.

Replace `YOUR_USER` with your PostgreSQL role. Never commit passwords or connection secrets.

## 🎓 Learning Outcomes

This project is intended to demonstrate relational data modeling, SQL-based transformation, multi-table reconciliation, deterministic update selection, troubleshooting, transactional loading, and clear exception reporting.

After completion, add a short reflection describing the most important bug encountered, how it was diagnosed, and which checks prevented it from reappearing.

## ✅ Completion Checklist

- [ ] Source database restored and attributed
- [ ] Sample and setup scripts completed
- [ ] Two import batches created
- [ ] Intentional errors documented
- [ ] Normalization and ranking implemented
- [ ] Validation reasons verified
- [ ] Transactional loading completed
- [ ] Reconciliation checks passed
- [ ] Repeat import produced no duplicate records
- [ ] Rollback behavior tested
- [ ] CSV results exported
- [ ] Troubleshooting case documented
- [ ] Screenshots and chart added
- [ ] Setup instructions tested
- [ ] Result placeholders replaced with measured counts

## ⚠️ Limitations

- This is a portfolio simulation; there is no live supplier API or SFTP connection.
- Reference data is demonstration data and incoming updates are simulated.
- The amount rule does not cover production repricing, refunds, or currency conversion.
- Valid identifiers are matched against a fixed reference snapshot, so genuinely new external bookings are outside scope.
- Performance optimization is not claimed without measured query-plan and timing evidence.

## 👤 Author

**[Your Name]**  
BS in Data Science | Master of Artificial Intelligence candidate

- GitHub: `[Add your profile URL]`
- LinkedIn: `[Add your profile URL]`

---

## 📌 Project Note

The project adapts airline booking data to a controlled integration scenario. The SQL files will contain the implementation; this README documents the scope, rules, execution steps, and evidence needed to verify it. Completion claims should match the committed code and outputs.

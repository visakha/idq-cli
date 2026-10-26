-- =====================================================================
-- 10_pre_etl_empty_snowflake.sql -- EXPECTED pre-ETL state, NOT
-- an ETL failure.  Read this header before triaging this case.
-- =====================================================================
-- Simulates: the daily copy has run (IDQ rows are in), but the
-- Snowflake ETL has NOT run yet -- which is exactly where this
-- project is today, because the Snowflake ETL is not ready.
-- There are no SNOWFLAKE rows at all, by design:
--   Phones, IDQ side:       1|Member v1, 2|Member v1
--   Phones, SNOWFLAKE side: (empty)
-- Expected (with 00 loaded, filter Phones):
--   verdict MISMATCH, counts 2 vs 0, oracle-only 2.
-- That MISMATCH is the compare doing its job: it is reporting
-- "the Snowflake side is empty", not "the ETL is broken".
-- Do NOT try to "fix" this case in the compare, and do NOT
-- treat it as a failing ETL test.  When the ETL is ready,
-- this scenario's SNOWFLAKE side is what the ETL must fill,
-- and this file's expected verdict flips to MATCH -- at which
-- point this file should be retired, not edited to match.
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ');

-- Deliberately NO SNOWFLAKE inserts: the ETL has not run.

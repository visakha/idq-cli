-- =====================================================================
-- 03_missing_on_snowflake.sql -- FAILURE case: ETL dropped a row.
-- =====================================================================
-- Simulates: the Snowflake ETL failed to produce one member's
-- phone (a filter too tight, a join that dropped a row, a
-- source row the ETL never saw -- the compare cannot say which,
-- only that the row is missing).
--   IDQ side:       1|Member v1, 2|Member v1, 3|Member v1
--   SNOWFLAKE side: 1|Member v1, 2|Member v1
-- Expected (with 00 loaded, filter Phones):
--   verdict MISMATCH, counts 3 vs 2, matched 2,
--   oracle-only 1 with sample ['3|Member'], snowflake-only 0.
-- The sample is the triage starting point: look up 3|Member in
-- the ETL's work tables and find where it was dropped.
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ'),
    ('3|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE');

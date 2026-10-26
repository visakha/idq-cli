-- =====================================================================
-- 02_match_demographics.sql -- SUCCESS case: Demographics matches.
-- =====================================================================
-- Simulates: a correct ETL run for the Demographics dimension
-- (C_S_TRS_PTY, the party table itself).
--   IDQ side:       1|Member v1, 2|Member v1
--   SNOWFLAKE side: 1|Member v1, 2|Member v1 (identical)
-- Expected (with 00 + 01 loaded, no dimension filter):
--   verdict MATCH across all dimensions -- every other dimension
--   is empty on both sides, and empty-vs-empty matches.
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE');

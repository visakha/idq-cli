-- =====================================================================
-- 01_match_phones.sql -- SUCCESS case: Phones dimension matches.
-- =====================================================================
-- Simulates: a correct ETL run for Phones.
--   IDQ side:      1|Member v1, 2|Member v1
--   SNOWFLAKE side: 1|Member v1, 2|Member v1 (identical)
-- Expected (with 00_common_spine.sql loaded first, filter Phones):
--   verdict MATCH, counts 2 vs 2, matched 2, oracle-only 0,
--   snowflake-only 0, version sets also match.
-- Note member 3 has no phone on either side: that is fine, a
-- member need not appear in every dimension.  Coverage for
-- Phones is therefore 2 on both sides, not 3.
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE');

-- =====================================================================
-- 04_extra_on_snowflake.sql -- FAILURE case: ETL over-produced.
-- =====================================================================
-- Simulates: the Snowflake ETL produced a phone IDQ did not
-- (a join that duplicated a row, a filter too loose, a member
-- the IDQ run excluded).  Member 4 is deliberately NOT in the
-- common valid-member spine: an extra row can also be for a
-- member outside the spine, and the dimension compare must
-- still catch it even though the spine tables themselves match.
--   IDQ side:       1|Member v1, 2|Member v1
--   SNOWFLAKE side: 1|Member v1, 2|Member v1, 4|Member v1
-- Expected (with 00 loaded, filter Phones):
--   verdict MISMATCH, counts 2 vs 3, matched 2,
--   oracle-only 0, snowflake-only 1 with sample ['4|Member'].
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE'),
    ('4|Member', 1, 'SNOWFLAKE');

-- =====================================================================
-- 05_version_mismatch.sql -- FAILURE case: PKEYs match, versions
-- do not.  This is the case the version-set compare exists for.
-- =====================================================================
-- Simulates: member 2's phone was closed and re-opened in IDQ,
-- so IDQ has TWO timeline versions (v1 and v2) for 2|Member,
-- but the Snowflake ETL only produced v1 (it missed the closed
-- version, or collapsed the timeline).
--   PKEY sets:  IDQ {1|Member, 2|Member}, SNOWFLAKE {1|Member,
--     2|Member} -- IDENTICAL.  A PKEY-only compare would call
--     this a match and be wrong.
--   (PKEY, VERSION_SEQ) sets: IDQ has (2|Member, 2) that
--     SNOWFLAKE does not.
-- Expected (with 00 loaded, filter Phones):
--   verdict MISMATCH, counts 3 vs 2, PKEY oracle-only 0,
--   snowflake-only 0, but version_oracle_only 1.
-- If this scenario ever reports MATCH, the version compare is
-- broken -- that is the regression this file guards.
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ'),
    ('2|Member', 2, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE');

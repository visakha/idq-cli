-- =====================================================================
-- 06_duplicate_keys.sql -- FAILURE case: duplicate key on one side.
-- =====================================================================
-- Simulates: the IDQ side contains the same phone key twice
-- (1|Member v1 inserted twice -- a double-load, or a join that
-- fanned out).  Set compares collapse duplicates by
-- construction, so the key sets alone look perfect:
--   key sets: IDQ {1|Member, 2|Member}, SNOWFLAKE {1|Member,
--     2|Member} -- identical, oracle-only 0, snowflake-only 0.
-- What catches it is the COUNT: IDQ has 3 rows, SNOWFLAKE 2,
-- and the compare appends a "Duplicate compare keys" message
-- whenever row count exceeds matched + oracle-only (or the
-- Snowflake equivalent).
-- Expected (with 00 loaded, filter Phones):
--   verdict MISMATCH (count_diff -1), message contains
--   "Duplicate compare keys on the IDQ side".
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE');

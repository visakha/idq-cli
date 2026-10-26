-- =====================================================================
-- 07_spine_gap.sql -- FAILURE case: spine differs, dimension does
-- not.  DO NOT load 00_common_spine.sql with this file: this
-- file loads its OWN spine, because the spine IS the scenario.
-- =====================================================================
-- Simulates: member 3 is a valid member in IDQ but the
-- Snowflake valid-member spine is missing them (the spine
-- build dropped a member, or ran on a stale source snapshot).
-- The Phones dimension itself is perfect on both sides, so a
-- dimension-only check would call this a match.
--   Valid-member spine: IDQ {1, 2, 3}, SNOWFLAKE {1, 2}
--   Party-role spine:   {1|Member, 2|Member, 3|Member} both sides
--   Phones:             {1|Member, 2|Member} both sides
-- Expected (filter Phones):
--   Phones dimension matches, but verdict MISMATCH, because
--   the valid-member spine has oracle-only 1 (INDV_ID 3).
-- =====================================================================

-- Valid-member spine, IDQ side (member 3 present).
INSERT INTO TRS_ETL_WRK.STG_TRS_VALID_MEMBERS (INDV_ID, SRC_TBL, DATA_SOURCE) VALUES
    (1, 'STG_TRS_D_DC_INDV', 'IDQ'),
    (2, 'STG_TRS_D_DC_INDV', 'IDQ'),
    (3, 'STG_TRS_D_DC_INDV', 'IDQ');

-- Valid-member spine, SNOWFLAKE side (member 3 MISSING).
INSERT INTO TRS_ETL_WRK.STG_TRS_VALID_MEMBERS (INDV_ID, SRC_TBL, DATA_SOURCE) VALUES
    (1, 'STG_TRS_D_DC_INDV', 'SNOWFLAKE'),
    (2, 'STG_TRS_D_DC_INDV', 'SNOWFLAKE');

-- Party-role spine, both sides (matching, by design).
INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ'),
    ('3|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE'),
    ('3|Member', 1, 'SNOWFLAKE');

-- Phones dimension, both sides (matching, by design).
INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE');

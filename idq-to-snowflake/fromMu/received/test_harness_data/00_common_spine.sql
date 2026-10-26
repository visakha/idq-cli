-- =====================================================================
-- 00_common_spine.sql -- SHARED SETUP, not a scenario by itself.
-- =====================================================================
-- Load this file FIRST in every scenario that is about the
-- DIMENSIONS, not about the spine.  It gives both sides the same
-- spine, so a dimension verdict cannot be polluted by a spine
-- mismatch the scenario did not intend:
--   * Valid-member spine: INDV_ID 1, 2, 3 on BOTH sides.
--   * Party-role spine:   PKEY 1|Member, 2|Member, 3|Member, v1,
--     on BOTH sides.
-- The spine-gap scenario (07) deliberately does NOT load this
-- file: it loads its own spine, because the spine IS the scenario.
--
-- DATA_SOURCE is the v5 discriminator: 'IDQ' = rows the daily
-- IDQ run produced, 'SNOWFLAKE' = rows the Snowflake ETL
-- produced.  In this harness both sides are inserted by hand,
-- because the Snowflake ETL does not exist yet (see
-- tests/sqlite_harness.py).  When it does, a scenario's
-- SNOWFLAKE inserts are what the ETL must reproduce.
-- =====================================================================

-- Valid-member spine, IDQ side.
INSERT INTO TRS_ETL_WRK.STG_TRS_VALID_MEMBERS (INDV_ID, SRC_TBL, DATA_SOURCE) VALUES
    (1, 'STG_TRS_D_DC_INDV', 'IDQ'),
    (2, 'STG_TRS_D_DC_INDV', 'IDQ'),
    (3, 'STG_TRS_D_DC_INDV', 'IDQ');

-- Valid-member spine, SNOWFLAKE side (identical here, by design).
INSERT INTO TRS_ETL_WRK.STG_TRS_VALID_MEMBERS (INDV_ID, SRC_TBL, DATA_SOURCE) VALUES
    (1, 'STG_TRS_D_DC_INDV', 'SNOWFLAKE'),
    (2, 'STG_TRS_D_DC_INDV', 'SNOWFLAKE'),
    (3, 'STG_TRS_D_DC_INDV', 'SNOWFLAKE');

-- Party-role spine, IDQ side.
INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ'),
    ('3|Member', 1, 'IDQ');

-- Party-role spine, SNOWFLAKE side (identical here, by design).
INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE'),
    ('3|Member', 1, 'SNOWFLAKE');

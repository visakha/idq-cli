-- =====================================================================
-- 08_coverage_gap.sql -- FAILURE case: dimension coverage gap.
-- =====================================================================
-- Simulates: the Names dimension covers fewer members on the
-- Snowflake side than on the IDQ side.  Coverage is the
-- distinct spine ids (first segment of PKEY_SRC_OBJECT) present
-- in a dimension table, per side -- it answers "for how many
-- members did this dimension produce anything at all?"
--   Names, IDQ side:       1|Member, 2|Member, 3|Member
--   Names, SNOWFLAKE side: 1|Member, 2|Member
-- Expected (with 00 loaded, filter Names):
--   Names dimension MISMATCH (oracle-only 1), and the spine
--   section's coverage entry for Names reads oracle 3,
--   snowflake 2, diff -1.  Note: coverage diffs are REPORTED,
--   they do not by themselves drive the verdict -- the
--   dimension's own key mismatch does that here.  Coverage is
--   the triage view: it tells you the gap is member-wide
--   (a whole member missing from the dimension) rather than
--   row-wide.
-- =====================================================================

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_NM (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'IDQ'),
    ('2|Member', 1, 'IDQ'),
    ('3|Member', 1, 'IDQ');

INSERT INTO TRS_ETL_WRK.C_S_TRS_PTY_NM (PKEY_SRC_OBJECT, VERSION_SEQ, DATA_SOURCE) VALUES
    ('1|Member', 1, 'SNOWFLAKE'),
    ('2|Member', 1, 'SNOWFLAKE');

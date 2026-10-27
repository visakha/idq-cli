-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Stg_TOA, workflow wf_TRS_Stage_Load_TOA (its
-- only mapping; the daily parent workflow runs it after
-- wf_TRS_Stage_Load_1_Ongoing).
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-51  The MDM TOA lookup stays in sync with TIERS: the TIERS
--          type-of-assistance catalogue (every row, history and expired
--          codes included) is staged into C_S_LU_TOA, with the TOA code
--          and the program code cross-referenced against
--          LOOKUP_CODE_VALUE.
--   BR-01  Insert-only staging load (see Parity notes: no truncate here).
--   Not a member load: member TOA segments are
--   m_Tgt_C_S_TRS_Pty_Rle_TOA (BR-27), whose TOA_FK holds the same
--   master code -- translated there by source value, here by label.
--   Key = <TOA master code> (the program is not part of it).
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one CTE chain (lkp_toa / lkp_pgm /
--   keyed -> outer SELECT with the existing-key guard, the null-key
--   filter and the survivor QUALIFY), one transaction, one log line.
--   This rewrite: the SAME business SQL, split at the logical
--   boundaries into named work tables, one step at a time.  No business
--   expression was changed; each step's SELECT is the original logic,
--   with its FROM clause pointed at the previous work table instead of
--   the previous CTE.  The final publish is the original INSERT,
--   written as a single INSERT inside ONE transaction (it was the only
--   INSERT in the original, so there is nothing to split into INSERT
--   ALL branches).
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_LUTOA_S10_KEYED  catalogue rows with TOA master code
--                                     (by label) and program master code
--   Step 20  WRK_TRS_LUTOA_S20_FINAL  null keys dropped, keys not already
--                                     in the target, one survivor per key
--   Step 30  PUBLISH                  C_S_LU_TOA, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_LUTOA_S10_KEYED, WRK_TRS_LUTOA_S20_FINAL.  They live in the
--   same schema as the target (unqualified names, as in the original
--   code), are prefixed WRK_TRS_, and are registered in
--   JOB_CONTROL_ETL at creation.  They survive a
--   session crash (TRANSIENT, not TEMP), unlike a pure session TEMP
--   table, which would vanish with the session.  A Snowflake CURSOR was NOT used:
--   cursors process row by row, and every step here is set-based by
--   design -- the work table IS the result set, held as a table instead
--   of in memory, so it can be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of the target.  IDQ truncates C_S_LU_TOA; the Snowflake
--     version instead skips keys already present (VERSION_SEQ = 1) and
--     skips null keys.  A re-run therefore inserts nothing twice, but
--     it also does not remove rows that IDQ would have truncated away
--     -- see the User Guide, "Parity gaps".
--   * No validation in IDQ for this mapping: no router, no filter, no
--     exception table, and no begin-after-end date check (unlike the
--     member TOA mapping, BR-27).  The only checks in the original are
--     the target's NOT NULL / unique constraints, ported here as the
--     step-20 null-key filter and existing-key guard.  A TOA code with
--     no TOA master label leaves PKEY_SRC_OBJECT NULL; IDQ gets the row
--     rejected by Oracle and logs nothing, and this version drops it
--     silently in step 20 (Snowflake would fail the whole statement on
--     the NOT NULL column if it were published).
--   * Survivor rule, preserved and flagged: IDQ keeps the first row read
--     and its read has no ORDER BY, so the survivor of a code listed
--     under several programs or history rows is undefined there; this
--     version keeps the latest (UPDATE_DT, then UNIQUE_TRANS_ID,
--     descending), as the original Snowflake code did.  Confirm with
--     the business if that survivor rule is the intended one.
--   * Precision as IDQ: the key passes a string(10) port (cut to 10),
--     MBR_PRG_CD a string(9) port, TOA_LBL cut to 100, TOA_DESC to 250
--     and UPDATED_BY to 50.
--   * VERSION_SEQ = 1 (literal '1'); PERIOD_START_DATE, PERIOD_END_DATE
--     and PERIOD_REFERENCE_TIME are NULL (not linked); TIMELINE_ACTION
--     keeps the column default 0.  CREATOR = 'admin', HUB_STATE_IND = 1,
--     LAST_UPDATE_DATE = run start, CREATE_DATE = source CREATE_DT.
--   * ROWID_OBJECT (computed as the key without leading zeros in IDQ,
--     but not linked) and DELETED_* are NULL, as in the original.
--   * JUDGEMENT CALL, step 20: the original outer SELECT used QUALIFY
--     with ROW_NUMBER to pick the survivor.  A CREATE TABLE AS with a
--     bare QUALIFY is avoided here; step 20 instead computes the same
--     ROW_NUMBER as a column in a subquery and filters rn = 1, dropping
--     the helper column with SELECT * EXCLUDE (rn).  Same rows, same
--     order, same survivor -- only the spelling differs, so the step
--     compiles the same way in a CTAS as it would in an INSERT.
--
-- SIGNATURE
--   The original procedure took no parameters, so there is nothing to
--   preserve in order.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA (
    P_JOB_RUN_ID  VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_TOA';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Stg_TOA';
    l_run_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    l_job_run_id VARCHAR;
    l_rows       NUMBER DEFAULT 0;
    l_pub_rows   NUMBER DEFAULT 0;
    l_summary    VARCHAR DEFAULT '';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(:P_JOB_RUN_ID, ''),
            'TRS_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_TRS_LUTOA_S10_KEYED;
    DROP TABLE IF EXISTS WRK_TRS_LUTOA_S20_FINAL;

    -- ---- Step 10: CATALOGUE ROWS, KEYED (BR-51) --------------------------
    -- Purpose: every catalogue row from STG_TRS_D_LU_TOA with its TOA
    -- master code (LOOKUP_CODE_VALUE, CODE_TYPE = 'TOA', matched on
    -- master label = TOA_CODE, first code per label, no SRC_SYS
    -- filter) cut to the string(10) key port, and its program master
    -- code (CODE_TYPE = 'MEMBER_PRG', matched on label = PROGRAM_CODE)
    -- cut to string(9), NULL when not configured.  Rows whose TOA code
    -- has no master label get a NULL key here; step 20 drops them.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_LUTOA_S10_KEYED AS
    WITH
    lkp_toa AS (
        SELECT l.MSTR_REF_LABEL, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
         WHERE l.CODE_TYPE = 'TOA'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY l.MSTR_REF_LABEL ORDER BY l.MSTR_REF_CODE) = 1
    ),
    lkp_pgm AS (
        SELECT l.MSTR_REF_LABEL, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
         WHERE l.CODE_TYPE = 'MEMBER_PRG'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY l.MSTR_REF_LABEL ORDER BY l.MSTR_REF_CODE) = 1
    )
    SELECT s.*,
           SUBSTR(lt.MSTR_REF_CODE, 1, 10) AS pkey_src_object,
           lt.MSTR_REF_LABEL AS toa_lbl,
           SUBSTR(lp.MSTR_REF_CODE, 1, 9) AS mbr_prg_cd
      FROM STG_TRS_D_LU_TOA s
      LEFT JOIN lkp_toa lt ON lt.MSTR_REF_LABEL = s.TOA_CODE
      LEFT JOIN lkp_pgm lp ON lp.MSTR_REF_LABEL = s.PROGRAM_CODE;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_LUTOA_S10_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'CATALOGUE_KEYED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_LUTOA_S10_KEYED', 'CREATED',
        'Catalogue rows with the TOA master code (by label) and program master code resolved. '
        || 'Read by the survivor step (BR-51).',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 CATALOGUE_KEYED', :l_rows) || CHR(10);

    -- ---- Step 20: SURVIVOR PER KEY (BR-51) --------------------------------
    -- Purpose: drop null keys (Oracle would reject them, and this
    -- version logs nothing for them, as IDQ did), drop keys already in
    -- C_S_LU_TOA (VERSION_SEQ = 1), and keep one survivor per key:
    -- latest UPDATE_DT, then UNIQUE_TRANS_ID, descending.  See the
    -- header judgement call: the original QUALIFY is spelled here as
    -- a ROW_NUMBER column filtered to rn = 1, so the CTAS compiles
    -- identically to the INSERT form.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_LUTOA_S20_FINAL AS
    SELECT * EXCLUDE (rn)
      FROM (
        SELECT k.*,
               ROW_NUMBER() OVER (PARTITION BY k.pkey_src_object
                                      ORDER BY k.UPDATE_DT DESC NULLS LAST, k.UNIQUE_TRANS_ID DESC NULLS LAST) AS rn
          FROM WRK_TRS_LUTOA_S10_KEYED k
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_LU_TOA WHERE VERSION_SEQ = 1) xa
                 ON xa.PKEY_SRC_OBJECT = k.pkey_src_object
         WHERE k.pkey_src_object IS NOT NULL
           AND xa.PKEY_SRC_OBJECT IS NULL
      )
     WHERE rn = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_LUTOA_S20_FINAL;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'SURVIVOR_PER_KEY', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_LUTOA_S20_FINAL', 'CREATED',
        'One survivor per TOA master code (latest UPDATE_DT, then UNIQUE_TRANS_ID); '
        || 'null keys and keys already in the target dropped. Read by the publish step (BR-51).',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 SURVIVOR', :l_rows) || CHR(10);

    -- ---- Step 30: PUBLISH -- one transaction -----------------------------
    -- This is the ONLY step that writes to a final target.  The INSERT
    -- below is the original INSERT verbatim, with its FROM pointed at
    -- step 20.  Step 20 already removed null and already-present keys,
    -- so this INSERT loads exactly the survivor rows.
    BEGIN TRANSACTION;
    INSERT INTO C_S_LU_TOA
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            HUB_STATE_IND, TOA_CD, TOA_LBL, TOA_DESC, MBR_PRG_CD, EFF_STRT_DT, EFF_END_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, NULL, NULL,
           1, NULL, :l_run_ts, SUBSTR(UPDATE_USER_ID, 1, 50), CREATE_DT, 'admin', SUBSTR(pkey_src_object, 1, 30),
           1, pkey_src_object, SUBSTR(toa_lbl, 1, 100), SUBSTR(TOA_DESC, 1, 250), mbr_prg_cd, EFF_BEGIN_DT, EFF_END_DT
      FROM WRK_TRS_LUTOA_S20_FINAL;
    l_pub_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'PUBLISH', 'COMPLETED', 'C_S_LU_TOA', :l_pub_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: TOA catalogue survivors. '
        || 'Count shown is rows inserted into C_S_LU_TOA.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 PUBLISH (C_S_LU_TOA)', :l_pub_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Stg_TOA completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_TRS_Stg_TOA failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;

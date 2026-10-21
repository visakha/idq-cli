--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Managed attributes ("switches") of the valid TIERS members into C_S_TRS_PTY_MNG_ATTR (insert only, never truncated):
--   Read_Stg_TRS_D_DC_Indv (custom SQL: latest DC_INDV / MCI row per individual joined to STG_TRS_VALID_MEMBERS)
--   -> exp_Attr_Type + nrm_Attribute_Types: one row per attribute (five UNION ALL branches here)
--        File_Clearance_SW = FILE_CLEARANCE_SW, SSA_Validation_SW = SSA_VALIDATION_SW, TW_Convert_Ind,
--        LTC_Convert_Ind, Source_Table = SRC_TBL
--   -> fltr_Null_Values: value present and not blank
--   -> exp_Pkey_Src_Object: key = PTY_PK || '|' || attribute type
--   -> srtr_Pkey (distinct) -> exp_Version_Seq_No -> target
-- Runs BEFORE m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing, which appends to the same table.
--
-- VALIDATION: none (no rule runs here).
-- BAD DATA: NULL or blank switch values are dropped (fltr_Null_Values, IDQ blank test). Unfed ports written as NULL:
--   ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND. C_S_TRS_PTY_MNG_ATTR is unique on
--   (PKEY_SRC_OBJECT, VERSION_SEQ), which Snowflake does not enforce: one row per key, keys already there skipped.
-- TIMELINE: exp_Version_Seq_No.VERSION_SEQ_NUM is hard-coded to 1 (the running version counter is commented out in
--   IDQ); PERIOD_START_DATE = EFF_BEGIN_DT; PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION are linked to
--   unfed ports (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Sw';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP() / SESSSTARTTIME
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_MNG_ATTR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO C_S_TRS_PTY_MNG_ATTR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            MNG_ATTR_TP, MNG_ATTR_VAL, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE,
            SRC_ROWID, CREATOR, LAST_UPDATE_DATE, SRC_LAST_UPD_DT, PTY_FK, HUB_STATE_IND)
    WITH
    -- Read_Stg_TRS_D_DC_Indv (custom SQL, query mode SEMI)
    daily_indv AS (
        SELECT dc.indv_id AS INDV_ID, dc.FILE_CLEARANCE_SW, dc.SSA_VALIDATION_SW, dc.CREATE_DT AS EFF_BEGIN_DT,
               NULL AS TW_CONVERT_IND, NULL AS LTC_CONVERT_IND, TO_VARCHAR(dc.INDV_ID) || '|DC_INDV' AS PTY_PK,
               dc.create_dt AS CREATE_DT, 'DC_INDV' AS SRC_TBL,
               ROW_NUMBER() OVER (PARTITION BY dc.INDV_ID ORDER BY dc.CREATE_DT DESC) AS KEY_RN
          FROM STG_TRS_D_DC_INDV dc
        UNION
        SELECT cv.indv_id, NULL, NULL, cv.create_dt, cv.TW_CONVERT_IND, cv.LTC_CONVERT_IND, TO_VARCHAR(cv.INDV_ID),
               cv.create_dt, 'MCI', ROW_NUMBER() OVER (PARTITION BY cv.INDV_ID ORDER BY cv.CREATE_DT DESC)
          FROM STG_TRS_D_CV_DC_MCI_INDV cv
    ),
    src AS (
        SELECT dly.INDV_ID, dly.FILE_CLEARANCE_SW, dly.SSA_VALIDATION_SW, dly.EFF_BEGIN_DT, dly.TW_CONVERT_IND,
               dly.LTC_CONVERT_IND, dly.PTY_PK, dly.CREATE_DT, dly.SRC_TBL
          FROM daily_indv dly
          JOIN STG_TRS_VALID_MEMBERS IM ON dly.INDV_ID = IM.INDV_ID AND dly.SRC_TBL = IM.SRC_TBL
         WHERE dly.KEY_RN = 1
    ),
    -- exp_Attr_Type + nrm_Attribute_Types (5 occurrences)
    normalized AS (
        SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT AS SRC_LAST_UPD_DT, 'File_Clearance_SW' AS ATTR_TYPE,
               TO_VARCHAR(s.FILE_CLEARANCE_SW) AS ATTR_VALUE FROM src s
        UNION ALL
        SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'SSA_Validation_SW', TO_VARCHAR(s.SSA_VALIDATION_SW) FROM src s
        UNION ALL
        SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'TW_Convert_Ind', TO_VARCHAR(s.TW_CONVERT_IND) FROM src s
        UNION ALL
        SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'LTC_Convert_Ind', TO_VARCHAR(s.LTC_CONVERT_IND) FROM src s
        UNION ALL
        SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'Source_Table', TO_VARCHAR(s.SRC_TBL) FROM src s
    ),
    -- fltr_Null_Values + exp_Pkey_Src_Object + srtr_Pkey (distinct)
    attrs AS (
        SELECT DISTINCT NVL(a.PTY_PK, '') || '|' || a.ATTR_TYPE AS pkey_src_object, a.EFF_BEGIN_DT, a.PTY_PK,
               a.ATTR_TYPE, a.ATTR_VALUE, a.SRC_LAST_UPD_DT
          FROM normalized a
         WHERE NOT fn_snow_helper03_common(a.ATTR_VALUE)                 /* BAD DATA: NULL / blank values dropped */
    )
    -- exp_Version_Seq_No
    SELECT t.pkey_src_object, NULL, NULL, NULL, NULL, t.EFF_BEGIN_DT /* TIMELINE */, NULL /* TIMELINE: unfed */,
           t.ATTR_TYPE, t.ATTR_VALUE, 1 /* TIMELINE: VERSION_SEQ_NUM hard-coded */, NULL /* TIMELINE: unfed */,
           NULL /* TIMELINE: unfed */, NULL, :l_run_ts, t.pkey_src_object, NULL, :l_run_ts, t.SRC_LAST_UPD_DT,
           t.PTY_PK, NULL
      FROM attrs t
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_MNG_ATTR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = t.pkey_src_object
     /* BAD DATA: unique key not yet in the table, first row per key in this run */
     WHERE xa.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.pkey_src_object ORDER BY t.EFF_BEGIN_DT DESC NULLS LAST) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert C_S_TRS_PTY_MNG_ATTR', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

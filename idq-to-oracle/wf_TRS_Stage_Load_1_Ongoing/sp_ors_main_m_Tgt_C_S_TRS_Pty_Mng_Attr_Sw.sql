--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Managed attributes ("switches") of the valid TIERS members into C_S_TRS_PTY_MNG_ATTR (insert only, never truncated):
--   Read_Stg_TRS_D_DC_Indv (custom SQL: latest DC_INDV / MCI row per individual joined to STG_TRS_VALID_MEMBERS)
--   -> exp_Attr_Type + nrm_Attribute_Types: one row per attribute (UNPIVOT here)
--        File_Clearance_SW = FILE_CLEARANCE_SW, SSA_Validation_SW = SSA_VALIDATION_SW, TW_Convert_Ind,
--        LTC_Convert_Ind, Source_Table = SRC_TBL
--   -> fltr_Null_Values: value present and not blank
--   -> exp_Pkey_Src_Object: key = PTY_PK || '|' || attribute type
--   -> srtr_Pkey (distinct) -> exp_Version_Seq_No -> target
--
-- TIMELINE: exp_Version_Seq_No.VERSION_SEQ_NUM is hard-coded to 1 (the running version counter is commented out in
-- IDQ); PERIOD_START_DATE = EFF_BEGIN_DT; PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION are linked to
-- unfed ports (NULL).
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Sw';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP() / SESSSTARTTIME
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_MNG_ATTR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO C_S_TRS_PTY_MNG_ATTR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            MNG_ATTR_TP, MNG_ATTR_VAL, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE,
            SRC_ROWID, CREATOR, LAST_UPDATE_DATE, SRC_LAST_UPD_DT, PTY_FK, HUB_STATE_IND)
    WITH
    -- Read_Stg_TRS_D_DC_Indv (custom SQL, query mode SEMI)
    daily_indv AS (
        SELECT dc.indv_id AS INDV_ID, dc.FILE_CLEARANCE_SW, dc.SSA_VALIDATION_SW, dc.CREATE_DT AS EFF_BEGIN_DT,
               NULL AS TW_CONVERT_IND, NULL AS LTC_CONVERT_IND, TO_CHAR(dc.INDV_ID) || '|DC_INDV' AS PTY_PK,
               create_dt, 'DC_INDV' SRC_TBL,
               ROW_NUMBER() OVER (PARTITION BY INDV_ID ORDER BY CREATE_DT DESC) KEY_RN
          FROM STG_TRS_D_DC_INDV dc
        UNION
        SELECT indv_id AS INDV_ID, NULL AS FILE_CLEARANCE_SW, NULL AS SSA_VALIDATION_SW, create_dt AS EFF_BEGIN_DT,
               TW_CONVERT_IND, LTC_CONVERT_IND, TO_CHAR(INDV_ID) AS PTY_PK, create_dt, 'MCI' SRC_TBL,
               ROW_NUMBER() OVER (PARTITION BY INDV_ID ORDER BY CREATE_DT DESC) KEY_RN
          FROM STG_TRS_D_CV_DC_MCI_INDV cv
    ),
    src AS (
        SELECT dly.INDV_ID, dly.FILE_CLEARANCE_SW, dly.SSA_VALIDATION_SW, dly.EFF_BEGIN_DT, dly.TW_CONVERT_IND,
               dly.LTC_CONVERT_IND, dly.PTY_PK, dly.CREATE_DT, dly.SRC_TBL
          FROM daily_indv dly
          JOIN STG_TRS_VALID_MEMBERS IM ON dly.INDV_ID = IM.INDV_ID AND dly.SRC_TBL = IM.SRC_TBL
         WHERE key_rn = 1
    ),
    -- exp_Attr_Type + nrm_Attribute_Types (5 occurrences)
    normalized AS (
        SELECT n.INDV_ID, n.PTY_PK, n.EFF_BEGIN_DT, n.CREATE_DT AS SRC_LAST_UPD_DT, n.ATTR_TYPE, n.ATTR_VALUE
          FROM (SELECT s.INDV_ID, s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT,
                       CAST(s.FILE_CLEARANCE_SW AS VARCHAR2(30)) AS v1, CAST(s.SSA_VALIDATION_SW AS VARCHAR2(30)) AS v2,
                       CAST(s.TW_CONVERT_IND AS VARCHAR2(30))    AS v3, CAST(s.LTC_CONVERT_IND AS VARCHAR2(30))   AS v4,
                       CAST(s.SRC_TBL AS VARCHAR2(30))           AS v5
                  FROM src s)
       UNPIVOT INCLUDE NULLS (ATTR_VALUE FOR ATTR_TYPE IN (v1 AS 'File_Clearance_SW', v2 AS 'SSA_Validation_SW',
                                                           v3 AS 'TW_Convert_Ind', v4 AS 'LTC_Convert_Ind',
                                                           v5 AS 'Source_Table')) n
    ),
    -- fltr_Null_Values + exp_Pkey_Src_Object + srtr_Pkey (distinct)
    attrs AS (
        SELECT DISTINCT a.PTY_PK || '|' || a.ATTR_TYPE AS pkey_src_object, a.EFF_BEGIN_DT, a.PTY_PK, a.ATTR_TYPE,
               a.ATTR_VALUE, a.SRC_LAST_UPD_DT
          FROM normalized a
         WHERE a.ATTR_VALUE IS NOT NULL AND RTRIM(a.ATTR_VALUE) IS NOT NULL
    )
    -- exp_Version_Seq_No
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, EFF_BEGIN_DT /* TIMELINE */, NULL /* TIMELINE: unfed */,
           ATTR_TYPE, ATTR_VALUE, 1 /* TIMELINE: VERSION_SEQ_NUM hard-coded */, NULL /* TIMELINE: unfed */,
           NULL /* TIMELINE: unfed */, NULL, l_run_ts, pkey_src_object, NULL, l_run_ts, SRC_LAST_UPD_DT, PTY_PK, NULL
      FROM attrs;
    sp_ors_helper02_common(c_mapping, 'insert C_S_TRS_PTY_MNG_ATTR', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw;
/

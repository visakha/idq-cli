--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Member-to-member relationships (STG_TRS_D_DC_RELATIONSHIPS; both sides valid members, one source key per
-- individual, MCI preferred) into C_S_TRS_PTY_RLE_REL (insert only, never truncated):
--   -> Lookup_V_LOOKUP_CODE_VALUE (code type PTY_REL, 'TRS') + exp_Build_FK -> rtr_AltId_Exp
--        Invalid_Main_Alt_Id (no main party key)  -> EXC_STG_BAD_REC_MEMB ('Invalid_Member')
--        Invalid_Ref_Alt_Id  (no related key)     -> EXC_STG_BAD_REC_MEMB ('Invalid_Ref_Member')
--        Invalid_Lookup      (type untranslated)  -> EXC_STG_BAD_REC_MEMB ('Invalid_Rel_Type', looked-up code)
--        Period_Start_Dt_GT_Period_End_Date       -> EXC_STG_BAD_REC_MEMB ('Period_Start_Date_>_Period_End_Date')
--        Default (none of the above)
--          -> MPLT_Member_PTY_RLE_REL_Consolidation (inlined, set level): type present, distinct on
--             (key, end date, start date), one row per (key, end, start), running VERSION_SEQ per key
--          -> Exp_safe_C_S_TRS_PTY_RLE_REL
--          -> mplt_Pty_Rle_Rel_Timeline_Validation (inlined, TIMELINE, see below) -> C_S_TRS_PTY_RLE_REL
--
-- TIMELINE (stale MDM timeline, ported here as IDQ does it; this is the one mapping family where the timeline
-- changes the ROW SET, not only column values):
--   mplt_Pty_Rle_Rel_Timeline_Validation
--   1. mplt_DST_Correction (fn_dq_dst_correction): the end date moves forward one hour when start = end, or when
--      end + 2 hours is a daylight-saving change (REF_DYLGHT_SVNGS_TM).
--   2. rtr_Active_Records + union_All_Records: open rows (no end date) pass once; every END-DATED row is emitted
--      TWICE - the closed version (End_Dated_Records) and an open copy with the end date removed
--      (New_Active_Records).
--   3. SRT_PKEY_FOR_RANK + exp_RANK: VERSION_SEQ is re-numbered per key in (start date ascending, end date
--      descending, NULL high) order.
--   4. exp_Stage_Output_Attributes: PERIOD_REFERENCE_TIME = end date and TIMELINE_ACTION = 2 when end dated;
--      LAST_UPDATE_DATE = run start; HUB_STATE_IND forced to 1 on the open row with VERSION_SEQ 1 when it has none
--      (the input HUB_STATE_IND is not fed, so all other rows get NULL).
--   Exp_safe_C_S_TRS_PTY_RLE_REL also computes PERIOD_REFERENCE_TIME / TIMELINE_ACTION, but the mapplet outputs
--   replace them.
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem (
    p_indv_id_alt_id_tp  IN VARCHAR2 DEFAULT '007'   -- $INDV_ID_ALT_ID_TP (substituted into the source SQL)
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / systimestamp()
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_REL. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- rtr_AltId_Exp.Invalid_Main_Alt_Id
        WHEN row_kind = 'ROUTER' AND pty_rle_fk_1 IS NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, PERIOD_START_DATE,
                  PERIOD_END_DATE, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
            VALUES ('TRS', l_run_ts, c_mapping, INDV_ID, REF_INDV_ID, rel_type_code, EFF_BEGIN_DT, EFF_END_DT,
                    fn_ors_helper04_common('Invalid_Member'), fn_ors_helper05_common('Invalid_Member'),
                    'Invalid_Member')
        -- rtr_AltId_Exp.Invalid_Ref_Alt_Id
        WHEN row_kind = 'ROUTER' AND pty_rle_fk_2 IS NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, PERIOD_START_DATE,
                  PERIOD_END_DATE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES ('TRS', l_run_ts, c_mapping, INDV_ID, REF_INDV_ID, rel_type_code, EFF_BEGIN_DT, EFF_END_DT,
                    'Invalid_Ref_Member', fn_ors_helper04_common('Invalid_Ref_Member'),
                    fn_ors_helper05_common('Invalid_Ref_Member'))
        -- rtr_AltId_Exp.Invalid_Lookup
        WHEN row_kind = 'ROUTER' AND rel_type_code IS NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, SRC_SYS_ID_3, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
            VALUES ('TRS', INDV_ID, REF_INDV_ID, c_mapping, l_run_ts, RELATIONSHIP_TYPE_CD, RELATIONSHIP_TYPE_CD,
                    'Relationship Type', EFF_BEGIN_DT, EFF_END_DT, fn_ors_helper05_common('Invalid_Rel_Type'),
                    fn_ors_helper04_common('Invalid_Rel_Type'), fn_ors_helper08_common('Invalid_Rel_Type'))
        -- rtr_AltId_Exp.Period_Start_Dt_GT_Period_End_Date
        WHEN row_kind = 'ROUTER' AND EFF_BEGIN_DT > EFF_END_DT THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, SRC_SYS_ID_3, ATTRIBUTE_NAME,
                  PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES ('TRS', INDV_ID, REF_INDV_ID, c_mapping, l_run_ts, RELATIONSHIP_TYPE_CD, 'Effective Date',
                    EFF_BEGIN_DT, EFF_END_DT, 'Period_Start_Date_>_Period_End_Date',
                    fn_ors_helper04_common('Period_Start_Date_>_Period_End_Date'),
                    fn_ors_helper05_common('Period_Start_Date_>_Period_End_Date'))
        -- Default -> consolidation -> timeline -> Write_C_S_TRS_PTY_RLE_REL
        WHEN row_kind = 'TIMELINE' THEN
            INTO C_S_TRS_PTY_RLE_REL
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY,
                  CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE,
                  HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, EFF_BEGIN_DT /* TIMELINE */,
                    tl_period_end_date /* TIMELINE: DST-corrected, NULL on the open copy */,
                    tl_version_seq /* TIMELINE: re-ranked */,
                    tl_period_end_date /* TIMELINE: PERIOD_REFERENCE_TIME = end date */,
                    CASE WHEN tl_period_end_date IS NOT NULL THEN 2 END /* TIMELINE_ACTION */,
                    l_run_ts, NULL, CREATE_DT, NULL, pkey_src_object,
                    CASE WHEN tl_period_end_date IS NULL AND tl_version_seq = 1 THEN 1 END /* TIMELINE: forced hub state */,
                    pty_rle_fk_1, pty_rle_fk_2, 'Member Relationship', 'Member', rel_type_code, src_last_upd_dt)
    WITH
    -- Read_STG_TRS_D_DC_RELATIONSHIPS (custom SQL, query mode SEMI)
    min_pk AS (
        SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
    ),
    src AS (
        SELECT rel.indv_id AS INDV_ID, ref_indv_id AS REF_INDV_ID, eff_begin_dt AS EFF_BEGIN_DT,
               eff_end_dt AS EFF_END_DT, hist_nav_ind AS HIST_NAV_IND, relationship_type_cd AS RELATIONSHIP_TYPE_CD,
               pk1.pty_pk AS PTY_PKEY, pk2.pty_pk AS REF_PTY_PKEY, p_indv_id_alt_id_tp AS PTY_ALT_ID_TP,
               create_dt AS CREATE_DT, update_dt AS UPDATE_DT
          FROM stg_trs_d_dc_relationships rel
          JOIN min_pk pk1 ON rel.indv_id = pk1.indv_id
          JOIN min_pk pk2 ON rel.ref_indv_id = pk2.indv_id
    ),
    -- Lookup_V_LOOKUP_CODE_VALUE + exp_Build_FK
    keyed AS (
        SELECT s.*,
               fn_ors_helper03_common('PTY_REL', 'TRS', s.RELATIONSHIP_TYPE_CD)                       AS rel_type_code,
               CASE WHEN s.PTY_PKEY IS NULL THEN NULL ELSE LTRIM(RTRIM(s.PTY_PKEY)) || '|Member' END  AS pty_rle_fk_1,
               CASE WHEN s.REF_PTY_PKEY IS NULL THEN NULL
                    ELSE LTRIM(RTRIM(s.REF_PTY_PKEY)) || '|Member' END                                AS pty_rle_fk_2
          FROM src s
    ),
    routed AS (
        SELECT k.*,
               k.pty_rle_fk_1 || '|' || k.pty_rle_fk_2 || '|' || k.rel_type_code                    AS pkey_src_object,
               CASE WHEN k.pty_rle_fk_1 IS NULL OR k.pty_rle_fk_2 IS NULL OR k.rel_type_code IS NULL
                         OR k.EFF_BEGIN_DT > k.EFF_END_DT THEN 0 ELSE 1 END                          AS is_default
          FROM keyed k
    ),
    -- MPLT_Member_PTY_RLE_REL_Consolidation: Filter (type present), Sorter (distinct), Aggregator (one row per
    -- key + end + start; other ports from the last row)
    consolidated AS (
        SELECT c.*
          FROM (SELECT r.*,
                       ROW_NUMBER() OVER (PARTITION BY r.pkey_src_object, r.EFF_END_DT, r.EFF_BEGIN_DT
                                          ORDER BY r.CREATE_DT DESC NULLS FIRST, r.UPDATE_DT DESC NULLS FIRST) AS rn
                  FROM routed r
                 WHERE r.is_default = 1 AND r.rel_type_code IS NOT NULL) c
         WHERE c.rn = 1
    ),
    -- Exp_safe_C_S_TRS_PTY_RLE_REL (SRC_LAST_UPDATE_DATE = later of create / update) + mplt_DST_Correction
    prepared AS (
        SELECT c.*,
               CASE WHEN c.CREATE_DT IS NOT NULL AND c.UPDATE_DT IS NOT NULL
                    THEN CASE WHEN c.CREATE_DT > c.UPDATE_DT THEN c.CREATE_DT ELSE c.UPDATE_DT END
                    ELSE NVL(c.CREATE_DT, c.UPDATE_DT) END                                          AS src_last_upd_dt,
               fn_dq_dst_correction(c.EFF_BEGIN_DT, c.EFF_END_DT)                                   AS dst_end_date
          FROM consolidated c
    ),
    -- rtr_Active_Records + union_All_Records (TIMELINE)
    versions AS (
        SELECT p.*, p.dst_end_date AS tl_period_end_date FROM prepared p                            -- Active_Records /
                                                                                                    -- End_Dated_Records
        UNION ALL
        SELECT p.*, CAST(NULL AS DATE) FROM prepared p WHERE p.dst_end_date IS NOT NULL             -- New_Active_Records
    ),
    -- SRT_PKEY_FOR_RANK + exp_RANK (TIMELINE)
    ranked AS (
        SELECT v.*,
               ROW_NUMBER() OVER (PARTITION BY v.pkey_src_object
                                  ORDER BY v.EFF_BEGIN_DT ASC NULLS LAST, v.tl_period_end_date DESC NULLS FIRST) AS tl_version_seq
          FROM versions v
    )
    SELECT 'ROUTER' AS row_kind, r.INDV_ID, r.REF_INDV_ID, r.EFF_BEGIN_DT, r.EFF_END_DT, r.RELATIONSHIP_TYPE_CD,
           r.CREATE_DT, r.rel_type_code, r.pty_rle_fk_1, r.pty_rle_fk_2, r.pkey_src_object,
           CAST(NULL AS DATE) AS src_last_upd_dt, CAST(NULL AS DATE) AS tl_period_end_date,
           CAST(NULL AS NUMBER) AS tl_version_seq
      FROM routed r
    UNION ALL
    SELECT 'TIMELINE', k.INDV_ID, k.REF_INDV_ID, k.EFF_BEGIN_DT, k.EFF_END_DT, k.RELATIONSHIP_TYPE_CD, k.CREATE_DT,
           k.rel_type_code, k.pty_rle_fk_1, k.pty_rle_fk_2, k.pkey_src_object, k.src_last_upd_dt,
           k.tl_period_end_date, k.tl_version_seq
      FROM ranked k;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TRS_PTY_RLE_REL, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem;
/

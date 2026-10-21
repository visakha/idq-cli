--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem (workflow
-- wf_TRS_Stage_Load_1_Ongoing).
--
-- Member-to-member relationships (STG_TRS_D_DC_RELATIONSHIPS; both sides valid members, one source key per
-- individual) into C_S_TRS_PTY_RLE_REL (insert only, never truncated):
--   -> Lookup_V_LOOKUP_CODE_VALUE (code type PTY_REL, 'TRS') + exp_Build_FK -> rtr_AltId_Exp
--        Invalid_Main_Alt_Id (no main party key)  -> EXC_STG_BAD_REC_MEMB ('Invalid_Member')
--        Invalid_Ref_Alt_Id  (no related key)     -> EXC_STG_BAD_REC_MEMB ('Invalid_Ref_Member')
--        Invalid_Lookup      (type untranslated)  -> EXC_STG_BAD_REC_MEMB ('Invalid_Rel_Type', looked-up code)
--        Period_Start_Dt_GT_Period_End_Date       -> EXC_STG_BAD_REC_MEMB ('Period_Start_Date_>_Period_End_Date')
--        Default (none of the above)
--          -> MPLT_Member_PTY_RLE_REL_Consolidation (inlined, set level): type present, distinct on
--             (key, end date, start date), one row per (key, end, start)
--          -> Exp_safe_C_S_TRS_PTY_RLE_REL
--          -> mplt_Pty_Rle_Rel_Timeline_Validation (inlined, TIMELINE, see below) -> C_S_TRS_PTY_RLE_REL
--
-- VALIDATION: both members must be valid TRS members (STG_TRS_VALID_MEMBERS), the relationship type must translate
--   (V_LOOKUP_CODE_VALUE PTY_REL), and the begin date may not be after the end date.
-- BAD DATA: a failing relationship is not loaded, only logged; a row can match several exception groups and is then
--   logged once per group. 'Invalid_Rel_Type' writes the looked-up code (NULL when not configured). Unfed ports
--   written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR. Unique keys Snowflake does not enforce are
--   applied: C_S_TRS_PTY_RLE_REL (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE (stale MDM timeline, ported as IDQ does it; here the timeline changes the ROW SET, not only column values,
-- docs/common_insights.md section 8):
--   mplt_Pty_Rle_Rel_Timeline_Validation
--   1. mplt_DST_Correction (fn_snow_helper35_common + REF_DYLGHT_SVNGS_TM): the end date moves forward one hour when
--      start = end, or when end + 2 hours is a daylight-saving change.
--   2. rtr_Active_Records + union_All_Records: open rows (no end date) pass once; every END-DATED row is emitted
--      TWICE - the closed version (End_Dated_Records) and an open copy with the end date removed
--      (New_Active_Records).
--   3. SRT_PKEY_FOR_RANK + exp_RANK: VERSION_SEQ is re-numbered per key in (start date ascending, end date
--      descending, NULL high) order.
--   4. exp_Stage_Output_Attributes: PERIOD_REFERENCE_TIME = end date and TIMELINE_ACTION = 2 when end dated;
--      LAST_UPDATE_DATE = run start; HUB_STATE_IND forced to 1 on the open row with VERSION_SEQ 1 (the input
--      HUB_STATE_IND is not fed, so all other rows get NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem (
    P_INDV_ID_ALT_ID_TP VARCHAR DEFAULT '007'   -- $INDV_ID_ALT_ID_TP (substituted into the source SQL)
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / systimestamp()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_REL. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- rtr_AltId_Exp.Invalid_Main_Alt_Id
        WHEN row_kind = 'ROUTER' AND pty_rle_fk_1 IS NULL AND uq_exc_member THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, PERIOD_START_DATE,
                  PERIOD_END_DATE, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
            VALUES (src_sys, run_ts, mapping_name, INDV_ID, REF_INDV_ID, rel_type_code, EFF_BEGIN_DT, EFF_END_DT,
                    exc_member_desc, exc_member_type, exc_member_code)
        -- rtr_AltId_Exp.Invalid_Ref_Alt_Id
        WHEN row_kind = 'ROUTER' AND pty_rle_fk_2 IS NULL AND uq_exc_ref THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, PERIOD_START_DATE,
                  PERIOD_END_DATE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES (src_sys, run_ts, mapping_name, INDV_ID, REF_INDV_ID, rel_type_code, EFF_BEGIN_DT, EFF_END_DT,
                    exc_ref_code, exc_ref_desc, exc_ref_type)
        -- rtr_AltId_Exp.Invalid_Lookup
        WHEN row_kind = 'ROUTER' AND rel_type_code IS NULL AND uq_exc_type THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, SRC_SYS_ID_3, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
            VALUES (src_sys, INDV_ID, REF_INDV_ID, mapping_name, run_ts, RELATIONSHIP_TYPE_CD, RELATIONSHIP_TYPE_CD,
                    attr_rel_type, EFF_BEGIN_DT, EFF_END_DT, exc_type_type, exc_type_desc, exc_type_lkp_code)
        -- rtr_AltId_Exp.Period_Start_Dt_GT_Period_End_Date
        WHEN row_kind = 'ROUTER' AND dates_reversed AND uq_exc_dates THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, SRC_SYS_ID_3, ATTRIBUTE_NAME,
                  PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES (src_sys, INDV_ID, REF_INDV_ID, mapping_name, run_ts, RELATIONSHIP_TYPE_CD, attr_dates,
                    EFF_BEGIN_DT, EFF_END_DT, exc_dates_code, exc_dates_desc, exc_dates_type)
        -- Default -> consolidation -> timeline -> Write_C_S_TRS_PTY_RLE_REL
        WHEN row_kind = 'TIMELINE' AND uq_rel THEN
            INTO C_S_TRS_PTY_RLE_REL
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY,
                  CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE,
                  HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, EFF_BEGIN_DT, tl_period_end_date, tl_version_seq,
                    tl_period_end_date, tl_timeline_action, run_ts, NULL, CREATE_DT, NULL, pkey_src_object,
                    tl_hub_state_ind, pty_rle_fk_1, pty_rle_fk_2, rel_type_code_label, hierarchy_code, rel_type_code,
                    src_last_upd_dt)
    SELECT *
      FROM (
        WITH
        lkp_cv  AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_dst AS (SELECT * FROM TABLE(fn_snow_helper47_common())),
        -- Read_STG_TRS_D_DC_RELATIONSHIPS (custom SQL, query mode SEMI)
        min_pk AS (
            SELECT indv_id, MIN(pty_pk) pty_pk FROM STG_TRS_VALID_MEMBERS GROUP BY indv_id
        ),
        src AS (
            SELECT rel.indv_id AS INDV_ID, rel.ref_indv_id AS REF_INDV_ID, rel.eff_begin_dt AS EFF_BEGIN_DT,
                   rel.eff_end_dt AS EFF_END_DT, rel.hist_nav_ind AS HIST_NAV_IND,
                   rel.relationship_type_cd AS RELATIONSHIP_TYPE_CD, pk1.pty_pk AS PTY_PKEY, pk2.pty_pk AS REF_PTY_PKEY,
                   :P_INDV_ID_ALT_ID_TP AS PTY_ALT_ID_TP, rel.create_dt AS CREATE_DT, rel.update_dt AS UPDATE_DT
              FROM STG_TRS_D_DC_RELATIONSHIPS rel
              JOIN min_pk pk1 ON rel.indv_id = pk1.indv_id
              JOIN min_pk pk2 ON rel.ref_indv_id = pk2.indv_id
        ),
        -- Lookup_V_LOOKUP_CODE_VALUE + exp_Build_FK
        keyed AS (
            SELECT s.*,
                   pt.MSTR_CODE_VALUE                                                       AS rel_type_code,
                   IFF(s.PTY_PKEY IS NULL, NULL, TRIM(s.PTY_PKEY) || '|Member')             AS pty_rle_fk_1,
                   IFF(s.REF_PTY_PKEY IS NULL, NULL, TRIM(s.REF_PTY_PKEY) || '|Member')     AS pty_rle_fk_2
              FROM src s
              LEFT JOIN lkp_cv pt ON pt.CODE_TYPE = 'PTY_REL' AND pt.SRC_SYS = 'TRS'
                                 AND pt.SRC_CODE_VALUE = s.RELATIONSHIP_TYPE_CD
        ),
        routed AS (
            SELECT k.*,
                   NVL(k.pty_rle_fk_1, '') || '|' || NVL(k.pty_rle_fk_2, '') || '|' || NVL(k.rel_type_code, '')
                                                                                            AS pkey_src_object,
                   /* VALIDATION */ NVL(k.EFF_BEGIN_DT > k.EFF_END_DT, FALSE)              AS dates_reversed
              FROM keyed k
        ),
        -- MPLT_Member_PTY_RLE_REL_Consolidation: Filter (type present), Sorter (distinct), Aggregator (one row per
        -- key + end + start; other ports from the last row)
        consolidated AS (
            SELECT r.*
              FROM routed r
             WHERE r.pty_rle_fk_1 IS NOT NULL AND r.pty_rle_fk_2 IS NOT NULL AND r.rel_type_code IS NOT NULL
               AND NOT r.dates_reversed
           QUALIFY ROW_NUMBER() OVER (PARTITION BY r.pkey_src_object, r.EFF_END_DT, r.EFF_BEGIN_DT
                                          ORDER BY r.CREATE_DT DESC NULLS FIRST, r.UPDATE_DT DESC NULLS FIRST) = 1
        ),
        -- Exp_safe_C_S_TRS_PTY_RLE_REL (SRC_LAST_UPDATE_DATE = later of create / update) + mplt_DST_Correction
        prepared AS (
            SELECT c.*,
                   IFF(c.CREATE_DT IS NOT NULL AND c.UPDATE_DT IS NOT NULL, GREATEST(c.CREATE_DT, c.UPDATE_DT),
                       NVL(c.CREATE_DT, c.UPDATE_DT))                                      AS src_last_upd_dt,
                   /* TIMELINE */ fn_snow_helper35_common(c.EFF_BEGIN_DT, c.EFF_END_DT, d.DST IS NOT NULL) AS dst_end_date
              FROM consolidated c
              LEFT JOIN lkp_dst d ON d.DST = DATEADD(hour, 2, c.EFF_END_DT)
        ),
        -- rtr_Active_Records + union_All_Records (TIMELINE)
        versions AS (
            SELECT p.*, p.dst_end_date AS tl_period_end_date FROM prepared p                -- Active / End_Dated_Records
            UNION ALL
            SELECT p.*, NULL::TIMESTAMP_NTZ FROM prepared p WHERE p.dst_end_date IS NOT NULL -- New_Active_Records
        ),
        -- SRT_PKEY_FOR_RANK + exp_RANK (TIMELINE)
        ranked AS (
            SELECT v.*,
                   ROW_NUMBER() OVER (PARTITION BY v.pkey_src_object
                                      ORDER BY v.EFF_BEGIN_DT ASC NULLS LAST,
                                               v.tl_period_end_date DESC NULLS FIRST)       AS tl_version_seq
              FROM versions v
        ),
        timeline AS (
            SELECT k.*,
                   IFF(k.tl_period_end_date IS NOT NULL, 2, NULL)                          AS tl_timeline_action,
                   IFF(k.tl_period_end_date IS NULL AND k.tl_version_seq = 1, 1, NULL)     AS tl_hub_state_ind,
                   /* BAD DATA: unique key (PKEY_SRC_OBJECT, VERSION_SEQ) not yet in the table */
                   xr.PKEY_SRC_OBJECT IS NULL                                               AS uq_rel
              FROM ranked k
              LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_REL) xr
                     ON xr.PKEY_SRC_OBJECT = k.pkey_src_object AND xr.VERSION_SEQ = k.tl_version_seq
        ),
        router AS (
            SELECT r.*,
                   /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
                   ROW_NUMBER() OVER (PARTITION BY r.pty_rle_fk_1 IS NULL, r.INDV_ID, r.REF_INDV_ID, r.rel_type_code
                                          ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_member,
                   ROW_NUMBER() OVER (PARTITION BY r.pty_rle_fk_2 IS NULL, r.INDV_ID, r.REF_INDV_ID, r.rel_type_code
                                          ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_ref,
                   ROW_NUMBER() OVER (PARTITION BY r.rel_type_code IS NULL, r.INDV_ID, r.REF_INDV_ID,
                                                   r.RELATIONSHIP_TYPE_CD ORDER BY r.CREATE_DT DESC) = 1 AS uq_exc_type,
                   ROW_NUMBER() OVER (PARTITION BY r.dates_reversed, r.INDV_ID, r.REF_INDV_ID, r.RELATIONSHIP_TYPE_CD
                                          ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_dates
              FROM routed r
        ),
        both_kinds AS (
            SELECT 'ROUTER' AS row_kind, r.INDV_ID, r.REF_INDV_ID, r.EFF_BEGIN_DT, r.EFF_END_DT,
                   r.RELATIONSHIP_TYPE_CD, r.CREATE_DT, r.rel_type_code, r.pty_rle_fk_1, r.pty_rle_fk_2,
                   r.pkey_src_object, r.dates_reversed, NULL::TIMESTAMP_NTZ AS src_last_upd_dt,
                   NULL::TIMESTAMP_NTZ AS tl_period_end_date, NULL::NUMBER AS tl_version_seq,
                   NULL::NUMBER AS tl_timeline_action, NULL::NUMBER AS tl_hub_state_ind, NULL::BOOLEAN AS uq_rel,
                   r.uq_exc_member, r.uq_exc_ref, r.uq_exc_type, r.uq_exc_dates
              FROM router r
            UNION ALL
            SELECT 'TIMELINE', t.INDV_ID, t.REF_INDV_ID, t.EFF_BEGIN_DT, t.EFF_END_DT, t.RELATIONSHIP_TYPE_CD,
                   t.CREATE_DT, t.rel_type_code, t.pty_rle_fk_1, t.pty_rle_fk_2, t.pkey_src_object, t.dates_reversed,
                   t.src_last_upd_dt, t.tl_period_end_date, t.tl_version_seq, t.tl_timeline_action,
                   t.tl_hub_state_ind, t.uq_rel, NULL, NULL, NULL, NULL
              FROM timeline t
        )
        SELECT b.*,
               'TRS'                                         AS src_sys,
               :l_run_ts                                     AS run_ts,
               :c_mapping                                    AS mapping_name,
               'Member Relationship'                         AS rel_type_code_label,
               'Member'                                      AS hierarchy_code,
               'Relationship Type'                           AS attr_rel_type,
               'Effective Date'                              AS attr_dates,
               'Invalid_Member'                              AS exc_member_code,
               xm.EXCEPTION_DESC                             AS exc_member_desc,
               xm.EXCEPTION_TYPE                             AS exc_member_type,
               'Invalid_Ref_Member'                          AS exc_ref_code,
               xf.EXCEPTION_DESC                             AS exc_ref_desc,
               xf.EXCEPTION_TYPE                             AS exc_ref_type,
               xt.EXCEPTION_CODE                             AS exc_type_lkp_code,
               xt.EXCEPTION_DESC                             AS exc_type_desc,
               xt.EXCEPTION_TYPE                             AS exc_type_type,
               'Period_Start_Date_>_Period_End_Date'         AS exc_dates_code,
               xd.EXCEPTION_DESC                             AS exc_dates_desc,
               xd.EXCEPTION_TYPE                             AS exc_dates_type
          FROM both_kinds b
          LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = 'Invalid_Member'
          LEFT JOIN lkp_exc xf ON xf.EXCEPTION_CODE = 'Invalid_Ref_Member'
          LEFT JOIN lkp_exc xt ON xt.EXCEPTION_CODE = 'Invalid_Rel_Type'
          LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date'
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TRS_PTY_RLE_REL, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

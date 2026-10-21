--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Member-to-primary-care-provider relationships (STG_TRS_D_IN_MANAGED_CARE with a provider, one source key per
-- individual) into C_S_TRS_PTY_RLE_REL_PROV (insert only, never truncated):
--   -> Filt_Numeric_Prov: IS_NUMBER(PROVIDER_NUM)
--   -> Lookup_C_B_PTY_RLE_ALT_ID (custom lookup SQL: the TPI alternate id '006' of C21 in the MDM, latest source key
--      per id) -> Exp_Build_FK: provider key = source key up to its second '|'; type 'Member PCO' when the key holds
--      '|HCO', else 'Member PCP'; relationship key = member|provider|100
--   -> Rout_Valid_vs_Exceptions
--        Period_Start_Date_GT_Period_End_Date -> EXC_STG_BAD_REC_MEMB ('Period_Start_Date_>_Period_End_Date')
--        Valid_Records (both keys, start <= end or open)
--          -> MPLT_Member_PTY_RLE_REL_Consolidation (inlined) -> mplt_Pty_Rle_Rel_Timeline_Validation (inlined,
--             TIMELINE) -> C_S_TRS_PTY_RLE_REL_PROV
--        Default (anything else, e.g. a key missing) -> EXC_STG_BAD_REC_MEMB ('Invalid_Member' / 'Invalid_PCP')
--
-- TIMELINE (stale MDM timeline, ported as IDQ does it - same mapplet as m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem):
--   DST-corrected end date; every end-dated row emitted twice (closed version + open copy); VERSION_SEQ re-ranked
--   per key (start ascending, end descending, NULL high); PERIOD_REFERENCE_TIME = end date and TIMELINE_ACTION = 2
--   when end dated; HUB_STATE_IND = 1 on the open row with VERSION_SEQ 1 (input not fed, so NULL elsewhere).
-- Unfed ports written as NULL: CREATE_DATE (not fed into the timeline mapplet in this mapping), ROWID_OBJECT,
-- DELETED_*, UPDATED_BY, CREATOR. SRC_LAST_UPD_DT = source CREATE_DT.
-- The stored source filter PROVIDER_NUM is not null duplicates the custom query's WHERE.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP (
    p_pcp_rel_tp  IN VARCHAR2 DEFAULT '100'   -- $PCP_REL_TP
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / systimestamp()
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_REL_PROV. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Rout_Valid_vs_Exceptions.Period_Start_Date_GT_Period_End_Date
        WHEN row_kind = 'ROUTER' AND BEGIN_DT > END_DT THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  PERIOD_END_DATE, SRC_SYS_ID_3, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES ('TRS', INDV_ID, PROVIDER_NUM, c_mapping, l_run_ts, 'Effective Date', BEGIN_DT, END_DT,
                    pty_rle_fk_2, 'Period_Start_Date_>_Period_End_Date',
                    fn_ors_helper04_common('Period_Start_Date_>_Period_End_Date'),
                    fn_ors_helper05_common('Period_Start_Date_>_Period_End_Date'))
        -- Rout_Valid_vs_Exceptions.Default -> Exp_safe_EXC_STG_BAD_REC_MEMB
        WHEN row_kind = 'ROUTER' AND is_valid = 0 AND NOT (BEGIN_DT > END_DT AND BEGIN_DT IS NOT NULL
                                                           AND END_DT IS NOT NULL) THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, PERIOD_START_DATE,
                  PERIOD_END_DATE, SRC_SYS_ID_1, SRC_SYS_ID_2, ATTRIBUTE_VALUE, ATTRIBUTE_NAME)
            VALUES ('TRS', l_run_ts, c_mapping,
                    CASE WHEN pty_rle_fk_1 IS NULL THEN 'Invalid_Member'
                         WHEN pty_rle_fk_2 IS NULL THEN 'Invalid_PCP' END,
                    CASE WHEN pty_rle_fk_1 IS NULL THEN fn_ors_helper04_common('Invalid_Member')
                         WHEN pty_rle_fk_2 IS NULL THEN fn_ors_helper04_common('Invalid_PCP') END,
                    CASE WHEN pty_rle_fk_1 IS NULL THEN fn_ors_helper05_common('Invalid_Member')
                         WHEN pty_rle_fk_2 IS NULL THEN fn_ors_helper05_common('Invalid_PCP') END,
                    BEGIN_DT, END_DT, INDV_ID, PROVIDER_NUM, PROVIDER_NUM, 'Provider')
        -- Valid_Records -> consolidation -> timeline -> Write_C_S_TRS_PTY_RLE_REL_PROV
        WHEN row_kind = 'TIMELINE' THEN
            INTO C_S_TRS_PTY_RLE_REL_PROV
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE,
                  SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, HIERARCHY_CODE, REL_TP,
                  SRC_LAST_UPD_DT, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, ROWID_OBJECT, DELETED_IND, DELETED_DATE,
                  DELETED_BY, UPDATED_BY, CREATOR)
            VALUES (pkey_src_object, BEGIN_DT /* TIMELINE */,
                    tl_period_end_date /* TIMELINE: DST-corrected, NULL on the open copy */,
                    tl_version_seq /* TIMELINE: re-ranked */, l_run_ts, NULL /* unfed */, pkey_src_object,
                    CASE WHEN tl_period_end_date IS NULL AND tl_version_seq = 1 THEN 1 END /* TIMELINE: forced hub state */,
                    pty_rle_fk_1, pty_rle_fk_2, rel_type_code, 'Member', p_pcp_rel_tp, CREATE_DT,
                    tl_period_end_date /* TIMELINE: PERIOD_REFERENCE_TIME */,
                    CASE WHEN tl_period_end_date IS NOT NULL THEN 2 END /* TIMELINE_ACTION */,
                    NULL, NULL, NULL, NULL, NULL, NULL)
    WITH
    -- Read_STG_TRS_D_IN_MANAGED_CARE (custom SQL, query mode SEMI) + Filt_Numeric_Prov
    min_pk AS (
        SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
    ),
    src AS (
        SELECT mc.indv_id AS INDV_ID, mc.history_seq AS HISTORY_SEQ, mc.mc_prog_code AS MC_PROG_CODE,
               mc.begin_dt AS BEGIN_DT, mc.create_dt AS CREATE_DT, mc.provider_num AS PROVIDER_NUM,
               mc.end_dt AS END_DT, vm.pty_pk AS PTY_PK
          FROM stg_trs_d_in_managed_care mc
          JOIN min_pk vm ON mc.indv_id = vm.indv_id
         WHERE provider_num IS NOT NULL
           AND fn_ors_helper01_common(provider_num) = 1                                   -- Filt_Numeric_Prov
    ),
    -- Lookup_C_B_PTY_RLE_ALT_ID (custom lookup SQL)
    tpi_src_key AS (
        SELECT alt_id_val, pkey_src_object
          FROM (SELECT bo.alt_id_val, xr.pkey_src_object,
                       ROW_NUMBER() OVER (PARTITION BY bo.alt_id_val ORDER BY xr.src_last_upd_dt DESC) src_key_rn
                  FROM c_b_pty_rle_alt_id bo
                 INNER JOIN c_b_pty_rle_alt_id_xref xr ON bo.rowid_object = xr.rowid_object
                 WHERE bo.alt_id_tp = '006' AND xr.rowid_system = 'C21' AND xr.hub_state_ind = 1)
         WHERE src_key_rn = 1
    ),
    -- Exp_Build_FK
    keyed AS (
        SELECT s.*,
               CASE WHEN s.PTY_PK IS NULL THEN NULL ELSE LTRIM(RTRIM(s.PTY_PK)) || '|Member' END       AS pty_rle_fk_1,
               SUBSTR(LTRIM(RTRIM(t.pkey_src_object)), 1,
                      INSTR(LTRIM(RTRIM(t.pkey_src_object)), '|', 1, 2) - 1)                          AS pty_rle_fk_2,
               CASE WHEN INSTR(LTRIM(RTRIM(t.pkey_src_object)), '|HCO', 1, 1) > 0 THEN 'Member PCO'
                    ELSE 'Member PCP' END                                                             AS rel_type_code
          FROM src s
         OUTER APPLY (SELECT k.pkey_src_object FROM tpi_src_key k
                       WHERE k.alt_id_val = s.PROVIDER_NUM FETCH FIRST 1 ROW ONLY) t
    ),
    routed AS (
        SELECT k.*,
               k.pty_rle_fk_1 || '|' || k.pty_rle_fk_2 || '|' || p_pcp_rel_tp                        AS pkey_src_object,
               CASE WHEN k.pty_rle_fk_1 IS NOT NULL AND k.pty_rle_fk_2 IS NOT NULL
                         AND (k.BEGIN_DT <= k.END_DT OR k.END_DT IS NULL) THEN 1 ELSE 0 END          AS is_valid
          FROM keyed k
    ),
    -- MPLT_Member_PTY_RLE_REL_Consolidation (type always present here; UPDATE_DT not fed)
    consolidated AS (
        SELECT c.*
          FROM (SELECT r.*,
                       ROW_NUMBER() OVER (PARTITION BY r.pkey_src_object, r.END_DT, r.BEGIN_DT
                                          ORDER BY r.CREATE_DT DESC NULLS FIRST) AS rn
                  FROM routed r
                 WHERE r.is_valid = 1 AND r.rel_type_code IS NOT NULL) c
         WHERE c.rn = 1
    ),
    -- mplt_DST_Correction + rtr_Active_Records + union_All_Records (TIMELINE)
    versions AS (
        SELECT c.*, fn_dq_dst_correction(c.BEGIN_DT, c.END_DT) AS tl_period_end_date
          FROM consolidated c
        UNION ALL
        SELECT c.*, CAST(NULL AS DATE)
          FROM consolidated c
         WHERE fn_dq_dst_correction(c.BEGIN_DT, c.END_DT) IS NOT NULL
    ),
    -- SRT_PKEY_FOR_RANK + exp_RANK (TIMELINE)
    ranked AS (
        SELECT v.*,
               ROW_NUMBER() OVER (PARTITION BY v.pkey_src_object
                                  ORDER BY v.BEGIN_DT ASC NULLS LAST, v.tl_period_end_date DESC NULLS FIRST) AS tl_version_seq
          FROM versions v
    )
    SELECT 'ROUTER' AS row_kind, r.INDV_ID, r.PROVIDER_NUM, r.BEGIN_DT, r.END_DT, r.CREATE_DT, r.pty_rle_fk_1,
           r.pty_rle_fk_2, r.rel_type_code, r.pkey_src_object, r.is_valid, CAST(NULL AS DATE) AS tl_period_end_date,
           CAST(NULL AS NUMBER) AS tl_version_seq
      FROM routed r
    UNION ALL
    SELECT 'TIMELINE', k.INDV_ID, k.PROVIDER_NUM, k.BEGIN_DT, k.END_DT, k.CREATE_DT, k.pty_rle_fk_1, k.pty_rle_fk_2,
           k.rel_type_code, k.pkey_src_object, k.is_valid, k.tl_period_end_date, k.tl_version_seq
      FROM ranked k;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TRS_PTY_RLE_REL_PROV, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP;
/

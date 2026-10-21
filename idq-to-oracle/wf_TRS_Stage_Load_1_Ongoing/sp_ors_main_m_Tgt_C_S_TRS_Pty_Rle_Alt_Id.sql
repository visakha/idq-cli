--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Alt_Id (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Alternate ids of valid TIERS members into C_S_TRS_PTY_RLE_ALT_ID (insert only, never truncated):
--   Read_STG_TRS_D_DC_INDV (custom SQL: MCI, DC_INDV and merged-individual keys of valid members, one row per key
--     keeping the longest, latest SSN)
--   -> lkp_Valid_SSN: the SSN is used only when STG_TRS_H_DC_INDV has it SSA-validated for the individual
--   -> mplt_TRS_Pty_Rle_Alt_Id_Normalization (TABLE(fn_dq_norm_trs_alt_id(...))): Medicaid id and member id (both the
--      member id), validated SSN; one row per non-empty id
--        valid rows   -> srtr_Pkey -> exp_Rank / fltr_Rank (TIMELINE) -> target
--        invalid rows -> EXC_STG_BAD_REC_MEMB (written INSIDE the IDQ mapplet; written here by the procedure)
--
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * exp_Rank ranks versions per key but VERSION_SEQ is hard-coded to 1 (the rank is commented out), so fltr_Rank
--     (VERSION_SEQ = 1) keeps EVERY row; no de-duplication happens. VERSION_SEQ = 1.
--   * PERIOD_START_DATE / CREATE_DATE / SRC_LAST_UPD_DT = START_DT; PERIOD_END_DATE, PERIOD_REFERENCE_TIME,
--     TIMELINE_ACTION are linked to unfed ports (NULL).
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND.
-- The stored source filter INDV_ID = 504937068 is not part of the custom query and is not applied.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- RTR_Invalid_Alt_Ids.Valid_Alt_ID -> srtr_Pkey -> exp_Rank -> fltr_Rank -> exp_Safe_C_S_TRS_Pty_Rle_Alt_Id
        WHEN is_valid = 'Y' THEN
            INTO C_S_TRS_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, SRC_ROWID, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, ALT_ID_TP, ALT_ID_VAL,
                  STS_CD, ALT_ID_TP_FLTR, CV_IND, PTY_RLE_FK, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
                  PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE, CREATOR,
                  HUB_STATE_IND, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object_alt_id, pkey_src_object_alt_id, period_start_date /* TIMELINE */,
                    1 /* TIMELINE: exp_Rank.VERSION_SEQ hard-coded */, l_run_ts, alt_id_typ, alt_id_val, 'Issued',
                    alt_id_typ, cv_ind, pty_rle_fk, NULL, NULL, NULL, NULL, NULL /* TIMELINE: unfed */,
                    NULL /* TIMELINE: unfed */, NULL /* TIMELINE: unfed */, NULL, period_start_date, NULL, NULL,
                    period_start_date)
        -- RTR_Invalid_Alt_Ids.Default -> Expression -> Write_EXC_STG_BAD_REC_MEMB (inside the IDQ mapplet)
        WHEN is_valid = 'N' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (MAPPING_NAME, SRC_SYS, RUN_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, EXCEPTION_DESC, EXCEPTION_CODE,
                  EXCEPTION_TYPE, SRC_SYS_ID_1)
            VALUES (c_mapping, src_sys, l_run_ts, alt_id_val, alt_id_label, dq_excp, dq_excp_cd, 'Bad Value',
                    pkey_src_object_pty)
    WITH
    -- Read_STG_TRS_D_DC_INDV (custom SQL, query mode SEMI)
    all_indv AS (
        SELECT DISTINCT TO_CHAR(indv_id) AS pty_pkey, mci_indv.indv_id AS member_id, mci_indv.create_dt, ssn,
               '1' cv_ind
          FROM stg_trs_d_cv_dc_mci_indv mci_indv
        UNION ALL
        SELECT DISTINCT TO_CHAR(indv_id) || '|DC_INDV' AS pty_pkey, indv_id AS member_id, create_dt, ssn, NULL cv_ind
          FROM stg_trs_d_dc_indv indv
        UNION ALL
        SELECT DISTINCT TO_CHAR(old_indv_id) AS pty_pkey, mrg.indv_id AS member_id, mrg.create_dt, NULL AS ssn,
               NULL AS cv_ind
          FROM stg_trs_d_cv_dc_mrg_sprt_indv mrg
         WHERE type_cd = 'ME'
    ),
    de_dup_indv AS (
        SELECT pty_pkey, TO_CHAR(member_id) AS member_id, create_dt start_dt, ssn, cv_ind,
               ROW_NUMBER() OVER (PARTITION BY pty_pkey ORDER BY LENGTH(ssn) DESC, create_dt DESC) key_rn
          FROM all_indv
          JOIN stg_trs_valid_members vm ON all_indv.pty_pkey = vm.pty_pk
    ),
    src AS (
        SELECT pty_pkey AS PTY_PKEY, member_id AS MEMBER_ID, start_dt AS START_DT, ssn AS SSN, cv_ind AS CV_IND
          FROM de_dup_indv
         WHERE key_rn = 1
    ),
    -- exp_TRS_Pty_Rle_Alt_Id + lkp_Valid_SSN (custom lookup SQL: SSA-validated, positive SSNs)
    with_ssn AS (
        SELECT s.*, v.SSN AS valid_ssn
          FROM src s
         OUTER APPLY (SELECT h.SSN
                        FROM (SELECT DISTINCT INDV_ID, SSN FROM STG_TRS_H_DC_INDV
                               WHERE SSA_VALIDATION_SW = 'Y' AND SSN > 0) h
                       WHERE h.INDV_ID = fn_ors_helper07_common(s.MEMBER_ID, 0) AND h.SSN = s.SSN
                       FETCH FIRST 1 ROW ONLY) v
    )
    -- mplt_TRS_Pty_Rle_Alt_Id_Normalization
    SELECT n.pkey_src_object_alt_id, n.pkey_src_object_pty, n.pty_rle_fk, n.period_start_date, n.alt_id_val,
           n.alt_id_typ, n.alt_id_label, n.dq_excp, n.dq_excp_cd, n.src_sys, n.cv_ind, n.is_valid
      FROM with_ssn w
     CROSS APPLY TABLE(fn_dq_norm_trs_alt_id(w.PTY_PKEY, w.START_DT, 'TRS', w.MEMBER_ID, w.valid_ssn, w.MEMBER_ID,
                                             NULL, w.CV_IND)) n;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TRS_PTY_RLE_ALT_ID, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id;
/

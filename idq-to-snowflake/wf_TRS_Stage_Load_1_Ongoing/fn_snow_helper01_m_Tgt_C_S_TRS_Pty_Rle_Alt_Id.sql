--------------------------------------------------------------------------------------------------------------------
-- fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id
--
-- Helper of sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id: the rule calls and the Normalizer of
-- mplt_TRS_Pty_Rle_Alt_Id_Normalization (EXP_safe_src, rule_MEDICAID_ID_Std, rule_MEMBER_ID_Std,
-- rule_USA_SSN_Validation_post_June2011, exp_validate_ssn, EXP_prepare_Normalizer, NRM_ALT_ID). One member row becomes
-- one row per alternate id:
--   '002' Medicaid id     value = source value, code = rule_MEDICAID_ID_Std code (fn_snow_helper27_common)
--   '004' SSN             value = LPAD(SSN, 9, '0'), or NULL when the SSN rule says 'Invalid' (exp_validate_ssn:
--                         an invalid SSN is BLANKED, so FLTR_Remove_Null_Alt_IDs drops it and it is never logged,
--                         docs/common_insights.md 1.6); code 'Invalid_SSN' in that case (the mapplet then takes the
--                         code returned by LU_SSN_Exc_Code; the row is dropped either way)
--   '007' member id       value = source value, code = rule_Member_Id_Std code (fn_snow_helper28_common)
--   '009' NIS client id   value = source value, no rule
-- The value normalized is the SOURCE value (EXP_safe_src); the cleaned rule outputs only decide the exception code.
-- The rest of the mapplet runs in the calling procedure, set-based: the exception descriptions (EXC_LOOKUP_CODE_VALUE),
-- LKP_ALT_ID_LBL (LOOKUP_CODE_VALUE ALT_ID_TP), FLTR_Remove_Null_Alt_IDs, RTR_Invalid_Alt_Ids and the mapplet's own
-- EXC_STG_BAD_REC_MEMB target.
--
-- Pure SQL table function (no table access), called laterally: FROM src s, TABLE(fn_...(s.col, ...)) n.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id (
    p_pkey_src_object_pty VARCHAR, p_period_start_date TIMESTAMP_NTZ, p_src_sys VARCHAR,
    p_alt_id_val_member_id VARCHAR, p_alt_id_val_ssn_num NUMBER, p_alt_id_val_medicaid_id VARCHAR,
    p_alt_id_val_ns_client_id VARCHAR, p_cv_ind VARCHAR)
RETURNS TABLE (PKEY_SRC_OBJECT_PTY VARCHAR, PERIOD_START_DATE TIMESTAMP_NTZ, ALT_ID_VAL VARCHAR, ALT_ID_TYP VARCHAR,
               DQ_EXCP_CD VARCHAR, SRC_SYS VARCHAR, CV_IND VARCHAR, ORIGINAL_SSN VARCHAR)
AS
$$
    SELECT p_pkey_src_object_pty, p_period_start_date, p_alt_id_val_medicaid_id, '002',
           fn_snow_helper27_common(p_alt_id_val_medicaid_id):exception_code::VARCHAR, p_src_sys, p_cv_ind,
           LPAD(TO_VARCHAR(p_alt_id_val_ssn_num), 9, '0')
    UNION ALL
    SELECT p_pkey_src_object_pty, p_period_start_date,
           IFF(fn_snow_helper26_common(LPAD(TO_VARCHAR(p_alt_id_val_ssn_num), 9, '0')):ssn_status::VARCHAR = 'Invalid',
               NULL, LPAD(TO_VARCHAR(p_alt_id_val_ssn_num), 9, '0')),
           '004',
           IFF(fn_snow_helper26_common(LPAD(TO_VARCHAR(p_alt_id_val_ssn_num), 9, '0')):ssn_status::VARCHAR = 'Invalid',
               'Invalid_SSN', NULL),
           p_src_sys, p_cv_ind, LPAD(TO_VARCHAR(p_alt_id_val_ssn_num), 9, '0')
    UNION ALL
    SELECT p_pkey_src_object_pty, p_period_start_date, p_alt_id_val_member_id, '007',
           fn_snow_helper28_common(p_alt_id_val_member_id):exception_code::VARCHAR, p_src_sys, p_cv_ind,
           LPAD(TO_VARCHAR(p_alt_id_val_ssn_num), 9, '0')
    UNION ALL
    SELECT p_pkey_src_object_pty, p_period_start_date, p_alt_id_val_ns_client_id, '009', NULL, p_src_sys, p_cv_ind,
           LPAD(TO_VARCHAR(p_alt_id_val_ssn_num), 9, '0')
$$;

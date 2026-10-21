--------------------------------------------------------------------------------------------------------------------
-- fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr
--
-- Helper of sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr: the Normalizer of mplt_Member_Pty_Rle_Phn_Normalization
-- (exp_Phone_Input + Normalizer, occurs 3). One input row with three phone slots becomes three rows, one per slot,
-- with PREF_LVL 'Primary' / 'Secondary' / 'Tertiary' (exp_Phone_Input constants).
--
-- Only the row multiplication is here; the rest of the mapplet runs in the calling procedure, set-based:
--   rule_Phone_Primary / _Secondary / _Tertiary (rule_Phone_Std: fn_snow_helper23_common + REF_PHN_AREA_CD +
--   fn_snow_helper24_common), Filter_Null_Phone_Nums, Lookup_LOOKUP_CODE_VALUE (PHN_USG_TP) and Exp_NEWOUTPUT.
--
-- Pure SQL table function (no table access), called laterally: FROM src s, TABLE(fn_...(s.col, ...)) n.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr (
    p_period_start_date TIMESTAMP_NTZ, p_pty_fk VARCHAR, p_src_sys VARCHAR, p_case_number VARCHAR,
    p_usg_tp_primary VARCHAR, p_phn_tp_primary VARCHAR, p_phn_num_primary VARCHAR,
    p_usg_tp_secondary VARCHAR, p_phn_tp_secondary VARCHAR, p_phn_num_secondary VARCHAR,
    p_usg_tp_tertiary VARCHAR, p_phn_tp_tertiary VARCHAR, p_phn_num_tertiary VARCHAR)
RETURNS TABLE (PERIOD_START_DATE TIMESTAMP_NTZ, PTY_FK VARCHAR, PREF_LVL VARCHAR, USG_TP VARCHAR, PHN_TP VARCHAR,
               PHN_NUM_IN VARCHAR, SRC_SYS VARCHAR, CASE_NUMBER VARCHAR)
AS
$$
    SELECT p_period_start_date, p_pty_fk, 'Primary', p_usg_tp_primary, p_phn_tp_primary, p_phn_num_primary,
           p_src_sys, p_case_number
    UNION ALL
    SELECT p_period_start_date, p_pty_fk, 'Secondary', p_usg_tp_secondary, p_phn_tp_secondary, p_phn_num_secondary,
           p_src_sys, p_case_number
    UNION ALL
    SELECT p_period_start_date, p_pty_fk, 'Tertiary', p_usg_tp_tertiary, p_phn_tp_tertiary, p_phn_num_tertiary,
           p_src_sys, p_case_number
$$;

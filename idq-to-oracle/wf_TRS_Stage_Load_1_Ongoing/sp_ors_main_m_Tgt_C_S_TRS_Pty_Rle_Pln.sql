--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Pln (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Managed-care plans of valid MCI members (STG_TRS_D_IN_MANAGED_CARE, plan present, begin before end or open) into
-- C_S_TRS_PTY_RLE_PLN (truncated first):
--   -> lkp_Plan_Cd (V_LOOKUP_CODE_VALUE, code type PLAN_CD, source system 'MAX') -> rtr_Invalid_Plan_Cd
--        VALID (plan translates) -> srtr_Pkey -> agg_Dedup_Rec (one row per INDV_ID|Member|plan) -> target
--        Default                 -> exp_Rank + fltr_Rank: the FIRST invalid row per individual (source order
--                                   INDV_ID, MC_PLAN, BEGIN_DT, END_DT) -> EXC_STG_BAD_REC_MEMB ('Invalid_Plan')
--
-- agg_Dedup_Rec returns the last row of each key in srtr_Pkey order (key, PERIOD_START_DATE, PERIOD_END_DATE,
-- PLN_FK, PTY_RLE_FK; ascending, NULL high).
--
-- TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Safe_C_S_TRS_PTY_RLE_PLN.v_VERS_SEQ_NUM); PERIOD_START_DATE /
-- PERIOD_END_DATE = BEGIN_DT / END_DT of the last (latest) segment of the key.
-- Unfed ports written as NULL: UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT, DELETED_*.
-- The exception code is the computed 'Invalid_Plan'; description / type are looked up.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Rle_Pln';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    sp_ors_helper01_common('C_S_TRS_PTY_RLE_PLN');

    INSERT ALL
        -- rtr_Invalid_Plan_Cd.VALID -> srtr_Pkey -> agg_Dedup_Rec -> exp_Safe_C_S_TRS_PTY_RLE_PLN
        WHEN pln_mstr_cd IS NOT NULL AND rn_key = 1 THEN
            INTO C_S_TRS_PTY_RLE_PLN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, PTY_RLE_FK,
                  PLN_FK, UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
                  SRC_ROWID, CREATE_DATE, SRC_LAST_UPD_DT)
            VALUES (pkey_prty_rl_plan, BEGIN_DT /* TIMELINE */, END_DT /* TIMELINE */,
                    1 /* TIMELINE: VERSION_SEQ hard-coded */, l_run_ts, pty_rle_fk, pln_mstr_cd, NULL, NULL, NULL,
                    NULL, NULL, NULL, NULL, pkey_prty_rl_plan, l_run_ts, CREATE_DT)
        -- rtr_Invalid_Plan_Cd.Default -> exp_Rank -> fltr_Rank (RANK = 1) -> exp_Plan_Cd_Exc
        WHEN pln_mstr_cd IS NULL AND rn_invalid = 1 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, MAPPING_NAME, RUN_DATE, PERIOD_START_DATE, SRC_SYS_ID_2)
            VALUES ('TRS', INDV_ID, fn_ors_helper05_common('Invalid_Plan'), fn_ors_helper04_common('Invalid_Plan'),
                    'Invalid_Plan', MC_PLAN, 'Plan', c_mapping, l_run_ts, BEGIN_DT, TO_CHAR(BEGIN_DT, 'YYYY-MM-DD'))
    WITH
    -- Read_Stg_TRS_D_IN_Managed_Care (custom SQL, query mode SEMI)
    src AS (
        SELECT DISTINCT M.INDV_ID AS INDV_ID, M.BEGIN_DT, M.MC_PLAN, M.HISTORY_SEQ, M.END_DT, M.CREATE_DT
          FROM STG_TRS_D_IN_MANAGED_CARE M
          JOIN STG_TRS_VALID_MEMBERS VM ON M.INDV_ID = VM.INDV_ID AND VM.SRC_TBL = 'MCI'
         WHERE MC_PLAN IS NOT NULL
           AND (M.BEGIN_DT < M.END_DT OR M.END_DT IS NULL)
    ),
    -- lkp_Plan_Cd + exp_Pty_Rle_Fk + exp_Pty_Rle_Plan
    planned AS (
        SELECT s.*,
               lk.MSTR_CODE_VALUE                         AS pln_mstr_cd,
               s.INDV_ID || '|Member'                     AS pty_rle_fk,
               s.INDV_ID || '|Member' || '|' || lk.MSTR_CODE_VALUE AS pkey_prty_rl_plan
          FROM src s
         OUTER APPLY (SELECT v.MSTR_CODE_VALUE FROM V_LOOKUP_CODE_VALUE v
                       WHERE v.CODE_TYPE = 'PLAN_CD' AND v.SRC_SYS = 'MAX' AND v.SRC_CODE_VALUE = s.MC_PLAN
                       FETCH FIRST 1 ROW ONLY) lk
    )
    SELECT p.*,
           -- agg_Dedup_Rec: last row per key in srtr_Pkey order (NULL high)
           ROW_NUMBER() OVER (PARTITION BY p.pkey_prty_rl_plan
                              ORDER BY p.BEGIN_DT DESC NULLS FIRST, p.END_DT DESC NULLS FIRST,
                                       p.pty_rle_fk DESC NULLS FIRST, p.CREATE_DT DESC NULLS FIRST)   AS rn_key,
           -- exp_Rank + fltr_Rank on the invalid rows: first row per INDV_ID in source order
           ROW_NUMBER() OVER (PARTITION BY p.INDV_ID, CASE WHEN p.pln_mstr_cd IS NULL THEN 1 ELSE 0 END
                              ORDER BY p.MC_PLAN, p.BEGIN_DT, p.END_DT)                               AS rn_invalid
      FROM planned p;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TRS_PTY_RLE_PLN, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln;
/

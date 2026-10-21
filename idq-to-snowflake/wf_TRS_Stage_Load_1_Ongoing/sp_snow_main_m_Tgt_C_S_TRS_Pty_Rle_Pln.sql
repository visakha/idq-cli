--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Pln (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Managed-care plans of valid MCI members (STG_TRS_D_IN_MANAGED_CARE, plan present, begin before end or open) into
-- C_S_TRS_PTY_RLE_PLN (insert only, never truncated):
--   -> lkp_Plan_Cd (V_LOOKUP_CODE_VALUE, code type PLAN_CD, source system 'MAX') -> rtr_Invalid_Plan_Cd
--        VALID (plan translates) -> srtr_Pkey -> agg_Dedup_Rec (one row per INDV_ID|Member|plan) -> target
--        Default                 -> exp_Rank + fltr_Rank: the FIRST invalid row per individual (source order
--                                   INDV_ID, MC_PLAN, BEGIN_DT, END_DT) -> EXC_STG_BAD_REC_MEMB ('Invalid_Plan')
--
-- VALIDATION: the plan code must translate in V_LOOKUP_CODE_VALUE (PLAN_CD, looked up under source system 'MAX').
-- BAD DATA: rows with begin >= end are dropped by the source query; only the first invalid plan per individual is
--   logged (computed code 'Invalid_Plan', looked-up description / type). agg_Dedup_Rec returns the last row of each
--   key in srtr_Pkey order (key, PERIOD_START_DATE, PERIOD_END_DATE, PLN_FK, PTY_RLE_FK; ascending, NULL high).
--   Unfed ports written as NULL: UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT, DELETED_*. Unique keys Snowflake
--   does not enforce are applied: C_S_TRS_PTY_RLE_PLN (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Safe_C_S_TRS_PTY_RLE_PLN.v_VERS_SEQ_NUM); PERIOD_START_DATE /
--   PERIOD_END_DATE = BEGIN_DT / END_DT of the last (latest) segment of the key.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Pln';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_PLN. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- rtr_Invalid_Plan_Cd.VALID -> srtr_Pkey -> agg_Dedup_Rec -> exp_Safe_C_S_TRS_PTY_RLE_PLN
        WHEN pln_mstr_cd IS NOT NULL AND rn_key = 1 AND uq_pln THEN
            INTO C_S_TRS_PTY_RLE_PLN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, PTY_RLE_FK,
                  PLN_FK, UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
                  SRC_ROWID, CREATE_DATE, SRC_LAST_UPD_DT)
            VALUES (pkey_prty_rl_plan, BEGIN_DT, END_DT, version_seq, run_ts, pty_rle_fk, pln_mstr_cd, NULL, NULL,
                    NULL, NULL, NULL, NULL, NULL, pkey_prty_rl_plan, run_ts, CREATE_DT)
        -- rtr_Invalid_Plan_Cd.Default -> exp_Rank -> fltr_Rank (RANK = 1) -> exp_Plan_Cd_Exc
        WHEN pln_mstr_cd IS NULL AND rn_invalid = 1 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, MAPPING_NAME, RUN_DATE, PERIOD_START_DATE, SRC_SYS_ID_2)
            VALUES (src_sys, INDV_ID, exc_type, exc_desc, exc_code, MC_PLAN, attr_plan, mapping_name, run_ts,
                    BEGIN_DT, begin_dt_text)
    SELECT *
      FROM (
        WITH
        lkp_cv  AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_Stg_TRS_D_IN_Managed_Care (custom SQL, query mode SEMI)
        src AS (
            SELECT DISTINCT M.INDV_ID AS INDV_ID, M.BEGIN_DT, M.MC_PLAN, M.HISTORY_SEQ, M.END_DT, M.CREATE_DT
              FROM STG_TRS_D_IN_MANAGED_CARE M
              JOIN STG_TRS_VALID_MEMBERS VM ON M.INDV_ID = VM.INDV_ID AND VM.SRC_TBL = 'MCI'
             WHERE M.MC_PLAN IS NOT NULL
               AND (M.BEGIN_DT < M.END_DT OR M.END_DT IS NULL)
        ),
        -- lkp_Plan_Cd + exp_Pty_Rle_Fk + exp_Pty_Rle_Plan
        planned AS (
            SELECT s.*,
                   lk.MSTR_CODE_VALUE                                                   AS pln_mstr_cd,
                   TO_VARCHAR(s.INDV_ID) || '|Member'                                   AS pty_rle_fk,
                   TO_VARCHAR(s.INDV_ID) || '|Member|' || NVL(lk.MSTR_CODE_VALUE, '')   AS pkey_prty_rl_plan
              FROM src s
              LEFT JOIN lkp_cv lk ON lk.CODE_TYPE = 'PLAN_CD' AND lk.SRC_SYS = 'MAX' AND lk.SRC_CODE_VALUE = s.MC_PLAN
        )
        SELECT p.*,
               -- agg_Dedup_Rec: last row per key in srtr_Pkey order (NULL high)
               ROW_NUMBER() OVER (PARTITION BY p.pkey_prty_rl_plan
                                  ORDER BY p.BEGIN_DT DESC NULLS FIRST, p.END_DT DESC NULLS FIRST,
                                           p.pty_rle_fk DESC NULLS FIRST, p.CREATE_DT DESC NULLS FIRST)   AS rn_key,
               -- exp_Rank + fltr_Rank on the invalid rows: first row per INDV_ID in source order
               ROW_NUMBER() OVER (PARTITION BY p.INDV_ID, p.pln_mstr_cd IS NULL
                                  ORDER BY p.MC_PLAN, p.BEGIN_DT, p.END_DT)                               AS rn_invalid,
               /* BAD DATA: unique key (PKEY_SRC_OBJECT, VERSION_SEQ) not yet in the table */
               xp.PKEY_SRC_OBJECT IS NULL                                                                  AS uq_pln,
               1 /* TIMELINE: VERSION_SEQ hard-coded */                                                   AS version_seq,
               'TRS'                                                    AS src_sys,
               :l_run_ts                                                AS run_ts,
               :c_mapping                                               AS mapping_name,
               'Plan'                                                   AS attr_plan,
               'Invalid_Plan'                                           AS exc_code,
               ex.EXCEPTION_DESC                                        AS exc_desc,
               ex.EXCEPTION_TYPE                                        AS exc_type,
               TO_VARCHAR(p.BEGIN_DT, 'YYYY-MM-DD')                     AS begin_dt_text
          FROM planned p
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Plan'
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_PLN WHERE VERSION_SEQ = 1) xp
                 ON xp.PKEY_SRC_OBJECT = p.pkey_prty_rl_plan
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TRS_PTY_RLE_PLN, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

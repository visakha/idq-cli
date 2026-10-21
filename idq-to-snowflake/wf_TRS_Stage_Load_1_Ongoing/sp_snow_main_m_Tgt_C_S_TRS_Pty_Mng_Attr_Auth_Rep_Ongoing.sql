--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing (workflow
-- wf_TRS_Stage_Load_1_Ongoing). Runs after m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw and APPENDS to C_S_TRS_PTY_MNG_ATTR.
--
-- Authorized-representative flag ('Auth_Rep_Flag' = 'Y') of valid TIERS members whose case has a verified,
-- sent authorized representative (custom SQL: six union branches over the payee / case / EDG delta tables):
--   -> srtr_Indv_Id (INDV_ID, EFF_BEGIN_DT) -> exp_Rank -> srtr_Rank (distinct) -> exp_Pkey_Generation
--   -> agg_Dedup_TRS_Pty_Mng_Attr: one row per key (INDV_ID || '|Auth_Rep_Flag'), PERIOD_END_DATE = MAX(EFF_END_DT),
--      every other port from the last row of the group
--
-- VALIDATION: none (no rule runs here); the verification codes CS / FH / LD / OA and SENT_AUTHREP_SW = 'Y' select the
--   cases.
-- BAD DATA: C_S_TRS_PTY_MNG_ATTR is unique on (PKEY_SRC_OBJECT, VERSION_SEQ), which Snowflake does not enforce: a key
--   already in the table is skipped (the aggregator already gives one row per key in the run).
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * exp_Rank.VERSION_SEQ_NUM is hard-coded to 1 and written to VERSION_SEQ.
--   * srtr_Rank is a distinct re-sort on INDV_ID around exp_Rank (kept: the DISTINCT below).
--   * PERIOD_START_DATE = EFF_BEGIN_DT of the last row, PERIOD_END_DATE = MAX(EFF_END_DT) per key.
--   Last row per key = latest EFF_BEGIN_DT (srtr_Indv_Id order, NULL high), assuming the key-only re-sort keeps it.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing (
    P_ATTR_TP_AUTH_REP VARCHAR DEFAULT 'Auth_Rep_Flag'   -- $ATTR_TP_AUTH_REP
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO C_S_TRS_PTY_MNG_ATTR
           (CREATE_DATE, LAST_UPDATE_DATE, MNG_ATTR_TP, PTY_FK, PERIOD_END_DATE, PERIOD_START_DATE, VERSION_SEQ,
            SRC_ROWID, PKEY_SRC_OBJECT, SRC_LAST_UPD_DT, MNG_ATTR_VAL)
    WITH
    -- Read_STG_TRS_D_DC_Primary_Payee (custom SQL, query mode SEMI)
    a AS (
        SELECT ed.indv_id, 'Y' AS AR_FLAG, ed.elig_eff_begin_dt AS eff_begin_dt, ed.elig_eff_end_dt AS eff_end_dt,
               p.create_dt AS create_dt                                                                  -- In1
          FROM STG_TRS_D_DC_PRIMARY_PAYEE p
          JOIN STG_TRS_CV_ED_MCI_EDG_INDV ed
            ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
          JOIN STG_TRS_DC_CASES c ON p.case_num = c.case_num
         WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
           AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
        UNION ALL
        SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt                    -- In2
          FROM STG_TRS_D_DC_CASES c
          JOIN STG_TRS_DC_PRIMARY_PAYEE p ON p.case_num = c.case_num
          JOIN STG_TRS_CV_ED_MCI_EDG_INDV ed
            ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
         WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
           AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
        UNION ALL
        SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt                    -- In3
          FROM STG_TRS_DC_CASES c
          JOIN STG_TRS_DC_PRIMARY_PAYEE p ON p.case_num = c.case_num
          JOIN STG_TRS_D_CV_ED_MCI_EDG_INDV ed
            ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
         WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
           AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
        UNION ALL
        SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt) -- Out1
          FROM STG_TRS_D_CV_ED_MCI_EDG_INDV ed
          LEFT JOIN STG_TRS_DC_PRIMARY_PAYEE p
            ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
           AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
           AND p.edg_num IS NULL
          JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
          JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
         WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
        UNION ALL
        SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt                    -- Inner
          FROM STG_TRS_CV_ED_MCI_EDG_INDV ed
          JOIN STG_TRS_D_DC_PRIMARY_PAYEE p
            ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
           AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
           AND p.edg_num IS NULL
          JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
          JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
         WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
        UNION ALL
        SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt) -- Out3
          FROM STG_TRS_CV_ED_MCI_EDG_INDV ed
          LEFT JOIN STG_TRS_DC_PRIMARY_PAYEE p
            ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
           AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
           AND p.edg_num IS NULL
          JOIN STG_TRS_D_DC_CASES c ON ed.case_num = c.case_num
          JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
         WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    ),
    src AS (
        SELECT DISTINCT a.indv_id AS INDV_ID, a.AR_FLAG, a.eff_begin_dt AS EFF_BEGIN_DT, a.eff_end_dt AS EFF_END_DT,
               a.create_dt AS CREATE_DT
          FROM a
          JOIN STG_TRS_VALID_MEMBERS IM ON TO_VARCHAR(a.INDV_ID) = IM.PTY_PK
    ),
    -- srtr_Indv_Id -> exp_Rank -> srtr_Rank (TIMELINE: distinct re-sort) -> exp_Pkey_Generation
    keyed AS (
        SELECT DISTINCT s.INDV_ID, s.AR_FLAG, s.EFF_BEGIN_DT, s.EFF_END_DT, s.CREATE_DT,
               TO_VARCHAR(s.INDV_ID) || '|' || :P_ATTR_TP_AUTH_REP  AS pkey_src_object,
               TO_VARCHAR(s.INDV_ID)                                AS pty_pk
          FROM src s
    ),
    -- agg_Dedup_TRS_Pty_Mng_Attr: group by PKEY_SRC_OBJECT, MAX(EFF_END_DT), last row for the other ports
    agg AS (
        SELECT k.*,
               MAX(k.EFF_END_DT) OVER (PARTITION BY k.pkey_src_object)                               AS max_eff_end_dt,
               ROW_NUMBER() OVER (PARTITION BY k.pkey_src_object
                                  ORDER BY k.EFF_BEGIN_DT DESC NULLS FIRST, k.EFF_END_DT DESC NULLS FIRST,
                                           k.CREATE_DT DESC NULLS FIRST)                             AS rn
          FROM keyed k
    )
    SELECT g.CREATE_DT, :l_run_ts, :P_ATTR_TP_AUTH_REP, g.pty_pk, g.max_eff_end_dt /* TIMELINE */,
           g.EFF_BEGIN_DT /* TIMELINE */, 1 /* TIMELINE: exp_Rank.VERSION_SEQ_NUM hard-coded */, g.pkey_src_object,
           g.pkey_src_object, g.CREATE_DT, g.AR_FLAG
      FROM agg g
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_MNG_ATTR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = g.pkey_src_object
     WHERE g.rn = 1
       /* BAD DATA: unique key not yet in the table */
       AND xa.PKEY_SRC_OBJECT IS NULL;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert C_S_TRS_PTY_MNG_ATTR (Auth_Rep_Flag)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

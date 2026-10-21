--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Alt_Id (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Alternate ids of valid TIERS members into C_S_TRS_PTY_RLE_ALT_ID (insert only, never truncated):
--   Read_STG_TRS_D_DC_INDV (custom SQL: MCI, DC_INDV and merged-individual keys of valid members, one row per key
--     keeping the longest, latest SSN)
--   -> lkp_Valid_SSN: the SSN is used only when STG_TRS_H_DC_INDV has it SSA-validated for the individual
--   -> mplt_TRS_Pty_Rle_Alt_Id_Normalization (fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id + the steps below):
--      Medicaid id and member id (both the member id), validated SSN; one row per non-empty id
--        valid rows   -> srtr_Pkey -> exp_Rank / fltr_Rank (TIMELINE) -> target
--        invalid rows -> EXC_STG_BAD_REC_MEMB (written INSIDE the IDQ mapplet; written here by the procedure)
--
-- VALIDATION: rule_MEDICAID_ID_Std (9 characters; the member id is fed as the Medicaid id, so a 10-character member id
--   fails it), rule_Member_Id_Std (9 or 10 characters), rule_USA_SSN_Validation_post_June2011 (common functions 26-28).
-- BAD DATA: an invalid SSN is blanked and then dropped, never logged (docs/common_insights.md 1.6). An invalid Medicaid
--   or member id is not loaded and is logged with the computed code, the looked-up description, type 'Bad Value' and
--   the ALT_ID_TP label as ATTRIBUTE_NAME. When LKP_ALT_ID_LBL does not find a type, the key has an empty type part,
--   so the Medicaid and member rows of one person (same value) get the SAME key: C_S_TRS_PTY_RLE_ALT_ID is unique on
--   (PKEY_SRC_OBJECT, VERSION_SEQ) and IDQ gets the second row rejected. Snowflake does not enforce that unique key:
--   the first row per key is written and keys already in the table are skipped. Unfed ports written as NULL:
--   ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND. The stored source filter INDV_ID = 504937068 is not
--   part of the custom query and is not applied.
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * exp_Rank ranks versions per key but VERSION_SEQ is hard-coded to 1 (the rank is commented out), so fltr_Rank
--     (VERSION_SEQ = 1) keeps EVERY row (docs/common_insights.md 1.7). VERSION_SEQ = 1.
--   * PERIOD_START_DATE / CREATE_DATE / SRC_LAST_UPD_DT = START_DT; PERIOD_END_DATE, PERIOD_REFERENCE_TIME,
--     TIMELINE_ACTION are linked to unfed ports (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SESSSTARTTIME
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- RTR_Invalid_Alt_Ids.Valid_Alt_ID -> srtr_Pkey -> exp_Rank -> fltr_Rank -> exp_Safe_C_S_TRS_Pty_Rle_Alt_Id
        WHEN is_valid AND uq_alt_id THEN
            INTO C_S_TRS_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, SRC_ROWID, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, ALT_ID_TP, ALT_ID_VAL,
                  STS_CD, ALT_ID_TP_FLTR, CV_IND, PTY_RLE_FK, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
                  PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE, CREATOR,
                  HUB_STATE_IND, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object_alt_id, pkey_src_object_alt_id, period_start_date, version_seq, run_ts,
                    alt_id_typ, alt_id_val, sts_cd, alt_id_typ, cv_ind, pty_rle_fk, NULL, NULL, NULL, NULL, NULL,
                    NULL, NULL, NULL, period_start_date, NULL, NULL, period_start_date)
        -- RTR_Invalid_Alt_Ids.Default -> Expression -> Write_EXC_STG_BAD_REC_MEMB (inside the IDQ mapplet)
        WHEN NOT is_valid AND uq_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (MAPPING_NAME, SRC_SYS, RUN_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, EXCEPTION_DESC, EXCEPTION_CODE,
                  EXCEPTION_TYPE, SRC_SYS_ID_1)
            VALUES (mapping_name, src_sys, run_ts, alt_id_val, alt_id_label, dq_excp, dq_excp_cd, exc_type,
                    pkey_src_object_pty)
    SELECT *
      FROM (
        WITH
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_lcv AS (SELECT * FROM TABLE(fn_snow_helper45_common())),
        -- Read_STG_TRS_D_DC_INDV (custom SQL, query mode SEMI)
        all_indv AS (
            SELECT DISTINCT TO_VARCHAR(mci_indv.indv_id) AS pty_pkey, mci_indv.indv_id AS member_id,
                   mci_indv.create_dt, mci_indv.ssn, '1' AS cv_ind
              FROM STG_TRS_D_CV_DC_MCI_INDV mci_indv
            UNION ALL
            SELECT DISTINCT TO_VARCHAR(indv.indv_id) || '|DC_INDV', indv.indv_id, indv.create_dt, indv.ssn, NULL
              FROM STG_TRS_D_DC_INDV indv
            UNION ALL
            SELECT DISTINCT TO_VARCHAR(mrg.old_indv_id), mrg.indv_id, mrg.create_dt, NULL, NULL
              FROM STG_TRS_D_CV_DC_MRG_SPRT_INDV mrg
             WHERE mrg.type_cd = 'ME'
        ),
        de_dup_indv AS (
            SELECT a.pty_pkey, TO_VARCHAR(a.member_id) AS member_id, a.create_dt AS start_dt, a.ssn, a.cv_ind,
                   ROW_NUMBER() OVER (PARTITION BY a.pty_pkey
                                      ORDER BY LENGTH(TO_VARCHAR(a.ssn)) DESC NULLS LAST, a.create_dt DESC) AS key_rn
              FROM all_indv a
              JOIN STG_TRS_VALID_MEMBERS vm ON a.pty_pkey = vm.pty_pk
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
              LEFT JOIN (SELECT DISTINCT INDV_ID, SSN FROM STG_TRS_H_DC_INDV
                          WHERE SSA_VALIDATION_SW = 'Y' AND SSN > 0) v
                     ON v.INDV_ID = fn_snow_helper04_common(s.MEMBER_ID, 0) AND v.SSN = s.SSN
            QUALIFY ROW_NUMBER() OVER (PARTITION BY s.PTY_PKEY ORDER BY v.SSN) = 1
        ),
        -- mplt_TRS_Pty_Rle_Alt_Id_Normalization: rules + NRM_ALT_ID (helper UDTF)
        normalized AS (
            SELECT n.*
              FROM with_ssn w,
                   TABLE(fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id(w.PTY_PKEY, w.START_DT, 'TRS', w.MEMBER_ID,
                                                                       w.valid_ssn, w.MEMBER_ID, NULL, w.CV_IND)) n
        ),
        -- LKP_ALT_ID_LBL + FLTR_Remove_Null_Alt_IDs + RTR_Invalid_Alt_Ids + EXP_safe_tgt
        routed AS (
            SELECT n.PKEY_SRC_OBJECT_PTY AS pkey_src_object_pty, n.PERIOD_START_DATE AS period_start_date,
                   n.ALT_ID_VAL AS alt_id_val, lb.MSTR_REF_CODE AS alt_id_typ, lb.MSTR_REF_LABEL AS alt_id_label,
                   n.DQ_EXCP_CD AS dq_excp_cd, xd.EXCEPTION_DESC AS dq_excp, n.SRC_SYS AS src_sys, n.CV_IND AS cv_ind,
                   NVL(n.PKEY_SRC_OBJECT_PTY, '') || '|Member|' || NVL(lb.MSTR_REF_CODE, '') || '|' || n.ALT_ID_VAL
                                                                                         AS pkey_src_object_alt_id,
                   NVL(n.PKEY_SRC_OBJECT_PTY, '') || '|Member'                           AS pty_rle_fk,
                   /* VALIDATION */ fn_snow_helper03_common(n.DQ_EXCP_CD)                AS is_valid
              FROM normalized n
              LEFT JOIN lkp_lcv lb ON lb.CODE_TYPE = 'ALT_ID_TP' AND lb.MSTR_REF_CODE = n.ALT_ID_TYP
                                  AND lb.SRC_SYS = n.SRC_SYS
              LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = n.DQ_EXCP_CD
             /* BAD DATA: FLTR_Remove_Null_Alt_IDs: NOT ISNULL(ALT_ID_VAL) AND RTRIM(ALT_ID_VAL) <> '' */
             WHERE n.ALT_ID_VAL IS NOT NULL AND RTRIM(n.ALT_ID_VAL) <> ''
        )
        SELECT r.*,
               1 /* TIMELINE: exp_Rank.VERSION_SEQ hard-coded */                  AS version_seq,
               'Issued'                                                            AS sts_cd,
               'Bad Value'                                                         AS exc_type,
               :l_run_ts                                                           AS run_ts,
               :c_mapping                                                          AS mapping_name,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.is_valid, r.pkey_src_object_alt_id
                                       ORDER BY r.alt_id_typ NULLS LAST, r.period_start_date DESC) = 1
                AND xa.PKEY_SRC_OBJECT IS NULL)                                    AS uq_alt_id,
               ROW_NUMBER() OVER (PARTITION BY r.is_valid, r.pkey_src_object_pty, r.dq_excp_cd
                                      ORDER BY r.alt_id_typ NULLS LAST) = 1        AS uq_exc
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
                 ON xa.PKEY_SRC_OBJECT = r.pkey_src_object_alt_id
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TRS_PTY_RLE_ALT_ID, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

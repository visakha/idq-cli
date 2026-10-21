--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr (workflow
-- wf_TRS_Stage_Load_1_Ongoing).
--
-- Phones and e-mail of the TIERS case delta (STG_TRS_D_DC_CASES x STG_TRS_DC_CASE_INDV, valid members only) into
-- C_S_TRS_PTY_RLE_PHN and C_S_TRS_PTY_RLE_EADDR (insert only, never truncated):
--   -> fltr_Hold (TRUE)
--   phones: mplt_Phone_Normalization (fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr + the steps below):
--           main PH_NUM (001), work WORK_PH_NUM || ' ' || WORK_PH_NUM_EXT (002), other OTHER_PH_NUM (003); each
--           through rule_Phone_Std, Filter_Null_Phone_Nums, LOOKUP_CODE_VALUE PHN_USG_TP for the key
--           -> rtr_Valid_Phone_Records
--                Valid_Records (no code) -> mplt_Phone_Consolidation -> srtr_Pty_Rle_Phone + agg_Pty_Rle_Phone
--                                           -> C_S_TRS_PTY_RLE_PHN
--                Default (a code)        -> EXC_STG_BAD_REC_MEMB
--   e-mail: fltr_Null_Emails -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
--                Valid_Records -> mplt_EAddr_Consolidation -> srtr_Pty_Rle_Eaddr + agg_Pty_Rle_Eaddr
--                                 -> C_S_TRS_PTY_RLE_EADDR
--                Default       -> EXC_STG_BAD_REC_MEMB
--
-- VALIDATION: rule_Phone_Std (fn_snow_helper23/24_common with RDM.REF_PHN_AREA_CD). Inside
--   mplt_Member_Pty_Rle_Phn_Normalization the three rule instances get ONLY the phone: their SRC_SYS and USG_TP
--   inputs are not linked, so the TRS / main-number toll-free check of the rule never runs here
--   (docs/common_insights.md 9). rule_email_validation_v01 (fn_snow_helper22_common), routed on the looked-up code.
-- BAD DATA: the work phone is fed as "number extension"; the rule removes the space and its string(10) port keeps
--   the first ten characters, so the extension is dropped and the number itself is validated and written (port
--   precision, docs/common_insights.md 9). Failed phones / e-mails are not loaded, only logged ('Bad Value' for
--   phones). Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND, USG_TP
--   (e-mail). The stored source filter rownum < 100000 is not part of the custom query and is not applied. Unique
--   keys Snowflake does not enforce are applied: C_S_TRS_PTY_RLE_PHN / _EADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and
--   EXC_STG_BAD_REC_MEMB.
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * mplt_Member_Pty_Rle_Phn_Consolidation / mplt_Member_Pty_Rle_EAddr_Consolidation (set level, inlined): drop
--     NULL numbers / addresses, distinct sort on (FILE_DATE - not fed -, PKEY_SRC_OBJECT, PERIOD_START_DATE),
--     running VERSION_SEQ per key; the aggregator keeps the LAST row of the key, so VERSION_SEQ = number of distinct
--     versions of that key.
--   * PERIOD_END_DATE = MAX of a port that is not fed (NULL); PERIOD_REFERENCE_TIME and TIMELINE_ACTION are linked
--     to unfed ports (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_PHN, C_S_TRS_PTY_RLE_EADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- rtr_Valid_Phone_Records.Valid_Records -> consolidation -> agg_Pty_Rle_Phone -> Write_C_S_TRS_PTY_RLE_PHN
        WHEN row_kind = 'PHN' AND rn = 1 AND uq_tgt THEN
            INTO C_S_TRS_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, USG_TP, PHN_TP, PHN_NUM, PREF_LVL, PERIOD_END_DATE, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, period_start_date, version_seq, NULL, NULL, run_ts, NULL,
                    period_start_date, NULL, pkey_src_object, NULL, pty_rle_fk, usg_tp, phn_tp, phn_num, pref_lvl,
                    NULL, period_start_date)
        -- rtr_Valid_Phone_Records.Default -> exp_Stage_Phone_Exceptions -> write_Phone_EXC_STG_BAD_REC_MEMB
        WHEN row_kind = 'PHN_EXC' AND uq_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  SRC_SYS_ID_2, ATTRIBUTE_NAME)
            VALUES (src_sys, exc_code, exc_desc, run_ts, exc_primary_phone, exc_work_phone, exc_secondary_phone,
                    mapping_name, pty_fk, exc_type, usg_tp, period_start_date, phn_num, case_number, exc_attribute)
        -- rtr_Valid_EAddr_Records.Valid_Records -> consolidation -> agg_Pty_Rle_Eaddr -> Write_C_S_TRS_PTY_RLE_EADDR
        WHEN row_kind = 'EADDR' AND rn = 1 AND uq_tgt THEN
            INTO C_S_TRS_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, ELEC_ADDR, USG_TP, ADDR_TP, STS_CD, IS_VLD, PERIOD_END_DATE,
                  SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, period_start_date, version_seq, NULL, NULL, run_ts, NULL,
                    period_start_date, NULL, pkey_src_object, NULL, pty_rle_fk, elec_addr, NULL, eaddr_addr_tp,
                    eaddr_sts_cd, eaddr_is_vld, NULL, period_start_date)
        -- rtr_Valid_EAddr_Records.Default -> exp_Stage_Email_Exceptions -> write_Email_EXC_STG_BAD_REC_MEMB
        WHEN row_kind = 'EADDR_EXC' AND uq_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
                  PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_2)
            VALUES (src_sys, pty_fk, exc_code, exc_desc, run_ts, elec_addr, mapping_name, exc_type, period_start_date,
                    elec_addr, exc_attribute, case_number)
    SELECT *
      FROM (
        WITH
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
        lkp_lcv  AS (SELECT * FROM TABLE(fn_snow_helper45_common())),
        -- read_Staging_Delta_Tables (custom SQL, query mode SEMI) + fltr_Hold (TRUE)
        src AS (
            SELECT DISTINCT I.INDV_ID, C.CASE_NUM, C.CREATE_DT, C.WORK_PH_NUM, C.OTHER_PH_NUM, C.EMAIL, C.PH_NUM,
                   C.OFFICE_NUM, C.WORK_PH_NUM_EXT, TO_VARCHAR(I.INDV_ID) AS PTY_PK
              FROM STG_TRS_D_DC_CASES C
              JOIN STG_TRS_DC_CASE_INDV I ON C.CASE_NUM = I.CASE_NUM
              JOIN STG_TRS_VALID_MEMBERS VM ON TO_VARCHAR(I.INDV_ID) = VM.PTY_PK
        ),
        -- mplt_Phone_Normalization: Normalizer (helper UDTF) ...
        slots AS (
            SELECT n.*
              FROM src s,
                   TABLE(fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr(
                         s.CREATE_DT, s.PTY_PK, 'TRS', TO_VARCHAR(s.CASE_NUM),
                         '001', 'Telephone', s.PH_NUM,
                         '002', 'Telephone', IFF(s.WORK_PH_NUM IS NULL, NULL,
                                                 RTRIM(s.WORK_PH_NUM || ' ' || NVL(s.WORK_PH_NUM_EXT, ''))),
                         '003', 'Telephone', s.OTHER_PH_NUM)) n
        ),
        -- ... rule_Phone_Primary / _Secondary / _Tertiary (only Phone is linked: SRC_SYS and USG_TP are NULL)
        phones_checked AS (
            SELECT sl.*,
                   fn_snow_helper23_common(sl.PHN_NUM_IN)                                          AS phn_num,
                   /* VALIDATION */ fn_snow_helper24_common(fn_snow_helper23_common(sl.PHN_NUM_IN), NULL, NULL,
                                                            ar.NPA_ID, ar.SERVICE)                 AS dq_exception_code
              FROM slots sl
              LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(fn_snow_helper23_common(sl.PHN_NUM_IN), 1, 3)
        ),
        -- ... Filter_Null_Phone_Nums + Lookup_LOOKUP_CODE_VALUE (PHN_USG_TP) + Exp_NEWOUTPUT
        phones AS (
            SELECT p.PERIOD_START_DATE AS period_start_date, p.PTY_FK AS pty_fk, p.PREF_LVL AS pref_lvl,
                   p.USG_TP AS usg_tp, p.PHN_TP AS phn_tp, p.phn_num, p.SRC_SYS AS src_sys_in,
                   p.CASE_NUMBER AS case_number, p.dq_exception_code, xp.EXCEPTION_DESC AS dq_exception,
                   NVL(p.PTY_FK, '') || '|Member'                                                 AS pty_rle_fk,
                   NVL(p.PTY_FK, '') || '|Member|' || NVL(p.PHN_TP, '') || '|' || NVL(u.MSTR_REF_CODE, '') || '|'
                   || p.phn_num                                                                   AS pkey_src_object
              FROM phones_checked p
              LEFT JOIN lkp_lcv u ON u.CODE_TYPE = 'PHN_USG_TP' AND u.MSTR_REF_CODE = p.USG_TP AND u.SRC_SYS = p.SRC_SYS
              LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = p.dq_exception_code
             WHERE p.phn_num IS NOT NULL
        ),
        -- mplt_Phone_Consolidation (fltr_Null_Phone, srtr_Pkey_Src_Object distinct, exp_Rank) on Valid_Records
        phn_versions AS (
            SELECT d.*,
                   /* TIMELINE */ COUNT(*) OVER (PARTITION BY d.pkey_src_object)                    AS version_seq,
                   ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object
                                      ORDER BY d.period_start_date DESC NULLS FIRST, d.pty_rle_fk DESC, d.usg_tp DESC,
                                               d.phn_tp DESC, d.phn_num DESC, d.pref_lvl DESC)      AS rn
              FROM (SELECT DISTINCT p.period_start_date, p.pkey_src_object, p.pty_rle_fk, p.usg_tp, p.phn_tp,
                           p.phn_num, p.pref_lvl
                      FROM phones p
                     WHERE p.dq_exception_code IS NULL) d
        ),
        -- fltr_Null_Emails: not isnull(rtrim(ltrim(ELEC_ADDR))) + rule_email_validation_v01
        emails AS (
            SELECT s.*,
                   fn_snow_helper22_common(s.EMAIL)                                AS em
              FROM src s
             WHERE TRIM(s.EMAIL) IS NOT NULL
        ),
        emails_checked AS (
            SELECT e.*,
                   e.em:email_address::VARCHAR                                     AS std_email,
                   xe.EXCEPTION_CODE AS em_exc_code, xe.EXCEPTION_DESC AS em_exc_desc, xe.EXCEPTION_TYPE AS em_exc_type
              FROM emails e
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = e.em:exception_code::VARCHAR
        ),
        -- mplt_EAddr_Consolidation (fltr_Null_Email, srtr_Pkey_Src_Object distinct, exp_Version_Seq) on Valid_Records
        eaddr_versions AS (
            SELECT d.*,
                   /* TIMELINE */ COUNT(*) OVER (PARTITION BY d.pkey_src_object)                    AS version_seq,
                   ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object
                                      ORDER BY d.period_start_date DESC NULLS FIRST, d.pty_rle_fk DESC,
                                               d.elec_addr DESC)                                    AS rn
              FROM (SELECT DISTINCT e.CREATE_DT AS period_start_date,
                           TO_VARCHAR(e.INDV_ID) || '|Member|001|' || NVL(e.EMAIL, '') AS pkey_src_object,
                           e.PTY_PK || '|Member' AS pty_rle_fk, e.std_email AS elec_addr
                      FROM emails_checked e
                     WHERE e.em_exc_code IS NULL
                       AND e.std_email IS NOT NULL) d
        ),
        all_kinds AS (
            SELECT 'PHN' AS row_kind, v.pkey_src_object, v.period_start_date, v.version_seq, v.rn, v.pty_rle_fk,
                   v.usg_tp, v.phn_tp, v.phn_num, v.pref_lvl, NULL::VARCHAR AS elec_addr, NULL::VARCHAR AS pty_fk,
                   NULL::VARCHAR AS case_number, NULL::VARCHAR AS exc_code, NULL::VARCHAR AS exc_desc,
                   NULL::VARCHAR AS exc_type
              FROM phn_versions v
            UNION ALL
            SELECT 'PHN_EXC', p.pkey_src_object, p.period_start_date, NULL, NULL, p.pty_rle_fk, p.usg_tp, p.phn_tp,
                   p.phn_num, p.pref_lvl, NULL, p.pty_fk, p.case_number, p.dq_exception_code, p.dq_exception,
                   'Bad Value'
              FROM phones p
             WHERE p.dq_exception_code IS NOT NULL
            UNION ALL
            SELECT 'EADDR', v.pkey_src_object, v.period_start_date, v.version_seq, v.rn, v.pty_rle_fk, NULL, NULL,
                   NULL, NULL, v.elec_addr, NULL, NULL, NULL, NULL, NULL
              FROM eaddr_versions v
            UNION ALL
            SELECT 'EADDR_EXC', NULL, e.CREATE_DT, NULL, NULL, NULL, NULL, NULL, NULL, NULL, e.EMAIL,
                   TO_VARCHAR(e.INDV_ID), TO_VARCHAR(e.CASE_NUM), e.em_exc_code, e.em_exc_desc, e.em_exc_type
              FROM emails_checked e
             WHERE e.em_exc_code IS NOT NULL
        )
        SELECT a.*,
               'TRS'                                                 AS src_sys,
               :l_run_ts                                             AS run_ts,
               :c_mapping                                            AS mapping_name,
               '001'                                                 AS eaddr_addr_tp,
               'Active'                                              AS eaddr_sts_cd,
               'Y'                                                   AS eaddr_is_vld,
               IFF(a.pref_lvl = 'Primary', a.phn_num, NULL)          AS exc_primary_phone,
               IFF(a.usg_tp = 'Work', a.phn_num, NULL)               AS exc_work_phone,
               IFF(a.pref_lvl = 'Secondary', a.phn_num, NULL)        AS exc_secondary_phone,
               IFF(a.row_kind = 'EADDR_EXC', 'Email',
                   DECODE(a.usg_tp, '001', 'Main Phone', '002', 'Work Phone', '003', 'Other Phone')) AS exc_attribute,
               /* BAD DATA: unique keys Snowflake does not enforce */
               xph.PKEY_SRC_OBJECT IS NULL AND xea.PKEY_SRC_OBJECT IS NULL                        AS uq_tgt,
               ROW_NUMBER() OVER (PARTITION BY a.row_kind, a.pty_fk, a.case_number, a.usg_tp, a.exc_type, a.exc_code
                                      ORDER BY a.period_start_date DESC) = 1                       AS uq_exc
          FROM all_kinds a
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_PHN) xph
                 ON a.row_kind = 'PHN' AND xph.PKEY_SRC_OBJECT = a.pkey_src_object AND xph.VERSION_SEQ = a.version_seq
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_EADDR) xea
                 ON a.row_kind = 'EADDR' AND xea.PKEY_SRC_OBJECT = a.pkey_src_object AND xea.VERSION_SEQ = a.version_seq
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TRS_PTY_RLE_PHN, C_S_TRS_PTY_RLE_EADDR, exceptions)',
                                   :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

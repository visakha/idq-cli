--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Phones and e-mail of the TIERS case delta (STG_TRS_D_DC_CASES x STG_TRS_DC_CASE_INDV, valid members only) into
-- C_S_TRS_PTY_RLE_PHN and C_S_TRS_PTY_RLE_EADDR (both insert only, never truncated):
--   -> fltr_Hold (TRUE)
--   phones: mplt_Phone_Normalization (TABLE(fn_dq_norm_member_phn(...))): main PH_NUM (001), work
--           WORK_PH_NUM || ' ' || WORK_PH_NUM_EXT (002), other OTHER_PH_NUM (003); each through rule_Phone_Std
--           -> rtr_Valid_Phone_Records
--                Valid_Records (no code) -> mplt_Phone_Consolidation -> srtr_Pty_Rle_Phone + agg_Pty_Rle_Phone
--                                           -> C_S_TRS_PTY_RLE_PHN
--                Default (a code)        -> EXC_STG_BAD_REC_MEMB
--   e-mail: fltr_Null_Emails -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
--                Valid_Records -> mplt_EAddr_Consolidation -> srtr_Pty_Rle_Eaddr + agg_Pty_Rle_Eaddr
--                                 -> C_S_TRS_PTY_RLE_EADDR
--                Default       -> EXC_STG_BAD_REC_MEMB
--
-- mplt_Member_Pty_Rle_Phn_Consolidation / mplt_Member_Pty_Rle_EAddr_Consolidation are set-level mapplets, inlined
-- here: drop NULL numbers / addresses, distinct sort on (FILE_DATE - not fed, NULL -, PKEY_SRC_OBJECT,
-- PERIOD_START_DATE), running VERSION_SEQ per key, LAST_UPDATE_DATE = SYSTIMESTAMP, SRC_ROWID = key.
--
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * VERSION_SEQ: the consolidation mapplets number the distinct versions of a key 1, 2, 3, ... in
--     PERIOD_START_DATE order; the aggregator keeps the LAST row of the key, so VERSION_SEQ = number of distinct
--     versions of that key.
--   * PERIOD_END_DATE = MAX of a port that is not fed (NULL); PERIOD_REFERENCE_TIME and TIMELINE_ACTION are linked
--     to unfed ports (NULL).
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND, USG_TP (e-mail).
-- The stored source filter rownum < 100000 is not part of the custom query and is not applied.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP()
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_PHN, C_S_TRS_PTY_RLE_EADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- rtr_Valid_Phone_Records.Valid_Records -> consolidation -> agg_Pty_Rle_Phone -> Write_C_S_TRS_PTY_RLE_PHN
        WHEN row_kind = 'PHN' AND rn = 1 THEN
            INTO C_S_TRS_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, USG_TP, PHN_TP, PHN_NUM, PREF_LVL, PERIOD_END_DATE, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, period_start_date /* TIMELINE */,
                    version_seq /* TIMELINE: running version per key */, NULL /* TIMELINE */, NULL /* TIMELINE */,
                    l_run_ts, NULL, period_start_date, NULL, pkey_src_object, NULL, pty_rle_fk, usg_tp, phn_tp,
                    phn_num, pref_lvl, NULL /* TIMELINE: MAX of unfed */, period_start_date)
        -- rtr_Valid_Phone_Records.Default -> exp_Stage_Phone_Exceptions -> write_Phone_EXC_STG_BAD_REC_MEMB
        WHEN row_kind = 'PHN_EXC' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  SRC_SYS_ID_2, ATTRIBUTE_NAME)
            VALUES ('TRS', exc_code, exc_desc, l_run_ts,
                    CASE WHEN pref_lvl = 'Primary' THEN phn_num END,
                    CASE WHEN usg_tp = 'Work' THEN phn_num END,
                    CASE WHEN pref_lvl = 'Secondary' THEN phn_num END,
                    c_mapping, pty_fk, 'Bad Value', usg_tp, period_start_date, phn_num, case_number,
                    CASE usg_tp WHEN '001' THEN 'Main Phone' WHEN '002' THEN 'Work Phone' WHEN '003' THEN 'Other Phone' END)
        -- rtr_Valid_EAddr_Records.Valid_Records -> consolidation -> agg_Pty_Rle_Eaddr -> Write_C_S_TRS_PTY_RLE_EADDR
        WHEN row_kind = 'EADDR' AND rn = 1 THEN
            INTO C_S_TRS_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, ELEC_ADDR, USG_TP, ADDR_TP, STS_CD, IS_VLD, PERIOD_END_DATE,
                  SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, period_start_date /* TIMELINE */,
                    version_seq /* TIMELINE: running version per key */, NULL /* TIMELINE */, NULL /* TIMELINE */,
                    l_run_ts, NULL, period_start_date, NULL, pkey_src_object, NULL, pty_rle_fk, elec_addr, NULL,
                    '001', 'Active', 'Y', NULL /* TIMELINE: MAX of unfed */, period_start_date)
        -- rtr_Valid_EAddr_Records.Default -> exp_Stage_Email_Exceptions -> write_Email_EXC_STG_BAD_REC_MEMB
        WHEN row_kind = 'EADDR_EXC' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
                  PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_2)
            VALUES ('TRS', pty_fk, exc_code, exc_desc, l_run_ts, elec_addr, c_mapping, exc_type, period_start_date,
                    elec_addr, 'Email', case_number)
    WITH
    -- read_Staging_Delta_Tables (custom SQL, query mode SEMI) + fltr_Hold (TRUE)
    src AS (
        SELECT DISTINCT I.INDV_ID, C.CASE_NUM, C.CREATE_DT, C.WORK_PH_NUM, C.OTHER_PH_NUM, C.EMAIL, C.PH_NUM,
               C.OFFICE_NUM, C.WORK_PH_NUM_EXT, TO_CHAR(I.INDV_ID) AS PTY_PK
          FROM STG_TRS_D_DC_CASES C
          JOIN STG_TRS_DC_CASE_INDV I ON C.CASE_NUM = I.CASE_NUM
          JOIN STG_TRS_VALID_MEMBERS VM ON TO_CHAR(I.INDV_ID) = VM.PTY_PK
    ),
    -- mplt_Phone_Normalization (exp_Stage_Source_Attributes feeds the three slots)
    phones AS (
        SELECT n.*
          FROM src s
         CROSS APPLY TABLE(fn_dq_norm_member_phn(
                     s.CREATE_DT, s.PTY_PK, 'TRS', s.CASE_NUM,
                     '001', 'Telephone', s.PH_NUM,
                     '002', 'Telephone', CASE WHEN s.WORK_PH_NUM IS NULL THEN NULL
                                              ELSE RTRIM(s.WORK_PH_NUM || ' ' || s.WORK_PH_NUM_EXT) END,
                     '003', 'Telephone', s.OTHER_PH_NUM)) n
    ),
    -- mplt_Phone_Consolidation (fltr_Null_Phone, srtr_Pkey_Src_Object distinct, exp_Rank) on Valid_Records
    phn_versions AS (
        SELECT d.*,
               COUNT(*) OVER (PARTITION BY d.pkey_src_object)                                       AS version_seq,
               ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object
                                  ORDER BY d.period_start_date DESC NULLS FIRST, d.pty_rle_fk DESC, d.usg_tp DESC,
                                           d.phn_tp DESC, d.phn_num DESC, d.pref_lvl DESC)          AS rn
          FROM (SELECT DISTINCT p.period_start_date, p.pkey_src_object, p.pty_rle_fk, p.usg_tp, p.phn_tp, p.phn_num,
                       p.pref_lvl
                  FROM phones p
                 WHERE p.dq_exception_code IS NULL
                   AND p.phn_num IS NOT NULL) d
    ),
    -- fltr_Null_Emails + rule_email_validation_v01
    emails AS (
        SELECT /*+ NO_MERGE */
               s.*,
               fn_dq_valid_email(s.EMAIL) AS em
          FROM src s
         WHERE RTRIM(LTRIM(s.EMAIL)) IS NOT NULL
    ),
    -- mplt_EAddr_Consolidation (fltr_Null_Email, srtr_Pkey_Src_Object distinct, exp_Version_Seq) on Valid_Records
    eaddr_versions AS (
        SELECT d.*,
               COUNT(*) OVER (PARTITION BY d.pkey_src_object)                                       AS version_seq,
               ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object
                                  ORDER BY d.period_start_date DESC NULLS FIRST, d.pty_rle_fk DESC,
                                           d.elec_addr DESC)                                        AS rn
          FROM (SELECT DISTINCT e.CREATE_DT AS period_start_date,
                       e.INDV_ID || '|Member|' || '001' || '|' || e.EMAIL AS pkey_src_object,
                       e.PTY_PK || '|Member' AS pty_rle_fk, e.em.email_address AS elec_addr
                  FROM emails e
                 WHERE e.em.exception_code IS NULL
                   AND e.em.email_address IS NOT NULL) d
    )
    SELECT 'PHN' AS row_kind, v.pkey_src_object, v.period_start_date, v.version_seq, v.rn, v.pty_rle_fk, v.usg_tp,
           v.phn_tp, v.phn_num, v.pref_lvl, CAST(NULL AS VARCHAR2(200)) AS elec_addr,
           CAST(NULL AS VARCHAR2(255)) AS pty_fk, CAST(NULL AS VARCHAR2(50)) AS case_number,
           CAST(NULL AS VARCHAR2(300)) AS exc_code, CAST(NULL AS VARCHAR2(255)) AS exc_desc,
           CAST(NULL AS VARCHAR2(100)) AS exc_type
      FROM phn_versions v
    UNION ALL
    SELECT 'PHN_EXC', p.pkey_src_object, p.period_start_date, NULL, NULL, p.pty_rle_fk, p.usg_tp, p.phn_tp,
           p.phn_num, p.pref_lvl, NULL, p.pty_fk, p.case_number, p.dq_exception_code, p.dq_exception, NULL
      FROM phones p
     WHERE p.dq_exception_code IS NOT NULL
    UNION ALL
    SELECT 'EADDR', v.pkey_src_object, v.period_start_date, v.version_seq, v.rn, v.pty_rle_fk, NULL, NULL, NULL,
           NULL, v.elec_addr, NULL, NULL, NULL, NULL, NULL
      FROM eaddr_versions v
    UNION ALL
    SELECT 'EADDR_EXC', NULL, e.CREATE_DT, NULL, NULL, NULL, NULL, NULL, NULL, NULL, e.EMAIL, TO_CHAR(e.INDV_ID),
           TO_CHAR(e.CASE_NUM), e.em.exception_code, e.em.exception_desc, e.em.exception_type
      FROM emails e
     WHERE e.em.exception_code IS NOT NULL;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TRS_PTY_RLE_PHN, C_S_TRS_PTY_RLE_EADDR, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr;
/

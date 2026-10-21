--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Alt_Id (workflow wf_ECI_Stage_Load).
--
-- Alternate ids of the ECI parties into C_S_ECI_PTY_RLE_ALT_ID (truncated first):
--   Read_STG_ECI_D_CHILD (custom SQL: child ECI id 018, child SSN 004, Medicaid number 002 via STG_ECI_SN_CASE,
--                         family ECI id 019)
--     -> Filter: party (first 11 characters of the role key, '|' trimmed) not in STG_ECI_PTY_INACTIVE_STS
--     -> Rtr_ALT_ID_Type
--          CHILD_SSN    (004) -> rule_USA_SSN_Validation_post_June2011 -> RTR_Valid_SSN
--                                 Valid   -> Union -> target
--                                 Invalid -> Exp_SSN_Exceptions -> EXC_STG_BAD_REC_MEMB
--          ECI_IDs  (018/019) -> Union -> target
--          MEDICAID_NBR (002) -> rule_MEDICAID_ID_Std -> RTR_Valid_Medicaid_ID
--                                 Valid   -> Union -> target
--                                 Invalid -> Exp_Invalid_MedicaidId -> EXC_STG_BAD_REC_MEMB
--          Default            -> not linked (no other type is read)
-- The id written is the SOURCE value (the standardized SSN / Medicaid id is only used for validation).
--
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = source DATE_CREATED.
--
-- IDQ quirks kept: the SSN exception row has no RUN_DATE linked (NULL) and writes the EXCEPTION_CODE returned by the
-- EXC_LOOKUP_CODE_VALUE lookup (NULL when Invalid_SSN is not configured); the Medicaid exception row writes the
-- computed code.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP()
BEGIN
    sp_ors_helper01_common('C_S_ECI_PTY_RLE_ALT_ID');

    INSERT ALL
        -- Union_Valid_ALT_ID_Type (SSN valid, ECI ids, Medicaid valid) -> Exp_STG_ALT_ID_Type_Load -> target
        WHEN (ALT_ID_TP = '004' AND ssn_exception_code IS NULL)
          OR ALT_ID_TP IN ('018', '019')
          OR (ALT_ID_TP = '002' AND medicaid_exception_code IS NULL) THEN
            INTO C_S_ECI_PTY_RLE_ALT_ID
                 (PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE, PKEY_SRC_OBJECT, SRC_ROWID,
                  VERSION_SEQ, STS_CD, HUB_STATE_IND, SRC_LAST_UPD_DT, ALT_ID_TP_FLTR, PERIOD_START_DATE)
            VALUES (PTY_REL_FK, ALT_ID_TP, ALT_ID_VAL, DATE_CREATED, l_run_ts, PKEY_SRC_OBJECT,
                    TO_CHAR(ID) || '|' || ALT_ID_TP, 1 /* TIMELINE: VERSION_SEQ */, 'Issued', 1,
                    NVL(DATE_MODIFIED, DATE_CREATED), ALT_ID_TP, DATE_CREATED /* TIMELINE */)
        -- RTR_Valid_SSN.Invalid_CHILD_SSN -> Exp_SSN_Exceptions -> Write_EXC_STG_BAD_REC_MEMB_SSN (RUN_DATE unlinked)
        WHEN ALT_ID_TP = '004' AND ssn_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, SRC_SYS, ATTRIBUTE_NAME, MAPPING_NAME,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2)
            VALUES (fn_ors_helper08_common(ssn_exception_code), fn_ors_helper04_common(ssn_exception_code),
                    fn_ors_helper05_common(ssn_exception_code), 'ECI', 'ALT_ID_Type_SSN', c_mapping, ALT_ID_VAL,
                    PKEY_SRC_OBJECT, PTY_REL_FK)
        -- RTR_Valid_Medicaid_ID.INVALID_Medicaid_Id -> Exp_Invalid_MedicaidId -> Write_EXC_STG_BAD_REC_MEMB_MedicaidId
        WHEN ALT_ID_TP = '002' AND medicaid_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, MAPPING_NAME, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, SRC_SYS_ID_2, SRC_SYS_ID_1)
            VALUES ('ECI', l_run_ts, medicaid_exception_type, medicaid_exception_code, medicaid_exception_desc,
                    c_mapping, ALT_ID_VAL, 'ALT_ID_TP_MedicaidId', PTY_REL_FK, PKEY_SRC_OBJECT)
    WITH
    -- Read_STG_ECI_D_CHILD (custom SQL, query mode SEMI; port ID_CHILD = column ID)
    src AS (
        SELECT ID_CHILD AS ID, LPAD(ID_CHILD, 10, '0') || '|Member' AS PTY_REL_FK,
               LPAD(ID_CHILD, 10, '0') AS SRC_KEY_SFX, '018' AS ALT_ID_TP, LPAD(ID_CHILD, 10, '0') AS ALT_ID_VAL,
               DATE_CREATED, DATE_MODIFIED,
               LPAD(ID_CHILD, 10, '0') || '|Member' || '|018' || '|' || LPAD(ID_CHILD, 10, '0') AS PKEY_SRC_OBJECT
          FROM STG_ECI_D_CHILD
        UNION ALL
        SELECT ID_CHILD, LPAD(ID_CHILD, 10, '0') || '|Member', LPAD(ID_CHILD, 10, '0'), '004', CHILD_SSN,
               DATE_CREATED, DATE_MODIFIED,
               LPAD(ID_CHILD, 10, '0') || '|Member' || '|004' || '|' || LPAD(ID_CHILD, 10, '0')
          FROM STG_ECI_D_CHILD
         WHERE CHILD_SSN IS NOT NULL
        UNION ALL
        SELECT ID_CHILD, LPAD(ID_CHILD, 10, '0') || '|Member', LPAD(ID_MEDICAID, 9, '0'), '002', MEDICAID_NBR,
               M.DATE_CREATED, M.DATE_MODIFIED,
               LPAD(ID_CHILD, 10, '0') || '|Member' || '|002' || '|' || LPAD(ID_MEDICAID, 10, '0')
          FROM STG_ECI_D_MEDICAID M
         INNER JOIN STG_ECI_SN_CASE C ON M.ID_CASE = C.ID_CASE
        UNION ALL
        SELECT ID_FAMILY, LPAD(ID_FAMILY, 10, '0') || 'F|Member', LPAD(ID_FAMILY, 10, '0'), '019',
               LPAD(ID_FAMILY, 10, '0'), DATE_CREATED, DATE_MODIFIED,
               LPAD(ID_FAMILY, 10, '0') || 'F|Member' || '|019' || '|' || LPAD(ID_FAMILY, 10, '0')
          FROM STG_ECI_D_FAMILY
    ),
    -- exp_ECI_Pty_Rle_Alt_Id + Lkp_STG_ECI_PTY_INACTIVE_STS + Filter
    active AS (
        SELECT s.*
          FROM src s
         WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = RTRIM(SUBSTR(s.PTY_REL_FK, 1, 11), '|') AND i.ROWID_SYSTEM = 'ECI'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    -- rule_USA_SSN_Validation_post_June2011 (004 rows) + exp_validate_ssn; rule_MEDICAID_ID_Std (002 rows)
    dq AS (
        SELECT /*+ NO_MERGE */
               a.*,
               CASE WHEN a.ALT_ID_TP = '004' THEN fn_dq_valid_ssn(a.ALT_ID_VAL) END        AS ssn,
               CASE WHEN a.ALT_ID_TP = '002' THEN fn_dq_std_medicaid_id(a.ALT_ID_VAL) END  AS mcd
          FROM active a
    )
    SELECT d.*,
           CASE WHEN d.ssn.ssn_status = 'Invalid' THEN 'Invalid_SSN' END  AS ssn_exception_code,
           d.mcd.exception_code                                         AS medicaid_exception_code,
           d.mcd.exception_type                                         AS medicaid_exception_type,
           d.mcd.exception_desc                                         AS medicaid_exception_desc
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_ECI_PTY_RLE_ALT_ID, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id;
/

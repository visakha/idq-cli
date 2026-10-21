--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr (workflow wf_ECI_Stage_Load).
--
-- Phones and e-mail addresses of the ECI parties (V_ECI_ETL_SRC_FAMILY_PHONE) into C_S_ECI_PTY_RLE_PHN and
-- C_S_ECI_PTY_RLE_EADDR (both insert only, never truncated):
--   -> fil_deactivated_status: party not in STG_ECI_PTY_INACTIVE_STS
--   -> rtr_Phone_Email
--        Email_Group (PHONE_EMAIL_TYPE = 'EADDRESS') -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
--             Valid_Records (no looked-up exception code) -> C_S_ECI_PTY_RLE_EADDR
--             Bad_Records                                 -> EXC_STG_BAD_REC_MEMB
--        Default (every other row, including a NULL type)  -> rule_Phone_Std (7-digit numbers get '000' prefixed)
--             -> RTR_Valid_PhoneNumbers
--             Good_Records      (no code, or 'Missing_AreaCode') -> C_S_ECI_PTY_RLE_PHN
--             Bad_Phone_Records (any code)                       -> EXC_STG_BAD_REC_MEMB
--        A 'Missing_AreaCode' phone matches both groups, so it is loaded AND logged (IDQ router semantics).
--        An e-mail whose 'Invalid_Email' code is not configured in EXC_LOOKUP_CODE_VALUE is treated as valid
--        (the router tests the looked-up code).
--
-- TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = source PERIOD_START_DATE; the e-mail
-- PERIOD_REFERENCE_TIME port is not fed in IDQ (NULL).
-- The phone exception SRC_SYS_ID_1 is linked to an unfed port (PTY_FK) in IDQ and is written NULL.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP()
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Default -> RTR_Valid_PhoneNumbers.Good_Records -> exp_Stage_Target_PhoneNumbers -> Write_C_S_ECI_PTY_RLE_PHN
        WHEN is_email = 0 AND (phone_exception_code IS NULL OR phone_exception_code = 'Missing_AreaCode') THEN
            INTO C_S_ECI_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, PHN_NUM_EXT, HUB_STATE_IND)
            VALUES (pkey_src_object, PERIOD_START_DATE /* TIMELINE */, '1' /* TIMELINE: VERSION_SEQ */, l_run_ts,
                    l_run_ts, src_rowid, pty_rle_fk, PHONE_TP, USG_TP, std_phone, PREF_LVL, PERIOD_START_DATE,
                    WORK_EXT, 1)
        -- Default -> RTR_Valid_PhoneNumbers.Bad_Phone_Records -> exp_Stage_Phone_Exceptions
        WHEN is_email = 0 AND phone_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  SRC_SYS_ID_2, ATTRIBUTE_NAME)
            VALUES ('ECI', phone_exception_code, phone_exception_desc, l_run_ts,
                    CASE WHEN PREF_LVL = 'Primary' THEN std_phone END,
                    CASE WHEN USG_TP = 'Work' THEN std_phone END,
                    CASE WHEN PREF_LVL = 'Secondary' THEN std_phone END,
                    c_mapping, NULL /* PTY_FK unfed in IDQ */, 'Bad Value', USG_TP, PERIOD_START_DATE, std_phone,
                    ID_CASE,
                    CASE USG_TP WHEN '001' THEN 'Main Phone' WHEN '002' THEN 'Work Phone' WHEN '003' THEN 'Other Phone' END)
        -- Email_Group -> rtr_Valid_EAddr_Records.Valid_Records -> exp_Stage_Target_EAddr_Attributes
        WHEN is_email = 1 AND email_exception_code IS NULL THEN
            INTO C_S_ECI_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  PTY_RLE_FK, ELEC_ADDR, USG_TP, ADDR_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, VERSION_SEQ, HUB_STATE_IND)
            VALUES (pkey_src_object, PERIOD_START_DATE /* TIMELINE */, NULL /* TIMELINE: unfed */, l_run_ts,
                    l_run_ts, pkey_src_object, pty_rle_fk, std_email, NULL, '001', 'Active', 'Y',
                    PERIOD_START_DATE, '1' /* TIMELINE: VERSION_SEQ */, 1)
        -- Email_Group -> rtr_Valid_EAddr_Records.Bad_Records -> exp_Stage_Email_Exceptions
        WHEN is_email = 1 AND email_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME,
                  EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME)
            VALUES ('ECI', ID_FAMILY_PHONE, email_exception_code, email_exception_desc, l_run_ts, PHONE_EMAIL,
                    c_mapping, email_exception_type, PERIOD_START_DATE, PHONE_EMAIL, 'Email')
    WITH
    -- Read_V_ECI_ETL_SRC_FAMILY_PHONE + exp_Stage_Source_Attributes
    src AS (
        SELECT s.SOURCE_TABLE, s.WORK_EXT, s.PHONE_TP, s.USG_TP, s.PREF_LVL, s.PERIOD_START_DATE,
               s.PHONE_EMAIL_TYPE, s.PHONE_EMAIL, s.ID_CASE, s.ID, s.ID_FAMILY_PHONE,
               CASE WHEN s.PHONE_EMAIL_TYPE = 'EADDRESS' THEN 1 ELSE 0 END                AS is_email,
               s.ID || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END               AS pty_src_key,
               s.ID || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END || '|Member'  AS pty_rle_fk,
               CASE WHEN s.PHONE_EMAIL_TYPE = 'EADDRESS'
                    THEN s.ID || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END || '|Member' || '|' || '001'
                         || '|' || s.ID_FAMILY_PHONE || '|' || LTRIM(RTRIM(s.PHONE_EMAIL))
                    ELSE s.ID || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END || '|Member' || '|'
                         || s.PHONE_TP || '|' || s.USG_TP || '|' || s.ID_FAMILY_PHONE || '|' || LTRIM(RTRIM(s.PHONE_EMAIL))
               END                                                                        AS pkey_src_object,
               -- o_SRC_ROWID: same as the key but WITHOUT trimming the phone / e-mail
               CASE WHEN s.PHONE_EMAIL_TYPE = 'EADDRESS'
                    THEN s.ID || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END || '|Member' || '|' || '001'
                         || '|' || s.ID_FAMILY_PHONE || '|' || s.PHONE_EMAIL
                    ELSE s.ID || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END || '|Member' || '|'
                         || s.PHONE_TP || '|' || s.USG_TP || '|' || s.ID_FAMILY_PHONE || '|' || s.PHONE_EMAIL
               END                                                                        AS src_rowid
          FROM V_ECI_ETL_SRC_FAMILY_PHONE s
    ),
    -- Lkp_STG_ECI_PTY_INACTIVE_STS + fil_deactivated_status
    active AS (
        SELECT s.*
          FROM src s
         WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = s.pty_src_key AND i.ROWID_SYSTEM = 'ECI'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    -- rule_Phone_Std (phone rows; Expression.PHONE_EMAIL1 prefixes '000' to 7-digit numbers) and
    -- rule_email_validation_v01 (e-mail rows)
    dq AS (
        SELECT /*+ NO_MERGE */
               a.*,
               CASE WHEN a.is_email = 0 THEN
                    fn_dq_std_phone(CASE WHEN LENGTH(a.PHONE_EMAIL) = 7 THEN '000' || a.PHONE_EMAIL
                                         ELSE a.PHONE_EMAIL END, 'ECI', a.USG_TP) END   AS ph,
               CASE WHEN a.is_email = 1 THEN fn_dq_valid_email(a.PHONE_EMAIL) END        AS em
          FROM active a
    )
    SELECT d.*,
           d.ph.phone                 AS std_phone,
           d.ph.phone_exception_code  AS phone_exception_code,
           d.ph.phone_exception_desc  AS phone_exception_desc,
           d.em.email_address         AS std_email,
           d.em.exception_code        AS email_exception_code,
           d.em.exception_desc        AS email_exception_desc,
           d.em.exception_type        AS email_exception_type
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr;
/

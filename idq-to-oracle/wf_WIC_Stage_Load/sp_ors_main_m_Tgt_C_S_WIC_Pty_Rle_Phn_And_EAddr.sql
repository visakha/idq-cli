--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr (workflow wf_WIC_Stage_Load).
--
-- Each WIC row (V_WIC_ETL_SRC) gives one phone and possibly one e-mail:
--   -> fil_deactivated_status: party not in STG_WIC_PTY_INACTIVE_STS, then two branches
--   phone : rule_Phone_Std (usage 001 'Telephone', 'Primary') on EVERY active row (there is no null-phone filter,
--           so a missing phone is validated and, when the rule flags it, logged) -> RTR_Valid_PhoneNumbers
--           Good_Records (no code, or 'Missing_AreaCode') -> C_S_WIC_PTY_RLE_PHN
--           Bad_Phone_Records (any code)                 -> EXC_STG_BAD_REC_MEMB
--   e-mail: Filt_null_email -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
--           Valid_Records -> C_S_WIC_PTY_RLE_EADDR ; Bad_Records -> EXC_STG_BAD_REC_MEMB
-- Both C_S targets are only inserted into; nothing is truncated.
--
-- TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = DATEKEY.
-- The e-mail key uses the e-mail as read (no trim), unlike ECI.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP()
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_WIC_PTY_RLE_PHN, C_S_WIC_PTY_RLE_EADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- RTR_Valid_PhoneNumbers.Good_Records -> Write_C_S_WIC_PTY_RLE_PHN
        WHEN phone_exception_code IS NULL OR phone_exception_code = 'Missing_AreaCode' THEN
            INTO C_S_WIC_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, PTY_RLE_FK, PHN_TP,
                  USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, HUB_STATE_IND)
            VALUES (phn_pkey, DATEKEY /* TIMELINE */, '1' /* TIMELINE: VERSION_SEQ */, l_run_ts, phn_pkey,
                    pty_rle_fk, 'Telephone', '001', std_phone, 'Primary', DATEKEY, 1)
        -- RTR_Valid_PhoneNumbers.Bad_Phone_Records -> write_Phone_EXC_STG_BAD_REC_MEMB
        WHEN phone_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, SRC_SYS_ID_2)
            VALUES ('WIC', phone_exception_code, phone_exception_desc, l_run_ts,
                    std_phone /* PREF_LVL is 'Primary' */, NULL /* USG_TP is '001' */, NULL, c_mapping, PTY_SRC_KEY,
                    'Bad Value', '001', DATEKEY, std_phone, 'Main Phone', FID)
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Valid_Records -> Write_C_S_WIC_PTY_RLE_EADDR
        WHEN EMAIL IS NOT NULL AND email_exception_code IS NULL THEN
            INTO C_S_WIC_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, ELEC_ADDR, USG_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, ADDR_TP)
            VALUES (eaddr_pkey, DATEKEY /* TIMELINE */, '1' /* TIMELINE: VERSION_SEQ */, l_run_ts, l_run_ts,
                    eaddr_pkey, 1, pty_rle_fk, std_email, NULL, 'Active', 'Y', DATEKEY, '001')
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Bad_Records -> write_Email_EXC_STG_BAD_REC_MEMB
        WHEN EMAIL IS NOT NULL AND email_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
                  PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
            VALUES ('WIC', email_exception_code, email_exception_desc, l_run_ts, EMAIL, c_mapping,
                    email_exception_type, DATEKEY, EMAIL, 'Email', PTY_SRC_KEY, FID)
    WITH
    -- Read_V_WIC_ETL_SRC + exp_Stage_Source_Attributes + exp_Phone_Email_Keys + fil_deactivated_status
    src AS (
        SELECT v.SOURCE_TABLE, v.ID, v.PTY_SRC_KEY, v.DATEKEY, v.FID, v.PHONE, v.EMAIL,
               v.PTY_SRC_KEY || '|Member'                                                              AS pty_rle_fk,
               v.PTY_SRC_KEY || '|Member' || '|' || 'Telephone' || '|' || '001' || '|' || v.FID || '|'
               || LTRIM(RTRIM(v.PHONE))                                                                AS phn_pkey,
               v.PTY_SRC_KEY || '|Member' || '|' || '001' || '|' || v.FID || '|' || v.EMAIL            AS eaddr_pkey
          FROM V_WIC_ETL_SRC v
         WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    dq AS (
        SELECT /*+ NO_MERGE */
               s.*,
               fn_dq_std_phone(s.PHONE, 'WIC', '001')                                   AS ph,
               CASE WHEN s.EMAIL IS NOT NULL THEN fn_dq_valid_email(s.EMAIL) END        AS em
          FROM src s
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
    sp_ors_helper02_common(c_mapping, 'insert (C_S_WIC_PTY_RLE_PHN, C_S_WIC_PTY_RLE_EADDR, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr;
/

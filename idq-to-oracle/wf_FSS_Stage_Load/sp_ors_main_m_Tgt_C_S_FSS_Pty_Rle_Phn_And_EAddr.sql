--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr (workflow wf_FSS_Stage_Load).
--
-- Each FSS registration row (V_FSS_ETL_SRC, capture action not 'D') can give one e-mail and one phone:
--   -> fil_deactivated_status: party not in STG_FSS_PTY_INACTIVE_STS, then two branches
--   e-mail: Filt_null_email (ADDR_EMAIL not NULL) -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
--           Valid_Records -> C_S_FSS_PTY_RLE_EADDR ; Bad_Records -> EXC_STG_BAD_REC_MEMB
--   phone : Filt_null_phone (NBR_PHONE not NULL) -> rule_Phone_Std (usage 001 'Telephone', 'Primary') and
--           rule_Phone_Extension_Std -> RTR_Valid_PhoneNumbers
--           Good_Records (no phone code)  -> C_S_FSS_PTY_RLE_PHN (an invalid extension is blanked)
--           Bad_Phone_Records             -> EXC_STG_BAD_REC_MEMB ('Rejected Record')
--           Bad_Phone_Ext__Records        -> EXC_STG_BAD_REC_MEMB ('Bad Value'); a row with a good phone and a bad
--                                            extension is loaded AND logged
-- Both C_S targets are truncated first.
--
-- TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = DT_LAST_UPDATE.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
BEGIN
    sp_ors_helper01_common('C_S_FSS_PTY_RLE_EADDR');
    sp_ors_helper01_common('C_S_FSS_PTY_RLE_PHN');

    INSERT ALL
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Valid_Records -> Write_C_S_FSS_PTY_RLE_EADDR
        WHEN ADDR_EMAIL IS NOT NULL AND email_exception_code IS NULL THEN
            INTO C_S_FSS_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, ADDR_TP, USG_TP, ELEC_ADDR, STS_CD, IS_VLD, SRC_LAST_UPD_DT)
            VALUES (eaddr_pkey, DT_LAST_UPDATE /* TIMELINE */, '1' /* TIMELINE: VERSION_SEQ */, l_run_ts, l_run_ts,
                    eaddr_pkey, 1, pty_rle_fk, '001', NULL, std_email, 'Active', 'Y', DT_LAST_UPDATE)
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Bad_Records -> write_Email_Exception
        WHEN ADDR_EMAIL IS NOT NULL AND email_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
                  PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
            VALUES ('FSS', email_exception_code, email_exception_desc, l_run_ts, ADDR_EMAIL, c_mapping,
                    email_exception_type, DT_LAST_UPDATE, ADDR_EMAIL, 'Email', PTY_SRC_KEY, ID_REGISTRATION_CLIENT)
        -- Filt_null_phone -> RTR_Valid_PhoneNumbers.Good_Records -> Write_C_S_FSS_PTY_RLE_PHN
        WHEN NBR_PHONE IS NOT NULL AND phone_exception_code IS NULL THEN
            INTO C_S_FSS_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND,
                  PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, PHN_NUM_EXT)
            VALUES (phn_pkey, DT_LAST_UPDATE /* TIMELINE */, '1' /* TIMELINE: VERSION_SEQ */, l_run_ts, phn_pkey, 1,
                    pty_rle_fk, 'Telephone', '001', std_phone, 'Primary', DT_LAST_UPDATE,
                    CASE WHEN ext_exception_code IS NULL THEN std_ext END)
        -- Filt_null_phone -> RTR_Valid_PhoneNumbers.Bad_Phone_Records -> write_Phone_Exception
        WHEN NBR_PHONE IS NOT NULL AND phone_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME,
                  SRC_SYS_ID_2)
            VALUES ('FSS', phone_exception_code, phone_exception_desc, l_run_ts,
                    NBR_PHONE /* PREF_LVL is 'Primary' */, NULL /* USG_TP is '001', never 'Work' */, NULL,
                    c_mapping, PTY_SRC_KEY, 'Rejected Record', DT_LAST_UPDATE, NBR_PHONE, 'Main Phone',
                    ID_REGISTRATION_CLIENT)
        -- Filt_null_phone -> RTR_Valid_PhoneNumbers.Bad_Phone_Ext__Records -> Write_Phone_Ext_Exception
        WHEN NBR_PHONE IS NOT NULL AND ext_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  PRIMARY_PHONE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, PERIOD_START_DATE, MAPPING_NAME)
            VALUES ('FSS', PTY_SRC_KEY, ID_REGISTRATION_CLIENT, 'Bad Value', ext_exception_code, ext_exception_desc,
                    l_run_ts, NBR_PHONE_EXT, NBR_PHONE_EXT, 'Main Phone Ext', DT_LAST_UPDATE, c_mapping)
    WITH
    -- Read_V_FSS_ETL_SRC (source filter; the commented-out testing filter is not applied) + fil_deactivated_status
    src AS (
        SELECT v.PTY_SRC_KEY, v.ADDR_EMAIL, v.NBR_PHONE, v.NBR_PHONE_EXT, v.SOURCE_TYPE, v.ID_REGISTRATION_CLIENT,
               v.DT_LAST_UPDATE,
               v.PTY_SRC_KEY || '|Member'                                                         AS pty_rle_fk,
               v.PTY_SRC_KEY || '|Member' || '|' || '001' || '|' || LPAD(v.ID_REGISTRATION_CLIENT, 10, '0') || '|'
               || LTRIM(RTRIM(v.ADDR_EMAIL))                                                      AS eaddr_pkey,
               v.PTY_SRC_KEY || '|Member' || '|' || 'Telephone' || '|' || '001' || '|'
               || LPAD(v.ID_REGISTRATION_CLIENT, 10, '0') || '|' || LTRIM(RTRIM(v.NBR_PHONE))     AS phn_pkey
          FROM V_FSS_ETL_SRC v
         WHERE v.DTL__CAPXACTION <> 'D'
           AND NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    dq AS (
        SELECT /*+ NO_MERGE */
               s.*,
               CASE WHEN s.ADDR_EMAIL IS NOT NULL THEN fn_dq_valid_email(s.ADDR_EMAIL) END          AS em,
               CASE WHEN s.NBR_PHONE IS NOT NULL THEN fn_dq_std_phone(s.NBR_PHONE, 'FSS', '001') END AS ph,
               CASE WHEN s.NBR_PHONE IS NOT NULL THEN fn_dq_std_phone_ext(s.NBR_PHONE_EXT) END      AS px
          FROM src s
    )
    SELECT d.*,
           d.em.email_address                  AS std_email,
           d.em.exception_code                 AS email_exception_code,
           d.em.exception_desc                 AS email_exception_desc,
           d.em.exception_type                 AS email_exception_type,
           d.ph.phone                          AS std_phone,
           d.ph.phone_exception_code           AS phone_exception_code,
           d.ph.phone_exception_desc           AS phone_exception_desc,
           d.px.phone_nbr_ext                  AS std_ext,
           d.px.phone_nbr_ext_exception_code   AS ext_exception_code,
           d.px.phone_nbr_ext_exception_desc   AS ext_exception_desc
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_FSS_PTY_RLE_EADDR, C_S_FSS_PTY_RLE_PHN, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr;
/

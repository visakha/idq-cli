--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Phn
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Rle_Phn (workflow wf_TTF_Stage_Load).
--
-- One phone per active TTF client (V_TTF_ETL_SRC) into C_S_TTF_PTY_RLE_PHN (truncated first):
--   -> fil_deactivated_status: party not in STG_TTF_PTY_INACTIVE_STS
--   -> Filt_null_phone: PHONE not NULL
--   -> rule_Phone_Std (usage 001 'Telephone', 'Primary') -> RTR_Valid_PhoneNumbers
--        Good_Records (no code)      -> C_S_TTF_PTY_RLE_PHN
--        Bad_Phone_Records (a code)  -> EXC_STG_BAD_REC_MEMB ('Rejected Record')
--        Bad_Phone_Ext__Records      -> never: the extension port feeding rule_Phone_Extension_Std is not fed in IDQ,
--                                       so the extension is NULL and the rule returns no code. Not generated.
-- The source read stores an invalid SQL fragment ("PHONE" in ()) that is not in custom-query mode: not applied.
--
-- TIMELINE: VERSION_SEQ = '1'; PERIOD_START_DATE = SUBMITDATE.
-- SRC_SYS_ID_2 of the exception row is linked to a router port without input (ID_PHONE): NULL.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Phn
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TTF_Pty_Rle_Phn';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
BEGIN
    sp_ors_helper01_common('C_S_TTF_PTY_RLE_PHN');

    INSERT ALL
        -- RTR_Valid_PhoneNumbers.Good_Records -> Write_C_S_TTF_PTY_RLE_PHN
        WHEN phone_exception_code IS NULL THEN
            INTO C_S_TTF_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND,
                  PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT)
            VALUES (phn_pkey, SUBMITDATE /* TIMELINE */, '1' /* TIMELINE: VERSION_SEQ */, l_run_ts, phn_pkey, 1,
                    PTY_SRC_KEY || '|Member', 'Telephone', '001', std_phone, 'Primary', SUBMITDATE)
        -- RTR_Valid_PhoneNumbers.Bad_Phone_Records -> write_Phone_Exception
        WHEN phone_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME,
                  SRC_SYS_ID_2)
            VALUES ('TTF', phone_exception_code, phone_exception_desc, l_run_ts, PHONE /* 'Primary' */, NULL, NULL,
                    c_mapping, PTY_SRC_KEY, 'Rejected Record', SUBMITDATE, PHONE, 'Main Phone',
                    NULL /* router port ID_PHONE unfed */)
    WITH
    src AS (
        SELECT v.PHONE, v.SUBMITDATE, v.PTY_SRC_KEY,
               v.PTY_SRC_KEY || '|Member' || '|' || 'Telephone' || '|' || '001' || '|' || v.PHONE AS phn_pkey
          FROM V_TTF_ETL_SRC v
         WHERE v.PHONE IS NOT NULL                                           -- Filt_null_phone
           AND NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i          -- fil_deactivated_status
                            WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    dq AS (
        SELECT /*+ NO_MERGE */ s.*, fn_dq_std_phone(s.PHONE, 'TTF', '001') AS ph
          FROM src s
    )
    SELECT d.*,
           d.ph.phone                 AS std_phone,
           d.ph.phone_exception_code  AS phone_exception_code,
           d.ph.phone_exception_desc  AS phone_exception_desc
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TTF_PTY_RLE_PHN, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Phn;
/

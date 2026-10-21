--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr (workflow wf_ECI_Stage_Load).
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
--
-- VALIDATION: rule_Phone_Std = fn_snow_helper23_common (cleaning) + RDM.REF_PHN_AREA_CD (fn_snow_helper44_common)
--   + fn_snow_helper24_common (code; ECI: area code '000' -> Missing_AreaCode, main / other numbers may not be
--   toll-free); rule_email_validation_v01 = fn_snow_helper22_common.
-- BAD DATA: a 'Missing_AreaCode' phone matches both phone groups, so it is loaded AND logged (IDQ router semantics).
--   An e-mail whose 'Invalid_Email' code is not configured in EXC_LOOKUP_CODE_VALUE is treated as valid and loaded,
--   because the router tests the looked-up code (docs/common_insights.md section 3). The phone exception
--   SRC_SYS_ID_1 is linked to an unfed port (PTY_FK) in IDQ and is written NULL; its type is the literal 'Bad Value'.
--   The phone is written cleaned and cut to 10 characters (port precision of the rule). Unique keys Snowflake does
--   not enforce are applied: C_S_ECI_PTY_RLE_PHN / _EADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = source PERIOD_START_DATE; the e-mail
--   PERIOD_REFERENCE_TIME port is not fed in IDQ (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Default -> RTR_Valid_PhoneNumbers.Good_Records -> exp_Stage_Target_PhoneNumbers -> Write_C_S_ECI_PTY_RLE_PHN
        WHEN grp_phone_good AND uq_phn THEN
            INTO C_S_ECI_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, PHN_NUM_EXT, HUB_STATE_IND)
            VALUES (pkey_src_object, PERIOD_START_DATE, version_seq, run_ts, run_ts, src_rowid, pty_rle_fk, PHONE_TP,
                    USG_TP, std_phone, PREF_LVL, PERIOD_START_DATE, WORK_EXT, hub_state_ind)
        -- Default -> RTR_Valid_PhoneNumbers.Bad_Phone_Records -> exp_Stage_Phone_Exceptions
        WHEN grp_phone_bad AND uq_phone_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  SRC_SYS_ID_2, ATTRIBUTE_NAME)
            VALUES (src_sys, phone_exception_code, phone_exception_desc, run_ts, exc_primary_phone, exc_work_phone,
                    exc_secondary_phone, mapping_name, NULL, exc_type_bad_value, USG_TP, PERIOD_START_DATE,
                    std_phone, ID_CASE, exc_phone_attribute)
        -- Email_Group -> rtr_Valid_EAddr_Records.Valid_Records -> exp_Stage_Target_EAddr_Attributes
        WHEN grp_email_good AND uq_eaddr THEN
            INTO C_S_ECI_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  PTY_RLE_FK, ELEC_ADDR, USG_TP, ADDR_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, VERSION_SEQ, HUB_STATE_IND)
            VALUES (pkey_src_object, PERIOD_START_DATE, NULL, run_ts, run_ts, pkey_src_object, pty_rle_fk,
                    std_email, NULL, eaddr_addr_tp, eaddr_sts_cd, eaddr_is_vld, PERIOD_START_DATE, version_seq,
                    hub_state_ind)
        -- Email_Group -> rtr_Valid_EAddr_Records.Bad_Records -> exp_Stage_Email_Exceptions
        WHEN grp_email_bad AND uq_email_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME,
                  EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME)
            VALUES (src_sys, ID_FAMILY_PHONE, email_exception_code, email_exception_desc, run_ts, PHONE_EMAIL,
                    mapping_name, email_exception_type, PERIOD_START_DATE, PHONE_EMAIL, exc_email_attribute)
    SELECT *
      FROM (
        WITH
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
        -- Read_V_ECI_ETL_SRC_FAMILY_PHONE + exp_Stage_Source_Attributes
        src AS (
            SELECT s.SOURCE_TABLE, s.WORK_EXT, s.PHONE_TP, s.USG_TP, s.PREF_LVL, s.PERIOD_START_DATE,
                   s.PHONE_EMAIL_TYPE, s.PHONE_EMAIL, s.ID_CASE, s.ID, s.ID_FAMILY_PHONE,
                   NVL(s.PHONE_EMAIL_TYPE = 'EADDRESS', FALSE)                                    AS is_email,
                   NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')      AS pty_src_key,
                   NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member' AS pty_rle_fk,
                   IFF(NVL(s.PHONE_EMAIL_TYPE = 'EADDRESS', FALSE),
                       NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|001|'
                       || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '') || '|' || NVL(TRIM(s.PHONE_EMAIL), ''),
                       NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|'
                       || NVL(s.PHONE_TP, '') || '|' || NVL(s.USG_TP, '') || '|' || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '')
                       || '|' || NVL(TRIM(s.PHONE_EMAIL), ''))                                     AS pkey_src_object,
                   -- o_SRC_ROWID: same as the key but WITHOUT trimming the phone / e-mail
                   IFF(NVL(s.PHONE_EMAIL_TYPE = 'EADDRESS', FALSE),
                       NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|001|'
                       || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '') || '|' || NVL(s.PHONE_EMAIL, ''),
                       NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|'
                       || NVL(s.PHONE_TP, '') || '|' || NVL(s.USG_TP, '') || '|' || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '')
                       || '|' || NVL(s.PHONE_EMAIL, ''))                                           AS src_rowid
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
        -- rule_Phone_Std step 1 (phone rows; Expression.PHONE_EMAIL1 prefixes '000' to 7-digit numbers) and
        -- rule_email_validation_v01 (e-mail rows)
        dq AS (
            SELECT a.*,
                   IFF(NOT a.is_email,
                       fn_snow_helper23_common(IFF(LENGTH(a.PHONE_EMAIL) = 7, '000' || a.PHONE_EMAIL, a.PHONE_EMAIL)),
                       NULL)                                                          AS std_phone,
                   IFF(a.is_email, fn_snow_helper22_common(a.PHONE_EMAIL), NULL)       AS em
              FROM active a
        ),
        -- rule_Phone_Std step 2 (Lookup_REF_PHN_AREA_CD, exp_validate_Phone) and the exception lookups
        checked AS (
            SELECT d.*,
                   /* VALIDATION */
                   IFF(NOT d.is_email,
                       fn_snow_helper24_common(d.std_phone, 'ECI', d.USG_TP, ar.NPA_ID, ar.SERVICE), NULL) AS phone_exception_code,
                   d.em:email_address::VARCHAR                                        AS std_email
              FROM dq d
              LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.std_phone, 1, 3)
        ),
        routed AS (
            SELECT c.*,
                   xp.EXCEPTION_DESC                                                  AS phone_exception_desc,
                   xe.EXCEPTION_CODE                                                  AS email_exception_code,
                   xe.EXCEPTION_DESC                                                  AS email_exception_desc,
                   xe.EXCEPTION_TYPE                                                  AS email_exception_type,
                   (NOT c.is_email AND (c.phone_exception_code IS NULL
                                        OR c.phone_exception_code = 'Missing_AreaCode')) AS grp_phone_good,
                   (NOT c.is_email AND c.phone_exception_code IS NOT NULL)            AS grp_phone_bad,
                   (c.is_email AND xe.EXCEPTION_CODE IS NULL)                          AS grp_email_good,
                   (c.is_email AND xe.EXCEPTION_CODE IS NOT NULL)                      AS grp_email_bad
              FROM checked c
              LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = c.em:exception_code::VARCHAR
        )
        SELECT r.*,
               '1' /* TIMELINE: VERSION_SEQ */                                     AS version_seq,
               1                                                                    AS hub_state_ind,
               'ECI'                                                                AS src_sys,
               :l_run_ts                                                            AS run_ts,
               :c_mapping                                                           AS mapping_name,
               'Bad Value'                                                          AS exc_type_bad_value,
               IFF(r.PREF_LVL = 'Primary', r.std_phone, NULL)                       AS exc_primary_phone,
               IFF(r.USG_TP = 'Work', r.std_phone, NULL)                            AS exc_work_phone,
               IFF(r.PREF_LVL = 'Secondary', r.std_phone, NULL)                     AS exc_secondary_phone,
               DECODE(r.USG_TP, '001', 'Main Phone', '002', 'Work Phone', '003', 'Other Phone') AS exc_phone_attribute,
               'Email'                                                              AS exc_email_attribute,
               '001'                                                                AS eaddr_addr_tp,
               'Active'                                                             AS eaddr_sts_cd,
               'Y'                                                                  AS eaddr_is_vld,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.pkey_src_object
                                       ORDER BY r.PERIOD_START_DATE DESC, r.ID_FAMILY_PHONE) = 1
                AND xph.PKEY_SRC_OBJECT IS NULL)                                    AS uq_phn,
               (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.pkey_src_object
                                       ORDER BY r.PERIOD_START_DATE DESC, r.ID_FAMILY_PHONE) = 1
                AND xea.PKEY_SRC_OBJECT IS NULL)                                    AS uq_eaddr,
               ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.ID_CASE, r.USG_TP, r.phone_exception_code
                                      ORDER BY r.ID_FAMILY_PHONE) = 1               AS uq_phone_exc,
               ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.ID_FAMILY_PHONE, r.email_exception_type,
                                               r.email_exception_code ORDER BY r.ID) = 1 AS uq_email_exc
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
                 ON xph.PKEY_SRC_OBJECT = r.pkey_src_object
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
                 ON xea.PKEY_SRC_OBJECT = r.pkey_src_object
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR, exceptions)',
                                   :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

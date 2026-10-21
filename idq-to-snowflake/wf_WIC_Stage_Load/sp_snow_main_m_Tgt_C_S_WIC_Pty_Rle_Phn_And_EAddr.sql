--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr (workflow wf_WIC_Stage_Load).
--
-- Each WIC row (V_WIC_ETL_SRC) gives one phone and possibly one e-mail:
--   -> fil_deactivated_status: party not in STG_WIC_PTY_INACTIVE_STS, then two branches
--   phone : rule_Phone_Std (usage 001 'Telephone', 'Primary') on EVERY active row -> RTR_Valid_PhoneNumbers
--           Good_Records (no code, or 'Missing_AreaCode') -> C_S_WIC_PTY_RLE_PHN
--           Bad_Phone_Records (any code)                 -> EXC_STG_BAD_REC_MEMB
--   e-mail: Filt_null_email -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
--           Valid_Records -> C_S_WIC_PTY_RLE_EADDR ; Bad_Records -> EXC_STG_BAD_REC_MEMB
--
-- VALIDATION: rule_Phone_Std = fn_snow_helper23/24_common with RDM.REF_PHN_AREA_CD ('Missing_AreaCode' only exists
--   for ECI, so WIC never gets it); rule_email_validation_v01 = fn_snow_helper22_common (routed on the looked-up
--   code).
-- BAD DATA: there is no null-phone filter (docs/common_insights.md 1.14): a party without a phone is validated and
--   logged as Invalid_Phone_Number. The e-mail key uses the e-mail as read (no trim), unlike ECI. Unique keys
--   Snowflake does not enforce are applied: C_S_WIC_PTY_RLE_PHN / _EADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and
--   EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = DATEKEY.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_WIC_PTY_RLE_PHN, C_S_WIC_PTY_RLE_EADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- RTR_Valid_PhoneNumbers.Good_Records -> Write_C_S_WIC_PTY_RLE_PHN
        WHEN grp_phone_good AND uq_phn THEN
            INTO C_S_WIC_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, PTY_RLE_FK, PHN_TP,
                  USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, HUB_STATE_IND)
            VALUES (phn_pkey, DATEKEY, version_seq, run_ts, phn_pkey, pty_rle_fk, phn_tp, usg_tp, std_phone, pref_lvl,
                    DATEKEY, hub_state_ind)
        -- RTR_Valid_PhoneNumbers.Bad_Phone_Records -> write_Phone_EXC_STG_BAD_REC_MEMB
        WHEN grp_phone_bad AND uq_phone_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, SRC_SYS_ID_2)
            VALUES (src_sys, phone_exception_code, phone_exception_desc, run_ts, std_phone, NULL, NULL, mapping_name,
                    PTY_SRC_KEY, exc_type_bad_value, usg_tp, DATEKEY, std_phone, attr_phone, FID)
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Valid_Records -> Write_C_S_WIC_PTY_RLE_EADDR
        WHEN grp_email_good AND uq_eaddr THEN
            INTO C_S_WIC_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, ELEC_ADDR, USG_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, ADDR_TP)
            VALUES (eaddr_pkey, DATEKEY, version_seq, run_ts, run_ts, eaddr_pkey, hub_state_ind, pty_rle_fk,
                    std_email, NULL, eaddr_sts_cd, eaddr_is_vld, DATEKEY, eaddr_addr_tp)
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Bad_Records -> write_Email_EXC_STG_BAD_REC_MEMB
        WHEN grp_email_bad AND uq_email_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
                  PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
            VALUES (src_sys, email_exception_code, email_exception_desc, run_ts, EMAIL, mapping_name,
                    email_exception_type, DATEKEY, EMAIL, attr_email, PTY_SRC_KEY, FID)
    SELECT *
      FROM (
        WITH
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
        -- Read_V_WIC_ETL_SRC + exp_Stage_Source_Attributes + exp_Phone_Email_Keys + fil_deactivated_status
        src AS (
            SELECT v.SOURCE_TABLE, v.ID, v.PTY_SRC_KEY, v.DATEKEY, v.FID, v.PHONE, v.EMAIL,
                   NVL(v.PTY_SRC_KEY, '') || '|Member'                                            AS pty_rle_fk,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|Telephone|001|' || NVL(TO_VARCHAR(v.FID), '') || '|'
                   || NVL(TRIM(v.PHONE), '')                                                      AS phn_pkey,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|001|' || NVL(TO_VARCHAR(v.FID), '') || '|' || NVL(v.EMAIL, '')
                                                                                                  AS eaddr_pkey,
                   fn_snow_helper23_common(v.PHONE)                                               AS std_phone,
                   IFF(v.EMAIL IS NOT NULL, fn_snow_helper22_common(v.EMAIL), NULL)               AS em
              FROM V_WIC_ETL_SRC v
             WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        checked AS (
            SELECT s.*,
                   /* VALIDATION */ fn_snow_helper24_common(s.std_phone, 'WIC', '001', ar.NPA_ID, ar.SERVICE) AS phone_exception_code,
                   s.em:email_address::VARCHAR                                                   AS std_email
              FROM src s
              LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(s.std_phone, 1, 3)
        ),
        routed AS (
            SELECT c.*,
                   xp.EXCEPTION_DESC AS phone_exception_desc,
                   xe.EXCEPTION_CODE AS email_exception_code,
                   xe.EXCEPTION_DESC AS email_exception_desc,
                   xe.EXCEPTION_TYPE AS email_exception_type,
                   (c.phone_exception_code IS NULL OR c.phone_exception_code = 'Missing_AreaCode') AS grp_phone_good,
                   c.phone_exception_code IS NOT NULL                                            AS grp_phone_bad,
                   (c.EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NULL)                            AS grp_email_good,
                   (c.EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NOT NULL)                        AS grp_email_bad
              FROM checked c
              LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = c.em:exception_code::VARCHAR
        )
        SELECT r.*,
               '1' /* TIMELINE: VERSION_SEQ */                          AS version_seq,
               1                                                         AS hub_state_ind,
               'WIC'                                                     AS src_sys,
               :l_run_ts                                                 AS run_ts,
               :c_mapping                                                AS mapping_name,
               'Telephone'                                               AS phn_tp,
               '001'                                                     AS usg_tp,
               'Primary'                                                 AS pref_lvl,
               'Bad Value'                                               AS exc_type_bad_value,
               'Main Phone'                                              AS attr_phone,
               'Email'                                                   AS attr_email,
               '001'                                                     AS eaddr_addr_tp,
               'Active'                                                  AS eaddr_sts_cd,
               'Y'                                                       AS eaddr_is_vld,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.phn_pkey ORDER BY r.DATEKEY DESC, r.FID) = 1
                AND xph.PKEY_SRC_OBJECT IS NULL)                         AS uq_phn,
               (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.eaddr_pkey ORDER BY r.DATEKEY DESC, r.FID) = 1
                AND xea.PKEY_SRC_OBJECT IS NULL)                         AS uq_eaddr,
               ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.PTY_SRC_KEY, r.FID, r.phone_exception_code
                                      ORDER BY r.DATEKEY DESC) = 1       AS uq_phone_exc,
               ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.PTY_SRC_KEY, r.FID, r.email_exception_type,
                                               r.email_exception_code ORDER BY r.DATEKEY DESC) = 1 AS uq_email_exc
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
                 ON xph.PKEY_SRC_OBJECT = r.phn_pkey
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
                 ON xea.PKEY_SRC_OBJECT = r.eaddr_pkey
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_WIC_PTY_RLE_PHN, C_S_WIC_PTY_RLE_EADDR, exceptions)',
                                   :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

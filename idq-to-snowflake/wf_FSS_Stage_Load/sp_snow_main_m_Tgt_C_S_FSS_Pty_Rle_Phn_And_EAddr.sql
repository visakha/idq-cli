--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr (workflow wf_FSS_Stage_Load).
--
-- Each FSS registration row (V_FSS_ETL_SRC, capture action not 'D') can give one e-mail and one phone:
--   -> fil_deactivated_status: party not in STG_FSS_PTY_INACTIVE_STS, then two branches
--   e-mail: Filt_null_email (ADDR_EMAIL not NULL) -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
--           Valid_Records -> C_S_FSS_PTY_RLE_EADDR ; Bad_Records -> EXC_STG_BAD_REC_MEMB
--   phone : Filt_null_phone (NBR_PHONE not NULL) -> rule_Phone_Std (usage 001 'Telephone', 'Primary') and
--           rule_Phone_Extension_Std -> RTR_Valid_PhoneNumbers
--           Good_Records (no phone code)  -> C_S_FSS_PTY_RLE_PHN (an invalid extension is blanked)
--           Bad_Phone_Records             -> EXC_STG_BAD_REC_MEMB ('Rejected Record')
--           Bad_Phone_Ext__Records        -> EXC_STG_BAD_REC_MEMB ('Bad Value')
--
-- VALIDATION: rule_email_validation_v01 = fn_snow_helper22_common (routed on the looked-up code);
--   rule_Phone_Std = fn_snow_helper23/24_common with RDM.REF_PHN_AREA_CD; rule_Phone_Extension_Std =
--   fn_snow_helper25_common.
-- BAD DATA: a row with a good phone and a bad extension is loaded (extension blanked) AND logged as 'Bad Value'
--   (docs/common_insights.md section 2). An e-mail whose code is not configured in EXC_LOOKUP_CODE_VALUE is loaded.
--   Unique keys Snowflake does not enforce are applied: C_S_FSS_PTY_RLE_EADDR / _PHN (PKEY_SRC_OBJECT,
--   VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = DT_LAST_UPDATE.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_FSS_PTY_RLE_EADDR, C_S_FSS_PTY_RLE_PHN. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Valid_Records -> Write_C_S_FSS_PTY_RLE_EADDR
        WHEN grp_email_good AND uq_eaddr THEN
            INTO C_S_FSS_PTY_RLE_EADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_RLE_FK, ADDR_TP, USG_TP, ELEC_ADDR, STS_CD, IS_VLD, SRC_LAST_UPD_DT)
            VALUES (eaddr_pkey, DT_LAST_UPDATE, version_seq, run_ts, run_ts, eaddr_pkey, hub_state_ind, pty_rle_fk,
                    eaddr_addr_tp, NULL, std_email, eaddr_sts_cd, eaddr_is_vld, DT_LAST_UPDATE)
        -- Filt_null_email -> rtr_Valid_EAddr_Records.Bad_Records -> write_Email_Exception
        WHEN grp_email_bad AND uq_email_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
                  PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
            VALUES (src_sys, email_exception_code, email_exception_desc, run_ts, ADDR_EMAIL, mapping_name,
                    email_exception_type, DT_LAST_UPDATE, ADDR_EMAIL, attr_email, PTY_SRC_KEY, ID_REGISTRATION_CLIENT)
        -- Filt_null_phone -> RTR_Valid_PhoneNumbers.Good_Records -> Write_C_S_FSS_PTY_RLE_PHN
        WHEN grp_phone_good AND uq_phn THEN
            INTO C_S_FSS_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND,
                  PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, PHN_NUM_EXT)
            VALUES (phn_pkey, DT_LAST_UPDATE, version_seq, run_ts, phn_pkey, hub_state_ind, pty_rle_fk, phn_tp,
                    usg_tp, std_phone, pref_lvl, DT_LAST_UPDATE, phn_num_ext)
        -- Filt_null_phone -> RTR_Valid_PhoneNumbers.Bad_Phone_Records -> write_Phone_Exception
        WHEN grp_phone_bad AND uq_phone_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME,
                  SRC_SYS_ID_2)
            VALUES (src_sys, phone_exception_code, phone_exception_desc, run_ts, NBR_PHONE, NULL, NULL,
                    mapping_name, PTY_SRC_KEY, exc_type_rejected, DT_LAST_UPDATE, NBR_PHONE, attr_phone,
                    ID_REGISTRATION_CLIENT)
        -- Filt_null_phone -> RTR_Valid_PhoneNumbers.Bad_Phone_Ext__Records -> Write_Phone_Ext_Exception
        WHEN grp_ext_bad AND uq_ext_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  PRIMARY_PHONE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, PERIOD_START_DATE, MAPPING_NAME)
            VALUES (src_sys, PTY_SRC_KEY, ID_REGISTRATION_CLIENT, exc_type_bad_value, ext_exception_code,
                    ext_exception_desc, run_ts, NBR_PHONE_EXT, NBR_PHONE_EXT, attr_phone_ext, DT_LAST_UPDATE,
                    mapping_name)
    SELECT *
      FROM (
        WITH
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
        -- Read_V_FSS_ETL_SRC (source filter; the commented-out testing filter is not applied) + fil_deactivated_status
        src AS (
            SELECT v.PTY_SRC_KEY, v.ADDR_EMAIL, v.NBR_PHONE, v.NBR_PHONE_EXT, v.SOURCE_TYPE, v.ID_REGISTRATION_CLIENT,
                   v.DT_LAST_UPDATE,
                   NVL(v.PTY_SRC_KEY, '') || '|Member'                                             AS pty_rle_fk,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|001|' || NVL(LPAD(TO_VARCHAR(v.ID_REGISTRATION_CLIENT), 10, '0'), '')
                   || '|' || NVL(TRIM(v.ADDR_EMAIL), '')                                           AS eaddr_pkey,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|Telephone|001|'
                   || NVL(LPAD(TO_VARCHAR(v.ID_REGISTRATION_CLIENT), 10, '0'), '') || '|' || NVL(TRIM(v.NBR_PHONE), '')
                                                                                                   AS phn_pkey
              FROM V_FSS_ETL_SRC v
             WHERE v.DTL__CAPXACTION <> 'D'
               AND NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        dq AS (
            SELECT s.*,
                   IFF(s.ADDR_EMAIL IS NOT NULL, fn_snow_helper22_common(s.ADDR_EMAIL), NULL)    AS em,
                   IFF(s.NBR_PHONE IS NOT NULL, fn_snow_helper23_common(s.NBR_PHONE), NULL)      AS std_phone,
                   IFF(s.NBR_PHONE IS NOT NULL, fn_snow_helper25_common(s.NBR_PHONE_EXT), NULL)  AS px
              FROM src s
        ),
        checked AS (
            SELECT d.*,
                   d.em:email_address::VARCHAR                                                   AS std_email,
                   /* VALIDATION */
                   IFF(d.NBR_PHONE IS NOT NULL,
                       fn_snow_helper24_common(d.std_phone, 'FSS', '001', ar.NPA_ID, ar.SERVICE), NULL) AS phone_exception_code,
                   d.px:phone_nbr_ext::VARCHAR                                                   AS std_ext,
                   d.px:exception_code::VARCHAR                                                  AS ext_exception_code
              FROM dq d
              LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.std_phone, 1, 3)
        ),
        routed AS (
            SELECT c.*,
                   xe.EXCEPTION_CODE  AS email_exception_code,
                   xe.EXCEPTION_DESC  AS email_exception_desc,
                   xe.EXCEPTION_TYPE  AS email_exception_type,
                   xp.EXCEPTION_DESC  AS phone_exception_desc,
                   xx.EXCEPTION_DESC  AS ext_exception_desc,
                   (c.ADDR_EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NULL)          AS grp_email_good,
                   (c.ADDR_EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NOT NULL)      AS grp_email_bad,
                   (c.NBR_PHONE IS NOT NULL AND c.phone_exception_code IS NULL)      AS grp_phone_good,
                   (c.NBR_PHONE IS NOT NULL AND c.phone_exception_code IS NOT NULL)  AS grp_phone_bad,
                   (c.NBR_PHONE IS NOT NULL AND c.ext_exception_code IS NOT NULL)    AS grp_ext_bad
              FROM checked c
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = c.em:exception_code::VARCHAR
              LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
              LEFT JOIN lkp_exc xx ON xx.EXCEPTION_CODE = c.ext_exception_code
        )
        SELECT r.*,
               '1' /* TIMELINE: VERSION_SEQ */                          AS version_seq,
               1                                                         AS hub_state_ind,
               'FSS'                                                     AS src_sys,
               :l_run_ts                                                 AS run_ts,
               :c_mapping                                                AS mapping_name,
               '001'                                                     AS eaddr_addr_tp,
               'Active'                                                  AS eaddr_sts_cd,
               'Y'                                                       AS eaddr_is_vld,
               'Telephone'                                               AS phn_tp,
               '001'                                                     AS usg_tp,
               'Primary'                                                 AS pref_lvl,
               /* BAD DATA: an invalid extension is blanked on the loaded phone */
               IFF(r.ext_exception_code IS NULL, r.std_ext, NULL)        AS phn_num_ext,
               'Email'                                                   AS attr_email,
               'Main Phone'                                              AS attr_phone,
               'Main Phone Ext'                                          AS attr_phone_ext,
               'Rejected Record'                                         AS exc_type_rejected,
               'Bad Value'                                               AS exc_type_bad_value,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.eaddr_pkey
                                       ORDER BY r.DT_LAST_UPDATE DESC, r.ID_REGISTRATION_CLIENT) = 1
                AND xea.PKEY_SRC_OBJECT IS NULL)                         AS uq_eaddr,
               (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.phn_pkey
                                       ORDER BY r.DT_LAST_UPDATE DESC, r.ID_REGISTRATION_CLIENT) = 1
                AND xph.PKEY_SRC_OBJECT IS NULL)                         AS uq_phn,
               ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                               r.email_exception_type, r.email_exception_code
                                      ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_email_exc,
               ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                               r.phone_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_phone_exc,
               ROW_NUMBER() OVER (PARTITION BY r.grp_ext_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                               r.ext_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1   AS uq_ext_exc
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
                 ON xea.PKEY_SRC_OBJECT = r.eaddr_pkey
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
                 ON xph.PKEY_SRC_OBJECT = r.phn_pkey
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_FSS_PTY_RLE_EADDR, C_S_FSS_PTY_RLE_PHN, exceptions)',
                                   :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

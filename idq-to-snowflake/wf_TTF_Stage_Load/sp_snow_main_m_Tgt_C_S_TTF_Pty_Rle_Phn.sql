--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Rle_Phn (workflow wf_TTF_Stage_Load).
--
-- One phone per active TTF client (V_TTF_ETL_SRC) into C_S_TTF_PTY_RLE_PHN (insert only, never truncated):
--   -> fil_deactivated_status: party not in STG_TTF_PTY_INACTIVE_STS
--   -> Filt_null_phone: PHONE not NULL
--   -> rule_Phone_Std (usage 001 'Telephone', 'Primary') -> RTR_Valid_PhoneNumbers
--        Good_Records (no code)      -> C_S_TTF_PTY_RLE_PHN
--        Bad_Phone_Records (a code)  -> EXC_STG_BAD_REC_MEMB ('Rejected Record')
--        Bad_Phone_Ext__Records      -> never: the extension port feeding rule_Phone_Extension_Std is not fed in IDQ
--                                       (docs/common_insights.md 1.5), so the rule returns no code. Not generated.
--
-- VALIDATION: rule_Phone_Std = fn_snow_helper23_common + RDM.REF_PHN_AREA_CD (fn_snow_helper44_common) +
--   fn_snow_helper24_common ('TTF', '001').
-- BAD DATA: a bad phone is not loaded, only logged; the exception row writes the computed code and the source
--   phone. SRC_SYS_ID_2 of the exception row is linked to a router port without input (ID_PHONE): NULL. The source
--   read stores an invalid SQL fragment ("PHONE" in ()) that is not in custom-query mode: not applied. Unique keys
--   Snowflake does not enforce are applied: C_S_TTF_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ) and
--   EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = '1'; PERIOD_START_DATE = SUBMITDATE.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty_Rle_Phn';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TTF_PTY_RLE_PHN. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- RTR_Valid_PhoneNumbers.Good_Records -> Write_C_S_TTF_PTY_RLE_PHN
        WHEN phone_exception_code IS NULL AND uq_phn THEN
            INTO C_S_TTF_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND,
                  PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT)
            VALUES (phn_pkey, SUBMITDATE, version_seq, run_ts, phn_pkey, hub_state_ind, pty_rle_fk, phn_tp, usg_tp,
                    std_phone, pref_lvl, SUBMITDATE)
        -- RTR_Valid_PhoneNumbers.Bad_Phone_Records -> write_Phone_Exception
        WHEN phone_exception_code IS NOT NULL AND uq_phone_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
                  MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME,
                  SRC_SYS_ID_2)
            VALUES (src_sys, phone_exception_code, phone_exception_desc, run_ts, PHONE, NULL, NULL, mapping_name,
                    PTY_SRC_KEY, exc_type_rejected, SUBMITDATE, PHONE, attr_phone, NULL)
    SELECT *
      FROM (
        WITH
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
        src AS (
            SELECT v.PHONE, v.SUBMITDATE, v.PTY_SRC_KEY,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|Telephone|001|' || v.PHONE AS phn_pkey,
                   fn_snow_helper23_common(v.PHONE)                             AS std_phone
              FROM V_TTF_ETL_SRC v
             WHERE v.PHONE IS NOT NULL                                           -- Filt_null_phone
               AND NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i          -- fil_deactivated_status
                                WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        checked AS (
            SELECT s.*,
                   /* VALIDATION */ fn_snow_helper24_common(s.std_phone, 'TTF', '001', ar.NPA_ID, ar.SERVICE) AS phone_exception_code
              FROM src s
              LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(s.std_phone, 1, 3)
        )
        SELECT c.*,
               xp.EXCEPTION_DESC                                    AS phone_exception_desc,
               '1' /* TIMELINE: VERSION_SEQ */                     AS version_seq,
               1                                                    AS hub_state_ind,
               NVL(c.PTY_SRC_KEY, '') || '|Member'                  AS pty_rle_fk,
               'Telephone'                                          AS phn_tp,
               '001'                                                AS usg_tp,
               'Primary'                                            AS pref_lvl,
               'TTF'                                                AS src_sys,
               :l_run_ts                                            AS run_ts,
               :c_mapping                                           AS mapping_name,
               'Rejected Record'                                    AS exc_type_rejected,
               'Main Phone'                                         AS attr_phone,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY c.phone_exception_code IS NULL, c.phn_pkey
                                       ORDER BY c.SUBMITDATE DESC) = 1
                AND xph.PKEY_SRC_OBJECT IS NULL)                    AS uq_phn,
               ROW_NUMBER() OVER (PARTITION BY c.phone_exception_code IS NULL, c.PTY_SRC_KEY, c.phone_exception_code
                                      ORDER BY c.SUBMITDATE DESC) = 1 AS uq_phone_exc
          FROM checked c
          LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
                 ON xph.PKEY_SRC_OBJECT = c.phn_pkey
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TTF_PTY_RLE_PHN, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

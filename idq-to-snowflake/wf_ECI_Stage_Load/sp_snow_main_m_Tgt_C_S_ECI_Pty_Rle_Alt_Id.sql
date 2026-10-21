--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Alt_Id (workflow wf_ECI_Stage_Load).
--
-- Alternate ids of the ECI parties into C_S_ECI_PTY_RLE_ALT_ID (insert only, never truncated):
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
-- VALIDATION: rule_USA_SSN_Validation_post_June2011 = fn_snow_helper26_common (status 'Invalid' -> Invalid_SSN);
--   rule_MEDICAID_ID_Std = fn_snow_helper27_common (special characters removed, not 9 characters ->
--   Invalid_Medicaid_Id).
-- BAD DATA: an invalid SSN or Medicaid id is not loaded, only logged. The SSN exception row has no RUN_DATE linked
--   (NULL, docs/common_insights.md 1.13) and writes the EXCEPTION_CODE returned by the EXC_LOOKUP_CODE_VALUE lookup
--   (NULL when Invalid_SSN is not configured); the Medicaid exception row writes the computed code.
--   Unique keys Snowflake does not enforce are applied: C_S_ECI_PTY_RLE_ALT_ID (PKEY_SRC_OBJECT, VERSION_SEQ) and
--   EXC_STG_BAD_REC_MEMB (SRC_SYS, SRC_SYS_ID_1..3, EXCEPTION_TYPE, EXCEPTION_CODE, RUN_DATE). Because the SSN row's
--   RUN_DATE is NULL, its key repeats from run to run: in Oracle the unique constraint rejects the row of every later
--   run, so an invalid SSN is logged only once, ever. That is reproduced here (key already in the table -> skipped).
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = source DATE_CREATED.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_ECI_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Union_Valid_ALT_ID_Type (SSN valid, ECI ids, Medicaid valid) -> Exp_STG_ALT_ID_Type_Load -> target
        WHEN grp_valid AND uq_alt_id THEN
            INTO C_S_ECI_PTY_RLE_ALT_ID
                 (PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE, PKEY_SRC_OBJECT, SRC_ROWID,
                  VERSION_SEQ, STS_CD, HUB_STATE_IND, SRC_LAST_UPD_DT, ALT_ID_TP_FLTR, PERIOD_START_DATE)
            VALUES (PTY_REL_FK, ALT_ID_TP, ALT_ID_VAL, DATE_CREATED, run_ts, PKEY_SRC_OBJECT, src_rowid,
                    version_seq, sts_cd, hub_state_ind, src_last_upd_dt, ALT_ID_TP, DATE_CREATED)
        -- RTR_Valid_SSN.Invalid_CHILD_SSN -> Exp_SSN_Exceptions -> Write_EXC_STG_BAD_REC_MEMB_SSN (RUN_DATE unlinked)
        WHEN grp_ssn_exc AND uq_ssn_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, SRC_SYS, ATTRIBUTE_NAME, MAPPING_NAME,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2)
            VALUES (ssn_lkp_code, ssn_lkp_desc, ssn_lkp_type, src_sys, attr_ssn, mapping_name, ALT_ID_VAL,
                    PKEY_SRC_OBJECT, PTY_REL_FK)
        -- RTR_Valid_Medicaid_ID.INVALID_Medicaid_Id -> Exp_Invalid_MedicaidId -> Write_EXC_STG_BAD_REC_MEMB_MedicaidId
        WHEN grp_mcd_exc AND uq_mcd_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, MAPPING_NAME, ATTRIBUTE_VALUE,
                  ATTRIBUTE_NAME, SRC_SYS_ID_2, SRC_SYS_ID_1)
            VALUES (src_sys, run_ts, medicaid_exception_type, medicaid_exception_code, medicaid_exception_desc,
                    mapping_name, ALT_ID_VAL, attr_medicaid, PTY_REL_FK, PKEY_SRC_OBJECT)
    SELECT *
      FROM (
        WITH
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_STG_ECI_D_CHILD (custom SQL, query mode SEMI; port ID_CHILD = column ID)
        src AS (
            SELECT ID_CHILD AS ID, LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member' AS PTY_REL_FK,
                   LPAD(TO_VARCHAR(ID_CHILD), 10, '0') AS SRC_KEY_SFX, '018' AS ALT_ID_TP,
                   LPAD(TO_VARCHAR(ID_CHILD), 10, '0') AS ALT_ID_VAL, DATE_CREATED, DATE_MODIFIED,
                   LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member' || '|018' || '|'
                   || LPAD(TO_VARCHAR(ID_CHILD), 10, '0') AS PKEY_SRC_OBJECT
              FROM STG_ECI_D_CHILD
            UNION ALL
            SELECT ID_CHILD, LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member', LPAD(TO_VARCHAR(ID_CHILD), 10, '0'),
                   '004', CHILD_SSN, DATE_CREATED, DATE_MODIFIED,
                   LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member' || '|004' || '|' || LPAD(TO_VARCHAR(ID_CHILD), 10, '0')
              FROM STG_ECI_D_CHILD
             WHERE CHILD_SSN IS NOT NULL
            UNION ALL
            SELECT C.ID_CHILD, LPAD(TO_VARCHAR(C.ID_CHILD), 10, '0') || '|Member', LPAD(TO_VARCHAR(M.ID_MEDICAID), 9, '0'),
                   '002', M.MEDICAID_NBR, M.DATE_CREATED, M.DATE_MODIFIED,
                   LPAD(TO_VARCHAR(C.ID_CHILD), 10, '0') || '|Member' || '|002' || '|' || LPAD(TO_VARCHAR(M.ID_MEDICAID), 10, '0')
              FROM STG_ECI_D_MEDICAID M
             INNER JOIN STG_ECI_SN_CASE C ON M.ID_CASE = C.ID_CASE
            UNION ALL
            SELECT ID_FAMILY, LPAD(TO_VARCHAR(ID_FAMILY), 10, '0') || 'F|Member', LPAD(TO_VARCHAR(ID_FAMILY), 10, '0'),
                   '019', LPAD(TO_VARCHAR(ID_FAMILY), 10, '0'), DATE_CREATED, DATE_MODIFIED,
                   LPAD(TO_VARCHAR(ID_FAMILY), 10, '0') || 'F|Member' || '|019' || '|' || LPAD(TO_VARCHAR(ID_FAMILY), 10, '0')
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
            SELECT a.*,
                   /* VALIDATION */
                   IFF(a.ALT_ID_TP = '004' AND fn_snow_helper26_common(a.ALT_ID_VAL):ssn_status::VARCHAR = 'Invalid',
                       'Invalid_SSN', NULL)                                                    AS ssn_exception_code,
                   IFF(a.ALT_ID_TP = '002', fn_snow_helper27_common(a.ALT_ID_VAL):exception_code::VARCHAR, NULL)
                                                                                               AS medicaid_exception_code
              FROM active a
        ),
        routed AS (
            SELECT d.*,
                   xs.EXCEPTION_CODE AS ssn_lkp_code, xs.EXCEPTION_DESC AS ssn_lkp_desc, xs.EXCEPTION_TYPE AS ssn_lkp_type,
                   xm.EXCEPTION_TYPE AS medicaid_exception_type, xm.EXCEPTION_DESC AS medicaid_exception_desc,
                   ((d.ALT_ID_TP = '004' AND d.ssn_exception_code IS NULL)
                    OR d.ALT_ID_TP IN ('018', '019')
                    OR (d.ALT_ID_TP = '002' AND d.medicaid_exception_code IS NULL))          AS grp_valid,
                   (d.ALT_ID_TP = '004' AND d.ssn_exception_code IS NOT NULL)                 AS grp_ssn_exc,
                   (d.ALT_ID_TP = '002' AND d.medicaid_exception_code IS NOT NULL)            AS grp_mcd_exc
              FROM dq d
              LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.ssn_exception_code
              LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = d.medicaid_exception_code
        )
        SELECT r.*,
               TO_VARCHAR(r.ID) || '|' || r.ALT_ID_TP                    AS src_rowid,
               1 /* TIMELINE: VERSION_SEQ */                             AS version_seq,
               'Issued'                                                  AS sts_cd,
               1                                                         AS hub_state_ind,
               NVL(r.DATE_MODIFIED, r.DATE_CREATED)                      AS src_last_upd_dt,
               'ECI'                                                     AS src_sys,
               :l_run_ts                                                 AS run_ts,
               :c_mapping                                                AS mapping_name,
               'ALT_ID_Type_SSN'                                         AS attr_ssn,
               'ALT_ID_TP_MedicaidId'                                    AS attr_medicaid,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.grp_valid, r.PKEY_SRC_OBJECT ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
                AND xa.PKEY_SRC_OBJECT IS NULL)                          AS uq_alt_id,
               (ROW_NUMBER() OVER (PARTITION BY r.grp_ssn_exc, r.PKEY_SRC_OBJECT, r.PTY_REL_FK, r.ssn_lkp_type,
                                                r.ssn_lkp_code ORDER BY r.ID) = 1
                AND xe.SRC_SYS_ID_1 IS NULL)                             AS uq_ssn_exc,
               ROW_NUMBER() OVER (PARTITION BY r.grp_mcd_exc, r.PKEY_SRC_OBJECT, r.PTY_REL_FK,
                                               r.medicaid_exception_type, r.medicaid_exception_code
                                      ORDER BY r.ID) = 1                 AS uq_mcd_exc
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
                 ON xa.PKEY_SRC_OBJECT = r.PKEY_SRC_OBJECT
          -- SSN exception rows of earlier runs (RUN_DATE NULL, same key): Oracle's unique constraint rejects a repeat
          LEFT JOIN (SELECT DISTINCT SRC_SYS_ID_1, SRC_SYS_ID_2, NVL(EXCEPTION_TYPE, '~') AS EXC_TYPE,
                            NVL(EXCEPTION_CODE, '~') AS EXC_CODE
                       FROM EXC_STG_BAD_REC_MEMB
                      WHERE SRC_SYS = 'ECI' AND RUN_DATE IS NULL AND SRC_SYS_ID_3 IS NULL) xe
                 ON r.grp_ssn_exc AND xe.SRC_SYS_ID_1 = r.PKEY_SRC_OBJECT AND xe.SRC_SYS_ID_2 = r.PTY_REL_FK
                AND xe.EXC_TYPE = NVL(r.ssn_lkp_type, '~') AND xe.EXC_CODE = NVL(r.ssn_lkp_code, '~')
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_ECI_PTY_RLE_ALT_ID, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

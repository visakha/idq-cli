--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Validation (workflow wf_ECI_Stage_Load, first step).
--
-- Checks every ECI child and family party of the delta (STG_ECI_D_CHILD + STG_ECI_D_FAMILY) and maintains the
-- deactivation list that every later ECI mapping uses as a filter:
--   * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank (and the family is not already
--                                          inactive)                     -> EXC_STG_BAD_REC_MEMB
--   * Rtr_Valid_Party.Deactivation       : name blank, or a duplicate case (V_ECI_ETL_LU_DUP_CASES), or the family is
--                                          inactive (V_ECI_ETL_LU_FAMILY_VALIDATION)
--                                          -> STG_ECI_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_ECI_PTY_INACTIVE_STS (new row, only when the party has no status yet;
--                                             H / D / P from the C_B_PTY_XREF hub state)
--   * Rtr_Valid_Party.Reactivation       : party has a status, names present, not a duplicate, family active
--                                          -> STG_ECI_PTY_INACTIVE_LOG ('Reactivation')
--   * Default group                      : not linked, rows dropped.
-- A row goes to every group whose condition is true (IDQ router semantics), so Invalid_Party_Name rows are also
-- Deactivation rows.
--
-- VALIDATION: mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common, with its prefix / suffix / junk-name
--   lookups) cleans the names first; the blank test is the IDQ one (fn_snow_helper03_common: '' and white space are
--   blank, NULL is blank). Missing_First_Name wins over Missing_Last_Name.
-- BAD DATA: the exception row takes its description and type from EXC_LOOKUP_CODE_VALUE (NULL when the code is not
--   configured) and writes the computed code. EXC_STG_BAD_REC_MEMB is unique on (SRC_SYS, SRC_SYS_ID_1..3,
--   EXCEPTION_TYPE, EXCEPTION_CODE, RUN_DATE) in Oracle; Snowflake does not enforce that, so a second row with the
--   same key in this run is not written (IDQ rejects it and carries on).
-- TIMELINE: this mapping has no MDM timeline logic.
--
-- Not performed: the IDQ DD_DELETE of STG_ECI_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
-- Snapshot: the lookups on STG_ECI_PTY_INACTIVE_STS read the table as it was before the run (IDQ static lookup
-- cache): all routing happens in one multi-table INSERT, which reads one snapshot.
-- Lookup Lookup_C_B_PTY_XREF: TRIM(ROWID_SYSTEM) = 'ECI' (the MDM column is blank-padded; Oracle compares a CHAR
-- column blank-padded, Snowflake does not).
-- v_FULL_NAME is declared string(10) in IDQ, so the full name passed to the name mapplet is cut at 10 characters
-- (BAD DATA); this mapping does not write the full-name outputs.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Validation';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP() of RUN_DATE / ACTION_DT
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
    l_log      VARCHAR DEFAULT '';
BEGIN
    BEGIN TRANSACTION;

    INSERT ALL
        -- Write_Invalid_Party_Name (Exp_Invalid_PTY_NM + Lkp_EXC_LOOKUP_CODE_VALUE_Name)
        WHEN grp_invalid_party_name AND uq_exc_name THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME,
                  PERIOD_START_DATE)
            VALUES (src_system, pkey_src_object, exc_code_name, exc_desc_name, exc_type_name, run_ts,
                    std_first_name, std_mdl_name, std_lst_name, DOB, exc_attribute_name, exc_attribute_value,
                    mapping_name, DATE_CREATED)
        -- Write_Deactv_STG_ECI_PTY_INACTIVE_LOG (Exp_Log_Deactv)
        WHEN grp_deactivation THEN
            INTO STG_ECI_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, src_system, action_deactivation, run_ts)
        -- Filt_new_deactivations: IsNull(DEACTIVATION_STS) -> Write_new_STG_ECI_PTY_INACTIVE_STS (Exp_New_Deactvn_Sts)
        WHEN grp_deactivation AND deactivation_sts IS NULL THEN
            INTO STG_ECI_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (pkey_src_object, src_system, new_deactivation_sts, run_ts)
        -- Write_STG_ECI_PTY_INACTIVE_LOG (Exp_Log_Reactv)
        WHEN grp_reactivation THEN
            INTO STG_ECI_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, src_system, action_reactivation, run_ts)
    SELECT *
      FROM (
        WITH
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_STG_ECI_D_CHILD_and_FAMILY (custom SQL, query mode SEMI)
        src AS (
            SELECT 'ECI_CHILD' AS SOURCE_TABLE, c.ID_CHILD AS ID, c.FIRST_NAME, c.LAST_NAME, c.MIDDLE_INITIAL,
                   c.DOB, c.DATE_CREATED, c.DATE_MODIFIED, c.MODIFIED_BY, c.CREATED_BY, c.LOAD_DATE
              FROM STG_ECI_D_CHILD c
            UNION ALL
            SELECT 'ECI_FAMILY' AS SOURCE_TABLE, fam.ID_FAMILY AS ID, fam.FIRST_NAME, fam.LAST_NAME,
                   fam.MIDDLE_INITIAL, fam.DOB, fam.DATE_CREATED, fam.DATE_MODIFIED, fam.MODIFIED_BY,
                   fam.CREATED_BY, fam.LOAD_DATE
              FROM STG_ECI_D_FAMILY fam
        ),
        -- Exp_ECI_Data_Load
        exp_load AS (
            SELECT s.*,
                   LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')   AS pkey_src_object,
                   'ECI'                                                                           AS src_system,
                   SUBSTR(TRIM(NVL(s.FIRST_NAME, '')
                               || IFF(s.MIDDLE_INITIAL IS NOT NULL, ' ' || TRIM(s.MIDDLE_INITIAL), '')
                               || ' ' || NVL(LTRIM(s.LAST_NAME), '')), 1, 10)                       AS full_name
              FROM src s
        ),
        -- lookups of the mapping
        sts AS (    -- Lookup_STG_ECI_PTY_INACTIVE_STS (any row)
            SELECT i.SRC_KEY, i.ROWID_SYSTEM, i.DEACTIVATION_STS
              FROM STG_ECI_PTY_INACTIVE_STS i
           QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY, i.ROWID_SYSTEM
                                          ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
        ),
        xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'ECI')
            SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
              FROM C_B_PTY_XREF x
             WHERE TRIM(x.ROWID_SYSTEM) = 'ECI'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
        ),
        dup AS (    -- Lookup_V_ECI_ETL_LU_DUP_CASES
            SELECT DISTINCT d.SOURCE_TABLE, d.ID FROM V_ECI_ETL_LU_DUP_CASES d
        ),
        fam AS (    -- Lookup_V_ECI_ETL_LU_FAMILY_VALIDATION
            SELECT f.SOURCE_TABLE, f.ID_FAMILY, f.FAM_NAME_STATUS, f.FAM_PHONE_AND_ADDRESS_STS, f.FAM_INACTIVE_STS
              FROM V_ECI_ETL_LU_FAMILY_VALIDATION f
           QUALIFY ROW_NUMBER() OVER (PARTITION BY f.SOURCE_TABLE, f.ID_FAMILY ORDER BY f.ID_FAMILY) = 1
        ),
        -- lookups + mplt_Name_Standardization_Indv_Member
        enriched AS (
            SELECT e.*,
                   sts.DEACTIVATION_STS                                                    AS deactivation_sts,
                   xref.HUB_STATE_IND                                                      AS hub_state_ind,
                   dup.ID                                                                  AS omit_id,
                   IFF(fam.FAM_NAME_STATUS IS NULL AND fam.FAM_PHONE_AND_ADDRESS_STS IS NULL
                       AND fam.FAM_INACTIVE_STS IS NULL, 'N', 'Y')                         AS fam_inactive_yn,
                   -- no prefix / suffix is passed, so their lookups cannot match
                   fn_snow_helper15_common(e.FIRST_NAME, e.MIDDLE_INITIAL, e.LAST_NAME, e.full_name, NULL, NULL,
                                           NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
              FROM exp_load e
              LEFT JOIN sts  ON sts.SRC_KEY = e.pkey_src_object AND sts.ROWID_SYSTEM = e.src_system
              LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = e.pkey_src_object
              LEFT JOIN dup  ON dup.SOURCE_TABLE = e.SOURCE_TABLE AND dup.ID = e.ID
              LEFT JOIN fam  ON fam.SOURCE_TABLE = e.SOURCE_TABLE AND fam.ID_FAMILY = e.ID
              -- junk-name lookups inside mplt_Name_Standardization_Indv_Member
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(e.FIRST_NAME)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(e.LAST_NAME)) AND jl.IS_LAST_JUNK
        ),
        -- Exp_Consolidate_Exceptions + Rtr_Valid_Party conditions + Exp_Invalid_PTY_NM
        named AS (
            SELECT n.*,
                   n.nm:first_name::VARCHAR  AS std_first_name,
                   n.nm:middle_name::VARCHAR AS std_mdl_name,
                   n.nm:last_name::VARCHAR   AS std_lst_name,
                   /* VALIDATION */ (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
                                     OR fn_snow_helper03_common(n.nm:last_name::VARCHAR)) AS name_missing
              FROM enriched n
        ),
        routed AS (
            SELECT r.*,
                   (r.name_missing AND r.fam_inactive_yn = 'N')                                  AS grp_invalid_party_name,
                   (r.name_missing OR r.omit_id IS NOT NULL OR r.fam_inactive_yn = 'Y')          AS grp_deactivation,
                   (r.deactivation_sts IS NOT NULL AND NOT r.name_missing AND r.omit_id IS NULL
                    AND r.fam_inactive_yn = 'N')                                                 AS grp_reactivation,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name' END AS exc_code_name,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'First Name'
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Last Name' END        AS exc_attribute_name,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN r.std_first_name
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN r.std_lst_name END     AS exc_attribute_value,
                   fn_snow_helper02_common(r.hub_state_ind)                                      AS new_deactivation_sts
              FROM named r
        )
        SELECT r.*,
               ex.EXCEPTION_DESC     AS exc_desc_name,
               ex.EXCEPTION_TYPE     AS exc_type_name,
               :l_run_ts             AS run_ts,
               :c_mapping            AS mapping_name,
               'Deactivation'        AS action_deactivation,
               'Reactivation'        AS action_reactivation,
               /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
               ROW_NUMBER() OVER (PARTITION BY r.grp_invalid_party_name, r.src_system, r.pkey_src_object,
                                               ex.EXCEPTION_TYPE, r.exc_code_name
                                      ORDER BY r.ID) = 1 AS uq_exc_name
          FROM routed r
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (exceptions, deactivation log / status, reactivation log)',
                                   :l_rows) INTO :l_line;
    l_log := l_log || l_line;

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_ECI_PTY_INACTIVE_STS.
    -- Not performed: the IDQ DD_DELETE of STG_ECI_PTY_INACTIVE_STS. This code base never deletes, truncates or drops (rows are only inserted).

    COMMIT;
    RETURN l_log;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

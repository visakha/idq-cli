--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Validation (workflow wf_FSS_Stage_Load, first step).
--
-- Checks the FSS clients (V_FSS_ETL_SRC, rows that are the last active registration of a client or that mark all
-- registrations inactive) and maintains the deactivation list used by every later FSS mapping:
--   * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank      -> EXC_STG_BAD_REC_MEMB
--   * Rtr_Valid_Party.Deactivation       : name blank, client deleted (CLIENT_DTL__CAPXACTION = 'D') or all
--                                          registrations inactive (LAST_INACTV_CLIENT_YN = 'Y')
--                                          -> STG_FSS_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_FSS_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
--   * Rtr_Valid_Party.Reactivation       : has a status, names present, not deleted, not all inactive
--                                          -> STG_FSS_PTY_INACTIVE_STS row inserted with DEACTIVATION_STS =
--                                             'Reactivation' (IDQ links Exp_Log_Reactv to the STATUS table, not the
--                                             log; ported as observed, docs/common_insights.md 1.1). Because later
--                                             mappings skip any key with a non-null status, a reactivated FSS client
--                                             stays excluded - confirm with the business.
--   * Default group: not linked.
--
-- VALIDATION: mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common) then the IDQ blank test
--   (fn_snow_helper03_common). A NULL capture action or inactive flag: "x <> 'D'" is not true for NULL in IDQ or
--   Snowflake, so such rows are not reactivated (docs/common_insights.md section 6).
-- BAD DATA: the exception row writes the computed code with the looked-up description / type, and the source full
--   name as ATTRIBUTE_VALUE. EXC_STG_BAD_REC_MEMB's unique key is applied (Snowflake does not enforce it).
-- TIMELINE: none.
--
-- Not performed: the IDQ DD_DELETE of STG_FSS_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
-- Snapshot: one multi-table INSERT, so the status lookup reads the table as it was before the run.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Validation';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;

    INSERT ALL
        -- Write_Invalid_Party_Name
        WHEN grp_invalid_party_name AND uq_exc_name THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, FIRST_NAME, MIDDLE_NAME, LAST_NAME, RUN_DATE,
                  SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE, BIRTH_DATE, ATTRIBUTE_VALUE)
            VALUES (DT_LAST_UPDATE, mapping_name, exc_attribute_name, std_first_name, std_mdl_name, std_lst_name,
                    run_ts, src_sys, PTY_SRC_KEY, exc_desc_name, exc_type_name, exc_code_name, DT_DOB,
                    std_src_full_name)
        -- Write_STG_FSS_PTY_INACTIVE_LOG (Exp_Log_Deactv)
        WHEN grp_deactivation THEN
            INTO STG_FSS_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (PTY_SRC_KEY, src_sys, action_deactivation, run_ts)
        -- Filt_new_deactivations -> Write_STG_FSS_PTY_INACTIVE_STS2 (Exp_New_Deactvn_Sts)
        WHEN grp_deactivation AND deactivation_sts IS NULL THEN
            INTO STG_FSS_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (PTY_SRC_KEY, src_sys, new_deactivation_sts, run_ts)
        -- Write_STG_FSS_PTY_INACTIVE_STS (Exp_Log_Reactv: ACTION -> DEACTIVATION_STS, ACTION_DT -> DEACTIVATION_DT)
        WHEN grp_reactivation THEN
            INTO STG_FSS_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (PTY_SRC_KEY, src_sys, action_reactivation, run_ts)
    SELECT *
      FROM (
        WITH
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_V_FSS_ETL_SRC (source filter; the commented-out testing filters are not applied)
        src AS (
            SELECT v.ID_CLIENT, v.PTY_SRC_KEY, v.SOURCE_TYPE, v.NM_FIRST, v.NM_LAST, v.NM_MIDDLE, v.DT_DOB,
                   v.DT_LAST_UPDATE, v.CLIENT_DTL__CAPXACTION, v.STG_UPDATE_DATE, v.LAST_INACTV_CLIENT_YN
              FROM V_FSS_ETL_SRC v
             WHERE (v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y' OR v.LAST_INACTV_CLIENT_YN = 'Y')
        ),
        sts AS (    -- Lookup_STG_FSS_PTY_INACTIVE_STS (any row)
            SELECT i.SRC_KEY, i.DEACTIVATION_STS
              FROM STG_FSS_PTY_INACTIVE_STS i
             WHERE i.ROWID_SYSTEM = 'FSS'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
        ),
        xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'FSS'; blank-padded MDM column trimmed)
            SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
              FROM C_B_PTY_XREF x
             WHERE TRIM(x.ROWID_SYSTEM) = 'FSS'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
        ),
        -- Exp_ECI_Data_Load (sic) + lookups + mplt_Name_Standardization_Indv_Member
        enriched AS (
            SELECT s.*,
                   sts.DEACTIVATION_STS AS deactivation_sts,
                   xref.HUB_STATE_IND   AS hub_state_ind,
                   fn_snow_helper15_common(s.NM_FIRST, s.NM_MIDDLE, s.NM_LAST,
                       TRIM(NVL(s.NM_FIRST, '') || IFF(s.NM_MIDDLE IS NOT NULL, ' ' || TRIM(s.NM_MIDDLE), '')
                            || ' ' || NVL(LTRIM(s.NM_LAST), '')),
                       NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
              FROM src s
              LEFT JOIN sts  ON sts.SRC_KEY = s.PTY_SRC_KEY
              LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = s.PTY_SRC_KEY
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(s.NM_FIRST)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(s.NM_LAST)) AND jl.IS_LAST_JUNK
        ),
        named AS (
            SELECT n.*,
                   n.nm:first_name::VARCHAR    AS std_first_name,
                   n.nm:middle_name::VARCHAR   AS std_mdl_name,
                   n.nm:last_name::VARCHAR     AS std_lst_name,
                   n.nm:src_full_name::VARCHAR AS std_src_full_name,
                   /* VALIDATION */ (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
                                     OR fn_snow_helper03_common(n.nm:last_name::VARCHAR)) AS name_missing
              FROM enriched n
        ),
        -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
        routed AS (
            SELECT r.*,
                   r.name_missing                                                          AS grp_invalid_party_name,
                   (r.name_missing OR r.CLIENT_DTL__CAPXACTION = 'D' OR r.LAST_INACTV_CLIENT_YN = 'Y') AS grp_deactivation,
                   NVL(r.deactivation_sts IS NOT NULL AND NOT r.name_missing
                       AND r.CLIENT_DTL__CAPXACTION <> 'D' AND r.LAST_INACTV_CLIENT_YN <> 'Y', FALSE) AS grp_reactivation,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name' END    AS exc_code_name,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'First Name'
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Last Name' END            AS exc_attribute_name,
                   fn_snow_helper02_common(r.hub_state_ind)                                          AS new_deactivation_sts
              FROM named r
        )
        SELECT r.*,
               ex.EXCEPTION_DESC     AS exc_desc_name,
               ex.EXCEPTION_TYPE     AS exc_type_name,
               'FSS'                 AS src_sys,
               :l_run_ts             AS run_ts,
               :c_mapping            AS mapping_name,
               'Deactivation'        AS action_deactivation,
               'Reactivation'        AS action_reactivation,
               /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
               ROW_NUMBER() OVER (PARTITION BY r.grp_invalid_party_name, r.PTY_SRC_KEY, ex.EXCEPTION_TYPE,
                                               r.exc_code_name ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1 AS uq_exc_name
          FROM routed r
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (exceptions, log, statuses)', :l_rows) INTO :l_line;

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_FSS_PTY_INACTIVE_STS1.
    -- Not performed: the IDQ DD_DELETE of STG_FSS_PTY_INACTIVE_STS. This code base never deletes, truncates or drops (rows are only inserted).

    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

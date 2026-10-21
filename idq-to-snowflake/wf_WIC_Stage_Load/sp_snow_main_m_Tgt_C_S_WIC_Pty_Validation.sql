--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Validation (workflow wf_WIC_Stage_Load, first step).
--
-- Checks the WIC parties (V_WIC_ETL_SRC) and maintains the deactivation list used by every later WIC mapping:
--   * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank      -> EXC_STG_BAD_REC_MEMB
--   * Rtr_Valid_Party.Deactivation       : the same condition
--                                          -> STG_WIC_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_WIC_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
--   * Rtr_Valid_Party.Reactivation       : has a status and both names present
--                                          -> STG_WIC_PTY_INACTIVE_LOG ('Reactivation')
--   * Default group: not linked.
--
-- VALIDATION: mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common) then the IDQ blank test.
-- BAD DATA: the exception row writes the computed code (Missing_First_Name / Missing_Last_Name) with the looked-up
--   description / type. EXC_STG_BAD_REC_MEMB's unique key is applied (not enforced by Snowflake).
--   Lookup_C_B_PTY_XREF: TRIM(ROWID_SYSTEM) = 'WIC' (blank-padded MDM column).
-- TIMELINE: none.
--
-- Not performed: the IDQ DD_DELETE of STG_WIC_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
-- Snapshot: all routing happens in one multi-table INSERT, so the lookups see the pre-run status.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Validation';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;

    INSERT ALL
        -- Write_Invalid_Party_Name
        WHEN name_missing AND uq_exc_name THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME, RUN_DATE, SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE,
                  BIRTH_DATE)
            VALUES (DATEKEY, mapping_name, exc_attribute_name, exc_attribute_value, std_first_name, std_mdl_name,
                    std_lst_name, run_ts, src_sys, PTY_SRC_KEY, exc_desc_name, exc_type_name, exc_code_name, DOB)
        -- Write_Deactv_STG_WIC_PTY_INACTIVE_LOG
        WHEN name_missing THEN
            INTO STG_WIC_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (PTY_SRC_KEY, src_sys, action_deactivation, run_ts)
        -- Filt_new_deactivations -> Write_new_STG_WIC_PTY_INACTIVE_STS
        WHEN name_missing AND deactivation_sts IS NULL THEN
            INTO STG_WIC_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (PTY_SRC_KEY, src_sys, new_deactivation_sts, run_ts)
        -- Write_STG_WIC_PTY_INACTIVE_LOG (reactivation)
        WHEN deactivation_sts IS NOT NULL AND NOT name_missing THEN
            INTO STG_WIC_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (PTY_SRC_KEY, src_sys, action_reactivation, run_ts)
    SELECT *
      FROM (
        WITH
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        sts AS (    -- Lookup_STG_WIC_PTY_INACTIVE_STS (any row)
            SELECT i.SRC_KEY, i.DEACTIVATION_STS
              FROM STG_WIC_PTY_INACTIVE_STS i
             WHERE i.ROWID_SYSTEM = 'WIC'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
        ),
        xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'WIC')
            SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
              FROM C_B_PTY_XREF x
             WHERE TRIM(x.ROWID_SYSTEM) = 'WIC'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
        ),
        enriched AS (
            SELECT v.SOURCE_TABLE, v.ID, v.FIRST_NAME, v.LAST_NAME, v.MIDDLE_NAME, v.DOB, v.DATEKEY, v.LOAD_DATE,
                   v.PTY_SRC_KEY,
                   sts.DEACTIVATION_STS AS deactivation_sts,
                   xref.HUB_STATE_IND   AS hub_state_ind,
                   fn_snow_helper15_common(v.FIRST_NAME, v.MIDDLE_NAME, v.LAST_NAME,
                       TRIM(NVL(v.FIRST_NAME, '') || IFF(v.MIDDLE_NAME IS NOT NULL, ' ' || TRIM(v.MIDDLE_NAME), '')
                            || ' ' || NVL(LTRIM(v.LAST_NAME), '')),
                       NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
              FROM V_WIC_ETL_SRC v
              LEFT JOIN sts  ON sts.SRC_KEY = v.PTY_SRC_KEY
              LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = v.PTY_SRC_KEY
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(v.FIRST_NAME)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(v.LAST_NAME)) AND jl.IS_LAST_JUNK
        ),
        named AS (
            SELECT n.*,
                   n.nm:first_name::VARCHAR  AS std_first_name,
                   n.nm:middle_name::VARCHAR AS std_mdl_name,
                   n.nm:last_name::VARCHAR   AS std_lst_name,
                   /* VALIDATION */ (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
                                     OR fn_snow_helper03_common(n.nm:last_name::VARCHAR)) AS name_missing
              FROM enriched n
        ),
        -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
        routed AS (
            SELECT r.*,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name' END  AS exc_code_name,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'First Name'
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Last Name' END          AS exc_attribute_name,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN r.std_first_name
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN r.std_lst_name END       AS exc_attribute_value,
                   fn_snow_helper02_common(r.hub_state_ind)                                        AS new_deactivation_sts
              FROM named r
        )
        SELECT r.*,
               ex.EXCEPTION_DESC     AS exc_desc_name,
               ex.EXCEPTION_TYPE     AS exc_type_name,
               'WIC'                 AS src_sys,
               :l_run_ts             AS run_ts,
               :c_mapping            AS mapping_name,
               'Deactivation'        AS action_deactivation,
               'Reactivation'        AS action_reactivation,
               /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
               ROW_NUMBER() OVER (PARTITION BY r.name_missing, r.PTY_SRC_KEY, ex.EXCEPTION_TYPE, r.exc_code_name
                                      ORDER BY r.DATEKEY DESC, r.ID) = 1 AS uq_exc_name
          FROM routed r
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (exceptions, deactivation log / status, reactivation log)',
                                   :l_rows) INTO :l_line;

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_WIC_PTY_INACTIVE_STS
    -- Not performed: the IDQ DD_DELETE of STG_WIC_PTY_INACTIVE_STS. This code base never deletes, truncates or drops (rows are only inserted).

    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

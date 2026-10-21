--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Validation (workflow wf_TTF_Stage_Load, first step).
--
-- Checks the TTF clients (V_TTF_ETL_SRC) and maintains the deactivation list used by every later TTF mapping. Party
-- key = LPAD(CLIENTS_ID, 10, '0'). Names are standardized with CopyOf_mplt_Name_Standardization_Indv_Member
-- (fn_snow_helper15_common; the TTF copy is identical apart from its name).
--   * Rtr_Valid_Party.Invalid_Party_Name : first or last name blank, or 'DECLINED' / 'DO_NOT_DISCLOSE'
--                                          -> EXC_STG_BAD_REC_MEMB (code Missing_/Invalid_First_/Last_Name)
--   * Rtr_Valid_Party.Deactivation       : name blank or 'DECLINED' (not 'DO_NOT_DISCLOSE'), or
--                                          CLIENT_EXISTS_FLAG = 'N'
--                                          -> STG_TTF_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_TTF_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
--   * Rtr_Valid_Party.Reactivation       : has a status, names present and not 'DECLINED', CLIENT_EXISTS_FLAG = 'Y'
--                                          -> STG_TTF_PTY_INACTIVE_LOG ('Reactivation')
--   * Default group: not linked.
--
-- VALIDATION: blank test fn_snow_helper03_common on the standardized names; the placeholders 'DECLINED' and
--   'DO_NOT_DISCLOSE' (any case) are invalid names. A 'DO_NOT_DISCLOSE' name is logged but does not deactivate.
-- BAD DATA: the exception row writes the computed code, with description / type from EXC_LOOKUP_CODE_VALUE, and the
--   source full name as ATTRIBUTE_VALUE. EXC_STG_BAD_REC_MEMB's unique key is applied (not enforced by Snowflake).
--   The source read stores a SQL text that is only a WHERE fragment (test client ids) and is not in custom-query
--   mode: it is not applied. Lookup_C_B_PTY_XREF: TRIM(ROWID_SYSTEM) = 'TTF' (the MDM column is blank padded).
-- TIMELINE: none.
--
-- Not performed: the IDQ DD_DELETE of STG_TTF_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty_Validation';
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
            VALUES (CREATEDDATE, mapping_name, exc_code_name /* ATTRIBUTE_NAME_Name has the same expression */,
                    std_first_name, std_mdl_name, std_lst_name, run_ts, src_sys, pkey_src_object, exc_desc_name,
                    exc_type_name, exc_code_name, DOB, std_src_full_name)
        -- Write_STG_TTF_PTY_INACTIVE_LOG (Exp_Log_Deactv)
        WHEN grp_deactivation THEN
            INTO STG_TTF_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, src_sys, action_deactivation, run_ts)
        -- Filt_new_deactivations -> Write_STG_TTF_PTY_INACTIVE_STS2
        WHEN grp_deactivation AND deactivation_sts IS NULL THEN
            INTO STG_TTF_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (pkey_src_object, src_sys, new_deactivation_sts, run_ts)
        -- Write_STG_TTF_PTY_INACTIVE_LOG1 (Exp_Log_Reactv)
        WHEN grp_reactivation THEN
            INTO STG_TTF_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, src_sys, action_reactivation, run_ts)
    SELECT *
      FROM (
        WITH
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        sts AS (    -- Lookup_STG_TTF_PTY_INACTIVE_STS (any row)
            SELECT i.SRC_KEY, i.DEACTIVATION_STS
              FROM STG_TTF_PTY_INACTIVE_STS i
             WHERE i.ROWID_SYSTEM = 'TTF'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
        ),
        xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter TRIM(ROWID_SYSTEM) = 'TTF')
            SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
              FROM C_B_PTY_XREF x
             WHERE TRIM(x.ROWID_SYSTEM) = 'TTF'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
        ),
        enriched AS (
            SELECT v.CLIENTS_ID, v.FIRSTNAME, v.LASTNAME, v.MIDDLENAME, v.DOB, v.CREATEDDATE, v.SUBMITDATE,
                   v.CLIENT_EXISTS_FLAG,
                   LPAD(TO_VARCHAR(v.CLIENTS_ID), 10, '0')  AS pkey_src_object,
                   sts.DEACTIVATION_STS                     AS deactivation_sts,
                   xref.HUB_STATE_IND                       AS hub_state_ind,
                   fn_snow_helper15_common(v.FIRSTNAME, v.MIDDLENAME, v.LASTNAME,
                       TRIM(NVL(v.FIRSTNAME, '') || IFF(v.MIDDLENAME IS NOT NULL, ' ' || TRIM(v.MIDDLENAME), '')
                            || ' ' || NVL(LTRIM(v.LASTNAME), '')),
                       NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
              FROM V_TTF_ETL_SRC v
              LEFT JOIN sts  ON sts.SRC_KEY = LPAD(TO_VARCHAR(v.CLIENTS_ID), 10, '0')
              LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = LPAD(TO_VARCHAR(v.CLIENTS_ID), 10, '0')
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(v.FIRSTNAME)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(v.LASTNAME)) AND jl.IS_LAST_JUNK
        ),
        named AS (
            SELECT n.*,
                   n.nm:first_name::VARCHAR    AS std_first_name,
                   n.nm:middle_name::VARCHAR   AS std_mdl_name,
                   n.nm:last_name::VARCHAR     AS std_lst_name,
                   n.nm:src_full_name::VARCHAR AS std_src_full_name,
                   /* VALIDATION */
                   (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
                    OR fn_snow_helper03_common(n.nm:last_name::VARCHAR))                          AS name_missing,
                   NVL(UPPER(n.nm:last_name::VARCHAR) = 'DECLINED'
                       OR UPPER(n.nm:first_name::VARCHAR) = 'DECLINED', FALSE)                    AS name_declined,
                   NVL(UPPER(n.nm:last_name::VARCHAR) = 'DO_NOT_DISCLOSE'
                       OR UPPER(n.nm:first_name::VARCHAR) = 'DO_NOT_DISCLOSE', FALSE)             AS name_undisclosed
              FROM enriched n
        ),
        -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
        routed AS (
            SELECT r.*,
                   (r.name_missing OR r.name_declined OR r.name_undisclosed)                      AS grp_invalid_party_name,
                   (r.name_missing OR r.name_declined OR NVL(r.CLIENT_EXISTS_FLAG = 'N', FALSE))  AS grp_deactivation,
                   NVL(r.deactivation_sts IS NOT NULL AND NOT r.name_missing
                       AND NOT (UPPER(r.std_lst_name) = 'DECLINED') AND NOT (UPPER(r.std_first_name) = 'DECLINED')
                       AND r.CLIENT_EXISTS_FLAG = 'Y', FALSE)                                      AS grp_reactivation,
                   CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                        WHEN UPPER(TRIM(r.std_first_name)) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_First_Name'
                        WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name'
                        WHEN UPPER(TRIM(r.std_lst_name)) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_Last_Name'
                        ELSE 'Valid' END                                                           AS exc_code_name,
                   fn_snow_helper02_common(r.hub_state_ind)                                        AS new_deactivation_sts
              FROM named r
        )
        SELECT r.*,
               ex.EXCEPTION_DESC     AS exc_desc_name,
               ex.EXCEPTION_TYPE     AS exc_type_name,
               'TTF'                 AS src_sys,
               :l_run_ts             AS run_ts,
               :c_mapping            AS mapping_name,
               'Deactivation'        AS action_deactivation,
               'Reactivation'        AS action_reactivation,
               /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
               ROW_NUMBER() OVER (PARTITION BY r.grp_invalid_party_name, r.pkey_src_object, ex.EXCEPTION_TYPE,
                                               r.exc_code_name ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1 AS uq_exc_name
          FROM routed r
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (exceptions, deactivation log / status, reactivation log)',
                                   :l_rows) INTO :l_line;

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_TTF_PTY_INACTIVE_STS1
    -- Not performed: the IDQ DD_DELETE of STG_TTF_PTY_INACTIVE_STS. This code base never deletes, truncates or drops (rows are only inserted).

    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

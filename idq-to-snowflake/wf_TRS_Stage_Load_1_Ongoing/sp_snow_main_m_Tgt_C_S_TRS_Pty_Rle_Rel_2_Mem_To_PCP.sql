--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP (workflow
-- wf_TRS_Stage_Load_1_Ongoing).
--
-- Member-to-primary-care-provider relationships (STG_TRS_D_IN_MANAGED_CARE with a provider, one source key per
-- individual) into C_S_TRS_PTY_RLE_REL_PROV (insert only, never truncated):
--   -> Filt_Numeric_Prov: IS_NUMBER(PROVIDER_NUM)
--   -> Lookup_C_B_PTY_RLE_ALT_ID (custom lookup SQL: the TPI alternate id '006' of C21 in the MDM, latest source key
--      per id) -> Exp_Build_FK: provider key = source key up to its second '|'; type 'Member PCO' when the key holds
--      '|HCO', else 'Member PCP'; relationship key = member|provider|100
--   -> Rout_Valid_vs_Exceptions
--        Period_Start_Date_GT_Period_End_Date -> EXC_STG_BAD_REC_MEMB ('Period_Start_Date_>_Period_End_Date')
--        Valid_Records (both keys, start <= end or open)
--          -> MPLT_Member_PTY_RLE_REL_Consolidation (inlined) -> mplt_Pty_Rle_Rel_Timeline_Validation (inlined,
--             TIMELINE) -> C_S_TRS_PTY_RLE_REL_PROV
--        Default (anything else, e.g. a key missing) -> EXC_STG_BAD_REC_MEMB ('Invalid_Member' / 'Invalid_PCP')
--
-- VALIDATION: the provider number must be numeric (fn_snow_helper01_common) and known as a C21 TPI in the MDM; the
--   begin date may not be after the end date.
-- BAD DATA: a non-numeric provider number is dropped silently (Filt_Numeric_Prov). A missing member or provider key
--   is logged as Invalid_Member / Invalid_PCP (computed code, looked-up description / type). Unfed ports written as
--   NULL: CREATE_DATE (not fed into the timeline mapplet in this mapping), ROWID_OBJECT, DELETED_*, UPDATED_BY,
--   CREATOR. SRC_LAST_UPD_DT = source CREATE_DT. The stored source filter PROVIDER_NUM is not null duplicates the
--   custom query's WHERE. The MDM cross-reference filter ROWID_SYSTEM = 'C21' is trimmed (blank-padded MDM column).
--   Unique keys Snowflake does not enforce are applied: C_S_TRS_PTY_RLE_REL_PROV (PKEY_SRC_OBJECT, VERSION_SEQ) and
--   EXC_STG_BAD_REC_MEMB.
-- TIMELINE (stale MDM timeline, ported as IDQ does it - same mapplet as m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem):
--   DST-corrected end date (fn_snow_helper35_common + REF_DYLGHT_SVNGS_TM); every end-dated row emitted twice (closed
--   version + open copy); VERSION_SEQ re-ranked per key (start ascending, end descending, NULL high);
--   PERIOD_REFERENCE_TIME = end date and TIMELINE_ACTION = 2 when end dated; HUB_STATE_IND = 1 on the open row with
--   VERSION_SEQ 1 (input not fed, so NULL elsewhere).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP (
    P_PCP_REL_TP VARCHAR DEFAULT '100'   -- $PCP_REL_TP
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / systimestamp()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_REL_PROV. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Rout_Valid_vs_Exceptions.Period_Start_Date_GT_Period_End_Date
        WHEN row_kind = 'ROUTER' AND dates_reversed AND uq_exc_dates THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  PERIOD_END_DATE, SRC_SYS_ID_3, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES (src_sys, INDV_ID, PROVIDER_NUM, mapping_name, run_ts, attr_dates, BEGIN_DT, END_DT, pty_rle_fk_2,
                    exc_dates_code, exc_dates_desc, exc_dates_type)
        -- Rout_Valid_vs_Exceptions.Default -> Exp_safe_EXC_STG_BAD_REC_MEMB
        WHEN row_kind = 'ROUTER' AND NOT is_valid AND NOT dates_reversed AND uq_exc_default THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, PERIOD_START_DATE,
                  PERIOD_END_DATE, SRC_SYS_ID_1, SRC_SYS_ID_2, ATTRIBUTE_VALUE, ATTRIBUTE_NAME)
            VALUES (src_sys, run_ts, mapping_name, exc_default_code, exc_default_desc, exc_default_type, BEGIN_DT,
                    END_DT, INDV_ID, PROVIDER_NUM, PROVIDER_NUM, attr_provider)
        -- Valid_Records -> consolidation -> timeline -> Write_C_S_TRS_PTY_RLE_REL_PROV
        WHEN row_kind = 'TIMELINE' AND uq_rel THEN
            INTO C_S_TRS_PTY_RLE_REL_PROV
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE,
                  SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, HIERARCHY_CODE, REL_TP,
                  SRC_LAST_UPD_DT, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, ROWID_OBJECT, DELETED_IND, DELETED_DATE,
                  DELETED_BY, UPDATED_BY, CREATOR)
            VALUES (pkey_src_object, BEGIN_DT, tl_period_end_date, tl_version_seq, run_ts, NULL, pkey_src_object,
                    tl_hub_state_ind, pty_rle_fk_1, pty_rle_fk_2, rel_type_code, hierarchy_code, rel_tp, CREATE_DT,
                    tl_period_end_date, tl_timeline_action, NULL, NULL, NULL, NULL, NULL, NULL)
    SELECT *
      FROM (
        WITH
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        lkp_dst AS (SELECT * FROM TABLE(fn_snow_helper47_common())),
        -- Read_STG_TRS_D_IN_MANAGED_CARE (custom SQL, query mode SEMI) + Filt_Numeric_Prov
        min_pk AS (
            SELECT indv_id, MIN(pty_pk) pty_pk FROM STG_TRS_VALID_MEMBERS GROUP BY indv_id
        ),
        src AS (
            SELECT mc.indv_id AS INDV_ID, mc.history_seq AS HISTORY_SEQ, mc.mc_prog_code AS MC_PROG_CODE,
                   mc.begin_dt AS BEGIN_DT, mc.create_dt AS CREATE_DT, mc.provider_num AS PROVIDER_NUM,
                   mc.end_dt AS END_DT, vm.pty_pk AS PTY_PK
              FROM STG_TRS_D_IN_MANAGED_CARE mc
              JOIN min_pk vm ON mc.indv_id = vm.indv_id
             WHERE mc.provider_num IS NOT NULL
               AND fn_snow_helper01_common(mc.provider_num) = 1                              -- Filt_Numeric_Prov
        ),
        -- Lookup_C_B_PTY_RLE_ALT_ID (custom lookup SQL)
        tpi_src_key AS (
            SELECT bo.alt_id_val, xr.pkey_src_object
              FROM C_B_PTY_RLE_ALT_ID bo
             INNER JOIN C_B_PTY_RLE_ALT_ID_XREF xr ON bo.rowid_object = xr.rowid_object
             WHERE bo.alt_id_tp = '006' AND TRIM(xr.rowid_system) = 'C21' AND xr.hub_state_ind = 1
           QUALIFY ROW_NUMBER() OVER (PARTITION BY bo.alt_id_val ORDER BY xr.src_last_upd_dt DESC) = 1
        ),
        -- Exp_Build_FK
        keyed AS (
            SELECT s.*,
                   IFF(s.PTY_PK IS NULL, NULL, TRIM(s.PTY_PK) || '|Member')                        AS pty_rle_fk_1,
                   SUBSTR(TRIM(t.pkey_src_object), 1, REGEXP_INSTR(TRIM(t.pkey_src_object), '[|]', 1, 2) - 1)
                                                                                                  AS pty_rle_fk_2,
                   IFF(CONTAINS(TRIM(t.pkey_src_object), '|HCO'), 'Member PCO', 'Member PCP')     AS rel_type_code
              FROM src s
              LEFT JOIN tpi_src_key t ON t.alt_id_val = s.PROVIDER_NUM
        ),
        routed AS (
            SELECT k.*,
                   NVL(k.pty_rle_fk_1, '') || '|' || NVL(k.pty_rle_fk_2, '') || '|' || :P_PCP_REL_TP AS pkey_src_object,
                   /* VALIDATION */ NVL(k.BEGIN_DT > k.END_DT, FALSE)                              AS dates_reversed,
                   /* VALIDATION */ (k.pty_rle_fk_1 IS NOT NULL AND k.pty_rle_fk_2 IS NOT NULL
                                     AND NVL(k.BEGIN_DT <= k.END_DT OR k.END_DT IS NULL, FALSE))   AS is_valid
              FROM keyed k
        ),
        -- MPLT_Member_PTY_RLE_REL_Consolidation (type always present here; UPDATE_DT not fed)
        consolidated AS (
            SELECT r.*
              FROM routed r
             WHERE r.is_valid AND r.rel_type_code IS NOT NULL
           QUALIFY ROW_NUMBER() OVER (PARTITION BY r.pkey_src_object, r.END_DT, r.BEGIN_DT
                                          ORDER BY r.CREATE_DT DESC NULLS FIRST) = 1
        ),
        -- mplt_DST_Correction (TIMELINE)
        prepared AS (
            SELECT c.*,
                   /* TIMELINE */ fn_snow_helper35_common(c.BEGIN_DT, c.END_DT, d.DST IS NOT NULL)  AS dst_end_date
              FROM consolidated c
              LEFT JOIN lkp_dst d ON d.DST = DATEADD(hour, 2, c.END_DT)
        ),
        -- rtr_Active_Records + union_All_Records (TIMELINE)
        versions AS (
            SELECT p.*, p.dst_end_date AS tl_period_end_date FROM prepared p
            UNION ALL
            SELECT p.*, NULL::TIMESTAMP_NTZ FROM prepared p WHERE p.dst_end_date IS NOT NULL
        ),
        -- SRT_PKEY_FOR_RANK + exp_RANK + exp_Stage_Output_Attributes (TIMELINE)
        timeline AS (
            SELECT v.*,
                   ROW_NUMBER() OVER (PARTITION BY v.pkey_src_object
                                      ORDER BY v.BEGIN_DT ASC NULLS LAST, v.tl_period_end_date DESC NULLS FIRST) AS tl_version_seq
              FROM versions v
        ),
        timeline_flagged AS (
            SELECT t.*,
                   IFF(t.tl_period_end_date IS NOT NULL, 2, NULL)                          AS tl_timeline_action,
                   IFF(t.tl_period_end_date IS NULL AND t.tl_version_seq = 1, 1, NULL)     AS tl_hub_state_ind,
                   /* BAD DATA: unique key (PKEY_SRC_OBJECT, VERSION_SEQ) not yet in the table */
                   xr.PKEY_SRC_OBJECT IS NULL                                               AS uq_rel
              FROM timeline t
              LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_REL_PROV) xr
                     ON xr.PKEY_SRC_OBJECT = t.pkey_src_object AND xr.VERSION_SEQ = t.tl_version_seq
        ),
        router AS (
            SELECT r.*,
                   CASE WHEN r.pty_rle_fk_1 IS NULL THEN 'Invalid_Member'
                        WHEN r.pty_rle_fk_2 IS NULL THEN 'Invalid_PCP' END                 AS exc_default_code
              FROM routed r
        ),
        router_flagged AS (
            SELECT r.*,
                   /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
                   ROW_NUMBER() OVER (PARTITION BY r.dates_reversed, r.INDV_ID, r.PROVIDER_NUM, r.pty_rle_fk_2
                                          ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_dates,
                   ROW_NUMBER() OVER (PARTITION BY NOT r.is_valid AND NOT r.dates_reversed, r.INDV_ID,
                                                   r.PROVIDER_NUM, r.exc_default_code
                                          ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_default
              FROM router r
        ),
        both_kinds AS (
            SELECT 'ROUTER' AS row_kind, r.INDV_ID, r.PROVIDER_NUM, r.BEGIN_DT, r.END_DT, r.CREATE_DT,
                   r.pty_rle_fk_1, r.pty_rle_fk_2, r.rel_type_code, r.pkey_src_object, r.is_valid, r.dates_reversed,
                   r.exc_default_code, NULL::TIMESTAMP_NTZ AS tl_period_end_date, NULL::NUMBER AS tl_version_seq,
                   NULL::NUMBER AS tl_timeline_action, NULL::NUMBER AS tl_hub_state_ind, NULL::BOOLEAN AS uq_rel,
                   r.uq_exc_dates, r.uq_exc_default
              FROM router_flagged r
            UNION ALL
            SELECT 'TIMELINE', t.INDV_ID, t.PROVIDER_NUM, t.BEGIN_DT, t.END_DT, t.CREATE_DT, t.pty_rle_fk_1,
                   t.pty_rle_fk_2, t.rel_type_code, t.pkey_src_object, t.is_valid, t.dates_reversed, NULL,
                   t.tl_period_end_date, t.tl_version_seq, t.tl_timeline_action, t.tl_hub_state_ind, t.uq_rel,
                   NULL, NULL
              FROM timeline_flagged t
        )
        SELECT b.*,
               'TRS'                                         AS src_sys,
               :l_run_ts                                     AS run_ts,
               :c_mapping                                    AS mapping_name,
               'Member'                                      AS hierarchy_code,
               :P_PCP_REL_TP                                 AS rel_tp,
               'Effective Date'                              AS attr_dates,
               'Provider'                                    AS attr_provider,
               'Period_Start_Date_>_Period_End_Date'         AS exc_dates_code,
               xd.EXCEPTION_DESC                             AS exc_dates_desc,
               xd.EXCEPTION_TYPE                             AS exc_dates_type,
               xx.EXCEPTION_DESC                             AS exc_default_desc,
               xx.EXCEPTION_TYPE                             AS exc_default_type
          FROM both_kinds b
          LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date'
          LEFT JOIN lkp_exc xx ON xx.EXCEPTION_CODE = b.exc_default_code
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TRS_PTY_RLE_REL_PROV, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

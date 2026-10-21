--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Alt_Id (workflow wf_FSS_Stage_Load).
--
-- One alternate id per active FSS client into C_S_FSS_PTY_RLE_ALT_ID (insert only, never truncated): the FSS client
-- id, type '022' for SOURCE_TYPE 'CLIENT' and '023' otherwise.
--   Read_V_FSS_ETL_SRC (last active registration) -> Filter: party not in STG_FSS_PTY_INACTIVE_STS -> target
--
-- VALIDATION: none (no rule runs here).
-- BAD DATA: C_S_FSS_PTY_RLE_ALT_ID is unique on (PKEY_SRC_OBJECT, VERSION_SEQ), which Snowflake does not enforce:
--   one row per key is written and keys already in the table are skipped (IDQ gets the duplicate rejected).
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = DT_CREATED.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_FSS_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO C_S_FSS_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, SRC_LAST_UPD_DT, HUB_STATE_IND, STS_CD, SRC_ROWID,
            LAST_UPDATE_DATE, VERSION_SEQ, ALT_ID_TP_FLTR, CREATE_DATE, PERIOD_START_DATE)
    SELECT x.pkey_src_object, x.pty_rle_fk, x.alt_id_tp, LPAD(TO_VARCHAR(x.ID_CLIENT), 10, '0'), :l_run_ts, 1,
           'Issued', NVL(TO_VARCHAR(x.ID_CLIENT), '') || '|' || x.alt_id_tp, :l_run_ts,
           1 /* TIMELINE: VERSION_SEQ */, x.alt_id_tp, x.DT_CREATED, x.DT_CREATED /* TIMELINE */
      FROM (SELECT v.SOURCE_TYPE, v.DT_CREATED, v.DT_LAST_UPDATE, v.PTY_SRC_KEY, v.ID_CLIENT,
                   NVL(v.PTY_SRC_KEY, '') || '|Member'                                      AS pty_rle_fk,
                   IFF(v.SOURCE_TYPE = 'CLIENT', '022', '023')                              AS alt_id_tp,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|' || IFF(v.SOURCE_TYPE = 'CLIENT', '022', '023') || '|'
                   || NVL(LPAD(TO_VARCHAR(v.ID_CLIENT), 10, '0'), '')                        AS pkey_src_object
              FROM V_FSS_ETL_SRC v
             -- source filter (the commented-out testing filter is not applied)
             WHERE v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y') x
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = x.pkey_src_object
     -- Lkp_STG_FSS_PTY_INACTIVE_STS + Filter: IsNull(DEACTIVATION_STS)
     WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = x.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL)
       /* BAD DATA: unique key not yet in the table */
       AND xa.PKEY_SRC_OBJECT IS NULL
    /* BAD DATA: first row per key in this run */
    QUALIFY ROW_NUMBER() OVER (PARTITION BY x.pkey_src_object ORDER BY x.DT_LAST_UPDATE DESC NULLS LAST) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert C_S_FSS_PTY_RLE_ALT_ID', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

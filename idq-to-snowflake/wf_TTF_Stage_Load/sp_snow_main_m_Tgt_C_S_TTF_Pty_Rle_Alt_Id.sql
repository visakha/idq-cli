--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Rle_Alt_Id (workflow wf_TTF_Stage_Load).
--
-- One alternate id per active TTF client into C_S_TTF_PTY_RLE_ALT_ID (insert only, never truncated): the party key
-- itself, type '024'.
--   Read_V_TTF_ETL_SRC -> Filter: party not in STG_TTF_PTY_INACTIVE_STS -> target
--
-- VALIDATION: none (no rule runs here).
-- BAD DATA: the source read stores a SQL text that is only a WHERE fragment (test client ids) and is not in
--   custom-query mode: it is not applied. C_S_TTF_PTY_RLE_ALT_ID is unique on (PKEY_SRC_OBJECT, VERSION_SEQ), which
--   Snowflake does not enforce: one row per key, keys already in the table skipped.
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = run start ($sys.MappingRunStartTime).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TTF_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO C_S_TTF_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE, VERSION_SEQ, CREATE_DATE, PTY_RLE_FK,
            ALT_ID_TP, ALT_ID_VAL, ALT_ID_TP_FLTR, STS_CD, PERIOD_START_DATE, SRC_LAST_UPD_DT)
    SELECT k.pkey_src_object, 1, k.pkey_src_object, :l_run_ts, 1 /* TIMELINE: VERSION_SEQ */, k.SUBMITDATE,
           NVL(k.PTY_SRC_KEY, '') || '|Member', '024', k.PTY_SRC_KEY, '024', 'Issued',
           :l_run_ts /* TIMELINE: $sys.MappingRunStartTime */, k.SUBMITDATE
      FROM (SELECT v.PTY_SRC_KEY, v.SUBMITDATE,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|024|' || NVL(v.PTY_SRC_KEY, '') AS pkey_src_object
              FROM V_TTF_ETL_SRC v
             -- Lkp_STG_TTF_PTY_INACTIVE_STS + Filter
             WHERE NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                                  AND i.DEACTIVATION_STS IS NOT NULL)) k
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = k.pkey_src_object
     /* BAD DATA: unique key not yet in the table, first row per key in this run */
     WHERE xa.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY k.pkey_src_object ORDER BY k.SUBMITDATE DESC NULLS LAST) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert C_S_TTF_PTY_RLE_ALT_ID', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

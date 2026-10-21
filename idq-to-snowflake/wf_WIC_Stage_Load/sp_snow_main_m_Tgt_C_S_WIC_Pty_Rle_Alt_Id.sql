--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Rle_Alt_Id (workflow wf_WIC_Stage_Load).
--
-- One alternate id per active WIC party into C_S_WIC_PTY_RLE_ALT_ID (insert only, never truncated): the WIC id padded
-- to 12, type '020' for SOURCE_TABLE 'CLIENT' and '021' otherwise.
--   Read_V_WIC_ETL_SRC -> Filter: party not in STG_WIC_PTY_INACTIVE_STS -> target
--
-- VALIDATION: none (no rule runs here).
-- BAD DATA: HUB_STATE_IND is not linked in this IDQ mapping (left to the column default). C_S_WIC_PTY_RLE_ALT_ID is
--   unique on (PKEY_SRC_OBJECT, VERSION_SEQ), which Snowflake does not enforce: one row per key, keys already in the
--   table skipped.
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = DATEKEY.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_WIC_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO C_S_WIC_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE,
            ALT_ID_TP_FLTR, SRC_LAST_UPD_DT, STS_CD, PERIOD_START_DATE)
    SELECT x.pkey_src_object, NVL(TO_VARCHAR(x.ID), '') || '|' || x.alt_id_tp, 1 /* TIMELINE: VERSION_SEQ */,
           x.pty_rle_fk, x.alt_id_tp, LPAD(TO_VARCHAR(x.ID), 12, '0'), x.DATEKEY, :l_run_ts, x.alt_id_tp,
           x.DATEKEY /* IIF(IsNull(DATEKEY), DATEKEY, DATEKEY) */, 'Issued', x.DATEKEY /* TIMELINE */
      FROM (SELECT v.ID, v.PTY_SRC_KEY, v.DATEKEY, v.SOURCE_TABLE,
                   NVL(v.PTY_SRC_KEY, '') || '|Member'                                    AS pty_rle_fk,
                   IFF(v.SOURCE_TABLE = 'CLIENT', '020', '021')                           AS alt_id_tp,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|' || IFF(v.SOURCE_TABLE = 'CLIENT', '020', '021') || '|'
                   || NVL(LPAD(TO_VARCHAR(v.ID), 12, '0'), '')                             AS pkey_src_object
              FROM V_WIC_ETL_SRC v) x
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = x.pkey_src_object
     -- Lookup_STG_WIC_PTY_INACTIVE_STS + Filter
     WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = x.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                          AND i.DEACTIVATION_STS IS NOT NULL)
       /* BAD DATA: unique key not yet in the table, first row per key in this run */
       AND xa.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY x.pkey_src_object ORDER BY x.DATEKEY DESC NULLS LAST) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert C_S_WIC_PTY_RLE_ALT_ID', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

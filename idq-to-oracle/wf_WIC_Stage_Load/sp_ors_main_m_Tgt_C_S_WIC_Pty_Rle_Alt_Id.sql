--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Rle_Alt_Id (workflow wf_WIC_Stage_Load).
--
-- One alternate id per active WIC party into C_S_WIC_PTY_RLE_ALT_ID (truncated first): the WIC id padded to 12,
-- type '020' for SOURCE_TABLE 'CLIENT' and '021' otherwise.
--   Read_V_WIC_ETL_SRC -> Filter: party not in STG_WIC_PTY_INACTIVE_STS -> target
--
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = DATEKEY.
-- HUB_STATE_IND is not linked in this IDQ mapping (left to the column default).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    sp_ors_helper01_common('C_S_WIC_PTY_RLE_ALT_ID');

    INSERT INTO C_S_WIC_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE,
            ALT_ID_TP_FLTR, SRC_LAST_UPD_DT, STS_CD, PERIOD_START_DATE)
    SELECT x.pty_rle_fk || '|' || x.alt_id_tp || '|' || LPAD(x.ID, 12, '0'), TO_CHAR(x.ID) || '|' || x.alt_id_tp,
           1 /* TIMELINE: VERSION_SEQ */, x.pty_rle_fk, x.alt_id_tp, LPAD(x.ID, 12, '0'), x.DATEKEY, l_run_ts,
           x.alt_id_tp, x.DATEKEY /* IIF(IsNull(DATEKEY), DATEKEY, DATEKEY) */, 'Issued', x.DATEKEY /* TIMELINE */
      FROM (SELECT v.ID, v.PTY_SRC_KEY, v.DATEKEY, v.SOURCE_TABLE,
                   v.PTY_SRC_KEY || '|Member'                                   AS pty_rle_fk,
                   CASE WHEN v.SOURCE_TABLE = 'CLIENT' THEN '020' ELSE '021' END AS alt_id_tp
              FROM V_WIC_ETL_SRC v) x
     -- Lookup_STG_WIC_PTY_INACTIVE_STS + Filter
     WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = x.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    sp_ors_helper02_common(c_mapping, 'insert C_S_WIC_PTY_RLE_ALT_ID', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id;
/

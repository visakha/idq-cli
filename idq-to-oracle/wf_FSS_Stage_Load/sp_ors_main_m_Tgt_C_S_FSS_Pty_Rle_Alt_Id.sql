--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Alt_Id (workflow wf_FSS_Stage_Load).
--
-- One alternate id per active FSS client into C_S_FSS_PTY_RLE_ALT_ID (truncated first): the FSS client id,
-- type '022' for SOURCE_TYPE 'CLIENT' and '023' otherwise.
--   Read_V_FSS_ETL_SRC (last active registration) -> Filter: party not in STG_FSS_PTY_INACTIVE_STS -> target
--
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = DT_CREATED.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_FSS_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    sp_ors_helper01_common('C_S_FSS_PTY_RLE_ALT_ID');

    INSERT INTO C_S_FSS_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, SRC_LAST_UPD_DT, HUB_STATE_IND, STS_CD, SRC_ROWID,
            LAST_UPDATE_DATE, VERSION_SEQ, ALT_ID_TP_FLTR, CREATE_DATE, PERIOD_START_DATE)
    SELECT x.pty_rle_fk || '|' || x.alt_id_tp || '|' || LPAD(x.ID_CLIENT, 10, '0'), x.pty_rle_fk, x.alt_id_tp,
           LPAD(x.ID_CLIENT, 10, '0'), l_run_ts, 1, 'Issued', TO_CHAR(x.ID_CLIENT) || '|' || x.alt_id_tp, l_run_ts,
           1 /* TIMELINE: VERSION_SEQ */, x.alt_id_tp, x.DT_CREATED, x.DT_CREATED /* TIMELINE */
      FROM (SELECT v.SOURCE_TYPE, v.DT_CREATED, v.DT_LAST_UPDATE, v.PTY_SRC_KEY, v.ID_CLIENT,
                   v.PTY_SRC_KEY || '|Member'                                  AS pty_rle_fk,
                   CASE WHEN v.SOURCE_TYPE = 'CLIENT' THEN '022' ELSE '023' END AS alt_id_tp
              FROM V_FSS_ETL_SRC v
             -- source filter (the commented-out testing filter is not applied)
             WHERE v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y') x
     -- Lkp_STG_FSS_PTY_INACTIVE_STS + Filter: IsNull(DEACTIVATION_STS)
     WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = x.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    sp_ors_helper02_common(c_mapping, 'insert C_S_FSS_PTY_RLE_ALT_ID', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id;
/

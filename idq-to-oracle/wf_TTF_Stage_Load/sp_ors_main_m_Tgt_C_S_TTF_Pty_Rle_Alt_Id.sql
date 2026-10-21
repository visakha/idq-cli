--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Rle_Alt_Id (workflow wf_TTF_Stage_Load).
--
-- One alternate id per active TTF client into C_S_TTF_PTY_RLE_ALT_ID (insert only, never truncated): the party key itself,
-- type '024'.
--   Read_V_TTF_ETL_SRC -> Filter: party not in STG_TTF_PTY_INACTIVE_STS -> target
-- The source read stores a SQL text that is only a WHERE fragment (test client ids) and is not in custom-query mode:
-- it is not applied.
--
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = run start ($sys.MappingRunStartTime).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TTF_Pty_Rle_Alt_Id';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TTF_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO C_S_TTF_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE, VERSION_SEQ, CREATE_DATE, PTY_RLE_FK,
            ALT_ID_TP, ALT_ID_VAL, ALT_ID_TP_FLTR, STS_CD, PERIOD_START_DATE, SRC_LAST_UPD_DT)
    SELECT v.PTY_SRC_KEY || '|Member' || '|' || '024' || '|' || v.PTY_SRC_KEY, 1,
           v.PTY_SRC_KEY || '|Member' || '|' || '024' || '|' || v.PTY_SRC_KEY, l_run_ts, 1 /* TIMELINE: VERSION_SEQ */,
           v.SUBMITDATE, v.PTY_SRC_KEY || '|Member', '024', v.PTY_SRC_KEY, '024', 'Issued',
           l_run_ts /* TIMELINE: $sys.MappingRunStartTime */, v.SUBMITDATE
      FROM V_TTF_ETL_SRC v
     -- Lkp_STG_TTF_PTY_INACTIVE_STS + Filter
     WHERE NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    sp_ors_helper02_common(c_mapping, 'insert C_S_TTF_PTY_RLE_ALT_ID', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id;
/

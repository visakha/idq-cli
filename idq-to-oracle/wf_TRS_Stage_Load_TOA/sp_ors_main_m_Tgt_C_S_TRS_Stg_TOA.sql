--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Stg_TOA (workflow wf_TRS_Stage_Load_TOA, its only mapping; the
-- daily parent workflow runs it after wf_TRS_Stage_Load_1_Ongoing).
--
-- The TIERS type-of-assistance catalogue (STG_TRS_D_LU_TOA, every row: history and expired codes included) into the
-- MDM lookup staging table C_S_LU_TOA (insert only, never truncated):
--   -> Lkp_LOOKUP_CODE_VALUE_TOA (code type TOA, MSTR_REF_LABEL = TOA_CODE, no SRC_SYS filter, any row)
--        MSTR_REF_CODE -> PKEY_SRC_OBJECT, SRC_ROWID, TOA_CD; MSTR_REF_LABEL -> TOA_LBL
--   -> Lkp_LOOKUP_CODE_VALUE_MBR_PGM (code type MEMBER_PRG, MSTR_REF_LABEL = PROGRAM_CODE, any row)
--        MSTR_REF_CODE -> MBR_PRG_CD (NULL when not configured)
--   -> C_S_LU_TOA: EFF_STRT_DT / EFF_END_DT, TOA_DESC, CREATE_DATE = CREATE_DT, UPDATED_BY = UPDATE_USER_ID,
--      LAST_UPDATE_DATE = run start, CREATOR 'admin', HUB_STATE_IND 1.
--   Key = <TOA master code> (the program is not part of it).
--
-- VALIDATION: none in IDQ (no router, no filter, no exception table); only the C_S_LU_TOA constraints reject rows.
-- BAD DATA: IDQ gets a row without a TOA master label (NULL key) and every repeat of a key rejected by Oracle one row
--   at a time and carries on. A set-based INSERT would fail as a whole, so those rows are left out here: NULL keys,
--   keys already in C_S_LU_TOA (VERSION_SEQ = 1), and all but one row per key. IDQ keeps the first row read (no
--   ORDER BY, so undefined); this keeps the latest (UPDATE_DT, then UNIQUE_TRANS_ID, descending), as the Java and
--   Snowflake ports do. Precision as IDQ: the key passes a string(10) port, MBR_PRG_CD a string(9) port, TOA_LBL is
--   cut to 100, TOA_DESC to 250 and UPDATED_BY to 50 (target precision).
--   Unfed ports written as NULL: ROWID_OBJECT (computed as the key without leading zeros but not linked), DELETED_*.
-- TIMELINE: VERSION_SEQ = 1 (literal '1'). PERIOD_START_DATE, PERIOD_END_DATE and PERIOD_REFERENCE_TIME are not
--   linked (NULL); TIMELINE_ACTION keeps the column default 0.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Stg_TOA';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_LU_TOA. This code base never deletes, truncates or drops (rows are only inserted).

    -- Exp_TOA_Load -> Write_C_S_LU_TOA
    INSERT INTO C_S_LU_TOA
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            HUB_STATE_IND, TOA_CD, TOA_LBL, TOA_DESC, MBR_PRG_CD, EFF_STRT_DT, EFF_END_DT)
    WITH
    -- Read_STG_TRS_D_LU_TOA -> Exp_Src_TRS_Input -> Lkp_LOOKUP_CODE_VALUE_TOA / _MBR_PGM -> Exp_TOA_Load
    keyed AS (
        SELECT s.*,
               SUBSTR(lt.MSTR_REF_CODE, 1, 10) AS pkey_src_object,   -- string(10) port
               lt.MSTR_REF_LABEL               AS toa_lbl,
               SUBSTR(lp.MSTR_REF_CODE, 1, 9)  AS mbr_prg_cd         -- string(9) port
          FROM STG_TRS_D_LU_TOA s
         OUTER APPLY (SELECT l.MSTR_REF_CODE, l.MSTR_REF_LABEL FROM LOOKUP_CODE_VALUE l
                       WHERE l.CODE_TYPE = 'TOA' AND l.MSTR_REF_LABEL = s.TOA_CODE
                       ORDER BY l.MSTR_REF_CODE FETCH FIRST 1 ROW ONLY) lt
         OUTER APPLY (SELECT l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                       WHERE l.CODE_TYPE = 'MEMBER_PRG' AND l.MSTR_REF_LABEL = s.PROGRAM_CODE
                       ORDER BY l.MSTR_REF_CODE FETCH FIRST 1 ROW ONLY) lp
    ),
    ranked AS (
        SELECT k.*,
               ROW_NUMBER() OVER (PARTITION BY k.pkey_src_object
                                  ORDER BY k.UPDATE_DT DESC NULLS LAST, k.UNIQUE_TRANS_ID DESC NULLS LAST) AS key_rn
          FROM keyed k
         WHERE k.pkey_src_object IS NOT NULL                                     -- BAD DATA: Oracle rejects a NULL key
           AND NOT EXISTS (SELECT 1 FROM C_S_LU_TOA x                            -- BAD DATA: key already loaded
                            WHERE x.PKEY_SRC_OBJECT = k.pkey_src_object AND x.VERSION_SEQ = 1)
    )
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, NULL, NULL,
           1 /* TIMELINE: literal '1' */, NULL, l_run_ts, SUBSTR(UPDATE_USER_ID, 1, 50), CREATE_DT, 'admin',
           SUBSTR(pkey_src_object, 1, 30), 1, pkey_src_object, SUBSTR(toa_lbl, 1, 100), SUBSTR(TOA_DESC, 1, 250),
           mbr_prg_cd, EFF_BEGIN_DT, EFF_END_DT
      FROM ranked
     WHERE key_rn = 1;                                                           -- BAD DATA: repeated keys
    sp_ors_helper02_common(c_mapping, 'insert (C_S_LU_TOA)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA;
/

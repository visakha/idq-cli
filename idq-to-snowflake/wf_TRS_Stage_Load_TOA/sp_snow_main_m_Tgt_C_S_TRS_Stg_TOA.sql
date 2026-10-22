--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Stg_TOA (workflow wf_TRS_Stage_Load_TOA, its only
-- mapping; the daily parent workflow runs it after wf_TRS_Stage_Load_1_Ongoing).
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
-- Not a member load: the member TOA segments are m_Tgt_C_S_TRS_Pty_Rle_TOA (wf_TRS_Stage_Load_1_Ongoing), whose
-- TOA_FK holds the same master code (translated there by source value, here by label: docs/common_insights.md 1.21).
--
-- VALIDATION: none in IDQ: no router, no filter, no exception table. The only checks are the Oracle constraints of
--   C_S_LU_TOA (PKEY_SRC_OBJECT NOT NULL, unique (PKEY_SRC_OBJECT, VERSION_SEQ)), which reject rows one by one.
--   No begin-after-end date check (unlike m_Tgt_C_S_TRS_Pty_Rle_TOA).
-- BAD DATA: a TOA code without a TOA master label leaves PKEY_SRC_OBJECT NULL; IDQ gets the row rejected by Oracle
--   (Write_C_S_LU_TOA.bad) and logs nothing. The procedure skips these rows (Snowflake would fail the whole
--   statement on the NOT NULL column). Unique keys Snowflake does not enforce are applied: C_S_LU_TOA
--   (PKEY_SRC_OBJECT, VERSION_SEQ = 1), i.e. one row per TOA master code and none whose key is already in the
--   table. IDQ keeps the first row read and its read has no ORDER BY, so the survivor of a code listed under
--   several programs or history rows is undefined there; the procedure keeps the latest (UPDATE_DT, then
--   UNIQUE_TRANS_ID, descending), as the Java and Oracle ports do. Confirm with the business (common_insights 1.22).
--   Precision as IDQ: the key passes a string(10) port (cut to 10), MBR_PRG_CD a string(9) port, TOA_LBL is cut
--   to 100, TOA_DESC to 250 and UPDATED_BY to 50 (target precision).
--   Unfed ports written as NULL: ROWID_OBJECT (computed as the key without leading zeros but not linked), DELETED_*.
-- TIMELINE: VERSION_SEQ = 1 (literal '1'). PERIOD_START_DATE, PERIOD_END_DATE and PERIOD_REFERENCE_TIME are not
--   linked (NULL); TIMELINE_ACTION keeps the column default 0.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Stg_TOA';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_LU_TOA. This code base never deletes, truncates or drops (rows are only inserted).

    -- Exp_TOA_Load -> Write_C_S_LU_TOA
    INSERT INTO C_S_LU_TOA
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            HUB_STATE_IND, TOA_CD, TOA_LBL, TOA_DESC, MBR_PRG_CD, EFF_STRT_DT, EFF_END_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, NULL, NULL,
           1, NULL, :l_run_ts, SUBSTR(UPDATE_USER_ID, 1, 50), CREATE_DT, 'admin', SUBSTR(pkey_src_object, 1, 30),
           1, pkey_src_object, SUBSTR(toa_lbl, 1, 100), SUBSTR(TOA_DESC, 1, 250), mbr_prg_cd, EFF_BEGIN_DT, EFF_END_DT
      FROM (
        WITH
        -- Lkp_LOOKUP_CODE_VALUE_TOA / Lkp_LOOKUP_CODE_VALUE_MBR_PGM (SQL override by code type; any row per label)
        lkp_toa AS (
            SELECT l.MSTR_REF_LABEL, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
             WHERE l.CODE_TYPE = 'TOA'
            QUALIFY ROW_NUMBER() OVER (PARTITION BY l.MSTR_REF_LABEL ORDER BY l.MSTR_REF_CODE) = 1
        ),
        lkp_pgm AS (
            SELECT l.MSTR_REF_LABEL, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
             WHERE l.CODE_TYPE = 'MEMBER_PRG'
            QUALIFY ROW_NUMBER() OVER (PARTITION BY l.MSTR_REF_LABEL ORDER BY l.MSTR_REF_CODE) = 1
        ),
        -- Read_STG_TRS_D_LU_TOA -> Exp_Src_TRS_Input -> lookups -> Exp_TOA_Load
        keyed AS (
            SELECT s.*,
                   SUBSTR(lt.MSTR_REF_CODE, 1, 10) AS pkey_src_object,   -- string(10) port
                   lt.MSTR_REF_LABEL               AS toa_lbl,
                   SUBSTR(lp.MSTR_REF_CODE, 1, 9)  AS mbr_prg_cd         -- string(9) port
              FROM STG_TRS_D_LU_TOA s
              LEFT JOIN lkp_toa lt ON lt.MSTR_REF_LABEL = s.TOA_CODE
              LEFT JOIN lkp_pgm lp ON lp.MSTR_REF_LABEL = s.PROGRAM_CODE
        )
        SELECT k.*
          FROM keyed k
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_LU_TOA WHERE VERSION_SEQ = 1) xa
                 ON xa.PKEY_SRC_OBJECT = k.pkey_src_object
         /* BAD DATA: Oracle rejects a NULL key */
         WHERE k.pkey_src_object IS NOT NULL
           /* BAD DATA: unique keys Snowflake does not enforce */
           AND xa.PKEY_SRC_OBJECT IS NULL
        QUALIFY ROW_NUMBER() OVER (PARTITION BY k.pkey_src_object
                                       ORDER BY k.UPDATE_DT DESC NULLS LAST, k.UNIQUE_TRANS_ID DESC NULLS LAST) = 1
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_LU_TOA)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

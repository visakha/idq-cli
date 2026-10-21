--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_TOA (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Type of assistance of valid TIERS members (STG_TRS_D_CV_MCI_EDG_INDV_TOA, latest create per individual / EDG /
-- program / MCI sequence) into C_S_TRS_PTY_RLE_TOA (truncated first):
--   -> lkp_LOOKUP_CODE_VALUE (code type TOA, source 'TRS') -> rtr_Valid_Records
--        Bad_Value (TOA code does not translate)            -> EXC_STG_BAD_REC_MEMB ('Invalid_TOA')
--        Period_Begin_Date_GT_Period_End_Date (BEGIN > END) -> EXC_STG_BAD_REC_MEMB
--                                                              ('Period_Start_Date_>_Period_End_Date')
--        Default (neither)                                  -> C_S_TRS_PTY_RLE_TOA
--   A row with an untranslated code AND begin > end writes both exception rows.
--   Key = INDV_ID|Member|<TOA master code>|TIERS|<EDG_NUM>|<PROGRAM_CD>|<MCI_CREATE_SEQ>.
--
-- TIMELINE: VERSION_SEQ is the source ROW_NUMBER() kept only where it equals 1, i.e. always 1; PERIOD_START_DATE /
-- EFF_STRT_DT = BEGIN_DT, PERIOD_END_DATE / EFF_END_DT = END_DT; PERIOD_REFERENCE_TIME is linked to an unfed port.
-- IDQ quirks kept: the Bad_Value row writes the looked-up EXCEPTION_CODE (NULL when 'Invalid_TOA' is not
-- configured); the date row writes the computed code.
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND, and the name / address /
-- phone columns of the Bad_Value exception row.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Rle_TOA';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / systimestamp()
BEGIN
    sp_ors_helper01_common('C_S_TRS_PTY_RLE_TOA');

    INSERT ALL
        -- rtr_Valid_Records.Bad_Value -> exp_Stage_Exceptions -> Write_Exc_Stg_Bad_Rec_Memb
        WHEN toa_cd IS NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE, ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES ('TRS', l_run_ts, 'Type of Assistance', c_mapping, BEGIN_DT, END_DT,
                    fn_ors_helper08_common('Invalid_TOA'), fn_ors_helper04_common('Invalid_TOA'),
                    fn_ors_helper05_common('Invalid_TOA'), TYPE_OF_ASSISTANCE_CD, INDV_ID, EDG_NUM, MCI_CREATE_SEQ)
        -- rtr_Valid_Records.Period_Begin_Date_GT_Period_End_Date -> Write_EXC_STG_BAD_REC_MEMB_Start_Date_End_Date
        WHEN BEGIN_DT > END_DT THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  PERIOD_END_DATE, SRC_SYS, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
            VALUES (pkey_src_object, pty_rle_fk, c_mapping, l_run_ts, 'Effective Date', BEGIN_DT, END_DT, 'TRS',
                    fn_ors_helper04_common('Period_Start_Date_>_Period_End_Date'),
                    fn_ors_helper05_common('Period_Start_Date_>_Period_End_Date'),
                    'Period_Start_Date_>_Period_End_Date')
        -- rtr_Valid_Records.Default -> exp_Stage_Target_Attributes -> Write_C_S_TRS_PTY_RLE_TOA
        WHEN toa_cd IS NOT NULL AND NOT (BEGIN_DT > END_DT AND BEGIN_DT IS NOT NULL AND END_DT IS NOT NULL) THEN
            INTO C_S_TRS_PTY_RLE_TOA
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE,
                  CREATOR, SRC_ROWID, HUB_STATE_IND, TOA_SOURCE, TOA_FK, EFF_STRT_DT, EFF_END_DT, PTY_RLE_FK, EDG_NUM,
                  CASE_NUM, SGMNT_KEY, CNVRT_DT, CNVRT_SYS_CD, INDV_ID, PRTCPNT_STS_CD, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, BEGIN_DT /* TIMELINE */, END_DT /* TIMELINE */,
                    VERSION_SEQ /* TIMELINE: source ROW_NUMBER, always 1 */, NULL /* TIMELINE: unfed */, l_run_ts,
                    NULL, CREATE_DT, NULL, pkey_src_object, NULL, toa_source, toa_cd, BEGIN_DT, END_DT, pty_rle_fk,
                    EDG_NUM, CASE_NUM, sgmnt_key, CONVERT_DT, SYSTEM_CD, PTY_PK, PART_STATUS_CD, CREATE_DT)
    WITH
    -- read_Staging_Delta_Tables (custom SQL, query mode SEMI)
    toa_src AS (
        SELECT TO_CHAR(toa.INDV_ID) AS INDV_ID, TYPE_OF_ASSISTANCE_CD, ELIG_EFF_BEGIN_DT AS BEGIN_DT,
               ELIG_EFF_END_DT AS END_DT, 'MCI_EDG_INDV' AS SRC_TBL,
               ROW_NUMBER() OVER (PARTITION BY toa.INDV_ID || '|' || toa.EDG_NUM || '|' || toa.PROGRAM_CD || '|'
                                               || toa.MCI_CREATE_SEQ
                                  ORDER BY toa.CREATE_DT DESC) AS VERSION_SEQ,
               TO_CHAR(toa.INDV_ID) AS PTY_PK, EDG_NUM, CASE_NUM, MCI_CREATE_SEQ, PROGRAM_CD, PART_STATUS_CD,
               SYSTEM_CD, CONVERT_DT, toa.CREATE_DT
          FROM STG_TRS_D_CV_MCI_EDG_INDV_TOA toa
          JOIN STG_TRS_VALID_MEMBERS vm ON TO_CHAR(toa.INDV_ID) = vm.PTY_PK
         WHERE TYPE_OF_ASSISTANCE_CD IS NOT NULL
           AND (CONVERSION_IND IS NULL OR CONVERSION_IND = 'C')
    ),
    src AS (
        SELECT * FROM toa_src WHERE VERSION_SEQ = 1
    )
    -- lkp_LOOKUP_CODE_VALUE + exp_Stage_Source_Attributes + exp_Setup_PKey
    SELECT s.*,
           lk.MSTR_REF_CODE                                                      AS toa_cd,
           DECODE(s.SRC_TBL, 'LTSS_ELIG_PER', 'DADS', 'MCI_EDG_INDV', 'TIERS')  AS toa_source,
           s.EDG_NUM || '|' || s.PROGRAM_CD || '|' || s.MCI_CREATE_SEQ           AS sgmnt_key,
           s.INDV_ID || '|Member'                                                AS pty_rle_fk,
           s.INDV_ID || '|Member' || '|' || lk.MSTR_REF_CODE || '|'
           || DECODE(s.SRC_TBL, 'LTSS_ELIG_PER', 'DADS', 'MCI_EDG_INDV', 'TIERS') || '|'
           || s.EDG_NUM || '|' || s.PROGRAM_CD || '|' || s.MCI_CREATE_SEQ        AS pkey_src_object
      FROM src s
     OUTER APPLY (SELECT l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                   WHERE l.CODE_TYPE = 'TOA' AND l.SRC_SYS = 'TRS' AND l.SRC_CODE_VALUE = s.TYPE_OF_ASSISTANCE_CD
                   FETCH FIRST 1 ROW ONLY) lk;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TRS_PTY_RLE_TOA, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA;
/

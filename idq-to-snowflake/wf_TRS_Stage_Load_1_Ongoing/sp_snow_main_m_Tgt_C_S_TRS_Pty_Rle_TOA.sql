--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_TOA (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Type of assistance of valid TIERS members (STG_TRS_D_CV_MCI_EDG_INDV_TOA, latest create per individual / EDG /
-- program / MCI sequence) into C_S_TRS_PTY_RLE_TOA (insert only, never truncated):
--   -> lkp_LOOKUP_CODE_VALUE (code type TOA, source 'TRS') -> rtr_Valid_Records
--        Bad_Value (TOA code does not translate)            -> EXC_STG_BAD_REC_MEMB ('Invalid_TOA')
--        Period_Begin_Date_GT_Period_End_Date (BEGIN > END) -> EXC_STG_BAD_REC_MEMB
--                                                              ('Period_Start_Date_>_Period_End_Date')
--        Default (neither)                                  -> C_S_TRS_PTY_RLE_TOA
--   Key = INDV_ID|Member|<TOA master code>|TIERS|<EDG_NUM>|<PROGRAM_CD>|<MCI_CREATE_SEQ>.
--
-- VALIDATION: the TOA code must translate in LOOKUP_CODE_VALUE (TOA, TRS); the eligibility begin date may not be
--   after the end date.
-- BAD DATA: a row with an untranslated code AND begin > end writes BOTH exception rows (router semantics). The
--   Bad_Value row writes the looked-up EXCEPTION_CODE (NULL when 'Invalid_TOA' is not configured); the date row
--   writes the computed code. Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR,
--   HUB_STATE_IND, and the name / address / phone columns of the Bad_Value exception row. Unique keys Snowflake does
--   not enforce are applied: C_S_TRS_PTY_RLE_TOA (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ is the source ROW_NUMBER() kept only where it equals 1, i.e. always 1; PERIOD_START_DATE /
--   EFF_STRT_DT = BEGIN_DT, PERIOD_END_DATE / EFF_END_DT = END_DT; PERIOD_REFERENCE_TIME is linked to an unfed port.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_TOA';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / systimestamp()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_TOA. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- rtr_Valid_Records.Bad_Value -> exp_Stage_Exceptions -> Write_Exc_Stg_Bad_Rec_Memb
        WHEN grp_bad_value AND uq_exc_toa THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE, ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES (src_sys, run_ts, attr_toa, mapping_name, BEGIN_DT, END_DT, toa_exc_code, toa_exc_desc,
                    toa_exc_type, TYPE_OF_ASSISTANCE_CD, INDV_ID, EDG_NUM, MCI_CREATE_SEQ)
        -- rtr_Valid_Records.Period_Begin_Date_GT_Period_End_Date -> Write_EXC_STG_BAD_REC_MEMB_Start_Date_End_Date
        WHEN grp_dates AND uq_exc_dates THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  PERIOD_END_DATE, SRC_SYS, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
            VALUES (pkey_src_object, pty_rle_fk, mapping_name, run_ts, attr_dates, BEGIN_DT, END_DT, src_sys,
                    date_exc_desc, date_exc_type, date_exc_code)
        -- rtr_Valid_Records.Default -> exp_Stage_Target_Attributes -> Write_C_S_TRS_PTY_RLE_TOA
        WHEN NOT grp_bad_value AND NOT grp_dates AND uq_toa THEN
            INTO C_S_TRS_PTY_RLE_TOA
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE,
                  CREATOR, SRC_ROWID, HUB_STATE_IND, TOA_SOURCE, TOA_FK, EFF_STRT_DT, EFF_END_DT, PTY_RLE_FK, EDG_NUM,
                  CASE_NUM, SGMNT_KEY, CNVRT_DT, CNVRT_SYS_CD, INDV_ID, PRTCPNT_STS_CD, SRC_LAST_UPD_DT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, BEGIN_DT, END_DT, VERSION_SEQ, NULL, run_ts, NULL,
                    CREATE_DT, NULL, pkey_src_object, NULL, toa_source, toa_cd, BEGIN_DT, END_DT, pty_rle_fk, EDG_NUM,
                    CASE_NUM, sgmnt_key, CONVERT_DT, SYSTEM_CD, PTY_PK, PART_STATUS_CD, CREATE_DT)
    SELECT *
      FROM (
        WITH
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- read_Staging_Delta_Tables (custom SQL, query mode SEMI)
        toa_src AS (
            SELECT TO_VARCHAR(toa.INDV_ID) AS INDV_ID, toa.TYPE_OF_ASSISTANCE_CD, toa.ELIG_EFF_BEGIN_DT AS BEGIN_DT,
                   toa.ELIG_EFF_END_DT AS END_DT, 'MCI_EDG_INDV' AS SRC_TBL,
                   /* TIMELINE */
                   ROW_NUMBER() OVER (PARTITION BY TO_VARCHAR(toa.INDV_ID) || '|' || NVL(TO_VARCHAR(toa.EDG_NUM), '')
                                                   || '|' || NVL(TO_VARCHAR(toa.PROGRAM_CD), '') || '|'
                                                   || NVL(TO_VARCHAR(toa.MCI_CREATE_SEQ), '')
                                      ORDER BY toa.CREATE_DT DESC) AS VERSION_SEQ,
                   TO_VARCHAR(toa.INDV_ID) AS PTY_PK, toa.EDG_NUM, toa.CASE_NUM, toa.MCI_CREATE_SEQ, toa.PROGRAM_CD,
                   toa.PART_STATUS_CD, toa.SYSTEM_CD, toa.CONVERT_DT, toa.CREATE_DT
              FROM STG_TRS_D_CV_MCI_EDG_INDV_TOA toa
              JOIN STG_TRS_VALID_MEMBERS vm ON TO_VARCHAR(toa.INDV_ID) = vm.PTY_PK
             WHERE toa.TYPE_OF_ASSISTANCE_CD IS NOT NULL
               AND (toa.CONVERSION_IND IS NULL OR toa.CONVERSION_IND = 'C')
        ),
        src AS (
            SELECT * FROM toa_src WHERE VERSION_SEQ = 1
        ),
        -- lkp_LOOKUP_CODE_VALUE + exp_Stage_Source_Attributes + exp_Setup_PKey
        keyed AS (
            SELECT s.*,
                   lk.MSTR_REF_CODE                                                          AS toa_cd,
                   DECODE(s.SRC_TBL, 'LTSS_ELIG_PER', 'DADS', 'MCI_EDG_INDV', 'TIERS')      AS toa_source,
                   NVL(TO_VARCHAR(s.EDG_NUM), '') || '|' || NVL(TO_VARCHAR(s.PROGRAM_CD), '') || '|'
                   || NVL(TO_VARCHAR(s.MCI_CREATE_SEQ), '')                                  AS sgmnt_key,
                   s.INDV_ID || '|Member'                                                    AS pty_rle_fk,
                   s.INDV_ID || '|Member|' || NVL(lk.MSTR_REF_CODE, '') || '|'
                   || NVL(DECODE(s.SRC_TBL, 'LTSS_ELIG_PER', 'DADS', 'MCI_EDG_INDV', 'TIERS'), '') || '|'
                   || NVL(TO_VARCHAR(s.EDG_NUM), '') || '|' || NVL(TO_VARCHAR(s.PROGRAM_CD), '') || '|'
                   || NVL(TO_VARCHAR(s.MCI_CREATE_SEQ), '')                                  AS pkey_src_object,
                   /* VALIDATION */ lk.MSTR_REF_CODE IS NULL                                 AS grp_bad_value,
                   /* VALIDATION */ NVL(s.BEGIN_DT > s.END_DT, FALSE)                        AS grp_dates
              FROM src s
              LEFT JOIN (SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                          WHERE l.CODE_TYPE = 'TOA' AND l.SRC_SYS = 'TRS'
                        QUALIFY ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.MSTR_REF_CODE) = 1) lk
                     ON lk.SRC_CODE_VALUE = s.TYPE_OF_ASSISTANCE_CD
        )
        SELECT k.*,
               'TRS'                                         AS src_sys,
               :l_run_ts                                     AS run_ts,
               :c_mapping                                    AS mapping_name,
               'Type of Assistance'                          AS attr_toa,
               'Effective Date'                              AS attr_dates,
               xt.EXCEPTION_CODE                             AS toa_exc_code,
               xt.EXCEPTION_DESC                             AS toa_exc_desc,
               xt.EXCEPTION_TYPE                             AS toa_exc_type,
               'Period_Start_Date_>_Period_End_Date'         AS date_exc_code,
               xd.EXCEPTION_DESC                             AS date_exc_desc,
               xd.EXCEPTION_TYPE                             AS date_exc_type,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY k.grp_bad_value OR k.grp_dates, k.pkey_src_object
                                       ORDER BY k.CREATE_DT DESC) = 1
                AND xa.PKEY_SRC_OBJECT IS NULL)              AS uq_toa,
               ROW_NUMBER() OVER (PARTITION BY k.grp_bad_value, k.INDV_ID, k.EDG_NUM, k.MCI_CREATE_SEQ
                                      ORDER BY k.CREATE_DT DESC) = 1 AS uq_exc_toa,
               ROW_NUMBER() OVER (PARTITION BY k.grp_dates, k.pkey_src_object, k.pty_rle_fk
                                      ORDER BY k.CREATE_DT DESC) = 1 AS uq_exc_dates
          FROM keyed k
          LEFT JOIN lkp_exc xt ON xt.EXCEPTION_CODE = 'Invalid_TOA'
          LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date'
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_TOA WHERE VERSION_SEQ = 1) xa
                 ON xa.PKEY_SRC_OBJECT = k.pkey_src_object
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TRS_PTY_RLE_TOA, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

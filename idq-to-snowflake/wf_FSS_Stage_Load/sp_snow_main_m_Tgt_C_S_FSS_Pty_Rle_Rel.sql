--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Rel (workflow wf_FSS_Stage_Load).
--
-- Relationships between FSS clients (V_FSS_ETL_SRC_RELATIONS, one row per direction) into C_S_FSS_PTY_RLE_REL
-- (insert only, never truncated):
--   -> Filter_Fam_Child_Valid: neither PTY_SRC_KEY nor RELN_PTY_SRC_KEY is in STG_FSS_PTY_INACTIVE_STS
--   -> Exp_Map_Code_Val_and_Gender: relation code (CAREGIVER when missing) || '|' || gender of the related party
--      ('To Child': RELN_CD_GENDER with code type REL_TP; otherwise CD_GENDER with code type INVERSE_REL)
--   -> Lkp_Rel_Tp_Code_Value (LOOKUP_CODE_VALUE) -> Route_Good_vs_Exceptions
--        Valid_Relations     -> C_S_FSS_PTY_RLE_REL
--        Relation_Exceptions -> EXC_STG_BAD_REC_MEMB ('Invalid_Relationship', attribute 'Relationship|Sex', gender)
--
-- VALIDATION: the relation code must translate in LOOKUP_CODE_VALUE for the direction's code type.
-- BAD DATA: an untranslated relationship is not loaded, only logged, with the looked-up EXCEPTION_CODE (NULL when
--   'Invalid_Relationship' is not configured). Unique keys Snowflake does not enforce are applied:
--   C_S_FSS_PTY_RLE_REL (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = RELN_DT_CREATED.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Rel';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_FSS_PTY_RLE_REL. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Route_Good_vs_Exceptions.Valid_Relations -> Exp_Build_Reln -> Write_C_S_FSS_PTY_RLE_REL
        WHEN mstr_ref_code IS NOT NULL AND uq_rel THEN
            INTO C_S_FSS_PTY_RLE_REL
                 (REL_TP, VERSION_SEQ, HUB_STATE_IND, REL_TYPE_CODE, HIERARCHY_CODE, UPDATED_BY, LAST_UPDATE_DATE,
                  PERIOD_START_DATE, PKEY_SRC_OBJECT, PTY_RLE_FK_1, PTY_RLE_FK_2, SRC_LAST_UPD_DT, CREATOR, SRC_ROWID,
                  CREATE_DATE)
            VALUES (mstr_ref_code, version_seq, hub_state_ind, rel_type_code, hierarchy_code, batch_user, run_ts,
                    RELN_DT_CREATED, rel_pkey, rel_fk_1, rel_fk_2, RELN_DT_LAST_UPDATE, batch_user, rel_pkey,
                    RELN_DT_LAST_UPDATE)
        -- Route_Good_vs_Exceptions.Relation_Exceptions -> Exp_Build_Exception -> Write_EXC_STG_BAD_REC_MEMB
        WHEN mstr_ref_code IS NULL AND uq_rel_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE, SRC_SYS_ID_3, GENDER)
            VALUES (src_sys, RELN_ID_CLIENT, ID_CLIENT, run_ts, mapping_name, attr_relationship, RELN_DT_CREATED,
                    exc_type, exc_code, exc_desc, relation_cd, ID_REGISTRATION, out_gender_cd)
    SELECT *
      FROM (
        WITH
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_V_FSS_ETL_SRC_RELATIONS + Lkp_*_STG_FSS_PTY_INACTIVE_STS + Filter_Fam_Child_Valid
        src AS (
            SELECT r.RELATION_DIRECTION, r.RELN_DT_LAST_UPDATE, r.RELN_DT_CREATED, r.ID_CLIENT, r.CD_RELTSHP_TO_TC,
                   r.PTY_SRC_KEY, r.RELN_PTY_SRC_KEY, r.RELN_CD_GENDER, r.CD_GENDER, r.RELN_ID_CLIENT,
                   r.ID_REGISTRATION
              FROM V_FSS_ETL_SRC_RELATIONS r
             WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = r.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
               AND NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = r.RELN_PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        -- Exp_Map_Code_Val_and_Gender (IIF(x = 'UNK','UNK',x) is the identity and is kept implicit)
        coded AS (
            SELECT s.*,
                   NVL(s.CD_RELTSHP_TO_TC, 'CAREGIVER') || '|'
                   || NVL(IFF(s.RELATION_DIRECTION = 'To Child', s.RELN_CD_GENDER, s.CD_GENDER), '') AS relation_cd,
                   IFF(s.RELATION_DIRECTION = 'To Child', 'REL_TP', 'INVERSE_REL')                    AS code_type,
                   IFF(s.RELATION_DIRECTION = 'To Child', s.RELN_CD_GENDER, s.CD_GENDER)              AS out_gender_cd,
                   NVL(IFF(s.RELATION_DIRECTION = 'To Child', s.RELN_PTY_SRC_KEY, s.PTY_SRC_KEY), '') || '|Member'
                                                                                                      AS rel_fk_1,
                   NVL(IFF(s.RELATION_DIRECTION = 'To Child', s.PTY_SRC_KEY, s.RELN_PTY_SRC_KEY), '') || '|Member'
                                                                                                      AS rel_fk_2
              FROM src s
        ),
        -- Lkp_Rel_Tp_Code_Value (lookup filter CODE_TYPE IN ('REL_TP','INVERSE_REL') plus the code-type condition)
        typed AS (
            SELECT c.*, lk.MSTR_REF_CODE AS mstr_ref_code
              FROM coded c
              LEFT JOIN (SELECT l.CODE_TYPE, l.SRC_CODE_VALUE, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                          WHERE l.CODE_TYPE IN ('REL_TP', 'INVERSE_REL') AND l.SRC_SYS = 'FSS'
                        QUALIFY ROW_NUMBER() OVER (PARTITION BY l.CODE_TYPE, l.SRC_CODE_VALUE
                                                       ORDER BY l.MSTR_REF_CODE) = 1) lk
                     ON lk.SRC_CODE_VALUE = c.relation_cd AND lk.CODE_TYPE = c.code_type
        )
        SELECT t.*,
               t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')  AS rel_pkey,
               1 /* TIMELINE: VERSION_SEQ */                                       AS version_seq,
               1                                                                    AS hub_state_ind,
               'Member Relationship'                                                AS rel_type_code,
               'Member'                                                             AS hierarchy_code,
               'batchload'                                                          AS batch_user,
               'FSS'                                                                AS src_sys,
               :l_run_ts                                                            AS run_ts,
               :c_mapping                                                           AS mapping_name,
               'Relationship|Sex'                                                   AS attr_relationship,
               ex.EXCEPTION_CODE                                                    AS exc_code,
               ex.EXCEPTION_DESC                                                    AS exc_desc,
               ex.EXCEPTION_TYPE                                                    AS exc_type,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY t.mstr_ref_code IS NULL,
                                                t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')
                                       ORDER BY t.RELN_DT_LAST_UPDATE DESC, t.ID_REGISTRATION) = 1
                AND xr.PKEY_SRC_OBJECT IS NULL)                                     AS uq_rel,
               ROW_NUMBER() OVER (PARTITION BY t.mstr_ref_code IS NULL, t.RELN_ID_CLIENT, t.ID_CLIENT,
                                               t.ID_REGISTRATION ORDER BY t.RELN_DT_LAST_UPDATE DESC) = 1 AS uq_rel_exc
          FROM typed t
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Relationship'
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_REL WHERE VERSION_SEQ = 1) xr
                 ON xr.PKEY_SRC_OBJECT = t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_FSS_PTY_RLE_REL, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Rel (workflow wf_FSS_Stage_Load).
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
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = RELN_DT_CREATED.
-- The exception row writes the looked-up EXCEPTION_CODE (NULL when 'Invalid_Relationship' is not configured).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_FSS_Pty_Rle_Rel';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_FSS_PTY_RLE_REL. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Route_Good_vs_Exceptions.Valid_Relations -> Exp_Build_Reln -> Write_C_S_FSS_PTY_RLE_REL
        WHEN mstr_ref_code IS NOT NULL THEN
            INTO C_S_FSS_PTY_RLE_REL
                 (REL_TP, VERSION_SEQ, HUB_STATE_IND, REL_TYPE_CODE, HIERARCHY_CODE, UPDATED_BY, LAST_UPDATE_DATE,
                  PERIOD_START_DATE, PKEY_SRC_OBJECT, PTY_RLE_FK_1, PTY_RLE_FK_2, SRC_LAST_UPD_DT, CREATOR, SRC_ROWID,
                  CREATE_DATE)
            VALUES (mstr_ref_code, 1 /* TIMELINE: VERSION_SEQ */, 1, 'Member Relationship', 'Member', 'batchload',
                    l_run_ts, RELN_DT_CREATED /* TIMELINE */, rel_fk_1 || '|' || rel_fk_2 || '|' || mstr_ref_code,
                    rel_fk_1, rel_fk_2, RELN_DT_LAST_UPDATE, 'batchload',
                    rel_fk_1 || '|' || rel_fk_2 || '|' || mstr_ref_code, RELN_DT_LAST_UPDATE)
        -- Route_Good_vs_Exceptions.Relation_Exceptions -> Exp_Build_Exception -> Write_EXC_STG_BAD_REC_MEMB
        WHEN mstr_ref_code IS NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE, SRC_SYS_ID_3, GENDER)
            VALUES ('FSS', RELN_ID_CLIENT, ID_CLIENT, l_run_ts, c_mapping, 'Relationship|Sex', RELN_DT_CREATED,
                    fn_ors_helper05_common('Invalid_Relationship'), fn_ors_helper08_common('Invalid_Relationship'),
                    fn_ors_helper04_common('Invalid_Relationship'), relation_cd, ID_REGISTRATION, out_gender_cd)
    WITH
    -- Read_V_FSS_ETL_SRC_RELATIONS + Lkp_*_STG_FSS_PTY_INACTIVE_STS + Filter_Fam_Child_Valid
    src AS (
        SELECT r.RELATION_DIRECTION, r.RELN_DT_LAST_UPDATE, r.RELN_DT_CREATED, r.ID_CLIENT, r.CD_RELTSHP_TO_TC,
               r.PTY_SRC_KEY, r.RELN_PTY_SRC_KEY, r.RELN_CD_GENDER, r.CD_GENDER, r.RELN_ID_CLIENT, r.ID_REGISTRATION
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
               || CASE WHEN s.RELATION_DIRECTION = 'To Child' THEN s.RELN_CD_GENDER ELSE s.CD_GENDER END AS relation_cd,
               CASE WHEN s.RELATION_DIRECTION = 'To Child' THEN 'REL_TP' ELSE 'INVERSE_REL' END          AS code_type,
               CASE WHEN s.RELATION_DIRECTION = 'To Child' THEN s.RELN_CD_GENDER ELSE s.CD_GENDER END    AS out_gender_cd,
               CASE WHEN s.RELATION_DIRECTION = 'To Child' THEN s.RELN_PTY_SRC_KEY ELSE s.PTY_SRC_KEY END
                   || '|Member'                                                                        AS rel_fk_1,
               CASE WHEN s.RELATION_DIRECTION = 'To Child' THEN s.PTY_SRC_KEY ELSE s.RELN_PTY_SRC_KEY END
                   || '|Member'                                                                        AS rel_fk_2
          FROM src s
    )
    -- Lkp_Rel_Tp_Code_Value (lookup filter CODE_TYPE IN ('REL_TP','INVERSE_REL') plus the code-type condition)
    SELECT c.*, lk.MSTR_REF_CODE AS mstr_ref_code
      FROM coded c
     OUTER APPLY (SELECT l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                   WHERE l.CODE_TYPE IN ('REL_TP', 'INVERSE_REL')
                     AND l.SRC_SYS = 'FSS' AND l.SRC_CODE_VALUE = c.relation_cd AND l.CODE_TYPE = c.code_type
                   FETCH FIRST 1 ROW ONLY) lk;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_FSS_PTY_RLE_REL, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel;
/

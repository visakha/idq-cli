--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Rel
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Rel (workflow wf_ECI_Stage_Load).
--
-- Family <-> child relationships into C_S_ECI_PTY_RLE_REL (truncated first). Every STG_ECI_D_FAMILY row is read
-- twice (custom SQL, 'To Child' and 'From Child'):
--   * To Child  : family -> child, relationship code = FAMILY_CD
--   * From Child: child -> family, relationship code = FAMILY_CD || '|' || child gender (STG_ECI_SN_CHILD.GENDER)
--   -> Filter_Fam_Child_Valid: neither the child (LPAD(ID_CHILD,10,'0')) nor the family (LPAD(ID_FAMILY,10,'0')||'F')
--      is in STG_ECI_PTY_INACTIVE_STS
--   -> Lkp_Rel_Tp_Code_Value (LOOKUP_CODE_VALUE, code types REL_TP / INVERSE_REL) -> Route_Good_vs_Exceptions
--        Valid_Relations     (code translates)       -> C_S_ECI_PTY_RLE_REL
--        Relation_Exceptions (code does not translate) -> EXC_STG_BAD_REC_MEMB ('Invalid_Relationship')
--
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = family DATE_CREATED; CREATE_DATE = DATE_MODIFIED (as IDQ links it).
-- The exception row writes the EXCEPTION_CODE returned by the EXC_LOOKUP_CODE_VALUE lookup (NULL when
-- 'Invalid_Relationship' is not configured).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Rel
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_ECI_Pty_Rle_Rel';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP()
BEGIN
    sp_ors_helper01_common('C_S_ECI_PTY_RLE_REL');

    INSERT ALL
        -- Route_Good_vs_Exceptions.Valid_Relations -> Exp_Build_Reln -> Write_C_S_ECI_PTY_RLE_REL
        WHEN mstr_ref_code IS NOT NULL THEN
            INTO C_S_ECI_PTY_RLE_REL
                 (PTY_RLE_FK_1, PTY_RLE_FK_2, PKEY_SRC_OBJECT, VERSION_SEQ, SRC_ROWID, HUB_STATE_IND, REL_TYPE_CODE,
                  HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
                  PERIOD_START_DATE)
            VALUES (rel_fk_1, rel_fk_2, rel_src_key, 1 /* TIMELINE: VERSION_SEQ */, rel_src_key, 1,
                    'Member Relationship', 'Member', mstr_ref_code, DATE_MODIFIED, l_run_ts, c_mapping,
                    DATE_MODIFIED, c_mapping, DATE_CREATED /* TIMELINE */)
        -- Route_Good_vs_Exceptions.Relation_Exceptions -> Exp_Build_Exception -> Write_EXC_STG_BAD_REC_MEMB
        WHEN mstr_ref_code IS NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME,
                  PERIOD_START_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE)
            VALUES ('ECI', ID_FAMILY, ID_CHILD, rel_src_key, l_run_ts, c_mapping, 'FAMILY_CD', DATE_CREATED,
                    fn_ors_helper05_common('Invalid_Relationship'), fn_ors_helper08_common('Invalid_Relationship'),
                    fn_ors_helper04_common('Invalid_Relationship'), rel_family_cd)
    WITH
    -- Read_STG_ECI_D_FAMILY (custom SQL: two rows per family row)
    src AS (
        SELECT d.RELATION_DIRECTION, f.ID_FAMILY, f.GENDER AS FAMILY_GENDER, f.ID_CHILD, f.FAMILY_CD,
               COALESCE(f.DATE_MODIFIED, f.DATE_CREATED) AS DATE_MODIFIED, f.DATE_CREATED
          FROM STG_ECI_D_FAMILY f
         INNER JOIN (SELECT 'From Child' AS RELATION_DIRECTION FROM dual
                     UNION ALL
                     SELECT 'To Child' FROM dual) d ON 1 = 1
    ),
    -- Exp_Build_Keys + Filter_Fam_Child_Valid
    keyed AS (
        SELECT s.*,
               LPAD(s.ID_CHILD, 10, '0')          AS child_pty_src_key,
               LPAD(s.ID_FAMILY, 10, '0') || 'F'  AS family_pty_src_key
          FROM src s
         WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = LPAD(s.ID_CHILD, 10, '0') AND i.ROWID_SYSTEM = 'ECI'
                              AND i.DEACTIVATION_STS IS NOT NULL)
           AND NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = LPAD(s.ID_FAMILY, 10, '0') || 'F' AND i.ROWID_SYSTEM = 'ECI'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    -- Lkp_STG_ECI_SN_CHILD + Exp_Prep_Family_cd
    coded AS (
        SELECT k.*,
               CASE WHEN k.RELATION_DIRECTION = 'To Child' THEN TO_CHAR(k.FAMILY_CD)
                    ELSE TO_CHAR(k.FAMILY_CD) || '|' || ch.GENDER END                 AS rel_family_cd
          FROM keyed k
         OUTER APPLY (SELECT c.GENDER FROM STG_ECI_SN_CHILD c
                       WHERE c.ID_CHILD = k.ID_CHILD FETCH FIRST 1 ROW ONLY) ch
    ),
    -- Lkp_Rel_Tp_Code_Value
    typed AS (
        SELECT c.*, lk.MSTR_REF_CODE AS mstr_ref_code
          FROM coded c
         OUTER APPLY (SELECT l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                       WHERE l.CODE_TYPE IN ('REL_TP', 'INVERSE_REL')
                         AND l.SRC_SYS = 'ECI' AND l.SRC_CODE_VALUE = c.rel_family_cd
                       FETCH FIRST 1 ROW ONLY) lk
    )
    -- Exp_Build_Reln / Exp_Build_Exception
    SELECT t.*,
           CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.family_pty_src_key ELSE t.child_pty_src_key END
               || '|Member'                                                          AS rel_fk_1,
           CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.child_pty_src_key ELSE t.family_pty_src_key END
               || '|Member'                                                          AS rel_fk_2,
           CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.family_pty_src_key ELSE t.child_pty_src_key END
               || '|Member' || '|'
               || CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.child_pty_src_key ELSE t.family_pty_src_key END
               || '|Member' || '|' || t.mstr_ref_code                                AS rel_src_key
      FROM typed t;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_ECI_PTY_RLE_REL, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Rel;
/

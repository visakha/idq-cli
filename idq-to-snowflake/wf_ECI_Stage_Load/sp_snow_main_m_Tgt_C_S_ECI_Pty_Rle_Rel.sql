--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Rel (workflow wf_ECI_Stage_Load).
--
-- Family <-> child relationships into C_S_ECI_PTY_RLE_REL (insert only, never truncated). Every STG_ECI_D_FAMILY row
-- is read twice (custom SQL, 'To Child' and 'From Child'):
--   * To Child  : family -> child, relationship code = FAMILY_CD
--   * From Child: child -> family, relationship code = FAMILY_CD || '|' || child gender (STG_ECI_SN_CHILD.GENDER)
--   -> Filter_Fam_Child_Valid: neither the child (LPAD(ID_CHILD,10,'0')) nor the family (LPAD(ID_FAMILY,10,'0')||'F')
--      is in STG_ECI_PTY_INACTIVE_STS
--   -> Lkp_Rel_Tp_Code_Value (LOOKUP_CODE_VALUE, code types REL_TP / INVERSE_REL) -> Route_Good_vs_Exceptions
--        Valid_Relations     (code translates)         -> C_S_ECI_PTY_RLE_REL
--        Relation_Exceptions (code does not translate) -> EXC_STG_BAD_REC_MEMB ('Invalid_Relationship')
--
-- VALIDATION: the relationship code must translate in LOOKUP_CODE_VALUE (REL_TP / INVERSE_REL, source ECI).
-- BAD DATA: an untranslated relationship is not loaded, only logged. The exception row writes the EXCEPTION_CODE
--   returned by the EXC_LOOKUP_CODE_VALUE lookup (NULL when 'Invalid_Relationship' is not configured). Its key
--   SRC_SYS_ID_3 ends in '|' (the master code is NULL; IDQ concatenates NULL as ''). Unique keys Snowflake does not
--   enforce are applied: C_S_ECI_PTY_RLE_REL (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = family DATE_CREATED. CREATE_DATE = DATE_MODIFIED (as IDQ links it,
--   docs/common_insights.md 1.12).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Rel';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_ECI_PTY_RLE_REL. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Route_Good_vs_Exceptions.Valid_Relations -> Exp_Build_Reln -> Write_C_S_ECI_PTY_RLE_REL
        WHEN mstr_ref_code IS NOT NULL AND uq_rel THEN
            INTO C_S_ECI_PTY_RLE_REL
                 (PTY_RLE_FK_1, PTY_RLE_FK_2, PKEY_SRC_OBJECT, VERSION_SEQ, SRC_ROWID, HUB_STATE_IND, REL_TYPE_CODE,
                  HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
                  PERIOD_START_DATE)
            VALUES (rel_fk_1, rel_fk_2, rel_src_key, version_seq, rel_src_key, hub_state_ind, rel_type_code,
                    hierarchy_code, mstr_ref_code, DATE_MODIFIED, run_ts, mapping_name, DATE_MODIFIED, mapping_name,
                    DATE_CREATED)
        -- Route_Good_vs_Exceptions.Relation_Exceptions -> Exp_Build_Exception -> Write_EXC_STG_BAD_REC_MEMB
        WHEN mstr_ref_code IS NULL AND uq_rel_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME,
                  PERIOD_START_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE)
            VALUES (src_sys, ID_FAMILY, ID_CHILD, rel_src_key, run_ts, mapping_name, attr_family_cd, DATE_CREATED,
                    exc_type, exc_code, exc_desc, rel_family_cd)
    SELECT *
      FROM (
        WITH
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_STG_ECI_D_FAMILY (custom SQL: two rows per family row)
        src AS (
            SELECT d.RELATION_DIRECTION, f.ID_FAMILY, f.GENDER AS FAMILY_GENDER, f.ID_CHILD, f.FAMILY_CD,
                   COALESCE(f.DATE_MODIFIED, f.DATE_CREATED) AS DATE_MODIFIED, f.DATE_CREATED
              FROM STG_ECI_D_FAMILY f
             CROSS JOIN (SELECT column1 AS RELATION_DIRECTION FROM VALUES ('From Child'), ('To Child')) d
        ),
        -- Exp_Build_Keys + Filter_Fam_Child_Valid
        keyed AS (
            SELECT s.*,
                   LPAD(TO_VARCHAR(s.ID_CHILD), 10, '0')          AS child_pty_src_key,
                   LPAD(TO_VARCHAR(s.ID_FAMILY), 10, '0') || 'F'  AS family_pty_src_key
              FROM src s
             WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = LPAD(TO_VARCHAR(s.ID_CHILD), 10, '0') AND i.ROWID_SYSTEM = 'ECI'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
               AND NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = LPAD(TO_VARCHAR(s.ID_FAMILY), 10, '0') || 'F'
                                  AND i.ROWID_SYSTEM = 'ECI' AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        -- Lkp_STG_ECI_SN_CHILD + Exp_Prep_Family_cd
        coded AS (
            SELECT k.*,
                   IFF(k.RELATION_DIRECTION = 'To Child', TO_VARCHAR(k.FAMILY_CD),
                       NVL(TO_VARCHAR(k.FAMILY_CD), '') || '|' || NVL(ch.GENDER, ''))     AS rel_family_cd
              FROM keyed k
              LEFT JOIN (SELECT c.ID_CHILD, c.GENDER FROM STG_ECI_SN_CHILD c
                         QUALIFY ROW_NUMBER() OVER (PARTITION BY c.ID_CHILD ORDER BY c.GENDER) = 1) ch
                     ON ch.ID_CHILD = k.ID_CHILD
        ),
        -- Lkp_Rel_Tp_Code_Value (LOOKUP_CODE_VALUE by source code, any row)
        typed AS (
            SELECT c.*, lk.MSTR_REF_CODE AS mstr_ref_code
              FROM coded c
              LEFT JOIN (SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                          WHERE l.CODE_TYPE IN ('REL_TP', 'INVERSE_REL') AND l.SRC_SYS = 'ECI'
                        QUALIFY ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.CODE_TYPE DESC,
                                                   l.MSTR_REF_CODE) = 1) lk
                     ON lk.SRC_CODE_VALUE = c.rel_family_cd
        ),
        -- Exp_Build_Reln / Exp_Build_Exception
        built AS (
            SELECT t.*,
                   IFF(t.RELATION_DIRECTION = 'To Child', t.family_pty_src_key, t.child_pty_src_key) || '|Member'
                                                                                              AS rel_fk_1,
                   IFF(t.RELATION_DIRECTION = 'To Child', t.child_pty_src_key, t.family_pty_src_key) || '|Member'
                                                                                              AS rel_fk_2,
                   IFF(t.RELATION_DIRECTION = 'To Child', t.family_pty_src_key, t.child_pty_src_key) || '|Member|'
                   || IFF(t.RELATION_DIRECTION = 'To Child', t.child_pty_src_key, t.family_pty_src_key) || '|Member|'
                   || NVL(t.mstr_ref_code, '')                                               AS rel_src_key
              FROM typed t
        )
        SELECT b.*,
               1 /* TIMELINE: VERSION_SEQ */                  AS version_seq,
               1                                              AS hub_state_ind,
               'Member Relationship'                          AS rel_type_code,
               'Member'                                       AS hierarchy_code,
               'ECI'                                          AS src_sys,
               :l_run_ts                                      AS run_ts,
               :c_mapping                                     AS mapping_name,
               'FAMILY_CD'                                    AS attr_family_cd,
               ex.EXCEPTION_CODE                              AS exc_code,
               ex.EXCEPTION_DESC                              AS exc_desc,
               ex.EXCEPTION_TYPE                              AS exc_type,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY b.mstr_ref_code IS NULL, b.rel_src_key
                                       ORDER BY b.DATE_MODIFIED DESC, b.ID_FAMILY) = 1
                AND xr.PKEY_SRC_OBJECT IS NULL)               AS uq_rel,
               ROW_NUMBER() OVER (PARTITION BY b.mstr_ref_code IS NULL, b.ID_FAMILY, b.ID_CHILD, b.rel_src_key
                                      ORDER BY b.DATE_MODIFIED DESC) = 1 AS uq_rel_exc
          FROM built b
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Relationship'
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_REL WHERE VERSION_SEQ = 1) xr
                 ON xr.PKEY_SRC_OBJECT = b.rel_src_key
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_ECI_PTY_RLE_REL, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

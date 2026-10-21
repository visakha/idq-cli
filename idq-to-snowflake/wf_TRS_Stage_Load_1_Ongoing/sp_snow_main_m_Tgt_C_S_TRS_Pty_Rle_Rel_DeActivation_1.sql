--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 (workflow
-- wf_TRS_Stage_Load_1_Ongoing).
--
-- Logs TIERS relationships that were deactivated (STG_TRS_D_DC_RELATIONSHIPS_A, both sides valid members) so a
-- later process can soft-delete them in the MDM:
--   -> Lookup_V_LOOKUP_CODE_VALUE (code type PTY_REL) + Exp_Gen_PKEY: key = member|ref member|master type
--   -> Lookup_STG_TRS_DEACTIVATED_RELATIONSHIPS (unprocessed rows only) and Lkp_C_B_PTY_RLE_REL_XREF (custom lookup
--      SQL: per MDM cross-reference the record count, merge / master / soft-delete flags, lowest ROWID_XREF of the key)
--   -> Fil_New_Deactivations: not yet logged as unprocessed AND present in the MDM (a cross-reference exists)
--   -> STG_TRS_DEACTIVATED_RELATIONSHIPS (insert; PROCESSED_YN is not linked - left to the column default)
--
-- VALIDATION: none (no rule runs here); the relationship must exist in the MDM (C_B_PTY_RLE_REL_XREF).
-- BAD DATA: the mapping description also mentions removing relationships from a valid list; the IDQ mapping has no
--   such target (docs/common_insights.md 1.10). An untranslated relationship type gives a key ending in '|', which
--   finds no cross-reference and is dropped by the filter.
-- TIMELINE: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- sysdate of LOAD_DATE
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO STG_TRS_DEACTIVATED_RELATIONSHIPS
           (INDV_ID, REF_INDV_ID, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, SRC_PKEY_CT, LOAD_DATE, PKEY_SRC_OBJECT,
            ROWID_OBJECT, MASTER_RECORD_YN, MERGED_YN, ROWID_SYSTEM, ROWID_XREF)
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    -- Read_STG_TRS_D_DC_RELATIONSHIPS_A (custom SQL, query mode SEMI)
    min_pk AS (
        SELECT indv_id, MIN(pty_pk) pty_pk FROM STG_TRS_VALID_MEMBERS GROUP BY indv_id
    ),
    src AS (
        SELECT rel.indv_id AS INDV_ID, rel.ref_indv_id AS REF_INDV_ID, rel.eff_begin_dt AS EFF_BEGIN_DT,
               rel.eff_end_dt AS EFF_END_DT, rel.relationship_type_cd AS RELATIONSHIP_TYPE_CD, pk1.pty_pk AS PTY_PKEY,
               pk2.pty_pk AS REF_PTY_PKEY, 'TRS' AS SRC_SYS
          FROM STG_TRS_D_DC_RELATIONSHIPS_A rel
          JOIN min_pk pk1 ON rel.indv_id = pk1.indv_id
          JOIN min_pk pk2 ON rel.ref_indv_id = pk2.indv_id
    ),
    -- Lookup_V_LOOKUP_CODE_VALUE + Exp_Gen_PKEY
    keyed AS (
        SELECT s.*,
               IFF(s.PTY_PKEY IS NULL, NULL, TRIM(s.PTY_PKEY) || '|Member')               AS pty_rle_fk_1,
               IFF(s.REF_PTY_PKEY IS NULL, NULL, TRIM(s.REF_PTY_PKEY) || '|Member')       AS pty_rle_fk_2,
               NVL(IFF(s.PTY_PKEY IS NULL, NULL, TRIM(s.PTY_PKEY) || '|Member'), '') || '|'
               || NVL(IFF(s.REF_PTY_PKEY IS NULL, NULL, TRIM(s.REF_PTY_PKEY) || '|Member'), '') || '|'
               || NVL(pt.MSTR_CODE_VALUE, '')                                             AS pkey_src_object
          FROM src s
          LEFT JOIN lkp_cv pt ON pt.CODE_TYPE = 'PTY_REL' AND pt.SRC_SYS = s.SRC_SYS
                             AND pt.SRC_CODE_VALUE = s.RELATIONSHIP_TYPE_CD
    ),
    -- Lkp_C_B_PTY_RLE_REL_XREF (custom lookup SQL; the per-object window counts written as grouped joins)
    xref_obj AS (
        SELECT ROWID_OBJECT, COUNT(DISTINCT PKEY_SRC_OBJECT) AS SRC_PKEY_CT, MAX(HUB_STATE_IND) AS MAX_HUB_STATE_IND
          FROM C_B_PTY_RLE_REL_XREF
         GROUP BY ROWID_OBJECT
    ),
    xref_key AS (
        SELECT PKEY_SRC_OBJECT, MIN(ROWID_XREF) AS MIN_ROWID_XREF
          FROM C_B_PTY_RLE_REL_XREF
         GROUP BY PKEY_SRC_OBJECT
    ),
    xref AS (
        SELECT DISTINCT t.ROWID_OBJECT, t.PKEY_SRC_OBJECT, t.ROWID_SYSTEM, o.SRC_PKEY_CT,
               IFF(o.SRC_PKEY_CT > 1, 'Y', 'N')                          AS MERGE_YN,
               IFF(t.ROWID_OBJECT = t.ORIG_ROWID_OBJECT, 'Y', 'N')        AS MASTER_RECORD_YN,
               IFF(o.MAX_HUB_STATE_IND = -1, 'Y', 'N')                    AS SOFT_DELETE_YN,
               k.MIN_ROWID_XREF
          FROM C_B_PTY_RLE_REL_XREF t
          JOIN xref_obj o ON o.ROWID_OBJECT = t.ROWID_OBJECT
          JOIN xref_key k ON k.PKEY_SRC_OBJECT = t.PKEY_SRC_OBJECT
    ),
    xref_one AS (   -- lookup "return any row" per PKEY_SRC_OBJECT
        SELECT * FROM xref
        QUALIFY ROW_NUMBER() OVER (PARTITION BY PKEY_SRC_OBJECT ORDER BY ROWID_OBJECT) = 1
    )
    SELECT k.INDV_ID, k.REF_INDV_ID, k.pty_rle_fk_1, k.pty_rle_fk_2, k.RELATIONSHIP_TYPE_CD, x.SRC_PKEY_CT, :l_run_ts,
           k.pkey_src_object, x.ROWID_OBJECT, x.MASTER_RECORD_YN, TRIM(x.MERGE_YN), k.SRC_SYS, x.MIN_ROWID_XREF
      FROM keyed k
      LEFT JOIN xref_one x ON x.PKEY_SRC_OBJECT = k.pkey_src_object
      -- Lookup_STG_TRS_DEACTIVATED_RELATIONSHIPS (PROCESSED_YN = 'N') + Fil_New_Deactivations
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM STG_TRS_DEACTIVATED_RELATIONSHIPS
                  WHERE PROCESSED_YN = 'N' AND PKEY_SRC_OBJECT IS NOT NULL) d
             ON d.PKEY_SRC_OBJECT = k.pkey_src_object
     WHERE d.PKEY_SRC_OBJECT IS NULL
       AND x.MIN_ROWID_XREF IS NOT NULL;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert STG_TRS_DEACTIVATED_RELATIONSHIPS', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

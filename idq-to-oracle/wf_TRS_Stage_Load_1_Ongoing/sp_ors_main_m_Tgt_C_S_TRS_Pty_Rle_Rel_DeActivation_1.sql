--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Logs TIERS relationships that were deactivated (STG_TRS_D_DC_RELATIONSHIPS_A, both sides valid members) so a
-- later process can soft-delete them in the MDM:
--   -> Lookup_V_LOOKUP_CODE_VALUE (code type PTY_REL) + Exp_Gen_PKEY: key = member|ref member|master type
--   -> Lookup_STG_TRS_DEACTIVATED_RELATIONSHIPS (unprocessed rows only) and Lkp_C_B_PTY_RLE_REL_XREF (custom lookup
--      SQL: per MDM cross-reference the record count, merge / master / soft-delete flags, lowest ROWID_XREF of the key)
--   -> Fil_New_Deactivations: not yet logged as unprocessed AND present in the MDM (a cross-reference exists)
--   -> STG_TRS_DEACTIVATED_RELATIONSHIPS (insert; PROCESSED_YN is not linked - left to the column default)
-- The mapping description also mentions removing relationships from a valid list; the IDQ mapping has no such target.
--
-- Timeline: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1';
    l_sysdate  DATE := SYSDATE;   -- sysdate of LOAD_DATE
BEGIN
    INSERT INTO STG_TRS_DEACTIVATED_RELATIONSHIPS
           (INDV_ID, REF_INDV_ID, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, SRC_PKEY_CT, LOAD_DATE, PKEY_SRC_OBJECT,
            ROWID_OBJECT, MASTER_RECORD_YN, MERGED_YN, ROWID_SYSTEM, ROWID_XREF)
    WITH
    -- Read_STG_TRS_D_DC_RELATIONSHIPS_A (custom SQL, query mode SEMI)
    min_pk AS (
        SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
    ),
    src AS (
        SELECT rel.indv_id AS INDV_ID, ref_indv_id AS REF_INDV_ID, eff_begin_dt AS EFF_BEGIN_DT,
               eff_end_dt AS EFF_END_DT, relationship_type_cd AS RELATIONSHIP_TYPE_CD, pk1.pty_pk AS PTY_PKEY,
               pk2.pty_pk AS REF_PTY_PKEY, 'TRS' AS SRC_SYS
          FROM stg_trs_d_dc_relationships_a rel
          JOIN min_pk pk1 ON rel.indv_id = pk1.indv_id
          JOIN min_pk pk2 ON rel.ref_indv_id = pk2.indv_id
    ),
    -- Lookup_V_LOOKUP_CODE_VALUE + Exp_Gen_PKEY
    keyed AS (
        SELECT s.*,
               CASE WHEN s.PTY_PKEY IS NULL THEN NULL ELSE LTRIM(RTRIM(s.PTY_PKEY)) || '|Member' END         AS pty_rle_fk_1,
               CASE WHEN s.REF_PTY_PKEY IS NULL THEN NULL ELSE LTRIM(RTRIM(s.REF_PTY_PKEY)) || '|Member' END AS pty_rle_fk_2,
               (CASE WHEN s.PTY_PKEY IS NULL THEN NULL ELSE LTRIM(RTRIM(s.PTY_PKEY)) || '|Member' END) || '|'
               || (CASE WHEN s.REF_PTY_PKEY IS NULL THEN NULL ELSE LTRIM(RTRIM(s.REF_PTY_PKEY)) || '|Member' END)
               || '|' || fn_ors_helper03_common('PTY_REL', s.SRC_SYS, s.RELATIONSHIP_TYPE_CD)              AS pkey_src_object
          FROM src s
    ),
    -- Lkp_C_B_PTY_RLE_REL_XREF (custom lookup SQL)
    xref AS (
        SELECT DISTINCT T.ROWID_OBJECT, T.PKEY_SRC_OBJECT, T.ROWID_SYSTEM,
               COUNT(DISTINCT PKEY_SRC_OBJECT) OVER (PARTITION BY ROWID_OBJECT) SRC_PKEY_CT,
               CASE WHEN COUNT(DISTINCT PKEY_SRC_OBJECT) OVER (PARTITION BY ROWID_OBJECT) > 1 THEN 'Y' ELSE 'N' END MERGE_YN,
               CASE WHEN T.ROWID_OBJECT = T.ORIG_ROWID_OBJECT THEN 'Y' ELSE 'N' END MASTER_RECORD_YN,
               CASE WHEN MAX(HUB_STATE_IND) OVER (PARTITION BY ROWID_OBJECT) = -1 THEN 'Y' ELSE 'N' END SOFT_DELETE_YN,
               MIN(rowid_xref) OVER (PARTITION BY PKEY_SRC_OBJECT) MIN_ROWID_XREF
          FROM C_B_PTY_RLE_REL_XREF T
    )
    SELECT k.INDV_ID, k.REF_INDV_ID, k.pty_rle_fk_1, k.pty_rle_fk_2, k.RELATIONSHIP_TYPE_CD, x.SRC_PKEY_CT, l_sysdate,
           k.pkey_src_object, x.ROWID_OBJECT, x.MASTER_RECORD_YN, RTRIM(LTRIM(x.MERGE_YN)), k.SRC_SYS,
           x.MIN_ROWID_XREF
      FROM keyed k
     OUTER APPLY (SELECT * FROM xref
                   WHERE xref.PKEY_SRC_OBJECT = k.pkey_src_object FETCH FIRST 1 ROW ONLY) x
     -- Lookup_STG_TRS_DEACTIVATED_RELATIONSHIPS (PROCESSED_YN = 'N') + Fil_New_Deactivations
     WHERE NOT EXISTS (SELECT 1 FROM STG_TRS_DEACTIVATED_RELATIONSHIPS d
                        WHERE d.PROCESSED_YN = 'N' AND d.PKEY_SRC_OBJECT = k.pkey_src_object
                          AND d.PKEY_SRC_OBJECT IS NOT NULL)
       AND x.MIN_ROWID_XREF IS NOT NULL;
    sp_ors_helper02_common(c_mapping, 'insert STG_TRS_DEACTIVATED_RELATIONSHIPS', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1;
/

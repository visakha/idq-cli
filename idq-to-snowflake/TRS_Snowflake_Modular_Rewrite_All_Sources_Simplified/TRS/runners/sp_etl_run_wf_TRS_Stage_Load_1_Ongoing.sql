-- ============================================================================
-- sp_etl_run_wf_TRS_Stage_Load_1_Ongoing  --  WORKFLOW RUNNER (app level)
--
-- Runs the Snowflake replacement for IDQ workflow wf_TRS_Stage_Load_1_Ongoing,
-- in the same order as the original run script, with the same dependencies:
--   * m_Tgt_C_S_TRS_Pty_OnGoing first (it builds STG_TRS_VALID_MEMBERS,
--     which every later mapping joins to);
--   * m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw before
--     m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing (the second appends to
--     the table the first loads);
--   * m_Tgt_C_S_TRS_Addr_1 before m_Tgt_C_S_TRS_Addr_2 (part 2 reads the
--     unique addresses of part 1).
--   The IDQ command task (touch <workflow>.ind) is left to the scheduler,
--   exactly as in the original run script.
--
-- HOW TO RUN IT
--   CALL sp_etl_run_wf_TRS_Stage_Load_1_Ongoing();
--   (A JOB_RUN_ID is generated and returned. Pass one explicitly only if
--   you want this workflow attempt recorded under a specific id.)
--
-- RESTARTING (mapping level only -- there is no step-level restart)
--   A restart is simply a new run: call the runner again with no run id
--   (or with a new one). Each mapping, at its start (step 5), drops any
--   work tables the previous run of that mapping left in the database,
--   then runs every step from scratch. Work tables are never dropped at
--   the end of a run, and no mapping is ever skipped because it
--   completed in an earlier run -- a new run re-runs every mapping.
--   Because the procedures are insert-only with unique-key guards, a
--   re-run inserts nothing twice; it does not undo what an earlier run
--   already published (see the User Guide).
--
-- WHY THE RUNNER PASSES EVERY ORIGINAL PARAMETER EXPLICITLY
--   Mapping procedures append P_JOB_RUN_ID AFTER their original
--   parameters, so the runner cannot call a mapping with only the run
--   id -- it would land in the wrong parameter. The runner therefore
--   passes the original defaults (taken from each procedure's header)
--   in full, every time, followed by the run id.
--
-- WHY THE RUNNER DOES NOT RETURN EACH MAPPING'S SUMMARY
--   In Snowflake scripting, a CALL's return value cannot be assigned to
--   a variable as an expression, so the runner cannot collect the
--   mappings' summary strings. It returns the JOB_RUN_ID and a short
--   status line instead; the full per-step story is in
--   JOB_CONTROL_ETL (query VW_ETL_JOB_STORY for the run id).
--   Standalone mapping CALLs DO return their summary -- use those when
--   you run one mapping by hand.
--
-- This runner is APP level in the boundary model (see the User Guide):
-- it owns the workflow order, but it never writes to a target table
-- itself and never drops a work table.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_etl_run_wf_TRS_Stage_Load_1_Ongoing (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    l_job_run_id VARCHAR;
BEGIN
    IF (:P_JOB_RUN_ID IS NULL OR :P_JOB_RUN_ID = '') THEN
        l_job_run_id := 'TRS_WF_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
                        || '_' || UUID_STRING();
    ELSE
        l_job_run_id := :P_JOB_RUN_ID;
    END IF;

    -- Workflow-level STARTING row (MAPPING_NAME = 'WORKFLOW').
    CALL sp_etl_job_begin(:c_source, :c_workflow, 'WORKFLOW', :l_job_run_id);

    -- 1. Party (builds the valid-member spine).
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing('Indv', 'Member', 'DC_INDV', 'MCI', :l_job_run_id);

    -- 2. Party deactivation capture.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1(:l_job_run_id);

    -- 3. TOA (role level).
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA(:l_job_run_id);

    -- 4. Member-to-member relationships.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem('007', :l_job_run_id);

    -- 5. Relationship deactivation capture.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1(:l_job_run_id);

    -- 6. Member-to-PCP relationships.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP('100', :l_job_run_id);

    -- 7. Phones and emails.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr(:l_job_run_id);

    -- 8. Managed-attribute switches (must precede Auth Rep).
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw(:l_job_run_id);

    -- 9. Managed-attribute authorised representative.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing('Auth_Rep_Flag', :l_job_run_id);

    -- 10. Names.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm('002', :l_job_run_id);

    -- 11. Alternate IDs.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id(:l_job_run_id);

    -- 12. Plans.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln(:l_job_run_id);

    -- 13. Addresses, part 1 (must precede part 2).
    CALL sp_snow_main_m_Tgt_C_S_TRS_Addr_1(:l_job_run_id);

    -- 14. Addresses, part 2.
    CALL sp_snow_main_m_Tgt_C_S_TRS_Addr_2('Member', 'Member', 'Member Addr', :l_job_run_id);

    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, 'WORKFLOW',
        'wf_TRS_Stage_Load_1_Ongoing completed. JOB_RUN_ID = ' || :l_job_run_id
        || '. Per-step counts: SELECT * FROM VW_ETL_JOB_STORY WHERE JOB_RUN_ID = ''' || :l_job_run_id || ''' ORDER BY EVENT_ID;');
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || ' STATUS=COMPLETED MAPPINGS=14. '
           || 'Per-step story: SELECT * FROM VW_ETL_JOB_STORY WHERE JOB_RUN_ID = ''' || :l_job_run_id || ''' ORDER BY EVENT_ID;';
EXCEPTION
    WHEN OTHER THEN
        -- The failing mapping has already checkpointed its own FAILED
        -- row and left its work tables in place. This row records that
        -- the WORKFLOW stopped, so the next run starts cleanly from
        -- step 5 of each mapping (there is no step-level restart).
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, 'WORKFLOW',
            'wf_TRS_Stage_Load_1_Ongoing stopped at a mapping failure. Restart the workflow with a new run.');
        RAISE;
END;
$$;

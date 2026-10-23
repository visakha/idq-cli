# TRS IDQ — Verification Checklist

Tick-through list derived from §5 "Findings, risks and points to verify" of
`TRS_IDQ_Workflow_and_Mapping_Analysis.md` (v2, all 44 mapping definitions documented).
Check items against the **live repository / runtime**, not just the export — an
IMX export can preserve a developer's local test settings.

## Check promptly (runtime-impacting)

- [ ] **1. Remove or confirm the hard-coded test filter.**
  Where: source filter `INDV_ID=504937068` in `m_Tgt_C_S_TRS_Pty_OnGoing`
  (§6.1, line ~466) and `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` (§6.1, line ~3071).
  Action: open both mappings in the live repo; if the filter is active, the
  party and alt-ID loads process a single individual. Remove unless it is a
  deliberately-scoped run.

- [ ] **2. Confirm the phone/email row cap is deliberate.**
  Where: source filter `rownum < 100000` in `m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`.
  Action: decide whether this is an intentional batch-size guard (with a
  compensating re-run / backlog process) or a leftover. Above ~100k delta rows,
  contact records are silently dropped from that run.

- [ ] **3. Fix the pre-SQL table-name typo on the phone target.**
  Where: target pre-SQL `call Utility.Table_Pre_Load_Maint('_C_S_TRS_PTY_RLE_PHN');`
  — leading underscore; the matching post-SQL and every other target use the
  plain name `C_S_TRS_PTY_RLE_PHN`.
  Action: check what the utility procedure does with a non-existent name; if it
  no-ops, the phone staging table is loading without its pre-load maintenance.
  Correct the name in the target.

## Operational / design review

- [ ] **4. Audit tooling must read both IMX serialisation forms.**
  Where: deactivation exports + 13 objects in the ongoing export embed mappings
  as `<IObject>` inside Project contents instead of top-level `<Mapping>`.
  Action: verify any inventory/backup/audit tooling counts both forms before
  relying on an export as a recovery or audit source.

- [ ] **5. Bring the deactivation shell scripts under version control.**
  Where: `./unmerge_soft_delete_party.sh` and `./unmerge_soft_delete_relationship.sh`
  run from `/u01/apps/informatica/mdm_exec_batch/scripts` (command tasks
  `Cmd_Unmerge_Soft_Delete` in `wf_TRS_Deactivation_Initial` and
  `wf_TRS_Relationship_Deactivation`).
  Action: review and back up these scripts (MDM batch-group unmerge + Oracle
  soft-delete procedure) with the same rigour as the IDQ exports — the hub-side
  deactivation logic lives here, not in the mappings.

- [ ] **6. Document the failed-run recovery sequence.**
  Where: `wf_TRS_Deactivation_Initial` / `wf_TRS_Relationship_Deactivation`
  annotations — re-running after a partial deactivation re-populates MDM staging
  and fails on duplicate keys where soft-delete rows already exist.
  Action: runbook should sequence a failed deactivation run as
  *Complete/clean-up first*, not a blind restart. Mark Processed is re-runnable
  by design.

- [ ] **7. Guard against mid-load failure on truncate-loaded targets.**
  Where: most `C_S_*` targets truncate at mapping start; no cross-mapping
  transaction exists.
  Action: the workflow's success-gated design mitigates this, but confirm the
  MDM batch is never started off an `.ind` indicator file from a
  partially-failed cycle.

- [ ] **8. Isolate the shared workflow success variable.**
  Where: `wf_TRS_Stage_Load_1_Ongoing` — all parallel branches set and test the
  same `$var:MappingTaskSuccessful` (last writer wins).
  Action: consider per-branch variables or per-branch gateways so failure
  isolation is auditable.

- [ ] **9. Uniqueness check on the code crosswalk.**
  Where: code lookups use multiple-match handling = `returnAny` against
  `LOOKUP_CODE_VALUE` / `V_LOOKUP_CODE_VALUE`.
  Action: duplicate rows for the same code type + source code produce
  non-deterministic master codes — add a uniqueness check on the crosswalk.

- [ ] **10. Preserve the two-step address design in any redesign.**
  Where: designer's own annotation — address validation is the ongoing load's
  bottleneck; Addr_1 validates unique addresses once, Addr_2 distributes.
  Action: keep this mitigation in any rework of the load.

---
*Source: analysis of the six IDQ IMX exports (incl. the `-2` deactivation
re-exports); see `TRS_IDQ_Workflow_and_Mapping_Analysis.md` §5 for the full
findings with evidence, and §6/§7 for per-mapping detail.*

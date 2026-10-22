# WIC deactivation workflows: analysis

Analysis only. No code, tests or mapping docs were changed. Sources: `docs/wf_WIC_Deactivation_Initial.xml` and
`docs/wf_WIC_Deactivation_Complete.xml` (IDQ 10.x exports, project `HHSC_Enterprise_Development`), read against
`wf_WIC_Stage_Load`, mapping 029 (`m_Tgt_C_S_WIC_Pty_Validation`), `core/InactiveStatus.java` and
`docs/common_insights.md` sections 6 and 7.

| File | What it covers |
|---|---|
| [01-purpose-and-lifecycle.md](01-purpose-and-lifecycle.md) | What the two workflows are for, and where they sit in the WIC day |
| [02-how-it-is-implemented.md](02-how-it-is-implemented.md) | Task by task and port by port, with the equivalent SQL |
| [03-defects-and-risks.md](03-defects-and-risks.md) | What is wrong or fragile in the current design |
| [04-recommended-design.md](04-recommended-design.md) | A cleaner way to do the same job, and how it fits idq-cli |

## In one paragraph

`wf_WIC_Stage_Load` decides that a WIC party should be inactive (incomplete name). It writes a row with status `P`
(*pending*) to `STG_WIC_PTY_INACTIVE_STS` when the MDM hub still holds that party as active. It does not tell
the MDM hub. These two workflows do. **Initial** copies every `P` key into an MDM utility table
(`HHS_MDM_ORS.ZZ_UTL_UNMERGE_TREE_SRC_KEY`) and runs an MDM-side shell script (`unmerge_soft_delete_party.sh`).
The script unmerges the WIC cross-reference from its golden record and soft-deletes it (`HUB_STATE_IND = -1`).
**Complete** later checks `C_B_PTY_XREF`: each `P` party whose WIC xref is now `-1` becomes `D` (*deactivated*).
`P` parties the hub has not deleted stay `P` and are sent again by the next Initial run. Together they make a
two-phase handshake: send the request, then confirm it against the hub.

## Main findings

1. **The design is sound, but the plumbing is fragile.** The handshake (request, then confirm against the system of
   record) is the right pattern. What is fragile is how it is built: a truncated, shared, cross-schema hand-off table,
   a shell script the export does not contain, and gates that do not check whether the mapping succeeded.
2. **A failed copy mapping can still raise the "done" indicator** (Initial). `TgtRows` stays 0, so the gateway
   treats the run as "nothing to do" and touches `wf_WIC_Deactivation_Initial.ind`. Meanwhile the truncate has
   already emptied the hand-off table.
3. **Complete's success gate is a constant.** `MappingIsSuccessful` is declared with the value `true` and never bound
   to the mapping task, so `$var:MappingIsSuccessful=true` is always true.
4. **Complete overwrites `DEACTIVATION_DT`.** After it runs, the date is when the hub deletion was confirmed, no
   longer when the deactivation was decided. Nothing in the table keeps the request date.
5. **Insert-only conflict.** The IDQ pair needs a `TRUNCATE` (Initial) and an `UPDATE` (Complete). Neither can be
   ported as-is under this repo's insert-only rule. Also, the Java port keeps the status row on reactivation
   (`InactiveStatus.output`: the `DD_DELETE` is not performed). So a reactivated `P` party would still be sent for
   soft-delete if these workflows ran from CLI-written status rows. This must be designed out before the pair is
   ported (see 04).
6. **Recommendation:** use one append-only *deactivation request* table with a request id and its state
   (`REQUESTED → SUBMITTED → CONFIRMED / FAILED`), written in the same run as the validation. Use one set-based
   reconcile statement instead of a dynamic-cache lookup. Have the MDM side read a view instead of a truncated copy,
   and gate every step on real success. Where the MDM configuration allows, send soft-deletes through the existing
   stage/load path with `HUB_STATE_IND = -1`, the same way reactivations already go through it with `1`.

## What is inferred, not seen

- `unmerge_soft_delete_party.sh` (MDM host, `/u01/apps/informatica/mdm_exec_batch/scripts`) is not in the repo or
  the export. Its behaviour comes from its name, the table name `ZZ_UTL_UNMERGE_TREE_SRC_KEY`, the
  `EXPLODE_NODE_IND = '1'` column, and what Complete checks afterwards (`HUB_STATE_IND = -1`). Get the script
  before porting.
- Whatever schedules the three workflows in order (Stage_Load → Initial → Complete) is not in the repo. The
  `.ind` files in `/opt/apps/informatica/SrcFiles/Indicators` suggest an external scheduler that watches files.
- Whether a failed mapping task stops an IDQ workflow depends on the workflow's recovery settings (Initial: recovery
  off; Complete: recovery on). Finding 2 assumes the default for a workflow without recovery: the failed task's
  outputs keep their initial values and the next objects still run. Confirm this in the DIS logs of a failed run.

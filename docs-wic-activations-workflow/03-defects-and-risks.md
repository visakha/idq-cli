# 3. Defects and risks

Ordered by impact. "Defect" = demonstrably wrong in the export. "Risk" = fragile or dependent on something outside
the export.

| # | Kind | Where | What happens | Effect |
|---|---|---|---|---|
| R1 | Defect | Initial, gateways | The success gate is `TgtRows = 0 OR (script ok)`. A **failed** copy mapping leaves `TgtRows` at 0, so the run counts as "nothing to do" and goes straight to the indicator. | `wf_WIC_Deactivation_Initial.ind` is written although nothing was sent. The truncate has already emptied the hand-off table. `MappingIsSuccessful` is declared but never bound, so it cannot help. |
| R2 | Defect | Complete, gateway | `$var:MappingIsSuccessful = true` checks a variable that is never bound to the mapping. It is always `true`. | The gate does nothing. Whether a failed update still reaches the indicator depends only on the recovery settings, not on the design. |
| R3 | Defect | Complete, `DEACTIVATION_DT` | Complete overwrites the date the validation wrote. | After `P → D` the table no longer shows when the deactivation was decided, only when the hub confirmed it. Turnaround (decision → hub deletion) cannot be measured, and an audit cannot tell when WIC data deactivated the party. |
| R4 | Risk | Initial, hand-off table | `ZZ_UTL_UNMERGE_TREE_SRC_KEY` has a generic name, no source column of its own beyond `ROWID_SYSTEM`, no run id, and is **truncated** each run. | If another source's (or a manual) unmerge uses the same utility table, concurrent runs wipe each other's lists. Nothing records which run sent what. |
| R5 | Risk | Initial → script | The script runs from a fixed working directory on the MDM batch host. Its behaviour (synchronous? does it submit a batch job? tree unmerge before delete?) is not in the export. Its exit code is the only feedback. | The real deactivation logic sits outside version control, as far as this repo can see. A script that "succeeds" by submitting a job that later fails is only noticed if someone watches for rows stuck in `P`. |
| R6 | Risk | Port to idq-cli | IDQ *deletes* the status row on reactivation. The Java port of 029 does not (insert-only; `InactiveStatus.output`). | If Initial were driven off CLI-written status rows, a party that was deactivated as `P` and later **reactivated** would still be `P` and would be **soft-deleted in the hub after its reactivation**. The pair must not be ported without a "current status" rule that sees the reactivation (see 04). |
| R7 | Risk | Both | The pair needs `TRUNCATE` (Initial) and `UPDATE` (Complete). | It cannot be ported word for word under the repo's insert-only rule, in Java, `idq-to-oracle` or `idq-to-snowflake`. |
| R8 | Risk | Retry loop | `P` rows are re-sent on every run, with no counter, no age limit and no alert. | A party the hub can never delete (hard-deleted xref, key changed, merged away, script bug) is re-sent for ever. Nobody is told. |
| R9 | Smell | Complete, lookup | Dynamic cache with all ~70 `C_B_PTY_XREF` columns, built for an existence check. | It caches every soft-deleted WIC xref in full, every run. That wastes memory and time, and it grows with history. |
| R10 | Smell | Initial | `RPAD(ROWID_SYSTEM, 14)` into a `CHAR(14)` column; typo `Source_Sytem_Padded`; unused `MappingIsSuccessful`. | Harmless, but it shows the workflow was copied from a template and not tidied. |
| R11 | Risk | Ordering | The three workflows are chained only by `.ind` files and an external scheduler. | If Initial overlaps Stage_Load, the `P` rows inserted after its read go out only on the next cycle. Worse, if the script only *submits* an asynchronous hub job, the next Stage_Load can reactivate the party (delete the status row, reload it with hub state 1) before that job runs. The job then soft-deletes the xref anyway: the hub holds a deleted xref for a party WIC treats as active, and nothing reconciles it, because the status row is gone. |

## Things that are right and worth keeping

- **Confirmation against the system of record.** Complete checks `C_B_PTY_XREF`, not the script's exit code.
- **Idempotent, self-healing retry.** A failed run costs nothing more than a delay: the `P` rows go out again.
- **Clear separation of states** (`H` / `D` / `P`): parties that never reached the hub are not sent to it.
- **Skip the script when there is nothing to do** (`TgtRows > 0` gate). This avoids pointless MDM batch jobs.

## IDQ behaviour worth recording in `docs/common_insights.md`

- A workflow variable that is declared but **not bound** to a task output keeps its initial value. A gateway such as
  `$var:MappingIsSuccessful = true` is then a constant. (Complete: always true. Initial: declared, unused.)
- A "skip when no data" gateway on *number of target rows* cannot tell an empty result from a failed mapping. Both
  give 0 (Initial, R1).
- Complete moves a WIC status `P → D` and sets `DEACTIVATION_DT` to its own run start, so the decision date is lost
  (R3).

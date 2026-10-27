# STEP MAP — wf_TTF_Stage_Load (TTF, simplified v2 style)

Workflow run order (same as the original run script): Pty_Validation,
Pty, Pty_Rle_Alt_Id, Pty_Rle_Phn. All procedures install in schema
`TTF_ETL_WRK` in database `MDM_ETL_TTF`; all table names are
unqualified in code. Every mapping starts with step 5
`CLEANUP_PREVIOUS_RUN` (bare `DROP TABLE IF EXISTS` for that mapping's
work tables only, no checkpoint for drops), ends with a `TERMINATING`
row, and leaves its work tables standing. Restart is mapping-level
only: a new run. Publish is the only transaction in each mapping.

## 1. m_Tgt_C_S_TTF_Pty_Validation

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Original: no parameters; `P_JOB_RUN_ID` appended.

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | ENRICHED | `WRK_TTF_VAL_S1_ENRICHED` | Clients + latest inactive status + cross-reference row + standardised-name object |
| 20 | NAMED | `WRK_TTF_VAL_S2_NAMED` | Standardised names pulled out + blank / DECLINED / DO_NOT_DISCLOSE flags |
| 30 | ROUTED | `WRK_TTF_VAL_S3_ROUTED` | Router groups (invalid name / deactivation / reactivation) + exception code, description, type + first-row-per-key flag `uq_exc_name` |
| 40 | PUBLISH | — (targets only) | One transaction, 4 inserts (see below) |

Publish targets (step 40, in order):
- `EXC_STG_BAD_REC_MEMB` — invalid party names (`grp_invalid_party_name AND uq_exc_name`)
- `STG_TTF_PTY_INACTIVE_LOG` — deactivation log rows (`grp_deactivation`)
- `STG_TTF_PTY_INACTIVE_STS` — new status rows (`grp_deactivation AND deactivation_sts IS NULL`)
- `STG_TTF_PTY_INACTIVE_LOG` — reactivation log rows (`grp_reactivation`)

Preserved quirks: insert-only (IDQ DD_DELETE of the inactive-status
table not performed); a DO_NOT_DISCLOSE name is logged but does not
deactivate; the source WHERE fragment (test client ids) is not applied;
cross-reference filter is `TRIM(ROWID_SYSTEM) = 'TTF'`.

## 2. m_Tgt_C_S_TTF_Pty

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty(P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member', P_JOB_RUN_ID VARCHAR DEFAULT NULL)`

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | ACTIVE | `WRK_TTF_PTY_S1_ACTIVE` | Active clients only (inactive parties filtered out) + gender decoded from SEXID + ethnicity flag |
| 20 | DQ | `WRK_TTF_PTY_S2_DQ` | Name-standardisation object, gender object, birth-date exception code, ethnicity / race master codes |
| 30 | DQ2 | `WRK_TTF_PTY_S3_DQ2` | Standardised fields + exception descriptions / types pulled out; future birth date nulled |
| 40 | ROUTED | `WRK_TTF_PTY_S4_ROUTED` | Party / role keys, exception groups, constants, insert-only guards `uq_pty / uq_rle / uq_gender / uq_birth / uq_ethnicity / uq_race` |
| 50 | PUBLISH | — (targets only) | One transaction, 6 inserts (see below) |

Publish targets (step 50, in order):
- `C_S_TTF_PTY` — valid parties (`uq_pty`)
- `C_S_TTF_PTY_RLE` — valid roles (`uq_rle`)
- `EXC_STG_BAD_REC_MEMB` — invalid gender (`grp_gender AND uq_gender`)
- `EXC_STG_BAD_REC_MEMB` — invalid birth date (`grp_birth AND uq_birth`)
- `EXC_STG_BAD_REC_MEMB` — invalid ethnicity (`grp_ethnicity AND uq_ethnicity`)
- `EXC_STG_BAD_REC_MEMB` — invalid race (`grp_race AND uq_race`)

Preserved quirks: insert-only (IDQ truncate of party / role targets not
performed); Invalid_Language / Invalid_Suffix groups never write (unfed
ports, no branches generated); PRFRD_LANG_CD and SFX_NM are NULL (unfed
ports); VERSION_SEQ = 1; party PERIOD_START_DATE = run start, role
PERIOD_START_DATE = SUBMITDATE; an exception never stops the party
loading.

## 3. m_Tgt_C_S_TTF_Pty_Rle_Alt_Id

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Original: no parameters; `P_JOB_RUN_ID` appended.

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | KEYS | `WRK_TTF_ALT_S1_KEYS` | Candidate keys for active clients only (party key, submit date, alternate-id key) |
| 20 | DEDUP | `WRK_TTF_ALT_S2_DEDUP` | Keys not already loaded + one row per key (latest submit date wins) |
| 30 | PUBLISH | — (targets only) | One transaction, 1 insert (see below) |

Publish target (step 30):
- `C_S_TTF_PTY_RLE_ALT_ID` — one alternate id per active client, type '024'

FLAGGED — THIN SPLIT: the original is a single short query, not a CTE
chain, so the split above is the closest sensible one. Step 20 is not a
separate business stage in the original; it is the already-loaded guard
+ one-row-per-key dedup half of the one original SELECT, pulled out so
the publish input can be counted and inspected before it lands.

Preserved quirks: insert-only (IDQ truncate not performed); the source
WHERE fragment (test client ids) is not applied; VERSION_SEQ = 1;
PERIOD_START_DATE = run start.

## 4. m_Tgt_C_S_TTF_Pty_Rle_Phn

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Original: no parameters; `P_JOB_RUN_ID` appended.

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | SRC | `WRK_TTF_PHN_S1_SRC` | Non-NULL phones of active clients only + phone key + standardised phone |
| 20 | CHECKED | `WRK_TTF_PHN_S2_CHECKED` | Phone validation code (area-code lookup included); NULL = good phone |
| 30 | ROUTED | `WRK_TTF_PHN_S3_ROUTED` | Exception description, constants, insert-only guards `uq_phn / uq_phone_exc` |
| 40 | PUBLISH | — (targets only) | One transaction, 2 inserts (see below) |

Publish targets (step 40, in order):
- `C_S_TTF_PTY_RLE_PHN` — good phones (`phone_exception_code IS NULL AND uq_phn`)
- `EXC_STG_BAD_REC_MEMB` — bad phones as 'Rejected Record' exceptions (`phone_exception_code IS NOT NULL AND uq_phone_exc`)

Preserved quirks: insert-only (IDQ truncate not performed);
Bad_Phone_Ext records never occur (unfed extension port, no branch
generated); exception SRC_SYS_ID_2 is NULL (unfed ID_PHONE port); the
source invalid SQL fragment is not applied; VERSION_SEQ = '1';
PERIOD_START_DATE = SUBMITDATE; a bad phone is logged only, never
loaded.

## Runner

- `runners/sp_etl_run_wf_TTF_Stage_Load.sql` —
  `sp_etl_run_wf_TTF_Stage_Load(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`.
  Generates `TTF_WF_...` when NULL, writes a WORKFLOW-level job_begin
  row, calls the 4 mappings in the original run-script order passing
  each mapping's original defaults in full followed by the run id, then
  job_finish; on failure, job_fail + RAISE. Writes to no target and
  drops no work table itself.
- `runners/run_wf_TTF_Stage_Load.sql` — SnowSQL script: header comment,
  `!set exit_on_error=true`, a single `CALL sp_etl_run_wf_TTF_Stage_Load();`.

# STEP MAP — WIC (wf_WIC_Stage_Load, modular rewrite, simplified v2 style)

Install location: database `MDM_ETL_WIC`, schema `WIC_ETL_WRK`. All table
and procedure names in the rewritten code are unqualified, exactly as in
the originals.

Run order (identical to the original run script
`run_wf_WIC_Stage_Load.sql`, and to the runner
`sp_etl_run_wf_WIC_Stage_Load`):

1. `m_Tgt_C_S_WIC_Pty_Validation`
2. `m_Tgt_C_S_WIC_Pty`
3. `m_Tgt_C_S_WIC_Pty_Addr`
4. `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`
5. `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`

Every mapping starts with step 5 `CLEANUP_PREVIOUS_RUN` (bare
`DROP TABLE IF EXISTS` statements for that mapping's work tables only, no
checkpoint call for drops), then runs every staged step from scratch, then
publishes in a single transaction. Work tables are TRANSIENT, are left
standing after the run, and are cleaned at the start of the next run.
Restart is mapping-level only: there is no step-level resume, no
`P_RESUME_STEP`, and no cleanup procedure. Every mapping appends
`P_JOB_RUN_ID VARCHAR DEFAULT NULL` after its original parameters, in
the same order as the original.

Publish checkpoint row counts are the final work-table row counts feeding
the publish (each branch inserts only its own WHEN-filtered subset), except
where noted. Step checkpoints carry the work-table row count for that step.

---

## 1. m_Tgt_C_S_WIC_Pty_Validation
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation(P_JOB_RUN_ID)`
Original: no parameters; the rewrite appends `P_JOB_RUN_ID` only.

What it does, in plain words: checks the WIC parties and maintains the
deactivation list every later WIC mapping reads. A party whose
standardised first or last name is blank is logged as an exception,
written to the deactivation log, and given a new deactivation-status row
if it has none yet. A party that already has a status and now has both
names present is written to the deactivation log as a reactivation.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below, no checkpoint |
| 10 | ENRICHED | `WRK_WIC_VAL_S10_ENRICHED` | Source parties joined to the current deactivation status (latest row per source key) and the cross-reference hub state, with standardised names computed. The status / cross-reference lookups stay inline here because they are reference lookups, not data stages. Only step that reads `V_WIC_ETL_SRC`. |
| 20 | NAMED_BLANK_TEST | `WRK_WIC_VAL_S20_NAMED` | Standardised first / middle / last names pulled out; the blank-name test applied (`name_missing`). |
| 30 | ROUTED | `WRK_WIC_VAL_S30_ROUTED` | Exception code / attribute name / value, new deactivation status from hub state, looked-up exception description and type, run constants, and the first-row-per-exception-key flag (`uq_exc_name`). Computed before publish, so routing sees the pre-run status. |
| 40 | PUBLISH (one transaction) | — (reads step 30) | See publish targets below. |

Publish targets (step 40, in original INSERT ALL branch order):
- `EXC_STG_BAD_REC_MEMB` — invalid party names (`name_missing AND uq_exc_name`)
- `STG_WIC_PTY_INACTIVE_LOG` — deactivations (`name_missing`)
- `STG_WIC_PTY_INACTIVE_STS` — new deactivation-status rows (`name_missing AND deactivation_sts IS NULL`)
- `STG_WIC_PTY_INACTIVE_LOG` — reactivations (`deactivation_sts IS NOT NULL AND NOT name_missing`)

Preserved quirks: insert-only (the IDQ delete of
`STG_WIC_PTY_INACTIVE_STS` is not performed); the cross-reference lookup
filters on `TRIM(ROWID_SYSTEM) = 'WIC'`; no timeline handling in this
mapping.

---

## 2. m_Tgt_C_S_WIC_Pty
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty(P_PTY_BO_CLASS_CD_MEMBER DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER DEFAULT 'Member', P_JOB_RUN_ID)`
Original parameters, in order: `P_PTY_BO_CLASS_CD_MEMBER`,
`P_RLE_BO_CLASS_CD_MEMBER`; `P_JOB_RUN_ID` appended.

What it does, in plain words: loads the active WIC parties into the party
and party-role tables and logs demographic exceptions. Every active party
loads — an exception never rejects the party, it is loaded AND logged.
Gender, ethnicity and race exceptions are logged only for
`SOURCE_TABLE = 'CLIENT'`; birth date and language exceptions are logged
for every row.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below, no checkpoint |
| 10 | ACTIVE | `WRK_WIC_PTY_S10_ACTIVE` | Active source parties only (parties with a deactivation status removed). Only step that reads `V_WIC_ETL_SRC`. |
| 20 | DQ_STANDARDISE_VALIDATE | `WRK_WIC_PTY_S20_DQ` | Name standardisation, gender, birth date, ethnicity, race indicators, language. |
| 30 | DQ2_EXCEPTION_DETAIL | `WRK_WIC_PTY_S30_DQ2` | Standardised values pulled out; every exception description and type resolved from the exception lookup; birth-date value used downstream is NULL when the birth date raised an exception. |
| 40 | ROUTED | `WRK_WIC_PTY_S40_ROUTED` | Party / role keys, exception routing groups, run constants, birth weight in grams, and the insert-only guards (`uq_pty`, `uq_rle`, `uq_gender`, `uq_birth`, `uq_ethnicity`, `uq_race`, `uq_language`). Guards evaluated here, before publish, as in the original single query. |
| 50 | PUBLISH (one transaction) | — (reads step 40) | See publish targets below. |

Publish targets (step 50, in original INSERT ALL branch order):
- `C_S_WIC_PTY` — valid parties (`uq_pty`)
- `C_S_WIC_PTY_RLE` — valid roles (`uq_rle`)
- `EXC_STG_BAD_REC_MEMB` — invalid gender (`grp_gender AND uq_gender`)
- `EXC_STG_BAD_REC_MEMB` — invalid birth date (`grp_birth AND uq_birth`)
- `EXC_STG_BAD_REC_MEMB` — invalid ethnicity (`grp_ethnicity AND uq_ethnicity`)
- `EXC_STG_BAD_REC_MEMB` — invalid race (`grp_race AND uq_race`)
- `EXC_STG_BAD_REC_MEMB` — invalid language (`grp_language AND uq_language`)

Preserved quirks: insert-only (IDQ truncates of `C_S_WIC_PTY` /
`C_S_WIC_PTY_RLE` not performed); party birth date is the source DOB while
the language exception row writes the mapplet's birth date (NULL for a
future one); birth weight in grams is `BIRTH_WT_OZ * 28.35` (ounces only);
`VERSION_SEQ` hard-coded to 1, `PERIOD_START_DATE = DATEKEY`;
`HUB_STATE_IND` hard-coded to 1.

---

## 3. m_Tgt_C_S_WIC_Pty_Addr
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr(P_MEMBER_HIERARCHY_CODE DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD DEFAULT 'Member Addr', P_JOB_RUN_ID)`
Original parameters, in order: `P_MEMBER_HIERARCHY_CODE`,
`P_MEMBER_HM_REL_TP_CD`; `P_JOB_RUN_ID` appended.

What it does, in plain words: validates the WIC addresses and loads the
good ones into the party-role address table. Every active address is
written to the address-quality table first. A good address (score '100')
loads; an exception address (score '40') is only logged, never loaded.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below, no checkpoint |
| 10 | ACTIVE | `WRK_WIC_ADDR_S10_ACTIVE` | Active source addresses only (deactivation-status filter) + the address key. Only step that reads `V_WIC_ETL_SRC`. |
| 20 | VALIDATED | `WRK_WIC_ADDR_S20_VALIDATED` | Address validation with state 'TX', country 'US', zip only; state code resolved from the state lookup. |
| 30 | FLAT | `WRK_WIC_ADDR_S30_FLAT` | Validation result pulled out into flat columns; match-code description resolved. |
| 40 | SCORED | `WRK_WIC_ADDR_S40_SCORED` | Score ('100' / '40'), exception detail, held address lines, run constants, and the insert-only guards (`uq_addr`, `uq_addr_exc`). Target guard evaluated here, before publish, as in the original single query. |
| 50 | PUBLISH (one transaction) | — (reads step 40) | See publish targets below. |

Publish targets (step 50, in original INSERT ALL branch order):
- `DQM_ADDRESS` — every active address (unconditional branch)
- `C_S_WIC_PTY_RLE_ADDR` — good addresses (`score = '100' AND uq_addr`)
- `EXC_STG_BAD_REC_MEMB` — exception addresses (`score = '40' AND uq_addr_exc`)

Preserved quirks: insert-only (IDQ truncate of `C_S_WIC_PTY_RLE_ADDR`
not performed); address type is the constant '002', so with the
pass-through validator every address scores '100'; exception addresses
are logged only ('Invalid Address per Address Doctor', 'Bad Value');
unfed ports written as NULL (including `SRC_STATE`, even though 'TX'
goes to the validator); `DQM_ADDRESS.PTY_SRC_KEY` is `LPAD(ID, 10, '0')`
(the ECI-only 'F' suffix never applies); `VERSION_SEQ = 1`,
`PERIOD_START_DATE / EFF_STRT_DT = DATE_ADDRESS_VALID_FROM`,
`EFF_END_DT` and `PERIOD_REFERENCE_TIME` NULL.

---

## 4. m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr(P_JOB_RUN_ID)`
Original: no parameters; the rewrite appends `P_JOB_RUN_ID` only.

What it does, in plain words: each active WIC row gives one phone and
possibly one e-mail. Good phones load, bad phones are logged. Non-null
e-mails are validated the same way: valid e-mails load, bad e-mails are
logged.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below, no checkpoint |
| 10 | SRC | `WRK_WIC_PHN_S10_SRC` | Active source rows only (deactivation-status filter) + party-role / phone / e-mail keys, standardised phone, e-mail validation object (NULL when e-mail is null). Only step that reads `V_WIC_ETL_SRC`. |
| 20 | CHECKED | `WRK_WIC_PHN_S20_CHECKED` | Phone exception code from the area-code lookup (usage '001'); standardised e-mail pulled out. |
| 30 | ROUTED | `WRK_WIC_PHN_S30_ROUTED` | Phone / e-mail exception descriptions, codes and types resolved; good / bad routing groups for phones and e-mails. |
| 40 | READY | `WRK_WIC_PHN_S40_READY` | Run constants (phone type 'Telephone', usage '001', preference 'Primary', e-mail type '001', status 'Active', valid 'Y') and the insert-only guards (`uq_phn`, `uq_eaddr`, `uq_phone_exc`, `uq_email_exc`). Target guards evaluated here, before publish, as in the original single query. |
| 50 | PUBLISH (one transaction) | — (reads step 40) | See publish targets below. |

Publish targets (step 50, in original INSERT ALL branch order):
- `C_S_WIC_PTY_RLE_PHN` — good phones (`grp_phone_good AND uq_phn`)
- `EXC_STG_BAD_REC_MEMB` — bad phones (`grp_phone_bad AND uq_phone_exc`)
- `C_S_WIC_PTY_RLE_EADDR` — valid e-mails (`grp_email_good AND uq_eaddr`)
- `EXC_STG_BAD_REC_MEMB` — bad e-mails (`grp_email_bad AND uq_email_exc`)

Preserved quirks: insert-only (IDQ truncates of the phone / e-mail
targets not performed); no null-phone filter — a party without a phone
is validated and logged as an invalid phone; the e-mail key uses the
e-mail as read (no trim); the phone routing groups overlap by
construction — a 'Missing_AreaCode' code counts as both good and bad, so
the original INSERT ALL would write such a row to both the phone table
and the exception table, and the publish INSERTs below keep the same
WHEN conditions (the original header notes 'Missing_AreaCode' only
exists for ECI, so WIC never gets it in practice); `VERSION_SEQ` is '1'
on both targets, `PERIOD_START_DATE = DATEKEY`.

---

## 5. m_Tgt_C_S_WIC_Pty_Rle_Alt_Id
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id(P_JOB_RUN_ID)`
Original: no parameters; the rewrite appends `P_JOB_RUN_ID` only.

What it does, in plain words: writes one alternate id per active WIC
party — the WIC id padded to 12, type '020' for `SOURCE_TABLE`
'CLIENT' and '021' otherwise. Parties with a deactivation status are
excluded; keys already in the target are skipped.

**Split flag:** this original has no CTE chain — it is a single query
(an inner derived table plus an outer SELECT). The split used is the
closest sensible one: step 10 builds the keys (the original inner
derived table) and step 20 applies the deactivation filter, the
already-loaded guard and the one-row-per-key rank (the original outer
SELECT). Nothing was merged into a single step, and no business
expression was changed.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below, no checkpoint |
| 10 | KEYS | `WRK_WIC_ALT_S10_KEYS` | Party-role key, id type ('020' / '021'), alternate-id key. Only step that reads `V_WIC_ETL_SRC`. |
| 20 | READY | `WRK_WIC_ALT_S20_READY` | Deactivation filter applied, keys already in the target skipped, one row per alternate-id key (latest `DATEKEY` wins). Guard evaluated here, before publish, as in the original single query. |
| 30 | PUBLISH (one transaction) | — (reads step 20) | See publish target below. |

Publish target (step 30, single INSERT):
- `C_S_WIC_PTY_RLE_ALT_ID` — one alternate id per active party (all rows in step 20; filters and guard already applied there, so the publish count equals the ready-row count)

Preserved quirks: insert-only (IDQ truncate of
`C_S_WIC_PTY_RLE_ALT_ID` not performed); `HUB_STATE_IND` is not linked
(left to the column default); `VERSION_SEQ = 1`,
`PERIOD_START_DATE = DATEKEY`; no validation rule runs in this mapping.

---

## Runner
File: `runners/sp_etl_run_wf_WIC_Stage_Load.sql`
Procedure: `sp_etl_run_wf_WIC_Stage_Load(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Generates a `WIC_WF_` run id when none is passed, writes a
WORKFLOW-level `job_begin` row, calls the 5 mappings in the original run
order passing each mapping's original defaults in full followed by the
run id, then `job_finish`; on failure `job_fail` + `RAISE`. It writes to
no target and drops no work table.

File: `runners/run_wf_WIC_Stage_Load.sql`
SnowSQL script with `!set exit_on_error=true` and a single
`CALL sp_etl_run_wf_WIC_Stage_Load();` (replaces the original script's
5 CALL lines; the scheduler's IDQ command task is still left to the
scheduler).

## Work-table inventory (all TRANSIENT, all in WIC_ETL_WRK)
- Validation: `WRK_WIC_VAL_S10_ENRICHED`, `WRK_WIC_VAL_S20_NAMED`, `WRK_WIC_VAL_S30_ROUTED`
- Party: `WRK_WIC_PTY_S10_ACTIVE`, `WRK_WIC_PTY_S20_DQ`, `WRK_WIC_PTY_S30_DQ2`, `WRK_WIC_PTY_S40_ROUTED`
- Address: `WRK_WIC_ADDR_S10_ACTIVE`, `WRK_WIC_ADDR_S20_VALIDATED`, `WRK_WIC_ADDR_S30_FLAT`, `WRK_WIC_ADDR_S40_SCORED`
- Phone/E-mail: `WRK_WIC_PHN_S10_SRC`, `WRK_WIC_PHN_S20_CHECKED`, `WRK_WIC_PHN_S30_ROUTED`, `WRK_WIC_PHN_S40_READY`
- Alt Id: `WRK_WIC_ALT_S10_KEYS`, `WRK_WIC_ALT_S20_READY`

Total: 17 work tables across 5 mappings. No work table is shared between
mappings; each mapping's step 5 drops only its own tables.

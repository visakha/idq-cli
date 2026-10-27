# Step map — wf_FSS_Stage_Load (FSS, modular rewrite)

Install schema is `FSS_ETL_WRK` in database `MDM_ETL_FSS`. All table
names in the procedures are unqualified, as in the originals.

Run order (same as the original `run_wf_FSS_Stage_Load.sql`):

1. `m_Tgt_C_S_FSS_Pty_Validation`
2. `m_Tgt_C_S_FSS_Pty`
3. `m_Tgt_C_S_FSS_Pty_Addr`
4. `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`
5. `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`
6. `m_Tgt_C_S_FSS_Pty_Rle_Rel`

Every mapping starts with step 5 `CLEANUP_PREVIOUS_RUN`: bare
`DROP TABLE IF EXISTS` statements for that mapping's work tables only,
with no checkpoint call for the drops. Every mapping ends with step 50
`PUBLISH` (the only transaction) and a terminating row; work tables
are left standing after the run. There is no step-level restart and no
resume parameter — a restart is simply a new run.

## 1. m_Tgt_C_S_FSS_Pty_Validation

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | SRC | `WRK_FSS_VAL_S1_SRC` | Source clients: last active registration or all-inactive rows |
| 20 | ENRICHED | `WRK_FSS_VAL_S2_ENRICHED` | Standardised names + blank-name flag, current deactivation status, cross-reference state |
| 30 | ROUTED | `WRK_FSS_VAL_S3_ROUTED` | Invalid-name / deactivation / reactivation groups, exception details, first-row-per-exception-key flag |
| 50 | PUBLISH | — | 4 INSERTs in one transaction |

Publish targets: `EXC_STG_BAD_REC_MEMB` (invalid names),
`STG_FSS_PTY_INACTIVE_LOG` (deactivations),
`STG_FSS_PTY_INACTIVE_STS` (new deactivation statuses, reactivation
statuses).

## 2. m_Tgt_C_S_FSS_Pty

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty(P_PTY_BO_CLASS_CD_MEMBER DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER DEFAULT 'Member', P_JOB_RUN_ID)`
Original parameters in order: `P_PTY_BO_CLASS_CD_MEMBER`,
`P_RLE_BO_CLASS_CD_MEMBER`; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_PTY_S1_SRC` | Source clients, deactivated parties removed |
| 20 | DQ_CHECKS | `WRK_FSS_PTY_S2_DQ` | Name standardisation, gender, birth date, ethnicity, race, language, suffix checks |
| 30 | DQ2_EXCEPTIONS | `WRK_FSS_PTY_S3_DQ2` | Standardised values with exception codes / descriptions / types resolved |
| 40 | ROUTED | `WRK_FSS_PTY_S4_ROUTED` | Party / role keys, exception groups, insert-only guards |
| 50 | PUBLISH | — | 8 INSERTs in one transaction |

Publish targets: `C_S_FSS_PTY`, `C_S_FSS_PTY_RLE`,
`EXC_STG_BAD_REC_MEMB` (gender, birth-date, ethnicity, race, language,
suffix exceptions).

## 3. m_Tgt_C_S_FSS_Pty_Addr

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr(P_MEMBER_HIERARCHY_CODE DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD DEFAULT 'Member Addr', P_JOB_RUN_ID)`
Original parameters in order: `P_MEMBER_HIERARCHY_CODE`,
`P_MEMBER_HM_REL_TP_CD`; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_ADDR_S1_SRC` | Source addresses with address key built, deactivated parties removed |
| 20 | VALIDATED | `WRK_FSS_ADDR_S2_VALIDATED` | Address validation result attached, state code translated |
| 30 | FLAT | `WRK_FSS_ADDR_S3_FLAT` | Validation result flattened into plain columns, match-code description resolved |
| 40 | SCORED | `WRK_FSS_ADDR_S4_SCORED` | Good / exception score, held address lines, exception details, insert-only guards |
| 50 | PUBLISH | — | 3 INSERTs in one transaction |

Publish targets: `DQM_ADDRESS` (every active address),
`C_S_FSS_PTY_RLE_ADDR` (good addresses),
`EXC_STG_BAD_REC_MEMB` (exception addresses).

## 4. m_Tgt_C_S_FSS_Pty_Rle_Alt_Id

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | SRC_KEYED | `WRK_FSS_ALT_S1_SRC` | Keyed source rows: role key, alternate-ID type ('022' / '023') and key, last active registrations |
| 20 | FILTERED | `WRK_FSS_ALT_S2_FILTERED` | Deactivated parties and existing keys removed, first row per key kept |
| 50 | PUBLISH | — | 1 INSERT in one transaction |

Publish target: `C_S_FSS_PTY_RLE_ALT_ID`.

Flagged split note: this mapping has no CTE chain in the original —
its whole logic is one keyed query plus filters — so it stages into
just two work tables before publish. That is the closest sensible
split; nothing was merged into a single step to hide it. Publish keeps
step number 50 for consistency with the other mappings.

## 5. m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_PHN_S1_SRC` | Source rows with role, e-mail and phone keys built, deactivated parties removed |
| 20 | DQ_VALIDATE | `WRK_FSS_PHN_S2_DQ` | E-mail validation, phone standardisation, extension check |
| 30 | CHECKED | `WRK_FSS_PHN_S3_CHECKED` | Standardised e-mail, phone exception code (area-code lookup), standardised extension + its exception code |
| 40 | ROUTED | `WRK_FSS_PHN_S4_ROUTED` | Exception details, good / bad groups for e-mail, phone and extension, insert-only guards |
| 50 | PUBLISH | — | 5 INSERTs in one transaction |

Publish targets: `C_S_FSS_PTY_RLE_EADDR` (valid e-mails),
`C_S_FSS_PTY_RLE_PHN` (valid phones),
`EXC_STG_BAD_REC_MEMB` (bad e-mails, bad phones, bad extensions).

## 6. m_Tgt_C_S_FSS_Pty_Rle_Rel

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_REL_S1_SRC` | Source relationships, both parties off the deactivation list |
| 20 | CODED | `WRK_FSS_REL_S2_CODED` | Relationship code built (missing code defaults to CAREGIVER), direction code type, output gender, both role keys |
| 30 | TYPED | `WRK_FSS_REL_S3_TYPED` | Relationship code translated through the code-value lookup |
| 40 | FINAL | `WRK_FSS_REL_S4_FINAL` | Relationship key, constants, exception details, insert-only guards |
| 50 | PUBLISH | — | 2 INSERTs in one transaction |

Publish targets: `C_S_FSS_PTY_RLE_REL` (valid relationships),
`EXC_STG_BAD_REC_MEMB` (untranslated relationships).

## Runner

- `runners/sp_etl_run_wf_FSS_Stage_Load.sql` —
  `sp_etl_run_wf_FSS_Stage_Load(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`:
  workflow-level `job_begin`, the 6 mappings in the order above with
  each mapping's original defaults in full followed by the run id,
  then `job_finish`; on failure `job_fail` + `RAISE`. It writes no
  target rows and drops no work tables itself.
- `runners/run_wf_FSS_Stage_Load.sql` — SnowSQL script with
  `!set exit_on_error=true` and a single `CALL` to the runner.

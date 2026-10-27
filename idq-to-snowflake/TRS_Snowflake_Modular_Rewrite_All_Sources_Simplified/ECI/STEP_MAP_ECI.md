# STEP_MAP_ECI — wf_ECI_Stage_Load (modular rewrite, simplified v2 style)

Install: database `MDM_ETL_ECI`, schema `ECI_ETL_WRK`. All table names in
the procedures are unqualified. Every procedure appends `P_JOB_RUN_ID
VARCHAR DEFAULT NULL` after its original parameters, in the same order.
Every procedure starts with step 5 `CLEANUP_PREVIOUS_RUN` (bare
`DROP TABLE IF EXISTS` for that mapping's work tables only, no checkpoint
call for drops), writes a checkpoint per staged step, publishes in the
only transaction, and leaves its work tables standing afterwards.
Restart is mapping-level only: a new run cleans up at step 5 and runs
every step from scratch. No `P_RESUME_STEP`, no resume guards, no
end-of-run drops, no cleanup procedure. All loads are insert-only
(no `TRUNCATE` / `DELETE` of targets), exactly as in the originals.

Runner order (identical to the original `run_wf_ECI_Stage_Load.sql`):
Validation, Pty, Reactivation_D_Family_Addr, Reactivation_D_Family_Phn,
Reactivation_D_Medicaid, Pty_Rle_Alt_Id, Pty_Rle_Phn_And_EAddr, Pty_Addr,
Pty_Rle_Rel. Runner: `sp_etl_run_wf_ECI_Stage_Load` (see `runners/`).

## 1. m_Tgt_C_S_ECI_Pty_Validation — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation`

Checks every child/family delta party and maintains the deactivation
list every later mapping filters on. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | SRC_DELTA_PARTIES | `WRK_ECI_VAL_S10_SRC` | Child + family delta rows, party key, 10-character full name |
| 20 | ENRICHED_STD_NAMES | `WRK_ECI_VAL_S20_ENRICHED` | Status / hub / duplicate / family lookups + standardised names |
| 30 | ROUTED_GROUPS | `WRK_ECI_VAL_S30_ROUTED` | Blank-name / deactivation / reactivation groups, exception descriptions, `uq_exc_name` flag |
| 40 | PUBLISH | — (transaction) | 4 inserts, original order |

Publish targets: `EXC_STG_BAD_REC_MEMB` (blank-name exceptions),
`STG_ECI_PTY_INACTIVE_LOG` (deactivation + reactivation log rows),
`STG_ECI_PTY_INACTIVE_STS` (new deactivation status rows only).

Preserved quirks: full name cut at 10 characters; no prefix/suffix passed
to name standardisation; the IDQ delete of the inactive-status table is
not performed; exception description/type from the exception catalogue
(NULL when unconfigured).

## 2. m_Tgt_C_S_ECI_Pty — `sp_snow_main_m_Tgt_C_S_ECI_Pty`

Loads active child/family parties and logs demographic exceptions.
Original parameters: `P_PTY_BO_CLASS_CD_MEMBER` ('Indv'),
`P_RLE_BO_CLASS_CD_MEMBER` ('Member').

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 5 work tables below |
| 10 | SRC_DELTA_PARTIES | `WRK_ECI_PTY_S10_SRC` | Child + family delta rows, party key, party type, source full name |
| 20 | ACTIVE_PARTIES | `WRK_ECI_PTY_S20_ACTIVE` | Active parties only (no deactivation status) |
| 30 | DQ_RULES | `WRK_ECI_PTY_S30_DQ` | Name standardisation, gender, birth date, ethnicity, race indicators, language |
| 40 | DQ_EXCEPTIONS_RESOLVED | `WRK_ECI_PTY_S40_DQ2` | Standardised fields unpacked, every exception code/description/type resolved |
| 50 | ROUTED_READY | `WRK_ECI_PTY_S50_READY` | Router groups, party/role keys, insert-only guards |
| 60 | PUBLISH | — (transaction) | 7 inserts, original order |

Publish targets: `C_S_ECI_PTY`, `C_S_ECI_PTY_RLE`, `EXC_STG_BAD_REC_MEMB`
(gender, birth date, ethnicity, race, language — in that order).

Preserved quirks: exception rows carry the literal mapping name
`m_Tgt_C_S_ECI_Pty_OnGoing`; the stored filter on five child ids is
ignored (not part of the custom query); the stored inactive-filter
comment means active parties are kept; `VERSION_SEQ` = 1; duplicate rank
and demographics MD5 are not computed (IDQ does not write them);
party `PERIOD_START_DATE` = source `DATE_MODIFIED`, role
`PERIOD_START_DATE` = `DATE_CREATED`; an exception never rejects a party
(a future birth date loads as NULL); ethnicity/race/language exceptions
are child rows only.

## 3. m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr — `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`

Moves the latest history address row of each reactivated family into the
delta table. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | LATEST_HISTORY_ROWS | `WRK_ECI_RFA_S10_LATEST` | Latest history row per address of reactivated families |
| 20 | KEEP_NEW_ONLY | `WRK_ECI_RFA_S20_KEEPNEW` | Latest rows not already in the delta table |
| 30 | PUBLISH | — (transaction) | 1 insert |

Publish target: `STG_ECI_D_FAMILY_ADDRESS`.

FLAGGED SPLIT: the original is a single INSERT with no CTE chain, so
this is the closest sensible split (latest rows, then keep-new filter,
then publish), not a CTE-boundary split. The keep-new filter is
evaluated in step 20, before any insert, so it still sees the delta
table as it was before the run, as in the original.

## 4. m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn — `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`

Moves the latest history phone row of each reactivated family into the
delta table. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | LATEST_HISTORY_ROWS | `WRK_ECI_RFP_S10_LATEST` | Latest history row per phone record of reactivated families |
| 20 | KEEP_NEW_ONLY | `WRK_ECI_RFP_S20_KEEPNEW` | Latest rows not already in the delta table |
| 30 | PUBLISH | — (transaction) | 1 insert |

Publish target: `STG_ECI_D_FAMILY_PHONE`.

FLAGGED SPLIT: as §3 — the original is a single INSERT with no CTE
chain; closest sensible split (latest rows, keep-new filter, publish).

## 5. m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid — `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`

Moves the latest history Medicaid row of each reactivated child into the
delta table. Original parameters: `P_TEST_LOOKUP_RESULT` ('N').

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | LATEST_HISTORY_ROWS | `WRK_ECI_RFM_S10_LATEST` | Latest history row per Medicaid record of reactivated children, plus the delta-table lookup key (`LKP_ID_MEDICAID`) |
| 20 | KEEP_NEW_ONLY | `WRK_ECI_RFM_S20_KEEPNEW` | Rows passing the keep-new filter, one row per Medicaid id |
| 30 | PUBLISH | — (transaction) | 1 insert |

Publish target: `STG_ECI_D_MEDICAID`.

FLAGGED SPLIT: as §3 — the original is a single INSERT with no CTE
chain; closest sensible split (latest rows + lookup, keep-new filter +
rank, publish).

PRESERVED DEFECT: with the default `P_TEST_LOOKUP_RESULT` = 'N' the
keep-new filter tests the source `ID_MEDICAID`, which is never NULL, so
the mapping writes no rows, exactly as IDQ does. Passing 'Y' tests the
lookup result instead (records not yet in the delta table). The runner
passes 'N' (the original default).

## 6. m_Tgt_C_S_ECI_Pty_Rle_Alt_Id — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`

Loads alternate ids (child ECI id 018, child SSN 004, Medicaid number
002, family ECI id 019); invalid SSNs/Medicaid ids are only logged.
Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ALT_IDS | `WRK_ECI_ALT_S10_SRC` | Four alternate-id branches |
| 20 | ACTIVE_ALT_IDS | `WRK_ECI_ALT_S20_ACTIVE` | Ids of active parties only |
| 30 | VALIDATED_ROUTED | `WRK_ECI_ALT_S30_ROUTED` | SSN/Medicaid validation + valid / SSN-exception / Medicaid-exception groups |
| 40 | READY_TO_PUBLISH | `WRK_ECI_ALT_S40_READY` | Publish-ready rows with insert-only guards |
| 50 | PUBLISH | — (transaction) | 3 inserts, original order |

Publish targets: `C_S_ECI_PTY_RLE_ALT_ID`, `EXC_STG_BAD_REC_MEMB`
(SSN, then Medicaid).

Preserved quirks: the id written is the source value (standardised
values are validation-only); the SSN exception row has NULL `RUN_DATE`
and the looked-up exception code (NULL when unconfigured), so an
invalid SSN is logged only once, ever (reproduced via the
`uq_ssn_exc` guard); `VERSION_SEQ` = 1; `PERIOD_START_DATE` = source
`DATE_CREATED`.

## 7. m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`

Loads phones and e-mails of the ECI parties. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 5 work tables below |
| 10 | SRC_PHN_EADDR | `WRK_ECI_PHN_S10_SRC` | Phone/e-mail source rows with party, role and record keys |
| 20 | ACTIVE_PHN_EADDR | `WRK_ECI_PHN_S20_ACTIVE` | Rows of active parties only |
| 30 | DQ_CLEAN_VALIDATE | `WRK_ECI_PHN_S30_DQ` | Cleaned phones (7-digit numbers get '000' prefixed), validated e-mails |
| 40 | ROUTED_GROUPS | `WRK_ECI_PHN_S40_ROUTED` | Area-code lookup, phone exception codes, good/bad phone and e-mail groups |
| 50 | READY_TO_PUBLISH | `WRK_ECI_PHN_S50_READY` | Publish-ready rows with insert-only guards |
| 60 | PUBLISH | — (transaction) | 4 inserts, original order |

Publish targets: `C_S_ECI_PTY_RLE_PHN`, `EXC_STG_BAD_REC_MEMB`
(bad phones), `C_S_ECI_PTY_RLE_EADDR`, `EXC_STG_BAD_REC_MEMB`
(bad e-mails).

Preserved quirks: a `Missing_AreaCode` phone is both loaded AND logged;
an e-mail whose `Invalid_Email` code is unconfigured is treated as
valid and loaded (router tests the looked-up code); the phone exception
`SRC_SYS_ID_1` is NULL and its type is the literal 'Bad Value';
`VERSION_SEQ` = '1'; e-mail `PERIOD_REFERENCE_TIME` is NULL.

Framework note: step 40 uses `fn_snow_helper44_common` (area-code
reference) exactly as the original does. That helper's body references
`RDM.REF_PHN_AREA_CD` in the supplied common file, so the install must
make that reference resolve (e.g. a COMMON-qualified reference, as was
noted for the TRS install) — this rewrite does not change the helper
call or invent a replacement.

## 8. m_Tgt_C_S_ECI_Pty_Addr — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr`

Validates addresses and loads the good ones. Original parameters:
`P_MEMBER_HIERARCHY_CODE` ('Member'), `P_MEMBER_HM_REL_TP_CD`
('Member Addr').

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 5 work tables below |
| 10 | SRC_ADDRESSES | `WRK_ECI_ADR_S10_SRC` | Address source rows, party/role keys, translated address type |
| 20 | KEYED_ACTIVE | `WRK_ECI_ADR_S20_KEYED` | Record keys, active addresses only |
| 30 | ADDR_VALIDATION | `WRK_ECI_ADR_S30_VALIDATED` | Address validation result (pass-through stand-in) + state lookup |
| 40 | FLAT_VALIDATION | `WRK_ECI_ADR_S40_FLAT` | Validation result unpacked + match-code description |
| 50 | SCORED_READY | `WRK_ECI_ADR_S50_READY` | Score, issue description, held lines, insert-only guards |
| 60 | PUBLISH | — (transaction) | 3 inserts, original order |

Publish targets: `DQM_ADDRESS` (every active address, first),
`C_S_ECI_PTY_RLE_ADDR` (score '100'), `EXC_STG_BAD_REC_MEMB`
(score '40').

Preserved quirks: the validator is the pass-through stand-in, so every
address with a known type scores '100'; exception rows use the
hard-coded description 'Invalid Address per Address Doctor' and type
'Bad Value' (no catalogue lookup); unfed ports are NULL (including
`FLR_NUM`, `EFF_END_DT`, exception `PERIOD_END_DATE`);
`PERIOD_REFERENCE_TIME` is NULL; `VERSION_SEQ` = 1;
`PERIOD_START_DATE` / `EFF_STRT_DT` = source `LAST_UPDATE_DATE`.

## 9. m_Tgt_C_S_ECI_Pty_Rle_Rel — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel`

Loads family-to-child relationships in both directions. Original
parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_BOTH_DIRECTIONS | `WRK_ECI_REL_S10_SRC` | Family rows doubled (one per direction) |
| 20 | KEYED_BOTH_ACTIVE | `WRK_ECI_REL_S20_KEYED` | Child/family party keys, both parties active |
| 30 | CODED_TRANSLATED | `WRK_ECI_REL_S30_TYPED` | Relationship code built and translated (NULL when untranslated) |
| 40 | READY_TO_PUBLISH | `WRK_ECI_REL_S40_READY` | Relationship keys, exception details, insert-only guards |
| 50 | PUBLISH | — (transaction) | 2 inserts, original order |

Publish targets: `C_S_ECI_PTY_RLE_REL` (translated codes),
`EXC_STG_BAD_REC_MEMB` (untranslated codes).

Preserved quirks: the code translation is a direct `LOOKUP_CODE_VALUE`
lookup (REL_TP / INVERSE_REL, source ECI), not a helper, as in the
original; the exception code is the catalogue-lookup result (NULL when
`Invalid_Relationship` is unconfigured); exception `SRC_SYS_ID_3` ends
in '|' (master code NULL); `VERSION_SEQ` = 1; `PERIOD_START_DATE` =
family `DATE_CREATED`; `CREATE_DATE` = `DATE_MODIFIED`.

## Work-table inventory (all TRANSIENT, all in ECI_ETL_WRK)

- Validation: `WRK_ECI_VAL_S10_SRC`, `WRK_ECI_VAL_S20_ENRICHED`, `WRK_ECI_VAL_S30_ROUTED`
- Pty: `WRK_ECI_PTY_S10_SRC`, `WRK_ECI_PTY_S20_ACTIVE`, `WRK_ECI_PTY_S30_DQ`, `WRK_ECI_PTY_S40_DQ2`, `WRK_ECI_PTY_S50_READY`
- Reactivation Addr: `WRK_ECI_RFA_S10_LATEST`, `WRK_ECI_RFA_S20_KEEPNEW`
- Reactivation Phn: `WRK_ECI_RFP_S10_LATEST`, `WRK_ECI_RFP_S20_KEEPNEW`
- Reactivation Medicaid: `WRK_ECI_RFM_S10_LATEST`, `WRK_ECI_RFM_S20_KEEPNEW`
- Alt_Id: `WRK_ECI_ALT_S10_SRC`, `WRK_ECI_ALT_S20_ACTIVE`, `WRK_ECI_ALT_S30_ROUTED`, `WRK_ECI_ALT_S40_READY`
- Phn_And_EAddr: `WRK_ECI_PHN_S10_SRC`, `WRK_ECI_PHN_S20_ACTIVE`, `WRK_ECI_PHN_S30_DQ`, `WRK_ECI_PHN_S40_ROUTED`, `WRK_ECI_PHN_S50_READY`
- Addr: `WRK_ECI_ADR_S10_SRC`, `WRK_ECI_ADR_S20_KEYED`, `WRK_ECI_ADR_S30_VALIDATED`, `WRK_ECI_ADR_S40_FLAT`, `WRK_ECI_ADR_S50_READY`
- Rel: `WRK_ECI_REL_S10_SRC`, `WRK_ECI_REL_S20_KEYED`, `WRK_ECI_REL_S30_TYPED`, `WRK_ECI_REL_S40_READY`

Total: 32 work tables (3 + 5 + 2 + 2 + 2 + 4 + 5 + 5 + 4). No work table
is shared between mappings; each mapping's step 5 drops only its own
tables (verified: 32 step-5 drops = 32 work tables created).

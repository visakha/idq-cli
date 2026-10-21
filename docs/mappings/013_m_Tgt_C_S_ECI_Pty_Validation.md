# 013 m_Tgt_C_S_ECI_Pty_Validation

| | |
|---|---|
| Source system | ECI, workflow `wf_ECI_Stage_Load`, first mapping |
| Sub-domain | Demographics (party activation status) |
| Sources | `STG_ECI_D_CHILD`, `STG_ECI_D_FAMILY`, `C_B_PTY_XREF`, `STG_ECI_PTY_INACTIVE_STS`, `V_ECI_ETL_LU_DUP_CASES`, `V_ECI_ETL_LU_FAMILY_VALIDATION` |
| Targets | `STG_ECI_PTY_INACTIVE_STS`, `STG_ECI_PTY_INACTIVE_LOG`, `EXC_STG_BAD_REC_MEMB` |
| Java | `com.idq.cli.source.eci.etlmap.svc.EciPartyValidationService` |

## Business purpose

Decides, before anything is loaded, which ECI children and family members are inactive. Every later ECI mapping
skips a party whose source key has a deactivation status. A party is deactivated when its name is incomplete, when
all its cases are duplicates, or when its family is flagged by the family validation view; it is reactivated when
it is complete again.

## Process

```mermaid
flowchart LR
  C["children"] --> U["union, party key<br/>id (family: idF)"]
  F["family members"] --> U
  U --> N["name standardization"]
  X["hub state (C_B_PTY_XREF)"] --> R{"router"}
  S["current status"] --> R
  D["duplicate cases view"] --> R
  V["family validation view"] --> R
  N --> R
  R -->|name missing,<br/>family active| E["Missing name exception"]
  R -->|name missing, duplicate<br/>or family inactive| DA["log Deactivation,<br/>new status H / D / P"]
  R -->|has status, complete,<br/>not duplicate, family ok| RA["log Reactivation,<br/>delete status"]
```

## IdqMapInitQuery

### ECI-013 Children and family members

Children and family members with names, birth date and audit dates. No stale filter found.

Entity: `EciQueryRows.PartyName` - named query: `EciChildDeltaRepository#fetchPartyNames`.

```sql
SELECT 'ECI_CHILD' AS source_table, id_child AS id, first_name, last_name, middle_initial, dob,
       date_created, date_modified, modified_by, created_by, load_date
FROM stg_eci_d_child
UNION ALL
SELECT 'ECI_FAMILY', id_family, first_name, last_name, middle_initial, dob, date_created, date_modified,
       modified_by, created_by, load_date
FROM stg_eci_d_family
```

### Lookups

`Lookup_STG_ECI_PTY_INACTIVE_STS` - `EciInactiveStatusRepository#fetchInactiveStatuses`:

```sql
SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_eci_pty_inactive_sts
WHERE rowid_system = 'ECI' AND deactivation_sts IS NOT NULL
```

`Lookup_C_B_PTY_XREF` (hub state of the party in MDM) - `EciPartyXrefRepository#fetchHubStates`:

```sql
SELECT pkey_src_object AS lookup_key, hub_state_ind AS lookup_value FROM c_b_pty_xref
WHERE rowid_system = 'ECI'
```

`Lookup_V_ECI_ETL_LU_DUP_CASES` - `EciDupCasesViewRepository#fetchDuplicateCases`:

```sql
SELECT source_table || '|' || id AS lookup_key, TO_CHAR(id) AS lookup_value FROM v_eci_etl_lu_dup_cases
```

`Lookup_V_ECI_ETL_LU_FAMILY_VALIDATION` - `EciFamilyValidationViewRepository#fetchFamilyValidations`:

```sql
SELECT source_table, id_family, fam_name_status, fam_phone_and_address_sts, fam_inactive_sts
FROM v_eci_etl_lu_family_validation
```

The two `V_ECI_ETL_*` views and `C_B_PTY_XREF` are not part of the exports; see `db/missing-objects.sql`.

<!-- lookups:begin -->
## Lookups

Connected lookups, grouped by the transformation that feeds their input ports. In a lookup condition the
left side is the lookup table column and the right side is the lookup input port. Output ports are the
returned table columns (or input ports passed through) and the downstream port each one feeds.

### Fed by `Exp_Invalid_PTY_NM` (Expression)

| Lookup | Table | Condition | Input ports | Output ports |
|---|---|---|---|---|
| `Lkp_EXC_LOOKUP_CODE_VALUE_Name` | `EXC_LOOKUP_CODE_VALUE` (STAGING)<br>multiple match: default | `EXCEPTION_CODE = Exception_Code_Name` | `Exception_Code_Name` &larr; `Exception_Code_Name` | `EXCEPTION_DESC` &rarr; `Write_Invalid_Party_Name.EXCEPTION_DESC` (Target)<br>`EXCEPTION_TYPE` &rarr; `Write_Invalid_Party_Name.EXCEPTION_TYPE` (Target) |

### Fed by `Exp_ECI_Data_Load` (Expression)

| Lookup | Table | Condition | Input ports | Output ports |
|---|---|---|---|---|
| `Lookup_STG_ECI_PTY_INACTIVE_STS` | `STG_ECI_PTY_INACTIVE_STS` (STAGING)<br>multiple match: default | `SRC_KEY = PKEY_SRC_OBJECT AND ROWID_SYSTEM = SRC_SYSTEM` | `SRC_SYSTEM` &larr; `SRC_SYSTEM`<br>`PKEY_SRC_OBJECT` &larr; `PKEY_SRC_OBJECT` | `DEACTIVATION_STS` &rarr; `Exp_Consolidate_Exceptions.DEACTIVATION_STS` (Expression) |
| `Lookup_C_B_PTY_XREF` | `C_B_PTY_XREF` (HHS_MDM_ORS)<br>filter: `"C_B_PTY_XREF"."ROWID_SYSTEM" = 'ECI'`<br>multiple match: default | `PKEY_SRC_OBJECT = PKEY_SRC_OBJECT1` | `SRC_SYSTEM` &larr; `SRC_SYSTEM`<br>`PKEY_SRC_OBJECT1` &larr; `PKEY_SRC_OBJECT` | `HUB_STATE_IND` &rarr; `Exp_Consolidate_Exceptions.HUB_STATE_IND` (Expression) |
| `Lookup_V_ECI_ETL_LU_FAMILY_VALIDATION` | `V_ECI_ETL_LU_FAMILY_VALIDATION` (STAGING)<br>multiple match: any row | `SOURCE_TABLE = SOURCE_TABLE1 AND ID_FAMILY = ID` | `SOURCE_TABLE1` &larr; `SOURCE_TABLE`<br>`ID` &larr; `ID` | `FAM_NAME_STATUS` &rarr; `Exp_Consolidate_Exceptions.FAM_NAME_STATUS` (Expression)<br>`FAM_PHONE_AND_ADDRESS_STS` &rarr; `Exp_Consolidate_Exceptions.FAM_PHONE_AND_ADDRESS_STS` (Expression)<br>`FAM_INACTIVE_STS` &rarr; `Exp_Consolidate_Exceptions.FAM_INACTIVE_STATUS` (Expression) |
| `Lookup_V_ECI_ETL_LU_DUP_CASES` | `V_ECI_ETL_LU_DUP_CASES` (STAGING)<br>multiple match: any row | `SOURCE_TABLE = SOURCE_TABLE1 AND ID = ID1` | `SOURCE_TABLE1` &larr; `SOURCE_TABLE`<br>`ID1` &larr; `ID` | `ID` &rarr; `Exp_Consolidate_Exceptions.OMIT_ID` (Expression) |

Lookups inside the mapplets / rules this mapping calls are listed in
[000](000_mapplets.md#lookups-inside-mapplets-and-rules): `mplt_Name_Standardization_Indv_Member`.

<!-- lookups:end -->

## Business rules

1. Party key = id left-padded to 10 digits, family members suffixed `F`.
2. Family inactive = any of the family name, phone-and-address or inactive statuses is set.
3. `Invalid_Party_Name`: standardized first or last name missing **and** family not inactive ->
   `Missing_First_Name` / `Missing_Last_Name`.
4. `Deactivation`: name missing, or all cases duplicate (id in the duplicate-cases view), or family inactive. A log
   row is written; if the party has no status yet a status row is added: `H` (no MDM cross-reference),
   `D` (hub state -1) or `P` (pending).
5. `Reactivation`: the party has a status and both names, is not a duplicate and the family is not inactive. A log
   row is written and the status row deleted (`DD_DELETE`).

## PKEY formulation

No `C_S_*` target. Status / log key `SRC_KEY` = party key, `ROWID_SYSTEM` = `ECI`. Unit test:
`EciPkeyTest#m_Tgt_C_S_ECI_Pty_Validation_pkey_test` (status keys `0000000042` and `0000000007F`).

## Java implementation

* `EciPartyValidationService.transform` + `InactiveStatus.Changes` (deactivate / reactivate) + `InactiveStatus.output`
  (log append, status delete by key, status append). Entities `EciSources.InactiveStatus`,
  `EciSources.InactiveLog`.
* Source entities (raw source tables, captured in the `adhoc_runs_*` audit reports): `EciSources.ChildDelta`
  (`STG_ECI_D_CHILD`), `EciSources.FamilyDelta` (`STG_ECI_D_FAMILY`), `MdmBaseTables.PartyXref` (`C_B_PTY_XREF`),
  `EciSources.InactiveStatus` (`STG_ECI_PTY_INACTIVE_STS`), `EciSources.EtlLuDupCases` (`V_ECI_ETL_LU_DUP_CASES`),
  `EciSources.EtlLuFamilyValidation` (`V_ECI_ETL_LU_FAMILY_VALIDATION`).

# 023 m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr

| | |
|---|---|
| Source system | FSS |
| Sub-domain | Phone-email |
| Sources | `V_FSS_ETL_SRC`, `STG_FSS_PTY_INACTIVE_STS` |
| Targets | `C_S_FSS_PTY_RLE_PHN`, `C_S_FSS_PTY_RLE_EADDR`, `EXC_STG_BAD_REC_MEMB` |
| Java | `com.idq.cli.source.fss.etlmap.svc.FssPhoneEmailService` |

## Business purpose

Publishes the registration phone (with extension) and e-mail of active FSS clients.

```mermaid
flowchart LR
  V["V_FSS_ETL_SRC<br/>not deleted"] --> A["active clients"]
  A --> P["phone rule (FSS, 001)<br/>+ extension rule"]
  A --> M["email rule"]
  P -->|valid| PT["C_S_FSS_PTY_RLE_PHN"]
  P -->|invalid phone| E["Rejected Record"]
  P -->|invalid extension| E2["Bad Value (extension)"]
  M -->|valid| MT["C_S_FSS_PTY_RLE_EADDR"]
  M -->|invalid| E
```

## IdqMapInitQuery

### FSS-023 Registration phone and e-mail

Client view rows whose capture action is not delete. No stale filter.

Entity: `FssQueryRows.ClientContact` - named query: `FssEtlSrcViewRepository#fetchClientContacts`.

```sql
SELECT id_registration_client, dt_last_update, nbr_phone, addr_email, source_type, pty_src_key,
       nbr_phone_ext
FROM v_fss_etl_src
WHERE dtl__capxaction <> 'D'
```

<!-- lookups:begin -->
## Lookups

Connected lookups, grouped by the transformation that feeds their input ports. In a lookup condition the
left side is the lookup table column and the right side is the lookup input port. Output ports are the
returned table columns (or input ports passed through) and the downstream port each one feeds.

### Fed by `exp_Stage_Source_Attributes` (Expression)

| Lookup | Table | Condition | Input ports | Output ports |
|---|---|---|---|---|
| `Lookup_STG_FSS_PTY_INACTIVE_STS` | `STG_FSS_PTY_INACTIVE_STS` (STAGING)<br>multiple match: any row | `SRC_KEY = PTY_SRC_KEY AND ROWID_SYSTEM = SRC_SYS` | `PTY_SRC_KEY` &larr; `PTY_SRC_KEY`<br>`SRC_SYS` &larr; `SRC_SYS` | `DEACTIVATION_STS` &rarr; `fil_deactivated_status.DEACTIVATION_STS` (Filter) |

Lookups inside the mapplets / rules this mapping calls are listed in
[000](000_mapplets.md#lookups-inside-mapplets-and-rules): `rule_Phone_Extension_Std`, `rule_Phone_Std`, `rule_email_validation_v01`.

<!-- lookups:end -->

## Business rules

1. Phone (when present): type `Telephone`, usage `001`, preference `Primary`; `rule_Phone_Std` with source `FSS`.
   Valid phones are loaded; invalid ones go to the exception queue with type `Rejected Record`.
2. Extension: `rule_Phone_Extension_Std`; an invalid extension raises its own exception (`Bad Value`, attribute
   `Main Phone Ext`) and is loaded empty.
3. E-mail (when present): rejected only when the exception code is configured; loaded with `001`, `Active`, `Y`.

## PKEY formulation

| Target | PKEY_SRC_OBJECT | Example |
|---|---|---|
| `C_S_FSS_PTY_RLE_PHN` | `<party>|Member|Telephone|001|LPAD(registration client,10)|TRIM(phone as reported)` | `0000000011|Member|Telephone|001|0000000600|512-555-1234` |
| `C_S_FSS_PTY_RLE_EADDR` | `<party>|Member|001|LPAD(registration client,10)|TRIM(e-mail as reported)` | `0000000011|Member|001|0000000600|Ann@Example.org` |

Unit test: `FssPkeyTest#m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr_pkey_test`.

## Java implementation

* `FssPhoneEmailService.phoneKey`, `emailKey`, `transform`; `ContactRules.phone`, `phoneExtension`, `email`; entities
  `FssTargets.Phone` (`PHN_NUM_EXT`), `FssTargets.Email`.
* Source entities (raw source tables, captured in the `adhoc_runs_*` audit reports): `FssSources.EtlSrc`
  (`V_FSS_ETL_SRC`), `FssSources.InactiveStatus` (`STG_FSS_PTY_INACTIVE_STS`).

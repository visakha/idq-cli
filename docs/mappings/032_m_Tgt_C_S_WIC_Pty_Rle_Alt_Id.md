# 032 m_Tgt_C_S_WIC_Pty_Rle_Alt_Id

| | |
|---|---|
| Source system | WIC |
| Sub-domain | Alternate-ID |
| Sources | `V_WIC_ETL_SRC`, `STG_WIC_PTY_INACTIVE_STS` |
| Targets | `C_S_WIC_PTY_RLE_ALT_ID` |
| Java | `com.idq.cli.source.wic.etlmap.svc.WicAlternateIdService` |

## Business purpose

Publishes the WIC id as alternate identifier: `020` for clients, `021` for family members.

```mermaid
flowchart LR
  V["V_WIC_ETL_SRC"] --> A["active parties"]
  A --> T["type 020 CLIENT / 021 other,<br/>value LPAD(id,12)"]
  T --> O["C_S_WIC_PTY_RLE_ALT_ID"]
```

## IdqMapInitQuery

### WIC-032 Client and family ids

All rows of the WIC view. No filter in IDQ.

Entity: `WicQueryRows.ClientIdentifier` - named query: `WicEtlSrcViewRepository#fetchClientIdentifiers`.

```sql
SELECT id, datekey, pty_src_key, source_table FROM v_wic_etl_src
```

<!-- lookups:begin -->
## Lookups

Connected lookups, grouped by the transformation that feeds their input ports. In a lookup condition the
left side is the lookup table column and the right side is the lookup input port. Output ports are the
returned table columns (or input ports passed through) and the downstream port each one feeds.

### Fed by `exp_ECI_Pty_Rle_Alt_Id` (Expression)

| Lookup | Table | Condition | Input ports | Output ports |
|---|---|---|---|---|
| `Lookup_STG_WIC_PTY_INACTIVE_STS` | `STG_WIC_PTY_INACTIVE_STS` (STAGING)<br>multiple match: any row | `SRC_KEY = PTY_SRC_KEY AND ROWID_SYSTEM = SRC_SYSTEM` | `PTY_SRC_KEY` &larr; `PTY_SRC_KEY`<br>`SRC_SYSTEM` &larr; `SRC_SYSTEM` | `DEACTIVATION_STS` &rarr; `Filter.DEACTIVATION_STS` (Filter) |

<!-- lookups:end -->

## Business rules

1. Type `020` when `SOURCE_TABLE = 'CLIENT'`, else `021`; value `LPAD(ID,12,'0')`; status `Issued`.
2. `SRC_ROWID` = `id|type`; dates = `DATEKEY`.

## PKEY formulation

| Target | PKEY_SRC_OBJECT | Example |
|---|---|---|
| `C_S_WIC_PTY_RLE_ALT_ID` | `<PTY_SRC_KEY>|Member|<020/021>|LPAD(id,12)` | `0000000051|Member|020|000000000051` |

Unit test: `WicPkeyTest#m_Tgt_C_S_WIC_Pty_Rle_Alt_Id_pkey_test`.

## Java implementation

* `WicAlternateIdService.altIdType`, `pkey`, `transform`; entity `WicTargets.AlternateId`.
* Source entities (raw source tables, captured in the `adhoc_runs_*` audit reports): `WicSources.EtlSrc`
  (`V_WIC_ETL_SRC`), `WicSources.InactiveStatus` (`STG_WIC_PTY_INACTIVE_STS`).

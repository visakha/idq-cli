# 010 m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP

| | |
|---|---|
| Source system | TRS |
| Sub-domain | Role |
| Targets | `C_S_TRS_PTY_RLE_REL_PROV`, `EXC_STG_BAD_REC_MEMB` |
| Java | `com.idq.cli.source.trs.TrsPrimaryCareProvider` |

## Business purpose

Links a member to the primary care provider (or clinic) of their managed care enrolment. The provider is reported
by its TPI number and resolved to the provider party role that MDM already knows from the C21 provider source.

## Process

```mermaid
flowchart LR
  M["managed care with provider"] --> K["member key<br/>(MCI preferred)"]
  K --> N["numeric provider only"]
  N --> L["TPI -> newest active C21<br/>provider source key"]
  L --> X{"router"}
  X -->|begin after end| E1["Period_Start_Date_>_Period_End_Date"]
  X -->|member and provider found,<br/>dates ok| C["consolidate"]
  X -->|otherwise| E2["Invalid_Member / Invalid_PCP"]
  C --> T["C_S_TRS_PTY_RLE_REL_PROV"]
```

## IdqMapInitQuery

### TRS-010 Member primary care providers

* Managed care rows with a provider number for registered individuals, one source key per individual (MCI first).
* No stale filter (commented `ora_hash` sample and the old query are removed).

Entity: `TrsQueries.PrimaryCareProvider` - named query: `TrsQueries#fetchPrimaryCareProviders`.

```sql
WITH min_pk AS (
    SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
)
SELECT mc.indv_id, mc.history_seq, mc.mc_prog_code, mc.begin_dt, mc.create_dt, mc.provider_num,
       mc.end_dt, vm.pty_pk
FROM stg_trs_d_in_managed_care mc
JOIN min_pk vm ON mc.indv_id = vm.indv_id
WHERE mc.provider_num IS NOT NULL
ORDER BY mc.indv_id, mc.end_dt
```

### Lookup: provider TPI to provider source key

`Lookup_C_B_PTY_RLE_ALT_ID` (MDM base object, connection `HHS_MDM_ORS`): alternate ids of type `006` (TPI) whose
C21 cross-reference is active; when a provider was re-classed, the source key with the latest source update wins.
Entity `TrsQueries.ProviderKey` - named query `TrsQueries#fetchProviderKeys`.

```sql
WITH tpi_src_key AS (
    SELECT bo.alt_id_val, xr.pkey_src_object,
           ROW_NUMBER() OVER (PARTITION BY bo.alt_id_val ORDER BY xr.src_last_upd_dt DESC) src_key_rn
    FROM c_b_pty_rle_alt_id bo
    JOIN c_b_pty_rle_alt_id_xref xr ON bo.rowid_object = xr.rowid_object
    WHERE bo.alt_id_tp = '006' AND xr.rowid_system = 'C21' AND xr.hub_state_ind = 1
)
SELECT alt_id_val, pkey_src_object FROM tpi_src_key WHERE src_key_rn = 1
```

## Business rules

1. Only numeric provider numbers are kept (`IS_NUMBER`).
2. Provider role key = the provider source key up to its second `|` (`<tpi>|HCP` or `<tpi>|HCO`).
3. `REL_TYPE_CODE` = `Member PCO` when the source key contains `|HCO`, else `Member PCP`; `REL_TP` =
   `$PCP_REL_TP` = `100`; `HIERARCHY_CODE` = `Member`.
4. Router: begin after end -> `Period_Start_Date_>_Period_End_Date`; member and provider key present and dates in
   order (or open) -> loaded; anything else -> `Invalid_Member` (no member key) or `Invalid_PCP` (provider not
   found), attribute `Provider`.
5. Consolidation as in 009: one row per key.

## PKEY formulation

| Target | PKEY_SRC_OBJECT | Example |
|---|---|---|
| `C_S_TRS_PTY_RLE_REL_PROV` | `<member key>|Member|<provider role key>|100` | `123|Member|700000001|HCO|100` |

Unit test: `TrsPkeyTest#m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP_pkey_test`.

## Retired / not ported

* Timeline validation mapplet, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION` - MDM timeline.

## Java implementation

* `TrsPrimaryCareProvider.transform`, `providerRoleKey`, `pkey`; `Lookups(providerKeyByTpi)`;
  `Rows.currentSegmentPerKey`; entity `TrsTargets.ProviderRelationship`.
* Source entities (raw source tables, captured in the `adhoc_runs_*` audit reports): `TrsSources.DInManagedCare`
  (`STG_TRS_D_IN_MANAGED_CARE`), `TrsTargets.ValidMember` (`STG_TRS_VALID_MEMBERS`), `MdmBaseTables.PartyRoleAltId`
  (`C_B_PTY_RLE_ALT_ID`), `MdmBaseTables.PartyRoleAltIdXref` (`C_B_PTY_RLE_ALT_ID_XREF`).

# m_Tgt_C_S_FSS_Pty_Rle_Alt_Id

IDQ mapping &rarr; CDI **Mapping** `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`.

> MDM Stage Data Load for FSS Alternate ID from STAGING

## Summary

| IDQ transformation | CDI transformation | Count |
|---|---|---|
| ExpressionTx | Expression | 2 |
| FilterTx | Filter | 1 |
| LookupTx | Lookup | 1 |
| SourceTx | Source | 1 |
| TargetTx | Target | 1 |

Sources:

| Instance | Object | Connection |
|---|---|---|
| Read_V_FSS_ETL_SRC | `V_FSS_ETL_SRC` | STAGING |

Targets:

| Instance | Object | Connection |
|---|---|---|
| Write_C_S_FSS_PTY_RLE_ALT_ID | `C_S_FSS_PTY_RLE_ALT_ID` | HHS_MDM_ORS |

## Flow

```mermaid
flowchart LR
  n0["Read_V_FSS_ETL_SRC<br/><i>Source</i>"]
  n1["exp_FSS_Pty_Rle_Alt_Id<br/><i>Expression</i>"]
  n2["Lkp_STG_FSS_PTY_INACTIVE_STS<br/><i>Lookup</i>"]
  n3["Filter<br/><i>Filter</i>"]
  n4["Exp_STG_ALT_ID_Type_Load<br/><i>Expression</i>"]
  n5["Write_C_S_FSS_PTY_RLE_ALT_ID<br/><i>Target</i>"]
  n0 --> n1
  n1 --> n2
  n1 --> n3
  n2 --> n3
  n3 --> n4
  n4 --> n5
```

## Filtered data

Every step that can stop, divert or collapse rows, and what happens to the rows that do not pass. A Filter keeps a row only when its condition is TRUE: FALSE **or NULL** drops the row silently (no target, no reject file). A Router writes a row to **every** group whose condition is TRUE; a row that matches no group goes to the default group and is discarded when that group is not linked. Comments (`--`, `//`) are removed from the conditions shown here. A `= ...` line reads a null check on a lookup return in plain terms; *no matching row* also covers a matching row whose returned field is NULL.

### Steps that filter rows

| Step | IDQ type | Rule | Rows that pass go to | Rows that do not pass |
|---|---|---|---|---|
| Read_V_FSS_ETL_SRC | SourceTx | source filter `"V_FSS_ETL_SRC"."LAST_ACTIVE_CLIENT_REGISTRATION_YN"='Y'`; rows the view `V_FSS_ETL_SRC` returns (view logic is outside the export) | `C_S_FSS_PTY_RLE_ALT_ID` | never read |
| Filter | FilterTx | keep `IsNull(DEACTIVATION_STS)`<br>= no matching row in `STG_FSS_PTY_INACTIVE_STS` | `C_S_FSS_PTY_RLE_ALT_ID` | **discarded** |

### Where the condition fields come from

| Step | Field | Origin |
|---|---|---|
| Filter | `DEACTIVATION_STS` | `DEACTIVATION_STS` returned by lookup `Lkp_STG_FSS_PTY_INACTIVE_STS` on `STG_FSS_PTY_INACTIVE_STS` where `SRC_KEY = PTY_SRC_KEY AND ROWID_SYSTEM = SRC_SYSTEM`; NULL when no row matches; `STG_FSS_PTY_INACTIVE_STS` is loaded by `m_Tgt_C_S_FSS_Pty_Validation` in this workflow |

### Rows that do not reach `C_S_*` tables

**`C_S_FSS_PTY_RLE_ALT_ID`** (`Write_C_S_FSS_PTY_RLE_ALT_ID`): a source row is written only when it passes every step below.

| Step | Must hold | Otherwise the row |
|---|---|---|
| `Read_V_FSS_ETL_SRC` | source filter `"V_FSS_ETL_SRC"."LAST_ACTIVE_CLIENT_REGISTRATION_YN"='Y'`; rows the view `V_FSS_ETL_SRC` returns (view logic is outside the export) | never read |
| `Filter` | `IsNull(DEACTIVATION_STS)`<br>= no matching row in `STG_FSS_PTY_INACTIVE_STS` | **discarded** (not written anywhere) |

## Transformations

In data-flow order.

### Read_V_FSS_ETL_SRC

IDQ `SourceTx` &rarr; CDI **Source**. Oracle connector source; carry the SQL override / filter below verbatim.

| Property | Value |
|---|---|
| Connection | STAGING |
| Object | V_FSS_ETL_SRC (view) |

Filter (CDI source/lookup *Filter* property; translated):

```sql
"V_FSS_ETL_SRC"."LAST_ACTIVE_CLIENT_REGISTRATION_YN"='Y'
-- Testing Filter 
/*
and (ORA_HASH("V_FSS_ETL_SRC"."ID_REGISTRATION",9999) = 1
or "V_FSS_ETL_SRC"."PTY_SRC_KEY" in ('0000018326'
,'0000028796'
,'0000031710F'
,'0000091821'))
*/
```

Columns: `SOURCE_TYPE`, `DT_CREATED`, `DT_LAST_UPDATE`, `ID_CLIENT`, `PTY_SRC_KEY`, `NM_FIRST`, `NM_LAST`, `NM_MIDDLE`, `DT_DOB`, `CD_GENDER`, `LANGUAGE_CD`, `CD_HISPANIC`, `RACE_AN`, `RACE_ASIAN`, `RACE_AA`, `RACE_WHITE`, `RACE_PI`, `RACE_DECLINED`, `RACE_UNABLE_TO_DETERMINE`, `RACE_INVALID`, `ADDR_LINE1`, `ADDR_LINE2`, `ADDR_CITY`, `ADDR_STATE`, `ADDR_ZIP`, `CD_CNTY`, `NBR_PHONE`, `NBR_PHONE_EXT`, `ADDR_EMAIL`, `CD_RELTSHP_TO_TC`, `CD_CLNT_TYPE`, `DTL__CAPXACTION`, `DTL__CAPXTIMESTAMP`, `ID_REGISTRATION_CLIENT`, `ID_REGISTRATION`, `LAST_ACTIVE_CLIENT_REGISTRATION_YN`, `None`, `None`, `None`, `None`, `None`, `None`

### exp_FSS_Pty_Rle_Alt_Id

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| SOURCE_TYPE | in/out | string(6) |  |
| ID | in/out | string(15) |  |
| PTY_SRC_KEY | in/out | string(255) | `PTY_SRC_KEY` |
| v_PTY_RLE_FK | variable | string(255) | `PTY_SRC_KEY \|\| '\|Member'` |
| PTY_RLE_FK | out | string(255) | `v_PTY_RLE_FK` |
| v_ALT_ID_TP | variable | string(10) | `IIF(SOURCE_TYPE = 'CLIENT', '022','023')` |
| ALT_ID_TP | out | string(3) | `v_ALT_ID_TP` |
| ALT_ID_VAL | out | string(15) | `LPAD(ID,10,'0')` |
| DATE_CREATED | in/out | date/time |  |
| DATE_MODIFIED | in/out | date/time |  |
| SRC_SYSTEM | out | string(10) | `'FSS'` |
| PKEY_SRC_OBJECT | out | string(255) | `v_PTY_RLE_FK \|\| '\|' \|\| v_ALT_ID_TP \|\| '\|' \|\| LPAD(ID,10,'0')` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| ID | Read_V_FSS_ETL_SRC.ID_CLIENT |
| DATE_CREATED | Read_V_FSS_ETL_SRC.DT_CREATED |
| DATE_MODIFIED | Read_V_FSS_ETL_SRC.DT_LAST_UPDATE |
| PTY_SRC_KEY | Read_V_FSS_ETL_SRC.PTY_SRC_KEY |
| SOURCE_TYPE | Read_V_FSS_ETL_SRC.SOURCE_TYPE |

### Lkp_STG_FSS_PTY_INACTIVE_STS

IDQ `LookupTx` &rarr; CDI **Lookup**. Connected lookup unless a return port is set (then unconnected).

| Property | Value |
|---|---|
| Connection | STAGING |
| Object | STG_FSS_PTY_INACTIVE_STS |
| Lookup condition | SRC_KEY = PTY_SRC_KEY AND ROWID_SYSTEM = SRC_SYSTEM |
| Multiple matches | Return any row |
| Cache | static cache |

| Lookup input field | Type |
|---|---|
| PTY_SRC_KEY | string(255) |
| SRC_SYSTEM | string(10) |

| Return / pass-through field | Feeds |
|---|---|
| DEACTIVATION_STS | Filter.DEACTIVATION_STS |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PTY_SRC_KEY | exp_FSS_Pty_Rle_Alt_Id.PTY_SRC_KEY |
| SRC_SYSTEM | exp_FSS_Pty_Rle_Alt_Id.SRC_SYSTEM |

### Filter

IDQ `FilterTx` &rarr; CDI **Filter**. Advanced filter condition.

Filter condition:

```
IsNull(DEACTIVATION_STS)
```

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| ID | exp_FSS_Pty_Rle_Alt_Id.ID |
| PKEY_SRC_OBJECT | exp_FSS_Pty_Rle_Alt_Id.PKEY_SRC_OBJECT |
| PTY_REL_FK | exp_FSS_Pty_Rle_Alt_Id.PTY_RLE_FK |
| ALT_ID_TP | exp_FSS_Pty_Rle_Alt_Id.ALT_ID_TP |
| ALT_ID_VAL | exp_FSS_Pty_Rle_Alt_Id.ALT_ID_VAL |
| DATE_CREATED | exp_FSS_Pty_Rle_Alt_Id.DATE_CREATED |
| DATE_MODIFIED | exp_FSS_Pty_Rle_Alt_Id.DATE_MODIFIED |
| SRC_SYSTEM | exp_FSS_Pty_Rle_Alt_Id.SRC_SYSTEM |
| DEACTIVATION_STS | Lkp_STG_FSS_PTY_INACTIVE_STS.DEACTIVATION_STS |

### Exp_STG_ALT_ID_Type_Load

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| ID | in/out | string(15) | `ID` |
| PKEY_SRC_OBJECT | in/out | string(255) | `PKEY_SRC_OBJECT` |
| PTY_REL_FK | in/out | string(255) | `PTY_REL_FK` |
| ALT_ID_TP | in/out | string(3) | `ALT_ID_TP` |
| ALT_ID_VAL | in/out | string(15) | `ALT_ID_VAL` |
| DATE_CREATED | in/out | date/time | `DATE_CREATED` |
| DATE_MODIFIED | in/out | date/time | `DATE_MODIFIED` |
| Last_Changed_Dt | out | date/time | `IIF(IsNull(DATE_MODIFIED),DATE_CREATED,DATE_MODIFIED)` |
| SRC_SYSTEM | in/out | string(10) | `SRC_SYSTEM` |
| LAST_UPDATE_DATE | out | date/time | `SESSSTARTTIME` |
| SRC_ROWID | out | string(30) | `TO_CHAR(ID)\|\|'\|'\|\|ALT_ID_TP` |
| VERSION_SEQ (stale timeline: omit) | out | decimal(38) | `1` |
| STS_CD | out | string(20) | `'Issued'` |
| HUB_STATE_IND | out | decimal(38) | `1` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PTY_REL_FK | Filter.PTY_REL_FK |
| ALT_ID_TP | Filter.ALT_ID_TP |
| ALT_ID_VAL | Filter.ALT_ID_VAL |
| DATE_CREATED | Filter.DATE_CREATED |
| DATE_MODIFIED | Filter.DATE_MODIFIED |
| PKEY_SRC_OBJECT | Filter.PKEY_SRC_OBJECT |
| ID | Filter.ID |
| SRC_SYSTEM | Filter.SRC_SYSTEM |

### Write_C_S_FSS_PTY_RLE_ALT_ID

IDQ `TargetTx` &rarr; CDI **Target**. Oracle connector target.

| Property | Value |
|---|---|
| Connection | HHS_MDM_ORS |
| Object | C_S_FSS_PTY_RLE_ALT_ID |
| Operation | Insert |
| Truncate target table | yes |
| Load type | normal (no bulk load) |
| Reject file | Write_C_S_FSS_PTY_RLE_ALT_ID.bad |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PKEY_SRC_OBJECT | Exp_STG_ALT_ID_Type_Load.PKEY_SRC_OBJECT |
| PTY_RLE_FK | Exp_STG_ALT_ID_Type_Load.PTY_REL_FK |
| ALT_ID_TP | Exp_STG_ALT_ID_Type_Load.ALT_ID_TP |
| ALT_ID_VAL | Exp_STG_ALT_ID_Type_Load.ALT_ID_VAL |
| SRC_LAST_UPD_DT | Exp_STG_ALT_ID_Type_Load.LAST_UPDATE_DATE |
| HUB_STATE_IND | Exp_STG_ALT_ID_Type_Load.HUB_STATE_IND |
| STS_CD | Exp_STG_ALT_ID_Type_Load.STS_CD |
| SRC_ROWID | Exp_STG_ALT_ID_Type_Load.SRC_ROWID |
| LAST_UPDATE_DATE | Exp_STG_ALT_ID_Type_Load.LAST_UPDATE_DATE |
| VERSION_SEQ (stale timeline: do not map) | Exp_STG_ALT_ID_Type_Load.VERSION_SEQ |
| ALT_ID_TP_FLTR | Exp_STG_ALT_ID_Type_Load.ALT_ID_TP |
| CREATE_DATE | Exp_STG_ALT_ID_Type_Load.DATE_CREATED |
| PERIOD_START_DATE | Exp_STG_ALT_ID_Type_Load.DATE_CREATED |

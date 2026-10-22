# wf_TRS_Stage_Load_TOA &rarr; IDMC CDI

Build specification generated from `docs/wf_TRS_Stage_Load_TOA.xml` by `ext-tools/idmc_spec.py`. It describes every asset to create in IDMC so the CDI/CDQ version behaves like the IDQ workflow. Regenerate rather than edit.

## Target layout

| IDMC asset | Name | Count | Spec |
|---|---|---|---|
| Project / folder | `HHS_MDM_Stage` / `TRS` | 1 |  |
| Taskflow | `tf_TRS_Stage_Load_TOA` | 1 | [taskflow.md](taskflow.md) |
| Mapping task | `mct_<mapping name without m_>` | 1 | [taskflow.md](taskflow.md#mapping-tasks) |
| Mapping | same as IDQ | 1 | mappings/ |
| Mapplet | same as IDQ (`mplt_*`, `rule_*`) | 0 | mapplets/ |
| CDQ assets | Cleanse / Labeler / Verifier / Dictionary |  | [cdq.md](cdq.md) |
| Parameter file | `tf_TRS_Stage_Load_TOA.param` | 1 | [tf_TRS_Stage_Load_TOA.param](tf_TRS_Stage_Load_TOA.param) |

## Connections

Keep the IDQ connection names so the specs read one to one.

| Connection | IDQ type | IDMC connector |
|---|---|---|
| HHS_MDM_ORS | ORACLE | Oracle |
| STAGING | ORACLE | Oracle |

## Build order

1. Connections and the Secure Agent runtime environment (Linux, command tasks enabled).
2. CDQ dictionaries, then Cleanse / Labeler / Verifier assets ([cdq.md](cdq.md)).
3. Mapplets, innermost first:


4. Mappings, in taskflow order:

   - [`m_Tgt_C_S_TRS_Stg_TOA`](mappings/m_Tgt_C_S_TRS_Stg_TOA.md)

5. Mapping tasks with the parameter file, then the taskflow ([taskflow.md](taskflow.md)).

## Transformation inventory

| IDQ transformation | CDI | Count | Note |
|---|---|---|---|
| ExpressionTx | Expression | 2 | Same expression language; variable fields are supported. |
| LookupTx | Lookup | 2 | Connected lookup unless a return port is set (then unconnected). |
| SourceTx | Source | 1 | Oracle connector source; carry the SQL override / filter below verbatim. |
| TargetTx | Target | 1 | Oracle connector target. |

## Not ported: stale MDM timeline

The legacy MDM timeline of the C_S_* tables is stale, so its logic is not built (same decision as the Java port; see the *Retired / not ported* sections of `docs/mappings`):

- **Fields**: `VERSION_SEQ*`, version / duplicate ranks, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION` are marked *omit* in expressions and *do not map* in links.
- **Steps and mapplets** listed below are not built; each spec says how to link around them.

No whole steps are retired in this workflow; only the timeline fields are omitted.

## Filtered data

Which steps can keep a source row out of each `C_S_*` table, and where the diverted rows go instead. Each mapping spec has a *Filtered data* section with the conditions, the origin of every field they test and what happens to the rows that fail.

| Mapping | `C_S_*` table | Steps that can keep a row out | Failed rows diverted to |
|---|---|---|---|
| [`m_Tgt_C_S_TRS_Stg_TOA`](mappings/m_Tgt_C_S_TRS_Stg_TOA.md#filtered-data) | `C_S_LU_TOA` | none |  |

## Translation rules applied

| IDQ | CDI | Where |
|---|---|---|
| `$<Param>` (user parameter) | `$$<Param>` input parameter | expressions, conditions, SQL |
| `$sys.MappingName` | `$$MappingName` input parameter, set per mapping task in the parameter file | expressions |
| `$sys.MappingRunStartTime` | `SESSSTARTTIME` | expressions |
| Update Strategy (`DD_DELETE`) | Target operation *Data Driven* / *Delete* | targets |
| Inclusive gateways (split + join) | *Parallel Paths* step | taskflow |
| Command task | Taskflow *Command Task* on the Secure Agent | taskflow |
| Data types | string/decimal/date-time/integer/double (same precision and scale) | all fields |
| MDM timeline fields, steps and mapplets | not ported (see the section above) | all |

Every other function used (`IIF`, `DECODE`, `REG_MATCH`, `REPLACESTR`, `LPAD`, `MD5`, `IN`, `IS_NUMBER`, `SYSTIMESTAMP`, ...) exists in CDI with the same signature, so expressions are carried over as is.

## Open items to confirm in the target org

- **Snowflake_PEI**: the IDQ ODBC DSN becomes a Snowflake Data Cloud connection; check the lookup table `RDM.REF_PHN_AREA_CD` resolves (database/schema in the connection).
- **Reference data**: dictionary rows are not in the export; load them from the IDQ reference data warehouse (see [cdq.md](cdq.md)).
- **Address verification**: the Verifier asset needs the US reference data licensed and installed for the org; output fields and mailability score must be compared on a sample before go-live.
- **Indicator file**: the command task path assumes the Secure Agent host mounts `/opt/apps/informatica/SrcFiles/Indicators`.
- **DQ transformations inside mapplets**: the address, name and rule mapplets call Cleanse / Labeler / Verifier transformations; create the CDQ assets first so the mapplets validate.
- **Project / folder names** (`HHS_MDM_Stage` / `TRS`) are placeholders: rename freely, then update the section headers in the parameter file.

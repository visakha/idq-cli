# wf_FSS_Stage_Load &rarr; IDMC CDI

Build specification generated from `docs/wf_FSS_Stage_Load.xml` by `ext-tools/idmc_spec.py`. It describes every asset to create in IDMC so the CDI/CDQ version behaves like the IDQ workflow. Regenerate rather than edit.

## Target layout

| IDMC asset | Name | Count | Spec |
|---|---|---|---|
| Project / folder | `HHS_MDM_Stage` / `FSS` | 1 |  |
| Taskflow | `tf_FSS_Stage_Load` | 1 | [taskflow.md](taskflow.md) |
| Mapping task | `mct_<mapping name without m_>` | 6 | [taskflow.md](taskflow.md#mapping-tasks) |
| Mapping | same as IDQ | 6 | mappings/ |
| Mapplet | same as IDQ (`mplt_*`, `rule_*`) | 16 | mapplets/ |
| CDQ assets | Cleanse / Labeler / Verifier / Dictionary |  | [cdq.md](cdq.md) |
| Parameter file | `tf_FSS_Stage_Load.param` | 1 | [tf_FSS_Stage_Load.param](tf_FSS_Stage_Load.param) |

## Connections

Keep the IDQ connection names so the specs read one to one.

| Connection | IDQ type | IDMC connector |
|---|---|---|
| HHS_MDM_ORS | ORACLE | Oracle |
| INFA_STAGE | ORACLE | Oracle |
| STAGING | ORACLE | Oracle |
| Snowflake_PEI | ODBC | Snowflake Data Cloud (replaces the ODBC DSN) |

## Build order

1. Connections and the Secure Agent runtime environment (Linux, command tasks enabled).
2. CDQ dictionaries, then Cleanse / Labeler / Verifier assets ([cdq.md](cdq.md)).
3. Mapplets, innermost first:

   - [`mplt_BirthDate_Validation`](mapplets/mplt_BirthDate_Validation.md)
   - [`mplt_Ethnicity_Validation`](mapplets/mplt_Ethnicity_Validation.md)
   - [`mplt_Gender_Validation`](mapplets/mplt_Gender_Validation.md)
   - [`rule_Addr_Line_Post_Scrub`](mapplets/rule_Addr_Line_Post_Scrub.md)
   - [`rule_Addr_Line_Pre_Scrub1`](mapplets/rule_Addr_Line_Pre_Scrub1.md)
   - [`mplt_Global_Addr_Validation`](mapplets/mplt_Global_Addr_Validation.md)
   - [`mplt_Language_Validation`](mapplets/mplt_Language_Validation.md)
   - [`mplt_Name_Standardization_Trailing_Num_Removal`](mapplets/mplt_Name_Standardization_Trailing_Num_Removal.md)
   - [`mplt_Name_Standardization_Indv_Member`](mapplets/mplt_Name_Standardization_Indv_Member.md)
   - [`mplt_Race_Ind_Validation`](mapplets/mplt_Race_Ind_Validation.md)
   - [`rule_Phone_Extension_Std`](mapplets/rule_Phone_Extension_Std.md)
   - [`rule_Phone_Std`](mapplets/rule_Phone_Std.md)
   - [`rule_Suffix_Std`](mapplets/rule_Suffix_Std.md)
   - [`rule_email_Domain_Subdomain_validation__V1`](mapplets/rule_email_Domain_Subdomain_validation__V1.md)
   - [`rule_email_LocalPart_validation_V1`](mapplets/rule_email_LocalPart_validation_V1.md)
   - [`rule_email_validation_v01`](mapplets/rule_email_validation_v01.md)

4. Mappings, in taskflow order:

   - [`m_Tgt_C_S_FSS_Pty_Validation`](mappings/m_Tgt_C_S_FSS_Pty_Validation.md)
   - [`m_Tgt_C_S_FSS_Pty`](mappings/m_Tgt_C_S_FSS_Pty.md)
   - [`m_Tgt_C_S_FSS_Pty_Addr`](mappings/m_Tgt_C_S_FSS_Pty_Addr.md)
   - [`m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md)
   - [`m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md)
   - [`m_Tgt_C_S_FSS_Pty_Rle_Rel`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Rel.md)

5. Mapping tasks with the parameter file, then the taskflow ([taskflow.md](taskflow.md)).

## Transformation inventory

| IDQ transformation | CDI | Count | Note |
|---|---|---|---|
| AvTx | Verifier | 1 | CDQ Verifier asset for address verification (see cdq.md). |
| CaseConverterTx | Cleanse | 2 | CDQ Cleanse asset with a Change Case step (see cdq.md). |
| ExpressionTx | Expression | 69 | Same expression language; variable fields are supported. |
| FilterTx | Filter | 8 | Advanced filter condition. |
| LabelerTx | Labeler | 2 | CDQ Labeler asset (see cdq.md). |
| LookupTx | Lookup | 30 | Connected lookup unless a return port is set (then unconnected). |
| MappletInputTx | Input | 16 | Mapplet Input transformation. |
| MappletOutputTx | Output | 16 | Mapplet Output transformation. |
| MappletTx | Mapplet | 17 | Reusable CDI mapplet (see the mapplets folder). |
| RouterTx | Router | 6 | One output group per IDQ group; the default group is created automatically. |
| SourceTx | Source | 6 | Oracle connector source; carry the SQL override / filter below verbatim. |
| TargetTx | Target | 24 | Oracle connector target. |
| TokenStandardiserTx | Cleanse | 8 | CDQ Cleanse asset with remove/replace steps (see cdq.md). |
| UpdateStrategyTx | (target operation) | 1 | CDI has no Update Strategy transformation: set the downstream target operation to Data Driven with the condition below. |

## Not ported: stale MDM timeline

The legacy MDM timeline of the C_S_* tables is stale, so its logic is not built (same decision as the Java port; see the *Retired / not ported* sections of `docs/mappings`):

- **Fields**: `VERSION_SEQ*`, version / duplicate ranks, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION` are marked *omit* in expressions and *do not map* in links.
- **Steps and mapplets** listed below are not built; each spec says how to link around them.

No whole steps are retired in this workflow; only the timeline fields are omitted.

## Filtered data

Which steps can keep a source row out of each `C_S_*` table, and where the diverted rows go instead. Each mapping spec has a *Filtered data* section with the conditions, the origin of every field they test and what happens to the rows that fail.

| Mapping | `C_S_*` table | Steps that can keep a row out | Failed rows diverted to |
|---|---|---|---|
| [`m_Tgt_C_S_FSS_Pty_Validation`](mappings/m_Tgt_C_S_FSS_Pty_Validation.md#filtered-data) | (no `C_S_*` target) |  |  |
| [`m_Tgt_C_S_FSS_Pty`](mappings/m_Tgt_C_S_FSS_Pty.md#filtered-data) | `C_S_FSS_PTY` | `Read_V_FSS_ETL_SRC`, `Flt_Remove_Inactive`, `Rtr_Exception` |  |
| [`m_Tgt_C_S_FSS_Pty`](mappings/m_Tgt_C_S_FSS_Pty.md#filtered-data) | `C_S_FSS_PTY_RLE` | `Read_V_FSS_ETL_SRC`, `Flt_Remove_Inactive`, `Rtr_Exception` |  |
| [`m_Tgt_C_S_FSS_Pty_Addr`](mappings/m_Tgt_C_S_FSS_Pty_Addr.md#filtered-data) | `C_S_FSS_PTY_RLE_ADDR` | `Read_V_FSS_ETL_SRC`, `Fil_Inactive_recs`, `rtr_Good_vs_Exception_Pty_Records` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md#filtered-data) | `C_S_FSS_PTY_RLE_ALT_ID` | `Read_V_FSS_ETL_SRC`, `Filter` |  |
| [`m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md#filtered-data) | `C_S_FSS_PTY_RLE_EADDR` | `Read_V_FSS_ETL_SRC`, `fil_deactivated_status`, `Filt_null_email`, `rtr_Valid_EAddr_Records` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md#filtered-data) | `C_S_FSS_PTY_RLE_PHN` | `Read_V_FSS_ETL_SRC`, `fil_deactivated_status`, `Filt_null_phone`, `RTR_Valid_PhoneNumbers` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_FSS_Pty_Rle_Rel`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Rel.md#filtered-data) | `C_S_FSS_PTY_RLE_REL` | `Read_V_FSS_ETL_SRC_RELATIONS`, `Filter_Fam_Child_Valid`, `Route_Good_vs_Exceptions` | `EXC_STG_BAD_REC_MEMB` |

## Oracle stored procedures

Each mapping also has a drop-in Oracle replacement under [idq-to-oracle/wf_FSS_Stage_Load](../../idq-to-oracle/wf_FSS_Stage_Load/) (conventions, install order and the shared `fn_dq_*` / helper objects: [idq-to-oracle/README.md](../../idq-to-oracle/README.md)). Run them in taskflow order (paths of a *Parallel Paths* step may run in parallel sessions); [run_wf_FSS_Stage_Load.sql](../../idq-to-oracle/wf_FSS_Stage_Load/run_wf_FSS_Stage_Load.sql) runs them one after another. Each mapping spec has an *Oracle stored procedure* section.

| Mapping | Procedure |
|---|---|
| [`m_Tgt_C_S_FSS_Pty_Validation`](mappings/m_Tgt_C_S_FSS_Pty_Validation.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation`](../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation.sql) |
| [`m_Tgt_C_S_FSS_Pty`](mappings/m_Tgt_C_S_FSS_Pty.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_FSS_Pty`](../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty.sql) |
| [`m_Tgt_C_S_FSS_Pty_Addr`](mappings/m_Tgt_C_S_FSS_Pty_Addr.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr`](../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr.sql) |
| [`m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`](../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.sql) |
| [`m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`](../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql) |
| [`m_Tgt_C_S_FSS_Pty_Rle_Rel`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Rel.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel`](../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql) |

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
- **Project / folder names** (`HHS_MDM_Stage` / `FSS`) are placeholders: rename freely, then update the section headers in the parameter file.

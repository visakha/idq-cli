# wf_CRE_Stage_Load_Ongoing &rarr; IDMC CDI

Build specification generated from `docs/wf_CRE_Stage_Load_Ongoing.xml` by `ext-tools/idmc_spec.py`. It describes every asset to create in IDMC so the CDI/CDQ version behaves like the IDQ workflow. Regenerate rather than edit.

## Target layout

| IDMC asset | Name | Count | Spec |
|---|---|---|---|
| Project / folder | `HHS_MDM_Stage` / `CRE` | 1 |  |
| Taskflow | `tf_CRE_Stage_Load_Ongoing` | 1 | [taskflow.md](taskflow.md) |
| Mapping task | `mct_<mapping name without m_>` | 1 | [taskflow.md](taskflow.md#mapping-tasks) |
| Mapping | same as IDQ | 1 | mappings/ |
| Mapplet | same as IDQ (`mplt_*`, `rule_*`) | 12 | mapplets/ |
| CDQ assets | Cleanse / Labeler / Verifier / Dictionary |  | [cdq.md](cdq.md) |
| Parameter file | `tf_CRE_Stage_Load_Ongoing.param` | 1 | [tf_CRE_Stage_Load_Ongoing.param](tf_CRE_Stage_Load_Ongoing.param) |

## Connections

Keep the IDQ connection names so the specs read one to one.

| Connection | IDQ type | IDMC connector |
|---|---|---|
| HHS_MDM_ORS | ORACLE | Oracle |
| INFA_STAGE | ORACLE | Oracle |
| SRCMRG | ORACLE | Oracle |
| STAGING | ORACLE | Oracle |
| Snowflake_PEI | ODBC | Snowflake Data Cloud (replaces the ODBC DSN) |

## Build order

1. Connections and the Secure Agent runtime environment (Linux, command tasks enabled).
2. CDQ dictionaries, then Cleanse / Labeler / Verifier assets ([cdq.md](cdq.md)).
3. Mapplets, innermost first:

   - [`mplt_Ethnicity_Validation`](mapplets/mplt_Ethnicity_Validation.md)
   - [`mplt_Gender_Validation`](mapplets/mplt_Gender_Validation.md)
   - [`rule_Addr_Line_Post_Scrub`](mapplets/rule_Addr_Line_Post_Scrub.md)
   - [`rule_Addr_Line_Pre_Scrub1`](mapplets/rule_Addr_Line_Pre_Scrub1.md)
   - [`mplt_Global_Addr_Validation`](mapplets/mplt_Global_Addr_Validation.md)
   - [`mplt_Name_Standardization_Trailing_Num_Removal`](mapplets/mplt_Name_Standardization_Trailing_Num_Removal.md)
   - [`mplt_Name_Standardization_Indv_Member`](mapplets/mplt_Name_Standardization_Indv_Member.md)
   - [`mplt_Race_Validation`](mapplets/mplt_Race_Validation.md)
   - [`rule_CARE_ID_Std`](mapplets/rule_CARE_ID_Std.md)
   - [`rule_MEDICAID_ID_Std`](mapplets/rule_MEDICAID_ID_Std.md)
   - [`rule_Phone_Std`](mapplets/rule_Phone_Std.md)
   - [`rule_USA_SSN_Validation_post_June2011`](mapplets/rule_USA_SSN_Validation_post_June2011.md)

4. Mappings, in taskflow order:

   - [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md)

5. Mapping tasks with the parameter file, then the taskflow ([taskflow.md](taskflow.md)).

## Transformation inventory

| IDQ transformation | CDI | Count | Note |
|---|---|---|---|
| AvTx | Verifier | 1 | CDQ Verifier asset for address verification (see cdq.md). |
| CaseConverterTx | Cleanse | 2 | CDQ Cleanse asset with a Change Case step (see cdq.md). |
| ExpressionTx | Expression | 50 | Same expression language; variable fields are supported. |
| FilterTx | Filter | 8 | Advanced filter condition. |
| LabelerTx | Labeler | 4 | CDQ Labeler asset (see cdq.md). |
| LookupTx | Lookup | 29 | Connected lookup unless a return port is set (then unconnected). |
| MappletInputTx | Input | 12 | Mapplet Input transformation. |
| MappletOutputTx | Output | 12 | Mapplet Output transformation. |
| MappletTx | Mapplet | 12 | Reusable CDI mapplet (see the mapplets folder). |
| NormalizerTx | Normalizer | 1 | Normalized fields with their occurrence counts below. |
| RouterTx | Router | 8 | One output group per IDQ group; the default group is created automatically. |
| SorterTx | Sorter | 2 | Sort keys in the order listed; distinct, case and null settings below. |
| SourceTx | Source | 1 | Oracle connector source; carry the SQL override / filter below verbatim. |
| TargetTx | Target | 15 | Oracle connector target. |
| TokenStandardiserTx | Cleanse | 9 | CDQ Cleanse asset with remove/replace steps (see cdq.md). |
| UnionTx | Union | 3 | One input group per IDQ group. |

## Not ported: stale MDM timeline

The legacy MDM timeline of the C_S_* tables is stale, so its logic is not built (same decision as the Java port; see the *Retired / not ported* sections of `docs/mappings`):

- **Fields**: `VERSION_SEQ*`, version / duplicate ranks, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION` are marked *omit* in expressions and *do not map* in links.
- **Steps and mapplets** listed below are not built; each spec says how to link around them.

No whole steps are retired in this workflow; only the timeline fields are omitted.

## Filtered data

Which steps can keep a source row out of each `C_S_*` table, and where the diverted rows go instead. Each mapping spec has a *Filtered data* section with the conditions, the origin of every field they test and what happens to the rows that fail.

| Mapping | `C_S_*` table | Steps that can keep a row out | Failed rows diverted to |
|---|---|---|---|
| [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md#filtered-data) | `C_S_CRE_PTY_RLE` | `Read_Stg_CRE_D_CARE_Clients`, `RTR_MERGES`, `rtr_Valid_Members`, `Filt_DeDeup_Seq1` | `CRE_SRC_MRG`, `EXC_STG_BAD_REC_MEMB`, `C_S_CRE_PTY_RLE_ADDR`, `C_S_CRE_PTY_RLE_PHN`, `C_S_CRE_PTY_RLE_ALT_ID`, `C_S_CRE_PTY` |
| [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md#filtered-data) | `C_S_CRE_PTY_RLE_ADDR` | `Read_Stg_CRE_D_CARE_Clients`, `RTR_MERGES`, `rtr_Valid_Members`, `Filt_DeDeup_Seq1`, `RTR_US_ADDRESSES`, `RTR_VALID_NON_US_ADDRESSES`, `RTR_VALID_ADDRESS` | `CRE_SRC_MRG`, `EXC_STG_BAD_REC_MEMB`, `C_S_CRE_PTY_RLE`, `C_S_CRE_PTY_RLE_PHN`, `C_S_CRE_PTY_RLE_ALT_ID`, `C_S_CRE_PTY` |
| [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md#filtered-data) | `C_S_CRE_PTY_RLE_PHN` | `Read_Stg_CRE_D_CARE_Clients`, `RTR_MERGES`, `rtr_Valid_Members`, `Filt_DeDeup_Seq1`, `FLTR_NULL_PHONE`, `RTR_VALID_PHONE` | `CRE_SRC_MRG`, `EXC_STG_BAD_REC_MEMB`, `C_S_CRE_PTY_RLE`, `C_S_CRE_PTY_RLE_ADDR`, `C_S_CRE_PTY_RLE_ALT_ID`, `C_S_CRE_PTY` |
| [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md#filtered-data) | `C_S_CRE_PTY_RLE_ALT_ID` | `Read_Stg_CRE_D_CARE_Clients`, `RTR_MERGES`, `rtr_Valid_Members`, `FLTR_NULL_ALT_ID_SEQ1`, `RTR_VALID_ALT_ID` | `CRE_SRC_MRG`, `EXC_STG_BAD_REC_MEMB`, `C_S_CRE_PTY_RLE`, `C_S_CRE_PTY_RLE_ADDR`, `C_S_CRE_PTY_RLE_PHN`, `C_S_CRE_PTY` |
| [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md#filtered-data) | `C_S_CRE_PTY` | `Read_Stg_CRE_D_CARE_Clients`, `RTR_MERGES`, `rtr_Valid_Members`, `Filt_DeDeup_Seq1` | `CRE_SRC_MRG`, `EXC_STG_BAD_REC_MEMB`, `C_S_CRE_PTY_RLE`, `C_S_CRE_PTY_RLE_ADDR`, `C_S_CRE_PTY_RLE_PHN`, `C_S_CRE_PTY_RLE_ALT_ID` |

## Oracle stored procedures

Each mapping also has a drop-in Oracle replacement under [idq-to-oracle/wf_CRE_Stage_Load_Ongoing](../../idq-to-oracle/wf_CRE_Stage_Load_Ongoing/) (conventions, install order and the shared `fn_dq_*` / helper objects: [idq-to-oracle/README.md](../../idq-to-oracle/README.md)). Run them in taskflow order (paths of a *Parallel Paths* step may run in parallel sessions); [run_wf_CRE_Stage_Load_Ongoing.sql](../../idq-to-oracle/wf_CRE_Stage_Load_Ongoing/run_wf_CRE_Stage_Load_Ongoing.sql) runs them one after another. Each mapping spec has an *Oracle stored procedure* section.

| Mapping | Procedure |
|---|---|
| [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients`](../../idq-to-oracle/wf_CRE_Stage_Load_Ongoing/sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients.sql) |

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
- **Project / folder names** (`HHS_MDM_Stage` / `CRE`) are placeholders: rename freely, then update the section headers in the parameter file.

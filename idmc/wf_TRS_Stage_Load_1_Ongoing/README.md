# wf_TRS_Stage_Load_1_Ongoing &rarr; IDMC CDI

Build specification generated from `docs/wf_TRS_Stage_Load_1_Ongoing.xml` by `ext-tools/idmc_spec.py`. It describes every asset to create in IDMC so the CDI/CDQ version behaves like the IDQ workflow. Regenerate rather than edit.

## Target layout

| IDMC asset | Name | Count | Spec |
|---|---|---|---|
| Project / folder | `HHS_MDM_Stage` / `TRS` | 1 |  |
| Taskflow | `tf_TRS_Stage_Load_1_Ongoing` | 1 | [taskflow.md](taskflow.md) |
| Mapping task | `mct_<mapping name without m_>` | 14 | [taskflow.md](taskflow.md#mapping-tasks) |
| Mapping | same as IDQ | 14 | mappings/ |
| Mapplet | same as IDQ (`mplt_*`, `rule_*`) | 22 | mapplets/ |
| CDQ assets | Cleanse / Labeler / Verifier / Dictionary |  | [cdq.md](cdq.md) |
| Parameter file | `tf_TRS_Stage_Load_1_Ongoing.param` | 1 | [tf_TRS_Stage_Load_1_Ongoing.param](tf_TRS_Stage_Load_1_Ongoing.param) |

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
   - [`mplt_Date_Greater_Than_Fifty_Years`](mapplets/mplt_Date_Greater_Than_Fifty_Years.md)
   - [`mplt_Ethnicity_Validation`](mapplets/mplt_Ethnicity_Validation.md)
   - [`mplt_Gender_Validation`](mapplets/mplt_Gender_Validation.md)
   - [`rule_Addr_Line_Post_Scrub`](mapplets/rule_Addr_Line_Post_Scrub.md)
   - [`rule_Addr_Line_Pre_Scrub1`](mapplets/rule_Addr_Line_Pre_Scrub1.md)
   - [`mplt_Global_Addr_Validation`](mapplets/mplt_Global_Addr_Validation.md)
   - [`mplt_Member_Pty_Rle_EAddr_Consolidation`](mapplets/mplt_Member_Pty_Rle_EAddr_Consolidation.md)
   - [`mplt_Member_Pty_Rle_Phn_Consolidation`](mapplets/mplt_Member_Pty_Rle_Phn_Consolidation.md)
   - [`rule_Phone_Std`](mapplets/rule_Phone_Std.md)
   - [`mplt_Member_Pty_Rle_Phn_Normalization`](mapplets/mplt_Member_Pty_Rle_Phn_Normalization.md)
   - [`mplt_Member_Pty_Rle_Rel_Consolidation`](mapplets/mplt_Member_Pty_Rle_Rel_Consolidation.md)
   - [`mplt_Name_Standardization_Trailing_Num_Removal`](mapplets/mplt_Name_Standardization_Trailing_Num_Removal.md)
   - [`mplt_Name_Standardization_Indv_Member`](mapplets/mplt_Name_Standardization_Indv_Member.md)
   - [`mplt_Race_Validation`](mapplets/mplt_Race_Validation.md)
   - [`rule_MEDICAID_ID_Std`](mapplets/rule_MEDICAID_ID_Std.md)
   - [`rule_Member_Id_Std`](mapplets/rule_Member_Id_Std.md)
   - [`rule_USA_SSN_Validation_post_June2011`](mapplets/rule_USA_SSN_Validation_post_June2011.md)
   - [`mplt_TRS_Pty_Rle_Alt_Id_Normalization`](mapplets/mplt_TRS_Pty_Rle_Alt_Id_Normalization.md)
   - [`rule_email_Domain_Subdomain_validation__V1`](mapplets/rule_email_Domain_Subdomain_validation__V1.md)
   - [`rule_email_LocalPart_validation_V1`](mapplets/rule_email_LocalPart_validation_V1.md)
   - [`rule_email_validation_v01`](mapplets/rule_email_validation_v01.md)

4. Mappings, in taskflow order:

   - [`m_Tgt_C_S_TRS_Pty_OnGoing`](mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md)
   - [`m_Tgt_C_S_TRS_Pty_Deactivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Deactivation_1.md)
   - [`m_Tgt_C_S_TRS_Pty_Rle_TOA`](mappings/m_Tgt_C_S_TRS_Pty_Rle_TOA.md)
   - [`m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md)
   - [`m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.md)
   - [`m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md)
   - [`m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md)
   - [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md)
   - [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md)
   - [`m_Tgt_C_S_TRS_Pty_Nm`](mappings/m_Tgt_C_S_TRS_Pty_Nm.md)
   - [`m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md)
   - [`m_Tgt_C_S_TRS_Pty_Rle_Pln`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Pln.md)
   - [`m_Tgt_C_S_TRS_Addr_1`](mappings/m_Tgt_C_S_TRS_Addr_1.md)
   - [`m_Tgt_C_S_TRS_Addr_2`](mappings/m_Tgt_C_S_TRS_Addr_2.md)

5. Mapping tasks with the parameter file, then the taskflow ([taskflow.md](taskflow.md)).

## Transformation inventory

| IDQ transformation | CDI | Count | Note |
|---|---|---|---|
| AggregatorTx | Aggregator | 8 | Group-by fields and aggregate expressions below. |
| AvTx | Verifier | 1 | CDQ Verifier asset for address verification (see cdq.md). |
| CaseConverterTx | Cleanse | 2 | CDQ Cleanse asset with a Change Case step (see cdq.md). |
| ExpressionTx | Expression | 107 | Same expression language; variable fields are supported. |
| FilterTx | Filter | 16 | Advanced filter condition. |
| LabelerTx | Labeler | 4 | CDQ Labeler asset (see cdq.md). |
| LookupTx | Lookup | 45 | Connected lookup unless a return port is set (then unconnected). |
| MappletInputTx | Input | 22 | Mapplet Input transformation. |
| MappletOutputTx | Output | 22 | Mapplet Output transformation. |
| MappletTx | Mapplet | 27 | Reusable CDI mapplet (see the mapplets folder). |
| NormalizerTx | Normalizer | 3 | Normalized fields with their occurrence counts below. |
| RouterTx | Router | 9 | One output group per IDQ group; the default group is created automatically. |
| SorterTx | Sorter | 16 | Sort keys in the order listed; distinct, case and null settings below. |
| SourceTx | Source | 14 | Oracle connector source; carry the SQL override / filter below verbatim. |
| TargetTx | Target | 38 | Oracle connector target. |
| TokenStandardiserTx | Cleanse | 9 | CDQ Cleanse asset with remove/replace steps (see cdq.md). |
| UpdateStrategyTx | (target operation) | 1 | CDI has no Update Strategy transformation: set the downstream target operation to Data Driven with the condition below. |

## Not ported: stale MDM timeline

The legacy MDM timeline of the C_S_* tables is stale, so its logic is not built (same decision as the Java port; see the *Retired / not ported* sections of `docs/mappings`):

- **Fields**: `VERSION_SEQ*`, version / duplicate ranks, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION` are marked *omit* in expressions and *do not map* in links.
- **Steps and mapplets** listed below are not built; each spec says how to link around them.

| Mapplet (not built) | Why |
|---|---|
| [`mplt_DST_Correction`](mapplets/mplt_DST_Correction.md) | shifts end dates by one hour around daylight-saving changes for the timeline |
| [`mplt_Pty_Rle_Rel_Timeline_Validation`](mapplets/mplt_Pty_Rle_Rel_Timeline_Validation.md) | duplicates end-dated relationships into open and closed versions, re-ranks `VERSION_SEQ`, sets `PERIOD_REFERENCE_TIME` / `TIMELINE_ACTION` and forces `HUB_STATE_IND` on open rows |

| Mapping / mapplet | Step | IDQ type | Reason |
|---|---|---|---|
| [`m_Tgt_C_S_TRS_Pty_OnGoing`](mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md) | `fltr_Dups` | FilterTx | Filter `VERSION_SEQ_NUM = 1`; the version is hard-coded to 1, so it passes every row. Link the fields that feed it straight to the fields it fed. |
| [`m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md) | `exp_Rank` | ExpressionTx | Version rank for `fltr_Rank`. Replaced together with `fltr_Rank` (see there). |
| [`m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md) | `fltr_Rank` | FilterTx | Keeps `VERSION_SEQ = 1`. Replace `exp_Rank` + `fltr_Rank` with an Aggregator grouped by `PKEY_SRC_OBJECT` (one row per key, as the Java port does); a CDI Aggregator without aggregate functions returns the last row of each group in the upstream `srtr_Pkey` order. |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md) | `mplt_Pty_Rle_Rel_Timeline_Validation` | MappletTx | Calls the retired mapplet `mplt_Pty_Rle_Rel_Timeline_Validation`, which duplicates end-dated relationships into open and closed versions, re-ranks `VERSION_SEQ`, sets `PERIOD_REFERENCE_TIME` / `TIMELINE_ACTION` and forces `HUB_STATE_IND` on open rows. Link the fields that feed it straight to the fields it fed. |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md) | `mplt_Pty_Rle_Rel_Timeline_Validation` | MappletTx | Calls the retired mapplet `mplt_Pty_Rle_Rel_Timeline_Validation`, which duplicates end-dated relationships into open and closed versions, re-ranks `VERSION_SEQ`, sets `PERIOD_REFERENCE_TIME` / `TIMELINE_ACTION` and forces `HUB_STATE_IND` on open rows. Link the fields that feed it straight to the fields it fed. |
| [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md) | `exp_Rank` | ExpressionTx | `VERSION_SEQ_NUM` rank, hard-coded to 1. Link the fields that feed it straight to the fields it fed. |
| [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md) | `srtr_Rank` | SorterTx | Distinct re-sort around `exp_Rank`. Link the fields that feed it straight to the fields it fed. |

## Filtered data

Which steps can keep a source row out of each `C_S_*` table, and where the diverted rows go instead. Each mapping spec has a *Filtered data* section with the conditions, the origin of every field they test and what happens to the rows that fail.

| Mapping | `C_S_*` table | Steps that can keep a row out | Failed rows diverted to |
|---|---|---|---|
| [`m_Tgt_C_S_TRS_Pty_OnGoing`](mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md#filtered-data) | `C_S_TRS_PTY_RLE` | `Read_STG_TRS_D_DC_INDV`, `rtr_Invalid_Party`, `srtr_Dedup_Rec`, `Aggregator` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Pty_OnGoing`](mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md#filtered-data) | `C_S_TRS_PTY` | `Read_STG_TRS_D_DC_INDV`, `rtr_Invalid_Party`, `srtr_Dedup_Rec`, `Aggregator1` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Pty_Deactivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Deactivation_1.md#filtered-data) | (no `C_S_*` target) |  |  |
| [`m_Tgt_C_S_TRS_Pty_Rle_TOA`](mappings/m_Tgt_C_S_TRS_Pty_Rle_TOA.md#filtered-data) | `C_S_TRS_PTY_RLE_TOA` | `read_Staging_Delta_Tables`, `rtr_Valid_Records` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md#filtered-data) | `C_S_TRS_PTY_RLE_REL` | `Read_STG_TRS_D_DC_RELATIONSHIPS`, `rtr_AltId_Exp`, `MPLT_Member_PTY_RLE_REL_Consolidation` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.md#filtered-data) | (no `C_S_*` target) |  |  |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md#filtered-data) | `C_S_TRS_PTY_RLE_REL_PROV` | `Read_STG_TRS_D_IN_MANAGED_CARE`, `Filt_Numeric_Prov`, `Rout_Valid_vs_Exceptions`, `MPLT_Member_PTY_RLE_REL_Consolidation` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md#filtered-data) | `C_S_TRS_PTY_RLE_PHN` | `read_Staging_Delta_Tables`, `fltr_Hold`, `mplt_Phone_Normalization`, `rtr_Valid_Phone_Records`, `mplt_Phone_Consolidation`, `agg_Pty_Rle_Phone` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md#filtered-data) | `C_S_TRS_PTY_RLE_EADDR` | `read_Staging_Delta_Tables`, `fltr_Hold`, `fltr_Null_Emails`, `rtr_Valid_EAddr_Records`, `mplt_EAddr_Consolidation`, `agg_Pty_Rle_Eaddr` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md#filtered-data) | `C_S_TRS_PTY_MNG_ATTR` | `Read_Stg_TRS_D_DC_Indv`, `fltr_Null_Values`, `srtr_Pkey` |  |
| [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md#filtered-data) | `C_S_TRS_PTY_MNG_ATTR` | `Read_STG_TRS_D_DC_Primary_Payee`, `agg_Dedup_TRS_Pty_Mng_Attr` |  |
| [`m_Tgt_C_S_TRS_Pty_Nm`](mappings/m_Tgt_C_S_TRS_Pty_Nm.md#filtered-data) | `C_S_TRS_PTY_NM` | `Read_STG_TRS_D_CV_DC_MCI_Alias`, `fltr_Null_Fn_Ln`, `srtr_Pkey`, `srtr_TRS_Pty_Nm` |  |
| [`m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md#filtered-data) | `C_S_TRS_PTY_RLE_ALT_ID` | `Read_STG_TRS_D_DC_INDV`, `mplt_TRS_Pty_Rle_Alt_Id_Normalization` |  |
| [`m_Tgt_C_S_TRS_Pty_Rle_Pln`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Pln.md#filtered-data) | `C_S_TRS_PTY_RLE_PLN` | `Read_Stg_TRS_D_IN_Managed_Care`, `rtr_Invalid_Plan_Cd`, `agg_Dedup_Rec` | `EXC_STG_BAD_REC_MEMB` |
| [`m_Tgt_C_S_TRS_Addr_1`](mappings/m_Tgt_C_S_TRS_Addr_1.md#filtered-data) | (no `C_S_*` target) |  |  |
| [`m_Tgt_C_S_TRS_Addr_2`](mappings/m_Tgt_C_S_TRS_Addr_2.md#filtered-data) | `C_S_TRS_PTY_RLE_ADDR` | `read_Staging_Delta_Tables`, `rtr_Good_vs_Exception_Pty_Records` | `EXC_STG_BAD_REC_MEMB` |

## Oracle stored procedures

Each mapping also has a drop-in Oracle replacement under [idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/) (conventions, install order and the shared `fn_dq_*` / helper objects: [idq-to-oracle/README.md](../../idq-to-oracle/README.md)). Run them in taskflow order (paths of a *Parallel Paths* step may run in parallel sessions); [run_wf_TRS_Stage_Load_1_Ongoing.sql](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql) runs them one after another. Each mapping spec has an *Oracle stored procedure* section.

| Mapping | Procedure |
|---|---|
| [`m_Tgt_C_S_TRS_Pty_OnGoing`](mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql) |
| [`m_Tgt_C_S_TRS_Pty_Deactivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Deactivation_1.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql) |
| [`m_Tgt_C_S_TRS_Pty_Rle_TOA`](mappings/m_Tgt_C_S_TRS_Pty_Rle_TOA.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql) |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql) |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql) |
| [`m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql) |
| [`m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql) |
| [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql) |
| [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql) |
| [`m_Tgt_C_S_TRS_Pty_Nm`](mappings/m_Tgt_C_S_TRS_Pty_Nm.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm.sql) |
| [`m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql) |
| [`m_Tgt_C_S_TRS_Pty_Rle_Pln`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Pln.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql) |
| [`m_Tgt_C_S_TRS_Addr_1`](mappings/m_Tgt_C_S_TRS_Addr_1.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Addr_1`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Addr_1.sql) |
| [`m_Tgt_C_S_TRS_Addr_2`](mappings/m_Tgt_C_S_TRS_Addr_2.md#oracle-stored-procedure) | [`sp_ors_main_m_Tgt_C_S_TRS_Addr_2`](../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Addr_2.sql) |

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

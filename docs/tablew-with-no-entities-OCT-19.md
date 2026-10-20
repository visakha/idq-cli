# Tables without entities - STG_EXPORT_OCT_16.sql (review of 2026-10-19)

Snapshot for a later review of which `STAGING` tables in `docs/STG_EXPORT_OCT_16.sql` have no Spring Data JDBC
entity in this application, and why.

## Summary

| | Tables |
|---|---|
| Tables in `STG_EXPORT_OCT_16.sql` | 196 |
| With an entity | 28 |
| **Without an entity** | **168** |
| Already removed (file and OCI): `BAK` / date-stamped tables | 17 |
| Already removed (file and OCI): `ZZ*` work tables, test, landing-copy and misc tables | 22 |

How this was determined:

* An entity is a record annotated `@Table("<TABLE>")` anywhere in `src/main/java`.
* None of the tables without an entity is referenced anywhere in `src/main` (queries, lookups, mock data), so
  none of the 33 Member-domain mappings reads or writes them.
* On the OCI `ADMIN` schema all of them were empty when the file was re-applied on 2026-10-19; their DDL
  matches the export column for column.
* No `ZZ*`, `BAK` / `BKP` or date-stamped table is left in the file.

## Breakdown

| Group | Tables |
|---|---|
| Member source systems | 91 |
| Other source systems and the Provider domain | 60 |
| Exceptions and audit | 12 |
| Small reference tables | 5 |
| **Total** | **168** |

## Member source systems (in-scope sources, raw or history tables the mappings do not read)

### STG_TRS_* (65)

TIERS: history (`H_`), last-snapshot (`LS_`), other daily feeds (`D_`), `_A` variants, deactivation and invalid-member
tables. The 12 TRS mappings read other `STG_TRS_*` tables.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_TRS_CV_DC_MCI_ALIAS_A` | 13 | - |
| `STG_TRS_CV_DC_MCI_INDV_A` | 39 | - |
| `STG_TRS_DC_ALIAS` | 15 | - |
| `STG_TRS_DC_ALIAS_A` | 17 | - |
| `STG_TRS_DC_CASE_ADDR` | 37 | CASE_NUM, ADDR_TYPE_CD, EFF_BEGIN_DT |
| `STG_TRS_DC_INDV_A` | 57 | - |
| `STG_TRS_DC_PAYEE` | 29 | CASE_NUM, EDG_NUM |
| `STG_TRS_DEACTIVATED_RELATIONSHIPS` | 14 | PKEY_SRC_OBJECT, LOAD_DATE |
| `STG_TRS_DEACTIVED_REL_HIST` | 13 | - |
| `STG_TRS_DEACTIVED_UNMERGED_RELATIONSHIPS` | 18 | - |
| `STG_TRS_D_ADDR_OVERRIDES` | 73 | - |
| `STG_TRS_D_ADDR_OVERRIDES_MA` | 73 | - |
| `STG_TRS_D_ADDR_OVERRIDES_PA` | 45 | - |
| `STG_TRS_D_DC_ABSENT_PARENTS` | 13 | - |
| `STG_TRS_D_DC_ABS_PAR_ADDR` | 32 | - |
| `STG_TRS_D_DC_CASE_ADDR` | 37 | - |
| `STG_TRS_D_DC_CASE_INDV` | 20 | - |
| `STG_TRS_D_DC_CHILDREN_LINK` | 6 | - |
| `STG_TRS_D_DC_INDV_ADDR` | 39 | - |
| `STG_TRS_D_DC_LTSS_ELIG_PER` | 6 | - |
| `STG_TRS_D_DC_PAYEE` | 29 | - |
| `STG_TRS_D_DC_PREGNANCIES` | 57 | - |
| `STG_TRS_D_DC_RELATIONSHIPS_A` | 29 | - |
| `STG_TRS_D_ED_INDV_ELIG` | 7 | - |
| `STG_TRS_D_IN_MA_EXTRACT` | 68 | - |
| `STG_TRS_D_IN_PROVIDER` | 78 | - |
| `STG_TRS_D_LU_TOA` | 15 | - |
| `STG_TRS_H_ADDR_OVERRIDES` | 73 | - |
| `STG_TRS_H_ADDR_OVERRIDES_MA` | 73 | - |
| `STG_TRS_H_ADDR_OVERRIDES_PA` | 45 | - |
| `STG_TRS_H_CV_DC_MCI_ALIAS` | 14 | - |
| `STG_TRS_H_CV_DC_MCI_INDV` | 41 | - |
| `STG_TRS_H_CV_DC_MRG_SPRT_INDV` | 13 | - |
| `STG_TRS_H_CV_ED_MCI_EDG_INDV` | 24 | - |
| `STG_TRS_H_CV_MCI_EDG_INDV_TOA` | 24 | - |
| `STG_TRS_H_DC_ABSENT_PARENTS` | 13 | - |
| `STG_TRS_H_DC_ABS_PAR_ADDR` | 32 | - |
| `STG_TRS_H_DC_ALIAS` | 15 | - |
| `STG_TRS_H_DC_CASES` | 62 | - |
| `STG_TRS_H_DC_CASE_ADDR` | 37 | - |
| `STG_TRS_H_DC_CASE_INDV` | 20 | - |
| `STG_TRS_H_DC_CHILDREN_LINK` | 6 | - |
| `STG_TRS_H_DC_INDV_ADDR` | 39 | - |
| `STG_TRS_H_DC_LTSS_ELIG_PER` | 6 | - |
| `STG_TRS_H_DC_PAYEE` | 29 | - |
| `STG_TRS_H_DC_PREGNANCIES` | 57 | - |
| `STG_TRS_H_DC_PRIMARY_PAYEE` | 33 | - |
| `STG_TRS_H_DC_RELATIONSHIPS` | 28 | - |
| `STG_TRS_H_DC_RELATIONSHIPS_A` | 30 | - |
| `STG_TRS_H_ED_INDV_ELIG` | 7 | - |
| `STG_TRS_H_INDV_ADDR` | 23 | - |
| `STG_TRS_H_IN_MANAGED_CARE` | 24 | - |
| `STG_TRS_H_IN_PROVIDER` | 78 | - |
| `STG_TRS_INVALID_MEMBERS` | 5 | PTY_PK |
| `STG_TRS_INVALID_RELATIONSHIPS` | 10 | - |
| `STG_TRS_LS_CV_ED_MCI_EDG_INDV` | 24 | - |
| `STG_TRS_LS_DC_ALIAS` | 15 | - |
| `STG_TRS_LS_DC_CASES` | 62 | - |
| `STG_TRS_LS_DC_CASE_ADDR` | 37 | - |
| `STG_TRS_LS_DC_CASE_INDV` | 20 | - |
| `STG_TRS_LS_DC_INDV` | 56 | - |
| `STG_TRS_LS_DC_PAYEE` | 29 | - |
| `STG_TRS_LS_DC_PRIMARY_PAYEE` | 33 | - |
| `STG_TRS_LS_IN_MANAGED_CARE` | 24 | - |
| `STG_TRS_LS_IN_PROVIDER` | 78 | - |

### STG_ECI_* (9)

Raw ECI tables. The ECI mappings read the `V_ECI_ETL_*` views and the `STG_ECI_D_*` tables that have entities.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_ECI_D_CASE` | 27 | - |
| `STG_ECI_D_DISPOSITION` | 12 | - |
| `STG_ECI_D_FAMILY_ADDRESS` | 18 | - |
| `STG_ECI_D_FAMILY_PHONE` | 25 | - |
| `STG_ECI_H_DISPOSITION` | 12 | - |
| `STG_ECI_H_FAMILY_ADDRESS` | 18 | - |
| `STG_ECI_H_MEDICAID` | 14 | - |
| `STG_ECI_SN_DISPOSITION` | 13 | ID_DISPOSITION |
| `STG_ECI_SN_FAMILY_ADDRESS` | 19 | ID_FAMILY_ADDRESS |

### STG_TTF_* (8)

Raw TTF tables. The TTF mappings read the `V_TTF_ETL_SRC` view.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_TTF_D_CLIENTS` | 18 | - |
| `STG_TTF_D_DEMOGRAPHICS` | 37 | - |
| `STG_TTF_D_FYCLIENTS` | 13 | - |
| `STG_TTF_D_LOOKUPGROUPS` | 15 | - |
| `STG_TTF_D_LOOKUPOPTIONS` | 16 | - |
| `STG_TTF_D_SUBMISSIONS` | 19 | - |
| `STG_TTF_H_DEMOGRAPHICS` | 37 | - |
| `STG_TTF_SN_DEM_ALL` | 41 | CLIENTS_ID |

### STG_FSS_* (7)

Raw FSS tables. The FSS mappings read the `V_FSS_ETL_SRC*` views.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_FSS_D_CLIENT` | 23 | - |
| `STG_FSS_D_CLIENT_RACE` | 14 | - |
| `STG_FSS_D_CODES_TABLE` | 16 | - |
| `STG_FSS_D_REGISTRATION` | 38 | - |
| `STG_FSS_D_REGISTRATION_CLIENT` | 50 | - |
| `STG_FSS_H_CODES_TABLE` | 16 | - |
| `STG_FSS_SN_CODES_TABLE` | 17 | CODE, CODE_TYPE |

### STG_WIC_* (2)

Raw WIC tables. The WIC mappings read the `V_WIC_ETL_SRC` view.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_WIC_D_CLIENTS` | 43 | - |
| `STG_WIC_D_FAMILY` | 15 | - |

## Other source systems and the Provider domain (out of scope: Member domain only)

### STG_C21_* (31)

C21 provider data (TPI / NPI, locations, validation).

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_C21_ADR_ADDRESS` | 22 | - |
| `STG_C21_D_PTY_LOC_ADR` | 21 | - |
| `STG_C21_D_PTY_LOC_ASGN_NPI` | 18 | - |
| `STG_C21_D_PTY_LOC_ASGN_PL` | 13 | - |
| `STG_C21_D_PTY_LOC_ASSO` | 12 | - |
| `STG_C21_D_PTY_LOC_ASSO_LIC` | 20 | - |
| `STG_C21_D_PTY_LOC_EADDR` | 13 | - |
| `STG_C21_D_PTY_LOC_PGM_MC` | 14 | - |
| `STG_C21_D_PTY_LOC_PHN` | 15 | - |
| `STG_C21_D_PTY_LOC_PROV` | 16 | - |
| `STG_C21_D_PTY_LOC_PROV_TAX` | 19 | - |
| `STG_C21_D_PTY_LOC_TAXN` | 13 | - |
| `STG_C21_H_ADR_ADDRESS` | 22 | - |
| `STG_C21_H_PRV_NPI_PROVIDER` | 9 | - |
| `STG_C21_H_PRV_PROVIDER` | 11 | - |
| `STG_C21_H_PRV_PROVIDER_APPEND` | 11 | - |
| `STG_C21_H_VAL_VALIDATION` | 17 | - |
| `STG_C21_INVALID_TPI_REF` | 13 | - |
| `STG_C21_PRV_NPI_PROVIDER` | 9 | - |
| `STG_C21_PRV_NPI_PROVIDER_H` | 16 | - |
| `STG_C21_PRV_PL_ADDR_SB` | 31 | - |
| `STG_C21_PRV_PROVIDER` | 11 | - |
| `STG_C21_PRV_PROVIDER_SB` | 19 | - |
| `STG_C21_PRV_PROV_ID_SB` | 16 | - |
| `STG_C21_SN_ADR_ADDRESS` | 22 | ADR_ID |
| `STG_C21_SN_PRV_NPI_PROVIDER` | 9 | NPI_ID, NATIONAL_PROV_ID |
| `STG_C21_SN_PRV_PROVIDER` | 11 | PROV_ID, CREATE_DATE |
| `STG_C21_SN_PRV_PROVIDER_CURR` | 11 | PROV_ID |
| `STG_C21_VALID_TPI` | 12 | - |
| `STG_C21_VALID_TPI_ORG` | 5 | - |
| `STG_C21_VAL_VALIDATION` | 16 | - |

### STG_NE_* (7)

NE contracts and entities.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_NE_D_CONTRACT` | 41 | - |
| `STG_NE_D_CONTRACT_AGENCY` | 17 | - |
| `STG_NE_D_CONTRACT_COUNTY` | 15 | - |
| `STG_NE_D_CONTRACT_SERVICE` | 18 | - |
| `STG_NE_D_ENTITY_ADDRESS` | 26 | - |
| `STG_NE_D_LEGAL_OWNER` | 24 | - |
| `STG_NE_H_ENTITY_ADDRESS` | 26 | - |

### STG_PPS_* (5)

PPS plans, HMOs, service areas.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_PPS_D_HMO` | 8 | - |
| `STG_PPS_D_PLAN` | 19 | - |
| `STG_PPS_D_RISK_GROUP` | 7 | - |
| `STG_PPS_D_SA` | 4 | - |
| `STG_PPS_D_SA_COUNTY` | 5 | - |

### STG_TMC_* (5)

TMC source extracts.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_TMC_D_P23` | 30 | - |
| `STG_TMC_D_P84` | 51 | - |
| `STG_TMC_D_P88` | 51 | - |
| `STG_TMC_D_PMR` | 51 | - |
| `STG_TMC_D_PNR` | 51 | - |

### STG_CRE_* (3)

CRE care cases and clients.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_CRE_D_CARE_CASE_MAINT` | 12 | - |
| `STG_CRE_D_CARE_CLIENTS` | 21 | - |
| `STG_CRE_D_COMP_CASES` | 9 | - |

### STG_VDP_* (3)

VDP vendor drug program.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_VDP_D_VENDOR_DRUG` | 20 | - |
| `STG_VDP_H_VENDOR_DRUG` | 24 | VDP_SK |
| `STG_VDP_VALID_PARTY` | 2 | PTY_PK |

### Taxonomy and provider reference (6)

Provider taxonomy codes and provider reference data.

| Table | Columns | Primary key in export |
|---|---|---|
| `STG_NEP_VALID_PARTY` | 2 | PTY_PK |
| `STG_PROV_REF_DATA` | 10 | - |
| `STG_TXN_D_NUCC_TAXONOMY` | 9 | - |
| `TAXNMY_CODES` | 4 | - |
| `TXNMY_CDS` | 4 | - |
| `TX_CDS` | 2 | - |

## Exceptions and audit

### EXC_* (10)

Provider / reference exception queues and the older `EXC_BAD_RECORDS_*` tables. The Member mappings write only
`EXC_STG_BAD_REC_MEMB`, which has an entity.

| Table | Columns | Primary key in export |
|---|---|---|
| `EXC_BAD_RECORDS_MEMB` | 46 | ROW_IDENTIFIER, WORKFLOW_ID |
| `EXC_BAD_RECORDS_MEMB_ISSUE` | 2 | ROW_IDENTIFIER, WORKFLOW_ID |
| `EXC_BAD_RECORDS_PROV` | 40 | ROW_IDENTIFIER, WORKFLOW_ID |
| `EXC_BAD_RECORDS_PROV_ISSUE` | 4 | ROW_IDENTIFIER, WORKFLOW_ID |
| `EXC_BAD_RECORDS_REF` | 17 | ROW_IDENTIFIER, WORKFLOW_ID |
| `EXC_BAD_RECORDS_REF_ISSUE` | 2 | ROW_IDENTIFIER, WORKFLOW_ID |
| `EXC_BAD_RECORDS_SRC_META` | 14 | - |
| `EXC_STG_BAD_REC_PROV` | 34 | - |
| `EXC_STG_BAD_REC_PROV1` | 31 | - |
| `EXC_STG_BAD_REC_REF` | 11 | - |

### IDD_AUDIT* (2)

IDD audit header and details (`IDD_AUDIT_DETAILS` has a foreign key to `IDD_AUDIT`).

| Table | Columns | Primary key in export |
|---|---|---|
| `IDD_AUDIT` | 13 | AUDIT_ID |
| `IDD_AUDIT_DETAILS` | 5 | - |

## Small reference tables

### REF_* / STG_REF_* (5)

Static reference lists. `STG_REF_PHN_AREA_CD_TEST` looks like a test copy of `REF_PHN_AREA_CD`.

| Table | Columns | Primary key in export |
|---|---|---|
| `REF_ADDR_DOCTOR_STS_CODES` | 4 | - |
| `REF_DYLGHT_SVNGS_TM` | 2 | - |
| `REF_HMO_DAP_NM` | 2 | - |
| `REF_PRV_PLAN_AND_MCO` | 14 | - |
| `STG_REF_PHN_AREA_CD_TEST` | 33 | NPA_ID |

## For comparison: the 28 tables that have an entity

| Table | Entity | Key in export |
|---|---|---|
| `DQM_ADDRESS` | `DqmAddress` | unique: PTY_SRC_KEY, ADDR_SRC_KEY, SRC_SYSTEM, MDM_ADDR_TP |
| `EXC_LOOKUP_CODE_VALUE` | `ReferenceTables.ExceptionCode` | EXC_LOOKUP_CODE_VALUE_ID |
| `EXC_STG_BAD_REC_MEMB` | `BadRecord` | unique: SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, EXCEPTION_TYPE, EXCEPTION_CODE, RUN_DATE |
| `LOOKUP_CODE_VALUE` | `ReferenceTables.CodeValue` | CODE_TYPE, SRC_CODE_VALUE, SRC_SYS |
| `STG_ECI_D_CHILD` | `EciSources.DChild` | ID_CHILD |
| `STG_ECI_D_FAMILY` | `EciSources.DFamily` | ID_FAMILY |
| `STG_ECI_D_MEDICAID` | `EciSources.DMedicaid` | ID_MEDICAID |
| `STG_TRS_CD_REF` | `TrsSources.CdRef` | REF_ID |
| `STG_TRS_CV_ED_MCI_EDG_INDV` | `TrsSources.CvEdMciEdgIndv` | INDV_ID |
| `STG_TRS_DC_CASES` | `TrsSources.DcCases` | CASE_NUM |
| `STG_TRS_DC_CASE_INDV` | `TrsSources.DcCaseIndv` | INDV_ID |
| `STG_TRS_DC_PRIMARY_PAYEE` | `TrsSources.DcPrimaryPayee` | CASE_NUM |
| `STG_TRS_DEACTIVED_MEMBERS` | `TrsSources.DeactivedMembers` | INDV_ID |
| `STG_TRS_D_CV_DC_MCI_ALIAS` | `TrsSources.DCvDcMciAlias` | INDV_ID |
| `STG_TRS_D_CV_DC_MCI_INDV` | `TrsSources.DCvDcMciIndv` | INDV_ID |
| `STG_TRS_D_CV_DC_MRG_SPRT_INDV` | `TrsSources.DCvDcMrgSprtIndv` | INDV_ID |
| `STG_TRS_D_CV_ED_MCI_EDG_INDV` | `TrsSources.DCvEdMciEdgIndv` | INDV_ID |
| `STG_TRS_D_CV_MCI_EDG_INDV_TOA` | `TrsSources.DCvMciEdgIndvToa` | INDV_ID |
| `STG_TRS_D_DC_ALIAS` | `TrsSources.DDcAlias` | INDV_ID |
| `STG_TRS_D_DC_CASES` | `TrsSources.DDcCases` | CASE_NUM |
| `STG_TRS_D_DC_INDV` | `TrsSources.DDcIndv` | INDV_ID |
| `STG_TRS_D_DC_PRIMARY_PAYEE` | `TrsSources.DDcPrimaryPayee` | CASE_NUM |
| `STG_TRS_D_DC_RELATIONSHIPS` | `TrsSources.DDcRelationships` | INDV_ID |
| `STG_TRS_D_INDV_ADDR` | `TrsSources.DIndvAddr` | INDV_ID |
| `STG_TRS_D_IN_MANAGED_CARE` | `TrsSources.DInManagedCare` | INDV_ID |
| `STG_TRS_D_UNQ_ADDR` | `TrsTargets.UniqueAddress` | ADDR_ID |
| `STG_TRS_H_DC_INDV` | `TrsSources.HDcIndv` | INDV_ID |
| `STG_TRS_VALID_MEMBERS` | `TrsTargets.ValidMember` | PTY_PK |

Unique keys (not primary keys): `EXC_STG_BAD_REC_MEMB` and `DQM_ADDRESS` carry composite UNIQUE constraints
because some key columns are NULL by design. Most source-table `@Id`s are still provisional (marked
`/// Provisional @Id` in the code).

## Open points for the review

* `STG_REF_PHN_AREA_CD_TEST` is probably a leftover test copy and a candidate for removal.
* The 60 out-of-scope tables (other source systems, Provider domain) only matter once those domains are ported.
* The 91 Member-source tables are history / snapshot / raw copies of feeds the mappings read through views or
  other tables; entities are only needed if a future mapping, mock-data generator or report reads them.
* The two TRS alias tables (`STG_TRS_D_DC_ALIAS`, `STG_TRS_D_CV_DC_MCI_ALIAS`) have entities but a single-column
  `INDV_ID` primary key, while each individual has two aliases: their key still needs a decision.

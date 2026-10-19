# STG_ECI_PTY_INACTIVE_STS - ECI adhoc run (Java)

| item | value |
| --- | --- |
| source system | ECI (wf_ECI_Stage_Load) |
| etl_process | JAVA |
| run started | 2026-10-19 12:17:22 |
| rows shown per table | up to 200 |
| mock data SQL | `STG_ECI_PTY_INACTIVE_STS_$Java$_19_10_2026_12_17_PM.sql` |

## Mappings that load STG_ECI_PTY_INACTIVE_STS

| seq | mapping | status | rows read | rows written | exceptions | ms | message |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 013 | m_Tgt_C_S_ECI_Pty_Validation | SUCCEEDED | 40 | STG_ECI_PTY_INACTIVE_LOG=1, STG_ECI_PTY_INACTIVE_STS=0, EXC_STG_BAD_REC_MEMB=1 | 1 | 476 |  |

## 013 m_Tgt_C_S_ECI_Pty_Validation

Documentation: `docs/mappings/013_m_Tgt_C_S_ECI_Pty_Validation.md`

### Source tables

#### STG_ECI_D_CHILD (`EciSources.DChild`)

20 rows, 20 shown - rows in the table before the mapping ran

| ID_CHILD | CHILD_SSN | FIRST_NAME | LAST_NAME | MIDDLE_INITIAL | DOB | GESTATION_AGE | GENDER | BIRTH_WT_LB | BIRTH_WT_OZ | INTERPRET_IND | LANGUAGE_CD | RACE_CD | DATE_CREATED | DATE_MODIFIED | MODIFIED_BY | CREATED_BY | ETHNICITY | RACE_WHITE | RACE_AA | RACE_ASIAN | RACE_PI | RACE_AN | LOAD_DATE |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 9100000011 | 123450011 | Test_001-Erwin | Test_001-Weissnat | A | 2025-09-02 12:17:20 |  | F | 7 | 4 |  | 1 |  | 2025-12-09 12:17:20 | 2026-08-01 12:17:20 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:20 |
| 9100000012 | 000123456 | Test_001-Grover | Test_001-Green | A | 2025-09-25 12:17:20 |  | F | 7 | 4 |  | 1 |  | 2025-12-31 12:17:20 | 2026-02-28 12:17:20 | mock | mock | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-19 12:17:20 |
| 9100000013 | 123450013 | Test_001-Megan | Test_001-Schaden | A | 2026-08-28 12:17:20 |  | M | 7 | 4 |  | 1 |  | 2026-07-21 12:17:20 | 2026-07-22 12:17:20 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:20 |
| 9100000014 | 123450014 | Test_001-Danika | Test_001-Zieme | A | 2025-11-10 12:17:21 |  | M | 7 | 4 |  | 1 |  | 2025-01-22 12:17:21 | 2026-03-07 12:17:21 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:21 |
| 9100000015 | 123450015 | Test_001-Carey | Test_001-Mosciski | A | 2024-11-15 12:17:21 |  | M | 7 | 4 |  | 99 |  | 2026-01-08 12:17:21 | 2026-03-22 12:17:21 | mock | mock | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-19 12:17:21 |
| 9100000016 | 000123456 | Test_001-Sanford | Test_001-Mitchell | A | 2024-01-29 12:17:21 |  | F | 7 | 4 |  | 1 |  | 2026-01-11 12:17:21 | 2026-02-09 12:17:21 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:21 |
| 9100000017 | 123450017 | Test_001-Kimbery | Test_001-Cummerata | A | 2025-06-02 12:17:21 |  | F | 7 | 4 |  | 1 |  | 2025-03-27 12:17:21 | 2026-01-18 12:17:21 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:21 |
| 9100000018 | 123450018 | Test_001-Tracee | Test_001-Bailey | A | 2026-04-22 12:17:21 |  | F | 7 | 4 |  | 1 |  | 2026-01-21 12:17:21 | 2026-07-30 12:17:21 | mock | mock | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-19 12:17:21 |
| 9100000019 | 123450019 | Test_001-Mckenzie | Test_001-Cartwright | A | 2024-03-14 12:17:21 |  | F | 7 | 4 |  | 1 |  | 2025-09-28 12:17:21 | 2026-09-13 12:17:21 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:21 |
| 9100000020 | 000123456 | Test_001-Marvella | Test_001-Hackett | A | 2025-06-05 12:17:22 |  | F | 7 | 4 |  | 99 |  | 2024-11-24 12:17:22 | 2026-02-25 12:17:22 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:22 |
| 9100000001 | 123450001 | Test_001-Cristine | Test_001-Brown | A | 2026-04-30 12:17:18 |  | M | 7 | 4 |  | 1 |  | 2026-06-02 12:17:18 | 2026-05-23 12:17:18 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:18 |
| 9100000002 | 123450002 |  | Test_001-Heathcote | A | 2025-09-01 12:17:18 |  | F | 7 | 4 |  | 1 |  | 2025-02-12 12:17:18 | 2026-02-14 12:17:18 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:18 |
| 9100000003 | 123450003 | Test_001-Toshiko | Test_001-Koch | A | 2025-06-08 12:17:18 |  | M | 7 | 4 |  | 1 |  | 2026-04-18 12:17:18 | 2026-05-03 12:17:18 | mock | mock | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-19 12:17:18 |
| 9100000004 | 000123456 | Test_001-Miriam | Test_001-Hane | A | 2023-10-26 12:17:19 |  | F | 7 | 4 |  | 1 |  | 2025-09-02 12:17:19 | 2026-06-07 12:17:19 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:19 |
| 9100000005 | 123450005 | Test_001-Brenna | Test_001-Schumm | A | 2026-08-06 12:17:19 |  | F | 7 | 4 |  | 99 |  | 2026-07-05 12:17:19 | 2026-03-24 12:17:19 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:19 |
| 9100000006 | 123450006 | Test_001-Dulcie | Test_001-Gislason | A | 2024-08-09 12:17:19 |  | M | 7 | 4 |  | 1 |  | 2024-12-18 12:17:19 | 2026-04-17 12:17:19 | mock | mock | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-19 12:17:19 |
| 9100000007 | 123450007 | Test_001-Carlyn | Test_001-Quitzon | A | 2026-06-22 12:17:19 |  | F | 7 | 4 |  | 1 |  | 2025-05-15 12:17:19 | 2025-12-05 12:17:19 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:19 |
| 9100000008 | 000123456 | Test_001-Leilani | Test_001-Murray | A | 2026-05-25 12:17:19 |  | F | 7 | 4 |  | 1 |  | 2025-09-19 12:17:19 | 2026-09-03 12:17:19 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:19 |
| 9100000009 | 123450009 | Test_001-Reggie | Test_001-Kemmer | A | 2026-05-08 12:17:20 |  | F | 7 | 4 |  | 1 |  | 2024-12-21 12:17:20 | 2026-07-07 12:17:20 | mock | mock | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-19 12:17:20 |
| 9100000010 | 123450010 | Test_001-Lesley | Test_001-Littel | A | 2025-09-02 12:17:20 |  | M | 7 | 4 |  | 99 |  | 2026-05-25 12:17:20 | 2025-12-19 12:17:20 | mock | mock | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-19 12:17:20 |

#### STG_ECI_D_FAMILY (`EciSources.DFamily`)

20 rows, 20 shown - rows in the table before the mapping ran

| ID_FAMILY | ID_CHILD | FAMILY_CD | GENDER | EDUCATION_CD | EMPLOY_STATUS_CD | FIRST_NAME | LAST_NAME | MIDDLE_INITIAL | DOB | CHILD_RESIDES_IND | INACTIVE_IND | DATE_CREATED | DATE_MODIFIED | MODIFIED_BY | CREATED_BY | LOAD_DATE |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 9100000011 | 9100000011 | 1 | F |  |  | Test_001-Kieth | Test_001-Kovacek |  | 1987-11-15 12:17:20 |  |  | 2026-06-21 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| 9100000012 | 9100000012 | 1 | F |  |  | Test_001-Lillie | Test_001-Leffler |  | 1992-03-23 12:17:20 |  |  | 2025-04-09 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| 9100000013 | 9100000013 | 1 | F |  |  | Test_001-Samuel | Test_001-Stoltenberg |  | 2000-06-13 12:17:20 |  |  | 2025-06-23 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| 9100000014 | 9100000014 | 1 | F |  |  | Test_001-Santo | Test_001-Schimmel |  | 2013-01-23 12:17:21 |  |  | 2026-04-06 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| 9100000015 | 9100000015 | 1 | F |  |  | Test_001-Galen | Test_001-Becker |  | 2001-05-31 12:17:21 |  |  | 2025-05-16 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| 9100000016 | 9100000016 | 1 | F |  |  | Test_001-Antoinette | Test_001-Dickinson |  | 1988-09-14 12:17:21 |  |  | 2026-01-01 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| 9100000017 | 9100000017 | 1 | F |  |  | Test_001-Martin | Test_001-Cummings |  | 1998-12-27 12:17:21 |  |  | 2025-12-16 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| 9100000018 | 9100000018 | 1 | F |  |  | Test_001-Melina | Test_001-King |  | 2013-12-16 12:17:21 |  |  | 2025-09-15 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| 9100000019 | 9100000019 | 1 | F |  |  | Test_001-Humberto | Test_001-Schumm |  | 1998-01-28 12:17:22 |  |  | 2026-07-09 12:17:22 |  |  |  | 2026-10-19 12:17:22 |
| 9100000020 | 9100000020 | 1 | F |  |  | Test_001-Manie | Test_001-Konopelski |  | 2013-12-10 12:17:22 |  |  | 2026-08-25 12:17:22 |  |  |  | 2026-10-19 12:17:22 |
| 9100000001 | 9100000001 | 1 | F |  |  | Test_001-Lucy | Test_001-Pacocha |  | 2022-11-23 12:17:18 |  |  | 2025-07-27 12:17:18 |  |  |  | 2026-10-19 12:17:18 |
| 9100000002 | 9100000002 | 1 | F |  |  | Test_001-Mana | Test_001-Fay |  | 2017-09-11 12:17:18 |  |  | 2025-10-23 12:17:18 |  |  |  | 2026-10-19 12:17:18 |
| 9100000003 | 9100000003 | 1 | F |  |  | Test_001-Constance | Test_001-Lehner |  | 2022-01-25 12:17:19 |  |  | 2025-08-30 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| 9100000004 | 9100000004 | 1 | F |  |  | Test_001-Cory | Test_001-Maggio |  | 2015-11-08 12:17:19 |  |  | 2025-07-25 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| 9100000005 | 9100000005 | 1 | F |  |  | Test_001-Nannette | Test_001-Gulgowski |  | 2007-08-09 12:17:19 |  |  | 2025-09-09 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| 9100000006 | 9100000006 | 1 | F |  |  | Test_001-Coralee | Test_001-Breitenberg |  | 2007-07-11 12:17:19 |  |  | 2026-04-19 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| 9100000007 | 9100000007 | 1 | F |  |  | Test_001-Jenee | Test_001-Gleichner |  | 2012-08-28 12:17:19 |  |  | 2025-07-14 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| 9100000008 | 9100000008 | 1 | F |  |  | Test_001-Angelo | Test_001-Bernhard |  | 2021-07-26 12:17:19 |  |  | 2024-10-22 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| 9100000009 | 9100000009 | 1 | F |  |  | Test_001-Omar | Test_001-Howell |  | 2017-07-31 12:17:20 |  |  | 2025-07-14 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| 9100000010 | 9100000010 | 1 | F |  |  | Test_001-Kimiko | Test_001-Powlowski |  | 2013-10-13 12:17:20 |  |  | 2026-03-01 12:17:20 |  |  |  | 2026-10-19 12:17:20 |

#### C_B_PTY_XREF (`MdmBaseTables.PartyXref`)

0 rows, 0 shown - rows in the table before the mapping ran

_no rows_

#### STG_ECI_PTY_INACTIVE_STS (`EciTargets.InactiveStatus`)

1 rows, 1 shown - rows in the table before the mapping ran

| SRC_KEY | ROWID_SYSTEM | DEACTIVATION_STS | DEACTIVATION_DT |
| --- | --- | --- | --- |
| 9100000002 | ECI | H | 2026-10-19 03:58:23 |

#### V_ECI_ETL_LU_DUP_CASES (`EciSources.EtlLuDupCases`)

0 rows, 0 shown - rows in the table before the mapping ran

_no rows_

#### V_ECI_ETL_LU_FAMILY_VALIDATION (`EciSources.EtlLuFamilyValidation`)

0 rows, 0 shown - rows in the table before the mapping ran

_no rows_

### IdqMapInitQuery (`EciQueries.PartyName`)

40 rows, 40 shown - rows returned by the IdqMapInitQuery

| SOURCE_TABLE | ID | FIRST_NAME | LAST_NAME | MIDDLE_INITIAL | DOB | DATE_CREATED | DATE_MODIFIED | MODIFIED_BY | CREATED_BY | LOAD_DATE |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI_CHILD | 9100000011 | Test_001-Erwin | Test_001-Weissnat | A | 2025-09-02 12:17:20 | 2025-12-09 12:17:20 | 2026-08-01 12:17:20 | mock | mock | 2026-10-19 12:17:20 |
| ECI_CHILD | 9100000012 | Test_001-Grover | Test_001-Green | A | 2025-09-25 12:17:20 | 2025-12-31 12:17:20 | 2026-02-28 12:17:20 | mock | mock | 2026-10-19 12:17:20 |
| ECI_CHILD | 9100000013 | Test_001-Megan | Test_001-Schaden | A | 2026-08-28 12:17:20 | 2026-07-21 12:17:20 | 2026-07-22 12:17:20 | mock | mock | 2026-10-19 12:17:20 |
| ECI_CHILD | 9100000014 | Test_001-Danika | Test_001-Zieme | A | 2025-11-10 12:17:21 | 2025-01-22 12:17:21 | 2026-03-07 12:17:21 | mock | mock | 2026-10-19 12:17:21 |
| ECI_CHILD | 9100000015 | Test_001-Carey | Test_001-Mosciski | A | 2024-11-15 12:17:21 | 2026-01-08 12:17:21 | 2026-03-22 12:17:21 | mock | mock | 2026-10-19 12:17:21 |
| ECI_CHILD | 9100000016 | Test_001-Sanford | Test_001-Mitchell | A | 2024-01-29 12:17:21 | 2026-01-11 12:17:21 | 2026-02-09 12:17:21 | mock | mock | 2026-10-19 12:17:21 |
| ECI_CHILD | 9100000017 | Test_001-Kimbery | Test_001-Cummerata | A | 2025-06-02 12:17:21 | 2025-03-27 12:17:21 | 2026-01-18 12:17:21 | mock | mock | 2026-10-19 12:17:21 |
| ECI_CHILD | 9100000018 | Test_001-Tracee | Test_001-Bailey | A | 2026-04-22 12:17:21 | 2026-01-21 12:17:21 | 2026-07-30 12:17:21 | mock | mock | 2026-10-19 12:17:21 |
| ECI_CHILD | 9100000019 | Test_001-Mckenzie | Test_001-Cartwright | A | 2024-03-14 12:17:21 | 2025-09-28 12:17:21 | 2026-09-13 12:17:21 | mock | mock | 2026-10-19 12:17:21 |
| ECI_CHILD | 9100000020 | Test_001-Marvella | Test_001-Hackett | A | 2025-06-05 12:17:22 | 2024-11-24 12:17:22 | 2026-02-25 12:17:22 | mock | mock | 2026-10-19 12:17:22 |
| ECI_CHILD | 9100000001 | Test_001-Cristine | Test_001-Brown | A | 2026-04-30 12:17:18 | 2026-06-02 12:17:18 | 2026-05-23 12:17:18 | mock | mock | 2026-10-19 12:17:18 |
| ECI_CHILD | 9100000002 |  | Test_001-Heathcote | A | 2025-09-01 12:17:18 | 2025-02-12 12:17:18 | 2026-02-14 12:17:18 | mock | mock | 2026-10-19 12:17:18 |
| ECI_CHILD | 9100000003 | Test_001-Toshiko | Test_001-Koch | A | 2025-06-08 12:17:18 | 2026-04-18 12:17:18 | 2026-05-03 12:17:18 | mock | mock | 2026-10-19 12:17:18 |
| ECI_CHILD | 9100000004 | Test_001-Miriam | Test_001-Hane | A | 2023-10-26 12:17:19 | 2025-09-02 12:17:19 | 2026-06-07 12:17:19 | mock | mock | 2026-10-19 12:17:19 |
| ECI_CHILD | 9100000005 | Test_001-Brenna | Test_001-Schumm | A | 2026-08-06 12:17:19 | 2026-07-05 12:17:19 | 2026-03-24 12:17:19 | mock | mock | 2026-10-19 12:17:19 |
| ECI_CHILD | 9100000006 | Test_001-Dulcie | Test_001-Gislason | A | 2024-08-09 12:17:19 | 2024-12-18 12:17:19 | 2026-04-17 12:17:19 | mock | mock | 2026-10-19 12:17:19 |
| ECI_CHILD | 9100000007 | Test_001-Carlyn | Test_001-Quitzon | A | 2026-06-22 12:17:19 | 2025-05-15 12:17:19 | 2025-12-05 12:17:19 | mock | mock | 2026-10-19 12:17:19 |
| ECI_CHILD | 9100000008 | Test_001-Leilani | Test_001-Murray | A | 2026-05-25 12:17:19 | 2025-09-19 12:17:19 | 2026-09-03 12:17:19 | mock | mock | 2026-10-19 12:17:19 |
| ECI_CHILD | 9100000009 | Test_001-Reggie | Test_001-Kemmer | A | 2026-05-08 12:17:20 | 2024-12-21 12:17:20 | 2026-07-07 12:17:20 | mock | mock | 2026-10-19 12:17:20 |
| ECI_CHILD | 9100000010 | Test_001-Lesley | Test_001-Littel | A | 2025-09-02 12:17:20 | 2026-05-25 12:17:20 | 2025-12-19 12:17:20 | mock | mock | 2026-10-19 12:17:20 |
| ECI_FAMILY | 9100000011 | Test_001-Kieth | Test_001-Kovacek |  | 1987-11-15 12:17:20 | 2026-06-21 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| ECI_FAMILY | 9100000012 | Test_001-Lillie | Test_001-Leffler |  | 1992-03-23 12:17:20 | 2025-04-09 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| ECI_FAMILY | 9100000013 | Test_001-Samuel | Test_001-Stoltenberg |  | 2000-06-13 12:17:20 | 2025-06-23 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| ECI_FAMILY | 9100000014 | Test_001-Santo | Test_001-Schimmel |  | 2013-01-23 12:17:21 | 2026-04-06 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| ECI_FAMILY | 9100000015 | Test_001-Galen | Test_001-Becker |  | 2001-05-31 12:17:21 | 2025-05-16 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| ECI_FAMILY | 9100000016 | Test_001-Antoinette | Test_001-Dickinson |  | 1988-09-14 12:17:21 | 2026-01-01 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| ECI_FAMILY | 9100000017 | Test_001-Martin | Test_001-Cummings |  | 1998-12-27 12:17:21 | 2025-12-16 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| ECI_FAMILY | 9100000018 | Test_001-Melina | Test_001-King |  | 2013-12-16 12:17:21 | 2025-09-15 12:17:21 |  |  |  | 2026-10-19 12:17:21 |
| ECI_FAMILY | 9100000019 | Test_001-Humberto | Test_001-Schumm |  | 1998-01-28 12:17:22 | 2026-07-09 12:17:22 |  |  |  | 2026-10-19 12:17:22 |
| ECI_FAMILY | 9100000020 | Test_001-Manie | Test_001-Konopelski |  | 2013-12-10 12:17:22 | 2026-08-25 12:17:22 |  |  |  | 2026-10-19 12:17:22 |
| ECI_FAMILY | 9100000001 | Test_001-Lucy | Test_001-Pacocha |  | 2022-11-23 12:17:18 | 2025-07-27 12:17:18 |  |  |  | 2026-10-19 12:17:18 |
| ECI_FAMILY | 9100000002 | Test_001-Mana | Test_001-Fay |  | 2017-09-11 12:17:18 | 2025-10-23 12:17:18 |  |  |  | 2026-10-19 12:17:18 |
| ECI_FAMILY | 9100000003 | Test_001-Constance | Test_001-Lehner |  | 2022-01-25 12:17:19 | 2025-08-30 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| ECI_FAMILY | 9100000004 | Test_001-Cory | Test_001-Maggio |  | 2015-11-08 12:17:19 | 2025-07-25 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| ECI_FAMILY | 9100000005 | Test_001-Nannette | Test_001-Gulgowski |  | 2007-08-09 12:17:19 | 2025-09-09 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| ECI_FAMILY | 9100000006 | Test_001-Coralee | Test_001-Breitenberg |  | 2007-07-11 12:17:19 | 2026-04-19 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| ECI_FAMILY | 9100000007 | Test_001-Jenee | Test_001-Gleichner |  | 2012-08-28 12:17:19 | 2025-07-14 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| ECI_FAMILY | 9100000008 | Test_001-Angelo | Test_001-Bernhard |  | 2021-07-26 12:17:19 | 2024-10-22 12:17:19 |  |  |  | 2026-10-19 12:17:19 |
| ECI_FAMILY | 9100000009 | Test_001-Omar | Test_001-Howell |  | 2017-07-31 12:17:20 | 2025-07-14 12:17:20 |  |  |  | 2026-10-19 12:17:20 |
| ECI_FAMILY | 9100000010 | Test_001-Kimiko | Test_001-Powlowski |  | 2013-10-13 12:17:20 | 2026-03-01 12:17:20 |  |  |  | 2026-10-19 12:17:20 |

### Target STG_ECI_PTY_INACTIVE_STS

#### STG_ECI_PTY_INACTIVE_STS (`EciTargets.InactiveStatus`)

0 rows, 0 shown - rows deleted by key

_no rows_

#### STG_ECI_PTY_INACTIVE_STS (`EciTargets.InactiveStatus`)

0 rows, 0 shown - rows loaded by this run, read back from the table by key

_no rows_

### EXC_STG_BAD_REC_MEMB (`BadRecord`)

1 rows, 1 shown - rows appended (the table has no key to read them back by)

| SRC_SYS | SRC_SYS_ID_1 | SRC_SYS_ID_2 | SRC_SYS_ID_3 | EXCEPTION_TYPE | EXCEPTION_CODE | EXCEPTION_DESC | RUN_DATE | PREFIX | FIRST_NAME | MIDDLE_NAME | LAST_NAME | SUFFIX | ALIAS_SUFFIX | BIRTH_DATE | GENDER | ADDRESS_TYPE | ADDRESS_LINE_1 | ADDRESS_LINE_2 | ADDRESS_CITY | ADDRESS_COUNTY | ADDRESS_STATE | ADDRESS_ZIP | ADDRESS_ZIP_EXT | ADDRESS_COUNTRY | ADDRESS_DR_ERROR_CODE | ADDRESS_DR_ERROR_DESC | ADDRESS_DR_MAILABILITY_SCORE | PRIMARY_PHONE | WORK_PHONE | SECONDARY_PHONE | EMAIL | ATTRIBUTE_NAME | ATTRIBUTE_VALUE | MAPPING_NAME | PERIOD_START_DATE | PERIOD_END_DATE | DEATH_DT |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI | 9100000002 |  |  | Bad Value | Missing_First_Name | Missing First Name | 2026-10-19 12:17:22 |  |  | A | Test |  |  | 2025-09-01 12:17:18 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | First Name |  | m_Tgt_C_S_ECI_Pty_Validation | 2025-02-12 12:17:18 |  |  |


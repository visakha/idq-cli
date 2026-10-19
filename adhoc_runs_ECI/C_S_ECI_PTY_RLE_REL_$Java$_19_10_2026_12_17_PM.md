# C_S_ECI_PTY_RLE_REL - ECI adhoc run (Java)

| item | value |
| --- | --- |
| source system | ECI (wf_ECI_Stage_Load) |
| etl_process | JAVA |
| run started | 2026-10-19 12:17:22 |
| rows shown per table | up to 200 |
| mock data SQL | `C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_12_17_PM.sql` |

## Mappings that load C_S_ECI_PTY_RLE_REL

| seq | mapping | status | rows read | rows written | exceptions | ms | message |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 018 | m_Tgt_C_S_ECI_Pty_Rle_Rel | SUCCEEDED | 40 | C_S_ECI_PTY_RLE_REL=38 | 0 | 391 |  |

## 018 m_Tgt_C_S_ECI_Pty_Rle_Rel

Documentation: `docs/mappings/018_m_Tgt_C_S_ECI_Pty_Rle_Rel.md`

### Source tables

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

#### STG_ECI_SN_CHILD (`EciSources.SnChild`)

20 rows, 20 shown - rows in the table before the mapping ran

| ID_CHILD | CHILD_SSN | FIRST_NAME | LAST_NAME | MIDDLE_INITIAL | DOB | GESTATION_AGE | GENDER | BIRTH_WT_LB | BIRTH_WT_OZ | INTERPRET_IND | LANGUAGE_CD | RACE_CD | DATE_CREATED | DATE_MODIFIED | MODIFIED_BY | CREATED_BY | ETHNICITY | RACE_WHITE | RACE_AA | RACE_ASIAN | RACE_PI | RACE_AN |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 9100000011 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000012 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000013 |  |  |  |  |  |  | M |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000014 |  |  |  |  |  |  | M |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000015 |  |  |  |  |  |  | M |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000016 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000017 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000018 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000019 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000020 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000001 |  |  |  |  |  |  | M |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000002 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000003 |  |  |  |  |  |  | M |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000004 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000005 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000006 |  |  |  |  |  |  | M |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000007 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000008 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000009 |  |  |  |  |  |  | F |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 9100000010 |  |  |  |  |  |  | M |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |

#### STG_ECI_PTY_INACTIVE_STS (`EciTargets.InactiveStatus`)

1 rows, 1 shown - rows in the table before the mapping ran

| SRC_KEY | ROWID_SYSTEM | DEACTIVATION_STS | DEACTIVATION_DT |
| --- | --- | --- | --- |
| 9100000002 | ECI | H | 2026-10-19 03:58:23 |

### IdqMapInitQuery (`EciQueries.FamilyRelation`)

40 rows, 40 shown - rows returned by the IdqMapInitQuery

| RELATION_DIRECTION | ID_FAMILY | FAMILY_GENDER | ID_CHILD | FAMILY_CD | DATE_MODIFIED | DATE_CREATED |
| --- | --- | --- | --- | --- | --- | --- |
| From Child | 9100000011 | F | 9100000011 | 1 | 2026-06-21 12:17:20 | 2026-06-21 12:17:20 |
| From Child | 9100000012 | F | 9100000012 | 1 | 2025-04-09 12:17:20 | 2025-04-09 12:17:20 |
| From Child | 9100000013 | F | 9100000013 | 1 | 2025-06-23 12:17:20 | 2025-06-23 12:17:20 |
| From Child | 9100000014 | F | 9100000014 | 1 | 2026-04-06 12:17:21 | 2026-04-06 12:17:21 |
| From Child | 9100000015 | F | 9100000015 | 1 | 2025-05-16 12:17:21 | 2025-05-16 12:17:21 |
| From Child | 9100000016 | F | 9100000016 | 1 | 2026-01-01 12:17:21 | 2026-01-01 12:17:21 |
| From Child | 9100000017 | F | 9100000017 | 1 | 2025-12-16 12:17:21 | 2025-12-16 12:17:21 |
| From Child | 9100000018 | F | 9100000018 | 1 | 2025-09-15 12:17:21 | 2025-09-15 12:17:21 |
| From Child | 9100000019 | F | 9100000019 | 1 | 2026-07-09 12:17:22 | 2026-07-09 12:17:22 |
| From Child | 9100000020 | F | 9100000020 | 1 | 2026-08-25 12:17:22 | 2026-08-25 12:17:22 |
| From Child | 9100000001 | F | 9100000001 | 1 | 2025-07-27 12:17:18 | 2025-07-27 12:17:18 |
| From Child | 9100000002 | F | 9100000002 | 1 | 2025-10-23 12:17:18 | 2025-10-23 12:17:18 |
| From Child | 9100000003 | F | 9100000003 | 1 | 2025-08-30 12:17:19 | 2025-08-30 12:17:19 |
| From Child | 9100000004 | F | 9100000004 | 1 | 2025-07-25 12:17:19 | 2025-07-25 12:17:19 |
| From Child | 9100000005 | F | 9100000005 | 1 | 2025-09-09 12:17:19 | 2025-09-09 12:17:19 |
| From Child | 9100000006 | F | 9100000006 | 1 | 2026-04-19 12:17:19 | 2026-04-19 12:17:19 |
| From Child | 9100000007 | F | 9100000007 | 1 | 2025-07-14 12:17:19 | 2025-07-14 12:17:19 |
| From Child | 9100000008 | F | 9100000008 | 1 | 2024-10-22 12:17:19 | 2024-10-22 12:17:19 |
| From Child | 9100000009 | F | 9100000009 | 1 | 2025-07-14 12:17:20 | 2025-07-14 12:17:20 |
| From Child | 9100000010 | F | 9100000010 | 1 | 2026-03-01 12:17:20 | 2026-03-01 12:17:20 |
| To Child | 9100000011 | F | 9100000011 | 1 | 2026-06-21 12:17:20 | 2026-06-21 12:17:20 |
| To Child | 9100000012 | F | 9100000012 | 1 | 2025-04-09 12:17:20 | 2025-04-09 12:17:20 |
| To Child | 9100000013 | F | 9100000013 | 1 | 2025-06-23 12:17:20 | 2025-06-23 12:17:20 |
| To Child | 9100000014 | F | 9100000014 | 1 | 2026-04-06 12:17:21 | 2026-04-06 12:17:21 |
| To Child | 9100000015 | F | 9100000015 | 1 | 2025-05-16 12:17:21 | 2025-05-16 12:17:21 |
| To Child | 9100000016 | F | 9100000016 | 1 | 2026-01-01 12:17:21 | 2026-01-01 12:17:21 |
| To Child | 9100000017 | F | 9100000017 | 1 | 2025-12-16 12:17:21 | 2025-12-16 12:17:21 |
| To Child | 9100000018 | F | 9100000018 | 1 | 2025-09-15 12:17:21 | 2025-09-15 12:17:21 |
| To Child | 9100000019 | F | 9100000019 | 1 | 2026-07-09 12:17:22 | 2026-07-09 12:17:22 |
| To Child | 9100000020 | F | 9100000020 | 1 | 2026-08-25 12:17:22 | 2026-08-25 12:17:22 |
| To Child | 9100000001 | F | 9100000001 | 1 | 2025-07-27 12:17:18 | 2025-07-27 12:17:18 |
| To Child | 9100000002 | F | 9100000002 | 1 | 2025-10-23 12:17:18 | 2025-10-23 12:17:18 |
| To Child | 9100000003 | F | 9100000003 | 1 | 2025-08-30 12:17:19 | 2025-08-30 12:17:19 |
| To Child | 9100000004 | F | 9100000004 | 1 | 2025-07-25 12:17:19 | 2025-07-25 12:17:19 |
| To Child | 9100000005 | F | 9100000005 | 1 | 2025-09-09 12:17:19 | 2025-09-09 12:17:19 |
| To Child | 9100000006 | F | 9100000006 | 1 | 2026-04-19 12:17:19 | 2026-04-19 12:17:19 |
| To Child | 9100000007 | F | 9100000007 | 1 | 2025-07-14 12:17:19 | 2025-07-14 12:17:19 |
| To Child | 9100000008 | F | 9100000008 | 1 | 2024-10-22 12:17:19 | 2024-10-22 12:17:19 |
| To Child | 9100000009 | F | 9100000009 | 1 | 2025-07-14 12:17:20 | 2025-07-14 12:17:20 |
| To Child | 9100000010 | F | 9100000010 | 1 | 2026-03-01 12:17:20 | 2026-03-01 12:17:20 |

### Target C_S_ECI_PTY_RLE_REL

#### C_S_ECI_PTY_RLE_REL (`EciTargets.Relationship`)

38 rows, 38 shown - rows loaded by this run, read back from the table by key

| PKEY_SRC_OBJECT | PERIOD_START_DATE | PERIOD_END_DATE | LAST_UPDATE_DATE | CREATE_DATE | CREATOR | UPDATED_BY | SRC_ROWID | HUB_STATE_IND | SRC_LAST_UPD_DT | PTY_RLE_FK_1 | PTY_RLE_FK_2 | REL_TYPE_CODE | HIERARCHY_CODE | REL_TP |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 9100000011\|Member\|9100000011F\|Member\|DAU | 2026-06-21 12:17:20 |  | 2026-10-19 12:17:22 | 2026-06-21 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000011\|Member\|9100000011F\| | 1 | 2026-06-21 12:17:20 | 9100000011\|Member | 9100000011F\|Member | Member Relationship | Member | DAU |
| 9100000012\|Member\|9100000012F\|Member\|DAU | 2025-04-09 12:17:20 |  | 2026-10-19 12:17:22 | 2025-04-09 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000012\|Member\|9100000012F\| | 1 | 2025-04-09 12:17:20 | 9100000012\|Member | 9100000012F\|Member | Member Relationship | Member | DAU |
| 9100000013\|Member\|9100000013F\|Member\|SON | 2025-06-23 12:17:20 |  | 2026-10-19 12:17:22 | 2025-06-23 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000013\|Member\|9100000013F\| | 1 | 2025-06-23 12:17:20 | 9100000013\|Member | 9100000013F\|Member | Member Relationship | Member | SON |
| 9100000014\|Member\|9100000014F\|Member\|SON | 2026-04-06 12:17:21 |  | 2026-10-19 12:17:22 | 2026-04-06 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000014\|Member\|9100000014F\| | 1 | 2026-04-06 12:17:21 | 9100000014\|Member | 9100000014F\|Member | Member Relationship | Member | SON |
| 9100000015\|Member\|9100000015F\|Member\|SON | 2025-05-16 12:17:21 |  | 2026-10-19 12:17:22 | 2025-05-16 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000015\|Member\|9100000015F\| | 1 | 2025-05-16 12:17:21 | 9100000015\|Member | 9100000015F\|Member | Member Relationship | Member | SON |
| 9100000016\|Member\|9100000016F\|Member\|DAU | 2026-01-01 12:17:21 |  | 2026-10-19 12:17:22 | 2026-01-01 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000016\|Member\|9100000016F\| | 1 | 2026-01-01 12:17:21 | 9100000016\|Member | 9100000016F\|Member | Member Relationship | Member | DAU |
| 9100000017\|Member\|9100000017F\|Member\|DAU | 2025-12-16 12:17:21 |  | 2026-10-19 12:17:22 | 2025-12-16 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000017\|Member\|9100000017F\| | 1 | 2025-12-16 12:17:21 | 9100000017\|Member | 9100000017F\|Member | Member Relationship | Member | DAU |
| 9100000018\|Member\|9100000018F\|Member\|DAU | 2025-09-15 12:17:21 |  | 2026-10-19 12:17:22 | 2025-09-15 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000018\|Member\|9100000018F\| | 1 | 2025-09-15 12:17:21 | 9100000018\|Member | 9100000018F\|Member | Member Relationship | Member | DAU |
| 9100000019\|Member\|9100000019F\|Member\|DAU | 2026-07-09 12:17:22 |  | 2026-10-19 12:17:22 | 2026-07-09 12:17:22 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000019\|Member\|9100000019F\| | 1 | 2026-07-09 12:17:22 | 9100000019\|Member | 9100000019F\|Member | Member Relationship | Member | DAU |
| 9100000020\|Member\|9100000020F\|Member\|DAU | 2026-08-25 12:17:22 |  | 2026-10-19 12:17:22 | 2026-08-25 12:17:22 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000020\|Member\|9100000020F\| | 1 | 2026-08-25 12:17:22 | 9100000020\|Member | 9100000020F\|Member | Member Relationship | Member | DAU |
| 9100000001\|Member\|9100000001F\|Member\|SON | 2025-07-27 12:17:18 |  | 2026-10-19 12:17:22 | 2025-07-27 12:17:18 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000001\|Member\|9100000001F\| | 1 | 2025-07-27 12:17:18 | 9100000001\|Member | 9100000001F\|Member | Member Relationship | Member | SON |
| 9100000003\|Member\|9100000003F\|Member\|SON | 2025-08-30 12:17:19 |  | 2026-10-19 12:17:22 | 2025-08-30 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000003\|Member\|9100000003F\| | 1 | 2025-08-30 12:17:19 | 9100000003\|Member | 9100000003F\|Member | Member Relationship | Member | SON |
| 9100000004\|Member\|9100000004F\|Member\|DAU | 2025-07-25 12:17:19 |  | 2026-10-19 12:17:22 | 2025-07-25 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000004\|Member\|9100000004F\| | 1 | 2025-07-25 12:17:19 | 9100000004\|Member | 9100000004F\|Member | Member Relationship | Member | DAU |
| 9100000005\|Member\|9100000005F\|Member\|DAU | 2025-09-09 12:17:19 |  | 2026-10-19 12:17:22 | 2025-09-09 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000005\|Member\|9100000005F\| | 1 | 2025-09-09 12:17:19 | 9100000005\|Member | 9100000005F\|Member | Member Relationship | Member | DAU |
| 9100000006\|Member\|9100000006F\|Member\|SON | 2026-04-19 12:17:19 |  | 2026-10-19 12:17:22 | 2026-04-19 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000006\|Member\|9100000006F\| | 1 | 2026-04-19 12:17:19 | 9100000006\|Member | 9100000006F\|Member | Member Relationship | Member | SON |
| 9100000007\|Member\|9100000007F\|Member\|DAU | 2025-07-14 12:17:19 |  | 2026-10-19 12:17:22 | 2025-07-14 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000007\|Member\|9100000007F\| | 1 | 2025-07-14 12:17:19 | 9100000007\|Member | 9100000007F\|Member | Member Relationship | Member | DAU |
| 9100000008\|Member\|9100000008F\|Member\|DAU | 2024-10-22 12:17:19 |  | 2026-10-19 12:17:22 | 2024-10-22 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000008\|Member\|9100000008F\| | 1 | 2024-10-22 12:17:19 | 9100000008\|Member | 9100000008F\|Member | Member Relationship | Member | DAU |
| 9100000009\|Member\|9100000009F\|Member\|DAU | 2025-07-14 12:17:20 |  | 2026-10-19 12:17:22 | 2025-07-14 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000009\|Member\|9100000009F\| | 1 | 2025-07-14 12:17:20 | 9100000009\|Member | 9100000009F\|Member | Member Relationship | Member | DAU |
| 9100000010\|Member\|9100000010F\|Member\|SON | 2026-03-01 12:17:20 |  | 2026-10-19 12:17:22 | 2026-03-01 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000010\|Member\|9100000010F\| | 1 | 2026-03-01 12:17:20 | 9100000010\|Member | 9100000010F\|Member | Member Relationship | Member | SON |
| 9100000011F\|Member\|9100000011\|Member\|MTH | 2026-06-21 12:17:20 |  | 2026-10-19 12:17:22 | 2026-06-21 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000011F\|Member\|9100000011\| | 1 | 2026-06-21 12:17:20 | 9100000011F\|Member | 9100000011\|Member | Member Relationship | Member | MTH |
| 9100000012F\|Member\|9100000012\|Member\|MTH | 2025-04-09 12:17:20 |  | 2026-10-19 12:17:22 | 2025-04-09 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000012F\|Member\|9100000012\| | 1 | 2025-04-09 12:17:20 | 9100000012F\|Member | 9100000012\|Member | Member Relationship | Member | MTH |
| 9100000013F\|Member\|9100000013\|Member\|MTH | 2025-06-23 12:17:20 |  | 2026-10-19 12:17:22 | 2025-06-23 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000013F\|Member\|9100000013\| | 1 | 2025-06-23 12:17:20 | 9100000013F\|Member | 9100000013\|Member | Member Relationship | Member | MTH |
| 9100000014F\|Member\|9100000014\|Member\|MTH | 2026-04-06 12:17:21 |  | 2026-10-19 12:17:22 | 2026-04-06 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000014F\|Member\|9100000014\| | 1 | 2026-04-06 12:17:21 | 9100000014F\|Member | 9100000014\|Member | Member Relationship | Member | MTH |
| 9100000015F\|Member\|9100000015\|Member\|MTH | 2025-05-16 12:17:21 |  | 2026-10-19 12:17:22 | 2025-05-16 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000015F\|Member\|9100000015\| | 1 | 2025-05-16 12:17:21 | 9100000015F\|Member | 9100000015\|Member | Member Relationship | Member | MTH |
| 9100000016F\|Member\|9100000016\|Member\|MTH | 2026-01-01 12:17:21 |  | 2026-10-19 12:17:22 | 2026-01-01 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000016F\|Member\|9100000016\| | 1 | 2026-01-01 12:17:21 | 9100000016F\|Member | 9100000016\|Member | Member Relationship | Member | MTH |
| 9100000017F\|Member\|9100000017\|Member\|MTH | 2025-12-16 12:17:21 |  | 2026-10-19 12:17:22 | 2025-12-16 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000017F\|Member\|9100000017\| | 1 | 2025-12-16 12:17:21 | 9100000017F\|Member | 9100000017\|Member | Member Relationship | Member | MTH |
| 9100000018F\|Member\|9100000018\|Member\|MTH | 2025-09-15 12:17:21 |  | 2026-10-19 12:17:22 | 2025-09-15 12:17:21 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000018F\|Member\|9100000018\| | 1 | 2025-09-15 12:17:21 | 9100000018F\|Member | 9100000018\|Member | Member Relationship | Member | MTH |
| 9100000019F\|Member\|9100000019\|Member\|MTH | 2026-07-09 12:17:22 |  | 2026-10-19 12:17:22 | 2026-07-09 12:17:22 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000019F\|Member\|9100000019\| | 1 | 2026-07-09 12:17:22 | 9100000019F\|Member | 9100000019\|Member | Member Relationship | Member | MTH |
| 9100000020F\|Member\|9100000020\|Member\|MTH | 2026-08-25 12:17:22 |  | 2026-10-19 12:17:22 | 2026-08-25 12:17:22 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000020F\|Member\|9100000020\| | 1 | 2026-08-25 12:17:22 | 9100000020F\|Member | 9100000020\|Member | Member Relationship | Member | MTH |
| 9100000001F\|Member\|9100000001\|Member\|MTH | 2025-07-27 12:17:18 |  | 2026-10-19 12:17:22 | 2025-07-27 12:17:18 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000001F\|Member\|9100000001\| | 1 | 2025-07-27 12:17:18 | 9100000001F\|Member | 9100000001\|Member | Member Relationship | Member | MTH |
| 9100000003F\|Member\|9100000003\|Member\|MTH | 2025-08-30 12:17:19 |  | 2026-10-19 12:17:22 | 2025-08-30 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000003F\|Member\|9100000003\| | 1 | 2025-08-30 12:17:19 | 9100000003F\|Member | 9100000003\|Member | Member Relationship | Member | MTH |
| 9100000004F\|Member\|9100000004\|Member\|MTH | 2025-07-25 12:17:19 |  | 2026-10-19 12:17:22 | 2025-07-25 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000004F\|Member\|9100000004\| | 1 | 2025-07-25 12:17:19 | 9100000004F\|Member | 9100000004\|Member | Member Relationship | Member | MTH |
| 9100000005F\|Member\|9100000005\|Member\|MTH | 2025-09-09 12:17:19 |  | 2026-10-19 12:17:22 | 2025-09-09 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000005F\|Member\|9100000005\| | 1 | 2025-09-09 12:17:19 | 9100000005F\|Member | 9100000005\|Member | Member Relationship | Member | MTH |
| 9100000006F\|Member\|9100000006\|Member\|MTH | 2026-04-19 12:17:19 |  | 2026-10-19 12:17:22 | 2026-04-19 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000006F\|Member\|9100000006\| | 1 | 2026-04-19 12:17:19 | 9100000006F\|Member | 9100000006\|Member | Member Relationship | Member | MTH |
| 9100000007F\|Member\|9100000007\|Member\|MTH | 2025-07-14 12:17:19 |  | 2026-10-19 12:17:22 | 2025-07-14 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000007F\|Member\|9100000007\| | 1 | 2025-07-14 12:17:19 | 9100000007F\|Member | 9100000007\|Member | Member Relationship | Member | MTH |
| 9100000008F\|Member\|9100000008\|Member\|MTH | 2024-10-22 12:17:19 |  | 2026-10-19 12:17:22 | 2024-10-22 12:17:19 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000008F\|Member\|9100000008\| | 1 | 2024-10-22 12:17:19 | 9100000008F\|Member | 9100000008\|Member | Member Relationship | Member | MTH |
| 9100000009F\|Member\|9100000009\|Member\|MTH | 2025-07-14 12:17:20 |  | 2026-10-19 12:17:22 | 2025-07-14 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000009F\|Member\|9100000009\| | 1 | 2025-07-14 12:17:20 | 9100000009F\|Member | 9100000009\|Member | Member Relationship | Member | MTH |
| 9100000010F\|Member\|9100000010\|Member\|MTH | 2026-03-01 12:17:20 |  | 2026-10-19 12:17:22 | 2026-03-01 12:17:20 | m_Tgt_C_S_ECI_Pty_Rle_Rel | m_Tgt_C_S_ECI_Pty_Rle_Rel | 9100000010F\|Member\|9100000010\| | 1 | 2026-03-01 12:17:20 | 9100000010F\|Member | 9100000010\|Member | Member Relationship | Member | MTH |


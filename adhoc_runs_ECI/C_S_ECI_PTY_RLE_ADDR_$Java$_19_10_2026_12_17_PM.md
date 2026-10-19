# C_S_ECI_PTY_RLE_ADDR - ECI adhoc run (Java)

| item | value |
| --- | --- |
| source system | ECI (wf_ECI_Stage_Load) |
| etl_process | JAVA |
| run started | 2026-10-19 12:17:22 |
| rows shown per table | up to 200 |
| mock data SQL | `C_S_ECI_PTY_RLE_ADDR_$Java$_19_10_2026_12_17_PM.sql` |

## Mappings that load C_S_ECI_PTY_RLE_ADDR

| seq | mapping | status | rows read | rows written | exceptions | ms | message |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 015 | m_Tgt_C_S_ECI_Pty_Addr | SUCCEEDED | 20 | DQM_ADDRESS=20, C_S_ECI_PTY_RLE_ADDR=17, EXC_STG_BAD_REC_MEMB=3 | 3 | 454 |  |

## 015 m_Tgt_C_S_ECI_Pty_Addr

Documentation: `docs/mappings/015_m_Tgt_C_S_ECI_Pty_Addr.md`

### Source tables

#### V_ECI_ETL_SRC_FAMILY_ADDRESS (`EciSources.EtlSrcFamilyAddress`)

20 rows, 20 shown - rows in the table before the mapping ran

| SOURCE_TABLE | ID | ID_FAMILY_ADDRESS | ADDRESS1 | ADDRESS2 | ADDRESS_CD | CITY_NAME | COUNTY_NAME | STATE_ABBREV | ZIP_CODE | ZIP_SFX | LAST_UPDATE_DATE | ADDR_TP |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI_CHILD | 9100000001 | 501 | Test_001-34374 Lourie Neck |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-14 12:17:08 |  |
| ECI_FAMILY | 9100000002 | 502 | Test_001-9476 Jacobson Brook |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-12-09 12:17:08 |  |
| ECI_CHILD | 9100000003 | 503 | Test_001-875 Antonio Stravenue | Test_001-Suite 4 | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-11 12:17:08 |  |
| ECI_FAMILY | 9100000004 | 504 | Test_001-2027 Feest Road |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-12-09 12:17:09 |  |
| ECI_CHILD | 9100000005 | 505 | Test_001-5795 Darryl Ports |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-10-27 12:17:09 |  |
| ECI_FAMILY | 9100000006 | 506 | Test_001-462 Stacey Junctions | Test_001-Suite 4 | 9 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-02 12:17:09 |  |
| ECI_CHILD | 9100000007 | 507 | Test_001-8142 Jast Courts |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-05 12:17:09 |  |
| ECI_FAMILY | 9100000008 | 508 | Test_001-619 Torphy Causeway |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-05-04 12:17:09 |  |
| ECI_CHILD | 9100000009 | 509 | Test_001-3248 Tromp Stream | Test_001-Suite 4 | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-06 12:17:09 |  |
| ECI_FAMILY | 9100000010 | 510 | Test_001-108 Langworth Drives |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-04-03 12:17:09 |  |
| ECI_CHILD | 9100000011 | 511 | Test_001-17457 O'Hara Row |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-12-23 12:17:09 |  |
| ECI_FAMILY | 9100000012 | 512 | Test_001-5372 Hettinger Meadow | Test_001-Suite 4 | 9 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-02-16 12:17:09 |  |
| ECI_CHILD | 9100000013 | 513 | Test_001-544 Clint Lane |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-31 12:17:09 |  |
| ECI_FAMILY | 9100000014 | 514 | Test_001-088 Leigha Motorway |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-08-29 12:17:09 |  |
| ECI_CHILD | 9100000015 | 515 | Test_001-40189 Jerde Curve | Test_001-Suite 4 | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-11-07 12:17:09 |  |
| ECI_FAMILY | 9100000016 | 516 | Test_001-904 Konopelski Shores |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-05-31 12:17:09 |  |
| ECI_CHILD | 9100000017 | 517 | Test_001-828 Schneider Motorway |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-11-09 12:17:10 |  |
| ECI_FAMILY | 9100000018 | 518 | Test_001-2638 Harber Forges | Test_001-Suite 4 | 9 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-08-19 12:17:10 |  |
| ECI_CHILD | 9100000019 | 519 | Test_001-7275 Feest Road |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-18 12:17:10 |  |
| ECI_FAMILY | 9100000020 | 520 | Test_001-44248 Bradley Isle |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-17 12:17:10 |  |

#### STG_ECI_PTY_INACTIVE_STS (`EciTargets.InactiveStatus`)

1 rows, 1 shown - rows in the table before the mapping ran

| SRC_KEY | ROWID_SYSTEM | DEACTIVATION_STS | DEACTIVATION_DT |
| --- | --- | --- | --- |
| 9100000002 | ECI | H | 2026-10-19 03:58:23 |

### IdqMapInitQuery (`EciQueries.FamilyAddress`)

20 rows, 20 shown - rows returned by the IdqMapInitQuery

| SOURCE_TABLE | ID | ID_FAMILY_ADDRESS | ADDRESS1 | ADDRESS2 | ADDRESS_CD | CITY_NAME | COUNTY_NAME | STATE_ABBREV | ZIP_CODE | ZIP_SFX | LAST_UPDATE_DATE |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI_CHILD | 9100000001 | 501 | Test_001-34374 Lourie Neck |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-14 12:17:08 |
| ECI_FAMILY | 9100000002 | 502 | Test_001-9476 Jacobson Brook |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-12-09 12:17:08 |
| ECI_CHILD | 9100000003 | 503 | Test_001-875 Antonio Stravenue | Test_001-Suite 4 | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-11 12:17:08 |
| ECI_FAMILY | 9100000004 | 504 | Test_001-2027 Feest Road |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-12-09 12:17:09 |
| ECI_CHILD | 9100000005 | 505 | Test_001-5795 Darryl Ports |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-10-27 12:17:09 |
| ECI_FAMILY | 9100000006 | 506 | Test_001-462 Stacey Junctions | Test_001-Suite 4 | 9 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-02 12:17:09 |
| ECI_CHILD | 9100000007 | 507 | Test_001-8142 Jast Courts |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-05 12:17:09 |
| ECI_FAMILY | 9100000008 | 508 | Test_001-619 Torphy Causeway |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-05-04 12:17:09 |
| ECI_CHILD | 9100000009 | 509 | Test_001-3248 Tromp Stream | Test_001-Suite 4 | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-06 12:17:09 |
| ECI_FAMILY | 9100000010 | 510 | Test_001-108 Langworth Drives |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-04-03 12:17:09 |
| ECI_CHILD | 9100000011 | 511 | Test_001-17457 O'Hara Row |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-12-23 12:17:09 |
| ECI_FAMILY | 9100000012 | 512 | Test_001-5372 Hettinger Meadow | Test_001-Suite 4 | 9 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-02-16 12:17:09 |
| ECI_CHILD | 9100000013 | 513 | Test_001-544 Clint Lane |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-01-31 12:17:09 |
| ECI_FAMILY | 9100000014 | 514 | Test_001-088 Leigha Motorway |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-08-29 12:17:09 |
| ECI_CHILD | 9100000015 | 515 | Test_001-40189 Jerde Curve | Test_001-Suite 4 | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-11-07 12:17:09 |
| ECI_FAMILY | 9100000016 | 516 | Test_001-904 Konopelski Shores |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-05-31 12:17:09 |
| ECI_CHILD | 9100000017 | 517 | Test_001-828 Schneider Motorway |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2025-11-09 12:17:10 |
| ECI_FAMILY | 9100000018 | 518 | Test_001-2638 Harber Forges | Test_001-Suite 4 | 9 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-08-19 12:17:10 |
| ECI_CHILD | 9100000019 | 519 | Test_001-7275 Feest Road |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-18 12:17:10 |
| ECI_FAMILY | 9100000020 | 520 | Test_001-44248 Bradley Isle |  | 1 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | 2026-07-17 12:17:10 |

### Target C_S_ECI_PTY_RLE_ADDR

#### C_S_ECI_PTY_RLE_ADDR (`EciTargets.Address`)

17 rows, 17 shown - rows loaded by this run, read back from the table by key

| PKEY_SRC_OBJECT | PERIOD_START_DATE | PERIOD_END_DATE | LAST_UPDATE_DATE | CREATE_DATE | CREATOR | UPDATED_BY | SRC_ROWID | HUB_STATE_IND | SRC_LAST_UPD_DT | PTY_RLE_FK | ADDR_TP | PREF_LVL | HIERARCHY_CODE | HM_REL_TP_CD | LOC_IDN | ADDR_LN_1 | ADDR_LN_2 | BLDNG_NM | FLR_NUM | CITY | COUNTY | STATE | CNTRY_CD | PSTL_CD | PSTL_CD_EXT | LATTD | LNGTD | VLDTN_MSG | MLBLTY_SCR | ADDR_TP_CD | ORG_DESC | ORG_NM | BLDG_NMBR | SUB_BLDG_NM | SUB_BLDG_DESC | GEOCD_STS_CD | RSDNTL_DLVRY_IND | SRC_ADDR_LN_1 | SRC_ADDR_LN_2 | SRC_CITY | SRC_COUNTY | SRC_STATE | SRC_CNTRY | SRC_PSTL_CD | SRC_PSTL_CD_EXT | EFF_STRT_DT | EFF_END_DT |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 9100000001\|Member\|002\|0000000501\|TEST_001-34374 LOURIE NECK\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-01-14 12:17:08 |  | 2026-10-19 12:17:22 | 2026-01-14 12:17:08 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000001\|Member\|002\|00000005 | 1 | 2026-01-14 12:17:08 | 9100000001\|Member | 002 | Primary | Member | Member Addr | 9100000001\|501 | TEST001-34374 LOURIE NECK |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-34374 Lourie Neck |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-01-14 12:17:08 |  |
| 9100000002F\|Member\|002\|0000000502\|TEST_001-9476 JACOBSON BROOK\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2025-12-09 12:17:08 |  | 2026-10-19 12:17:22 | 2025-12-09 12:17:08 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000002F\|Member\|002\|0000000 | 1 | 2025-12-09 12:17:08 | 9100000002F\|Member | 002 | Primary | Member | Member Addr | 9100000002\|502 | TEST001-9476 JACOBSON BROOK |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-9476 Jacobson Brook |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2025-12-09 12:17:08 |  |
| 9100000003\|Member\|002\|0000000503\|TEST_001-875 ANTONIO STRAVENUE\|TEST_001-SUITE 4\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-07-11 12:17:08 |  | 2026-10-19 12:17:22 | 2026-07-11 12:17:08 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000003\|Member\|002\|00000005 | 1 | 2026-07-11 12:17:08 | 9100000003\|Member | 002 | Primary | Member | Member Addr | 9100000003\|503 | TEST001-875 ANTONIO STRAVENUE | TEST_001SUITE 4 |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-875 Antonio Stravenue | Test_001-Suite 4 | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-07-11 12:17:08 |  |
| 9100000004F\|Member\|002\|0000000504\|TEST_001-2027 FEEST ROAD\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2025-12-09 12:17:09 |  | 2026-10-19 12:17:22 | 2025-12-09 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000004F\|Member\|002\|0000000 | 1 | 2025-12-09 12:17:09 | 9100000004F\|Member | 002 | Primary | Member | Member Addr | 9100000004\|504 | TEST001-2027 FEEST ROAD |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-2027 Feest Road |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2025-12-09 12:17:09 |  |
| 9100000005\|Member\|002\|0000000505\|TEST_001-5795 DARRYL PORTS\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2025-10-27 12:17:09 |  | 2026-10-19 12:17:22 | 2025-10-27 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000005\|Member\|002\|00000005 | 1 | 2025-10-27 12:17:09 | 9100000005\|Member | 002 | Primary | Member | Member Addr | 9100000005\|505 | TEST001-5795 DARRYL PORTS |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-5795 Darryl Ports |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2025-10-27 12:17:09 |  |
| 9100000007\|Member\|002\|0000000507\|TEST_001-8142 JAST COURTS\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-01-05 12:17:09 |  | 2026-10-19 12:17:22 | 2026-01-05 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000007\|Member\|002\|00000005 | 1 | 2026-01-05 12:17:09 | 9100000007\|Member | 002 | Primary | Member | Member Addr | 9100000007\|507 | TEST001-8142 JAST COURTS |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-8142 Jast Courts |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-01-05 12:17:09 |  |
| 9100000008F\|Member\|002\|0000000508\|TEST_001-619 TORPHY CAUSEWAY\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-05-04 12:17:09 |  | 2026-10-19 12:17:22 | 2026-05-04 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000008F\|Member\|002\|0000000 | 1 | 2026-05-04 12:17:09 | 9100000008F\|Member | 002 | Primary | Member | Member Addr | 9100000008\|508 | TEST001-619 TORPHY CAUSEWAY |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-619 Torphy Causeway |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-05-04 12:17:09 |  |
| 9100000009\|Member\|002\|0000000509\|TEST_001-3248 TROMP STREAM\|TEST_001-SUITE 4\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-07-06 12:17:09 |  | 2026-10-19 12:17:22 | 2026-07-06 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000009\|Member\|002\|00000005 | 1 | 2026-07-06 12:17:09 | 9100000009\|Member | 002 | Primary | Member | Member Addr | 9100000009\|509 | TEST001-3248 TROMP STREAM | TEST_001SUITE 4 |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-3248 Tromp Stream | Test_001-Suite 4 | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-07-06 12:17:09 |  |
| 9100000010F\|Member\|002\|0000000510\|TEST_001-108 LANGWORTH DRIVES\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-04-03 12:17:09 |  | 2026-10-19 12:17:22 | 2026-04-03 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000010F\|Member\|002\|0000000 | 1 | 2026-04-03 12:17:09 | 9100000010F\|Member | 002 | Primary | Member | Member Addr | 9100000010\|510 | TEST001-108 LANGWORTH DRIVES |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-108 Langworth Drives |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-04-03 12:17:09 |  |
| 9100000011\|Member\|002\|0000000511\|TEST_001-17457 O'HARA ROW\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2025-12-23 12:17:09 |  | 2026-10-19 12:17:22 | 2025-12-23 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000011\|Member\|002\|00000005 | 1 | 2025-12-23 12:17:09 | 9100000011\|Member | 002 | Primary | Member | Member Addr | 9100000011\|511 | TEST001-17457 OHARA ROW |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-17457 O'Hara Row |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2025-12-23 12:17:09 |  |
| 9100000013\|Member\|002\|0000000513\|TEST_001-544 CLINT LANE\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-01-31 12:17:09 |  | 2026-10-19 12:17:22 | 2026-01-31 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000013\|Member\|002\|00000005 | 1 | 2026-01-31 12:17:09 | 9100000013\|Member | 002 | Primary | Member | Member Addr | 9100000013\|513 | TEST001-544 CLINT LANE |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-544 Clint Lane |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-01-31 12:17:09 |  |
| 9100000014F\|Member\|002\|0000000514\|TEST_001-088 LEIGHA MOTORWAY\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-08-29 12:17:09 |  | 2026-10-19 12:17:22 | 2026-08-29 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000014F\|Member\|002\|0000000 | 1 | 2026-08-29 12:17:09 | 9100000014F\|Member | 002 | Primary | Member | Member Addr | 9100000014\|514 | TEST001-088 LEIGHA MOTORWAY |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-088 Leigha Motorway |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-08-29 12:17:09 |  |
| 9100000015\|Member\|002\|0000000515\|TEST_001-40189 JERDE CURVE\|TEST_001-SUITE 4\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2025-11-07 12:17:09 |  | 2026-10-19 12:17:22 | 2025-11-07 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000015\|Member\|002\|00000005 | 1 | 2025-11-07 12:17:09 | 9100000015\|Member | 002 | Primary | Member | Member Addr | 9100000015\|515 | TEST001-40189 JERDE CURVE | TEST_001SUITE 4 |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-40189 Jerde Curve | Test_001-Suite 4 | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2025-11-07 12:17:09 |  |
| 9100000016F\|Member\|002\|0000000516\|TEST_001-904 KONOPELSKI SHORES\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-05-31 12:17:09 |  | 2026-10-19 12:17:22 | 2026-05-31 12:17:09 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000016F\|Member\|002\|0000000 | 1 | 2026-05-31 12:17:09 | 9100000016F\|Member | 002 | Primary | Member | Member Addr | 9100000016\|516 | TEST001-904 KONOPELSKI SHORES |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-904 Konopelski Shores |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-05-31 12:17:09 |  |
| 9100000017\|Member\|002\|0000000517\|TEST_001-828 SCHNEIDER MOTORWAY\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2025-11-09 12:17:10 |  | 2026-10-19 12:17:22 | 2025-11-09 12:17:10 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000017\|Member\|002\|00000005 | 1 | 2025-11-09 12:17:10 | 9100000017\|Member | 002 | Primary | Member | Member Addr | 9100000017\|517 | TEST001-828 SCHNEIDER MOTORWAY |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-828 Schneider Motorway |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2025-11-09 12:17:10 |  |
| 9100000019\|Member\|002\|0000000519\|TEST_001-7275 FEEST ROAD\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-07-18 12:17:10 |  | 2026-10-19 12:17:22 | 2026-07-18 12:17:10 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000019\|Member\|002\|00000005 | 1 | 2026-07-18 12:17:10 | 9100000019\|Member | 002 | Primary | Member | Member Addr | 9100000019\|519 | TEST001-7275 FEEST ROAD |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-7275 Feest Road |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-07-18 12:17:10 |  |
| 9100000020F\|Member\|002\|0000000520\|TEST_001-44248 BRADLEY ISLE\|\|TEST_001-AUSTIN\|TX\|78701\|1234 | 2026-07-17 12:17:10 |  | 2026-10-19 12:17:22 | 2026-07-17 12:17:10 |  | m_Tgt_C_S_ECI_Pty_Addr | 9100000020F\|Member\|002\|0000000 | 1 | 2026-07-17 12:17:10 | 9100000020F\|Member | 002 | Primary | Member | Member Addr | 9100000020\|520 | TEST001-44248 BRADLEY ISLE |  |  |  | Test_001-Austin | 999 | 48 | US | 78701 | 1234 | 0 | 0 |  |  |  |  |  |  |  |  |  |  | Test_001-44248 Bradley Isle |  | Test_001-Austin | Test_001-Travis | TX | US | 78701 | 1234 | 2026-07-17 12:17:10 |  |

### EXC_STG_BAD_REC_MEMB (`BadRecord`)

3 rows, 3 shown - rows appended (the table has no key to read them back by)

| SRC_SYS | SRC_SYS_ID_1 | SRC_SYS_ID_2 | SRC_SYS_ID_3 | EXCEPTION_TYPE | EXCEPTION_CODE | EXCEPTION_DESC | RUN_DATE | PREFIX | FIRST_NAME | MIDDLE_NAME | LAST_NAME | SUFFIX | ALIAS_SUFFIX | BIRTH_DATE | GENDER | ADDRESS_TYPE | ADDRESS_LINE_1 | ADDRESS_LINE_2 | ADDRESS_CITY | ADDRESS_COUNTY | ADDRESS_STATE | ADDRESS_ZIP | ADDRESS_ZIP_EXT | ADDRESS_COUNTRY | ADDRESS_DR_ERROR_CODE | ADDRESS_DR_ERROR_DESC | ADDRESS_DR_MAILABILITY_SCORE | PRIMARY_PHONE | WORK_PHONE | SECONDARY_PHONE | EMAIL | ATTRIBUTE_NAME | ATTRIBUTE_VALUE | MAPPING_NAME | PERIOD_START_DATE | PERIOD_END_DATE | DEATH_DT |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI | 9100000006 | 506 | ECI_FAMILY | Bad Value | Invalid_Address | Invalid Address per Address Doctor | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  | 9 | Test_001-462 Stacey Junctions | Test_001-Suite 4 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | US |  |  |  |  |  |  |  | Address | Test_001-462 Stacey Junctions Test_001-Suite 4 Test_001-Austin TX 78701 1234 US | m_Tgt_C_S_ECI_Pty_Addr | 2026-01-02 12:17:09 |  |  |
| ECI | 9100000012 | 512 | ECI_FAMILY | Bad Value | Invalid_Address | Invalid Address per Address Doctor | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  | 9 | Test_001-5372 Hettinger Meadow | Test_001-Suite 4 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | US |  |  |  |  |  |  |  | Address | Test_001-5372 Hettinger Meadow Test_001-Suite 4 Test_001-Austin TX 78701 1234 US | m_Tgt_C_S_ECI_Pty_Addr | 2026-02-16 12:17:09 |  |  |
| ECI | 9100000018 | 518 | ECI_FAMILY | Bad Value | Invalid_Address | Invalid Address per Address Doctor | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  | 9 | Test_001-2638 Harber Forges | Test_001-Suite 4 | Test_001-Austin | Test_001-Travis | TX | 78701 | 1234 | US |  |  |  |  |  |  |  | Address | Test_001-2638 Harber Forges Test_001-Suite 4 Test_001-Austin TX 78701 1234 US | m_Tgt_C_S_ECI_Pty_Addr | 2026-08-19 12:17:10 |  |  |


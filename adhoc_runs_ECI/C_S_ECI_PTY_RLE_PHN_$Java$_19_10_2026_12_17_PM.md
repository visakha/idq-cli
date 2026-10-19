# C_S_ECI_PTY_RLE_PHN - ECI adhoc run (Java)

| item | value |
| --- | --- |
| source system | ECI (wf_ECI_Stage_Load) |
| etl_process | JAVA |
| run started | 2026-10-19 12:17:22 |
| rows shown per table | up to 200 |
| mock data SQL | `C_S_ECI_PTY_RLE_PHN_$Java$_19_10_2026_12_17_PM.sql` |

## Mappings that load C_S_ECI_PTY_RLE_PHN

| seq | mapping | status | rows read | rows written | exceptions | ms | message |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 017 | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | SUCCEEDED | 40 | C_S_ECI_PTY_RLE_PHN=20, C_S_ECI_PTY_RLE_EADDR=16, EXC_STG_BAD_REC_MEMB=9 | 9 | 552 |  |

## 017 m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr

Documentation: `docs/mappings/017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md`

### Source tables

#### V_ECI_ETL_SRC_FAMILY_PHONE (`EciSources.EtlSrcFamilyPhone`)

40 rows, 40 shown - rows in the table before the mapping ran

| SOURCE_TABLE | ID_FAMILY_PHONE | ID_CASE | ID | PERIOD_START_DATE | PHONE_EMAIL_TYPE | PHONE_EMAIL | WORK_EXT | PHONE_TP | USG_TP | PREF_LVL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI_CHILD | P1 | 9100000001 | 9100000001 | 2026-04-05 12:17:16 | PHONE | 5125550001 |  | Telephone | 001 | Primary |
| ECI_CHILD | E1 | 9100000001 | 9100000001 | 2026-04-05 12:17:16 | EADDRESS | Test_001-avery.upton@yahoo.com |  |  |  |  |
| ECI_FAMILY | P2 | 9100000002 | 9100000002 | 2026-08-02 12:17:16 | PHONE | 5125550002 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E2 | 9100000002 | 9100000002 | 2026-08-02 12:17:16 | EADDRESS | Test_001-shawn.breitenberg@hotmail.com |  |  |  |  |
| ECI_CHILD | P3 | 9100000003 | 9100000003 | 2026-07-19 12:17:16 | PHONE | 5125550003 |  | Telephone | 001 | Primary |
| ECI_CHILD | E3 | 9100000003 | 9100000003 | 2026-07-19 12:17:16 | EADDRESS | Test_001-garry.kihn@hotmail.com |  |  |  |  |
| ECI_FAMILY | P4 | 9100000004 | 9100000004 | 2025-10-30 12:17:16 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E4 | 9100000004 | 9100000004 | 2025-10-30 12:17:16 | EADDRESS | Test_001-noemi.heller@yahoo.com |  |  |  |  |
| ECI_CHILD | P5 | 9100000005 | 9100000005 | 2026-05-22 12:17:16 | PHONE | 5125550005 |  | Telephone | 001 | Primary |
| ECI_CHILD | E5 | 9100000005 | 9100000005 | 2026-05-22 12:17:16 | EADDRESS | Test_001-broken@ |  |  |  |  |
| ECI_FAMILY | P6 | 9100000006 | 9100000006 | 2025-11-28 12:17:16 | PHONE | 5125550006 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E6 | 9100000006 | 9100000006 | 2025-11-28 12:17:16 | EADDRESS | Test_001-trey.grant@yahoo.com |  |  |  |  |
| ECI_CHILD | P7 | 9100000007 | 9100000007 | 2025-11-13 12:17:17 | PHONE | 5125550007 |  | Telephone | 001 | Primary |
| ECI_CHILD | E7 | 9100000007 | 9100000007 | 2025-11-13 12:17:17 | EADDRESS | Test_001-janyce.ward@hotmail.com |  |  |  |  |
| ECI_FAMILY | P8 | 9100000008 | 9100000008 | 2025-12-09 12:17:17 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E8 | 9100000008 | 9100000008 | 2025-12-09 12:17:17 | EADDRESS | Test_001-flo.morissette@hotmail.com |  |  |  |  |
| ECI_CHILD | P9 | 9100000009 | 9100000009 | 2026-03-19 12:17:17 | PHONE | 5125550009 |  | Telephone | 001 | Primary |
| ECI_CHILD | E9 | 9100000009 | 9100000009 | 2026-03-19 12:17:17 | EADDRESS | Test_001-jenine.reichert@gmail.com |  |  |  |  |
| ECI_FAMILY | P10 | 9100000010 | 9100000010 | 2025-11-24 12:17:17 | PHONE | 5125550010 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E10 | 9100000010 | 9100000010 | 2025-11-24 12:17:17 | EADDRESS | Test_001-broken@ |  |  |  |  |
| ECI_CHILD | P11 | 9100000011 | 9100000011 | 2026-01-01 12:17:17 | PHONE | 5125550011 |  | Telephone | 001 | Primary |
| ECI_CHILD | E11 | 9100000011 | 9100000011 | 2026-01-01 12:17:17 | EADDRESS | Test_001-arlen.ernser@yahoo.com |  |  |  |  |
| ECI_FAMILY | P12 | 9100000012 | 9100000012 | 2026-08-08 12:17:17 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E12 | 9100000012 | 9100000012 | 2026-08-08 12:17:17 | EADDRESS | Test_001-adrian.dibbert@yahoo.com |  |  |  |  |
| ECI_CHILD | P13 | 9100000013 | 9100000013 | 2026-06-08 12:17:17 | PHONE | 5125550013 |  | Telephone | 001 | Primary |
| ECI_CHILD | E13 | 9100000013 | 9100000013 | 2026-06-08 12:17:17 | EADDRESS | Test_001-eboni.kreiger@gmail.com |  |  |  |  |
| ECI_FAMILY | P14 | 9100000014 | 9100000014 | 2026-05-07 12:17:17 | PHONE | 5125550014 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E14 | 9100000014 | 9100000014 | 2026-05-07 12:17:17 | EADDRESS | Test_001-wai.purdy@hotmail.com |  |  |  |  |
| ECI_CHILD | P15 | 9100000015 | 9100000015 | 2026-02-21 12:17:17 | PHONE | 5125550015 |  | Telephone | 001 | Primary |
| ECI_CHILD | E15 | 9100000015 | 9100000015 | 2026-02-21 12:17:17 | EADDRESS | Test_001-broken@ |  |  |  |  |
| ECI_FAMILY | P16 | 9100000016 | 9100000016 | 2026-05-10 12:17:17 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E16 | 9100000016 | 9100000016 | 2026-05-10 12:17:17 | EADDRESS | Test_001-antoine.murphy@gmail.com |  |  |  |  |
| ECI_CHILD | P17 | 9100000017 | 9100000017 | 2026-05-03 12:17:18 | PHONE | 5125550017 |  | Telephone | 001 | Primary |
| ECI_CHILD | E17 | 9100000017 | 9100000017 | 2026-05-03 12:17:18 | EADDRESS | Test_001-robbyn.cummerata@gmail.com |  |  |  |  |
| ECI_FAMILY | P18 | 9100000018 | 9100000018 | 2026-07-11 12:17:18 | PHONE | 5125550018 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E18 | 9100000018 | 9100000018 | 2026-07-11 12:17:18 | EADDRESS | Test_001-david.schumm@yahoo.com |  |  |  |  |
| ECI_CHILD | P19 | 9100000019 | 9100000019 | 2026-06-24 12:17:18 | PHONE | 5125550019 |  | Telephone | 001 | Primary |
| ECI_CHILD | E19 | 9100000019 | 9100000019 | 2026-06-24 12:17:18 | EADDRESS | Test_001-mohamed.jakubowski@hotmail.com |  |  |  |  |
| ECI_FAMILY | P20 | 9100000020 | 9100000020 | 2026-02-03 12:17:18 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E20 | 9100000020 | 9100000020 | 2026-02-03 12:17:18 | EADDRESS | Test_001-broken@ |  |  |  |  |

#### STG_ECI_PTY_INACTIVE_STS (`EciTargets.InactiveStatus`)

1 rows, 1 shown - rows in the table before the mapping ran

| SRC_KEY | ROWID_SYSTEM | DEACTIVATION_STS | DEACTIVATION_DT |
| --- | --- | --- | --- |
| 9100000002 | ECI | H | 2026-10-19 03:58:23 |

### IdqMapInitQuery (`EciQueries.FamilyContact`)

40 rows, 40 shown - rows returned by the IdqMapInitQuery

| SOURCE_TABLE | ID_FAMILY_PHONE | ID_CASE | ID | PERIOD_START_DATE | PHONE_EMAIL_TYPE | PHONE_EMAIL | WORK_EXT | PHONE_TP | USG_TP | PREF_LVL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI_CHILD | P1 | 9100000001 | 9100000001 | 2026-04-05 12:17:16 | PHONE | 5125550001 |  | Telephone | 001 | Primary |
| ECI_CHILD | E1 | 9100000001 | 9100000001 | 2026-04-05 12:17:16 | EADDRESS | Test_001-avery.upton@yahoo.com |  |  |  |  |
| ECI_FAMILY | P2 | 9100000002 | 9100000002 | 2026-08-02 12:17:16 | PHONE | 5125550002 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E2 | 9100000002 | 9100000002 | 2026-08-02 12:17:16 | EADDRESS | Test_001-shawn.breitenberg@hotmail.com |  |  |  |  |
| ECI_CHILD | P3 | 9100000003 | 9100000003 | 2026-07-19 12:17:16 | PHONE | 5125550003 |  | Telephone | 001 | Primary |
| ECI_CHILD | E3 | 9100000003 | 9100000003 | 2026-07-19 12:17:16 | EADDRESS | Test_001-garry.kihn@hotmail.com |  |  |  |  |
| ECI_FAMILY | P4 | 9100000004 | 9100000004 | 2025-10-30 12:17:16 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E4 | 9100000004 | 9100000004 | 2025-10-30 12:17:16 | EADDRESS | Test_001-noemi.heller@yahoo.com |  |  |  |  |
| ECI_CHILD | P5 | 9100000005 | 9100000005 | 2026-05-22 12:17:16 | PHONE | 5125550005 |  | Telephone | 001 | Primary |
| ECI_CHILD | E5 | 9100000005 | 9100000005 | 2026-05-22 12:17:16 | EADDRESS | Test_001-broken@ |  |  |  |  |
| ECI_FAMILY | P6 | 9100000006 | 9100000006 | 2025-11-28 12:17:16 | PHONE | 5125550006 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E6 | 9100000006 | 9100000006 | 2025-11-28 12:17:16 | EADDRESS | Test_001-trey.grant@yahoo.com |  |  |  |  |
| ECI_CHILD | P7 | 9100000007 | 9100000007 | 2025-11-13 12:17:17 | PHONE | 5125550007 |  | Telephone | 001 | Primary |
| ECI_CHILD | E7 | 9100000007 | 9100000007 | 2025-11-13 12:17:17 | EADDRESS | Test_001-janyce.ward@hotmail.com |  |  |  |  |
| ECI_FAMILY | P8 | 9100000008 | 9100000008 | 2025-12-09 12:17:17 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E8 | 9100000008 | 9100000008 | 2025-12-09 12:17:17 | EADDRESS | Test_001-flo.morissette@hotmail.com |  |  |  |  |
| ECI_CHILD | P9 | 9100000009 | 9100000009 | 2026-03-19 12:17:17 | PHONE | 5125550009 |  | Telephone | 001 | Primary |
| ECI_CHILD | E9 | 9100000009 | 9100000009 | 2026-03-19 12:17:17 | EADDRESS | Test_001-jenine.reichert@gmail.com |  |  |  |  |
| ECI_FAMILY | P10 | 9100000010 | 9100000010 | 2025-11-24 12:17:17 | PHONE | 5125550010 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E10 | 9100000010 | 9100000010 | 2025-11-24 12:17:17 | EADDRESS | Test_001-broken@ |  |  |  |  |
| ECI_CHILD | P11 | 9100000011 | 9100000011 | 2026-01-01 12:17:17 | PHONE | 5125550011 |  | Telephone | 001 | Primary |
| ECI_CHILD | E11 | 9100000011 | 9100000011 | 2026-01-01 12:17:17 | EADDRESS | Test_001-arlen.ernser@yahoo.com |  |  |  |  |
| ECI_FAMILY | P12 | 9100000012 | 9100000012 | 2026-08-08 12:17:17 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E12 | 9100000012 | 9100000012 | 2026-08-08 12:17:17 | EADDRESS | Test_001-adrian.dibbert@yahoo.com |  |  |  |  |
| ECI_CHILD | P13 | 9100000013 | 9100000013 | 2026-06-08 12:17:17 | PHONE | 5125550013 |  | Telephone | 001 | Primary |
| ECI_CHILD | E13 | 9100000013 | 9100000013 | 2026-06-08 12:17:17 | EADDRESS | Test_001-eboni.kreiger@gmail.com |  |  |  |  |
| ECI_FAMILY | P14 | 9100000014 | 9100000014 | 2026-05-07 12:17:17 | PHONE | 5125550014 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E14 | 9100000014 | 9100000014 | 2026-05-07 12:17:17 | EADDRESS | Test_001-wai.purdy@hotmail.com |  |  |  |  |
| ECI_CHILD | P15 | 9100000015 | 9100000015 | 2026-02-21 12:17:17 | PHONE | 5125550015 |  | Telephone | 001 | Primary |
| ECI_CHILD | E15 | 9100000015 | 9100000015 | 2026-02-21 12:17:17 | EADDRESS | Test_001-broken@ |  |  |  |  |
| ECI_FAMILY | P16 | 9100000016 | 9100000016 | 2026-05-10 12:17:17 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E16 | 9100000016 | 9100000016 | 2026-05-10 12:17:17 | EADDRESS | Test_001-antoine.murphy@gmail.com |  |  |  |  |
| ECI_CHILD | P17 | 9100000017 | 9100000017 | 2026-05-03 12:17:18 | PHONE | 5125550017 |  | Telephone | 001 | Primary |
| ECI_CHILD | E17 | 9100000017 | 9100000017 | 2026-05-03 12:17:18 | EADDRESS | Test_001-robbyn.cummerata@gmail.com |  |  |  |  |
| ECI_FAMILY | P18 | 9100000018 | 9100000018 | 2026-07-11 12:17:18 | PHONE | 5125550018 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E18 | 9100000018 | 9100000018 | 2026-07-11 12:17:18 | EADDRESS | Test_001-david.schumm@yahoo.com |  |  |  |  |
| ECI_CHILD | P19 | 9100000019 | 9100000019 | 2026-06-24 12:17:18 | PHONE | 5125550019 |  | Telephone | 001 | Primary |
| ECI_CHILD | E19 | 9100000019 | 9100000019 | 2026-06-24 12:17:18 | EADDRESS | Test_001-mohamed.jakubowski@hotmail.com |  |  |  |  |
| ECI_FAMILY | P20 | 9100000020 | 9100000020 | 2026-02-03 12:17:18 | PHONE | 5551234 |  | Telephone | 001 | Primary |
| ECI_FAMILY | E20 | 9100000020 | 9100000020 | 2026-02-03 12:17:18 | EADDRESS | Test_001-broken@ |  |  |  |  |

### Target C_S_ECI_PTY_RLE_PHN

#### C_S_ECI_PTY_RLE_PHN (`EciTargets.Phone`)

20 rows, 20 shown - rows loaded by this run, read back from the table by key

| PKEY_SRC_OBJECT | PERIOD_START_DATE | PERIOD_END_DATE | LAST_UPDATE_DATE | CREATE_DATE | CREATOR | UPDATED_BY | SRC_ROWID | HUB_STATE_IND | SRC_LAST_UPD_DT | PTY_RLE_FK | PHN_TP | USG_TP | PHN_NUM | PREF_LVL | PHN_NUM_EXT |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 9100000001\|Member\|Telephone\|001\|P1\|5125550001 | 2026-04-05 12:17:16 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000001\|Member\|Telephone\|00 | 1 | 2026-04-05 12:17:16 | 9100000001\|Member | Telephone | 001 | 5125550001 | Primary |  |
| 9100000002F\|Member\|Telephone\|001\|P2\|5125550002 | 2026-08-02 12:17:16 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000002F\|Member\|Telephone\|0 | 1 | 2026-08-02 12:17:16 | 9100000002F\|Member | Telephone | 001 | 5125550002 | Primary |  |
| 9100000003\|Member\|Telephone\|001\|P3\|5125550003 | 2026-07-19 12:17:16 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000003\|Member\|Telephone\|00 | 1 | 2026-07-19 12:17:16 | 9100000003\|Member | Telephone | 001 | 5125550003 | Primary |  |
| 9100000004F\|Member\|Telephone\|001\|P4\|5551234 | 2025-10-30 12:17:16 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000004F\|Member\|Telephone\|0 | 1 | 2025-10-30 12:17:16 | 9100000004F\|Member | Telephone | 001 | 0005551234 | Primary |  |
| 9100000005\|Member\|Telephone\|001\|P5\|5125550005 | 2026-05-22 12:17:16 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000005\|Member\|Telephone\|00 | 1 | 2026-05-22 12:17:16 | 9100000005\|Member | Telephone | 001 | 5125550005 | Primary |  |
| 9100000006F\|Member\|Telephone\|001\|P6\|5125550006 | 2025-11-28 12:17:16 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000006F\|Member\|Telephone\|0 | 1 | 2025-11-28 12:17:16 | 9100000006F\|Member | Telephone | 001 | 5125550006 | Primary |  |
| 9100000007\|Member\|Telephone\|001\|P7\|5125550007 | 2025-11-13 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000007\|Member\|Telephone\|00 | 1 | 2025-11-13 12:17:17 | 9100000007\|Member | Telephone | 001 | 5125550007 | Primary |  |
| 9100000008F\|Member\|Telephone\|001\|P8\|5551234 | 2025-12-09 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000008F\|Member\|Telephone\|0 | 1 | 2025-12-09 12:17:17 | 9100000008F\|Member | Telephone | 001 | 0005551234 | Primary |  |
| 9100000009\|Member\|Telephone\|001\|P9\|5125550009 | 2026-03-19 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000009\|Member\|Telephone\|00 | 1 | 2026-03-19 12:17:17 | 9100000009\|Member | Telephone | 001 | 5125550009 | Primary |  |
| 9100000010F\|Member\|Telephone\|001\|P10\|5125550010 | 2025-11-24 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000010F\|Member\|Telephone\|0 | 1 | 2025-11-24 12:17:17 | 9100000010F\|Member | Telephone | 001 | 5125550010 | Primary |  |
| 9100000011\|Member\|Telephone\|001\|P11\|5125550011 | 2026-01-01 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000011\|Member\|Telephone\|00 | 1 | 2026-01-01 12:17:17 | 9100000011\|Member | Telephone | 001 | 5125550011 | Primary |  |
| 9100000012F\|Member\|Telephone\|001\|P12\|5551234 | 2026-08-08 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000012F\|Member\|Telephone\|0 | 1 | 2026-08-08 12:17:17 | 9100000012F\|Member | Telephone | 001 | 0005551234 | Primary |  |
| 9100000013\|Member\|Telephone\|001\|P13\|5125550013 | 2026-06-08 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000013\|Member\|Telephone\|00 | 1 | 2026-06-08 12:17:17 | 9100000013\|Member | Telephone | 001 | 5125550013 | Primary |  |
| 9100000014F\|Member\|Telephone\|001\|P14\|5125550014 | 2026-05-07 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000014F\|Member\|Telephone\|0 | 1 | 2026-05-07 12:17:17 | 9100000014F\|Member | Telephone | 001 | 5125550014 | Primary |  |
| 9100000015\|Member\|Telephone\|001\|P15\|5125550015 | 2026-02-21 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000015\|Member\|Telephone\|00 | 1 | 2026-02-21 12:17:17 | 9100000015\|Member | Telephone | 001 | 5125550015 | Primary |  |
| 9100000016F\|Member\|Telephone\|001\|P16\|5551234 | 2026-05-10 12:17:17 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000016F\|Member\|Telephone\|0 | 1 | 2026-05-10 12:17:17 | 9100000016F\|Member | Telephone | 001 | 0005551234 | Primary |  |
| 9100000017\|Member\|Telephone\|001\|P17\|5125550017 | 2026-05-03 12:17:18 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000017\|Member\|Telephone\|00 | 1 | 2026-05-03 12:17:18 | 9100000017\|Member | Telephone | 001 | 5125550017 | Primary |  |
| 9100000018F\|Member\|Telephone\|001\|P18\|5125550018 | 2026-07-11 12:17:18 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000018F\|Member\|Telephone\|0 | 1 | 2026-07-11 12:17:18 | 9100000018F\|Member | Telephone | 001 | 5125550018 | Primary |  |
| 9100000019\|Member\|Telephone\|001\|P19\|5125550019 | 2026-06-24 12:17:18 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000019\|Member\|Telephone\|00 | 1 | 2026-06-24 12:17:18 | 9100000019\|Member | Telephone | 001 | 5125550019 | Primary |  |
| 9100000020F\|Member\|Telephone\|001\|P20\|5551234 | 2026-02-03 12:17:18 |  | 2026-10-19 12:17:22 | 2026-10-19 12:17:22 |  |  | 9100000020F\|Member\|Telephone\|0 | 1 | 2026-02-03 12:17:18 | 9100000020F\|Member | Telephone | 001 | 0005551234 | Primary |  |

### EXC_STG_BAD_REC_MEMB (`BadRecord`)

9 rows, 9 shown - rows appended (the table has no key to read them back by)

| SRC_SYS | SRC_SYS_ID_1 | SRC_SYS_ID_2 | SRC_SYS_ID_3 | EXCEPTION_TYPE | EXCEPTION_CODE | EXCEPTION_DESC | RUN_DATE | PREFIX | FIRST_NAME | MIDDLE_NAME | LAST_NAME | SUFFIX | ALIAS_SUFFIX | BIRTH_DATE | GENDER | ADDRESS_TYPE | ADDRESS_LINE_1 | ADDRESS_LINE_2 | ADDRESS_CITY | ADDRESS_COUNTY | ADDRESS_STATE | ADDRESS_ZIP | ADDRESS_ZIP_EXT | ADDRESS_COUNTRY | ADDRESS_DR_ERROR_CODE | ADDRESS_DR_ERROR_DESC | ADDRESS_DR_MAILABILITY_SCORE | PRIMARY_PHONE | WORK_PHONE | SECONDARY_PHONE | EMAIL | ATTRIBUTE_NAME | ATTRIBUTE_VALUE | MAPPING_NAME | PERIOD_START_DATE | PERIOD_END_DATE | DEATH_DT |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ECI |  | 9100000004 | 001 | Bad Value | Missing_AreaCode | Missing AreaCode | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0005551234 |  |  |  | Main Phone | 0005551234 | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2025-10-30 12:17:16 |  |  |
| ECI | E5 |  |  | Bad Value | Invalid_Email | Invalid Email | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | Test_001-broken@ | Email | Test_001-broken@ | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2026-05-22 12:17:16 |  |  |
| ECI |  | 9100000008 | 001 | Bad Value | Missing_AreaCode | Missing AreaCode | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0005551234 |  |  |  | Main Phone | 0005551234 | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2025-12-09 12:17:17 |  |  |
| ECI | E10 |  |  | Bad Value | Invalid_Email | Invalid Email | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | Test_001-broken@ | Email | Test_001-broken@ | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2025-11-24 12:17:17 |  |  |
| ECI |  | 9100000012 | 001 | Bad Value | Missing_AreaCode | Missing AreaCode | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0005551234 |  |  |  | Main Phone | 0005551234 | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2026-08-08 12:17:17 |  |  |
| ECI | E15 |  |  | Bad Value | Invalid_Email | Invalid Email | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | Test_001-broken@ | Email | Test_001-broken@ | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2026-02-21 12:17:17 |  |  |
| ECI |  | 9100000016 | 001 | Bad Value | Missing_AreaCode | Missing AreaCode | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0005551234 |  |  |  | Main Phone | 0005551234 | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2026-05-10 12:17:17 |  |  |
| ECI |  | 9100000020 | 001 | Bad Value | Missing_AreaCode | Missing AreaCode | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0005551234 |  |  |  | Main Phone | 0005551234 | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2026-02-03 12:17:18 |  |  |
| ECI | E20 |  |  | Bad Value | Invalid_Email | Invalid Email | 2026-10-19 12:17:22 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | Test_001-broken@ | Email | Test_001-broken@ | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 2026-02-03 12:17:18 |  |  |


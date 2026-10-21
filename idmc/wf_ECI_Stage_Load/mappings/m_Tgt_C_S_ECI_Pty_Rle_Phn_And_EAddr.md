# m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr

IDQ mapping &rarr; CDI **Mapping** `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`.

> [MLayne  9/30/2024]  Added filters to TKDS_CHILD SQL, added TKDS_FAMILY to source and source keys
[MLayne  12/12/2024]  Added trim statement to email in before building the pkey
[MLayne 1/8/2025]  Changed Hub state output from null to 1 for phone

## Summary

| IDQ transformation | CDI transformation | Count |
|---|---|---|
| ExpressionTx | Expression | 7 |
| FilterTx | Filter | 1 |
| LookupTx | Lookup | 1 |
| MappletTx | Mapplet | 2 |
| RouterTx | Router | 3 |
| SourceTx | Source | 1 |
| TargetTx | Target | 4 |

Sources:

| Instance | Object | Connection |
|---|---|---|
| Read_V_ECI_ETL_SRC_FAMILY_PHONE | `V_ECI_ETL_SRC_FAMILY_PHONE` | STAGING |

Targets:

| Instance | Object | Connection |
|---|---|---|
| write_Phone_EXC_STG_BAD_REC_MEMB | `EXC_STG_BAD_REC_MEMB` | STAGING |
| Write_C_S_ECI_PTY_RLE_PHN | `C_S_ECI_PTY_RLE_PHN` | HHS_MDM_ORS |
| write_Email_EXC_STG_BAD_REC_MEMB | `EXC_STG_BAD_REC_MEMB` | STAGING |
| Write_C_S_ECI_PTY_RLE_EADDR | `C_S_ECI_PTY_RLE_EADDR` | HHS_MDM_ORS |

## Flow

```mermaid
flowchart LR
  n0["Read_V_ECI_ETL_SRC_FAMILY_PHONE<br/><i>Source</i>"]
  n1["exp_Stage_Source_Attributes<br/><i>Expression</i>"]
  n2["Lkp_STG_ECI_PTY_INACTIVE_STS<br/><i>Lookup</i>"]
  n3["fil_deactivated_status<br/><i>Filter</i>"]
  n4["rtr_Phone_Email<br/><i>Router</i>"]
  n5["Expression<br/><i>Expression</i>"]
  n6["rule_Phone_Std<br/><i>Mapplet</i>"]
  n7["RTR_Valid_PhoneNumbers<br/><i>Router</i>"]
  n8["exp_Stage_Phone_Exceptions<br/><i>Expression</i>"]
  n9["write_Phone_EXC_STG_BAD_REC_MEMB<br/><i>Target</i>"]
  n10["exp_Stage_Target_PhoneNumbers<br/><i>Expression</i>"]
  n11["Write_C_S_ECI_PTY_RLE_PHN<br/><i>Target</i>"]
  n12["rule_email_validation_v01<br/><i>Mapplet</i>"]
  n13["exp_Setup_Attributes<br/><i>Expression</i>"]
  n14["rtr_Valid_EAddr_Records<br/><i>Router</i>"]
  n15["exp_Stage_Target_EAddr_Attributes<br/><i>Expression</i>"]
  n16["exp_Stage_Email_Exceptions<br/><i>Expression</i>"]
  n17["write_Email_EXC_STG_BAD_REC_MEMB<br/><i>Target</i>"]
  n18["Write_C_S_ECI_PTY_RLE_EADDR<br/><i>Target</i>"]
  n0 --> n1
  n1 --> n2
  n1 --> n3
  n2 --> n3
  n3 --> n4
  n4 --> n5
  n4 --> n6
  n4 --> n7
  n4 --> n12
  n4 --> n13
  n5 --> n6
  n6 --> n7
  n7 --> n8
  n7 --> n10
  n8 --> n9
  n10 --> n11
  n12 --> n13
  n13 --> n14
  n14 --> n15
  n14 --> n16
  n15 --> n18
  n16 --> n17
```

## Transformations

In data-flow order.

### Read_V_ECI_ETL_SRC_FAMILY_PHONE

IDQ `SourceTx` &rarr; CDI **Source**. Oracle connector source; carry the SQL override / filter below verbatim.

| Property | Value |
|---|---|
| Connection | STAGING |
| Object | V_ECI_ETL_SRC_FAMILY_PHONE |

Columns: `SOURCE_TABLE`, `ID_FAMILY_PHONE`, `ID_CASE`, `ID`, `PERIOD_START_DATE`, `PHONE_EMAIL_TYPE`, `PHONE_EMAIL`, `WORK_EXT`, `PHONE_TP`, `USG_TP`, `PREF_LVL`

### exp_Stage_Source_Attributes

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| ID_FAMILY_PHONE | in/out | string(10) | `ID_FAMILY_PHONE` |
| LAST_UPDATE_DT | out | date/time | `SYSTIMESTAMP()` |
| ID_CASE | in/out | decimal(10) | `ID_CASE` |
| ID | in/out | string(36) |  |
| PTY_RLE_FK | out | string(43) | `ID\|\| IIF(SOURCE_TABLE = 'ECI_FAMILY', 'F','')  \|\| '\|Member'` |
| PTY_SRC_KEY | out | string(11) | `ID\|\| IIF(SOURCE_TABLE = 'ECI_FAMILY', 'F','')` |
| PERIOD_START_DATE | in/out | date/time | `PERIOD_START_DATE` |
| PHONE_EMAIL_TYPE | in/out | string(10) | `PHONE_EMAIL_TYPE` |
| PHONE_EMAIL | in/out | string(200) | `PHONE_EMAIL` |
| PHONE_TP | in/out | string(9) | `PHONE_TP` |
| USG_TP | in/out | string(3) | `USG_TP` |
| PREF_LVL | in/out | string(8) | `PREF_LVL` |
| out_SRC_SYS | out | string(255) | `'ECI'` |
| o_PKEY_SRC_OBJECT | out | string(255) | `IIF(PHONE_EMAIL_TYPE='EADDRESS',<br>ID\|\| IIF(SOURCE_TABLE = 'ECI_FAMILY', 'F','') \|\|'\|Member'\|\|'\|'\|\|'001'\|\|'\|'\|\|ID_FAMILY_PHONE\|\|'\|'\|\|LTRIM(RTRIM(PHONE_EMAIL)),<br>ID\|\| IIF(SOURCE_TABLE = 'ECI_FAMILY', 'F','') \|\|'\|Member'\|\| '\|' \|\|PHONE_TP\|\| '\|' \|\| USG_TP \|\| '\|'\|\|ID_FAMILY_PHONE\|\|'\|'\|\|LTRIM(RTRIM(PHONE_EMAIL))<br>)` |
| o_SRC_ROWID | out | string(255) | `IIF(PHONE_EMAIL_TYPE='EADDRESS',<br>ID\|\| IIF(SOURCE_TABLE = 'ECI_FAMILY', 'F','') \|\|'\|Member'\|\|'\|'\|\|'001'\|\|'\|'\|\|ID_FAMILY_PHONE\|\|'\|'\|\|PHONE_EMAIL,<br>ID\|\| IIF(SOURCE_TABLE = 'ECI_FAMILY', 'F','') \|\|'\|Member'\|\| '\|' \|\|PHONE_TP\|\| '\|' \|\| USG_TP \|\| '\|'\|\|ID_FAMILY_PHONE\|\|'\|'\|\|PHONE_EMAIL<br>)` |
| WORK_EXT | in/out | string(5) | `WORK_EXT` |
| SOURCE_TABLE | in/out | string(10) |  |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| ID_FAMILY_PHONE | Read_V_ECI_ETL_SRC_FAMILY_PHONE.ID_FAMILY_PHONE |
| ID_CASE | Read_V_ECI_ETL_SRC_FAMILY_PHONE.ID_CASE |
| PERIOD_START_DATE | Read_V_ECI_ETL_SRC_FAMILY_PHONE.PERIOD_START_DATE |
| PHONE_EMAIL_TYPE | Read_V_ECI_ETL_SRC_FAMILY_PHONE.PHONE_EMAIL_TYPE |
| PHONE_EMAIL | Read_V_ECI_ETL_SRC_FAMILY_PHONE.PHONE_EMAIL |
| PHONE_TP | Read_V_ECI_ETL_SRC_FAMILY_PHONE.PHONE_TP |
| USG_TP | Read_V_ECI_ETL_SRC_FAMILY_PHONE.USG_TP |
| PREF_LVL | Read_V_ECI_ETL_SRC_FAMILY_PHONE.PREF_LVL |
| WORK_EXT | Read_V_ECI_ETL_SRC_FAMILY_PHONE.WORK_EXT |
| SOURCE_TABLE | Read_V_ECI_ETL_SRC_FAMILY_PHONE.SOURCE_TABLE |
| ID | Read_V_ECI_ETL_SRC_FAMILY_PHONE.ID |

### Lkp_STG_ECI_PTY_INACTIVE_STS

IDQ `LookupTx` &rarr; CDI **Lookup**. Connected lookup unless a return port is set (then unconnected).

| Property | Value |
|---|---|
| Connection | STAGING |
| Object | STG_ECI_PTY_INACTIVE_STS |
| Lookup condition | SRC_KEY = PTY_SRC_KEY AND ROWID_SYSTEM = SRC_SYSTEM |
| Multiple matches | Return any row |
| Cache | static cache |

| Lookup input field | Type |
|---|---|
| PTY_SRC_KEY | string(255) |
| SRC_SYSTEM | string(10) |

| Return / pass-through field | Feeds |
|---|---|
| DEACTIVATION_STS | fil_deactivated_status.DEACTIVATION_STS |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| SRC_SYSTEM | exp_Stage_Source_Attributes.out_SRC_SYS |
| PTY_SRC_KEY | exp_Stage_Source_Attributes.PTY_SRC_KEY |

### fil_deactivated_status

IDQ `FilterTx` &rarr; CDI **Filter**. Advanced filter condition.

Filter condition:

```
IsNull(DEACTIVATION_STS)
```

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| DEACTIVATION_STS | Lkp_STG_ECI_PTY_INACTIVE_STS.DEACTIVATION_STS |
| ID_FAMILY_PHONE | exp_Stage_Source_Attributes.ID_FAMILY_PHONE |
| LAST_UPDATE_DT | exp_Stage_Source_Attributes.LAST_UPDATE_DT |
| ID_CASE | exp_Stage_Source_Attributes.ID_CASE |
| PTY_RLE_FK | exp_Stage_Source_Attributes.PTY_RLE_FK |
| PERIOD_START_DATE | exp_Stage_Source_Attributes.PERIOD_START_DATE |
| PHONE_EMAIL_TYPE | exp_Stage_Source_Attributes.PHONE_EMAIL_TYPE |
| PHONE_EMAIL | exp_Stage_Source_Attributes.PHONE_EMAIL |
| PHONE_TP | exp_Stage_Source_Attributes.PHONE_TP |
| USG_TP | exp_Stage_Source_Attributes.USG_TP |
| PREF_LVL | exp_Stage_Source_Attributes.PREF_LVL |
| SRC_SYS | exp_Stage_Source_Attributes.out_SRC_SYS |
| PKEY_SRC_OBJECT | exp_Stage_Source_Attributes.o_PKEY_SRC_OBJECT |
| SRC_ROWID | exp_Stage_Source_Attributes.o_SRC_ROWID |
| WORK_EXT | exp_Stage_Source_Attributes.WORK_EXT |
| SOURCE_TABLE | exp_Stage_Source_Attributes.SOURCE_TABLE |

### rtr_Phone_Email

IDQ `RouterTx` &rarr; CDI **Router**. One output group per IDQ group; the default group is created automatically.

| Output group | Condition |
|---|---|
| Email_Group | `PHONE_EMAIL_TYPE='EADDRESS'` |
| Default | (default group) |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| ID_FAMILY_PHONE | fil_deactivated_status.ID_FAMILY_PHONE |
| LAST_UPDATE_DT | fil_deactivated_status.LAST_UPDATE_DT |
| ID_CASE | fil_deactivated_status.ID_CASE |
| PTY_RLE_FK | fil_deactivated_status.PTY_RLE_FK |
| PERIOD_START_DATE | fil_deactivated_status.PERIOD_START_DATE |
| PHONE_EMAIL_TYPE | fil_deactivated_status.PHONE_EMAIL_TYPE |
| PHONE_EMAIL | fil_deactivated_status.PHONE_EMAIL |
| USG_TP | fil_deactivated_status.USG_TP |
| PHONE_TP | fil_deactivated_status.PHONE_TP |
| PREF_LVL | fil_deactivated_status.PREF_LVL |
| PKEY_SRC_OBJECT | fil_deactivated_status.PKEY_SRC_OBJECT |
| SRC_ROWID | fil_deactivated_status.SRC_ROWID |
| WORK_EXT | fil_deactivated_status.WORK_EXT |
| SOURCE_TABLE | fil_deactivated_status.SOURCE_TABLE |

### Expression

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| PHONE_EMAIL | in/out | string(200) | `PHONE_EMAIL` |
| PHONE_EMAIL1 | out | string(200) | `IIF(LENGTH(PHONE_EMAIL)=7,CONCAT('000',PHONE_EMAIL),PHONE_EMAIL)` |
| SRC | out | string(200) | `'ECI'` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PHONE_EMAIL | rtr_Phone_Email.Default.PHONE_EMAIL |

### rule_Phone_Std

IDQ `MappletTx` &rarr; CDI **Mapplet**. Reusable CDI mapplet (see the mapplets folder).

Mapplet: [`rule_Phone_Std`](../mapplets/rule_Phone_Std.md)

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| Group.USG_TP | rtr_Phone_Email.Default.USG_TP |
| Group.Phone | Expression.PHONE_EMAIL1 |
| Group.SRC_SYS | Expression.SRC |

### RTR_Valid_PhoneNumbers

IDQ `RouterTx` &rarr; CDI **Router**. One output group per IDQ group; the default group is created automatically.

| Output group | Condition |
|---|---|
| Good_Records | `ISNULL(Phone_Exception_Code) or Phone_Exception_Code='Missing_AreaCode'` |
| Bad_Phone_Records | `NOT ISNULL(Phone_Exception_Code)` |
| Default | (default group) |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| Phone_Exception_Type | rule_Phone_Std.NEWOUTPUT.Phone_Exception_Type |
| Phone_Exception_Code | rule_Phone_Std.NEWOUTPUT.Phone_Exception_Code |
| Phone_Exception_Desc | rule_Phone_Std.NEWOUTPUT.Phone_Exception_Desc |
| ID_FAMILY_PHONE | rtr_Phone_Email.Default.ID_FAMILY_PHONE |
| ID_CASE | rtr_Phone_Email.Default.ID_CASE |
| PTY_RLE_FK | rtr_Phone_Email.Default.PTY_RLE_FK |
| SRC_ROWID | rtr_Phone_Email.Default.SRC_ROWID |
| PHONE_TP | rtr_Phone_Email.Default.PHONE_TP |
| USG_TP | rtr_Phone_Email.Default.USG_TP |
| PREF_LVL | rtr_Phone_Email.Default.PREF_LVL |
| PKEY_SRC_OBJECT_PTY | rtr_Phone_Email.Default.PKEY_SRC_OBJECT |
| SRC_LAST_UPDATE_DATE | rtr_Phone_Email.Default.PERIOD_START_DATE |
| PERIOD_START_DATE | rtr_Phone_Email.Default.PERIOD_START_DATE |
| LAST_UPDATE_DT | rtr_Phone_Email.Default.LAST_UPDATE_DT |
| WORK_EXT | rtr_Phone_Email.Default.WORK_EXT |
| PHONE_NUMBER | rule_Phone_Std.NEWOUTPUT.Phone |
| SOURCE_TABLE | rtr_Phone_Email.Default.SOURCE_TABLE |

### exp_Stage_Phone_Exceptions

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| SRC_SYS | out | string(50) | `'ECI'` |
| OBJECT_NAME | out | string(50) | `'C_S_ECI_PTY_RLE_PHN'` |
| EXCEPTION_CODE | in/out | string(255) |  |
| EXCEPTION_DESC | in/out | string(255) |  |
| EXC_Type | out | string(50) | `'Bad Value'` |
| PTY_RLE_FK | in/out | string(255) | `PTY_RLE_FK` |
| PHN_TP | in/out | string(20) | `PHN_TP` |
| RUN_DATE | out | date/time | `systimestamp()` |
| PERIOD_START_DATE | in/out | date/time | `PERIOD_START_DATE` |
| PTY_FK | in/out | string(255) | `PTY_FK` |
| USG_TP | in/out | string(255) | `USG_TP` |
| ATTRIBUTE_OUT | out | string(50) | `DECODE(true,<br>USG_TP='001', 'Main Phone',<br>USG_TP='002', 'Work Phone',<br>USG_TP='003', 'Other Phone'<br>)` |
| PREF_LVL | in/out | string(255) | `PREF_LVL` |
| PHN_NUM | in/out | string(20) | `PHN_NUM` |
| PRIMARY_PHONE | out | string(20) | `iif(PREF_LVL='Primary', PHN_NUM, null)` |
| WORK_PHONE | out | string(20) | `iif(USG_TP='Work', PHN_NUM, null)` |
| SECONDARY_PHONE | out | string(20) | `iif(PREF_LVL='Secondary', PHN_NUM, null)` |
| MAPPING_NAME | out | string(255) | `'m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr'` |
| CaseNumber | in/out | double | `CaseNumber` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| EXCEPTION_CODE | RTR_Valid_PhoneNumbers.Bad_Phone_Records.Phone_Exception_Code |
| EXCEPTION_DESC | RTR_Valid_PhoneNumbers.Bad_Phone_Records.Phone_Exception_Desc |
| PHN_NUM | RTR_Valid_PhoneNumbers.Bad_Phone_Records.PHONE_NUMBER |
| USG_TP | RTR_Valid_PhoneNumbers.Bad_Phone_Records.USG_TP |
| PERIOD_START_DATE | RTR_Valid_PhoneNumbers.Bad_Phone_Records.PERIOD_START_DATE |
| CaseNumber | RTR_Valid_PhoneNumbers.Bad_Phone_Records.ID_CASE |
| PTY_RLE_FK | RTR_Valid_PhoneNumbers.Bad_Phone_Records.PTY_RLE_FK |
| PREF_LVL | RTR_Valid_PhoneNumbers.Bad_Phone_Records.PREF_LVL |
| PHN_TP | RTR_Valid_PhoneNumbers.Bad_Phone_Records.PHONE_TP |

### write_Phone_EXC_STG_BAD_REC_MEMB

IDQ `TargetTx` &rarr; CDI **Target**. Oracle connector target.

| Property | Value |
|---|---|
| Connection | STAGING |
| Object | EXC_STG_BAD_REC_MEMB |
| Operation | Insert |
| Truncate target table | no |
| Load type | normal (no bulk load) |
| Reject file | Write_EXC_STG_BAD_REC_MEMB.bad |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| SRC_SYS | exp_Stage_Phone_Exceptions.SRC_SYS |
| EXCEPTION_CODE | exp_Stage_Phone_Exceptions.EXCEPTION_CODE |
| EXCEPTION_DESC | exp_Stage_Phone_Exceptions.EXCEPTION_DESC |
| RUN_DATE | exp_Stage_Phone_Exceptions.RUN_DATE |
| PRIMARY_PHONE | exp_Stage_Phone_Exceptions.PRIMARY_PHONE |
| WORK_PHONE | exp_Stage_Phone_Exceptions.WORK_PHONE |
| SECONDARY_PHONE | exp_Stage_Phone_Exceptions.SECONDARY_PHONE |
| MAPPING_NAME | exp_Stage_Phone_Exceptions.MAPPING_NAME |
| SRC_SYS_ID_1 | exp_Stage_Phone_Exceptions.PTY_FK |
| EXCEPTION_TYPE | exp_Stage_Phone_Exceptions.EXC_Type |
| SRC_SYS_ID_3 | exp_Stage_Phone_Exceptions.USG_TP |
| PERIOD_START_DATE | exp_Stage_Phone_Exceptions.PERIOD_START_DATE |
| ATTRIBUTE_VALUE | exp_Stage_Phone_Exceptions.PHN_NUM |
| SRC_SYS_ID_2 | exp_Stage_Phone_Exceptions.CaseNumber |
| ATTRIBUTE_NAME | exp_Stage_Phone_Exceptions.ATTRIBUTE_OUT |

### exp_Stage_Target_PhoneNumbers

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| PKEY_SRC_OBJECT_PTY | in/out | string(255) | `PKEY_SRC_OBJECT_PTY` |
| PERIOD_START_DATE | in/out | date/time | `PERIOD_START_DATE` |
| VERSION_SEQ (stale timeline: omit) | out | string(10) | `'1'` |
| LAST_UPDATE_DT | in/out | date/time | `LAST_UPDATE_DT` |
| SRC_ROWID | in/out | string(255) | `SRC_ROWID` |
| HUB_STATE_IND | out | decimal(10) | `1` |
| PTY_RLE_FK | in/out | string(255) | `PTY_RLE_FK` |
| PHONE_TP | in/out | string(10) | `PHONE_TP` |
| USG_TP | in/out | string(10) | `USG_TP` |
| PHONE_NUMBER | in/out | string(10) | `PHONE_NUMBER` |
| PREF_LVL | in/out | string(10) | `PREF_LVL` |
| WORK_EXT | in/out | string(5) | `WORK_EXT` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PKEY_SRC_OBJECT_PTY | RTR_Valid_PhoneNumbers.Good_Records.PKEY_SRC_OBJECT_PTY |
| PERIOD_START_DATE | RTR_Valid_PhoneNumbers.Good_Records.PERIOD_START_DATE |
| LAST_UPDATE_DT | RTR_Valid_PhoneNumbers.Good_Records.LAST_UPDATE_DT |
| SRC_ROWID | RTR_Valid_PhoneNumbers.Good_Records.SRC_ROWID |
| PTY_RLE_FK | RTR_Valid_PhoneNumbers.Good_Records.PTY_RLE_FK |
| PHONE_TP | RTR_Valid_PhoneNumbers.Good_Records.PHONE_TP |
| USG_TP | RTR_Valid_PhoneNumbers.Good_Records.USG_TP |
| PHONE_NUMBER | RTR_Valid_PhoneNumbers.Good_Records.PHONE_NUMBER |
| PREF_LVL | RTR_Valid_PhoneNumbers.Good_Records.PREF_LVL |
| WORK_EXT | RTR_Valid_PhoneNumbers.Good_Records.WORK_EXT |

### Write_C_S_ECI_PTY_RLE_PHN

IDQ `TargetTx` &rarr; CDI **Target**. Oracle connector target.

| Property | Value |
|---|---|
| Connection | HHS_MDM_ORS |
| Object | C_S_ECI_PTY_RLE_PHN |
| Operation | Insert |
| Truncate target table | yes |
| Load type | normal (no bulk load) |
| Reject file | Write_C_S_ECI_PTY_RLE_PHN.bad |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PKEY_SRC_OBJECT | exp_Stage_Target_PhoneNumbers.PKEY_SRC_OBJECT_PTY |
| PERIOD_START_DATE | exp_Stage_Target_PhoneNumbers.PERIOD_START_DATE |
| VERSION_SEQ (stale timeline: do not map) | exp_Stage_Target_PhoneNumbers.VERSION_SEQ |
| LAST_UPDATE_DATE | exp_Stage_Target_PhoneNumbers.LAST_UPDATE_DT |
| CREATE_DATE | exp_Stage_Target_PhoneNumbers.LAST_UPDATE_DT |
| SRC_ROWID | exp_Stage_Target_PhoneNumbers.SRC_ROWID |
| PTY_RLE_FK | exp_Stage_Target_PhoneNumbers.PTY_RLE_FK |
| PHN_TP | exp_Stage_Target_PhoneNumbers.PHONE_TP |
| USG_TP | exp_Stage_Target_PhoneNumbers.USG_TP |
| PHN_NUM | exp_Stage_Target_PhoneNumbers.PHONE_NUMBER |
| PREF_LVL | exp_Stage_Target_PhoneNumbers.PREF_LVL |
| SRC_LAST_UPD_DT | exp_Stage_Target_PhoneNumbers.PERIOD_START_DATE |
| PHN_NUM_EXT | exp_Stage_Target_PhoneNumbers.WORK_EXT |
| HUB_STATE_IND | exp_Stage_Target_PhoneNumbers.HUB_STATE_IND |

### rule_email_validation_v01

IDQ `MappletTx` &rarr; CDI **Mapplet**. Reusable CDI mapplet (see the mapplets folder).

Mapplet: [`rule_email_validation_v01`](../mapplets/rule_email_validation_v01.md)

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| Group.Email | rtr_Phone_Email.Email_Group.PHONE_EMAIL |

### exp_Setup_Attributes

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| PTY_RLE_FK | in/out | string(255) | `PTY_RLE_FK` |
| PKEY_SRC_OBJECT_EADDR | in/out | string(255) | `PKEY_SRC_OBJECT_EADDR` |
| PERIOD_START_DATE | in/out | date/time | `PERIOD_START_DATE` |
| ELEC_ADDR | in/out | string(200) | `ELEC_ADDR` |
| DQ_Exception | in/out | string(255) | `DQ_Exception` |
| DQ_Exception_Code | in/out | string(255) | `DQ_Exception_Code` |
| Email_Exception_Type | in/out | string(50) | `Email_Exception_Type` |
| src_Email | in/out | string(255) | `src_Email` |
| LAST_UPDATE_DT | in/out | date/time | `LAST_UPDATE_DT` |
| ID_FAMILY_PHONE | in/out | string(10) | `ID_FAMILY_PHONE` |
| SOURCE_TABLE | in/out | string(10) | `SOURCE_TABLE` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PKEY_SRC_OBJECT_EADDR | rtr_Phone_Email.Email_Group.PKEY_SRC_OBJECT |
| DQ_Exception | rule_email_validation_v01.NEWOUTPUT.EXCEPTION_DESC |
| DQ_Exception_Code | rule_email_validation_v01.NEWOUTPUT.EXCEPTION_CODE |
| PERIOD_START_DATE | rtr_Phone_Email.Email_Group.PERIOD_START_DATE |
| ELEC_ADDR | rule_email_validation_v01.NEWOUTPUT.EMAIL_ADDRESS |
| Email_Exception_Type | rule_email_validation_v01.NEWOUTPUT.EXCEPTION_TYPE |
| PTY_RLE_FK | rtr_Phone_Email.Email_Group.PTY_RLE_FK |
| src_Email | rtr_Phone_Email.Email_Group.PHONE_EMAIL |
| LAST_UPDATE_DT | rtr_Phone_Email.Email_Group.LAST_UPDATE_DT |
| ID_FAMILY_PHONE | rtr_Phone_Email.Email_Group.ID_FAMILY_PHONE |
| SOURCE_TABLE | rtr_Phone_Email.Email_Group.SOURCE_TABLE |

### rtr_Valid_EAddr_Records

IDQ `RouterTx` &rarr; CDI **Router**. One output group per IDQ group; the default group is created automatically.

| Output group | Condition |
|---|---|
| Valid_Records | `ISNULL(DQ_Exception_Code)` |
| Bad_Records | `NOT ISNULL(DQ_Exception_Code)` |
| Default | (default group) |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PKEY_SRC_OBJECT_EADDR | exp_Setup_Attributes.PKEY_SRC_OBJECT_EADDR |
| PERIOD_START_DATE | exp_Setup_Attributes.PERIOD_START_DATE |
| DQ_Exception | exp_Setup_Attributes.DQ_Exception |
| DQ_Exception_Code | exp_Setup_Attributes.DQ_Exception_Code |
| ELEC_ADDR | exp_Setup_Attributes.ELEC_ADDR |
| Email_Exception_Type | exp_Setup_Attributes.Email_Exception_Type |
| PTY_RLE_FK | exp_Setup_Attributes.PTY_RLE_FK |
| src_Email | exp_Setup_Attributes.src_Email |
| LAST_UPDATE_DT | exp_Setup_Attributes.LAST_UPDATE_DT |
| ID_FAMILY_PHONE | exp_Setup_Attributes.ID_FAMILY_PHONE |
| SOURCE_TABLE | exp_Setup_Attributes.SOURCE_TABLE |

### exp_Stage_Target_EAddr_Attributes

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| PKEY_SRC_OBJECT | in/out | string(255) |  |
| ROWID_OBJECT | in/out | string(14) |  |
| DELETED_IND | in/out | decimal(38) |  |
| DELETED_DATE | in/out | date/time |  |
| DELETED_BY | in/out | string(50) |  |
| PERIOD_START_DATE | in/out | date/time |  |
| PERIOD_END_DATE | in/out | date/time |  |
| VERSION_SEQ (stale timeline: omit) | out | decimal(38) | `'1'` |
| PERIOD_REFERENCE_TIME (stale timeline: omit) | in/out | date/time |  |
| TIMELINE_ACTION (stale timeline: omit) | in/out | decimal(38) |  |
| LAST_UPDATE_DATE | in/out | date/time |  |
| UPDATED_BY | in/out | string(50) |  |
| CREATE_DATE | in/out | date/time |  |
| CREATOR | in/out | string(50) |  |
| SRC_ROWID | out | string(30) | `PKEY_SRC_OBJECT` |
| HUB_STATE_IND | out | decimal(38) | `1` |
| PTY_RLE_FK | in/out | string(255) |  |
| ELEC_ADDR | in/out | string(200) |  |
| USG_TP | in/out | string(50) |  |
| ADDR_TP | out | string(20) | `'001'` |
| STS_CD | out | string(20) | `'Active'` |
| IS_VLD | out | string(1) | `'Y'` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PKEY_SRC_OBJECT | rtr_Valid_EAddr_Records.Valid_Records.PKEY_SRC_OBJECT_EADDR |
| PERIOD_START_DATE | rtr_Valid_EAddr_Records.Valid_Records.PERIOD_START_DATE |
| LAST_UPDATE_DATE | rtr_Valid_EAddr_Records.Valid_Records.LAST_UPDATE_DT |
| PTY_RLE_FK | rtr_Valid_EAddr_Records.Valid_Records.PTY_RLE_FK |
| ELEC_ADDR | rtr_Valid_EAddr_Records.Valid_Records.ELEC_ADDR |
| CREATE_DATE | rtr_Valid_EAddr_Records.Valid_Records.LAST_UPDATE_DT |

### exp_Stage_Email_Exceptions

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| SRC_SYS | out | string(50) | `'ECI'` |
| OBJECT_NAME | out | string(50) | `'C_S_ECI_PTY_RLE_EADDR'` |
| ID_FAMILY_PHONE | in/out | string(10) |  |
| PERIOD_START_DATE | in/out | date/time | `PERIOD_START_DATE` |
| EXCEPTION_CODE | in/out | string(255) |  |
| EXCEPTION_DESC | in/out | string(255) |  |
| RUN_DATE | out | date/time | `systimestamp()` |
| EMAIL | in/out | string(200) |  |
| Email_Exception_Type | in/out | string(50) | `Email_Exception_Type` |
| MAPPING_NAME | out | string(255) | `'m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr'` |
| Attribute_Name | out | string(30) | `'Email'` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| ID_FAMILY_PHONE | rtr_Valid_EAddr_Records.Bad_Records.ID_FAMILY_PHONE |
| EXCEPTION_CODE | rtr_Valid_EAddr_Records.Bad_Records.DQ_Exception_Code |
| EXCEPTION_DESC | rtr_Valid_EAddr_Records.Bad_Records.DQ_Exception |
| EMAIL | rtr_Valid_EAddr_Records.Bad_Records.src_Email |
| Email_Exception_Type | rtr_Valid_EAddr_Records.Bad_Records.Email_Exception_Type |
| PERIOD_START_DATE | rtr_Valid_EAddr_Records.Bad_Records.PERIOD_START_DATE |

### write_Email_EXC_STG_BAD_REC_MEMB

IDQ `TargetTx` &rarr; CDI **Target**. Oracle connector target.

| Property | Value |
|---|---|
| Connection | STAGING |
| Object | EXC_STG_BAD_REC_MEMB |
| Operation | Insert |
| Truncate target table | no |
| Load type | normal (no bulk load) |
| Reject file | Write_EXC_STG_BAD_REC_MEMB.bad |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| SRC_SYS | exp_Stage_Email_Exceptions.SRC_SYS |
| SRC_SYS_ID_1 | exp_Stage_Email_Exceptions.ID_FAMILY_PHONE |
| EXCEPTION_CODE | exp_Stage_Email_Exceptions.EXCEPTION_CODE |
| EXCEPTION_DESC | exp_Stage_Email_Exceptions.EXCEPTION_DESC |
| RUN_DATE | exp_Stage_Email_Exceptions.RUN_DATE |
| EMAIL | exp_Stage_Email_Exceptions.EMAIL |
| MAPPING_NAME | exp_Stage_Email_Exceptions.MAPPING_NAME |
| EXCEPTION_TYPE | exp_Stage_Email_Exceptions.Email_Exception_Type |
| PERIOD_START_DATE | exp_Stage_Email_Exceptions.PERIOD_START_DATE |
| ATTRIBUTE_VALUE | exp_Stage_Email_Exceptions.EMAIL |
| ATTRIBUTE_NAME | exp_Stage_Email_Exceptions.Attribute_Name |

### Write_C_S_ECI_PTY_RLE_EADDR

IDQ `TargetTx` &rarr; CDI **Target**. Oracle connector target.

| Property | Value |
|---|---|
| Connection | HHS_MDM_ORS |
| Object | C_S_ECI_PTY_RLE_EADDR |
| Operation | Insert |
| Truncate target table | yes |
| Load type | normal (no bulk load) |
| Reject file | Write_C_S_ECI_PTY_RLE_EADDR.bad |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| PKEY_SRC_OBJECT | exp_Stage_Target_EAddr_Attributes.PKEY_SRC_OBJECT |
| PERIOD_START_DATE | exp_Stage_Target_EAddr_Attributes.PERIOD_START_DATE |
| PERIOD_REFERENCE_TIME (stale timeline: do not map) | exp_Stage_Target_EAddr_Attributes.PERIOD_REFERENCE_TIME |
| LAST_UPDATE_DATE | exp_Stage_Target_EAddr_Attributes.LAST_UPDATE_DATE |
| CREATE_DATE | exp_Stage_Target_EAddr_Attributes.CREATE_DATE |
| SRC_ROWID | exp_Stage_Target_EAddr_Attributes.SRC_ROWID |
| PTY_RLE_FK | exp_Stage_Target_EAddr_Attributes.PTY_RLE_FK |
| ELEC_ADDR | exp_Stage_Target_EAddr_Attributes.ELEC_ADDR |
| USG_TP | exp_Stage_Target_EAddr_Attributes.USG_TP |
| ADDR_TP | exp_Stage_Target_EAddr_Attributes.ADDR_TP |
| STS_CD | exp_Stage_Target_EAddr_Attributes.STS_CD |
| IS_VLD | exp_Stage_Target_EAddr_Attributes.IS_VLD |
| SRC_LAST_UPD_DT | exp_Stage_Target_EAddr_Attributes.PERIOD_START_DATE |
| VERSION_SEQ (stale timeline: do not map) | exp_Stage_Target_EAddr_Attributes.VERSION_SEQ |
| HUB_STATE_IND | exp_Stage_Target_EAddr_Attributes.HUB_STATE_IND |

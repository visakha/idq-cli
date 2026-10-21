# rule_Phone_Extension_Std

IDQ mapplet &rarr; CDI **Mapplet** `rule_Phone_Extension_Std`.

> This mapplet validates the Phone Number Extension if numeric and at least 2 digits and up to 6 digits.
Returns "Valid" or "Invalid".

## Summary

| IDQ transformation | CDI transformation | Count |
|---|---|---|
| ExpressionTx | Expression | 1 |
| LookupTx | Lookup | 1 |
| MappletInputTx | Input | 1 |
| MappletOutputTx | Output | 1 |
| TokenStandardiserTx | Cleanse | 1 |

## Flow

```mermaid
flowchart LR
  n0["input<br/><i>Input</i>"]
  n1["STD_remove_special_char<br/><i>Cleanse</i>"]
  n2["exp_validate_Phone<br/><i>Expression</i>"]
  n3["Lookup_EXC_LOOKUP_CODE_VALUE<br/><i>Lookup</i>"]
  n4["output<br/><i>Output</i>"]
  n0 --> n1
  n1 --> n2
  n2 --> n3
  n2 --> n4
  n3 --> n4
```

## Transformations

In data-flow order.

### input

IDQ `MappletInputTx` &rarr; CDI **Input**. Mapplet Input transformation.

| Field | Type |
|---|---|
| Phone_Nbr_Ext | string(20) |

### STD_remove_special_char

IDQ `TokenStandardiserTx` &rarr; CDI **Cleanse**. CDQ Cleanse asset with remove/replace steps (see cdq.md).

Settings: (defaults)

- `TokenStandardiserStrategy` **STD_remove_special_Char** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Phone_Nbr_Ext`
- `FieldParameter` **Output** field=`Phone_Nbr_Ext`
- `RtmOp` **Remove Reference Table Matches**
- `Dictionary`  refTable=`ref_special_char_list`

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| Phone_Nbr_Ext | input.Phone_Nbr_Ext |

### exp_validate_Phone

IDQ `ExpressionTx` &rarr; CDI **Expression**. Same expression language; variable fields are supported.

| Field | Kind | Type | Expression (CDI) |
|---|---|---|---|
| Phone_Nbr_Ext | in/out | string(20) | `Phone_Nbr_Ext` |
| EXCEPTION_CODE1 | out | string(300) | `DECODE(TRUE,<br>(LENGTH(Phone_Nbr_Ext) < 2 <br>	OR LENGTH(Phone_Nbr_Ext) > 6),<br>'Invalid_Phone_Number_Ext',<br>NOT IS_NUMBER(Phone_Nbr_Ext),<br>'Invalid_Phone_Number_Ext',<br>NULL<br>)` |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| Phone_Nbr_Ext | STD_remove_special_char.Phone_Nbr_Ext |

### Lookup_EXC_LOOKUP_CODE_VALUE

IDQ `LookupTx` &rarr; CDI **Lookup**. Connected lookup unless a return port is set (then unconnected).

| Property | Value |
|---|---|
| Connection | STAGING |
| Object | EXC_LOOKUP_CODE_VALUE |
| Lookup condition | EXCEPTION_CODE = EXCEPTION_CODE1 |
| Multiple matches | Return any row |
| Cache | static cache |

| Lookup input field | Type |
|---|---|
| EXCEPTION_CODE1 | string(300) |

| Return / pass-through field | Feeds |
|---|---|
| EXCEPTION_CODE1 | output.Phone_Nbr_Ext_Exception_Code |
| EXCEPTION_TYPE | output.Phone_Nbr_Ext_Exception_Type |
| EXCEPTION_DESC | output.Phone_Nbr_Ext_Exception_Desc |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| EXCEPTION_CODE1 | exp_validate_Phone.EXCEPTION_CODE1 |

### output

IDQ `MappletOutputTx` &rarr; CDI **Output**. Mapplet Output transformation.

| Field | Type |
|---|---|
| Phone_Nbr_Ext | string(20) |
| Phone_Nbr_Ext_Exception_Type | string(300) |
| Phone_Nbr_Ext_Exception_Code | string(300) |
| Phone_Nbr_Ext_Exception_Desc | string(300) |

Links (target field &larr; upstream field):

| Field | From |
|---|---|
| Phone_Nbr_Ext | exp_validate_Phone.Phone_Nbr_Ext |
| Phone_Nbr_Ext_Exception_Type | Lookup_EXC_LOOKUP_CODE_VALUE.EXCEPTION_TYPE |
| Phone_Nbr_Ext_Exception_Code | Lookup_EXC_LOOKUP_CODE_VALUE.EXCEPTION_CODE1 |
| Phone_Nbr_Ext_Exception_Desc | Lookup_EXC_LOOKUP_CODE_VALUE.EXCEPTION_DESC |

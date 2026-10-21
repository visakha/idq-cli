# CDQ assets

The IDQ data quality transformations become CDQ assets that the CDI mapplets/mappings call through the Cleanse, Labeler and Verifier transformations.

## Dictionaries (from IDQ reference tables)

IDQ managed reference tables keep their rows in the reference data warehouse (connection shown), not in the export. Export the rows with the SQL below and import them into a CDQ **Dictionary** asset of the same name.

| Dictionary | Description | IDQ connection | Physical table | Columns (first = valid value) |
|---|---|---|---|---|
| ref_Valid_City | This reference table has valid City Names | INFA_STAGE | ref_Valid_City133231612434 | CITY_NM, CITY_NM1 |
| ref_MatchCode_Desc |  | INFA_STAGE | ref_MatchCode_Desc11021312 | Match_Code, Description |

```sql
SELECT * FROM ref_Valid_City133231612434;  -- INFA_STAGE: rows for dictionary ref_Valid_City
```

```sql
SELECT * FROM ref_MatchCode_Desc11021312;  -- INFA_STAGE: rows for dictionary ref_MatchCode_Desc
```

Referenced but not defined in this export (shared Model Repository project); export them from the Developer tool and create the dictionaries the same way:

| Dictionary | MRS project |
|---|---|
| ref_special_char_list | HHSC_SHARED |

## Assets by IDQ transformation

### vr_dq_Global_AddressValidation_Hybrid

From `dq_Global_AddressValidation_Hybrid` (`AvTx`) in [`mplt_Global_Addr_Validation`](mapplets/mplt_Global_Addr_Validation.md). Verifier asset (address verification, US). Map the input ports to the Verifier input fields and select the *linked* output fields listed in the mapplet spec (the AddressDoctor field names are kept in CDQ). Mode `CERTIFIED` = CASS-certified processing; casing, default and force country as listed.

- `AvOptionSet`
- `AvStringOption` **MaxResultCount** optionValue=`5`
- `AvStringOption` **Process:EnrichmentGeoCodingType** optionValue=`NONE`

### cl_stdr_City_Name

From `stdr_City_Name` (`TokenStandardiserTx`) in [`mplt_Global_Addr_Validation`](mapplets/mplt_Global_Addr_Validation.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **stdr_City_name** delimiters=` `, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`City_12_Bytes`
- `FieldParameter` **Output** field=`City`
- `UserOp` **Replace Custom Strings** replace=`true`, replacement=` `, searchStrings=`  `

### cl_stdr_Name_Correction

From `stdr_Name_Correction` (`TokenStandardiserTx`) in [`mplt_Global_Addr_Validation`](mapplets/mplt_Global_Addr_Validation.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **stdr_Name_Correction** delimiters=` `, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`City`
- `FieldParameter` **Output** field=`City`
- `RtmOp` **Replace Reference Table Matches with Valid Values** replace=`true`, useRtmReplacement=`true`
- `Dictionary`  refTable=`ref_Valid_City`

### cl_std_Remove_Junk_Char_Indv

From `std_Remove_Junk_Char_Indv` (`TokenStandardiserTx`) in [`mplt_Name_Standardization_Indv_Member`](mapplets/mplt_Name_Standardization_Indv_Member.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **std_Remove_Junk_First_Name** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`First_Name`
- `FieldParameter` **Output** field=`First_Name`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ! ` @ # $ % ^ & * ( ) _ + = " : ; ? / . > , < 	 ``
- `TokenStandardiserStrategy` **std_Remove_Junk_MDL_Name** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Mdl_Name`
- `FieldParameter` **Output** field=`Mdl_Name`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ` ! @ # $ % ^ & * ( ) _ - + = } { [ ] | \ " ' : ; ? / > . < , 	 ``
- `TokenStandardiserStrategy` **std_Remove_Junk_Last_Name** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Last_Name`
- `FieldParameter` **Output** field=`Lst_Name`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ` ! @ # $ % ^ & * ( ) _ + = | \ } { [ ] " ; : ? > . < , 	 ``
- `TokenStandardiserStrategy` **std_Remove_Junk_Full_Name** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Full_Name`
- `FieldParameter` **Output** field=`Full_Name`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ` ! @ # $ % ^ * ( ) _ + = \ | } ] { [ " : ; ? / > . < , 	 ``
- `TokenStandardiserStrategy` **std_Remove_Junk_Org_Name** trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Org_Name`
- `FieldParameter` **Output** field=`Org_Name`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ` ! @ # $ % ^ * ( ) _ + = | \ } ] { [ " : ; ? / > . < , 	 ``
- `TokenStandardiserStrategy` **std_Remove_Junk_DBA_Name** trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`DBA_Name`
- `FieldParameter` **Output** field=`DBA_Name`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ` ! @ # $ % ^ * ( ) _ - + = | \ } ] { [ " ' : ; ? / > . < , 	 ``

### cl_cc_Name_Title_Case

From `cc_Name_Title_Case` (`CaseConverterTx`) in [`mplt_Name_Standardization_Indv_Member`](mapplets/mplt_Name_Standardization_Indv_Member.md). Cleanse asset, step **Change Case** with the conversion type listed. Equivalent CDI Expression: `UPPER()` / `LOWER()` / `INITCAP()` (Title).

- `CaseConverterTxStrategy` **cc_First_Name** conversionType=`TITLE`, delimiterList=` `
  - function: `TITLE`
- `FieldParameter` **First_Name** field=`First_Name`
- `FieldParameter` **Output** field=`First_Name`
- `CaseConverterTxStrategy` **cc_MDL_Name** conversionType=`TITLE`, delimiterList=` `
  - function: `TITLE`
- `FieldParameter` **Mdl_Name** field=`Mdl_Name`
- `FieldParameter` **Output** field=`Mdl_Name`
- `CaseConverterTxStrategy` **cc_Last_Name** conversionType=`TITLE`, delimiterList=` `
  - function: `TITLE`
- `FieldParameter` **Lst_Name** field=`Lst_Name`
- `FieldParameter` **Output** field=`Lst_Name`
- `CaseConverterTxStrategy` **cc_Full_Name** conversionType=`TITLE`, delimiterList=` `
  - function: `TITLE`
- `FieldParameter` **Full_Name** field=`Full_Name`
- `FieldParameter` **Output** field=`Full_Name`
- `CaseConverterTxStrategy` **cc_Org_Name** conversionType=`TITLE`, delimiterList=` `
  - function: `TITLE`
- `FieldParameter` **Org_Name** field=`Org_Name`
- `FieldParameter` **Output** field=`Org_Name`
- `CaseConverterTxStrategy` **cc_DBA_Name** conversionType=`TITLE`, delimiterList=` `
  - function: `TITLE`
- `FieldParameter` **DBA_Name** field=`DBA_Name`
- `FieldParameter` **Output** field=`DBA_Name`

### lb_lbl_Name_Zero

From `lbl_Name_Zero` (`LabelerTx`) in [`mplt_Name_Standardization_Trailing_Num_Removal`](mapplets/mplt_Name_Standardization_Trailing_Num_Removal.md). Labeler asset. Character labeling &rarr; *Character Labels* with the same character sets; token labeling &rarr; *Token Labels* with the same token sets / regular expressions and delimiters.

- `LabelerTxStrategy` **FName** outputField=`Fname_lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`FName`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`Fname_lbl`
- `CharacterLabel` **Label_FName** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=``
- `LabelerTxStrategy` **LName** outputField=`LName_Lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`LName`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`LName_Lbl`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=``
- `LabelerTxStrategy` **FullName** outputField=`FullName_lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`Full_Name`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`FullName_lbl`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=``
- `LabelerTxStrategy` **MName** outputField=`MName_lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`MName`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`MName_lbl`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=``

### lb_lbl_Name_Nbr

From `lbl_Name_Nbr` (`LabelerTx`) in [`mplt_Name_Standardization_Trailing_Num_Removal`](mapplets/mplt_Name_Standardization_Trailing_Num_Removal.md). Labeler asset. Character labeling &rarr; *Character Labels* with the same character sets; token labeling &rarr; *Token Labels* with the same token sets / regular expressions and delimiters.

- `LabelerTxStrategy` **FName_lbl** outputField=`FName_lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`FName`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`FName_lbl`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=` `
- `LabelerTxStrategy` **LName_lbl** outputField=`LName_lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`LName`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`LName_lbl`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=` `
- `LabelerTxStrategy` **FullName_lbl** outputField=`FullName_lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`FullName`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`FullName_lbl`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=` `
- `LabelerTxStrategy` **MName_lbl** outputField=`MName_lbl`
  - function: `labeler`
- `FieldParameter` **Input** field=`MName`, parameter=`Input0`
- `FieldParameter` **LabeledOutput** field=`MName_lbl`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`EnglishAlphabet`, labelOverrides=` `

### cl_std_Bad_Data

From `std_Bad_Data` (`TokenStandardiserTx`) in [`rule_Addr_Line_Post_Scrub`](mapplets/rule_Addr_Line_Post_Scrub.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **Standardizer1** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`AddressLine1`
- `FieldParameter` **Output** field=`AddressLine1`
- `UserOp` **ReplaceCustomStrings** replace=`true`, replacement=`c/o `, scope=`start`, searchStrings=`C/O `
- `UserOp` **Replace Custom Strings1** replace=`true`, replacement=` c/o `, searchStrings=` C/O `
- `UserOp` **Remove Custom Strings** scope=`end`, searchStrings=`# Apt Bldg Dept Fl Hngr Key Lot Pier Rm Slip Spc Stop Ste Trlr Unit`
- `TokenStandardiserStrategy` **Standardizer2** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`AddressLine2`
- `FieldParameter` **Output** field=`AddressLine2`
- `UserOp` **Replace Custom Strings** replace=`true`, replacement=`c/o `, scope=`start`, searchStrings=`C/O `
- `UserOp` **Replace Custom Strings1** replace=`true`, replacement=` c/o `, searchStrings=` C/O `
- `UserOp` **Remove Custom Strings** scope=`end`, searchStrings=`# Apt Bldg Dept Fl Hngr Key Lot Pier Rm Slip Spc Stop Ste Trlr Unit`

### cl_std_Remove_Junk_Characters

From `std_Remove_Junk_Characters` (`TokenStandardiserTx`) in [`rule_Addr_Line_Pre_Scrub1`](mapplets/rule_Addr_Line_Pre_Scrub1.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **Standardizer1** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Address_Line1`
- `FieldParameter` **Output** field=`Address_Line1`
- `UserOp` **Remove Custom Strings** searchStrings=`$ ) ( @ ^ ! ~ * % + _ = { } [ ] | : ; " ' < > ? &`
- `TokenStandardiserStrategy` **Standardizer2** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Address_Line2`
- `FieldParameter` **Output** field=`Address_Line2`
- `UserOp` **Remove Custom Strings** searchStrings=`$ ) ( @ ^ ! ~ * % + - = { } [ ] | : ; " ' < > ? &`

### cl_std_Replace_Hash_and_Slash

From `std_Replace_Hash_and_Slash` (`TokenStandardiserTx`) in [`rule_Addr_Line_Pre_Scrub1`](mapplets/rule_Addr_Line_Pre_Scrub1.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **Standardizer1**
  - function: `standardizer`
- `FieldParameter` **Input** field=`Address_Line1`
- `FieldParameter` **Output** field=`Address_Line1`
- `UserOp` **Replace Custom Strings** replace=`true`, replacement=`#`, searchStrings=`# # # # # # # # # ### ##`
- `UserOp` **Replace Custom Strings1** replace=`true`, replacement=`/`, searchStrings=`\`
- `TokenStandardiserStrategy` **Standardizer2**
  - function: `standardizer`
- `FieldParameter` **Input** field=`Address_Line2`
- `FieldParameter` **Output** field=`Address_Line2`
- `UserOp` **Replace Custom Strings** replace=`true`, replacement=`#`, searchStrings=`# # # # # # # # # ### ##`
- `UserOp` **Replace Custom Strings1** replace=`true`, replacement=`/`, searchStrings=`\`

### cl_Case_Converter

From `Case_Converter` (`CaseConverterTx`) in [`rule_Addr_Line_Pre_Scrub1`](mapplets/rule_Addr_Line_Pre_Scrub1.md). Cleanse asset, step **Change Case** with the conversion type listed. Equivalent CDI Expression: `UPPER()` / `LOWER()` / `INITCAP()` (Title).

- `CaseConverterTxStrategy` **CaseConverter**
  - function: `TOUPPER`
- `FieldParameter` **Address_Line1** field=`Address_Line1`
- `FieldParameter` **Address_Line2** field=`Address_Line2`
- `FieldParameter` **Output** field=`Address_Line1`
- `FieldParameter` **Output1** field=`Address_Line2`

### cl_STD_remove_special_char

From `STD_remove_special_char` (`TokenStandardiserTx`) in [`rule_MEDICAID_ID_Std`](mapplets/rule_MEDICAID_ID_Std.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **STD_remove_special_Char** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`MEDICAID_ID`
- `FieldParameter` **Output** field=`MEDICAID_ID`
- `RtmOp` **Remove Reference Table Matches**
- `Dictionary`  filename=`ref_special_char_list`, path=`HHSC_SHARED`, refTable=`ref_special_char_list`

### cl_std_to_number

From `std_to_number` (`TokenStandardiserTx`) in [`rule_Phone_Std`](mapplets/rule_Phone_Std.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **std_Remove_Junk_MDL_Name** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Phione`
- `FieldParameter` **Output** field=`Phone`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ` ! @ # $ % ^ & * ( ) _ - + = } { [ ] | \ " ' : ; ? / > . < , 	   ``

### lb_dq_Label_Characters

From `dq_Label_Characters` (`LabelerTx`) in [`rule_USA_SSN_Validation_post_June2011`](mapplets/rule_USA_SSN_Validation_post_June2011.md). Labeler asset. Character labeling &rarr; *Character Labels* with the same character sets; token labeling &rarr; *Token Labels* with the same token sets / regular expressions and delimiters.

- `LabelerTxStrategy` **Label Chars** delimiters=` `, outputField=`Out_SSN`
  - function: `labeler`
- `FieldParameter` **Input** field=`In_SSN`
- `FieldParameter` **LabeledOutput** field=`Out_SSN`
- `CharacterLabel` **Label Characters using Character Sets** enabled=`true`, characterSets=`English+alphabet`, labelOverrides=``
  - character set **English alphabet**: label `X`, characters `a-z, A-Z`

### lb_dq_Validate_SSN

From `dq_Validate_SSN` (`LabelerTx`) in [`rule_USA_SSN_Validation_post_June2011`](mapplets/rule_USA_SSN_Validation_post_June2011.md). Labeler asset. Character labeling &rarr; *Character Labels* with the same character sets; token labeling &rarr; *Token Labels* with the same token sets / regular expressions and delimiters.

- `LabelerTxStrategy` **Labeler1** labelerType=`token`, outputField=`Out_SSN_Status`, tokenizedOutputField=`TokenizedData`
  - function: `labeler`
- `FieldParameter` **Input** field=`In_SSN`
- `FieldParameter` **LabeledOutput** field=`Out_SSN_Status`
- `FieldParameter` **Output** field=`TokenizedData`
- `TokenLabel` **Label Tokens with Token Set** enabled=`true`, labelOverrides=`*`, preserveCases=`false`
- `ExecutionItem`  tokenSetReference=`National_ID_USA_exact`
  - token set **National_ID_USA_exact**: label `USANATID1`, regular expression `^(?!219[- ]?09[- ]?9999|078[- ]?05[- ]?1120)(?!666|000|9\d{2})\d{3}[- ]?(?!00)\d{2}[- ]?(?!0{4})\d{4}$` (Matches the format of the US Social Security Number (SSN). Performs some basic rule checks on certain number ranges that are not allowed.)

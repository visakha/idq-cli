# CDQ assets

The IDQ data quality transformations become CDQ assets that the CDI mapplets/mappings call through the Cleanse, Labeler and Verifier transformations.

## Dictionaries (from IDQ reference tables)

IDQ managed reference tables keep their rows in the reference data warehouse (connection shown), not in the export. Export the rows with the SQL below and import them into a CDQ **Dictionary** asset of the same name.

Referenced but not defined in this export (shared Model Repository project); export them from the Developer tool and create the dictionaries the same way:

| Dictionary | MRS project |
|---|---|
|  |  |

## Assets by IDQ transformation

### cl_std_Remove_Junk_Char_Indv

From `std_Remove_Junk_Char_Indv` (`TokenStandardiserTx`) in [`CopyOf_mplt_Name_Standardization_Indv_Member`](mapplets/CopyOf_mplt_Name_Standardization_Indv_Member.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

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

From `cc_Name_Title_Case` (`CaseConverterTx`) in [`CopyOf_mplt_Name_Standardization_Indv_Member`](mapplets/CopyOf_mplt_Name_Standardization_Indv_Member.md). Cleanse asset, step **Change Case** with the conversion type listed. Equivalent CDI Expression: `UPPER()` / `LOWER()` / `INITCAP()` (Title).

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

From `lbl_Name_Zero` (`LabelerTx`) in [`CopyOf_mplt_Name_Standardization_Trailing_Num_Removal`](mapplets/CopyOf_mplt_Name_Standardization_Trailing_Num_Removal.md). Labeler asset. Character labeling &rarr; *Character Labels* with the same character sets; token labeling &rarr; *Token Labels* with the same token sets / regular expressions and delimiters.

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

From `lbl_Name_Nbr` (`LabelerTx`) in [`CopyOf_mplt_Name_Standardization_Trailing_Num_Removal`](mapplets/CopyOf_mplt_Name_Standardization_Trailing_Num_Removal.md). Labeler asset. Character labeling &rarr; *Character Labels* with the same character sets; token labeling &rarr; *Token Labels* with the same token sets / regular expressions and delimiters.

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

### cl_STD_remove_special_char

From `STD_remove_special_char` (`TokenStandardiserTx`) in [`rule_Phone_Extension_Std`](mapplets/rule_Phone_Extension_Std.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **STD_remove_special_Char** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Phone_Nbr_Ext`
- `FieldParameter` **Output** field=`Phone_Nbr_Ext`
- `RtmOp` **Remove Reference Table Matches**
- `Dictionary`  refTable=`ref_special_char_list`

### cl_std_to_number

From `std_to_number` (`TokenStandardiserTx`) in [`rule_Phone_Std`](mapplets/rule_Phone_Std.md). Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and *remove multiple spaces* options as Cleanse steps **Remove Spaces**.

- `TokenStandardiserStrategy` **std_Remove_Junk_MDL_Name** removeMultipleSpaces=`true`, trim=`true`
  - function: `standardizer`
- `FieldParameter` **Input** field=`Phione`
- `FieldParameter` **Output** field=`Phone`
- `UserOp` **Remove Custom Strings** searchStrings=`` ~ ` ! @ # $ % ^ & * ( ) _ - + = } { [ ] | \ " ' : ; ? / > . < , 	   ``

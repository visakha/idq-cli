# Common insights: how the IDQ stage loads really behave

These are the surprises found while reading the six IDQ workflow exports (`docs/wf_*.xml`) line by line: once for
the Java port (`docs/mappings`), once for the IDMC specs (`idmc/`), once for the Oracle procedures
(`idq-to-oracle/`) and once for the Snowflake procedures (`idq-to-snowflake/`, which also write out the mapplets). Each one is something a reader of the mapping names, descriptions or diagrams would probably get
wrong.

Unless the entry says otherwise, every port keeps the behaviour as IDQ runs it, and the procedure header in
`idq-to-oracle/<workflow>/sp_ors_main_<mapping>.sql` explains it again at the place where it applies.

**Contents**

1. [Likely defects to confirm with the business](#1-likely-defects-to-confirm-with-the-business)
2. [Rows that are loaded and logged as exceptions](#2-rows-that-are-loaded-and-logged-as-exceptions)
3. [Exception codes that depend on configuration](#3-exception-codes-that-depend-on-configuration)
4. [Filters and SQL stored in the export but not applied](#4-filters-and-sql-stored-in-the-export-but-not-applied)
5. [Columns that are always NULL](#5-columns-that-are-always-null)
6. [IDQ engine semantics the mappings depend on](#6-idq-engine-semantics-the-mappings-depend-on)
7. [How the workflows hang together](#7-how-the-workflows-hang-together)
8. [The MDM timeline: mostly hard-coded, sometimes real](#8-the-mdm-timeline-mostly-hard-coded-sometimes-real)
9. [Mapplet and rule quirks](#9-mapplet-and-rule-quirks)
10. [Copy-paste traces between sources](#10-copy-paste-traces-between-sources)
11. [Data model and environment](#11-data-model-and-environment)
12. [Risks when re-platforming](#12-risks-when-re-platforming)

---

## 1. Likely defects to confirm with the business

| # | Where | What IDQ does | Effect |
|---|---|---|---|
| 1.1 | `m_Tgt_C_S_FSS_Pty_Validation` | The *Reactivation* group writes into the **status** table `STG_FSS_PTY_INACTIVE_STS`, with `DEACTIVATION_STS = 'Reactivation'`, not into the log table. It does this after deleting the old status row. ECI, TTF and WIC write reactivations to their `*_INACTIVE_LOG` table. | Every later FSS mapping skips a party that has *any* status row, so **a reactivated FSS client stays excluded for good**. |
| 1.2 | `m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` | `Filt_Keep_New_Medicaid` tests the **source** port `ID_MEDICAID` instead of the lookup result `lkp_ID_MEDICAID`. The sister mappings `_D_Family_Addr` and `_D_Family_Phn` test the lookup result. | `ID_MEDICAID` is the history key and is never NULL, so **the mapping never writes a row**. Medicaid records of reactivated children are not re-sent. The Oracle procedure has `p_test_lookup_result => 'Y'` for the intended behaviour. |
| 1.3 | `m_Tgt_C_S_ECI_Pty` | `Flt_Remove_Inactive` is stored as `--not IsNull(DEACTIVATION_STS)`. | `--not` is an IDQ comment, so the condition is `IsNull(...)`: the filter keeps **active** parties. That is correct, but it reads as the opposite. |
| 1.4 | `m_Tgt_C_S_TTF_Pty` | The `Invalid_Language` and `Invalid_Suffix` router groups test ports that nothing feeds, and they have no target. | TTF never reports language or suffix problems, and `PRFRD_LANG_CD` / `SFX_NM` are always NULL. |
| 1.5 | `m_Tgt_C_S_TTF_Pty_Rle_Phn` | The extension port that feeds `rule_Phone_Extension_Std` has no input. | The extension is always NULL, so the `Bad_Phone_Ext__Records` group never fires. |
| 1.6 | `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` | An invalid SSN is **blanked** by the rule, and blank ids are then dropped. | An invalid SSN never reaches `EXC_STG_BAD_REC_MEMB`. It just disappears. |
| 1.7 | `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` | `fltr_Rank` keeps `VERSION_SEQ = 1`, but `VERSION_SEQ` is hard-coded to 1 because the rank is commented out. | The filter is a no-op: **no de-duplication happens**, and several rows per key can reach `C_S_TRS_PTY_RLE_ALT_ID`. |
| 1.8 | `m_Tgt_C_S_TRS_Pty_OnGoing` | The race and ethnicity exception rows take `ATTRIBUTE_VALUE` from the **master** code, which is linked from `MDM_Race_Cd`. | The master code is NULL exactly when the exception fires, so the exception never shows the bad source value. |
| 1.9 | `m_Tgt_C_S_ECI_Pty` | Exception rows write `MAPPING_NAME = 'm_Tgt_C_S_ECI_Pty_OnGoing'`, a literal. | Exception reports filtered by the real mapping name miss these rows. |
| 1.10 | `m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1` | The description says the mapping removes relationships from a valid list, but there is no such target. `PROCESSED_YN` is not linked. | Only the log insert happens, and `PROCESSED_YN` comes from the column default. |
| 1.11 | `m_Tgt_C_S_TTF_Pty` | The party `PERIOD_START_DATE` is `$sys.MappingRunStartTime`. The role uses `SUBMITDATE`. | The party start date changes on every run even when nothing changed. |
| 1.12 | `m_Tgt_C_S_ECI_Pty_Rle_Rel` | `CREATE_DATE` is linked from `DATE_MODIFIED`. | Create and modify dates are mixed up in the role relationship table. |
| 1.13 | `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` | The SSN exception row has no `RUN_DATE` linked. | These exception rows have `RUN_DATE` NULL, so they drop out of any report by run. |
| 1.14 | `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | Unlike FSS and TTF, there is no null-phone filter before `rule_Phone_Std`. | A WIC party with no phone is validated and, when the rule flags it, logged as a phone exception. |
| 1.15 | `mplt_Date_Greater_Than_Fifty_Years` (`m_Tgt_C_S_TRS_Addr_2`) | `out_Date_Diff = DATE_DIFF(Input_Date, SYSDATE, 'YY')` is a **string(10)** port, and `out_Date` tests `out_Date_Diff > '50'`, a **text** comparison. | Besides end dates more than 50 years ahead, end dates **6 to 10 years ahead** become NULL (`'6.2' > '50'` as text), and dates 100+ years ahead are kept (`'100' < '50'`). A TRS address ending in 7 years is loaded as open-ended. The Snowflake port reproduces it (`fn_snow_helper21_common`); confirm on IDQ, then decide whether to fix. |
| 1.16 | `mplt_Member_Pty_Rle_Phn_Normalization` (`m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`) | The three `rule_Phone_Std` instances get only `Phone`; their `SRC_SYS` and `USG_TP` inputs are not linked. | The rule's own "TRS / CRE / ECI main and other numbers may not be toll-free" check never runs for TRS phones, the one source it was written for. |
| 1.17 | `m_Tgt_C_S_CRE_CARE_Clients` | `rule_Phone_Std` gets only `Phone` here too (`SRC_SYS` and `USG_TP` not linked). | The toll-free check never runs for CRE either: of the three sources it names, only ECI uses it. |
| 1.18 | `m_Tgt_C_S_CRE_CARE_Clients` | `FLTR_CRE_MRG` keeps the case moves whose source and target records have **no** merge history, including moves whose CARE ids have no `C_B_PTY_XREF` row at all. The move target row (`REC_TYPE 'A'`) goes through the same lookups when the snapshot gives it a `MAINT_FLAG`. | `CRE_SRC_MRG` gets rows with both `ROWID_OBJECT`s NULL, and the same move can be written twice in one run. |
| 1.19 | `m_Tgt_C_S_CRE_CARE_Clients` | For an unmerged move the `CARE ID` alternate id is built from `MRG_CARE_ID` = the **target** CARE id, but its key and role are the **source** member's (`<source>|Member|<type>|<target id>`). The exception rows of the Medicaid id and SSN carry the target id as `SRC_SYS_ID_1`. | The moved-away member is published with the target's CARE id. The source and target of one move can log the same Medicaid / SSN exception under the same key (see 12.7). |
| 1.20 | `m_Tgt_C_S_CRE_CARE_Clients` | `RTR_VALID_ADDRESS` keeps an address when `(TO_INTEGER(MailabilityScore) >= 3 OR NOT IN(SUBSTR(MatchCode,1,1),'I','N')) AND` a state FIPS. Without a score and a match code both tests are NULL. The other address mappings test the opposite way (a missing score is good). | A US address that AddressDoctor returns without score and match code is an exception in CRE but loaded elsewhere. With the pass-through validator of the Java, Oracle-contract and Snowflake ports, **every US CRE address is an exception**; only addresses abroad are loaded. |

## 2. Rows that are loaded and logged as exceptions

An IDQ **Router sends a row to every group whose condition is true**, not only the first one. Together with a few
`TRUE` conditions, this means a row in the exception table is often **also** in the `C_S_*` table.

- **ECI, FSS, TTF and WIC party mappings** (`m_Tgt_C_S_<SRC>_Pty`): the `Valid_Party` group condition is `TRUE`.
  Every active party is loaded, and each failed rule (gender, birth date, ethnicity, race, language, suffix) adds an
  exception row as well. An exception does not reject the party.
- **TRS party** (`m_Tgt_C_S_TRS_Pty_OnGoing`): `Valid_Party` is *first name **or** last name present*. A party with
  only one of the two names is loaded **and** logged as `Missing_First_Name` / `Missing_Last_Name`. Gender and death
  date problems never reject a party.
- **ECI and WIC phones**: a `Missing_AreaCode` phone matches both `Good_Records` and `Bad_Phone_Records`, so it is
  loaded **and** logged.
- **FSS phones**: a row with a good phone and a bad extension is loaded (with the extension blanked) **and** logged
  as `Bad Value`.
- **TRS type of assistance** (`m_Tgt_C_S_TRS_Pty_Rle_TOA`): a row with an untranslated TOA code **and** begin date
  after end date writes **two** exception rows.
- **Validation mappings**: an `Invalid_Party_Name` row also matches `Deactivation`, so it is both logged as an
  exception and deactivated.

## 3. Exception codes that depend on configuration

Some mappings write the exception code **computed** in the mapping. Others write the code **returned by the
`EXC_LOOKUP_CODE_VALUE` lookup**, which is NULL when the code is not configured there. Routers that test the
looked-up code treat an unconfigured exception as *no exception*.

| Mapping | Exception | Behaviour when the code is missing from `EXC_LOOKUP_CODE_VALUE` |
|---|---|---|
| `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` | `Invalid_SSN` | Row written with `EXCEPTION_CODE` NULL. (`Invalid_Medicaid_Id` writes the computed code.) |
| `m_Tgt_C_S_ECI_Pty_Rle_Rel`, `m_Tgt_C_S_FSS_Pty_Rle_Rel` | `Invalid_Relationship` | `EXCEPTION_CODE` NULL |
| `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` | `Invalid_Email` | **The e-mail is treated as valid and loaded**, because the router tests the looked-up code |
| `m_Tgt_C_S_TRS_Pty_Rle_TOA` | `Invalid_TOA` | `EXCEPTION_CODE` NULL. (The date exception writes the computed code.) |
| `m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem` | `Invalid_Rel_Type` | `EXCEPTION_CODE` NULL |
| `m_Tgt_C_S_TRS_Addr_2` | `Invalid_Address` | `EXCEPTION_CODE` NULL |
| `m_Tgt_C_S_TRS_Pty_OnGoing` | `Invalid_Death_Date`, `Invalid_Gender`, race, ethnicity | **No exception row at all**: the router only fires when the code is configured |

| `m_Tgt_C_S_CRE_CARE_Clients` | `Missing_First_Name`, `Missing_Last_Name` | **No exception row**, and the member is still dropped: it silently disappears |
| `m_Tgt_C_S_CRE_CARE_Clients` | `Invalid_Phone_Number`, `Invalid_SSN` | **The phone / SSN is treated as valid and loaded** |
| `m_Tgt_C_S_CRE_CARE_Clients` | `Invalid_Address` | Row written with `EXCEPTION_CODE` NULL (the hard-coded type and description of the mapping, which are swapped, are not written) |
| `m_Tgt_C_S_CRE_CARE_Clients` | `Invalid_Gender`, `Invalid_Ethnicity`, `Invalid_Race` | No exception row. (`Invalid_Suffix` and `Invalid_Medicaid_Id` write the computed code.) |

Keep `EXC_LOOKUP_CODE_VALUE` complete. A missing row silently changes what is loaded and what is reported.

The ECI, FSS and WIC address mappings do not look the description up. They hard-code
`'Invalid Address per Address Doctor'` and type `'Bad Value'`.

## 4. Filters and SQL stored in the export but not applied

| Mapping | Stored next to the source | Applied? |
|---|---|---|
| `m_Tgt_C_S_ECI_Pty` | filter on five hard-coded child ids | No: the source uses custom SQL, which replaces the generated query and its filter |
| `m_Tgt_C_S_TRS_Pty_OnGoing`, `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` | `INDV_ID = 504937068` | No, same reason |
| `m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` | `rownum < 100000` | No, same reason |
| `m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP` | `PROVIDER_NUM is not null` | Already in the custom query's `WHERE` |
| `m_Tgt_C_S_TRS_Addr_2` | *select distinct* | No: ignored with custom SQL |
| `m_Tgt_C_S_TTF_Pty_Validation`, `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` | a SQL `WHERE` fragment with test client ids | No: the read is not in custom-query mode |
| `m_Tgt_C_S_TTF_Pty_Rle_Phn` | the invalid fragment `"PHONE" in ()` | No: not in custom-query mode (it would not even parse) |
| FSS sources | testing filters | Already commented out in IDQ |

These look like test leftovers. They are harmless today, but they become live if someone switches a source back to a
generated query, and the TTF fragment would then break the read. They are worth deleting from IDQ, or at least not
carrying into a new platform.

## 5. Columns that are always NULL

Many target columns are linked to ports that nothing feeds. The column looks mapped in the designer, but it is always
NULL. The ones that matter most:

- **`FLR_NUM`** in the ECI, FSS and WIC address targets: the router port `Sub_buildingNumber` has no input link.
- **`LCTN_CRDNT_DESC`**, `PSTL_BRCD`, `RGN_CD`, `CRDNT_SYS`, `USG_TP` in every address target.
- **CRE** (`m_Tgt_C_S_CRE_CARE_Clients`): `HUB_STATE_IND`, `LOC_IDN` and `SRC_ADDR_LN_2` in every target,
  `CREATE_DATE` of `C_S_CRE_PTY_RLE_ALT_ID`, and `MDL_NM` / `PRFX_NM` of `C_S_CRE_PTY`. `PKEY_SRC_OBJECT_ADDR` (the
  validated address text) is computed but linked nowhere.
- **`HUB_STATE_IND`** in most `C_S_*` targets. The exceptions are the TRS relationship targets, where the timeline
  mapplet sets 1 on the current open row. `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` does not link it at all, so it gets the
  column default.
- **`PERIOD_END_DATE` / `EFF_END_DT`** in the ECI, FSS and WIC address targets, and `PERIOD_END_DATE` of
  `C_S_TRS_PTY` (a `MAX()` of an unfed port).
- **Exception table identifiers**: `SRC_SYS_ID_1` of ECI phone exceptions (from the unfed `PTY_FK`) and
  `SRC_SYS_ID_2` of TTF phone exceptions (from the unfed `ID_PHONE`).
- **`SRC_STATE`** of WIC addresses: `'TX'` is passed to the validator, but the source-state port is unfed.
- `CREATE_DATE` of `C_S_TRS_PTY_RLE_REL_PROV`, `SRC_COUNTY` of `STG_TRS_D_UNQ_ADDR`.
- The audit columns `ROWID_OBJECT`, `DELETED_*`, `UPDATED_BY`, `CREATOR`, `CREATE_DATE` everywhere. These are
  expected, because the MDM fills them.

## 6. IDQ engine semantics the mappings depend on

A re-implementation that misses these gives different results:

- **Router**: a row goes to every matching group (section 2). The default group gets only rows that match no group.
  The address default groups are never reached, because the score is always `'40'` or `'100'`.
- **Static lookup cache**: a lookup on a table that the same mapping writes reads it **as it was before the run**.
  The validation mappings rely on this. Rows inserted into `*_INACTIVE_STS` in a run do not affect routing in that
  run.
- **Aggregator without aggregate functions** returns the **last** row of each group in arrival order. Arrival order
  comes from the upstream Sorter, and **IDQ sorts NULL high**. This decides which version of a TRS party, plan or
  authorised-representative row wins.
- **Variable ports are evaluated before output ports.** In `m_Tgt_C_S_TRS_Pty_Nm`, the "carry forward the previous
  start date" logic (`IIF(v_DUP_RANK = 1, PERIOD_START_DATE, v_LAST_STRT_DATE)`) is a no-op. `v_LAST_STRT_DATE` is
  already overwritten with the current row's date when the output is computed, so the output is always the current
  row's `CREATE_DT`.
- **Empty string is not NULL in IDQ.** That is why every blank test is written as `LENGTH(RTRIM(x)) = 0 OR
  ISNULL(x)`. In Oracle both collapse to `RTRIM(x) IS NULL`.
- **`NULL <> 'D'` is not true.** An FSS client with a NULL capture action or NULL inactive flag is **never
  reactivated** (`m_Tgt_C_S_FSS_Pty_Validation`).
- **Mailability scores are compared as strings** (`MailabilityScore <= '3'`). That works for the single-digit
  scores the validator returns, but it is fragile.
- **Truncate target table** runs before the mapping writes, and it is not undone if the mapping fails. A failed run
  leaves the `C_S_*` table empty.
- **`$sys.MappingRunStartTime` is constant for the whole run.** All exception rows of a run share one `RUN_DATE`
  (see 12.1).

## 7. How the workflows hang together

- **The `*_Pty_Validation` mapping runs first and gates everything.** It maintains
  `STG_<SRC>_PTY_INACTIVE_STS` (status `H` history / `D` deactivated / `P` pending, from the `C_B_PTY_XREF` hub
  state) and the `*_INACTIVE_LOG` table. Every later mapping of the workflow drops parties that have a status row.
- **Reactivation in ECI** deletes the status row and then re-feeds the latest history rows of the family address
  and phone (and, if 1.2 were fixed, the Medicaid record) into the `STG_ECI_D_*` delta tables. Their next load is
  then sent to the MDM with hub state 1.
- **TRS has no validation mapping.** `m_Tgt_C_S_TRS_Pty_OnGoing` builds `STG_TRS_VALID_MEMBERS`, and
  `m_Tgt_C_S_TRS_Pty_Deactivation_1` deletes from it and logs to `STG_TRS_DEACTIVED_MEMBERS`. Every other TRS
  mapping joins to `STG_TRS_VALID_MEMBERS`.
- **TRS addresses are validated once per unique address.** `m_Tgt_C_S_TRS_Addr_1` validates the distinct addresses
  of the extract (about a tenth of the rows) into `STG_TRS_D_UNQ_ADDR`. `m_Tgt_C_S_TRS_Addr_2` joins the results
  back to the individuals. This is the only two-step mapping pair, and the cheapest place to save validator
  licence volume.
- **`m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing` appends** to `C_S_TRS_PTY_MNG_ATTR` after
  `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` truncates and loads it. Running them in the wrong order loses the switches.
- **Every `C_S_*` target is truncated and fully reloaded each run**, except `C_S_TRS_PTY_MNG_ATTR` for the auth-rep
  mapping above. The `STG_*_PTY_INACTIVE_*`, `STG_TRS_VALID_MEMBERS` and `STG_ECI_D_*` reactivation targets are
  appended to, not truncated.
- **CRE is one mapping.** `m_Tgt_C_S_CRE_CARE_Clients` loads all five `C_S_CRE_*` targets and `CRE_SRC_MRG` in one
  pass. There is no validation mapping and no inactive-status table. Instead it reads the CARE case maintenance of the
  day (`STG_CRE_D_CARE_CASE_MAINT`): deleted cases (`CASEDEL`) and the source of a case move (`CASEMOV`) are re-sent
  from the snapshot (`STG_CRE_SN_CARE_CLIENTS`) as end-dated records, the move target is re-sent too, and moves MDM
  has not merged yet go to `CRE_SRC_MRG` for MDM to merge.
- **Every workflow ends with a command task** that touches `<workflow>.ind` on the DIS host, an indicator file for
  whatever runs next.
- FSS and WIC use a **constant address type `'002'`** (physical mail), so their address score depends only on the
  mailability score and the match code. ECI and TRS look the type up, and an untranslatable type scores `'40'`.

## 8. The MDM timeline: mostly hard-coded, sometimes real

The `VERSION_SEQ`, `PERIOD_REFERENCE_TIME` and `TIMELINE_ACTION` logic belongs to an MDM timeline that is stale in
this estate. The Java port and the IDMC specs leave it out. The Oracle procedures port it, marked
`/* TIMELINE */`. Most of it does nothing:

- **Hard-coded `VERSION_SEQ = 1`** in almost every mapping. The rank or MD5 version comparison is commented out in
  IDQ, so the filters that keep version 1 (`fltr_Dups`, `fltr_Rank`) pass every row.
- **It is real in four places:** the three below and `m_Tgt_C_S_CRE_CARE_Clients`. There `VERSION_SEQ_NUM` is a
  running number per CARE id after a sort on `REC_TYPE` descending, and `VERSION_SEQ_NUM = 1` keeps one row per CARE
  id (a delta row beats a deleted, moved-away or move-target row). Deleted and moved-away rows are end-dated:
  `PERIOD_END_DATE = CARE_LASTUP_DT`, start one day earlier, `TIMELINE_ACTION = 2`, last update one hour before the
  run (the role keeps the run time). The Java port keeps the de-duplication and the period dates, not the version or
  timeline columns.
  - `m_Tgt_C_S_TRS_Addr_2`: a running `VERSION_SEQ` per role-address key, and `SRC_ROWID = key|VERSION_SEQ`.
  - The TRS phone and e-mail consolidation mapplets: `VERSION_SEQ` = number of distinct versions of the key.
  - `mplt_Pty_Rle_Rel_Timeline_Validation` (TRS member-to-member and member-to-PCP): this one **changes the row
    set**.
    - Every end-dated relationship is written twice: a closed version, plus an open copy with the end date removed.
    - The end date is corrected for daylight-saving changes (`mplt_DST_Correction`, `REF_DYLGHT_SVNGS_TM`).
    - Versions are re-ranked, `TIMELINE_ACTION = 2` for end-dated rows, and `HUB_STATE_IND = 1` on the current open
      row.

Removing the timeline is not entirely free: for the TRS relationships it changes the number of rows in
`C_S_TRS_PTY_RLE_REL` and `C_S_TRS_PTY_RLE_REL_PROV`.

## 9. Mapplet and rule quirks

From [000_mapplets.md](mappings/000_mapplets.md):

- **Name standardization**: in the "keep" branch of trailing-number removal, the middle-name expression returns the
  **last** name.
- **E-mail**: the local-part rule compares the address with the literal `'Invalid'`, so it never fires except for
  that word. All real checks are on the domain.
- **Phone**: `Missing_AreaCode` (area code `000`) exists only for ECI. Seven-digit numbers get `000` prefixed first.
- **Suffix**: `rule_Suffix_Std` looks the suffix up in `V_LOOKUP_CODE_VALUE` **without** a code-type filter, so any
  code type with a matching source value translates it.
- **Fifty years**: an end date more than fifty years ahead becomes NULL (open-ended).
- **TTF uses `CopyOf_mplt_Name_Standardization_Indv_Member`**, which is identical to the shared mapplet apart from
  its name. It can be replaced by the shared one.
- **Port precision cuts values** (the engine truncates a string to the precision of the port it enters; to confirm on
  IDQ with test values, the Snowflake port assumes it):
  - `mplt_Gender_Validation` reads the gender through `v_Gender_First_Digit` (string(1)): only the first character
    counts, so `'MALE'` maps to `'1'` and `'Unknown'` passes as `U`.
  - `rule_Phone_Std` checks and returns the phone through a string(10) port: a longer number is cut to ten digits
    before the length test, so an 11- or 12-digit number can pass and be stored cut. The TRS work phone is fed as
    `number extension`; the cleaning removes the space and the cut drops the extension, which is probably why that
    concatenation works at all.
  - `rule_MEDICAID_ID_Std` / `rule_Member_Id_Std` hold the cleaned id in a string(10) port.
- **SSN rule**: the error message strips `-`, space **and `X` / `x`** (`REPLACESTR(0, In_SSN, '-', ' ', 'X', '')`,
  case-insensitive), and compares the area as text (`> '899'`).
- **In the TRS alternate-id mapplet** the Medicaid and member ids are normalized from the *source* values; the rules
  only decide the exception code. TRS feeds the member id as the Medicaid id, so every 10-character member id also
  raises `Invalid_Medicaid_Id` for its `002` row.

## 10. Copy-paste traces between sources

WIC and FSS were cloned from ECI, and some ECI-only logic came along:

- `DQM_ADDRESS.PTY_SRC_KEY` in the **FSS and WIC** address mappings tests `SOURCE_TABLE = 'ECI_FAMILY'` to add the
  family `F` suffix. That value never occurs outside ECI.
- The WIC e-mail key uses the address as read, but ECI trims it. The same e-mail can produce two keys depending on
  the source.
- The WIC birth weight is `BIRTH_WT_OZ * 28.35`. The pound term is commented out (a deliberate 3/14/2025 change,
  not a bug).
- The TTF `C_B_PTY_XREF` lookup needs `TRIM(ROWID_SYSTEM) = 'TTF'`, because the MDM column is blank-padded. Any new
  lookup on `ROWID_SYSTEM` needs the same trim.
- TTF gender codes are `33 -> F`, `34 -> M`, otherwise `U`. Ethnicity is derived as `'55'` when
  `RACEETHNICITYID = '55'`, and race is validated from the same column.

## 11. Data model and environment

- `docs/*_EXPORT_OCT_16.sql` start with `DROP TABLE` statements. **Never run them** against a shared schema.
- `EXC_STG_BAD_REC_MEMB` is **unique** on (`SRC_SYS`, `SRC_SYS_ID_1..3`, `EXCEPTION_TYPE`, `EXCEPTION_CODE`,
  `RUN_DATE`).
- Tables named `*BAK*` or with a date stamp are backups. They are not part of the model.
- `STG_REF_PHN_AREA_CD_TEST` looks like a leftover test copy of `REF_PHN_AREA_CD`.
- CRE reads and writes objects that are not in the schema exports: `STG_CRE_SN_CARE_CLIENTS` (the client snapshot),
  `C_B_PTY_HMRG` (MDM merge history) and `CRE_SRC_MRG` (IDQ connection `SRCMRG`), plus `C_B_PTY_XREF.ORIG_ROWID_OBJECT`.
  `db/missing-objects.sql` creates them for mock runs; a `C_B_PTY_XREF` created by an earlier bootstrap lacks
  `ORIG_ROWID_OBJECT` and needs it added by a DBA.
- The CRE state lookup (`LKP_STATE_CODE`, "return last row") and alternate-id type lookup (`lkp_ALT_ID_MSTR_REF_CODE`)
  have **no code-type filter**, like `rule_Suffix_Std`: any code type with a matching source value translates.
- In IDQ, the phone rule's area-code lookup runs against Snowflake (`RDM.REF_PHN_AREA_CD`, filtered with
  `current_date()`). Everything else is Oracle.
- The race and ethnicity exception targets of `m_Tgt_C_S_TRS_Pty_OnGoing` are fed through **dynamic port groups**
  (`FieldMapPort`). Generic export parsers, including `ext-tools`, do not resolve those links. Check these targets by
  hand after any automated conversion.
- `idmc/` is 100% generated by `ext-tools/idmc_spec.py`. Change the generator, not the markdown.
- `ext-tools/README.md` and `idq-to-pc/wf_ECI_Stage_Load/README.md` name the output folder `idq-to-cdi`, but the
  folder in the repo is `idq-to-pc/`.

## 12. Risks when re-platforming

1. **Duplicate exception rows.** With one `RUN_DATE` per run and the unique key above, duplicate source keys can
   produce two equal exception rows. IDQ rejects just the duplicate and carries on, while a set-based
   `INSERT ... SELECT` fails as a whole. Use DML error logging (`LOG ERRORS`) or de-duplicate before inserting.
2. **Last-row semantics.** Any port of an aggregator without aggregate functions needs the exact upstream sort
   order, with NULL high, to pick the same row (section 6).
3. **Lookups on tables being written** must read a pre-run snapshot, as the IDQ static cache did.
4. **Configuration-driven exceptions** (section 3): compare `EXC_LOOKUP_CODE_VALUE` between environments before
   comparing outputs.
5. **Unfed columns** (section 5): a "fixed" port that suddenly fills `FLR_NUM` or `HUB_STATE_IND` changes what the
   MDM receives. Decide deliberately rather than by accident.
6. **Timeline removal** changes TRS relationship row counts (section 8).
7. **Unique keys that IDQ relies on.** Every `C_S_*` target is unique on (`PKEY_SRC_OBJECT`, `VERSION_SEQ`), and
   `STG_TRS_VALID_MEMBERS` (`PTY_PK`), `STG_TRS_DEACTIVED_MEMBERS` (`INDV_ID`), `STG_TRS_D_UNQ_ADDR` (`ADDR_ID`),
   `STG_ECI_D_MEDICAID` (`ID_MEDICAID`) have keys too. IDQ gets duplicates **rejected row by row** by Oracle and
   carries on, so the keys silently de-duplicate:
   - `VERSION_SEQ` is hard-coded to 1 almost everywhere, so a key that arrives twice in one run keeps only its first
     row. 1.7 ("no de-duplication") is therefore only half true: the filter does nothing, the unique index does it.
   - In `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`, when `LKP_ALT_ID_LBL` finds no type, the Medicaid and member rows of a person
     (same value) get the same key, and the second is rejected.
   - The ECI SSN exception row has `RUN_DATE` NULL (1.13), so its unique key repeats from run to run: an invalid SSN
     is logged **once, ever**; every later run's row is rejected.
   - An individual valid under two party keys (`INDV_ID|DC_INDV` and MCI `INDV_ID`) can be logged once in
     `STG_TRS_DEACTIVED_MEMBERS` (key `INDV_ID`).
   **Snowflake does not enforce unique keys** (except on hybrid tables). A Snowflake port must apply them itself,
   or it loads the duplicates IDQ never wrote; `idq-to-snowflake/` does (`uq_*` flags).
8. **Snowflake is not Oracle.** `''` is not NULL (as in IDQ), `'a' || NULL` is NULL (unlike IDQ and Oracle), `CHAR`
   columns are not compared blank-padded (so `ROWID_SYSTEM = 'ECI'` needs `TRIM`), and a value longer than a
   `VARCHAR(n)` column fails the whole statement instead of one row. The Oracle procedures cannot be translated
   word for word; see `idq-to-snowflake/README.md`.

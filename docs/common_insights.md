# Common insights: how the IDQ stage loads really behave

These are the surprises found while reading the five IDQ workflow exports (`docs/wf_*.xml`) line by line: once for
the Java port (`docs/mappings`), once for the IDMC specs (`idmc/`) and once for the Oracle procedures
(`idq-to-oracle/`). Each one is something a reader of the mapping names, descriptions or diagrams would probably get
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
- **It is real in three places:**
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

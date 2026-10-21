# idmc_spec.py: user guide

`idmc_spec.py` reads one IDQ workflow export (the `docs/wf_*.xml` files exported from the Developer tool) and
writes a build specification for **IDMC Cloud Data Integration (CDI)** and **Cloud Data Quality (CDQ)**: the
taskflow, mapping tasks, mappings, mapplets, CDQ assets and a parameter file. Developers use the spec to build the
assets in IDMC; the script does not create anything in IDMC itself.

It is a single file with no dependencies beyond the Python standard library.

## Requirements

* Python 3.9 or later (tested with 3.13).
* An IDQ workflow export in IMX format (the file starts with `<imx:IMX ...>` and contains a `workflow:Workflow`).
  Export the workflow **with dependencies** so its mappings, mapplets and rules are inside the file.

## Running it

From the repository root:

```sh
python -I ext-tools/idmc_spec.py <workflow.xml> <output-folder>
```

| Argument | Meaning |
|---|---|
| `<workflow.xml>` | The IDQ workflow export, for example `docs/wf_ECI_Stage_Load.xml`. |
| `<output-folder>` | Where the spec is written. Created if missing; existing files with the same names are overwritten. |

`-I` runs Python in isolated mode (ignores `PYTHON*` environment variables and the current directory), which is the
convention for the scripts in this repository.

The script prints one line when it finishes:

```
9 mappings, 16 mapplets -> idmc/wf_ECI_Stage_Load
```

### Examples

One workflow:

```sh
python -I ext-tools/idmc_spec.py docs/wf_ECI_Stage_Load.xml idmc/wf_ECI_Stage_Load
```

All five workflows (Git Bash):

```sh
for f in docs/wf_*.xml; do
  python -I ext-tools/idmc_spec.py "$f" "idmc/$(basename "$f" .xml)"
done
```

All five workflows (PowerShell):

```powershell
Get-ChildItem docs\wf_*.xml | ForEach-Object {
  python -I ext-tools\idmc_spec.py $_.FullName "idmc\$($_.BaseName)"
}
```

Expected counts for the current exports:

| Workflow | Mappings | Mapplets / rules |
|---|---|---|
| `wf_ECI_Stage_Load` | 9 | 16 |
| `wf_FSS_Stage_Load` | 6 | 16 |
| `wf_TRS_Stage_Load_1_Ongoing` | 14 | 22 (plus 2 retired timeline mapplets) |
| `wf_TTF_Stage_Load` | 4 | 10 |
| `wf_WIC_Stage_Load` | 5 | 14 |

The output is deterministic: running the script twice on the same export produces identical files, so the
output folder can be committed and diffs show real changes only.

## What it writes

```
<output-folder>/
  README.md              start here: asset inventory, connections, build order, translation rules, open items
  taskflow.md            the taskflow that replaces the IDQ workflow, mapping-task settings, command task
  tf_<name>.param        CDI parameter file (IDQ parameter defaults, one section per mapping task)
  cdq.md                 CDQ assets (Dictionary, Cleanse, Labeler, Verifier) with their exact settings
  mappings/<name>.md     one build spec per mapping
  mapplets/<name>.md     one build spec per mapplet and rule (mplt_*, rule_*)
```

### README.md

The entry point. It lists the IDMC assets to create and their names, maps each IDQ connection to an IDMC connector,
gives the build order (connections, CDQ assets, mapplets innermost first, mappings, mapping tasks, taskflow),
counts every transformation type, summarizes the filtered data (per mapping and `C_S_*` table: the steps that can
keep a row out and where the failed rows go), lists the translation rules applied, and ends with the items to
confirm in the target org.

### taskflow.md

* A diagram of the IDQ workflow as exported, and a diagram of the CDI taskflow.
* **Steps**: inclusive gateway pairs (split + join) become one **Parallel Paths** step. A path may hold several
  Data Tasks that run in sequence (TRS has paths of up to five mappings).
* **Mapping tasks**: one per mapping, named `mct_<mapping name without m_>`, with the IDQ mapping-task settings
  (date format, high precision, tracing, sort order).
* **Command task**: the IDQ command task becomes a taskflow Command Task on the Secure Agent. The indicator file
  keeps the IDQ workflow name (`wf_<name>.ind`) so its consumers are unaffected.

### tf_<name>.param

A CDI parameter file with `#USE_SECTIONS`, one section `[project].[folder].[mapping task]` per mapping task, holding
`$$MappingName` and each IDQ user parameter with its IDQ default value. Point every mapping task at this file.

### cdq.md

* **Dictionaries**: one per IDQ reference table, with the IDQ connection, the physical table holding the rows and a
  `SELECT` to extract them (reference table rows are not in the export). Dictionaries that are referenced but
  defined in another Model Repository project are listed separately.
* **Assets by IDQ transformation**: one CDQ asset per Token Standardizer / Case Converter (Cleanse), Labeler
  (Labeler) and Address Validator (Verifier), with every strategy, input and output field, search string, character
  set, token-set regular expression and option.

### mappings/ and mapplets/

Each file has:

1. **Summary**: transformation counts (IDQ type and its CDI equivalent), sources and targets with connections.
2. **Parameters**: name, type, default, and whether the mapping actually uses it (`no (declared only)` otherwise).
3. **Target load order**, when the IDQ mapping sets one.
4. **Flow**: a Mermaid diagram of the transformations in data-flow order.
5. **Filtered data** (see below).
6. **Transformations**, in data-flow order, each with its CDI equivalent and:
   * Source / Lookup / Target: connection, object, SQL override, filter, lookup condition, multiple-match policy,
     cache, target operation, truncate option.
   * Expression: every field with its kind (in, out, in/out, variable), type and expression already translated
     to CDI syntax.
   * Filter condition, router groups with conditions, union input groups, update-strategy expression.
   * Mapplet call with a link to the mapplet spec; DQ transformation settings; Verifier fields with the ones that
     are actually linked.
   * **Links**: every input field and the upstream `transformation.field` it comes from. Router and mapplet fields
     are shown as `transformation.group.field`.

#### Filtered data

Where rows leave the flow, worked out from the links (not hand-written), in three parts:

* **Steps that filter rows**: every step that can stop, divert or collapse rows, with its rule, the targets the
  passing rows can reach and what happens to the others.
  * Source: custom SQL query, source filter, select distinct, or a view (its logic is outside the export). A
    filter stored next to a custom query, or SQL text stored on a read that is not in custom-query mode, is
    flagged; hard-coded key lists, `rownum` caps and `ORA_HASH` sampling are flagged as likely test filters.
  * Filter: the condition with comments (`--`, `//`) removed. FALSE **or NULL** drops the row silently.
  * Router: one line per group. A row goes to every group whose condition is TRUE; a row matching no group goes
    to the default group, and is discarded when that group is not linked. A default group that no row can reach
    (two groups test `ISNULL(F)` / `NOT ISNULL(F)`) is said so.
  * Sorter with *distinct*, Aggregator (one row per group-by key), Update Strategy (rows delete/update instead of
    insert), mapplets that drop rows inside (their filters are listed), and timeline steps that are not ported.
* **Where the condition fields come from**: each field a Filter or Router tests is traced back through
  pass-through ports to a source column, a lookup return (table and condition; NULL when no row matches), an
  expression, or a mapplet output. When the lookup table is loaded by another mapping of the same workflow (for
  example `STG_ECI_PTY_INACTIVE_STS`, loaded by `m_Tgt_C_S_ECI_Pty_Validation`), that mapping is named. A null
  check on a lookup return also gets a plain reading, such as `IsNull(DEACTIVATION_STS)` = *no matching row in
  `STG_ECI_PTY_INACTIVE_STS`*.
* **Rows that do not reach `C_S_*` tables** (mappings only): for each `C_S_*` target, every path from the source
  with the steps a row must pass, and for each step what happens to a row that fails it: never read, discarded,
  sent to another router group (and the table it lands in, usually `EXC_STG_BAD_REC_MEMB`), collapsed into another
  row, or dropped inside a mapplet.

## Translation rules

| IDQ | CDI |
|---|---|
| `$<Param>` | `$$<Param>` (input parameter) |
| `$sys.MappingName` | `$$MappingName`, set per mapping task in the parameter file |
| `$sys.MappingRunStartTime` | `SESSSTARTTIME` |
| Update Strategy | target operation *Data Driven* (CDI has no Update Strategy transformation) |
| Inclusive gateways | *Parallel Paths* |
| Command task | taskflow *Command Task* |
| Token Standardizer, Case Converter | CDQ Cleanse asset |
| Labeler | CDQ Labeler asset |
| Address Validator | CDQ Verifier asset |
| Reference table | CDQ Dictionary |
| Aggregator, Sorter, Normalizer | same-named CDI transformations (group-by, sort keys and occurrences listed) |
| MDM timeline fields (`VERSION_SEQ*`, version / duplicate ranks, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION`) | flagged *omit* / *do not map* |
| MDM timeline steps and mapplets (version-rank filters, `mplt_Pty_Rle_Rel_Timeline_Validation`, `mplt_DST_Correction`) | marked **not ported**, with how to link around them; listed in the README *Not ported* section |

All other expression functions used in these workflows (`IIF`, `DECODE`, `REG_MATCH`, `REPLACESTR`, `LPAD`,
`MD5`, ...) exist in CDI unchanged.

## Customizing

All settings are constants near the top of the script or in `main()`:

| What | Where | Default |
|---|---|---|
| IDMC project and folder names (parameter file headers, README) | `main()`: `project, folder = ...` | `HHS_MDM_Stage` / source system (`ECI`, `FSS`, ...) |
| Taskflow name | `main()`: `tf = ...` | `wf_X` &rarr; `tf_X` |
| Mapping task names | `mct()` | `m_X` &rarr; `mct_X` |
| Fields flagged as not to be mapped | `STALE_COLUMNS` | MDM timeline fields and ranks |
| Source filters flagged as test filters | `TEST_FILTER` | key lists, long numeric ids, `rownum`, `ORA_HASH` |
| Whole steps not ported | `RETIRED_STEPS` (keyed by mapping and step name) | the timeline steps the Java port retired |
| Mapplets not ported (callers are marked too) | `RETIRED_MAPPLETS` | the two timeline mapplets |
| Live fields with timeline logic to replace | `FIELD_NOTES` | `SRC_ROWID`, `PERIOD_START_DATE_OUT`, `out_Period_End_Date` |
| IDQ &rarr; CDI transformation names and notes | `CDI_TX` | |
| Data type names | `DATA_TYPES` | |
| Expression translation | `to_cdi()` | rules above |
| CDQ guidance text per DQ transformation | `DQ_HELP` | |

After changing the script, regenerate the output folders; do not hand-edit the generated files.

## Limitations

* The script writes a **specification**, not an importable IICS package; the assets are built in the IDMC
  designers from the spec.
* Reference table and dictionary rows are not in the IDQ export; `cdq.md` gives the SQL to extract them.
* Objects that the workflow references from other Model Repository projects (for example `ref_special_char_list`
  in `HHSC_SHARED`) are listed but not described; export them separately.
* Only the transformation types present in the five exports are described in detail. Any other type appears with
  CDI **(manual)** and its links, and must be designed by hand.
* Expressions are translated textually; review any expression that uses IDQ system parameters other than the two
  listed above.
* *Filtered data* reads the conditions as written; it does not evaluate them. Conditions on expressions (for
  example a score computed by `DECODE`) are shown with the expression, so whether a router's default group is ever
  reached can still need judgement. The logic of source views and custom SQL queries is not analyzed.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `TypeError: 'NoneType' object is not subscriptable` in `main` | The file is a mapping or mapplet export, not a workflow export. Export the workflow. |
| A mapping task is missing from `taskflow.md` | The workflow uses a gateway pattern other than split/join pairs (for example conditional flows). Check the *IDQ workflow* diagram at the top of `taskflow.md` and add the step by hand. |
| A mapping spec says *(manual)* | A transformation type the script does not know; see Limitations. |
| `ParseError` | The export is truncated or not UTF-8. Re-export from the Developer tool. |

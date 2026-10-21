# Python usage guide

How to run the lookup documentation scripts in this folder.

## Requirements

* Python 3.8 or later (tested with 3.13). Only the standard library is used (`json`, `xml.etree`, `urllib`, `re`,
  `glob`), so there is nothing to `pip install` and no virtual environment is needed.
* The IDQ workflow exports in `docs/`: `wf_TRS_Stage_Load_1_Ongoing.xml`, `wf_ECI_Stage_Load.xml`,
  `wf_FSS_Stage_Load.xml`, `wf_TTF_Stage_Load.xml`, `wf_WIC_Stage_Load.xml`.
* The mapping documents in `docs/mappings/`, named `NNN_<mapping name>.md`, plus `000_mapplets.md`.

Check the interpreter:

```sh
python --version
```

On Windows, if `python` opens the Microsoft Store, use `py` instead (`py -I ext-tools/lookups.py ...`).

## Quick start

Run from the repository root (Git Bash, PowerShell or any shell):

```sh
python -I ext-tools/lookups.py lookups.json docs/wf_*.xml
python -I ext-tools/render_lookups.py lookups.json docs/mappings
```

Then review with `git diff docs/mappings` and delete `lookups.json`.

In PowerShell the wildcard is not expanded for native programs, so list the files explicitly:

```powershell
python -I ext-tools/lookups.py lookups.json (Get-ChildItem docs/wf_*.xml).FullName
python -I ext-tools/render_lookups.py lookups.json docs/mappings
```

`-I` (isolated mode) keeps Python from picking up modules from the current directory or `PYTHON*` environment
variables. It is recommended but not required.

## Step 1: `lookups.py`

```
python -I ext-tools/lookups.py <out.json> <wf1.xml> [<wf2.xml> ...]
```

| Argument | Meaning |
|---|---|
| `out.json` | File to write; overwritten if it exists. |
| `wf*.xml` | One or more IDQ workflow exports. Pass all five so that shared mapplets list every workflow. |

It prints the number of lookups found (158 for the current exports) and writes:

```json
{
  "lookups": [
    {
      "file": "wf_ECI_Stage_Load.xml",
      "container": "m_Tgt_C_S_ECI_Pty_Rle_Rel",
      "name": "Lkp_Rel_Tp_Code_Value",
      "condition": "SRC_SYS = Source_System AND SRC_CODE_VALUE = FAMILY_CD",
      "multipleMatch": "returnAny",
      "table": "LOOKUP_CODE_VALUE",
      "connection": "STAGING",
      "filter": "\"LOOKUP_CODE_VALUE\".\"CODE_TYPE\" IN ('REL_TP','INVERSE_REL')",
      "sqlQuery": null,
      "inputs":  [{"port": "FAMILY_CD", "from": {"instance": "Exp_Prep_Family_cd", "type": "ExpressionTx", "port": "out_FAMILY_CD"}}],
      "outputs": [{"port": "MSTR_REF_CODE", "to": {"instance": "Route_Good_vs_Exceptions", "type": "RouterTx", "port": "MSTR_REF_CODE"}}]
    }
  ],
  "mapplets": {"m_Tgt_C_S_ECI_Pty": ["mplt_BirthDate_Validation", "..."]}
}
```

* `container` is the mapping, mapplet or rule that holds the lookup.
* `inputs[].from` is the upstream port feeding each lookup input port; `outputs[].to` is the downstream port fed by
  each returned column. An output with `"passthrough": true` is an input port passed straight through.
* `mapplets` lists the mapplets and rules each mapping (or mapplet) calls directly.

The JSON is also handy for ad hoc questions, for example every lookup against `EXC_LOOKUP_CODE_VALUE`:

```sh
python -I -c "import json; [print(l['container'], l['name']) for l in json.load(open('lookups.json'))['lookups'] if l['table'] == 'EXC_LOOKUP_CODE_VALUE']"
```

## Step 2: `render_lookups.py`

```
python -I ext-tools/render_lookups.py <lookups.json> <docs/mappings dir>
```

For each `NNN_m_*.md` it finds the mapping name from the file name and writes a `## Lookups` section:

* grouped by the transformation feeding the lookup's input ports (`### Fed by Exp_X (Expression)`);
* one table row per lookup: table and connection, filter, multiple-match handling, condition, input ports, output
  ports;
* SQL overrides and multi-line filters as SQL blocks below the table;
* a closing link to the mapplets / rules the mapping calls (directly or nested) that contain lookups.

In `000_mapplets.md` it writes `## Lookups inside mapplets and rules`, one subsection per mapplet. Copies that are
identical across workflows are merged and the workflows are named in the heading.

The section is placed between `<!-- lookups:begin -->` and `<!-- lookups:end -->`:

* first run: inserted before `## Business rules` (mapping docs) or `## Retired: MDM timeline` (000), or appended
  at the end when that heading is missing;
* later runs: only the marked block is replaced. Edits outside the markers are kept; edits inside are overwritten.

Running it twice in a row produces no further changes.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `FileNotFoundError` on the JSON | Run from the repository root, or pass absolute paths. In Git Bash use `C:/...` paths rather than `/c/...` when handing them to Python. |
| `0 lookups` | The wildcard was not expanded (PowerShell) - list the XML files explicitly. |
| A mapping doc says "no lookup transformations" unexpectedly | The file name must be `NNN_<exact mapping name>.md`; the mapping name is matched against the XML. |
| Whole files show as changed in `git diff` | Line endings were rewritten. The scripts read and write with `newline=''` to keep the existing CR/LF bytes; do not change that. |
| A mapping without a doc (for example `m_Tgt_Stg_ECI_Pty_Reactivation_*`) is missing | Expected: only mappings with a document in `docs/mappings` are rendered. Its lookups are still in the JSON. |

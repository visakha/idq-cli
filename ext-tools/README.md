# ext-tools

Helper scripts that are not part of the Java build.

## Lookup documentation

Regenerates the `## Lookups` sections in `docs/mappings/*.md` (between the `<!-- lookups:begin -->` /
`<!-- lookups:end -->` markers) from the IDQ workflow exports. Run from the repository root:

```sh
python -I ext-tools/lookups.py lookups.json docs/wf_*.xml
python -I ext-tools/render_lookups.py lookups.json docs/mappings
```

* `lookups.py` parses every Lookup transformation (table, connection, filter, SQL override, condition, input ports
  and their feeding transformation, output ports and their downstream port) into a JSON file.
* `render_lookups.py` writes one section per mapping document and the mapplet section of `000_mapplets.md`. Only the
  marked block is replaced, so it is safe to re-run.

`lookups.json` is an intermediate file; delete it afterwards.

## IDMC CDI build specification

Converts one IDQ workflow export into a build specification for IDMC Cloud Data Integration (taskflow, mapping
tasks, mappings, mapplets) and Cloud Data Quality (Cleanse / Labeler / Verifier / Dictionary assets). Run from the
repository root:

```sh
python -I ext-tools/idmc_spec.py docs/wf_ECI_Stage_Load.xml idmc/wf_ECI_Stage_Load
```

* `README.md`: asset inventory, connections, build order, translation rules and open items.
* `taskflow.md`: the taskflow (IDQ gateways become Parallel Paths), mapping-task settings and the command task.
* `<taskflow>.param`: CDI parameter file with the IDQ parameter defaults, one section per mapping task.
* `cdq.md`: the CDQ assets for the IDQ data quality transformations, with their exact settings.
* `mappings/`, `mapplets/`: one spec per object with sources, SQL overrides, every transformation (expressions
  translated to CDI syntax), lookups, router groups, targets and field-level links.

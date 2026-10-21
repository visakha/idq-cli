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

# idq-cli: rules for Claude

Read first: README.md, user-guide-cli.md, the newest gathered-kb-todos-and-improvements-NNN.md, docs/common_insights.md.
Working from another machine (Azure VM, GitHub `@claude`): see getting-started-zero-to-hearo-azure-foundry.md.

## Hard rules
- INSERT-ONLY. Never add DELETE, TRUNCATE or DROP to Java code, tests, mock fills or any SQL the code runs
  (incl. idq-to-oracle procedures). LoadMode.Append only; mock fills use MockTables.skipIfPresent/skipIfMarked/skipIf.
  IDQ truncate/DD_DELETE steps are left out and marked `-- Not performed: ...`. Only CREATE TABLE for missing objects.
  The CLI may run against production.
- Ignore tables with BAK/BKP/BACKUP or a date stamp in the name (e.g. *_20231001, *_OCT16): no entities, mocks,
  tests or report sections. Beware false positives like REF_JUNK_NAME_LIST.
- C_S_* legacy MDM timeline is stale: ignore VERSION_SEQ, version-rank loops, version = 1 filters,
  PERIOD_REFERENCE_TIME, TIMELINE_ACTION. Do not port or write them; document the omission in each mapping doc.
- Never put credentials in the repo, issues, PRs or prompts. DB: IDQ_DB_USER / IDQ_DB_PASSWORD / IDQ_WALLET_DIR env vars.

## Conventions
- STG _D_ / _H_ tables map to `<Name>Delta` / `<Name>Hist` records.
- 5 sources (TRS, ECI, FSS, TTF, WIC), 33 in-scope mappings. WIC is the 5th.
- New non-obvious IDQ behaviour (quirks/defects) goes into docs/common_insights.md and is called out in the reply.
- Mapping docs (docs/mappings/*.md) were generated; edit them directly now and keep SQL in sync with *Queries classes.
  "## Lookups" blocks between <!-- lookups:begin/end --> markers come from ext-tools/lookups.py + render_lookups.py.
  Files contain stray bare CRs: read/write with newline=''.
- One branch + PR per piece of work. Parking notes are numbered and incremental (next: 003).
- When a new rule is learnt, add it here in the same PR so every machine gets it.

## Build
- JDK 27 (Zulu). Windows home: C:\Users\vamsi\jdk\zulu27. Linux VM: $HOME/jdk/zulu27.
- `./mvnw test` (unit, no DB). `-Dtest=OracleWorkflowIT` / `SourceEntitiesIT` need OCI.

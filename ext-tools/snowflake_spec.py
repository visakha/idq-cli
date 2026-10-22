"""Generate docs-from-snowflake-db-scripts/: one page per Snowflake stored procedure of idq-to-snowflake/.

    python -I ext-tools/snowflake_spec.py

Reads only the SQL of idq-to-snowflake/ (procedure headers, signatures, INSERT targets, functions called, run
scripts) and the file names of docs-from-idq-exports/ and docs/mappings/ for the links. Writes:

    docs-from-snowflake-db-scripts/README.md                       overview, shared functions, every workflow
    docs-from-snowflake-db-scripts/<workflow>/README.md            the procedures in run order
    docs-from-snowflake-db-scripts/<workflow>/mappings/<m>.md      one page per mapping / procedure

Regenerate after changing a procedure header; do not edit the generated pages.
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)
SQL_DIR = os.path.join(ROOT, 'idq-to-snowflake')
OUT_DIR = os.path.join(ROOT, 'docs-from-snowflake-db-scripts')
IDMC_DIR = os.path.join(ROOT, 'docs-from-idq-exports')
DOCS_DIR = os.path.join(ROOT, 'docs', 'mappings')
WORKFLOWS = ['wf_ECI_Stage_Load', 'wf_FSS_Stage_Load', 'wf_TTF_Stage_Load', 'wf_WIC_Stage_Load',
             'wf_TRS_Stage_Load_1_Ongoing', 'wf_CRE_Stage_Load_Ongoing']
MARKERS = ('VALIDATION', 'BAD DATA', 'TIMELINE')


def read(path):
    with open(path, encoding='utf-8', newline='') as fh:
        return fh.read().replace('\r\n', '\n')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)


def code_only(text):
    """Comments removed and string literals emptied (literal-aware)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":
            j = i + 1
            while j < n and not (text[j] == "'" and (j + 1 >= n or text[j + 1] != "'")):
                j += 2 if text[j] == "'" else 1
            out.append("''")
            i = j + 1
        elif text.startswith('--', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif text.startswith('/*', i):
            j = text.find('*/', i)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def header(text):
    """The comment block between the first two dashed lines, without the '-- ' prefix."""
    lines, inside = [], False
    for line in text.split('\n'):
        if line.startswith('-----'):
            if inside:
                break
            inside = True
            continue
        if inside:
            lines.append(line[3:] if line.startswith('-- ') else line[2:])
    while lines and not lines[0].strip():
        lines.pop(0)
    return lines


def md(s):
    return s.replace('|', '\\|')


def registry():
    """Purpose of every shared function, from the tables in the common/ headers."""
    reg, last = {}, None
    for name in ('01_snow_common_functions.sql', '02_snow_common_lookups.sql'):
        for line in read(os.path.join(SQL_DIR, 'common', name)).split('\n'):
            cells = [c.strip() for c in line.lstrip('- ').strip().strip('|').split('|')]
            if cells and re.fullmatch(r'fn_snow_helper\d+_common', cells[0]):
                reg[cells[0]] = ' '.join(c for c in cells[1:] if c)
                last = cells[0]
            elif cells and not cells[0] and last and any(cells[1:]):
                reg[last] += ' ' + ' '.join(c for c in cells[1:] if c)
            else:
                last = None
    for wf in WORKFLOWS:
        folder = os.path.join(SQL_DIR, wf)
        for f in sorted(os.listdir(folder)):
            if f.startswith('fn_snow_helper'):
                lines = [ln for ln in header(read(os.path.join(folder, f)))[1:] if ln.strip()]
                reg[f[:-4]] = lines[0].strip() if lines else ''
    return reg


def run_order(wf):
    text = read(os.path.join(SQL_DIR, wf, f'run_{wf}.sql'))
    return re.findall(r'^CALL\s+(sp_snow_main_\w+)\s*\(\s*\)\s*;', text, re.M)


def doc_link(mapping):
    if not os.path.isdir(DOCS_DIR):
        return None
    for f in sorted(os.listdir(DOCS_DIR)):
        if re.fullmatch(r'\d{3}_' + re.escape(mapping) + r'\.md', f):
            return f
    return None


def parameters(text, proc):
    m = re.search(r'CREATE OR REPLACE PROCEDURE\s+' + proc + r'\s*\((.*?)\)\s*RETURNS', text, re.S)
    rows = []
    if m:
        for line in m.group(1).split('\n'):
            p = re.match(r"\s*(\w+)\s+(\w+)(?:\s+DEFAULT\s+('(?:[^']|'')*'|\S+?))?\s*,?\s*(?:--\s*(.*))?$", line)
            if p:
                rows.append((p.group(1), p.group(2), p.group(3) or '', p.group(4) or ''))
    return rows


def targets(code):
    seen = {}
    for t in re.findall(r'\bINTO\s+([A-Za-z_]\w*)\b', code, re.I):
        seen.setdefault(t.upper(), None)
    return list(seen)


def marker_paragraphs(lines):
    """Split the header into the free text and the VALIDATION / BAD DATA / TIMELINE paragraphs."""
    body, paras, current = [], {}, None
    for line in lines:
        m = re.match(r'(VALIDATION|BAD DATA|TIMELINE)\b', line)
        if m:
            current = m.group(1)
            paras.setdefault(current, []).append(line)
        elif current and (line.startswith(' ') or not line.strip()) and line.strip():
            paras[current].append(line)
        else:
            current = None
            body.append(line)
    return body, paras


def mapping_page(wf, proc, position, total, reg):
    mapping = proc[len('sp_snow_main_'):]
    path = os.path.join(SQL_DIR, wf, proc + '.sql')
    text = read(path)
    code = code_only(text)
    lines = header(text)
    if lines and lines[0].strip() == proc:
        lines = lines[1:]
    body, paras = marker_paragraphs(lines)
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    out = [f'# {mapping} &rarr; Snowflake `{proc}`', '']
    links = [f'procedure [`{proc}.sql`](../../../idq-to-snowflake/{wf}/{proc}.sql)']
    if os.path.exists(os.path.join(IDMC_DIR, wf, 'mappings', mapping + '.md')):
        links.append(f'IDQ / CDI spec [`docs-from-idq-exports/{wf}/mappings/{mapping}.md`](../../../docs-from-idq-exports/{wf}/mappings/{mapping}.md)')
    d = doc_link(mapping)
    if d:
        links.append(f'business description [`docs/mappings/{d}`](../../../docs/mappings/{d})')
    oracle = os.path.join(ROOT, 'idq-to-oracle', wf, f'sp_ors_main_{mapping}.sql')
    if os.path.exists(oracle):
        links.append(f'Oracle port [`sp_ors_main_{mapping}`](../../../idq-to-oracle/{wf}/sp_ors_main_{mapping}.sql)')
    out += [f'Workflow `{wf}`, step {position} of {total} in '
            f'[`run_{wf}.sql`](../../../idq-to-snowflake/{wf}/run_{wf}.sql). Links: ' + '; '.join(links) + '.', '']
    out += ['Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or '
            '`INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It '
            'returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of '
            '[idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.', '']
    out += ['## What it does', '', '```text', *[ln.rstrip() for ln in body], '```', '']
    for marker in MARKERS:
        if marker in paras:
            title = {'VALIDATION': 'Validations', 'BAD DATA': 'Bad data', 'TIMELINE': 'MDM timeline'}[marker]
            out += [f'## {title}', '', '```text', *[ln.rstrip() for ln in paras[marker]], '```', '']
    params = parameters(text, proc)
    out += ['## Parameters', '']
    if params:
        out += ['| Parameter | Type | Default | Replaces / meaning |', '|---|---|---|---|']
        out += [f'| `{n}` | {t} | `{md(dv)}` | {md(c)} |' if dv else f'| `{n}` | {t} | | {md(c)} |'
                for n, t, dv, c in params]
    else:
        out += ['None.']
    out += ['', '## Tables written (insert only)', '', '| Table |', '|---|']
    out += [f'| `{t}` |' for t in targets(code)]
    used = sorted(set(re.findall(r'\b(fn_snow_helper\d+_\w+|sp_snow_helper\d+_\w+)\b', code)))
    out += ['', '## Shared and helper functions called', '']
    if used:
        out += ['| Function | Does |', '|---|---|'] + [f'| `{u}` | {md(reg.get(u, ""))} |' for u in used]
    else:
        out += ['None.']
    out += ['', '## Run it', '', '```sql', f'CALL {proc}();', '```', '',
            'From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole '
            'workflow in this order.', '']
    return '\n'.join(out)


def workflow_readme(wf, procs):
    out = [f'# {wf} &rarr; Snowflake', '',
           f'The Snowflake stored procedures that replace the IDQ workflow `docs/{wf}.xml`, in the order of '
           f'[`run_{wf}.sql`](../../idq-to-snowflake/{wf}/run_{wf}.sql) (the taskflow order of '
           f'[`docs-from-idq-exports/{wf}/taskflow.md`](../../docs-from-idq-exports/{wf}/taskflow.md); parallel IDQ paths run one after another).', '',
           '| Step | Mapping | Procedure |', '|---|---|---|']
    for i, p in enumerate(procs, 1):
        m = p[len('sp_snow_main_'):]
        out.append(f'| {i} | [`{m}`](mappings/{m}.md) | [`{p}`](../../idq-to-snowflake/{wf}/{p}.sql) |')
    helpers = sorted(f[:-4] for f in os.listdir(os.path.join(SQL_DIR, wf)) if f.startswith('fn_snow_helper'))
    if helpers:
        out += ['', 'Mapping-specific helpers:', '']
        out += [f'- [`{h}`](../../idq-to-snowflake/{wf}/{h}.sql)' for h in helpers]
    out += ['', 'Conventions, install and the shared functions: '
            '[idq-to-snowflake/README.md](../../idq-to-snowflake/README.md).', '']
    return '\n'.join(out)


def top_readme(counts, reg):
    out = ['# IDQ &rarr; Snowflake: procedure documentation', '',
           'One page per Snowflake stored procedure of [`idq-to-snowflake/`](../idq-to-snowflake/README.md), generated '
           'by `ext-tools/snowflake_spec.py` from the procedure headers. Each page says what the procedure does, its '
           'validations, its bad-data handling and its MDM timeline logic (all in scope for this port), its '
           'parameters, the tables it writes and the shared functions it calls. The IDQ / CDI specification of the '
           'same mapping is in [`docs-from-idq-exports/`](../docs-from-idq-exports/).', '',
           '## How is this file generated?', 'see below',
           '### What it is: The docs: one Markdown page per procedure (what it does, validations, bad-data handling, '
           'timeline, the', '  tables it writes)',
           "### How it's made: Generated from the procedure headers in idq-to-snowflake/ by ext-tools/snowflake_spec.py;",
           '\tDo not edit these pages by hand', '', '',
           '| Workflow | Procedures |', '|---|---|']
    out += [f'| [`{wf}`]({wf}/README.md) | {n} |' for wf, n in counts]
    out += ['', '## Shared functions', '',
            'The IDQ mapplets and rules, written out as Snowflake SQL functions (nothing is assumed to exist).', '',
            '| Function | Does |', '|---|---|']
    out += [f'| `{k}` | {md(v)} |' for k, v in sorted(reg.items())
            if k.endswith('_common')]
    out += ['', 'Regenerate with `python -I ext-tools/snowflake_spec.py`; do not edit these pages by hand.', '']
    return '\n'.join(out)


def main():
    reg = registry()
    counts = []
    for wf in WORKFLOWS:
        procs = run_order(wf)
        counts.append((wf, len(procs)))
        write(os.path.join(OUT_DIR, wf, 'README.md'), workflow_readme(wf, procs))
        for i, p in enumerate(procs, 1):
            write(os.path.join(OUT_DIR, wf, 'mappings', p[len('sp_snow_main_'):] + '.md'),
                  mapping_page(wf, p, i, len(procs), reg))
    write(os.path.join(OUT_DIR, 'README.md'), top_readme(counts, reg))
    print(f'{sum(n for _, n in counts)} procedure pages written to {os.path.normpath(OUT_DIR)}')


if __name__ == '__main__':
    main()

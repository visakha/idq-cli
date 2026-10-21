"""Insert a '## Lookups' section into docs/mappings/*.md from lk.json.

Usage: python -I render_lookups.py <lk.json> <docs/mappings dir>
"""
import glob
import json
import os
import re
import sys

BEGIN = '<!-- lookups:begin -->'
END = '<!-- lookups:end -->'
TYPE = {'ExpressionTx': 'Expression', 'MappletInputTx': 'Mapplet input', 'SourceTx': 'Source',
        'FilterTx': 'Filter', 'AvTx': 'Address Validator', 'NormalizerTx': 'Normalizer', 'RouterTx': 'Router',
        'TargetTx': 'Target', 'MappletOutputTx': 'Mapplet output', 'MappletTx': 'Mapplet',
        'LookupTx': 'Lookup', 'UnionTx': 'Union', 'SorterTx': 'Sorter', 'AggregatorTx': 'Aggregator',
        'UpdateStrategyTx': 'Update Strategy', 'LabelerTx': 'Labeler', 'CaseConverterTx': 'Case Converter',
        'TokenStandardiserTx': 'Standardizer'}
MATCH = {'returnAny': 'any row', 'returnFirst': 'first row', 'returnLast': 'last row',
         'reportError': 'error', 'returnAll': 'all rows'}
WF = {'wf_TRS_Stage_Load_1_Ongoing.xml': 'TRS', 'wf_ECI_Stage_Load.xml': 'ECI', 'wf_FSS_Stage_Load.xml': 'FSS',
      'wf_TTF_Stage_Load.xml': 'TTF', 'wf_WIC_Stage_Load.xml': 'WIC'}


def code(s):
    return '`' + s.replace('|', '\\|') + '`'


def tname(t):
    return TYPE.get(t, t)


def ref(x):
    return code(x['instance'] + '.' + x['port']) if x else '(unlinked)'


def signature(lk):
    return json.dumps({k: lk[k] for k in ('name', 'condition', 'table', 'sqlQuery', 'filter', 'inputs', 'outputs',
                                          'multipleMatch')}, sort_keys=True)


def feeders(lk):
    seen = []
    for i in lk['inputs']:
        f = i['from']
        key = (f['instance'], f['type']) if f else ('(unlinked)', '?')
        if key not in seen:
            seen.append(key)
    return tuple(seen)


def multiline(s):
    return chr(10) in s.strip() or chr(13) in s.strip()


def table_cell(lk):
    parts = [code(lk['table'] or '?') + (' (' + lk['connection'] + ')' if lk['connection'] else '')]
    if lk['filter'] and multiline(lk['filter']):
        parts.append('filter (below)')
    elif lk['filter']:
        parts.append('filter: ' + code(lk['filter']))
    if lk['sqlQuery']:
        parts.append('SQL override (below)')
    parts.append('multiple match: ' + MATCH.get(lk['multipleMatch'], lk['multipleMatch'] or 'default'))
    return '<br>'.join(parts)


def section(lks, heading='## Lookups', level='###'):
    lines = [heading, '']
    if not lks:
        lines += ['This mapping has no lookup transformations of its own.', '']
        return lines
    lines += ['Connected lookups, grouped by the transformation that feeds their input ports. In a lookup condition the',
              'left side is the lookup table column and the right side is the lookup input port. Output ports are the',
              'returned table columns (or input ports passed through) and the downstream port each one feeds.', '']
    groups = {}
    for lk in lks:
        groups.setdefault(feeders(lk), []).append(lk)
    sqls = []
    for fs, members in groups.items():
        single = len(fs) == 1
        title = ', '.join(code(n) + ' (' + tname(t) + ')' for n, t in fs)
        lines += [level + ' Fed by ' + title, '',
                  '| Lookup | Table | Condition | Input ports | Output ports |', '|---|---|---|---|---|']
        for lk in members:
            ins = '<br>'.join(code(i['port']) + ' &larr; ' +
                              (code(i['from']['port']) if single and i['from'] else ref(i['from']))
                              for i in lk['inputs'])
            outs = '<br>'.join(code(o['port']) + (' (pass-through)' if o.get('passthrough') else '') +
                               ' &rarr; ' + ref(o['to']) + (' (' + tname(o['to']['type']) + ')' if o['to'] else '')
                               for o in lk['outputs'])
            lines.append('| ' + ' | '.join([code(lk['name']), table_cell(lk), code(lk['condition'] or ''),
                                            ins, outs]) + ' |')
            if lk['sqlQuery'] or (lk['filter'] and multiline(lk['filter'])):
                sqls.append(lk)
        lines.append('')
    for lk in sqls:
        if lk['filter'] and multiline(lk['filter']):
            lines += ['Filter of ' + code(lk['name']) + ':', '', '```sql', lk['filter'].strip(), '```', '']
        if lk['sqlQuery']:
            lines += ['SQL override of ' + code(lk['name']) + ':', '', '```sql', lk['sqlQuery'].strip(), '```', '']
    return lines


def splice(text, block, anchor_re):
    block = BEGIN + '\n' + '\n'.join(block).rstrip() + '\n\n' + END + '\n\n'
    if BEGIN in text:
        return re.sub(re.escape(BEGIN) + '.*?' + re.escape(END) + '\n\n', lambda m: block, text, flags=re.S)
    m = re.search(anchor_re, text, flags=re.M)
    if not m:
        return text.rstrip() + '\n\n' + block.rstrip() + '\n'
    return text[:m.start()] + block + text[m.start():]


def transitive(used, name, acc=None):
    acc = acc if acc is not None else []
    for m in used.get(name, []):
        if m not in acc:
            acc.append(m)
            transitive(used, m, acc)
    return acc


def main():
    data = json.load(open(sys.argv[1]))
    docs = sys.argv[2]
    lookups, used = data['lookups'], data['mapplets']
    by_container = {}
    for lk in lookups:
        by_container.setdefault(lk['container'], []).append(lk)

    for path in sorted(glob.glob(os.path.join(docs, '0[0-9][0-9]_m_*.md'))):
        mapping = re.match(r'\d{3}_(m_.*)\.md', os.path.basename(path)).group(1)
        lks = by_container.get(mapping, [])
        block = section(lks)
        mps = [m for m in transitive(used, mapping) if by_container.get(m)]
        if mps:
            block += ['Lookups inside the mapplets / rules this mapping calls are listed in',
                      '[000](000_mapplets.md#lookups-inside-mapplets-and-rules): ' +
                      ', '.join(code(m) for m in mps) + '.', '']
        text = open(path, encoding='utf-8', newline='').read()
        open(path, 'w', encoding='utf-8', newline='\n').write(splice(text, block, r'^## Business rules'))
        print(os.path.basename(path), len(lks), 'lookups', len(mps), 'mapplets')

    # Mapplets: one subsection per mapplet; identical copies across workflows collapse into one
    block = ['## Lookups inside mapplets and rules', '',
             'Lookup transformations inside the shared mapplets and rules, per mapplet. When the same mapplet is exported',
             'in several workflows with identical lookups it is listed once with every workflow named. In a lookup',
             'condition the left side is the lookup table column and the right side is the lookup input port.', '']
    names = sorted(n for n in by_container if n and not n.startswith('m_'))
    for name in names:
        variants = {}
        for lk in by_container[name]:
            variants.setdefault(WF.get(lk['file'], lk['file']), []).append(lk)
        merged = {}
        for wf, lks in variants.items():
            key = tuple(sorted(signature(l) for l in lks))
            merged.setdefault(key, ([], lks))[0].append(wf)
        for wfs, lks in merged.values():
            heading = '### ' + code(name) + ' (' + ', '.join(sorted(wfs)) + ')'
            sec = section(lks, heading=heading, level='####')
            block += [sec[0]] + [l for l in sec[2:] if not l.startswith(('Connected lookups', 'left side',
                                                                               'returned table'))]
    text = open(os.path.join(docs, '000_mapplets.md'), encoding='utf-8', newline='').read()
    open(os.path.join(docs, '000_mapplets.md'), 'w', encoding='utf-8', newline='\n').write(
        splice(text, block, r'^## Retired: MDM timeline'))


if __name__ == '__main__':
    main()

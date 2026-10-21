"""Generate an IDMC CDI / CDQ build specification from an IDQ workflow XML export.

Usage: python -I idmc_spec.py <wf.xml> <out_dir>

Writes, under <out_dir>:
  README.md                 conversion overview: asset inventory, connections, parameters, build order, open items
  taskflow.md               taskflow design that replaces the IDQ workflow
  <taskflow>.param          CDI parameter file (defaults taken from the IDQ parameters)
  cdq.md                    CDQ assets to create for the IDQ data quality transformations
  mappings/<name>.md        one build spec per mapping (sources, transformations, links, targets)
  mapplets/<name>.md        one build spec per mapplet / rule
"""
import os
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from collections import defaultdict

IMX = '{http://com.informatica.imx}'
XSI = '{http://www.w3.org/2001/XMLSchema-instance}'
NOT_SHOWN = {'imx:id', 'imx:idref', 'xsi:type', 'name', 'typeSystem', 'tableDefinitions', 'tableDefinition'}
# MDM timeline columns are stale in this estate and are not ported (see docs/mappings retired sections)
STALE_COLUMNS = re.compile(r'^(o_|out_|v_)?(LAST_|LST_|CUR_)?(VERSION_SEQ\w*|VER_SEQ\w*|PERIOD_REFERENCE_TIME|'
                           r'TIMELINE_ACTION|DUP_RANK|CUR_RANK|LST_RANK)$', re.I)
# Whole steps of the stale timeline, as retired by the Java port (docs/mappings "Retired / not ported" sections).
# Steps that also compute live fields are not listed: only their timeline fields are omitted (STALE_COLUMNS).
LINK_AROUND = 'Link the fields that feed it straight to the fields it fed.'
RETIRED_STEPS = {
    ('m_Tgt_C_S_TRS_Pty_OnGoing', 'fltr_Dups'):
        f'Filter `VERSION_SEQ_NUM = 1`; the version is hard-coded to 1, so it passes every row. {LINK_AROUND}',
    ('m_Tgt_C_S_TRS_Pty_Rle_Alt_Id', 'exp_Rank'):
        'Version rank for `fltr_Rank`. Replaced together with `fltr_Rank` (see there).',
    ('m_Tgt_C_S_TRS_Pty_Rle_Alt_Id', 'fltr_Rank'):
        'Keeps `VERSION_SEQ = 1`. Replace `exp_Rank` + `fltr_Rank` with an Aggregator grouped by `PKEY_SRC_OBJECT` '
        '(one row per key, as the Java port does); a CDI Aggregator without aggregate functions returns the last row '
        'of each group in the upstream `srtr_Pkey` order.',
    ('m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing', 'exp_Rank'):
        f'`VERSION_SEQ_NUM` rank, hard-coded to 1. {LINK_AROUND}',
    ('m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing', 'srtr_Rank'):
        f'Distinct re-sort around `exp_Rank`. {LINK_AROUND}',
}
RETIRED_MAPPLETS = {
    'mplt_Pty_Rle_Rel_Timeline_Validation': 'duplicates end-dated relationships into open and closed versions, '
                                            're-ranks `VERSION_SEQ`, sets `PERIOD_REFERENCE_TIME` / `TIMELINE_ACTION` '
                                            'and forces `HUB_STATE_IND` on open rows',
    'mplt_DST_Correction': 'shifts end dates by one hour around daylight-saving changes for the timeline',
}
# Live fields whose timeline-specific logic is dropped: (mapping, step, field) -> what to do instead
FIELD_NOTES = {
    ('m_Tgt_C_S_TRS_Addr_2', 'exp_Stage_Target_Party_Role_Addr_Attributes', 'SRC_ROWID'):
        'drop the `|version` suffix: `SUBSTR(PKEY_SRC_OBJECT_PTY_RL_OBJECT, 1, 30)`',
    ('m_Tgt_C_S_TRS_Pty_Nm', 'exp_Party_Consolidation', 'PERIOD_START_DATE_OUT'):
        'timeline carry-forward: pass `PERIOD_START_DATE` (the alias create date) instead',
    ('m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr', 'agg_Pty_Rle_Eaddr', 'out_Period_End_Date'):
        '`MAX` of always-empty end dates: leave the end date empty',
    ('m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr', 'agg_Pty_Rle_Phone', 'out_Period_End_Date'):
        '`MAX` of always-empty end dates: leave the end date empty',
}

CDI_TX = {
    'SourceTx': ('Source', 'Oracle connector source; carry the SQL override / filter below verbatim.'),
    'TargetTx': ('Target', 'Oracle connector target.'),
    'ExpressionTx': ('Expression', 'Same expression language; variable fields are supported.'),
    'FilterTx': ('Filter', 'Advanced filter condition.'),
    'RouterTx': ('Router', 'One output group per IDQ group; the default group is created automatically.'),
    'LookupTx': ('Lookup', 'Connected lookup unless a return port is set (then unconnected).'),
    'UnionTx': ('Union', 'One input group per IDQ group.'),
    'AggregatorTx': ('Aggregator', 'Group-by fields and aggregate expressions below.'),
    'SorterTx': ('Sorter', 'Sort keys in the order listed; distinct, case and null settings below.'),
    'NormalizerTx': ('Normalizer', 'Normalized fields with their occurrence counts below.'),
    'UpdateStrategyTx': ('(target operation)', 'CDI has no Update Strategy transformation: set the downstream '
                                               'target operation to Data Driven with the condition below.'),
    'MappletTx': ('Mapplet', 'Reusable CDI mapplet (see the mapplets folder).'),
    'MappletInputTx': ('Input', 'Mapplet Input transformation.'),
    'MappletOutputTx': ('Output', 'Mapplet Output transformation.'),
    'CaseConverterTx': ('Cleanse', 'CDQ Cleanse asset with a Change Case step (see cdq.md).'),
    'LabelerTx': ('Labeler', 'CDQ Labeler asset (see cdq.md).'),
    'TokenStandardiserTx': ('Cleanse', 'CDQ Cleanse asset with remove/replace steps (see cdq.md).'),
    'AvTx': ('Verifier', 'CDQ Verifier asset for address verification (see cdq.md).'),
}

DATA_TYPES = {
    'string': 'string', 'varchar': 'string', 'varchar2': 'string', 'nvarchar2': 'nstring', 'char': 'string',
    'decimal': 'decimal', 'number(p,s)': 'decimal', 'number': 'decimal', 'integer': 'integer', 'double': 'double',
    'date/time': 'date/time', 'date': 'date/time', 'timestamp': 'date/time', 'boolean': 'integer',
}


def dec(s):
    return urllib.parse.unquote_plus(s) if s else s


def short(e):
    return (e.get(XSI + 'type') or '').split(':')[-1]


def local(tag):
    return tag.split('}')[-1]


def attr_name(k):
    return k.replace(IMX, 'imx:').replace(XSI, 'xsi:')


def slug(s):
    return re.sub(r'[^A-Za-z0-9]+', '-', s).strip('-').lower()


def md_cell(s):
    return (s or '').replace('|', '\\|').replace('\r', '').replace('\n', '<br>')


def to_cdi(expr, params):
    """Translate an IDQ expression to CDI syntax."""
    if not expr:
        return expr
    out = expr.replace('$sys.MappingRunStartTime', 'SESSSTARTTIME')
    out = out.replace('$sys.MappingName', '$$MappingName')
    for p in sorted(params, key=len, reverse=True):
        out = re.sub(r'(?<!\$)\$' + re.escape(p) + r'\b', '$$' + p, out)
    return out


class Model:
    def __init__(self, path):
        self.root = ET.parse(path).getroot()
        self.by_id = {}
        self.parent = {}
        for p in self.root.iter():
            for c in p:
                self.parent[c] = p
            i = p.get(IMX + 'id')
            if i:
                self.by_id[i] = p
        self.ports = {}
        self.instances = [e for e in self.root.iter() if short(e) == 'Instance' and local(e.tag) == 'Instance']
        for inst in self.instances:
            for p in inst.iter():
                t = short(p)
                if t == 'TransformationFieldPort':
                    f = self.by_id.get(p.get('transformationField'))
                    self.ports[p.get(IMX + 'id')] = (inst, f.get('name') if f is not None else '?', self.group(f))
                elif t == 'NestedPort':
                    sf = self.by_id.get(p.get('structuralFeature'))
                    self.ports[p.get(IMX + 'id')] = (inst, sf.get('name') if sf is not None else '?', None)
        self.handlers = {}
        for h in self.root.iter():
            if local(h.tag) == 'TxHandlerConfig' and h.get('txInstance'):
                self.handlers[h.get('txInstance')] = h
        self.tables = {e.get(IMX + 'id'): e for e in self.root.iter()
                       if (local(e.tag) == 'Table' or short(e) == 'Table') and e.get(IMX + 'id')}
        self.mappings = [e for e in self.root.iter()
                         if (local(e.tag) == 'Mapping' or short(e) == 'Mapping') and e.get('name')]
        self._inbound = None
        self.writers = {}  # target table -> mappings that load it (set by the caller for cross-references)

    def inbound(self, inst):
        """Links into an instance: (field label, upstream instance, upstream field label)."""
        if self._inbound is None:
            self._inbound = defaultdict(list)
            for i in self.instances:
                for p in i.iter():
                    if short(p) not in ('TransformationFieldPort', 'NestedPort') or not p.get('fromPort'):
                        continue
                    src_inst, src = self.label(p.get('fromPort'))
                    if src_inst is not None:
                        self._inbound[i].append((self.label(p.get(IMX + 'id'))[1], src_inst, src))
        return self._inbound[inst]

    def group(self, field):
        """Interface (group) name of a field, only for transformations with several groups per direction."""
        e = self.parent.get(field) if field is not None else None
        tx = e
        while tx is not None and not short(tx).endswith('Tx'):
            tx = self.parent.get(tx)
        if tx is None or short(tx) not in ('RouterTx', 'UnionTx', 'MappletTx', 'NormalizerTx'):
            return None
        while e is not None:
            t = short(e)
            if t.endswith('DataInterface') or t.endswith('Interface'):
                n = e.get('name')
                return None if n in (None, 'Input', 'Output', 'input', 'output') else n
            if t.endswith('Tx') or t == 'Mapping':
                return None
            e = self.parent.get(e)
        return None

    def container(self, e):
        e = self.parent.get(e)
        while e is not None:
            if (local(e.tag) == 'Mapping' or short(e) == 'Mapping') and e.get('name'):
                return e
            e = self.parent.get(e)
        return None

    def tx(self, inst):
        return self.by_id.get(inst.get('transformation'))

    def label(self, port_id):
        p = self.ports.get(port_id)
        if not p:
            return None, '?'
        inst, name, grp = p
        return inst, f'{grp}.{name}' if grp else name

    def connection(self, dso):
        for c in dso.iter():
            if c.get('connectionName'):
                return c.get('connectionName')
        return None

    def table_of(self, ref):
        t = self.tables.get(ref)
        if t is None:
            return None
        return {'name': t.get('name'), 'physical': t.get('physicalName') or t.get('name'),
                'owner': t.get('ownerName'), 'connection': t.get('connectionName'), 'kind': t.get('tableType')}


def ftype(e):
    t = e.get('type') or ''
    if t.startswith('smd:'):
        t = dec(t.split('typesystem%2F')[-1]) if 'typesystem%2F' in t else t.split('.')[-1]
        p, s = e.get('precision'), e.get('scale')
        cdi = DATA_TYPES.get(t, t)
        return f'{cdi}({p},{s})' if s and cdi == 'decimal' else (f'{cdi}({p})' if p and cdi in ('string', 'nstring', 'decimal') else cdi)
    return 'group'


def own_description(e):
    """Description annotation of the element itself (not of its fields)."""
    for a in e:
        if local(a.tag) == 'annotations':
            for d in a:
                if short(d) == 'Description' and d.get('body'):
                    return dec(d.get('body'))
    return None


def fields_of(tx):
    out = []
    for e in tx.iter():
        t = short(e)
        if e is tx or not e.get('name') or not t.endswith('Field') or t in ('RelationalField',):
            continue
        out.append(e)
    return out


class Doc:
    def __init__(self):
        self.lines = []

    def __call__(self, *ls):
        self.lines.extend(ls)

    def table(self, header, rows):
        if not rows:
            return
        self(('| ' + ' | '.join(header) + ' |'), '|' + '---|' * len(header))
        for r in rows:
            self('| ' + ' | '.join(md_cell(str(c)) if c is not None else '' for c in r) + ' |')
        self('')

    def code(self, lang, text):
        self(f'```{lang}', (text or '').replace('\r\n', '\n').replace('\r', '\n').rstrip(), '```', '')

    def text(self):
        return '\n'.join(self.lines).rstrip() + '\n'


def mapping_params(m, mapping):
    out = []
    for p in mapping.iter():
        if short(p) == 'UserDefinedParameter' and m.container(p) is mapping:
            dv = next((d.get('valueLiteral') for d in p if local(d.tag) == 'defaultValue'), None)
            out.append({'name': p.get('name'), 'type': dec((p.get('typeinfo') or '').split('typesystem%2F')[-1]),
                        'precision': p.get('precision'), 'default': dec(dv)})
    return out


def mapping_text(mapping):
    vals = []
    for e in mapping.iter():
        for k in ('expression', 'filterCondition', 'dataCondition', 'sqlQuery', 'lookupCondition', 'updateStrategy'):
            if e.get(k):
                vals.append(dec(e.get(k)))
    return '\n'.join(vals)


def topo(insts, edges):
    order = {i: n for n, i in enumerate(insts)}
    indeg = {i: 0 for i in insts}
    for a, b in edges:
        if a in indeg and b in indeg:
            indeg[b] += 1
    ready = sorted([i for i in insts if indeg[i] == 0], key=order.get)
    out = []
    while ready:
        i = ready.pop(0)
        out.append(i)
        for a, b in sorted(edges, key=lambda x: order.get(x[1], 0)):
            if a == i and b in indeg:
                indeg[b] -= 1
                if indeg[b] == 0:
                    ready.append(b)
        ready.sort(key=order.get)
    return out + [i for i in insts if i not in out]


def describe_attrs(e, m, skip=()):
    out = []
    for k, v in e.attrib.items():
        k = attr_name(k)
        if k in NOT_SHOWN or k in skip:
            continue
        r = m.by_id.get(v)
        if r is not None and r.get('name'):
            v = r.get('name')
        elif v.startswith('smd:'):
            v = dec(v).split('/')[-1].split('.')[-1]
        else:
            v = dec(v)
        v = v.replace('	', '\t')
        out.append(f'{k}=`` {v} ``' if '`' in v else f'{k}=`{v}`')
    return ', '.join(out)


def dq_strategies(doc, m, tx):
    """Dump DQ strategy configuration (case converter, labeler, token standardiser, address validator)."""
    for e in tx.iter():
        t = short(e)
        if t.endswith('Strategy') or t in ('UserOp', 'RtmOp', 'Dictionary', 'CharacterLabel', 'TokenLabel',
                                           'ExecutionItem', 'AvOptionSet', 'AvStringOption', 'FieldParameter'):
            name = dec(e.get('name') or '')
            doc(f'- `{t}` {("**" + name + "**") if name else ""} {describe_attrs(e, m, skip=("description", "function"))}'.rstrip())
            fn = e.get('function')
            if fn:
                doc(f'  - function: `{dec(fn).split("/")[-1]}`')
            ts = m.by_id.get(e.get('tokenSetReference') or '')
            if ts is not None:
                doc(f'  - token set **{dec(ts.get("name"))}**: label `{dec(ts.get("tokenLabel"))}`, regular expression '
                    f'`{dec(ts.get("tokenRegExp"))}` ({dec(ts.get("tokenSetDescription") or "")})')
            for ref in (e.get('characterSets') or '').split():
                cs = m.by_id.get(ref)
                if cs is not None:
                    ranges = ', '.join(f'{chr(int(r.get("startPosition")))}-{chr(int(r.get("endPosition")))}'
                                       if r.get('startPosition') != r.get('endPosition')
                                       else repr(chr(int(r.get('startPosition'))))
                                       for r in cs.iter() if short(r) == 'CharacterRange')
                    doc(f'  - character set **{dec(cs.get("name"))}**: label `{dec(cs.get("characterSetLabel"))}`, '
                        f'characters `{ranges}`')


def links_table(doc, inbound):
    if inbound:
        doc('Links (target field &larr; upstream field):', '')
        rows = []
        for dst, src_inst, src in inbound:
            stale = ' (stale timeline: do not map)' if STALE_COLUMNS.match(dst.split('.')[-1]) else ''
            rows.append([dst + stale, f'{src_inst}.{src}'])
        doc.table(['Field', 'From'], rows)


def retired_reason(m, mapping_name, inst):
    """Why a step is not ported (stale MDM timeline), or None."""
    reason = RETIRED_STEPS.get((mapping_name, inst.get('name')))
    tx = m.tx(inst)
    if reason is None and tx is not None and short(tx) == 'MappletTx':
        mp = m.by_id.get(tx.get('mapplet'))
        if mp is not None and mp.get('name') in RETIRED_MAPPLETS:
            reason = (f'Calls the retired mapplet `{mp.get("name")}`, which {RETIRED_MAPPLETS[mp.get("name")]}. '
                      f'{LINK_AROUND}')
    return reason


def field_note(mapping_name, inst, field):
    note = FIELD_NOTES.get((mapping_name, inst.get('name'), field))
    return f'<br>**Timeline, not ported as is:** {note}' if note else ''


def instance_section(doc, m, inst, params, inbound, used_mapplets, upd=False, retired=None, mapping_name=''):
    tx = m.tx(inst)
    t = short(tx) if tx is not None else '?'
    cdi, note = CDI_TX.get(t, ('(manual)', 'No direct CDI equivalent: rebuild manually.'))
    if retired:
        doc(f'### {inst.get("name")} (not ported)', '', f'IDQ `{t}`. **Not ported: stale MDM timeline.** {retired}', '')
        links_table(doc, inbound)
        return
    doc(f'### {inst.get("name")}', '', f'IDQ `{t}` &rarr; CDI **{cdi}**. {note}', '')
    if tx is None:
        return
    desc = own_description(tx)
    if desc:
        doc(f'> {desc}', '')

    if t in ('SourceTx', 'LookupTx', 'TargetTx'):
        dso = m.by_id.get(tx.get('dso'))
        if dso is not None:
            refs = (dso.get('tableDefinitions') or dso.get('tableDefinition') or '').split()
            tabs = [m.table_of(r) for r in refs if m.table_of(r)]
            rows = [['Connection', m.connection(dso) or (tabs[0]['connection'] if tabs else '')]]
            for tb in tabs:
                rows.append(['Object', f'{(tb["owner"] + ".") if tb["owner"] else ""}{tb["physical"]}'
                                       f'{" (" + tb["kind"].lower() + ")" if tb["kind"] else ""}'])
            if t == 'TargetTx':
                rows.append(['Operation', 'Data Driven (see the upstream Update Strategy)' if upd else 'Insert'])
                rows.append(['Truncate target table', 'yes' if dso.get('truncateTargetTable') == 'true' else 'no'])
                rows.append(['Load type', 'normal (no bulk load)' if dso.get('loadType') == 'Normal'
                             else dso.get('loadType') or 'normal'])
            for k in ('queryMode', 'targetCommitInterval'):
                if dso.get(k):
                    rows.append([k, dso.get(k)])
            if t == 'LookupTx':
                rows += [['Lookup condition', dec(tx.get('lookupCondition'))],
                         ['Multiple matches', {'returnAny': 'Return any row', 'returnFirst': 'Return first row',
                                               'returnLast': 'Return last row', 'reportError': 'Report error'}
                          .get(tx.get('multipleMatchHandling'), tx.get('multipleMatchHandling') or 'Report error')]]
                if tx.get('returnPort'):
                    rows.append(['Unconnected, return port', dec(tx.get('returnPort'))])
                h = m.handlers.get(inst.get(IMX + 'id'))
                if h is not None:
                    rows.append(['Cache', 'static cache' if h.get('cached') == 'true' else 'uncached'])
                    if h.get('cacheFileNamePrefix'):
                        rows.append(['Cache file name prefix', h.get('cacheFileNamePrefix')])
            if t == 'TargetTx':
                h = m.handlers.get(inst.get(IMX + 'id'))
                if h is not None and h.get('rejectFile'):
                    rows.append(['Reject file', h.get('rejectFile')])
            doc.table(['Property', 'Value'], rows)
            if dso.get('filterCondition'):
                doc('Filter (CDI source/lookup *Filter* property; translated):', '')
                doc.code('sql', to_cdi(dec(dso.get('filterCondition')), params))
            if dso.get('sqlQuery'):
                doc('SQL override (CDI *SQL Override*; translated):', '')
                doc.code('sql', to_cdi(dec(dso.get('sqlQuery')), params))
            cols = [f for f in dso.iter() if short(f) == 'RelationalField']
            if t == 'SourceTx' and cols:
                doc('Columns: ' + ', '.join(f'`{c.get("name")}`' for c in cols), '')
            if t == 'LookupTx':
                rows = [[f.get('name'), ftype(f)] for f in tx.iter()
                        if short(f) == 'LookupField' and f.get('input') == 'true' and ftype(f) != 'group']
                doc.table(['Lookup input field', 'Type'], rows)
                rows = []
                for p in inst.iter():
                    if short(p) not in ('NestedPort', 'TransformationFieldPort') or not p.get('toPorts'):
                        continue
                    _, name = m.label(p.get(IMX + 'id'))
                    for to in p.get('toPorts').split():
                        ti, tn = m.label(to)
                        rows.append([name, f'{ti.get("name") if ti is not None else "?"}.{tn}'])
                doc.table(['Return / pass-through field', 'Feeds'], rows)

    if t == 'ExpressionTx':
        rows = []
        for f in fields_of(tx):
            kind = 'variable' if f.get('variable') == 'true' else (
                'in/out' if f.get('input') == 'true' and f.get('output') == 'true' else
                ('in' if f.get('input') == 'true' else 'out'))
            ex = dec(f.get('expression'))
            stale = ' (stale timeline: omit)' if STALE_COLUMNS.match(f.get('name') or '') else ''
            rows.append([f.get('name') + stale, kind, ftype(f),
                         (f'`{to_cdi(ex, params)}`' if ex else '') + field_note(mapping_name, inst, f.get('name'))])
        doc.table(['Field', 'Kind', 'Type', 'Expression (CDI)'], rows)

    if t == 'AggregatorTx':
        refs = [m.by_id.get(r.get('transformationField')) for g in tx.iter() if local(g.tag) == 'groupByFields'
                for r in g.iter() if short(r) == 'TransformationFieldRef']
        group_by = [f.get('name') for f in refs if f is not None]
        doc.table(['Property', 'Value'], [
            ['Group by', ', '.join(f'`{g}`' for g in group_by) or '(none: one output row)'],
            ['Sorted input', 'yes' if tx.get('sortedInput') == 'true' else 'no'],
        ])
        rows = []
        for f in fields_of(tx):
            ex = dec(f.get('expression'))
            kind = 'group by' if f.get('name') in group_by else (
                'in/out' if f.get('input') == 'true' and f.get('output') == 'true' else
                ('in' if f.get('input') == 'true' else 'out'))
            stale = ' (stale timeline: omit)' if STALE_COLUMNS.match(f.get('name') or '') else ''
            rows.append([f.get('name') + stale, kind, ftype(f),
                         (f'`{to_cdi(ex, params)}`' if ex else '') + field_note(mapping_name, inst, f.get('name'))])
        doc.table(['Field', 'Kind', 'Type', 'Aggregate expression (CDI)'], rows)

    if t == 'SorterTx':
        rows = []
        for k in tx.iter():
            if short(k) == 'SortKeyFieldRef':
                ref = next((r for r in k.iter() if short(r) == 'TransformationFieldRef'), None)
                f = m.by_id.get(ref.get('transformationField')) if ref is not None else None
                rows.append([len(rows) + 1, f.get('name') if f is not None else '?',
                             'ascending' if k.get('ascending') == 'true' else 'descending'])
        doc.table(['#', 'Sort key', 'Order'], rows)
        doc.table(['Property', 'Value'], [
            ['Distinct', 'yes' if tx.get('distinct') == 'true' else 'no'],
            ['Case sensitive', 'yes' if tx.get('caseSensitive') == 'true' else 'no'],
            ['Null treated high', 'yes' if tx.get('nullHighest') == 'true' else 'no'],
        ])

    if t == 'NormalizerTx':
        rows = []

        def nodes(parent, depth):
            for n in parent:
                if local(n.tag) == 'normalizerNodes':
                    for c in n:
                        if short(c) == 'NormalizerNode':
                            src = next((x for x in c if short(x) == 'NormalizerSrcField'), None)
                            rows.append(['&nbsp;&nbsp;' * depth + c.get('name'),
                                         'record' if c.get('isRecord') == 'true' else (ftype(src) if src is not None else ''),
                                         c.get('occurs')])
                            nodes(c, depth + 1)
        nodes(tx, 0)
        doc('Normalized fields (a record with *Occurs* > 1 is a multiple-occurring field group):', '')
        doc.table(['Field / record', 'Type', 'Occurs'], rows)
        outs = [g.get('name') for g in tx.iter() if short(g) == 'NormalizerDataInterface' and g.get('output') == 'true']
        if len(outs) > 1:
            doc(f'IDQ output groups: {", ".join(f"`{o}`" for o in outs)}. Downstream links below name the group; '
                f'check that the CDI Normalizer exposes the same split, otherwise route the second group with a '
                f'Router after a single output group.', '')

    if t == 'FilterTx':
        doc('Filter condition:', '')
        doc.code('', to_cdi(dec(tx.get('filterCondition')), params))

    if t == 'RouterTx':
        rows = []
        for g in tx.iter():
            if short(g) == 'RouterDataInterface' and g.get('output') == 'true':
                rows.append([g.get('name'), f'`{to_cdi(dec(g.get("dataCondition")), params)}`'
                             if g.get('dataCondition') else '(default group)'])
        doc.table(['Output group', 'Condition'], rows)

    if t == 'UnionTx':
        groups = [g.get('name') for g in tx.iter() if short(g) == 'UnionDataInterface' and g.get('input') == 'true']
        doc('Input groups: ' + ', '.join(f'`{g}`' for g in groups), '')

    if t == 'UpdateStrategyTx':
        doc(f'Update strategy expression: `{dec(tx.get("updateStrategy"))}` (forward rejected rows: '
            f'{tx.get("rejectForwarding") or "false"}). In CDI set the target operation to **Data Driven** with '
            f'condition `{dec(tx.get("updateStrategy"))}` (or simply **Delete** when the expression is a constant), and mark '
            f'the linked target columns as the update/delete key.', '')

    if t == 'MappletTx':
        mp = m.by_id.get(tx.get('mapplet'))
        if mp is not None:
            used_mapplets.add(mp.get('name'))
            doc(f'Mapplet: [`{mp.get("name")}`](../mapplets/{mp.get("name")}.md)', '')

    if t in ('MappletInputTx', 'MappletOutputTx'):
        doc.table(['Field', 'Type'], [[f.get('name'), ftype(f)] for f in fields_of(tx)])

    if t in ('CaseConverterTx', 'LabelerTx', 'TokenStandardiserTx', 'AvTx'):
        doc(f'Settings: {describe_attrs(tx, m, skip=("transformationConfiguration",)) or "(defaults)"}', '')
        dq_strategies(doc, m, tx)
        doc('')
        if t == 'AvTx':
            linked = {p.get('transformationField') for p in inst.iter()
                      if short(p) == 'TransformationFieldPort' and (p.get('toPorts') or p.get('fromPort'))}
            rows = [[f.get('name'), 'in' if f.get('input') == 'true' else 'out', dec(f.get('internalName')),
                     dec(f.get('groupId')), 'yes' if f.get(IMX + 'id') in linked else '']
                    for f in tx.iter() if short(f) == 'AvField']
            doc('Only the fields marked *linked* need to be selected in the Verifier asset.', '')
            doc.table(['Port', 'Dir', 'AddressDoctor field', 'Group', 'Linked'], rows)

    links_table(doc, inbound)


# ---- filtered data: where rows leave the flow and which rows never reach a C_S_* table ----

PASS_THROUGH = ('FilterTx', 'RouterTx', 'SorterTx', 'UnionTx', 'UpdateStrategyTx')
# literal key lists, single hard-coded ids, row caps and hash sampling: typical leftovers of a test run
TEST_FILTER = re.compile(r"\bIN\s*\(\s*'[^']*'\s*,|\bIN\s*\(\s*\)|=\s*'?\d{6,}'?|\brownum\b|\bORA_HASH\b", re.I)
UPDATE_OPS = {'DD_DELETE': 'deletes', 'DD_UPDATE': 'updates', 'DD_INSERT': 'inserts', 'DD_REJECT': 'is rejected from'}


def one_line(text):
    return ' '.join((text or '').split())


def abbrev(text, n=300):
    text = one_line(text)
    return text if len(text) <= n else text[:n].rstrip() + ' …'


def strip_comments(text, sql=False):
    """Text without comments (expressions: -- and //; SQL: -- and /* */), string literals kept."""
    out, i, n, quoted = [], 0, len(text or ''), False
    while i < n:
        c = text[i]
        if quoted:
            quoted = c != "'"
        elif c == "'":
            quoted = True
        elif text.startswith('--', i) or (not sql and text.startswith('//', i)):
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        elif sql and text.startswith('/*', i):
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return one_line(''.join(out))


def always_true(cond):
    return (cond or '').strip().upper() in ('TRUE', '1')


def _equalities(cond):
    """(FIELD, {literals}) when a condition only compares one field with string literals (`F='a' or F='b'`)."""
    lits, field = set(), None
    for part in re.split(r'\bOR\b', cond or '', flags=re.I):
        hit = re.fullmatch(r"\s*\(?\s*(\w+)\s*=\s*'([^']*)'\s*\)?\s*", part)
        if not hit or (field and hit.group(1).upper() != field):
            return None
        field = hit.group(1).upper()
        lits.add(hit.group(2))
    return (field, lits) if field else None


def complementary(c1, c2):
    """`ISNULL(F)` vs `NOT ISNULL(F)`: exactly one is TRUE for every row."""
    a, b = (re.sub(r'\s+', '', c or '').upper() for c in (c1, c2))
    return a.startswith('ISNULL(') and (b == 'NOT' + a) or b.startswith('ISNULL(') and (a == 'NOT' + b)


def exclusive(c1, c2):
    """True when no row can satisfy both router conditions."""
    if complementary(c1, c2):
        return True
    e1, e2 = _equalities(c1), _equalities(c2)
    return bool(e1 and e2 and e1[0] == e2[0] and not e1[1] & e2[1])


def covering_pair(groups):
    """Two groups that together take every row (`ISNULL(F) or ...` / `NOT ISNULL(F) or ...`), or None."""
    conds = [(gn, re.split(r'\bOR\b', c, flags=re.I)) for gn, c, _ in groups if c]
    return next(((a, b) for k, (a, p1) in enumerate(conds) for b, p2 in conds[k + 1:]
                 if any(complementary(x, y) for x in p1 for y in p2)), None)


def source_gate(m, tx, params):
    dso = m.by_id.get(tx.get('dso'))
    if dso is None:
        return None
    refs = (dso.get('tableDefinitions') or dso.get('tableDefinition') or '').split()
    tabs = [m.table_of(r) for r in refs if m.table_of(r)]
    sql = strip_comments(dec(dso.get('sqlQuery')), sql=True)
    flt = strip_comments(dec(dso.get('filterCondition')), sql=True)
    custom = bool(sql) and bool(dso.get('queryMode'))
    views = [t['physical'] for t in tabs if (t['kind'] or '').upper() == 'VIEW' or t['physical'].upper().startswith('V_')]
    if not (sql or flt or views):
        return None
    g = {'kind': 'source', 'custom': custom, 'views': views if not custom else [], 'notes': [],
         'filter': to_cdi(flt, params) if flt else None, 'distinct': dso.get('distinct') == 'true' and not custom}
    if custom:
        g['rule'] = 'custom SQL query (see the step): only the rows it returns'
        if flt:
            inside = one_line(flt).upper().replace('"', '') in one_line(sql).upper().replace('"', '')
            g['notes'].append(f'filter `{abbrev(flt, 200)}` is also stored'
                              + (' and is part of the query' if inside else
                                 '; it is not part of the custom query text'
                                 + (' and looks like a test filter: confirm it is not applied'
                                    if TEST_FILTER.search(flt) else '')))
    else:
        parts = []
        if flt:
            parts.append(f'source filter `{abbrev(g["filter"], 200)}`')
            if TEST_FILTER.search(flt):
                g['notes'].append('the filter looks like a test filter (hard-coded keys / row cap): confirm before '
                                  'porting')
        if g['distinct']:
            parts.append('select distinct')
        if views:
            parts.append('rows the view ' + ', '.join(f'`{v}`' for v in views) + ' returns (view logic is outside '
                         'the export)')
        if sql:
            g['notes'].append(f'stored SQL text `{abbrev(sql, 120)}` ' + (
                'is a WHERE fragment, not a query, and the read has no custom-query mode: it looks unused, confirm'
                if not re.match(r'\s*(SELECT|WITH)\b', sql, re.I) else
                'is stored but the read has no custom-query mode: confirm whether it runs'))
        g['rule'] = '; '.join(parts) if parts else 'all rows'
    return g


def gate_of(m, inst, params, retired=()):
    """How a step can stop or reduce rows, or None when every row passes unchanged."""
    if inst in retired:
        return None
    tx = m.tx(inst)
    t = short(tx) if tx is not None else ''
    if t == 'SourceTx':
        return source_gate(m, tx, params)
    if t == 'FilterTx':
        raw = dec(tx.get('filterCondition')) or 'TRUE'
        cond = to_cdi(strip_comments(raw), params) or 'TRUE'
        return {'kind': 'filter', 'cond': cond, 'commented': one_line(raw) != cond and ('--' in raw or '//' in raw),
                'meaning': lookup_meaning(m, inst, cond, params)}
    if t == 'RouterTx':
        groups = []
        for g in tx.iter():
            if short(g) == 'RouterDataInterface' and g.get('output') == 'true':
                raw = dec(g.get('dataCondition'))
                groups.append((g.get('name'), to_cdi(strip_comments(raw), params) or 'TRUE' if raw else None,
                               bool(raw) and ('--' in raw or '//' in raw)))
        linked = {m.label(p.get(IMX + 'id'))[1].split('.')[0] for p in inst.iter()
                  if short(p) == 'TransformationFieldPort' and p.get('toPorts')}
        return {'kind': 'router', 'groups': groups, 'linked': linked,
                'meanings': {gn: lookup_meaning(m, inst, c, params) for gn, c, _ in groups if c}}
    if t == 'SorterTx' and tx.get('distinct') == 'true':
        return {'kind': 'distinct'}
    if t == 'AggregatorTx':
        refs = [m.by_id.get(r.get('transformationField')) for g in tx.iter() if local(g.tag) == 'groupByFields'
                for r in g.iter() if short(r) == 'TransformationFieldRef']
        return {'kind': 'aggregate', 'keys': [f.get('name') for f in refs if f is not None]}
    if t == 'UpdateStrategyTx':
        return {'kind': 'update', 'expr': one_line(dec(tx.get('updateStrategy')))}
    if t == 'MappletTx':
        mp = m.by_id.get(tx.get('mapplet'))
        if mp is None or mp.get('name') in RETIRED_MAPPLETS:
            return None
        inner = mapplet_gates(m, mp, params)
        return {'kind': 'mapplet', 'name': mp.get('name'), 'inner': inner} if inner else None
    return None


def mapplet_gates(m, mp, params, prefix=''):
    """Gates inside a mapplet (nested mapplets flattened), in data-flow order."""
    out = []
    insts = [i for i in m.instances if m.container(i) is mp]
    edges = {(s, i) for i in insts for _, s, _ in m.inbound(i)}
    retired = {i for i in insts if retired_reason(m, mp.get('name'), i)}
    for i in topo(insts, edges):
        g = gate_of(m, i, params, retired)
        if g is None or g['kind'] == 'update':
            continue
        if g['kind'] == 'mapplet':
            out += [(f'{i.get("name")}/{n}', ig) for n, ig in g['inner']]
        else:
            out.append((prefix + i.get('name'), g))
    return out


def gate_rule(g):
    k = g['kind']
    if k == 'source':
        return g['rule']
    if k == 'filter':
        return f'keep `{g["cond"]}`' + (' (comments removed)' if g['commented'] else '') +             (f'<br>= {g["meaning"]}' if g.get('meaning') else '')
    if k == 'distinct':
        return 'distinct: exact duplicate rows are collapsed into one'
    if k == 'aggregate':
        return ('one row per ' + ', '.join(f'`{x}`' for x in g['keys'])) if g['keys'] else 'one row in total'
    if k == 'update':
        return f'`{g["expr"]}`'
    if k == 'mapplet':
        return '<br>'.join(f'`{n}`: {gate_rule(ig)}' for n, ig in g['inner'])
    if k == 'router':
        kept = [f'`{gn}` (`{c}`)' if c else f'default `{gn}`' for gn, c, _ in g['groups'] if gn in g['linked']]
        return ('passes only rows of the linked group(s) ' + ', '.join(kept)) if kept else 'no group linked'
    return ''


def field_origin(m, inst, field, params, lookups=None):
    """Where a field read by `inst` comes from: source column, lookup return, expression or mapplet output.

    When the field is a lookup return, the lookup's tables are appended to `lookups`."""
    for _ in range(80):
        hit = next(((si, sl) for dl, si, sl in m.inbound(inst) if dl.split('.')[-1].lower() == field.lower()), None)
        if hit is None:
            return 'not linked'
        inst, field = hit[0], hit[1].split('.')[-1]
        tx = m.tx(inst)
        t = short(tx) if tx is not None else '?'
        name = inst.get('name')
        if t == 'SourceTx':
            return f'source column `{field}` read by `{name}`'
        if t == 'LookupTx':
            dso = m.by_id.get(tx.get('dso'))
            refs = (dso.get('tableDefinitions') or dso.get('tableDefinition') or '').split() if dso is not None else []
            tables = [m.table_of(r)['physical'] for r in refs if m.table_of(r)]
            if lookups is not None:
                lookups.append((name, tables))
            home = m.container(inst)
            loaded = [f'`{t}` is loaded by ' + ', '.join(f'`{w}`' for w in ws) + ' in this workflow'
                      for t in tables for ws in [[w for w in m.writers.get(t.upper(), ())
                                                  if home is None or w != home.get('name')]] if ws]
            return (f'`{field}` returned by lookup `{name}` on ' + (', '.join(f'`{t}`' for t in tables) or '?') +
                    f' where `{one_line(dec(tx.get("lookupCondition")))}`; NULL when no row matches'
                    + ''.join(f'; {x}' for x in loaded))
        if t in ('ExpressionTx', 'AggregatorTx'):
            by_name = {f.get('name'): f for f in fields_of(tx)}
            ex = None
            for _ in range(20):
                f = by_name.get(field)
                ex = dec(f.get('expression')) if f is not None else None
                ident = (ex or '').strip()
                if ex and re.fullmatch(r'\w+', ident) and ident in by_name and ident != field:
                    field = ident
                    continue
                if ident == field:  # in/out port that repeats its own name: pass-through
                    ex = None
                break
            if ex:
                return f'`{name}.{field}` = `{abbrev(to_cdi(strip_comments(ex), params))}`'
            continue
        if t == 'MappletTx':
            mp = m.by_id.get(tx.get('mapplet'))
            outs = [i for i in m.instances if m.container(i) is mp and m.tx(i) is not None
                    and short(m.tx(i)) == 'MappletOutputTx']
            out = next((o for o in outs if any(dl.split('.')[-1].lower() == field.lower() for dl, _, _ in m.inbound(o))),
                       None)
            inner = field_origin(m, out, field, params) if out is not None else 'not linked'
            return f'mapplet `{mp.get("name") if mp is not None else "?"}`: {inner}'
        if t == 'MappletInputTx':
            return f'mapplet input `{field}`'
        if t in PASS_THROUGH:
            continue
        return f'`{field}` output of `{name}` (CDI {CDI_TX.get(t, ("manual",))[0]})'
    return 'not resolved'


def lookup_meaning(m, inst, cond, params):
    """Plain reading of a condition that only null-checks lookup returns, e.g. `IsNull(DEACTIVATION_STS)`."""
    if not cond or re.search(r'\bOR\b', cond, re.I):
        return None
    parts = []
    for c in re.split(r'\bAND\b', cond, flags=re.I):
        hit = re.fullmatch(r'\s*(NOT\s+)?ISNULL\s*\(\s*(\w+)\s*\)\s*(=\s*(0|1|TRUE|FALSE))?\s*', c, re.I)
        if not hit:
            return None
        tables = []
        field_origin(m, inst, hit.group(2), params, tables)
        if not tables:
            return None
        is_null = (hit.group(1) is None) == (hit.group(4) is None or hit.group(4).upper() in ('1', 'TRUE'))
        lkp, tabs = tables[0]
        parts.append((lkp, ', '.join(f'`{t}`' for t in tabs), is_null))
    by = len(parts) > 1
    return ' and '.join((f'no matching row in {t}' if is_null else f'a matching row exists in {t}')
                        + (f' (lookup `{lkp}`)' if by else '') for lkp, t, is_null in parts)


def condition_fields(m, inst, cond):
    """Input fields of `inst` named in a condition, in order of appearance."""
    names = {dl.split('.')[-1].lower(): dl.split('.')[-1] for dl, _, _ in m.inbound(inst)}
    text = re.sub(r"'[^']*'", '', cond or '')
    return list(dict.fromkeys(names[w.lower()] for w in re.findall(r'(?<![$\w])[A-Za-z_]\w*', text)
                              if w.lower() in names))


def flow_graph(m, insts):
    """Row flow between instances: {instance: [(router group or None, downstream instance)]}."""
    out = defaultdict(set)
    for i in insts:
        for _, si, sl in m.inbound(i):
            grp = sl.split('.')[0] if '.' in sl and m.tx(si) is not None and short(m.tx(si)) == 'RouterTx' else None
            out[si].add((grp, i))
    for i in insts:  # whole-row links (port groups) that have no field-level link
        for ol in i.iter():
            if short(ol) == 'OutlineLink':
                a, b = m.by_id.get(ol.get('fromInstance')), m.by_id.get(ol.get('toInstance'))
                if a in insts and b in insts and not any(d is b for _, d in out[a]):
                    out[a].add((None, b))
    return out


def sink_label(m, inst):
    tx = m.tx(inst)
    if short(tx) == 'TargetTx':
        dso = m.by_id.get(tx.get('dso'))
        refs = (dso.get('tableDefinitions') or dso.get('tableDefinition') or '').split() if dso is not None else []
        tabs = [m.table_of(r)['physical'] for r in refs if m.table_of(r)]
        return ', '.join(f'`{t}`' for t in tabs) or f'`{inst.get("name")}`'
    return f'mapplet output `{inst.get("name")}`'


def is_cs(m, inst):
    return sink_label(m, inst).strip('`').upper().startswith('C_S_')


FILTER_INTRO = ('A Filter keeps a row only when its condition is TRUE: FALSE **or NULL** drops the row silently (no target, '
                'no reject file). A Router writes a row to **every** group whose condition is TRUE; a row that matches '
                'no group goes to the default group and is discarded when that group is not linked. Comments (`--`, '
                '`//`) are removed from the conditions shown here. A `= ...` line reads a null check on a lookup return '
                'in plain terms; *no matching row* also covers a matching row whose returned field is NULL.')


def filtered_section(doc, m, mapping, kind, params, order, retired, h='##', title='Filtered data', intro=True):
    """Write the *Filtered data* section; returns [(C_S table, [gate step names], [diverted-to tables])]."""
    insts = [i for i in order]
    sinks = [i for i in insts if m.tx(i) is not None and short(m.tx(i)) in ('TargetTx', 'MappletOutputTx')]
    out = flow_graph(m, insts)
    gates = {i: g for i in insts for g in [gate_of(m, i, params, retired)] if g is not None}
    if not gates:
        if kind == 'mapping':
            doc(f'{h} {title}', '', 'No step in this mapping drops, diverts or collapses rows: every source row '
                'reaches every target.', '')
        return [(sink_label(m, s).strip('`'), [], []) for s in sinks if is_cs(m, s)]
    order_ix = {i: n for n, i in enumerate(order)}

    reach_memo = {}

    def reach(n):
        if n not in reach_memo:
            reach_memo[n] = set()
            r = {n} if n in sinks else set()
            for _, d in out.get(n, ()):
                r |= reach(d)
            reach_memo[n] = r
        return reach_memo[n]

    def reach_group(n, grp):
        r = set()
        for g, d in out.get(n, ()):
            if g == grp:
                r |= reach(d)
        return r

    def fmt(targets):
        if not targets:
            return 'nothing: **discarded**'
        return ', '.join(dict.fromkeys(sink_label(m, t) for t in sorted(targets, key=order_ix.get)))

    doc(f'{h} {title}', '')
    if intro:
        doc('Every step that can stop, divert or collapse rows, and what happens to the rows that do not pass. '
            + FILTER_INTRO, '')
    rows = []
    for i in order:
        g = gates.get(i)
        if g is None:
            continue
        t = short(m.tx(i))
        if g['kind'] == 'router':
            cover = covering_pair(g['groups'])
            for gn, cond, commented in g['groups']:
                linked = reach_group(i, gn)
                connected = gn in g['linked']
                if cond is None and cover:
                    rows.append([i.get('name'), t, f'default group `{gn}`: rows that match no other group',
                                 f'no row gets here: every row matches `{cover[0]}` or `{cover[1]}`', ''])
                    continue
                rule = (f'group `{gn}`: `{cond}`' + (' (comments removed)' if commented else '') if cond
                        else f'default group `{gn}`: rows that match no other group')
                if g['meanings'].get(gn):
                    rule += f'<br>= {g["meanings"][gn]}'
                rows.append([i.get('name'), t, rule, fmt(linked) if connected else 'nothing: group not linked, '
                             '**discarded**', ''])
            continue
        down = reach(i)
        if g['kind'] == 'source':
            lost = 'never read'
        elif g['kind'] == 'filter':
            lost = 'never (condition is always TRUE)' if always_true(g['cond']) else '**discarded**'
        elif g['kind'] in ('distinct', 'aggregate'):
            lost = 'collapsed into the row kept for the same key'
        elif g['kind'] == 'update':
            ops = [v for k, v in UPDATE_OPS.items() if k in g['expr'].upper()]
            lost = f'not dropped: each row {" / ".join(ops) or "changes"} the target row'
        else:
            lost = '**discarded** inside the mapplet'
        note = ''.join(f'<br>Note: {n}' for n in g.get('notes', ()))
        rows.append([i.get('name'), t, gate_rule(g) + note, fmt(down), lost])
    for i in order:
        tx = m.tx(i)
        if i in retired and tx is not None and short(tx) in ('FilterTx', 'RouterTx', 'SorterTx', 'AggregatorTx'):
            rows.append([i.get('name'), short(tx), f'**not ported** (stale MDM timeline): {retired[i]}', '', ''])
    doc(f'{h}# Steps that filter rows', '')
    doc.table(['Step', 'IDQ type', 'Rule', 'Rows that pass go to', 'Rows that do not pass'], rows)

    rows = []
    for i in order:
        g = gates.get(i)
        conds = ([g['cond']] if g and g['kind'] == 'filter' else
                 [c for _, c, _ in g['groups'] if c] if g and g['kind'] == 'router' else [])
        for f in condition_fields(m, i, ' '.join(conds)):
            rows.append([i.get('name'), f'`{f}`', field_origin(m, i, f, params)])
    if rows:
        doc(f'{h}# Where the condition fields come from', '')
        doc.table(['Step', 'Field', 'Origin'], rows)

    if kind != 'mapping':
        return []

    # gate sequences from every start step to every sink
    memo = {}

    def walk(n):
        if n not in memo:
            res = defaultdict(set)
            if n in sinks:
                res[n].add(())
            for grp, d in sorted(out.get(n, ()), key=lambda x: (order_ix.get(x[1], 0), x[0] or '')):
                step = ((n, grp),) if n in gates else ()
                for t, seqs in walk(d).items():
                    res[t] |= {step + s for s in seqs}
            memo[n] = res
        return memo[n]

    starts = [i for i in insts if not m.inbound(i)]
    paths = defaultdict(set)
    for s in starts:
        for t, seqs in walk(s).items():
            paths[t] |= seqs

    doc(f'{h}# Rows that do not reach `C_S_*` tables', '')
    cs = [s for s in sinks if is_cs(m, s)]
    other = [s for s in sinks if not is_cs(m, s)]
    summary = []
    if not cs:
        doc('This mapping writes no `C_S_*` table (it loads ' + fmt(set(other)) + '); the steps above decide which '
            'rows it writes.', '')
        return summary
    for s in cs:
        seqs = sorted(paths.get(s, ()), key=lambda q: [(order_ix[x[0]], x[1] or '') for x in q])
        upd = [gates[x[0]] for q in seqs for x in q if gates[x[0]]['kind'] == 'update']
        op = 'delete' if any('DD_DELETE' in u['expr'].upper() for u in upd) else 'write'
        doc(f'**{sink_label(m, s)}** (`{s.get("name")}`): a source row is {"used to delete" if op == "delete" else "written"} '
            f'only when it passes every step below{"" if len(seqs) < 2 else " on one of its " + str(len(seqs)) + " paths"}.', '')
        steps_all, diverted = [], set()
        if not seqs:
            doc('No source row reaches this target through linked fields.', '')
        for k, q in enumerate(seqs):
            rows = []
            for i, grp in q:
                g = gates[i]
                if g['kind'] == 'update':
                    continue
                steps_all.append(i.get('name'))
                if g['kind'] == 'router':
                    cond = next((c for gn, c, _ in g['groups'] if gn == grp), None)
                    must = f'group `{grp}`: `{cond}`' if cond else f'matches none of the other groups (default `{grp}`)'
                    if g['meanings'].get(grp):
                        must += f'<br>= {g["meanings"][grp]}'
                    if cond and always_true(cond):
                        lost = 'never (condition is always TRUE)'
                    else:
                        alts = []
                        for gn, c, _ in g['groups']:
                            if gn == grp or c is None:
                                continue
                            dest = reach_group(i, gn)
                            diverted |= dest
                            linked = gn in g['linked']
                            alts.append(f'if `{c}`: group `{gn}` &rarr; ' + (fmt(dest) if linked else
                                                                             'not linked, **discarded**'))
                        dflt = next((gn for gn, c, _ in g['groups'] if c is None and gn != grp), None)
                        if dflt is not None and not covering_pair(g['groups']):
                            dest = reach_group(i, dflt)
                            diverted |= dest
                            alts.append('if no group matches: ' + (f'default group `{dflt}` &rarr; {fmt(dest)}'
                                                                    if dest else '**discarded** (default group not linked)'))
                        lost = '<br>'.join(alts) or '**discarded**'
                    others = [gn for gn, c, _ in g['groups'] if c and gn != grp and not (cond and exclusive(cond, c))]
                    if cond and others:
                        must += '<br>(a row that also matches ' + ', '.join(f'`{o}`' for o in others) + \
                                ' is written there as well)'
                elif g['kind'] == 'source':
                    must = g['rule'] + ''.join(f'<br>Note: {n}' for n in g['notes'])
                    lost = 'never read'
                elif g['kind'] == 'filter':
                    must = f'`{g["cond"]}`' + (f'<br>= {g["meaning"]}' if g.get('meaning') else '')
                    lost = 'never (condition is always TRUE)' if always_true(g['cond']) else \
                        '**discarded** (not written anywhere)'
                elif g['kind'] == 'distinct':
                    must = 'not an exact duplicate of an earlier row'
                    lost = 'collapsed into the identical row'
                elif g['kind'] == 'aggregate':
                    must = gate_rule(g)
                    lost = 'merged into the one row written for its key'
                else:
                    must = gate_rule(g)
                    lost = '**discarded** inside the mapplet'
                rows.append([f'`{i.get("name")}`', must, lost])
            if len(seqs) > 1:
                doc(f'Path {k + 1}:', '')
            if rows:
                doc.table(['Step', 'Must hold', 'Otherwise the row'], rows)
            else:
                doc('No filtering step on this path: every row read is written.', '')
        diverted -= {s}
        summary.append((sink_label(m, s).strip('`'), list(dict.fromkeys(steps_all)),
                        list(dict.fromkeys(sink_label(m, d).strip('`') for d in sorted(diverted, key=order_ix.get)))))
    return summary


def table_writers(m, mapping_names):
    """{TARGET TABLE: [mappings that load it]} for the given mappings."""
    out = defaultdict(list)
    for mp in m.mappings:
        if mp.get('name') not in mapping_names:
            continue
        for i in m.instances:
            if m.container(i) is mp and m.tx(i) is not None and short(m.tx(i)) == 'TargetTx':
                t = sink_label(m, i).strip('`').upper()
                if mp.get('name') not in out[t]:
                    out[t].append(mp.get('name'))
    return dict(out)


def mapping_filtered(m, mapping, kind='mapping', h='##', title='Filtered data', intro=True):
    """The *Filtered data* section of one mapping on its own: (markdown lines, summary)."""
    insts = [i for i in m.instances if m.container(i) is mapping]
    edges = {(si, i) for i in insts for _, si, _ in m.inbound(i)}
    for i in insts:
        for ol in i.iter():
            if short(ol) == 'OutlineLink':
                a, b = m.by_id.get(ol.get('fromInstance')), m.by_id.get(ol.get('toInstance'))
                if a is not None and b is not None:
                    edges.add((a, b))
    retired = {i: r for i in insts for r in [retired_reason(m, mapping.get('name'), i)] if r}
    doc = Doc()
    summary = filtered_section(doc, m, mapping, kind, [p['name'] for p in mapping_params(m, mapping)],
                               topo(insts, edges), retired, h, title, intro)
    return doc.lines, summary


ORACLE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, 'idq-to-oracle')


def oracle_registry():
    """Purpose of every shared Oracle object, from the tables in the idq-to-oracle/common headers."""
    reg, last = {}, None
    for fname in ('02_dq_functions_contract.sql', '03_ors_common_helpers.sql'):
        path = os.path.join(ORACLE_DIR, 'common', fname)
        if not os.path.exists(path):
            continue
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                cells = [c.strip() for c in line.rstrip('\n').lstrip('- ').strip('|').split('|')]
                if len(cells) == 2 and re.fullmatch(r'(fn|sp)_ors_\w+', cells[0]):
                    reg[cells[0]], last = cells[1], cells[0]
                elif len(cells) == 2 and not cells[0] and last:
                    reg[last] += ' ' + cells[1]
                elif len(cells) == 3 and re.fullmatch(r'fn_dq_\w+', cells[1]):
                    reg[cells[1]], last = f'replaces `{cells[0]}`, returns `{cells[2]}`', None
                else:
                    last = None
    return reg


def oracle_section(doc, wf, name):
    """'Oracle stored procedure' section: the sp_ors_main_<mapping> drop-in replacement in idq-to-oracle/<wf>/."""
    proc = f'sp_ors_main_{name}'
    path = os.path.join(ORACLE_DIR, wf or '', proc + '.sql')
    if not wf or not os.path.exists(path):
        return
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    lines = text.splitlines()
    header = []
    for line in lines[1:]:
        if line.startswith('-----'):
            break
        header.append(line[3:] if line.startswith('-- ') else line[2:])
    while header and (not header[0].strip() or header[0].strip() == proc):
        header.pop(0)
    code = re.sub(r'/\*.*?\*/', ' ', re.sub(r'--[^\n]*', '', text), flags=re.S)
    doc('## Oracle stored procedure', '',
        f'Drop-in replacement in Oracle: [`{proc}`](../../../idq-to-oracle/{wf}/{proc}.sql) (set-based SQL; one '
        f'transaction that commits at the end and rolls back and re-raises on error). The IDQ mapplets and rules '
        f'become the shared `fn_dq_*` functions; see [idq-to-oracle/README.md](../../../idq-to-oracle/README.md). '
        f'Unlike the CDI spec above, the procedure **keeps the MDM timeline logic**; it is marked `TIMELINE` in the '
        f'comments.', '')
    doc('```text', *header, '```', '')
    sig = re.search(r'CREATE OR REPLACE PROCEDURE\s+\w+\s*\((.*?)\)\s*IS', text, re.S)
    if sig:
        rows = []
        for line in sig.group(1).splitlines():
            p = re.match(r"\s*(\w+)\s+IN\s+(\w+)(?:\s+DEFAULT\s+(.*?))?\s*,?\s*(?:--\s*(.*))?$", line)
            if p:
                rows.append([f'`{p.group(1)}`', p.group(2), f'`{p.group(3)}`' if p.group(3) else '',
                             md_cell(p.group(4) or '')])
        if rows:
            doc('Parameters:', '')
            doc.table(['Parameter', 'Type', 'Default', 'Replaces / meaning'], rows)
    writes = {}
    for t in re.findall(r"sp_ors_helper01_common\s*\(\s*'(\w+)'", code):
        writes.setdefault(t.upper(), []).append('truncate')
    for t in re.findall(r'\bDELETE\s+FROM\s+(\w+)', code, re.I):
        writes.setdefault(t.upper(), []).append('delete')
    for t in re.findall(r'\bINTO\s+(\w+)', code, re.I):
        if not t.lower().startswith('l_'):   # SELECT ... INTO l_<variable>
            writes.setdefault(t.upper(), []).append('insert')
    if writes:
        doc('Tables written:', '')
        doc.table(['Table', 'Operation'],
                  [[f'`{t}`', ', '.join(dict.fromkeys(ops))] for t, ops in writes.items()])
    reg = oracle_registry()
    used = sorted(set(re.findall(r'\b((?:fn|sp)_ors_helper\d+_\w+|fn_dq_\w+)\b', code)), key=lambda s: (s[:2], s))
    if used:
        doc('Shared functions and procedures called:', '')
        doc.table(['Object', 'Does'], [[f'`{u}`', md_cell(reg.get(u, ''))] for u in used])


def build_mapping(m, mapping, kind, wf=None):
    doc = Doc()
    name = mapping.get('name')
    params = [p['name'] for p in mapping_params(m, mapping)]
    insts = [i for i in m.instances if m.container(i) is mapping]
    names = {i: i.get('name') for i in insts}
    inbound = defaultdict(list)
    edges = set()
    for inst in insts:
        for dst, src_inst, src in m.inbound(inst):
            inbound[inst].append((dst, src_inst.get('name'), src))
            edges.add((src_inst, inst))
        for ol in inst.iter():
            if short(ol) == 'OutlineLink':
                a, b = m.by_id.get(ol.get('fromInstance')), m.by_id.get(ol.get('toInstance'))
                if a is not None and b is not None:
                    edges.add((a, b))
    order = topo(insts, edges)
    desc = own_description(mapping)
    cdi_kind = 'Mapping' if kind == 'mapping' else 'Mapplet'
    doc(f'# {name}', '', f'IDQ {kind} &rarr; CDI **{cdi_kind}** `{name}`.', '')
    if name in RETIRED_MAPPLETS:
        doc(f'> **Not ported: stale MDM timeline.** This mapplet {RETIRED_MAPPLETS[name]}. Do not build it; the '
            f'callers link around it. The spec below is kept for reference only.', '')
    if desc:
        doc(f'> {desc}', '')

    retired = {i: retired_reason(m, name, i) for i in insts}
    retired = {i: r for i, r in retired.items() if r}
    counts = defaultdict(int)
    if name not in RETIRED_MAPPLETS:
        for i in insts:
            if i not in retired:
                counts[short(m.tx(i)) if m.tx(i) is not None else '?'] += 1
    doc('## Summary', '')
    doc.table(['IDQ transformation', 'CDI transformation', 'Count'],
              [[t, CDI_TX.get(t, ('(manual)',))[0], c] for t, c in sorted(counts.items())])
    retired_rows = [[name, i.get('name'), short(m.tx(i)) if m.tx(i) is not None else '?', r]
                    for i, r in sorted(retired.items(), key=lambda x: order.index(x[0]))]
    if retired_rows:
        doc('## Not ported (stale MDM timeline)', '',
            'These steps are not built (and not counted above); their sections below say how to rewire around them.',
            '')
        doc.table(['Step', 'IDQ type', 'Reason'], [r[1:] for r in retired_rows])
    sources, targets = [], []
    for i in insts:
        tx = m.tx(i)
        if tx is None or short(tx) not in ('SourceTx', 'TargetTx'):
            continue
        dso = m.by_id.get(tx.get('dso'))
        refs = (dso.get('tableDefinitions') or dso.get('tableDefinition') or '').split() if dso is not None else []
        objs = ', '.join(f'`{m.table_of(r)["physical"]}`' for r in refs if m.table_of(r))
        row = [i.get('name'), objs, m.connection(dso) if dso is not None else '']
        (sources if short(tx) == 'SourceTx' else targets).append(row)
    if sources:
        doc('Sources:', '')
        doc.table(['Instance', 'Object', 'Connection'], sources)
    if targets:
        doc('Targets:', '')
        doc.table(['Instance', 'Object', 'Connection'], targets)

    plist = mapping_params(m, mapping)
    if plist:
        text = mapping_text(mapping)
        doc('## Parameters', '', 'Create as CDI input parameters (`$$Name`); defaults go in the parameter file.', '')
        doc.table(['Parameter', 'Type', 'Precision', 'Default', 'Used in this ' + kind],
                  [[p['name'], p['type'], p['precision'], p['default'],
                    'yes' if re.search(r'\$' + re.escape(p['name']) + r'\b', text) else 'no (declared only)']
                   for p in plist])
    if '$sys.MappingName' in mapping_text(mapping):
        doc('`$sys.MappingName` is translated to the input parameter `$$MappingName` (default: the mapping name).', '')

    for c in mapping.iter():
        if short(c) == 'OneAfterAnotherConstraint':
            a, b = m.by_id.get(c.get('primaryInstance')), m.by_id.get(c.get('secondaryInstance'))
            doc('## Target load order', '',
                f'Load `{a.get("name") if a is not None else "?"}` before `{b.get("name") if b is not None else "?"}` '
                f'(CDI mapping *Target Load Order*).', '')

    doc('## Flow', '', '```mermaid', 'flowchart LR')
    ids = {i: f'n{k}' for k, i in enumerate(order)}
    for i in order:
        t = short(m.tx(i)) if m.tx(i) is not None else '?'
        label = 'not ported' if i in retired else CDI_TX.get(t, ("manual",))[0]
        doc(f'  {ids[i]}["{names[i]}<br/><i>{label}</i>"]')
    for a, b in sorted(edges, key=lambda e: (order.index(e[0]) if e[0] in order else 0,
                                              order.index(e[1]) if e[1] in order else 0)):
        if a in ids and b in ids:
            doc(f'  {ids[a]} --> {ids[b]}')
    if retired:
        doc('  classDef retired stroke-dasharray: 5 5,opacity:0.5',
            '  class ' + ','.join(ids[i] for i in order if i in retired) + ' retired')
    doc('```', '')

    summary = []
    if name not in RETIRED_MAPPLETS:
        summary = filtered_section(doc, m, mapping, kind, params, order, retired)
    if kind == 'mapping':
        oracle_section(doc, wf, name)

    doc('## Transformations', '', 'In data-flow order.', '')
    used = set()
    for i in order:
        upd = any(a is not None and m.tx(a) is not None and short(m.tx(a)) == 'UpdateStrategyTx'
                  for a, b in edges if b is i)
        instance_section(doc, m, i, params, inbound.get(i), used, upd, retired.get(i), name)
    return doc.text(), used, counts, retired_rows, summary


def workflow(m):
    wf = next((e for e in m.root.iter() if local(e.tag) == 'Workflow' and e.get('name')), None)
    if wf is None:
        return None
    tasks = {}
    flows = []
    for ti in wf.iter():
        if short(ti) == 'TaskInstance':
            at = next((c for c in ti if local(c.tag) == 'anonymousTask'), None)
            cfg = {}
            if at is not None:
                for c in at.iter():
                    if c.get('value') is not None and short(c).endswith('BoxedReceiverObject'):
                        cfg[local(c.tag)] = dec(c.get('value'))
            tasks[ti.get(IMX + 'id')] = {
                'name': ti.get('name'), 'type': short(at) if at is not None else '?',
                'mapping': (m.by_id.get(at.get('mapping')).get('name')
                            if at is not None and at.get('mapping') and m.by_id.get(at.get('mapping')) is not None
                            else None),
                'command': dec(at.get('command')) if at is not None else None, 'config': cfg}
        if short(ti) == 'SequenceFlow':
            flows.append((ti.get('fromInstance'), ti.get('toInstance'), ti.get('isDefault') == 'true'))
    variables = [v.get('name') for v in wf.iter() if short(v) == 'UserVariable']
    return {'name': wf.get('name'), 'tasks': tasks, 'flows': flows, 'variables': variables}


def mct(task_name):
    """Mapping task name for an IDQ mapping task (m_X -> mct_X)."""
    return 'mct_' + (task_name[2:] if task_name.lower().startswith('m_') else task_name)


def taskflow_doc(wfm, tf):
    doc = Doc()
    tasks, flows = wfm['tasks'], wfm['flows']
    succ = defaultdict(list)
    for a, b, d in flows:
        succ[a].append((b, d))
    doc(f'# Taskflow {tf}', '', f'Replaces IDQ workflow `{wfm["name"]}`. Create it as a **Taskflow** (not a linear '
        f'taskflow) because the workflow runs mapping tasks in parallel.', '')
    doc('## IDQ workflow', '', '```mermaid', 'flowchart LR')
    for k, t in tasks.items():
        shape = ('(["{}"])' if t['type'] in ('StartTask', 'EndTask') else
                 ('{{"{}"}}' if 'Gateway' in t['type'] else '["{}"]')).format(t['name'])
        doc(f'  {slug(k)}{shape}')
    for a, b, d in flows:
        doc(f'  {slug(a)} -->{"|default|" if d else ""} {slug(b)}')
    doc('```', '')

    # collapse gateway pairs into Parallel Paths steps
    start = next(k for k, t in tasks.items() if t['type'] == 'StartTask')
    steps, seen, cur = [], set(), start
    while cur and cur not in seen:
        seen.add(cur)
        t = tasks[cur]
        nxt = [b for b, d in succ.get(cur, []) if not d]
        if 'Gateway' in t['type'] and len(succ.get(cur, [])) > 1:
            # each branch is a chain of tasks that ends at the join gateway
            branches, join = [], None
            for b in nxt:
                chain = []
                while b and 'Gateway' not in tasks[b]['type']:
                    chain.append(tasks[b]['name'])
                    b = (succ.get(b) or [(None, False)])[0][0]
                join = join or b
                if chain:
                    branches.append(chain)
            join = join or next((b for b, d in succ.get(cur, []) if d), None)
            steps.append(('parallel', branches))
            seen.add(join)
            cur = (succ.get(join) or [(None, False)])[0][0] if join else None
            continue
        if t['type'] == 'MappingTask':
            steps.append(('data', t['name']))
        elif t['type'] == 'CommandTask':
            steps.append(('command', t))
        elif t['type'] == 'EndTask':
            steps.append(('end', None))
        elif t['type'] == 'ParallelAndGatewayTask':
            pass
        cur = (nxt or [b for b, _ in succ.get(cur, [])] or [None])[0]

    doc('## CDI taskflow', '', '```mermaid', 'flowchart LR', '  s(["Start"])')
    prev = ['s']
    for n, (kind, val) in enumerate(steps):
        sid = f'p{n}'
        if kind == 'parallel':
            doc(f'  {sid}{{{{"Parallel Paths {n}"}}}}')
            for p in prev:
                doc(f'  {p} --> {sid}')
            branch_ids = []
            for k, chain in enumerate(val):
                last = sid
                for j, b in enumerate(chain):
                    bid = f'{sid}b{k}s{j}'
                    doc(f'  {bid}["Data Task<br/>{mct(b)}"]')
                    doc(f'  {last} --> {bid}')
                    last = bid
                branch_ids.append(last)
            prev = branch_ids
        elif kind == 'data':
            doc(f'  {sid}["Data Task<br/>{mct(val)}"]')
            for p in prev:
                doc(f'  {p} --> {sid}')
            prev = [sid]
        elif kind == 'command':
            doc(f'  {sid}["Command Task<br/>{val["name"]}"]')
            for p in prev:
                doc(f'  {p} --> {sid}')
            prev = [sid]
        elif kind == 'end':
            doc(f'  {sid}(["End"])')
            for p in prev:
                doc(f'  {p} --> {sid}')
    doc('```', '')

    doc('## Steps', '')
    rows = []
    for n, (kind, val) in enumerate(steps):
        if kind == 'parallel':
            rows.append([n, 'Parallel Paths',
                         '<br>'.join(f'path {k + 1}: ' + ' &rarr; '.join(f'`{mct(b)}`' for b in chain)
                                     for k, chain in enumerate(val)),
                         'Data Tasks in a path run in sequence; all paths must complete before the next step '
                         '(same as the IDQ join gateway).'])
        elif kind == 'data':
            rows.append([n, 'Data Task', f'`{mct(val)}`', ''])
        elif kind == 'command':
            rows.append([n, 'Command Task', val['name'],
                         f'IDQ command `{val["command"]}`, working directory '
                         f'`{val["config"].get("workingDirectory", "")}`. See below.'])
        elif kind == 'end':
            rows.append([n, 'End', '', ''])
    doc.table(['#', 'Step', 'Runs', 'Notes'], rows)

    doc('## Mapping tasks', '', 'Create one mapping task per mapping. IDQ mapping-task settings and their CDI home:', '')
    rows = []
    for t in tasks.values():
        if t['type'] != 'MappingTask':
            continue
        c = t['config']
        rows.append([f'`{mct(t["name"])}`', f'[`{t["mapping"]}`](mappings/{t["mapping"]}.md)',
                     c.get('dateFormat', ''), c.get('highPrecisionEnabled', ''), c.get('overrideTracingLevel', ''),
                     c.get('sortOrder', '')])
    doc.table(['Mapping task', 'Mapping', 'Date format (Advanced session property *Default date format*)',
               'High precision (*Enable high precision*)', 'Tracing (*Override tracing*)', 'Sort order'], rows)
    doc('Each Data Task: *On error* = **Fail taskflow** (IDQ aborts the workflow when a mapping task fails). '
        'Pass the parameter file through the mapping task *Parameter file* setting (see the `.param` file).', '')
    if wfm['variables']:
        doc('Workflow variables `' + '`, `'.join(wfm['variables']) + '` are declared but never assigned or read in '
            'the IDQ workflow: not ported.', '')
    for kind, val in steps:
        if kind == 'command':
            doc('## Command task', '',
                f'IDQ runs `{val["command"]}` on the DIS host. In the CDI taskflow add a **Command Task** step '
                f'that runs on the Linux Secure Agent runtime environment:', '')
            doc.table(['Field', 'Value'], [
                ['Runtime Environment', 'the Linux Secure Agent group used by the mapping tasks'],
                ['Script File Name', '`/bin/sh`'],
                ['Input Arguments', f'`-c "touch {wfm["name"]}.ind"`'],
                ['Work Directory', f'`{val["config"].get("workingDirectory", "")}`'],
            ])
            doc(f'`${{var:sys.WorkflowName}}` resolved to `{wfm["name"]}` so the indicator file name downstream '
                f'consumers watch does not change. The agent user needs write access to the working directory.', '')
    return doc.text(), steps


DQ_HELP = {
    'CaseConverterTx': 'Cleanse asset, step **Change Case** with the conversion type listed. Equivalent CDI '
                       'Expression: `UPPER()` / `LOWER()` / `INITCAP()` (Title).',
    'TokenStandardiserTx': 'Cleanse asset. *Remove Custom Strings* &rarr; step **Remove/Replace Characters** (the search '
                           'strings listed). *Remove Reference Table Matches* &rarr; step **Replace with dictionary '
                           'values / Remove dictionary matches** using the dictionary listed. Keep the *trim* and '
                           '*remove multiple spaces* options as Cleanse steps **Remove Spaces**.',
    'LabelerTx': 'Labeler asset. Character labeling &rarr; *Character Labels* with the same character sets; '
                 'token labeling &rarr; *Token Labels* with the same token sets / regular expressions and '
                 'delimiters.',
    'AvTx': 'Verifier asset (address verification, US). Map the input ports to the Verifier input fields and '
            'select the *linked* output fields listed in the mapplet spec (the AddressDoctor field names are kept '
            'in CDQ). Mode `CERTIFIED` = CASS-certified processing; casing, default and force country as listed.',
}


def cdq_doc(m, mapping_names, mapplet_names):
    doc = Doc()
    doc('# CDQ assets', '', 'The IDQ data quality transformations become CDQ assets that the CDI mapplets/mappings '
        'call through the Cleanse, Labeler and Verifier transformations.', '')
    refs = [e for e in m.root.iter() if short(e) == 'ReferenceTable' and e.get('name')]
    defined = {r.get(IMX + 'id') for r in refs}
    external = sorted({(dec(d.get('path') or ''), dec(d.get('filename') or '')) for d in m.root.iter()
                       if short(d) == 'Dictionary' and d.get('refTable') not in defined})
    if refs or external:
        doc('## Dictionaries (from IDQ reference tables)', '',
            'IDQ managed reference tables keep their rows in the reference data warehouse '
            '(connection shown), not in the export. Export the rows with the SQL below and import them into a CDQ '
            '**Dictionary** asset of the same name.', '')
        rows = []
        for r in refs:
            dso = next((c for c in r if short(c) == 'ReadRelationalDataSourceOperation'), None)
            cols = [f.get('name') for f in r.iter() if short(f) == 'StructuralFeature']
            valid = m.by_id.get(r.get('validColumn'))
            tdef = m.table_of(dso.get('tableDefinitions')) if dso is not None else None
            desc = next((dec(a.get('body')) for a in r.iter() if short(a) == 'Description' and a.get('body')), '')
            rows.append([r.get('name'), desc, m.connection(dso) if dso is not None else '',
                         tdef['physical'] if tdef else '', ', '.join(cols)])
        doc.table(['Dictionary', 'Description', 'IDQ connection', 'Physical table', 'Columns (first = valid value)'],
                  rows)
        for row in rows:
            doc.code('sql', f'SELECT * FROM {row[3]};  -- {row[2]}: rows for dictionary {row[0]}')
        if external:
            doc('Referenced but not defined in this export (shared Model Repository project); export them from '
                'the Developer tool and create the dictionaries the same way:', '')
            doc.table(['Dictionary', 'MRS project'], [[f, pth] for pth, f in external])
    doc('## Assets by IDQ transformation', '')
    for mp in sorted(set(mapping_names) | set(mapplet_names)):
        mapping = next(x for x in m.mappings if x.get('name') == mp)
        for i in m.instances:
            if m.container(i) is not mapping:
                continue
            tx = m.tx(i)
            if tx is None or short(tx) not in DQ_HELP:
                continue
            t = short(tx)
            asset = f'{ {"CaseConverterTx": "cl", "TokenStandardiserTx": "cl", "LabelerTx": "lb", "AvTx": "vr"}[t]}_{i.get("name")}'
            folder = 'mapplets' if mp in mapplet_names else 'mappings'
            doc(f'### {asset}', '', f'From `{i.get("name")}` (`{t}`) in [`{mp}`]({folder}/{mp}.md). {DQ_HELP[t]}', '')
            dq_strategies(doc, m, tx)
            doc('')
    return doc.text()


def param_file(m, wfm, tf, project, folder):
    lines = ['#USE_SECTIONS', '', '[Global]', '$$MappingName=']
    for t in wfm['tasks'].values():
        if t['type'] != 'MappingTask':
            continue
        mapping = next(x for x in m.mappings if x.get('name') == t['mapping'])
        lines += ['', f'[{project}].[{folder}].[{mct(t["name"])}]', f'$$MappingName={t["mapping"]}']
        for p in mapping_params(m, mapping):
            lines.append(f'$${p["name"]}={p["default"] or ""}')
    return '\n'.join(lines) + '\n'


def readme(m, wfm, tf, mappings, mapplets, counts, steps, project, folder, retired_steps=(), retired_mapplets=(),
           filtered=None):
    doc = Doc()
    doc(f'# {wfm["name"]} &rarr; IDMC CDI', '',
        f'Build specification generated from `docs/{wfm["name"]}.xml` by `ext-tools/idmc_spec.py`. It describes every '
        f'asset to create in IDMC so the CDI/CDQ version behaves like the IDQ workflow. Regenerate rather than edit.', '')
    doc('## Target layout', '')
    doc.table(['IDMC asset', 'Name', 'Count', 'Spec'], [
        ['Project / folder', f'`{project}` / `{folder}`', 1, ''],
        ['Taskflow', f'`{tf}`', 1, '[taskflow.md](taskflow.md)'],
        ['Mapping task', '`mct_<mapping name without m_>`', len(mappings), '[taskflow.md](taskflow.md#mapping-tasks)'],
        ['Mapping', 'same as IDQ', len(mappings), 'mappings/'],
        ['Mapplet', 'same as IDQ (`mplt_*`, `rule_*`)', len(mapplets), 'mapplets/'],
        ['CDQ assets', 'Cleanse / Labeler / Verifier / Dictionary', '', '[cdq.md](cdq.md)'],
        ['Parameter file', f'`{tf}.param`', 1, f'[{tf}.param]({tf}.param)'],
    ])
    doc('## Connections', '', 'Keep the IDQ connection names so the specs read one to one.', '')
    conns = {}
    for c in m.root.iter():
        if local(c.tag).endswith('ConnectInfo') and c.get('name'):
            conns[c.get('name')] = c.get('connectionType')
    doc.table(['Connection', 'IDQ type', 'IDMC connector'],
              [[n, t, 'Snowflake Data Cloud (replaces the ODBC DSN)' if 'snowflake' in n.lower() else
                ('Oracle' if t == 'ORACLE' else t)] for n, t in sorted(conns.items())])
    doc('## Build order', '',
        '1. Connections and the Secure Agent runtime environment (Linux, command tasks enabled).',
        '2. CDQ dictionaries, then Cleanse / Labeler / Verifier assets ([cdq.md](cdq.md)).',
        '3. Mapplets, innermost first:', '')
    for n in mapplets:
        doc(f'   - [`{n}`](mapplets/{n}.md)')
    doc('', '4. Mappings, in taskflow order:', '')
    for n in mappings:
        doc(f'   - [`{n}`](mappings/{n}.md)')
    doc('', '5. Mapping tasks with the parameter file, then the taskflow ([taskflow.md](taskflow.md)).', '')
    total = defaultdict(int)
    for c in counts:
        for t, n in c.items():
            total[t] += n
    doc('## Transformation inventory', '')
    doc.table(['IDQ transformation', 'CDI', 'Count', 'Note'],
              [[t, CDI_TX.get(t, ('(manual)',))[0], n, CDI_TX.get(t, ('', 'rebuild manually'))[1]]
               for t, n in sorted(total.items())])
    doc('## Not ported: stale MDM timeline', '',
        'The legacy MDM timeline of the C_S_* tables is stale, so its logic is not built (same decision as the Java '
        'port; see the *Retired / not ported* sections of `docs/mappings`):', '',
        '- **Fields**: `VERSION_SEQ*`, version / duplicate ranks, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION` are '
        'marked *omit* in expressions and *do not map* in links.',
        '- **Steps and mapplets** listed below are not built; each spec says how to link around them.', '')
    if retired_mapplets:
        doc.table(['Mapplet (not built)', 'Why'],
                  [[f'[`{n}`](mapplets/{n}.md)', RETIRED_MAPPLETS[n]] for n in retired_mapplets])
    if retired_steps:
        doc.table(['Mapping / mapplet', 'Step', 'IDQ type', 'Reason'],
                  [[f'[`{r[0]}`]({"mappings" if r[0] in mappings else "mapplets"}/{r[0]}.md)', f'`{r[1]}`', r[2], r[3]]
                   for r in retired_steps])
    if not retired_mapplets and not retired_steps:
        doc('No whole steps are retired in this workflow; only the timeline fields are omitted.', '')
    if filtered:
        doc('## Filtered data', '',
            'Which steps can keep a source row out of each `C_S_*` table, and where the diverted rows go instead. '
            'Each mapping spec has a *Filtered data* section with the conditions, the origin of every field they test '
            'and what happens to the rows that fail.', '')
        rows = []
        for n in mappings:
            for table, steps_, diverted in filtered.get(n) or [(None, [], [])]:
                rows.append([f'[`{n}`](mappings/{n}.md#filtered-data)', f'`{table}`' if table else '(no `C_S_*` target)',
                             ', '.join(f'`{x}`' for x in steps_) or ('none' if table else ''),
                             ', '.join(f'`{x}`' for x in diverted)])
        doc.table(['Mapping', '`C_S_*` table', 'Steps that can keep a row out', 'Failed rows diverted to'], rows)
    procs = [n for n in mappings if os.path.exists(os.path.join(ORACLE_DIR, wfm['name'], f'sp_ors_main_{n}.sql'))]
    if procs:
        doc('## Oracle stored procedures', '',
            'Each mapping also has a drop-in Oracle replacement under '
            f'[idq-to-oracle/{wfm["name"]}](../../idq-to-oracle/{wfm["name"]}/) (conventions, install order and the '
            'shared `fn_dq_*` / helper objects: [idq-to-oracle/README.md](../../idq-to-oracle/README.md)). Run them '
            'in taskflow order (paths of a *Parallel Paths* step may run in parallel sessions); '
            f'[run_{wfm["name"]}.sql](../../idq-to-oracle/{wfm["name"]}/run_{wfm["name"]}.sql) runs them one after '
            'another. Each mapping spec has an *Oracle stored procedure* section.', '')
        doc.table(['Mapping', 'Procedure'],
                  [[f'[`{n}`](mappings/{n}.md#oracle-stored-procedure)',
                    f'[`sp_ors_main_{n}`](../../idq-to-oracle/{wfm["name"]}/sp_ors_main_{n}.sql)'] for n in procs])
    doc('## Translation rules applied', '')
    doc.table(['IDQ', 'CDI', 'Where'], [
        ['`$<Param>` (user parameter)', '`$$<Param>` input parameter', 'expressions, conditions, SQL'],
        ['`$sys.MappingName`', '`$$MappingName` input parameter, set per mapping task in the parameter file', 'expressions'],
        ['`$sys.MappingRunStartTime`', '`SESSSTARTTIME`', 'expressions'],
        ['Update Strategy (`DD_DELETE`)', 'Target operation *Data Driven* / *Delete*', 'targets'],
        ['Inclusive gateways (split + join)', '*Parallel Paths* step', 'taskflow'],
        ['Command task', 'Taskflow *Command Task* on the Secure Agent', 'taskflow'],
        ['Data types', 'string/decimal/date-time/integer/double (same precision and scale)', 'all fields'],
        ['MDM timeline fields, steps and mapplets', 'not ported (see the section above)', 'all'],
    ])
    doc('Every other function used (`IIF`, `DECODE`, `REG_MATCH`, `REPLACESTR`, `LPAD`, `MD5`, `IN`, `IS_NUMBER`, '
        '`SYSTIMESTAMP`, ...) exists in CDI with the same signature, so expressions are carried over as is.', '')
    doc('## Open items to confirm in the target org', '',
        '- **Snowflake_PEI**: the IDQ ODBC DSN becomes a Snowflake Data Cloud connection; check the lookup table '
        '`RDM.REF_PHN_AREA_CD` resolves (database/schema in the connection).',
        '- **Reference data**: dictionary rows are not in the export; load them from the IDQ reference data '
        'warehouse (see [cdq.md](cdq.md)).',
        '- **Address verification**: the Verifier asset needs the US reference data licensed and installed for the '
        'org; output fields and mailability score must be compared on a sample before go-live.',
        '- **Indicator file**: the command task path assumes the Secure Agent host mounts '
        '`/opt/apps/informatica/SrcFiles/Indicators`.',
        '- **DQ transformations inside mapplets**: the address, name and rule mapplets call Cleanse / Labeler / '
        'Verifier transformations; create the CDQ assets first so the mapplets validate.',
        f'- **Project / folder names** (`{project}` / `{folder}`) are placeholders: rename freely, then update the '
        f'section headers in the parameter file.', '')
    return doc.text()


def main(path, out):
    m = Model(path)
    wfm = workflow(m)
    tf = 'tf_' + wfm['name'][3:] if wfm['name'].startswith('wf_') else 'tf_' + wfm['name']
    src = re.sub(r'^wf_([A-Za-z0-9]+)_.*$', r'\1', wfm['name'])
    project, folder = 'HHS_MDM_Stage', src
    os.makedirs(os.path.join(out, 'mappings'), exist_ok=True)
    os.makedirs(os.path.join(out, 'mapplets'), exist_ok=True)

    mapping_order = []
    tf_text, steps = taskflow_doc(wfm, tf)
    for kind, val in steps:
        for n in ([b for chain in val for b in chain] if kind == 'parallel' else [val] if kind == 'data' else []):
            t = next(t for t in wfm['tasks'].values() if t['name'] == n)
            mapping_order.append(t['mapping'])
    mapping_set = set(mapping_order)
    m.writers = table_writers(m, mapping_set)

    counts, mapplet_deps, retired_steps, filtered = [], {}, [], {}
    for mp in m.mappings:
        name = mp.get('name')
        kind = 'mapping' if name in mapping_set else 'mapplet'
        text, used, c, r, fsum = build_mapping(m, mp, kind, wfm['name'])
        if kind == 'mapping':
            filtered[name] = fsum
        if kind == 'mapplet' and name not in RETIRED_MAPPLETS:
            mapplet_deps[name] = used
        counts.append(c)
        if name not in RETIRED_MAPPLETS:
            retired_steps += r
        with open(os.path.join(out, 'mappings' if kind == 'mapping' else 'mapplets', name + '.md'), 'w',
                  encoding='utf-8', newline='\n') as fh:
            fh.write(text)

    mapplet_order, done = [], set()

    def visit(n):
        if n in done:
            return
        done.add(n)
        for d in sorted(mapplet_deps.get(n, ())):
            visit(d)
        mapplet_order.append(n)
    for n in sorted(mapplet_deps):
        visit(n)

    retired_mapplets = sorted(n.get('name') for n in m.mappings if n.get('name') in RETIRED_MAPPLETS)
    files = {
        'taskflow.md': tf_text,
        f'{tf}.param': param_file(m, wfm, tf, project, folder),
        'cdq.md': cdq_doc(m, mapping_order, mapplet_order),
        'README.md': readme(m, wfm, tf, mapping_order, mapplet_order, counts, steps, project, folder,
                            retired_steps, retired_mapplets, filtered),
    }
    for n, text in files.items():
        with open(os.path.join(out, n), 'w', encoding='utf-8', newline='\n') as fh:
            fh.write(text)
    print(f'{len(mapping_order)} mappings, {len(mapplet_order)} mapplets -> {out}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

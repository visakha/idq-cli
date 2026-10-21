"""Convert an IDQ workflow XML export into PowerCenter repository XML that IDMC can import.

Usage: python -I idq_to_pc.py <wf.xml> <out_dir> [--folder NAME]

IDMC Cloud Data Integration converts PowerCenter exports (POWERMART XML) into CDI mappings, mapplets, mapping tasks and
taskflows; the IDQ (Model Repository) export itself cannot be uploaded. This script rewrites the IDQ objects as one
PowerCenter folder export.

Writes, under <out_dir>:
  <workflow>.XML            the whole folder: sources, targets, mapplets, mappings, sessions and the workflow
  mapplets/<name>.XML       one stand-alone export per mapplet (for a single "Mapplet - PowerCenter" upload)
  <workflow>.param          PowerCenter parameter file with the IDQ parameter defaults, one section per session
  conversion_report.md      every non 1:1 translation (DQ transformations, renamed ports, omitted fields)

Translation rules:
  * IDQ relational data objects become Source / Target definitions; each IDQ source becomes a Source Qualifier with
    the SQL override / filter carried over.
  * Expression, Filter, Router, Lookup, Union, Update Strategy map one to one. IDQ $Param -> $$Param,
    $sys.MappingName -> $PMMappingName, $sys.MappingRunStartTime -> SESSSTARTTIME.
  * PowerCenter mapplets cannot contain mapplets: a nested mapplet is inlined, its Input / Output become pass-through
    Expressions named <instance>_input / <instance>_output.
  * IDQ data quality transformations are rebuilt as Expressions (Case Converter, Token Standardizer, Labeler) or as a
    pass-through placeholder (Address Validator); conversion_report.md lists each one.
  * Stale MDM timeline fields (VERSION_SEQ, ranks, PERIOD_REFERENCE_TIME, TIMELINE_ACTION) are not ported.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict, OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from idmc_spec import (FILTER_INTRO, IMX, Model, STALE_COLUMNS, dec, fields_of, local, mapping_filtered,  # noqa: E402
                       mapping_params, own_description, short, table_writers, topo, workflow)

CREATION_DATE = '10/21/2026 00:00:00'
PLATFORM = 'Platform.typesystem%2F'
DEFAULT_ERROR = "ERROR('transformation error')"
CHAR_SET_SEEDS = {'EnglishAlphabet': ('A-Za-z', 'X'), 'Digits': ('0-9', '9')}
FIELD_TYPES = ('ExpressionField', 'FilterField', 'RouterField', 'UnionField', 'UpdateStrategyField', 'LookupField',
               'CaseConverterField', 'TokenStandardiserField', 'LabelerField', 'AvField', 'MappletInputField',
               'MappletOutputField', 'MappletField')
# Address Validator placeholder: output AddressDoctor field -> input AddressDoctor field it echoes
AV_ECHO = {
    'OUT#DeliveryAddressLine#1': 'DeliveryAddressLine#1',
    'OUT#DeliveryAddressLine#2': 'DeliveryAddressLine#2',
    'OUT#Locality#COMPLETE#1': 'Locality#COMPLETE#1',
    'OUT#PostalCode#FORMATTED#1': 'PostalCode#FORMATTED#1',
    'OUT#Province#COUNTRY_STANDARD#1': 'Province#COUNTRY_STANDARD#1',
}


# ---------------------------------------------------------------------------------------------------------- helpers

def idq_type(e):
    """(PowerCenter transformation datatype, precision, scale) of an IDQ field or structural feature."""
    t = e.get('type') or ''
    t = dec(t.split(PLATFORM)[-1]) if PLATFORM in t else 'string'
    p, s = e.get('precision'), e.get('scale')
    if t == 'date/time':
        return 'date/time', '29', '9'
    if t == 'integer':
        return 'integer', '10', '0'
    if t == 'bigint':
        return 'bigint', '19', '0'
    if t == 'double':
        return 'double', '15', '0'
    if t == 'decimal':
        return 'decimal', p or '28', s or '0'
    if t == 'binary':
        return 'binary', p or '255', '0'
    return 'string', p or '255', '0'


def db_type(col, odbc):
    """(datatype, precision, scale) of a physical column for a Source / Target definition."""
    t = dec((col.get('odbcType') if odbc else col.get('type')) or '').split('typesystem/')[-1]
    p, s = col.get('precision') or col.get('odbcPrecision') or '0', col.get('scale') or col.get('odbcScale') or '0'
    if odbc:
        p = col.get('odbcPrecision') or p
        s = col.get('odbcScale') or s
    if t in ('date',) and not odbc:
        return 'date', '19', '0'
    if t == 'timestamp':
        return 'timestamp', '29', s if s != '0' else '9'
    if t == 'number':
        return 'number', p if p != '0' else '15', s
    if t == 'varchar' and not odbc:
        return 'varchar2', p, s
    return t, p, s


def pc_lit(s):
    """PowerCenter string literal (CHR() for quotes and control characters)."""
    parts, buf = [], ''
    for ch in s:
        if ch == "'" or ord(ch) < 32:
            if buf:
                parts.append(f"'{buf}'")
                buf = ''
            parts.append(f'CHR({ord(ch)})')
        else:
            buf += ch
    if buf or not parts:
        parts.append(f"'{buf}'")
    return ' || '.join(parts)


def re_escape_class(chars):
    return ''.join('\\' + c if c in '\\]^-[' else c for c in chars)


def to_pc(expr, params):
    """Translate an IDQ expression / SQL text to PowerCenter syntax."""
    if not expr:
        return expr
    out = expr.replace('$sys.MappingRunStartTime', 'SESSSTARTTIME').replace('$sys.MappingName', '$PMMappingName')
    for p in sorted(params, key=len, reverse=True):
        out = re.sub(r'(?<!\$)\$' + re.escape(p) + r'\b', '$$' + p, out)
    return out.replace('\r\n', '\n').replace('\r', '\n')


def search_strings(raw):
    """Split a token standardizer searchStrings attribute: items are separated by raw spaces, '+' is an encoded space."""
    return [dec(x) for x in (raw or '').split(' ') if x != '']


class Port:
    def __init__(self, name, dtype, prec, scale, porttype, expr=None, default='', group=None, ref=None, extra=None):
        self.name, self.dtype, self.prec, self.scale, self.porttype = name, dtype, prec, scale, porttype
        self.expr, self.default, self.group, self.ref, self.extra = expr, default, group, ref, extra or {}


class Tx:
    """A PowerCenter transformation (non-reusable, inside a mapping or mapplet)."""

    def __init__(self, name, pctype, description=''):
        self.name, self.type, self.description = name, pctype, description
        self.ports, self.attrs, self.groups, self.deps, self.extra = [], [], [], [], {}
        self.used = set()

    def unique(self, name, prefix='o_'):
        n, k = name, 1
        if n.upper() in self.used:
            n = prefix + name
        while n.upper() in self.used:
            k += 1
            n = f'{prefix}{name}_{k}'
        self.used.add(n.upper())
        return n

    def add(self, port):
        self.ports.append(port)
        return port


class Container:
    def __init__(self, name, kind, description=''):
        self.name, self.kind, self.description = name, kind, description
        self.txs = OrderedDict()           # name -> Tx (non-reusable transformations, incl. SQs)
        self.instances = []                # dicts for INSTANCE elements
        self.connectors = []               # (from_inst, from_field, to_inst, to_field)
        self.params = []
        self.sources, self.targets = [], []  # session info
        self.mapplets = []                 # mapplet names used (top level)
        self.update_targets = set()
        self.inst_type = {}                # instance name -> PC instance type (for CONNECTOR)
        self.inst_names = set()
        self.load_order = []

    def unique_inst(self, name):
        n, k = name, 1
        while n.upper() in self.inst_names:
            k += 1
            n = f'{name}_{k}'
        self.inst_names.add(n.upper())
        return n


# ------------------------------------------------------------------------------------------------------- converter

class Converter:
    def __init__(self, path, folder):
        self.m = Model(path)
        self.folder = folder
        self.sources = OrderedDict()   # (dbd, name) -> source element info
        self.targets = OrderedDict()   # name -> target info
        self.report = defaultdict(list)
        self.mapplet_defs = OrderedDict()  # name -> Container
        self.mapping_defs = OrderedDict()
        self.ref_tables = {e.get(IMX + 'id'): e for e in self.m.root.iter() if short(e) == 'ReferenceTable'}
        self.char_sets = {e.get(IMX + 'id'): e for e in self.m.root.iter() if short(e) == 'CharacterSet'}
        self.token_sets = {e.get(IMX + 'id'): e for e in self.m.root.iter() if e.get('tokenRegExp')}
        self.by_name = {mp.get('name'): mp for mp in self.m.mappings}

    def note(self, container, text):
        self.report[container].append(text)

    # -- physical tables -------------------------------------------------------------------------------------------

    def table(self, ref):
        t = self.m.tables.get(ref)
        if t is None:
            raise SystemExit(f'table {ref} not in export')
        return t

    def table_conn(self, t):
        return t.get('connectionName') or dec((t.get('connection') or '').replace('stringIdentity:', ''))

    def is_odbc(self, t):
        return 'ODBC' in (t.get('connectionType') or '')

    def pk_columns(self, t):
        cols = set()
        for k in t.iter():
            if short(k) == 'PrimaryKey':
                cols |= set((k.get('columns') or '').split())
        return cols

    def columns(self, t):
        return [c for c in t.iter() if short(c) == 'Column']

    def register_source(self, t):
        key = (self.table_conn(t), t.get('physicalName') or t.get('name'))
        if key not in self.sources:
            self.sources[key] = t
        return key

    def register_target(self, t):
        name = t.get('physicalName') or t.get('name')
        if name in self.targets and self.targets[name] is not t:
            prev = self.targets[name]
            if [c.get('name') for c in self.columns(prev)] != [c.get('name') for c in self.columns(t)]:
                self.note('(folder)', f'Target `{name}` is defined twice with different columns; the first definition '
                                      f'is used.')
            return name
        self.targets.setdefault(name, t)
        return name

    # -- containers ------------------------------------------------------------------------------------------------

    def build(self, mp, kind, prefix='', into=None):
        """Convert one IDQ mapping / mapplet. With `into`, inline the mapplet into that container (name prefix) and
        return (input_tx_name, output_tx_name, field id -> (instance, port) of its Input / Output)."""
        m = self.m
        name = mp.get('name')
        c = into or Container(name, kind, own_description(mp) or '')
        params = [p['name'] for p in mapping_params(m, mp)]
        if into is None:
            c.params = mapping_params(m, mp)
        insts = [i for i in m.instances if m.container(i) is mp]
        edges = set()
        for inst in insts:
            for p in inst.iter():
                if short(p) in ('TransformationFieldPort', 'NestedPort') and p.get('fromPort'):
                    src = m.ports.get(p.get('fromPort'))
                    if src:
                        edges.add((src[0], inst))
        order = topo(insts, edges)
        portref = {}       # IDQ port id -> (pc instance, pc port)
        dropped = set()    # IDQ port ids whose fields are not ported
        iface = {}         # mapplet Input / Output field id -> (pc instance, pc port) for inlining

        for inst in order:
            tx = m.tx(inst)
            t = short(tx)
            iname = prefix + inst.get('name')
            fmap = {}      # IDQ field / feature id -> pc port name
            drop = set()   # IDQ field ids not ported
            conv = getattr(self, 'tx_' + t, None)
            if conv is None:
                raise SystemExit(f'{name}: no converter for {t} ({inst.get("name")})')
            res = conv(c, mp, inst, tx, iname, params, fmap, drop, prefix=prefix, into=into, kind=kind)
            pc_inst = res if isinstance(res, str) else iname
            for p in inst.iter():
                st = short(p)
                if st == 'TransformationFieldPort':
                    fid = p.get('transformationField')
                elif st == 'NestedPort':
                    fid = p.get('structuralFeature')
                else:
                    continue
                pid = p.get(IMX + 'id')
                if fid in drop:
                    dropped.add(pid)
                elif fid in fmap:
                    v = fmap[fid]
                    portref[pid] = v if isinstance(v, tuple) else (pc_inst, v)
            if t == 'MappletInputTx' or t == 'MappletOutputTx':
                for fid, v in fmap.items():
                    iface[fid] = v if isinstance(v, tuple) else (pc_inst, v)

        # links
        for inst in order:
            for p in inst.iter():
                if short(p) not in ('TransformationFieldPort', 'NestedPort') or not p.get('fromPort'):
                    continue
                to, frm = p.get(IMX + 'id'), p.get('fromPort')
                if to in dropped or frm in dropped:
                    continue
                if to not in portref or frm not in portref:
                    src = m.label(frm)[1]
                    dst = m.label(to)[1]
                    if STALE_COLUMNS.match(dst.split('.')[-1]) or STALE_COLUMNS.match(src.split('.')[-1]):
                        continue
                    raise SystemExit(f'{name}: unresolved link {src} -> {inst.get("name")}.{dst}')
                a, b = portref[frm], portref[to]
                tgt_col = b[1]
                if c.inst_type.get(b[0]) == 'Target Definition' and STALE_COLUMNS.match(tgt_col):
                    self.note(c.name, f'Link `{a[0]}.{a[1]}` -> `{b[0]}.{tgt_col}` not ported (stale MDM timeline).')
                    continue
                c.connectors.append((a[0], a[1], b[0], b[1]))
        for k in mp.iter():
            if short(k) == 'OneAfterAnotherConstraint' and into is None:
                a, b = m.by_id.get(k.get('primaryInstance')), m.by_id.get(k.get('secondaryInstance'))
                c.load_order.append((a.get('name'), b.get('name')))
        if into is not None:
            return iface
        c.io_names = {fid: v[1] for fid, v in iface.items()}
        return c

    # -- transformation converters -----------------------------------------------------------------------------------

    def ports_simple(self, tx_obj, tx, fmap, drop, refs_text, ftype_names=FIELD_TYPES):
        """Fields of an IDQ transformation whose fields keep their names (Expression, Filter, Update Strategy)."""
        fields = [f for f in fields_of(tx) if short(f) in ftype_names]
        stale = {f.get(IMX + 'id') for f in fields if STALE_COLUMNS.match(f.get('name') or '')}
        # keep a stale field when a live field or condition still references it
        changed = True
        while changed:
            changed = False
            live_text = refs_text + '\n' + '\n'.join(dec(f.get('expression') or '') for f in fields
                                                    if f.get(IMX + 'id') not in stale)
            for f in fields:
                if f.get(IMX + 'id') in stale and re.search(r'\b' + re.escape(f.get('name')) + r'\b', live_text, re.I):
                    stale.discard(f.get(IMX + 'id'))
                    changed = True
        drop |= stale
        return [f for f in fields if f.get(IMX + 'id') not in stale]

    def default_of(self, f):
        for d in f:
            if local(d.tag) == 'defaultValue':
                return dec(d.get('valueLiteral')) or ''
        return ''

    def porttype(self, f):
        if f.get('variable') == 'true':
            return 'LOCAL VARIABLE'
        i, o = f.get('input') == 'true', f.get('output') == 'true'
        return 'INPUT/OUTPUT' if i and o else ('INPUT' if i else 'OUTPUT')

    def add_inst(self, c, name, pctype, tx_obj=None, **attrs):
        c.inst_type[name] = pctype
        c.instances.append(dict(NAME=name, TRANSFORMATION_TYPE=pctype, **attrs))
        if tx_obj is not None:
            c.txs[tx_obj.name] = tx_obj

    def tx_ExpressionTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Expression', own_description(tx) or '')
        fields = self.ports_simple(e, tx, fmap, drop, '')
        for f in fields:
            dt, p, s = idq_type(f)
            pt = self.porttype(f)
            n = e.unique(f.get('name'))
            expr = f.get('name') if pt == 'INPUT/OUTPUT' else to_pc(dec(f.get('expression')), params)
            if pt == 'INPUT':
                expr = ''
            dflt = self.default_of(f)
            e.add(Port(n, dt, p, s, pt, expr or '', dflt if pt != 'INPUT' else ''))
            fmap[f.get(IMX + 'id')] = n
        for f in fields_of(tx):
            if f.get(IMX + 'id') in drop:
                self.note(c.name, f'`{iname}.{f.get("name")}` not ported (stale MDM timeline).')
        e.attrs = [('Tracing Level', 'Normal')]
        self.add_inst(c, iname, 'Expression', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')

    def tx_FilterTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        cond = to_pc(dec(tx.get('filterCondition')), params)
        e = Tx(iname, 'Filter', own_description(tx) or '')
        for f in self.ports_simple(e, tx, fmap, drop, cond or ''):
            dt, p, s = idq_type(f)
            n = e.unique(f.get('name'))
            e.add(Port(n, dt, p, s, 'INPUT/OUTPUT'))
            fmap[f.get(IMX + 'id')] = n
        e.attrs = [('Filter Condition', cond or 'TRUE'), ('Tracing Level', 'Normal')]
        self.add_inst(c, iname, 'Filter', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')

    def tx_UpdateStrategyTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Update Strategy', own_description(tx) or '')
        for f in self.ports_simple(e, tx, fmap, drop, ''):
            dt, p, s = idq_type(f)
            n = e.unique(f.get('name'))
            e.add(Port(n, dt, p, s, 'INPUT/OUTPUT'))
            fmap[f.get(IMX + 'id')] = n
        e.attrs = [('Update Strategy Expression', to_pc(dec(tx.get('updateStrategy')), params)),
                   ('Forward Rejected Rows', 'YES' if tx.get('rejectForwarding') == 'true' else 'NO'),
                   ('Tracing Level', 'Normal')]
        c.has_update_strategy = iname
        self.add_inst(c, iname, 'Update Strategy', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')

    def tx_RouterTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Router', own_description(tx) or '')
        groups = [g for g in tx.iter() if short(g) == 'RouterDataInterface']
        conds = '\n'.join(dec(g.get('dataCondition') or '') for g in groups)
        in_names = {}
        order, k = 1, 0
        for g in groups:
            fields = [f for f in g.iter() if short(f) == 'RouterField']
            live = []
            for f in fields:
                if STALE_COLUMNS.match(f.get('name')) and not re.search(r'\b' + re.escape(f.get('name')) + r'\b', conds):
                    drop.add(f.get(IMX + 'id'))
                else:
                    live.append(f)
            if g.get('input') == 'true':
                e.groups.append(dict(NAME='INPUT', ORDER=str(order), TYPE='INPUT', DESCRIPTION=''))
                for f in live:
                    dt, p, s = idq_type(f)
                    n = e.unique(f.get('name'))
                    in_names[f.get('name').upper()] = n
                    e.add(Port(n, dt, p, s, 'INPUT', group='INPUT'))
                    fmap[f.get(IMX + 'id')] = n
            else:
                k += 1
                gname = g.get('name')
                cond = g.get('dataCondition')
                gd = dict(NAME=gname, ORDER=str(order), TYPE='OUTPUT' if cond else 'OUTPUT/DEFAULT', DESCRIPTION='')
                if cond:
                    gd['EXPRESSION'] = to_pc(dec(cond), params)
                e.groups.append(gd)
                for f in live:
                    dt, p, s = idq_type(f)
                    n = e.unique(f'{f.get("name")}{k}', prefix='')
                    e.add(Port(n, dt, p, s, 'OUTPUT', default=self.default_of(f), group=gname,
                               ref=in_names.get(f.get('name').upper())))
                    fmap[f.get(IMX + 'id')] = n
            order += 1
        e.attrs = [('Tracing Level', 'Normal')]
        self.add_inst(c, iname, 'Router', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')

    def tx_UnionTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Custom Transformation', own_description(tx) or '')
        e.extra['TEMPLATENAME'] = 'Union Transformation'
        groups = [g for g in tx.iter() if short(g) == 'UnionDataInterface']
        outs = [g for g in groups if g.get('output') == 'true']
        ins = [g for g in groups if g.get('input') == 'true']
        order = 1
        out_by_name = {}
        for g in outs:
            e.groups.append(dict(NAME='OUTPUT', ORDER=str(order), TYPE='OUTPUT', DESCRIPTION=''))
            order += 1
            for f in g.iter():
                if short(f) != 'UnionField':
                    continue
                if STALE_COLUMNS.match(f.get('name')):
                    drop.add(f.get(IMX + 'id'))
                    continue
                dt, p, s = idq_type(f)
                n = e.unique(f.get('name'))
                out_by_name[f.get('name').upper()] = n
                e.add(Port(n, dt, p, s, 'OUTPUT', group='OUTPUT'))
                fmap[f.get(IMX + 'id')] = n
        for k, g in enumerate(ins, 1):
            gname = g.get('name')
            e.groups.append(dict(NAME=gname, ORDER=str(order), TYPE='INPUT', DESCRIPTION=''))
            order += 1
            for f in g.iter():
                if short(f) != 'UnionField':
                    continue
                if STALE_COLUMNS.match(f.get('name')):
                    drop.add(f.get(IMX + 'id'))
                    continue
                dt, p, s = idq_type(f)
                n = e.unique(f'{f.get("name")}{k}', prefix='')
                e.add(Port(n, dt, p, s, 'INPUT', group=gname))
                fmap[f.get(IMX + 'id')] = n
                if f.get('name').upper() in out_by_name:
                    e.deps.append((n, out_by_name[f.get('name').upper()]))
        e.attrs = [('Language', ''), ('Module Identifier', 'pmuniontrans'), ('Function Identifier Prefix', 'pmunion'),
                   ('Runtime Location', ''), ('Tracing Level', 'Normal'), ('Is Partitionable', 'No'),
                   ('Inputs Must Block', 'NO'), ('Is Active', 'YES'), ('Update Strategy Transformation', 'NO'),
                   ('Transformation Scope', 'Row'), ('Generate Transaction', 'NO'),
                   ('Output Is Repeatable', 'Never'), ('Requires Single Thread Per Partition', 'NO'),
                   ('Output Is Deterministic', 'NO')]
        self.add_inst(c, iname, 'Custom Transformation', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION',
                      REUSABLE='NO')

    def dso_of(self, tx):
        return self.m.by_id.get(tx.get('dso'))

    def complex_features(self, dso):
        return [f for f in dso.iter() if short(f) == 'StructuralFeature']

    def feature_columns(self, dso):
        """structural feature id -> (table element, column element)"""
        recs = {r.get(IMX + 'id'): r.get('record') for r in dso.iter() if short(r) == 'RelationalRecordInstance'}
        cols = {}
        for t in [self.table(r) for r in (dso.get('tableDefinitions') or dso.get('tableDefinition') or '').split()]:
            for col in self.columns(t):
                cols[col.get(IMX + 'id')] = (t, col)
        out = {}
        for rf in dso.iter():
            if short(rf) == 'RelationalField' and rf.get('feature'):
                tc = cols.get(rf.get('column'))
                if tc is None and recs.get(rf.get('recordInstance')):
                    t = self.table(recs[rf.get('recordInstance')])
                    tc = next(((t, cl) for cl in self.columns(t) if cl.get('name') == rf.get('name')), None)
                if tc:
                    out[rf.get('feature')] = tc
        return out

    def stand_in_column(self, tables, f, fcols):
        """A source column to link an SQL-override-only Source Qualifier port from (same name, else same type)."""
        for t in tables:
            for col in self.columns(t):
                if col.get('name').upper() == f.get('name').upper():
                    return t, col
        family = {'string': ('varchar2', 'char', 'nvarchar2', 'varchar', 'nchar'), 'decimal': ('number', 'number(p,s)'),
                  'integer': ('number', 'number(p,s)'), 'double': ('number', 'number(p,s)', 'float'),
                  'date/time': ('date', 'timestamp')}[idq_type(f)[0]]
        for t in tables:
            for col in self.columns(t):
                if db_type(col, self.is_odbc(t))[0] in family:
                    return t, col
        return None

    def tx_SourceTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        dso = self.dso_of(tx)
        refs = (dso.get('tableDefinitions') or '').split()
        tables = [self.table(r) for r in refs]
        fcols = self.feature_columns(dso)
        src_insts = {}
        for t in tables:
            key = self.register_source(t)
            sname = c.unique_inst(key[1])
            src_insts[t.get(IMX + 'id')] = sname
            self.add_inst(c, sname, 'Source Definition', TRANSFORMATION_NAME=key[1], TYPE='SOURCE', DBDNAME=key[0])
        sq = Tx(iname, 'Source Qualifier', own_description(tx) or '')
        c.inst_names.add(iname.upper())
        for f in self.complex_features(dso):
            dt, p, s = idq_type(f)
            n = sq.unique(f.get('name'))
            sq.add(Port(n, dt, p, s, 'INPUT/OUTPUT'))
            fmap[f.get(IMX + 'id')] = n
            tc = fcols.get(f.get(IMX + 'id')) or self.stand_in_column(tables, f, fcols)
            if tc is None:
                raise SystemExit(f'{c.name}: source field {f.get("name")} has no column')
            if f.get(IMX + 'id') not in fcols and tc[1].get('name').upper() != f.get('name').upper():
                self.note(c.name, f'`{iname}.{n}` is computed by the SQL override; in PowerCenter it is linked from '
                                  f'the stand-in column `{tc[0].get("name")}.{tc[1].get("name")}` (values come from the '
                                  f'override, by position).')
            c.connectors.append((src_insts[tc[0].get(IMX + 'id')], tc[1].get('name'), iname, n))
        sql = to_pc(dec(dso.get('sqlQuery')), params) or ''
        flt = to_pc(dec(dso.get('filterCondition')), params) or ''
        if sql:
            self.note(c.name, f'`{iname}`: SQL override carried over (Source Qualifier *Sql Query*).')
        if sql and flt:
            self.note(c.name, f'`{iname}`: the IDQ source also has the filter `{flt}`. IDQ and PowerCenter both ignore '
                              f'the filter when an SQL override is set; it is carried over unchanged (looks like a '
                              f'leftover test filter; remove it in the target org).')
        sq.attrs = [('Sql Query', sql), ('User Defined Join', ''), ('Source Filter', flt),
                    ('Number Of Sorted Ports', '0'), ('Tracing Level', 'Normal'),
                    ('Select Distinct', 'NO'), ('Is Partitionable', 'NO'), ('Pre SQL', ''), ('Post SQL', ''),
                    ('Output is deterministic', 'NO'), ('Output is repeatable', 'Never')]
        if len(tables) > 1 and not sql:
            self.note(c.name, f'`{iname}` reads {len(tables)} tables without an SQL override: check the join in the '
                              f'Source Qualifier.')
        c.inst_type[iname] = 'Source Qualifier'
        c.txs[iname] = sq
        c.instances.append(dict(NAME=iname, TRANSFORMATION_TYPE='Source Qualifier', TRANSFORMATION_NAME=iname,
                                TYPE='TRANSFORMATION', REUSABLE='NO',
                                _assoc=[src_insts[t.get(IMX + 'id')] for t in tables]))
        conn = self.table_conn(tables[0])
        c.sources.append(dict(sq=iname, defs=[src_insts[t.get(IMX + 'id')] for t in tables], conn=conn,
                              odbc=self.is_odbc(tables[0])))

    def tx_TargetTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        dso = self.dso_of(tx)
        t = self.table(dso.get('tableDefinition'))
        tname = self.register_target(t)
        c.unique_inst(iname)
        fcols = self.feature_columns(dso)
        for f in self.complex_features(dso):
            tc = fcols.get(f.get(IMX + 'id'))
            fmap[f.get(IMX + 'id')] = tc[1].get('name') if tc else f.get('name')
        self.add_inst(c, iname, 'Target Definition', TRANSFORMATION_NAME=tname, TYPE='TARGET')
        h = self.m.handlers.get(inst.get(IMX + 'id'))
        c.targets.append(dict(inst=iname, conn=self.table_conn(t), odbc=self.is_odbc(t),
                              truncate=dso.get('truncateTargetTable') == 'true',
                              reject=(h.get('rejectFile') if h is not None and h.get('rejectFile') else
                                      iname.lower() + '1.bad'),
                              bulk=dso.get('loadType') not in (None, 'Normal')))

    def lookup_tx(self, c, iname, dso, params, description, cond, multi, cached, prefix_cache, input_fields,
                  extra_ports=(), sql=None, return_port=None):
        e = Tx(iname, 'Lookup Procedure', description)
        for n, dt, p, s, pt in input_fields:
            e.add(Port(e.unique(n), dt, p, s, pt))
        tables = [self.table(r) for r in (dso.get('tableDefinitions') or '').split()] if dso is not None else []
        t = tables[0] if tables else None
        names = {}
        for f in extra_ports:
            dt, p, s = idq_type(f)
            n = e.unique(f.get('name'))
            names[f.get(IMX + 'id')] = n
            e.add(Port(n, dt, p, s, 'LOOKUP/RETURN/OUTPUT' if f.get(IMX + 'id') == return_port else 'LOOKUP/OUTPUT'))
        tname = (t.get('physicalName') or t.get('name')) if t is not None else ''
        owner = t.get('ownerName') if t is not None else None
        if sql is None:
            sql = to_pc(dec(dso.get('sqlQuery')), params) if dso is not None else ''
            if not sql and owner:
                cols = ', '.join(f'{f.get("name")} AS {names[f.get(IMX + "id")]}' for f in extra_ports)
                sql = f'SELECT {cols} FROM {owner}.{tname}'
        flt = to_pc(dec(dso.get('filterCondition')), params) if dso is not None else ''
        conn = self.table_conn(t) if t is not None else ''
        e.attrs = [('Lookup Sql Override', sql or ''), ('Lookup table name', tname),
                   ('Lookup Source Filter', flt or ''), ('Lookup caching enabled', 'YES' if cached else 'NO'),
                   ('Lookup policy on multiple match', multi), ('Lookup condition', cond),
                   ('Connection Information', conn), ('Source Type', 'Database'), ('Recache if Stale', 'NO'),
                   ('Tracing Level', 'Normal'), ('Lookup cache directory name', '$PMCacheDir/'),
                   ('Lookup cache initialize', 'NO'), ('Lookup cache persistent', 'NO'),
                   ('Lookup Data Cache Size', 'Auto'), ('Lookup Index Cache Size', 'Auto'),
                   ('Dynamic Lookup Cache', 'NO'), ('Synchronize Dynamic Cache', 'NO'),
                   ('Output Old Value On Update', 'NO'), ('Update Dynamic Cache Condition', 'TRUE'),
                   ('Cache File Name Prefix', prefix_cache or ''), ('Re-cache from lookup source', 'NO'),
                   ('Insert Else Update', 'NO'), ('Update Else Insert', 'NO'), ('Datetime Format', ''),
                   ('Thousand Separator', 'None'), ('Decimal Separator', '.'),
                   ('Case Sensitive String Comparison', 'YES'), ('Null ordering', 'Null Is Highest Value'),
                   ('Sorted Input', 'NO'), ('Lookup source is static', 'NO'), ('Pre-build lookup cache', 'Auto'),
                   ('Subsecond Precision', '6')]
        return e, names

    def tx_LookupTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        dso = self.dso_of(tx)
        h = self.m.handlers.get(inst.get(IMX + 'id'))
        linked_out = set()
        for p in inst.iter():
            if short(p) == 'TransformationFieldPort' and p.get('toPorts'):
                linked_out.add(p.get('transformationField'))
        inputs, in_ids = [], []
        for f in tx.iter():
            if short(f) == 'LookupField' and f.get('input') == 'true':
                dt, p, s = idq_type(f)
                pt = 'INPUT/OUTPUT' if f.get(IMX + 'id') in linked_out else 'INPUT'
                inputs.append((f.get('name'), dt, p, s, pt))
                in_ids.append(f.get(IMX + 'id'))
        multi = {'returnAny': 'Use Any Value', 'returnFirst': 'Use First Value', 'returnLast': 'Use Last Value',
                 'reportError': 'Report Error'}.get(tx.get('multipleMatchHandling'), 'Report Error')
        cond = to_pc(dec(tx.get('lookupCondition')), params)
        connected_return = any(p.get('structuralFeature') == tx.get('returnPort') and p.get('toPorts')
                               for p in inst.iter() if short(p) == 'NestedPort')
        e, names = self.lookup_tx(c, iname, dso, params, own_description(tx) or '', cond, multi,
                                  h is None or h.get('cached') != 'false',
                                  h.get('cacheFileNamePrefix') if h is not None else '', inputs,
                                  self.complex_features(dso),
                                  return_port=None if connected_return or not tx.get('returnPort') else tx.get('returnPort'))
        for fid, port in zip(in_ids, [p.name for p in e.ports[:len(in_ids)]]):
            fmap[fid] = port
        fmap.update(names)
        self.add_inst(c, iname, 'Lookup Procedure', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')

    def mapplet_io(self, c, tx, iname, fmap, inline, is_input, kind):
        fields = [f for f in fields_of(tx) if short(f) in ('MappletInputField', 'MappletOutputField')]
        if inline or kind == 'mapping':
            e = Tx(iname, 'Expression', 'Inlined mapplet ' + ('input' if is_input else 'output'))
            for f in fields:
                dt, p, s = idq_type(f)
                n = e.unique(f.get('name'))
                e.add(Port(n, dt, p, s, 'INPUT/OUTPUT', n))
                fmap[f.get(IMX + 'id')] = n
            e.attrs = [('Tracing Level', 'Normal')]
            self.add_inst(c, iname, 'Expression', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')
            return
        pctype = 'Input Transformation' if is_input else 'Output Transformation'
        e = Tx(iname, pctype)
        group = tx.get('name')
        if not is_input:
            for p in c.txs.values():
                if p.type == 'Input Transformation':
                    e.used |= {q.name.upper() for q in p.ports}
        for f in fields:
            dt, p, s = idq_type(f)
            n = e.unique(f.get('name'))
            if n != f.get('name'):
                self.note(c.name, f'Mapplet output `{f.get("name")}` renamed `{n}` (PowerCenter mapplet port names must '
                                  f'differ from the input port names).')
            e.add(Port(n, dt, p, s, 'OUTPUT' if is_input else 'INPUT', extra={'MAPPLETGROUP': group}))
            fmap[f.get(IMX + 'id')] = n
        self.add_inst(c, iname, pctype, e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')

    def tx_MappletInputTx(self, c, mp, inst, tx, iname, params, fmap, drop, into=None, kind=None, **kw):
        self.mapplet_io(c, tx, iname, fmap, into is not None, True, kind)

    def tx_MappletOutputTx(self, c, mp, inst, tx, iname, params, fmap, drop, into=None, kind=None, **kw):
        self.mapplet_io(c, tx, iname, fmap, into is not None, False, kind)

    def tx_MappletTx(self, c, mp, inst, tx, iname, params, fmap, drop, into=None, kind=None, **kw):
        child = self.m.by_id.get(tx.get('mapplet'))
        cname = child.get('name')
        if kind == 'mapplet' or into is not None:
            # PowerCenter mapplets cannot contain mapplets: inline the child
            iface = self.build(child, 'mapplet', prefix=iname + '_', into=c)
            for f in tx.iter():
                if short(f) == 'MappletField' and f.get('mappletField') in iface:
                    fmap[f.get(IMX + 'id')] = iface[f.get('mappletField')]
            self.note(c.name, f'Nested mapplet `{inst.get("name")}` ({cname}) inlined with the prefix `{iname}_`.')
            return
        md = self.mapplet(cname)
        for f in tx.iter():
            if short(f) == 'MappletField' and f.get('mappletField') in md.io_names:
                fmap[f.get(IMX + 'id')] = md.io_names[f.get('mappletField')]
        c.inst_names.add(iname.upper())
        if cname not in c.mapplets:
            c.mapplets.append(cname)
        c.inst_type[iname] = 'Mapplet'
        c.instances.append(dict(NAME=iname, TRANSFORMATION_TYPE='Mapplet', TRANSFORMATION_NAME=cname, TYPE='MAPPLET',
                                REUSABLE='YES'))

    def mapplet(self, name):
        if name not in self.mapplet_defs:
            self.mapplet_defs[name] = self.build(self.by_name[name], 'mapplet')
        return self.mapplet_defs[name]

    # -- data quality transformations rebuilt as Expressions -----------------------------------------------------------

    def dq_ports(self, e, tx, fmap, ftype):
        """Input ports first (keep their names), then outputs (renamed o_<name> on collision)."""
        ins = [f for f in tx.iter() if short(f) == ftype and f.get('input') == 'true']
        outs = [f for f in tx.iter() if short(f) == ftype and f.get('output') == 'true']
        names = {}
        for f in ins:
            dt, p, s = idq_type(f)
            n = e.unique(f.get('name'), prefix='i_')
            e.add(Port(n, dt, p, s, 'INPUT'))
            names[f.get(IMX + 'id')] = n
        for f in outs:
            dt, p, s = idq_type(f)
            n = e.unique(f.get('name'))
            names[f.get(IMX + 'id')] = n
        fmap.update(names)
        return ins, outs, names

    def finish_dq(self, c, e, outs, names, exprs, inst_name):
        """Append output ports in IDQ order; outputs without a strategy echo NULL."""
        for f in outs:
            dt, p, s = idq_type(f)
            ex = exprs.get(f.get(IMX + 'id'))
            if ex is None:
                ex = 'NULL'
                self.note(c.name, f'`{inst_name}.{f.get("name")}` has no IDQ strategy: set to NULL.')
            e.add(Port(names[f.get(IMX + 'id')], dt, p, s, 'OUTPUT', ex, DEFAULT_ERROR))
        e.attrs = [('Tracing Level', 'Normal')]
        self.add_inst(c, e.name, 'Expression', e, TRANSFORMATION_NAME=e.name, TYPE='TRANSFORMATION', REUSABLE='NO')

    def strategy_io(self, st):
        ins = [p.get('field') for blk in st if local(blk.tag) == 'inputs' for p in blk if short(p) == 'FieldParameter']
        outs = [p.get('field') for blk in st if local(blk.tag) == 'outputs' for p in blk if short(p) == 'FieldParameter']
        return ins, outs

    def tx_CaseConverterTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Expression', f'IDQ Case Converter {inst.get("name")} rebuilt as an Expression.')
        ins, outs, names = self.dq_ports(e, tx, fmap, 'CaseConverterField')
        exprs = {}
        for st in tx.iter():
            if short(st) != 'CaseConverterTxStrategy':
                continue
            fn = (st.get('conversionType') or dec(st.get('function') or '').split('/')[-1].split('.')[-1]).upper()
            func = {'TITLE': 'INITCAP', 'TOUPPER': 'UPPER', 'UPPER': 'UPPER', 'TOLOWER': 'LOWER', 'LOWER': 'LOWER',
                    'SENTENCE': 'INITCAP'}.get(fn)
            if func is None:
                raise SystemExit(f'{iname}: unknown case conversion {fn}')
            i_ids, o_ids = self.strategy_io(st)
            for i, o in zip(i_ids, o_ids):
                exprs[o] = f'{func}({names[i]})'
            if func == 'INITCAP':
                self.note(c.name, f'`{iname}` ({st.get("name")}): IDQ title case (delimiter: space) &rarr; `INITCAP`, '
                                  f'which also capitalises after punctuation (O\'Brien, Smith-Jones).')
        self.finish_dq(c, e, outs, names, exprs, iname)

    def ref_lookup(self, c, ref_id, params):
        """Unconnected lookup that returns the valid value of an IDQ reference table for any of its values."""
        rt = self.ref_tables[ref_id]
        lname = 'lkp_' + dec(rt.get('name'))
        if lname in c.txs:
            return lname
        dso = next(d for d in rt if short(d) == 'ReadRelationalDataSourceOperation')
        t = self.table(dso.get('tableDefinitions').split()[0])
        feats = self.complex_features(dso)
        fcols = self.feature_columns(dso)
        valid_id = rt.get('validColumn')
        valid = next(fcols[f.get(IMX + 'id')][1].get('name') for f in feats
                     if fcols[f.get(IMX + 'id')][1].get(IMX + 'id') == valid_id)
        cols = [fcols[f.get(IMX + 'id')][1].get('name') for f in feats]
        tname = t.get('physicalName') or t.get('name')
        sql = '\nUNION\n'.join(f'SELECT {valid} AS VALID_VALUE, UPPER({col}) AS MATCH_VALUE FROM {tname} '
                               f'WHERE {col} IS NOT NULL' for col in cols)
        e, _ = self.lookup_tx(c, lname, dso, params, f'Reference table {dec(rt.get("name"))}: any value -> valid value',
                              'MATCH_VALUE = in_VALUE', 'Use Any Value', True, '',
                              [('in_VALUE', 'string', '255', '0', 'INPUT')], sql=sql)
        e.add(Port('VALID_VALUE', 'string', '255', '0', 'LOOKUP/RETURN/OUTPUT'))
        e.add(Port('MATCH_VALUE', 'string', '255', '0', 'LOOKUP'))
        e.used |= {'VALID_VALUE', 'MATCH_VALUE'}
        c.unique_inst(lname)
        self.add_inst(c, lname, 'Lookup Procedure', e, TRANSFORMATION_NAME=lname, TYPE='TRANSFORMATION', REUSABLE='NO')
        self.note(c.name, f'Reference table `{dec(rt.get("name"))}` ({self.table_conn(t)}.{tname}) &rarr; unconnected '
                          f'lookup `{lname}`, whole-value match (IDQ matched token sequences).')
        return lname

    def tx_TokenStandardiserTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Expression', f'IDQ Token Standardizer {inst.get("name")} rebuilt as an Expression.')
        ins, outs, names = self.dq_ports(e, tx, fmap, 'TokenStandardiserField')
        exprs = {}
        for st in tx.iter():
            if short(st) != 'TokenStandardiserStrategy':
                continue
            i_ids, o_ids = self.strategy_io(st)
            src, out = names[i_ids[0]], o_ids[0]
            prec = idq_type(self.m.by_id[out])[1]
            v = src
            steps = []

            def step(expr):
                """Each operation becomes a variable port so the next one references it by name."""
                n = e.unique(f'v_{names[out]}_{len(steps) + 1}', prefix='')
                e.add(Port(n, 'string', prec, '0', 'LOCAL VARIABLE', expr))
                return n
            for op in st.iter():
                ot = short(op)
                if ot == 'UserOp':
                    items = sorted(search_strings(op.get('searchStrings')), key=len, reverse=True)
                    repl = dec(op.get('replacement') or '') if op.get('replace') == 'true' else ''
                    scope = op.get('scope')
                    if not items:
                        continue
                    if scope == 'start':
                        branches = ', '.join(f'SUBSTR({v}, 1, {len(s)}) = {pc_lit(s)}, '
                                             f'{pc_lit(repl)} || SUBSTR({v}, {len(s) + 1})' for s in items)
                        v = step(f'DECODE(TRUE, {branches}, {v})')
                    elif scope == 'end':
                        branches = ', '.join(f'LENGTH({v}) >= {len(s)} AND SUBSTR({v}, -{len(s)}) = {pc_lit(s)}, '
                                             f'SUBSTR({v}, 1, LENGTH({v}) - {len(s)}) || {pc_lit(repl)}'
                                             for s in items)
                        v = step(f'DECODE(TRUE, {branches}, {v})')
                    else:
                        v = step(f'REPLACESTR(1, {v}, {", ".join(pc_lit(s) for s in items)}, {pc_lit(repl)})')
                    steps.append(f'{dec(op.get("name"))} ({scope or "anywhere"})')
                elif ot == 'RtmOp':
                    d = next((x for x in op if short(x) == 'Dictionary'), None)
                    ref = d.get('refTable') if d is not None else None
                    if op.get('replace') == 'true' and ref in self.ref_tables:
                        lk = self.ref_lookup(c, ref, params)
                        v = step(f'IIF(ISNULL(:LKP.{lk}(UPPER(LTRIM(RTRIM({v}))))), {v}, '
                                 f':LKP.{lk}(UPPER(LTRIM(RTRIM({v})))))')
                        steps.append(f'{dec(op.get("name"))} (lookup {lk})')
                    else:
                        rname = dec(d.get('filename') or '') if d is not None else '?'
                        v = step(f"REG_REPLACE({v}, '[^A-Za-z0-9 ]', '')")
                        steps.append(f'{dec(op.get("name"))} (approximated)')
                        self.note(c.name, f'`{iname}` ({st.get("name")}): *{dec(op.get("name"))}* uses reference table '
                                          f'`{rname}`, which is not in the export &rarr; approximated as "remove every '
                                          f'character that is not a letter, digit or space" (`REG_REPLACE`). Replace it '
                                          f'with a lookup once the table is available.')
            if st.get('removeMultipleSpaces') == 'true':
                v = f"REG_REPLACE({v}, ' {{2,}}', ' ')"
            if st.get('trim') == 'true':
                v = f'LTRIM(RTRIM({v}))'
            exprs[out] = v
            self.note(c.name, f'`{iname}` ({st.get("name")}): {", ".join(steps) or "no operations"}'
                              f'{", remove multiple spaces" if st.get("removeMultipleSpaces") == "true" else ""}'
                              f'{", trim" if st.get("trim") == "true" else ""} &rarr; Expression.')
        self.finish_dq(c, e, outs, names, exprs, iname)

    def tx_LabelerTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Expression', f'IDQ Labeler {inst.get("name")} rebuilt as an Expression.')
        ins, outs, names = self.dq_ports(e, tx, fmap, 'LabelerField')
        exprs = {}
        for st in tx.iter():
            if short(st) != 'LabelerTxStrategy':
                continue
            i_ids, o_ids = self.strategy_io(st)
            src = names[i_ids[0]]
            v = src
            for lb in st.iter():
                lt = short(lb)
                if lt == 'CharacterLabel' and lb.get('enabled') != 'false':
                    for ref in (lb.get('characterSets') or '').split():
                        if ref in self.char_sets:
                            cs = self.char_sets[ref]
                            rng = ''.join(re_escape_class(chr(int(r.get('startPosition')))) +
                                          ('-' + re_escape_class(chr(int(r.get('endPosition'))))
                                           if r.get('startPosition') != r.get('endPosition') else '')
                                          for r in cs.iter() if short(r) == 'CharacterRange')
                            label = dec(cs.get('characterSetLabel'))
                        else:
                            seed = ref.split('.')[-1]
                            if seed not in CHAR_SET_SEEDS:
                                raise SystemExit(f'{iname}: unknown character set {seed}')
                            rng, label = CHAR_SET_SEEDS[seed]
                        v = f"REG_REPLACE({v}, '[{rng}]', {pc_lit(label)})"
                    self.note(c.name, f'`{iname}` ({st.get("name")}): character labels &rarr; `REG_REPLACE` per '
                                      f'character set.')
                elif lt == 'TokenLabel' and lb.get('enabled') != 'false':
                    branches = []
                    for it in lb.iter():
                        ts = self.token_sets.get(it.get('tokenSetReference') or '')
                        if ts is not None:
                            branches.append(f'REG_MATCH(LTRIM(RTRIM({src})), {pc_lit(dec(ts.get("tokenRegExp")))}), '
                                            f'{pc_lit(dec(ts.get("tokenLabel")))}')
                    other = dec(lb.get('labelOverrides') or '')
                    other = pc_lit(other) if other and other != '\x01' else src
                    v = f'DECODE(TRUE, {", ".join(branches)}, {other})'
                    self.note(c.name, f'`{iname}` ({st.get("name")}): token labels &rarr; `REG_MATCH` on the whole '
                                      f'trimmed value (IDQ labels each space-delimited token).')
            outs_st = o_ids
            exprs[st.get('outputField') or outs_st[0]] = v
            if st.get('tokenizedOutputField'):
                exprs[st.get('tokenizedOutputField')] = src
        self.finish_dq(c, e, outs, names, exprs, iname)

    def tx_AvTx(self, c, mp, inst, tx, iname, params, fmap, drop, **kw):
        e = Tx(iname, 'Expression', 'PLACEHOLDER for the IDQ Address Validator: replace with a CDQ Address Verifier '
                                    '(see conversion_report.md). Echoes the input address; status fields are NULL.')
        linked = {p.get('transformationField') for p in inst.iter()
                  if short(p) == 'TransformationFieldPort' and (p.get('toPorts') or p.get('fromPort'))}
        fields = [f for f in tx.iter() if short(f) == 'AvField' and f.get(IMX + 'id') in linked]
        by_internal = {}
        for f in fields:
            if f.get('input') == 'true':
                dt, p, s = idq_type(f)
                n = e.unique(f.get('name'), prefix='i_')
                e.add(Port(n, dt, p, s, 'INPUT'))
                fmap[f.get(IMX + 'id')] = n
                by_internal[dec(f.get('internalName'))] = n
        for f in fields:
            if f.get('output') == 'true':
                dt, p, s = idq_type(f)
                n = e.unique(f.get('name'))
                internal = dec(f.get('internalName'))
                ex = by_internal.get(AV_ECHO.get(internal, ''), None)
                if internal == 'OUT#Country#ISO2#1':
                    ex = "'US'"
                e.add(Port(n, dt, p, s, 'OUTPUT', ex or 'NULL', DEFAULT_ERROR))
                fmap[f.get(IMX + 'id')] = n
        e.attrs = [('Tracing Level', 'Normal')]
        self.add_inst(c, iname, 'Expression', e, TRANSFORMATION_NAME=iname, TYPE='TRANSFORMATION', REUSABLE='NO')
        opts = {a.get('name'): a.get('optionValue') for a in tx.iter() if short(a) == 'AvStringOption'}
        self.note(c.name, f'**`{iname}` is a placeholder.** The IDQ Address Validator (mode `{tx.get("mode")}`, '
                          f'country `{tx.get("defaultCountry")}`, casing `{tx.get("casingStyle")}`, options {opts}) has '
                          f'no PowerCenter-XML equivalent that IDMC converts. After import, replace the Expression with '
                          f'a CDQ **Address Verifier** (Verifier asset) and map the {len(fields)} linked ports; until '
                          f'then the address lines, city, postcode and state are echoed, country is `US` and every '
                          f'status / mailability / geocode field is NULL.')


# ----------------------------------------------------------------------------------------------------------- writer

def el(parent, tag, attrs=None, **kw):
    a = dict(attrs or {})
    a.update(kw)
    return ET.SubElement(parent, tag, {k: ('' if v is None else str(v)) for k, v in a.items() if not k.startswith('_')})


class Writer:
    def __init__(self, conv):
        self.cv = conv

    def tx_el(self, parent, t):
        attrs = dict(DESCRIPTION=t.description, NAME=t.name, OBJECTVERSION='1', REUSABLE='NO', TYPE=t.type,
                     VERSIONNUMBER='1')
        attrs.update(t.extra)
        x = el(parent, 'TRANSFORMATION', attrs)
        for g in t.groups:
            el(x, 'GROUP', g)
        for p in t.ports:
            a = dict(DATATYPE=p.dtype, DEFAULTVALUE=p.default, DESCRIPTION='', NAME=p.name, PICTURETEXT='',
                     PORTTYPE=p.porttype, PRECISION=p.prec, SCALE=p.scale)
            if p.expr is not None and t.type in ('Expression',):
                a['EXPRESSION'] = p.expr if p.porttype != 'INPUT' else ''
                a['EXPRESSIONTYPE'] = 'GENERAL'
            if p.group:
                a['GROUP'] = p.group
            if p.ref:
                a['REF_FIELD'] = p.ref
            a.update(p.extra)
            el(x, 'TRANSFORMFIELD', a)
        for k, v in t.attrs:
            el(x, 'TABLEATTRIBUTE', NAME=k, VALUE=v)
        for i, o in t.deps:
            el(x, 'FIELDDEPENDENCY', INPUTFIELD=i, OUTPUTFIELD=o)
        return x

    def body(self, parent, c):
        for t in c.txs.values():
            self.tx_el(parent, t)
        for i in c.instances:
            x = el(parent, 'INSTANCE', dict(DESCRIPTION='', **i))
            for s in i.get('_assoc', []):
                el(x, 'ASSOCIATED_SOURCE_INSTANCE', NAME=s)
        for a, af, b, bf in c.connectors:
            el(parent, 'CONNECTOR', FROMFIELD=af, FROMINSTANCE=a, FROMINSTANCETYPE=c.inst_type[a], TOFIELD=bf,
               TOINSTANCE=b, TOINSTANCETYPE=c.inst_type[b])

    def source(self, parent, key, t):
        odbc = self.cv.is_odbc(t)
        pk = self.cv.pk_columns(t)
        x = el(parent, 'SOURCE', BUSINESSNAME='', DATABASETYPE='ODBC' if odbc else 'Oracle', DBDNAME=key[0],
               DESCRIPTION='', NAME=key[1], OBJECTVERSION='1', OWNERNAME=t.get('ownerName') or '', VERSIONNUMBER='1')
        offset = 0
        for n, col in enumerate(self.cv.columns(t), 1):
            dt, p, s = db_type(col, odbc)
            el(x, 'SOURCEFIELD', BUSINESSNAME='', DATATYPE=dt, DESCRIPTION='', FIELDNUMBER=n, FIELDPROPERTY='0',
               FIELDTYPE='ELEMITEM', HIDDEN='NO', KEYTYPE='PRIMARY KEY' if col.get(IMX + 'id') in pk else 'NOT A KEY',
               LENGTH='0', LEVEL='0', NAME=col.get('name'), NULLABLE='NULL' if col.get('nullable') == 'true' else 'NOTNULL',
               OCCURS='0', OFFSET=offset, PHYSICALLENGTH=p, PHYSICALOFFSET=offset, PICTURETEXT='', PRECISION=p,
               SCALE=s, USAGE_FLAGS='')
            offset += int(p or 0)

    def target(self, parent, name, t):
        odbc = self.cv.is_odbc(t)
        pk = self.cv.pk_columns(t)
        x = el(parent, 'TARGET', BUSINESSNAME='', CONSTRAINT='', DATABASETYPE='ODBC' if odbc else 'Oracle',
               DESCRIPTION='', NAME=name, OBJECTVERSION='1', TABLEOPTIONS='', VERSIONNUMBER='1')
        for n, col in enumerate(self.cv.columns(t), 1):
            dt, p, s = db_type(col, odbc)
            el(x, 'TARGETFIELD', BUSINESSNAME='', DATATYPE=dt, DESCRIPTION='', FIELDNUMBER=n,
               KEYTYPE='PRIMARY KEY' if col.get(IMX + 'id') in pk else 'NOT A KEY', NAME=col.get('name'),
               NULLABLE='NULL' if col.get('nullable') == 'true' else 'NOTNULL', PICTURETEXT='', PRECISION=p, SCALE=s)

    def mapplet(self, parent, c):
        x = el(parent, 'MAPPLET', DESCRIPTION=c.description, ISVALID='YES', NAME=c.name, OBJECTVERSION='1',
               VERSIONNUMBER='1')
        self.body(x, c)

    def mapping(self, parent, c):
        x = el(parent, 'MAPPING', DESCRIPTION=c.description, ISVALID='YES', NAME=c.name, OBJECTVERSION='1',
               VERSIONNUMBER='1')
        self.body(x, c)
        order = [t['inst'] for t in c.targets]
        for a, b in c.load_order:
            if a in order and b in order:
                order.remove(a)
                order.insert(order.index(b), a)
        for n, t in enumerate(order, 1):
            el(x, 'TARGETLOADORDER', ORDER=n, TARGETINSTANCE=t)
        for p in c.params:
            dt = 'integer' if p['type'] == 'integer' else 'string'
            el(x, 'MAPPINGVARIABLE', DATATYPE=dt, DEFAULTVALUE=p['default'] or '', DESCRIPTION='',
               ISEXPRESSIONVARIABLE='NO', ISPARAM='YES', NAME='$$' + p['name'],
               PRECISION=p['precision'] or ('10' if dt == 'integer' else '255'), SCALE='0', USERDEFINED='YES')
        el(x, 'ERPINFO')

    def config(self, parent):
        x = el(parent, 'CONFIG', DESCRIPTION='Default session configuration object', ISDEFAULT='YES',
               NAME='default_session_config', VERSIONNUMBER='1')
        for k, v in [('Advanced', ''), ('Constraint based load ordering', 'NO'), ('Cache LOOKUP() function', 'YES'),
                     ('Default buffer block size', 'auto'), ('Line Sequential buffer length', '1024'),
                     ('Maximum Memory Allowed For Auto Memory Attributes', '512MB'),
                     ('Maximum Percentage of Total Memory Allowed For Auto Memory Attributes', '5'),
                     ('Additional Concurrent Pipelines for Lookup Cache Creation', 'Auto'),
                     ('Custom Properties', ''), ('Pre-build lookup cache', 'Auto'), ('Optimization Level', 'Medium'),
                     ('DateTime Format String', 'MM/DD/YYYY HH24:MI:SS.US'), ('Pre 85 Timestamp Compatibility', 'NO'),
                     ('Log Options', '0'), ('Save session log by', 'Session runs'),
                     ('Save session log for these runs', '0'), ('Error handling', ''), ('Stop on errors', '1'),
                     ('Override tracing', 'None'), ('On Stored Procedure error', 'Stop'),
                     ('On Pre-session command task error', 'Stop'), ('On Pre-Post SQL error', 'Stop'),
                     ('Enable Recovery', 'NO'), ('Error Log Type', 'None'), ('Partitioning Options', ''),
                     ('Dynamic Partitioning', 'Disabled'), ('Session on Grid', ''), ('Is Enabled', 'NO')]:
            el(x, 'ATTRIBUTE', NAME=k, VALUE=v)

    def session(self, parent, sname, c, cfg, param_file):
        x = el(parent, 'SESSION', DESCRIPTION='', ISVALID='YES', MAPPINGNAME=c.name, NAME=sname, REUSABLE='NO',
               SORTORDER='Binary', VERSIONNUMBER='1')
        pipe = 1
        for s in c.sources:
            for d in s['defs']:
                el(x, 'SESSTRANSFORMATIONINST', ISREPARTITIONPOINT='NO', PIPELINE=pipe, SINSTANCENAME=d, STAGE='0',
                   TRANSFORMATIONNAME=next(i['TRANSFORMATION_NAME'] for i in c.instances if i['NAME'] == d),
                   TRANSFORMATIONTYPE='Source Definition')
            el(x, 'SESSTRANSFORMATIONINST', ISREPARTITIONPOINT='YES', PARTITIONTYPE='PASS THROUGH', PIPELINE=pipe,
               SINSTANCENAME=s['sq'], STAGE='1', TRANSFORMATIONNAME=s['sq'], TRANSFORMATIONTYPE='Source Qualifier')
        for i in c.instances:
            if i['TRANSFORMATION_TYPE'] in ('Source Definition', 'Source Qualifier', 'Target Definition'):
                continue
            el(x, 'SESSTRANSFORMATIONINST', ISREPARTITIONPOINT='NO', PIPELINE=pipe, SINSTANCENAME=i['NAME'], STAGE='1',
               TRANSFORMATIONNAME=i['TRANSFORMATION_NAME'], TRANSFORMATIONTYPE=i['TRANSFORMATION_TYPE'])
        for t in c.targets:
            el(x, 'SESSTRANSFORMATIONINST', ISREPARTITIONPOINT='YES', PARTITIONTYPE='PASS THROUGH', PIPELINE=pipe,
               SINSTANCENAME=t['inst'], STAGE='2',
               TRANSFORMATIONNAME=next(i['TRANSFORMATION_NAME'] for i in c.instances if i['NAME'] == t['inst']),
               TRANSFORMATIONTYPE='Target Definition')
        ref = el(x, 'CONFIGREFERENCE', REFOBJECTNAME='default_session_config', TYPE='Session config')
        el(ref, 'ATTRIBUTE', NAME='DateTime Format String', VALUE=cfg.get('dateFormat') or 'MM/DD/YYYY HH24:MI:SS.US')
        el(ref, 'ATTRIBUTE', NAME='Override tracing', VALUE=(cfg.get('overrideTracingLevel') or 'none').capitalize()
           if cfg.get('overrideTracingLevel') not in (None, 'none') else 'None')
        for s in c.sources:
            el(x, 'SESSIONEXTENSION', NAME='Relational Reader', SINSTANCENAME=s['sq'], SUBTYPE='Relational Reader',
               TRANSFORMATIONTYPE='Source Qualifier', TYPE='READER')
            for d in s['defs']:
                se = el(x, 'SESSIONEXTENSION', DSQINSTNAME=s['sq'], DSQINSTTYPE='Source Qualifier',
                        NAME='Relational Reader', SINSTANCENAME=d, SUBTYPE='Relational Reader',
                        TRANSFORMATIONTYPE='Source Definition', TYPE='READER')
                el(se, 'CONNECTIONREFERENCE', CNXREFNAME='DB Connection', CONNECTIONNAME=s['conn'],
                   CONNECTIONNUMBER='1', CONNECTIONSUBTYPE='ODBC' if s['odbc'] else 'Oracle',
                   CONNECTIONTYPE='Relational', VARIABLE='')
        upd = c.update_targets
        for t in c.targets:
            se = el(x, 'SESSIONEXTENSION', NAME='Relational Writer', SINSTANCENAME=t['inst'],
                    SUBTYPE='Relational Writer', TRANSFORMATIONTYPE='Target Definition', TYPE='WRITER')
            el(se, 'CONNECTIONREFERENCE', CNXREFNAME='DB Connection', CONNECTIONNAME=t['conn'], CONNECTIONNUMBER='1',
               CONNECTIONSUBTYPE='ODBC' if t['odbc'] else 'Oracle', CONNECTIONTYPE='Relational', VARIABLE='')
            for k, v in [('Target load type', 'Bulk' if t['bulk'] else 'Normal'), ('Insert', 'YES'),
                         ('Update as Update', 'NO'), ('Update as Insert', 'NO'), ('Update else Insert', 'NO'),
                         ('Delete', 'YES' if t['inst'] in upd else 'NO'),
                         ('Truncate target table option', 'YES' if t['truncate'] else 'NO'),
                         ('Reject file directory', '$PMBadFileDir/'), ('Reject filename', t['reject'])]:
                el(se, 'ATTRIBUTE', NAME=k, VALUE=v)
        for k, v in [('General Options', ''), ('Write Backward Compatible Session Log File', 'NO'),
                     ('Session Log File Name', (cfg.get('sessionLogFileName') or sname) + '.log'),
                     ('Session Log File directory', '$PMSessionLogDir/'), ('Parameter Filename', param_file),
                     ('Enable Test Load', 'NO'), ('$Source connection value', ''), ('$Target connection value', ''),
                     ('Treat source rows as', 'Data driven' if upd else 'Insert'), ('Commit Type', 'Target'),
                     ('Commit Interval', '10000'), ('Commit On End Of File', 'YES'),
                     ('Rollback Transactions on Errors', 'NO'),
                     ('Recovery Strategy', 'Fail task and continue workflow'), ('Performance', ''),
                     ('DTM buffer size', 'auto'), ('Collect performance data', 'NO'),
                     ('Incremental Aggregation', 'NO'), ('Reinitialize Aggregate Cache', 'NO'),
                     ('Enable high precision', 'YES' if cfg.get('highPrecisionEnabled') == 'true' else 'NO'),
                     ('Session retry on deadlock', 'NO'), ('Pushdown Optimization', 'None'),
                     ('Allow Temporary View for Pushdown', 'NO'), ('Allow Temporary Sequence for Pushdown', 'NO'),
                     ('Allow Pushdown for User Incompatible Connections', 'NO')]:
            el(x, 'ATTRIBUTE', NAME=k, VALUE=v)

    def workflow(self, parent, wfm, sessions, param_file):
        x = el(parent, 'WORKFLOW', DESCRIPTION='Converted from IDQ workflow ' + wfm['name'], ISENABLED='YES',
               ISRUNNABLESERVICE='NO', ISSERVICE='NO', ISVALID='YES', NAME=wfm['name'], REUSABLE_SCHEDULER='NO',
               SCHEDULERNAME='Scheduler', SERVERNAME='', SERVER_DOMAINNAME='', SUSPEND_ON_ERROR='NO',
               TASKS_MUST_RUN_ON_SERVER='NO', VERSIONNUMBER='1')
        sch = el(x, 'SCHEDULER', DESCRIPTION='', NAME='Scheduler', REUSABLE='NO', VERSIONNUMBER='1')
        el(sch, 'SCHEDULEINFO', SCHEDULETYPE='ONDEMAND')
        el(x, 'TASK', DESCRIPTION='', NAME='Start', REUSABLE='NO', TYPE='Start', VERSIONNUMBER='1')
        tasks, names = wfm['tasks'], {}
        for tid, t in tasks.items():
            if t['type'] == 'CommandTask':
                ct = el(x, 'TASK', DESCRIPTION='', NAME=t['name'], REUSABLE='NO', TYPE='Command', VERSIONNUMBER='1')
                el(ct, 'ATTRIBUTE', NAME='Fail task if any command fails', VALUE='YES')
                el(ct, 'ATTRIBUTE', NAME='Recovery Strategy', VALUE='Fail task and continue workflow')
                cmd = t['command'].replace('${var:sys.WorkflowName}', wfm['name'])
                wd = t['config'].get('workingDirectory')
                el(ct, 'VALUEPAIR', EXECORDER='1', NAME='touch_indicator', REVERSEASSIGNMENT='NO',
                   VALUE=f'cd {wd} && {cmd}' if wd else cmd)
                names[tid] = (t['name'], 'Command')
        for tid, t in tasks.items():
            if t['type'] == 'MappingTask':
                sname = 's_' + t['name']
                self.session(x, sname, sessions[t['mapping']], t['config'], param_file)
                names[tid] = (sname, 'Session')
            elif t['type'] == 'StartTask':
                names[tid] = ('Start', 'Start')
        el(x, 'TASKINSTANCE', DESCRIPTION='', ISENABLED='YES', NAME='Start', REUSABLE='NO', TASKNAME='Start',
           TASKTYPE='Start')
        for tid, (n, typ) in names.items():
            if typ == 'Start':
                continue
            el(x, 'TASKINSTANCE', DESCRIPTION='', FAIL_PARENT_IF_INSTANCE_DID_NOT_RUN='NO',
               FAIL_PARENT_IF_INSTANCE_FAILS='YES', ISENABLED='YES', NAME=n, REUSABLE='NO', TASKNAME=n, TASKTYPE=typ,
               TREAT_INPUTLINK_AS_AND='YES')
        for a, b in self.links(wfm, names):
            cond = '' if a == 'Start' else f'${a}.Status = SUCCEEDED'
            el(x, 'WORKFLOWLINK', CONDITION=cond, FROMTASK=a, TOTASK=b)
        for k, v in [('Parameter Filename', param_file), ('Write Backward Compatible Workflow Log File', 'NO'),
                     ('Workflow Log File Name', wfm['name'] + '.log'), ('Workflow Log File Directory', '$PMWorkflowLogDir/'),
                     ('Save Workflow log by', 'By runs'), ('Save workflow log for these runs', '0'),
                     ('Service Name', ''), ('Service Timeout', '0'), ('Is Service Visible', 'NO'),
                     ('Is Service Protected', 'NO'), ('Fail task after wait time', '0'),
                     ('Enable HA recovery', 'NO'), ('Automatically recover terminated tasks', 'NO'),
                     ('Service Level Name', 'Default'), ('Allow concurrent run with unique run instance name', 'NO'),
                     ('Allow concurrent run with same run instance name', 'NO'), ('Maximum number of concurrent runs', '0'),
                     ('Assigned Web Services Hubs', ''), ('Maximum number of concurrent runs per Hub', '1000'),
                     ('Expected Service Time', '1')]:
            el(x, 'ATTRIBUTE', NAME=k, VALUE=v)

    def links(self, wfm, names):
        """Task-to-task links: IDQ gateways are collapsed (PowerCenter tasks wait for all input links)."""
        succ = defaultdict(list)
        for a, b, _ in wfm['flows']:
            succ[a].append(b)

        def reach(n, seen):
            out = set()
            for s in succ[n]:
                if s in seen:
                    continue
                seen.add(s)
                if s in names:
                    out.add(s)
                else:
                    out |= reach(s, seen)
            return out

        edges = {(a, b) for a in names for b in reach(a, set())}

        def path(a, b, skip):
            stack, seen = [a], set()
            while stack:
                n = stack.pop()
                for x, y in edges:
                    if x == n and (x, y) != skip and y not in seen:
                        if y == b:
                            return True
                        seen.add(y)
                        stack.append(y)
            return False

        reduced = sorted((e for e in edges if not path(e[0], e[1], e)), key=lambda e: (names[e[0]][0], names[e[1]][0]))
        return [(names[a][0], names[b][0]) for a, b in reduced]

    def document(self, folder, sources, targets, mapplets, mappings, wfm=None, sessions=None, param_file=''):
        root = ET.Element('POWERMART', CREATION_DATE=CREATION_DATE, REPOSITORY_VERSION='186.95')
        repo = el(root, 'REPOSITORY', CODEPAGE='UTF-8', DATABASETYPE='Oracle', NAME='IDQ_CONVERTED', VERSION='186')
        f = el(repo, 'FOLDER', DESCRIPTION='Converted from the IDQ export ' + (wfm['name'] if wfm else ''), GROUP='',
               NAME=folder, OWNER='Administrator', PERMISSIONS='rwx---r--', SHARED='NOTSHARED', UUID='')
        for key, t in sources:
            self.source(f, key, t)
        for name, t in targets:
            self.target(f, name, t)
        for c in mapplets:
            self.mapplet(f, c)
        for c in mappings:
            self.mapping(f, c)
        if wfm:
            self.config(f)
            self.workflow(f, wfm, sessions, param_file)
        ET.indent(root, space='  ')
        body = ET.tostring(root, encoding='unicode')
        return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE POWERMART SYSTEM "powrmart.dtd">\n' + body + '\n')


# ---------------------------------------------------------------------------------------------------------- checks

def check(c, mapplet_defs):
    """Structural checks: every connector names an existing instance and port with the right direction."""
    errs = []
    ports = {}
    inames = [i['NAME'].upper() for i in c.instances]
    if len(inames) != len(set(inames)):
        errs.append(f'{c.name}: duplicate instance names')
    for i in c.instances:
        n, t = i['NAME'], i['TRANSFORMATION_TYPE']
        if t in ('Source Definition', 'Target Definition'):
            continue
        if t == 'Mapplet':
            md = mapplet_defs[i['TRANSFORMATION_NAME']]
            ins = {p.name.upper() for x in md.txs.values() if x.type == 'Input Transformation' for p in x.ports}
            outs = {p.name.upper() for x in md.txs.values() if x.type == 'Output Transformation' for p in x.ports}
            ports[n] = (ins, outs)
            continue
        tx = c.txs.get(i['TRANSFORMATION_NAME'])
        ins = {p.name.upper() for p in tx.ports if 'INPUT' in p.porttype}
        outs = {p.name.upper() for p in tx.ports if 'OUTPUT' in p.porttype}
        ports[n] = (ins, outs)
        names = [p.name.upper() for p in tx.ports]
        if len(names) != len(set(names)):
            errs.append(f'{c.name}.{n}: duplicate port names')
    seen_to = set()
    for a, af, b, bf in c.connectors:
        if a in ports and af.upper() not in ports[a][1]:
            errs.append(f'{c.name}: {a}.{af} is not an output port')
        if b in ports and bf.upper() not in ports[b][0]:
            errs.append(f'{c.name}: {b}.{bf} is not an input port')
        if (b, bf.upper()) in seen_to:
            errs.append(f'{c.name}: {b}.{bf} has two incoming links')
        seen_to.add((b, bf.upper()))
    return errs


# ------------------------------------------------------------------------------------------------------------ main

def param_file_text(folder, wfm, mappings):
    lines = [f'# PowerCenter parameter file for {wfm["name"]} (defaults taken from the IDQ mapping parameters).', '']
    lines += [f'[{folder}.WF:{wfm["name"]}]', '']
    for t in wfm['tasks'].values():
        if t['type'] != 'MappingTask':
            continue
        c = mappings[t['mapping']]
        lines.append(f'[{folder}.WF:{wfm["name"]}.ST:s_{t["name"]}]')
        for p in c.params:
            lines.append(f'$${p["name"]}={p["default"] or ""}')
        lines.append('')
    return '\n'.join(lines)


def report_text(cv, wfm, mappings, mapplets, folder, stats):
    out = [f'# Conversion report: {wfm["name"]}', '',
           f'Generated by `ext-tools/idq_to_pc.py` from `docs/{wfm["name"]}.xml`. Regenerate rather than edit.', '',
           '## Objects', '', '| Object | Count |', '|---|---|']
    for k, v in stats.items():
        out.append(f'| {k} | {v} |')
    out += ['', '## Notes by object', '']
    for name in ['(folder)'] + [c.name for c in mapplets] + [c.name for c in mappings]:
        notes = cv.report.get(name)
        if not notes:
            continue
        out += [f'### {name}', '']
        out += [f'- {n}' for n in dict.fromkeys(notes)]
        out.append('')
    out += ['## Filtered data', '',
            'Per mapping: every step that can stop, divert or collapse rows, and which rows never reach a `C_S_*` '
            'table. The PowerCenter Filter, Router, Sorter and Aggregator carry the same conditions. ' + FILTER_INTRO, '']
    cv.m.writers = table_writers(cv.m, {c.name for c in mappings})
    for c in mappings:
        lines, _ = mapping_filtered(cv.m, cv.by_name[c.name], h='###', title=c.name, intro=False)
        out += lines
    return '\n'.join(out).rstrip() + '\n'


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    path, out = argv[1], argv[2]
    folder = argv[argv.index('--folder') + 1] if '--folder' in argv else 'ECI'
    cv = Converter(path, folder)
    wfm = workflow(cv.m)
    mapping_names = [t['mapping'] for t in wfm['tasks'].values() if t['type'] == 'MappingTask']
    mappings = OrderedDict()
    for n in mapping_names:
        c = cv.build(cv.by_name[n], 'mapping')
        for a, af, b, bf in c.connectors:
            if c.inst_type.get(a) == 'Update Strategy' and c.inst_type.get(b) == 'Target Definition':
                c.update_targets.add(b)
        mappings[n] = c
    # mapplets in dependency order (used ones only)
    mapplets = list(cv.mapplet_defs.values())
    errs = []
    for c in mapplets + list(mappings.values()):
        errs += check(c, cv.mapplet_defs)
    if errs:
        raise SystemExit('structural check failed:\n  ' + '\n  '.join(errs))

    os.makedirs(os.path.join(out, 'mapplets'), exist_ok=True)
    w = Writer(cv)
    param_file = f'$PMRootDir/ParamFiles/{wfm["name"]}.param'
    xml = w.document(folder, list(cv.sources.items()), list(cv.targets.items()), mapplets, list(mappings.values()),
                     wfm, mappings, param_file)
    ET.fromstring(xml.split('\n', 2)[2])  # well-formed
    with open(os.path.join(out, wfm['name'] + '.XML'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(xml)
    for c in mapplets:
        doc = w.document(folder, [], [], [c], [])
        with open(os.path.join(out, 'mapplets', c.name + '.XML'), 'w', encoding='utf-8', newline='\n') as fh:
            fh.write(doc)
    with open(os.path.join(out, wfm['name'] + '.param'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(param_file_text(folder, wfm, mappings))
    stats = OrderedDict([
        ('Source definitions', len(cv.sources)), ('Target definitions', len(cv.targets)),
        ('Mapplets', len(mapplets)), ('Mappings', len(mappings)),
        ('Sessions', len(mappings)), ('Workflow', 1),
        ('Transformations (in mappings and mapplets)', sum(len(c.txs) for c in mapplets + list(mappings.values()))),
        ('Links', sum(len(c.connectors) for c in mapplets + list(mappings.values()))),
    ])
    with open(os.path.join(out, 'conversion_report.md'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(report_text(cv, wfm, list(mappings.values()), mapplets, folder, stats))
    for k, v in stats.items():
        print(f'{k}: {v}')


if __name__ == '__main__':
    main(sys.argv)

"""Extract lookup transformations from IDQ workflow XML exports.

Usage: python -I lookups.py <out.json> <wf1.xml> [<wf2.xml> ...]
"""
import json
import sys
import urllib.parse
import xml.etree.ElementTree as ET

IMX = '{http://com.informatica.imx}'
XSI = '{http://www.w3.org/2001/XMLSchema-instance}'


def dec(s):
    return urllib.parse.unquote_plus(s) if s else s


def local(tag):
    return tag.split('}')[-1]


def parse(path):
    tree = ET.parse(path)
    root = tree.getroot()
    by_id = {}
    parent = {}
    for p in root.iter():
        for c in p:
            parent[c] = p
        i = p.get(IMX + 'id')
        if i:
            by_id[i] = p

    def xtype(e):
        return (e.get(XSI + 'type') or '').split(':')[-1]

    def container(e):
        while e is not None:
            if (local(e.tag) == 'Mapping' or xtype(e) == 'Mapping') and e.get('name'):
                return e.get('name')
            e = parent.get(e)
        return None

    # port id -> (instance element, field name)
    ports = {}
    for inst in root.iter():
        if local(inst.tag) != 'Instance' or xtype(inst) != 'Instance':
            continue
        for tfp in inst.iter():
            t = xtype(tfp)
            if t == 'TransformationFieldPort':
                f = by_id.get(tfp.get('transformationField'))
                ports[tfp.get(IMX + 'id')] = (inst, f.get('name') if f is not None else '?')
            elif t == 'NestedPort':
                sf = by_id.get(tfp.get('structuralFeature'))
                ports[tfp.get(IMX + 'id')] = (inst, sf.get('name') if sf is not None else '?')

    def tx_of(inst):
        return by_id.get(inst.get('transformation'))

    def describe(port_id):
        p = ports.get(port_id)
        if not p:
            return None
        inst, field = p
        tx = tx_of(inst)
        return {'instance': inst.get('name'), 'type': xtype(tx) if tx is not None else '?', 'port': field}

    used = {}
    for inst in root.iter():
        if local(inst.tag) != 'Instance' or xtype(inst) != 'Instance':
            continue
        tx = tx_of(inst)
        if tx is not None and xtype(tx) == 'MappletTx':
            m = by_id.get(tx.get('mapplet'))
            if m is not None:
                used.setdefault(container(inst), set()).add(m.get('name'))
    USED.update({k: sorted(set(USED.get(k, [])) | v) for k, v in used.items()})

    out = []
    for inst in root.iter():
        if local(inst.tag) != 'Instance' or xtype(inst) != 'Instance':
            continue
        tx = tx_of(inst)
        if tx is None or xtype(tx) != 'LookupTx':
            continue
        dso = by_id.get(tx.get('dso'))
        lk = {
            'file': path.replace('\\', '/').split('/')[-1],
            'container': container(inst),
            'name': inst.get('name'),
            'condition': dec(tx.get('lookupCondition')),
            'multipleMatch': tx.get('multipleMatchHandling'),
            'returnPort': tx.get('returnPort'),
            'table': dso.get('name') if dso is not None else None,
            'sqlQuery': dec(dso.get('sqlQuery')) if dso is not None else None,
            'filter': dec(dso.get('filterCondition')) if dso is not None else None,
            'connection': None,
            'inputs': [],
            'outputs': [],
        }
        if dso is not None:
            for c in dso.iter():
                if c.get('connectionName'):
                    lk['connection'] = c.get('connectionName')
                    break
        for tfp in inst.find('ports') if inst.find('ports') is not None else []:
            if xtype(tfp) != 'TransformationFieldPort':
                continue
            f = by_id.get(tfp.get('transformationField'))
            fname = f.get('name') if f is not None else '?'
            if tfp.get('fromPort'):
                src = describe(tfp.get('fromPort'))
                lk['inputs'].append({'port': fname, 'from': src})
                for t in (tfp.get('toPorts') or '').split():
                    lk['outputs'].append({'port': fname, 'passthrough': True, 'to': describe(t)})
            elif tfp.get('toPorts') and f is not None and f.get('type', '').startswith('smd:'):
                for t in tfp.get('toPorts').split():
                    lk['outputs'].append({'port': fname, 'to': describe(t)})
            for np_ in tfp.iter():
                if xtype(np_) != 'NestedPort':
                    continue
                sf = by_id.get(np_.get('structuralFeature'))
                col = sf.get('name') if sf is not None else '?'
                for t in (np_.get('toPorts') or '').split():
                    lk['outputs'].append({'port': col, 'to': describe(t)})
        out.append(lk)
    return out


USED = {}

if __name__ == '__main__':
    res = []
    for p in sys.argv[2:]:
        res.extend(parse(p))
    with open(sys.argv[1], 'w') as fh:
        json.dump({'lookups': res, 'mapplets': USED}, fh, indent=1)
    print(len(res), 'lookups')

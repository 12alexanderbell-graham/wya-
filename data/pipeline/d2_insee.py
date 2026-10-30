#!/usr/bin/env python3
"""D2, France's levels from one set of borders: each commune's arrondissement, department and region from INSEE's
official code tables (the Code officiel géographique: v_commune, v_arrondissement, v_departement), so the coarser
levels are built from the communes' own arcs (d2_dissolve) and share every border with them. The earlier levels keep
their units (ids and names, the data's selection); an INSEE unit is matched to the earlier unit holding most of its
communes' area. geoBoundaries writes "œ" as "½"; fixed here in the communes' names.

usage: d2_insee.py fr-5.wyar fr-3.wyar fr-2.wyar fr-1.wyar INSEE_DIR OUT_DIR
"""
import csv, collections, json, math, os, sys, subprocess
sys.path.insert(0, os.path.dirname(__file__))
from wyar import read, write
from shapely.geometry import Polygon
from shapely.strtree import STRtree
from shapely.ops import unary_union

f5, f3, f2, f1, insee, outd = sys.argv[1:7]
os.makedirs(outd, exist_ok=True)
h5, a5, _ = read(f5)
for u in h5['u']: u['n'] = u['n'].replace('½', 'œ').replace('¼', 'Œ')

def shapes(h, arcs):
    sx, sy, tx, ty = h['t']
    def rp(r):
        pts = []
        for i in r: pts += arcs[i] if i >= 0 else arcs[~i][::-1]
        return [(x * sx + tx, y * sy + ty) for x, y in pts]
    return [unary_union([Polygon(rp(r)).buffer(0) for r in o if len(rp(r)) >= 3]) for o in h['o']]
g5 = shapes(h5, a5)

# communes, and the municipal arrondissements of Paris, Lyon and Marseille (geoBoundaries draws those, not the three
# cities whole)
com = [r for r in csv.DictReader(open(f'{insee}/v_commune_2024.csv', encoding='utf-8')) if r['TYPECOM'] in ('COM', 'ARM')]
by_name = collections.defaultdict(list)
for r in com: by_name[r['LIBELLE']].append(r)
# each department's middle, from its communes matched without doubt
mid = collections.defaultdict(list)
for k, u in enumerate(h5['u']):
    c = by_name.get(u['n'], [])
    if len(c) == 1: p = g5[k].representative_point(); mid[c[0]['DEP']].append((p.x, p.y))
mid = {d: (sum(x for x, _ in v) / len(v), sum(y for _, y in v) / len(v)) for d, v in mid.items()}
code = {}
unmatched = []
for k, u in enumerate(h5['u']):
    c = by_name.get(u['n'], [])
    if not c: unmatched.append(k); continue
    if len(c) > 1:
        p = g5[k].representative_point()
        c = [min(c, key=lambda r: math.hypot(p.x - mid.get(r['DEP'], (999, 999))[0], p.y - mid.get(r['DEP'], (999, 999))[1]))]
    code[k] = c[0]

def match(level_file, key):
    """each INSEE unit (by `key`) -> the earlier unit holding most of its communes' area"""
    h, a, _ = read(level_file); g = shapes(h, a); tree = STRtree(g)
    area = collections.defaultdict(collections.Counter)
    for k, r in code.items():
        for j in tree.query(g5[k]): area[key(r)][j] += g[j].intersection(g5[k]).area
    m = {c: h['u'][cnt.most_common(1)[0][0]]['id'] for c, cnt in area.items() if cnt}
    clash = [i for i, n in collections.Counter(m.values()).items() if n > 1]
    return h, m, clash, g, tree

h3, m3, clash3, g3, t3 = match(f3, lambda r: r['DEP'] + r['ARR'])
h2, m2, clash2, _, _ = match(f2, lambda r: r['DEP'])
h1, m1, clash1, _, _ = match(f1, lambda r: r['REG'])
# communes with no INSEE row (merged since the source): their arrondissement by the larger share of their area
for k in unmatched:
    best = max(t3.query(g5[k]), key=lambda j: g3[j].intersection(g5[k]).area, default=None)
    code[k] = {'_arr': h3['u'][best]['id']} if best is not None else None

canton = {k: u.get('p') for k, u in enumerate(h5['u'])}
arr_of = {}
for k, r in code.items():
    if r is None: continue
    arr_of[k] = r['_arr'] if '_arr' in r else m3.get(r['DEP'] + r['ARR'])
# arrondissement -> department, department -> region, from the INSEE tables through the matches
arr_dep, dep_reg = {}, {}
for r in code.values():
    if r and '_arr' not in r:
        a = m3.get(r['DEP'] + r['ARR']); d = m2.get(r['DEP']); g = m1.get(r['REG'])
        if a and d: arr_dep[a] = d
        if d and g: dep_reg[d] = g

def dissolve(fine_path, coarse_path, out_path):
    r = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'd2_dissolve.py'), fine_path, coarse_path, out_path],
                       capture_output=True, text=True, check=True)
    return r.stdout.strip()
tmp = os.path.join(outd, '_tmp5.wyar')
for k, u in enumerate(h5['u']): u['p'] = arr_of.get(k)
write(tmp, h5, a5)
rep = {'3': dissolve(tmp, f3, os.path.join(outd, 'fr-3.wyar'))}
h, a, _ = read(os.path.join(outd, 'fr-3.wyar'))
for u in h['u']: u['p'] = arr_dep.get(u['id'])
write(os.path.join(outd, '_tmp3.wyar'), h, a)
rep['2'] = dissolve(os.path.join(outd, '_tmp3.wyar'), f2, os.path.join(outd, 'fr-2.wyar'))
h, a, _ = read(os.path.join(outd, 'fr-2.wyar'))
for u in h['u']: u['p'] = dep_reg.get(u['id'])
write(os.path.join(outd, '_tmp2.wyar'), h, a)
rep['1'] = dissolve(os.path.join(outd, '_tmp2.wyar'), f1, os.path.join(outd, 'fr-1.wyar'))
# the communes again with their canton as `p`, names fixed, and their INSEE code
for k, u in enumerate(h5['u']):
    u['p'] = canton[k]
    r = code.get(k)
    if r and '_arr' not in r: u['c'] = r['COM']
write(os.path.join(outd, 'fr-5.wyar'), h5, a5)
for t in ('_tmp5.wyar', '_tmp3.wyar', '_tmp2.wyar'): os.remove(os.path.join(outd, t))
print(json.dumps({'communes': len(h5['u']), 'matched to INSEE': len(h5['u']) - len(unmatched), 'not in INSEE (merged since)': len(unmatched),
                  'arrondissements matched': len(m3), 'two INSEE units on one earlier unit': {'arr': clash3, 'dep': clash2, 'reg': clash1},
                  'dissolve': rep}, ensure_ascii=False, indent=1))

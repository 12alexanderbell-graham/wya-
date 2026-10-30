#!/usr/bin/env python3
"""D2, the United Kingdom's levels from one set of borders: the electoral wards (ONS, WD_DEC_2025_UK_BGC, as gb-4 by
d2_level.py --code-ids) carry their ward code and their local authority district (LAD25CD); the districts are a new
level (gb-3, ids `GB3-<LAD code>`), and the earlier counties and unitary authorities (gb-2) and the four countries
(gb-1) keep their ids and names, each district given to the earlier county holding most of its area and each county to
its country the same way. Every level is dissolved from the wards' arcs (d2_dissolve), so all share the same lines.

usage: d2_gb.py gb-4.wyar wd.csv OLD_gb-2.wyar OLD_gb-1.wyar OUT_DIR      (wd.csv: WD25CD,LAD25CD,LAD25NM)
"""
import csv, collections, os, sys, subprocess
sys.path.insert(0, os.path.dirname(__file__))
from wyar import read, write
from shapely.geometry import Polygon
from shapely.ops import unary_union

f4, wdcsv, o2, o1, outd = sys.argv[1:6]
os.makedirs(outd, exist_ok=True)
P = os.path.dirname(os.path.abspath(__file__))
wd = {r['WD25CD']: r for r in csv.DictReader(open(wdcsv, encoding='utf-8'))}

def shapes(path):
    h, arcs, _ = read(path)
    sx, sy, tx, ty = h['t']
    def eo(o):
        # even-odd: a ring inside another is a hole
        g = Polygon()
        for r in o:
            pts = []
            for i in r: pts += arcs[i] if i >= 0 else arcs[~i][::-1]
            if len(pts) >= 3: g = g.symmetric_difference(Polygon([(x * sx + tx, y * sy + ty) for x, y in pts]).buffer(0))
        return g
    return h, [eo(o) for o in h['o']]

def best(groups, old):
    ho, go = shapes(old)
    out = {}
    for k, g in groups.items():
        share = [(g.intersection(o).area, j) for j, o in enumerate(go) if o.intersects(g)]
        out[k] = ho['u'][max(share)[1]]['id']
    return out

h4, a4, _ = read(f4)
_, g4 = shapes(f4)
lad = {u['c']: wd[u['c']]['LAD25CD'] for u in h4['u']}
for u in h4['u']: u['p'] = 'GB3-' + lad[u['c']]
write(os.path.join(outd, 'gb-4.wyar'), h4, a4)
names = {r['LAD25CD']: r['LAD25NM'] for r in wd.values()}
units3 = [{'id': 'GB3-' + c, 'n': n, 'c': c} for c, n in sorted(names.items(), key=lambda kv: kv[1])]
skel = os.path.join(outd, '_skel.wyar')
write(skel, {'t': h4['t'], 'u': units3, 'o': [[] for _ in units3], 'f': 1}, [])
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'gb-4.wyar'), skel,
                os.path.join(outd, 'gb-3.wyar')], check=True)
os.remove(skel)

# districts to the earlier counties, counties to the countries, by the larger share of area
by3 = collections.defaultdict(list)
for k, u in enumerate(h4['u']): by3[u['p']].append(k)
m2 = best({k: unary_union([g4[i] for i in v]) for k, v in by3.items()}, o2)
h3, a3, _ = read(os.path.join(outd, 'gb-3.wyar'))
for u in h3['u']: u['p'] = m2[u['id']]
write(os.path.join(outd, 'gb-3.wyar'), h3, a3)
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'gb-3.wyar'), o2,
                os.path.join(outd, 'gb-2.wyar')], check=True)
by2 = collections.defaultdict(list)
for k, u in enumerate(h4['u']): by2[m2[u['p']]].append(k)
m1 = best({k: unary_union([g4[i] for i in v]) for k, v in by2.items()}, o1)
h2, a2, _ = read(os.path.join(outd, 'gb-2.wyar'))
empty2 = [u['id'] for u, o in zip(h2['u'], h2['o']) if not o]
for u in h2['u']: u['p'] = m1.get(u['id'], '')
# an earlier county no district fell in (merged since): dropped, listed in the report
keep = [k for k, o in enumerate(h2['o']) if o]
h2['u'] = [h2['u'][k] for k in keep]; h2['o'] = [h2['o'][k] for k in keep]
write(os.path.join(outd, 'gb-2.wyar'), h2, a2)
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'gb-2.wyar'), o1,
                os.path.join(outd, 'gb-1.wyar')], check=True)
h1, a1, _ = read(os.path.join(outd, 'gb-1.wyar'))
for u in h1['u']: u.pop('p', None)
write(os.path.join(outd, 'gb-1.wyar'), h1, a1)
# which districts' counties disagree with the ward codes' own country letter (a check)
bad = [u['id'] for u in h3['u'] if {'E': 'GB-ENG', 'W': 'GB-WLS', 'S': 'GB-SCT', 'N': 'GB-NIR'}[u['c'][0]] !=
       next(x['c'] for x in h1['u'] if x['id'] == m1[u['p']])]
print({'wards': len(h4['u']), 'districts': len(h3['u']), 'counties': len(h2['u']), 'countries': len(h1['u']),
       'earlier counties with no district (dropped)': empty2, 'districts in the wrong country': bad})

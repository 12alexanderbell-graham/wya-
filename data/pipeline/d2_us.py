#!/usr/bin/env python3
"""D2, the United States' levels from one set of borders: the county subdivisions (Census cartographic boundaries,
cb_2024_us_cousub_500k, the 50 states and DC, as us-3 by d2_level.py --code-ids) carry their GEOID (state 2, county 3,
subdivision 5 digits). The counties (us-2) are their GEOIDs' first five digits and the states (us-1) the first two;
both are dissolved from the subdivisions' arcs (d2_dissolve), so all levels share the same lines. A county keeps its
earlier id (with the Census name) when one earlier county and it are each other's best match by area, or failing that the earlier county of the same name close by; the others (Connecticut's
planning regions, which replaced its eight counties in 2022) are new, ids `US2-<GEOID>`, and `us-2-moves.tsv` gives
each earlier id the new county holding most of its area. The states keep their earlier ids and names.

usage: d2_us.py us-3.wyar cs.csv OLD_us-2.wyar OLD_us-1.wyar OUT_DIR      (cs.csv: GEOID,NAMELSADCO,STATE_NAME)
"""
import csv, collections, os, sys, subprocess
sys.path.insert(0, os.path.dirname(__file__))
from wyar import read, write
from shapely.geometry import Polygon
from shapely.ops import unary_union

f3, cscsv, o2, o1, outd = sys.argv[1:6]
os.makedirs(outd, exist_ok=True)
P = os.path.dirname(os.path.abspath(__file__))
cs = {r['GEOID']: r for r in csv.DictReader(open(cscsv, encoding='utf-8'))}

def shapes(path):
    h, arcs, _ = read(path)
    sx, sy, tx, ty = h['t']
    def eo(o):
        g = Polygon()
        for r in o:
            pts = []
            for i in r: pts += arcs[i] if i >= 0 else arcs[~i][::-1]
            if len(pts) >= 3: g = g.symmetric_difference(Polygon([(x * sx + tx, y * sy + ty) for x, y in pts]).buffer(0))
        return g
    return h, [eo(o) for o in h['o']]

h3, a3, _ = read(f3)
_, g3 = shapes(f3)
groups = collections.defaultdict(list)
for k, u in enumerate(h3['u']): groups[u['c'][:5]].append(k)
gg = {c: unary_union([g3[i] for i in v]) for c, v in groups.items()}

# counties: mutual best matches keep the earlier unit
ho2, go2 = shapes(o2)
import shapely
def best_in(g, geoms, tree):
    s = [(g.intersection(geoms[j]).area, int(j)) for j in tree.query(g, predicate='intersects')]
    return max(s)[1] if s else None
t2 = shapely.STRtree(go2)
fwd = {c: best_in(g, go2, t2) for c, g in gg.items()}
gl = list(gg.items()); glg = [g for _, g in gl]; tg = shapely.STRtree(glg)
back = {j: gl[b][0] for j in range(len(go2)) if not go2[j].is_empty for b in [best_in(go2[j], glg, tg)] if b is not None}
cname = {}
for g_, r in cs.items(): cname.setdefault(g_[:5], r['NAMELSADCO'])
# a county the area match missed (the earlier shapes are coarse: an independent city lies mostly in its old neighbour)
# keeps the earlier county of its own name nearby, if no other county kept that one
import re
def plain(n): return re.sub(r"\s+(County|Parish|city|City|Borough|Census Area|City and Borough|Municipality)$", "", n).strip().lower()
kept_j = {j for c, j in fwd.items() if j is not None and back.get(j) == c}
oldname = collections.defaultdict(list)
for j, u in enumerate(ho2['u']): oldname[plain(u['n'])].append(j)
for c, g in gg.items():
    j = fwd[c]
    if j is not None and back.get(j) == c: continue
    near = [k for k in oldname.get(plain(cname[c]), []) if k not in kept_j and not go2[k].is_empty
            and go2[k].distance(g) < 0.5]
    if len(near) == 1: fwd[c] = near[0]; back[near[0]] = c; kept_j.add(near[0])
units2, newc = [], []
for c in sorted(gg, key=lambda c: cname[c]):
    j = fwd[c]
    if j is not None and back.get(j) == c:
        # the earlier id, the Census name (Connecticut's planning regions matched to its old counties by area)
        units2.append({'id': ho2['u'][j]['id'], 'n': cname[c], 'c': c})
    else:
        units2.append({'id': 'US2-' + c, 'n': cname[c], 'c': c}); newc.append((c, cname[c]))
id2 = {u['c']: u['id'] for u in units2}
for u in h3['u']: u['p'] = id2[u['c'][:5]]
write(os.path.join(outd, 'us-3.wyar'), h3, a3)
skel = os.path.join(outd, '_skel.wyar')
write(skel, {'t': h3['t'], 'u': units2, 'o': [[] for _ in units2], 'f': 1}, [])
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'us-3.wyar'), skel,
                os.path.join(outd, 'us-2.wyar')], check=True)
os.remove(skel)

# states: the earlier units, by the larger share of area
ho1, go1 = shapes(o1)
st = collections.defaultdict(list)
for c, g in gg.items(): st[c[:2]].append(g)
# by the state's name (the Census file names it), else by area
sname = {g_[:2]: r['STATE_NAME'] for g_, r in cs.items()}
byname = {u['n']: u['id'] for u in ho1['u']}
t1 = shapely.STRtree(go1)
m1 = {}
for s_, v in st.items():
    if sname.get(s_) in byname: m1[s_] = byname[sname[s_]]
    else:
        b_ = best_in(unary_union(v), go1, t1)
        m1[s_] = ho1['u'][b_]['id'] if b_ is not None else None
missing_states = [s_ for s_, v in m1.items() if v is None]
h2, a2, _ = read(os.path.join(outd, 'us-2.wyar'))
for u in h2['u']: u['p'] = m1[u['c'][:2]]
write(os.path.join(outd, 'us-2.wyar'), h2, a2)
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'us-2.wyar'), o1,
                os.path.join(outd, 'us-1.wyar')], check=True)
h1, a1, _ = read(os.path.join(outd, 'us-1.wyar'))
for u in h1['u']: u.pop('p', None)
write(os.path.join(outd, 'us-1.wyar'), h1, a1)

# the earlier counties that are not kept, each to the new county holding most of its area
kept = {u['id'] for u in units2}
with open(os.path.join(outd, 'us-2-moves.tsv'), 'w', encoding='utf-8') as f:
    f.write('old\tnew\told name\tnew name\tshare\n')
    for u, g in zip(ho2['u'], go2):
        if u['id'] in kept or g.is_empty: continue
        s = sorted(((g.intersection(glg[int(j)]).area, gl[int(j)][0]) for j in tg.query(g, predicate='intersects')), reverse=True)
        if not s: f.write(f"{u['id']}\t\t{u['n']}\t\t0\n"); continue
        a, c = s[0]
        nu = next(x for x in units2 if x['c'] == c)
        f.write(f"{u['id']}\t{nu['id']}\t{u['n']}\t{nu['n']}\t{a / g.area:.2f}\n")
print({'states with no match': missing_states, 'subdivisions': len(h3['u']), 'counties': len(units2), 'states': len(h1['u']), 'new counties': newc,
       'states matched twice': [s for s, n in collections.Counter(m1.values()).items() if n > 1]})

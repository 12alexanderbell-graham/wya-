#!/usr/bin/env python3
"""D2, Germany's levels from one set of borders: the municipalities (BKG VG250, Gemeinden, as de-4 by d2_level.py
--code-ids) carry their official key (AGS); each one's district is its AGS's first five digits, its NUTS-2 region its
NUTS code's first four characters, its Land the AGS's first two digits. The coarser levels are dissolved from the
municipalities' arcs (d2_dissolve), so every level shares the same lines.

- districts (level 3): the current ones from VG250_KRS (401), ids `DE3-<AGS>`; the earlier file's 428 included
  districts merged since, so `de-3-moves.tsv` gives each earlier id the new district holding most of its area;
- NUTS-2 regions (level 2) and Länder (level 1): the earlier units, ids and names kept, each matched to the
  municipalities' groups by the larger share of area.

usage: d2_ags.py de-4.wyar gem.csv krs.csv OLD_de-3.wyar OLD_de-2.wyar OLD_de-1.wyar OUT_DIR
  gem.csv: AGS,NUTS of every land municipality (VG250_GEM, GF 4); krs.csv: AGS,GEN,BEZ,NUTS of every district
"""
import csv, collections, os, sys, subprocess
sys.path.insert(0, os.path.dirname(__file__))
from wyar import read, write
from shapely.geometry import Polygon
from shapely.ops import unary_union

f4, gemcsv, krscsv, o3, o2, o1, outd = sys.argv[1:8]
os.makedirs(outd, exist_ok=True)
P = os.path.dirname(os.path.abspath(__file__))
nuts = {r['AGS']: r['NUTS'] for r in csv.DictReader(open(gemcsv, encoding='utf-8'))}
krs = list(csv.DictReader(open(krscsv, encoding='utf-8')))

def shapes(path):
    h, arcs, _ = read(path)
    sx, sy, tx, ty = h['t']
    def rp(r):
        pts = []
        for i in r: pts += arcs[i] if i >= 0 else arcs[~i][::-1]
        return [(x * sx + tx, y * sy + ty) for x, y in pts]
    def eo(o):
        # even-odd: a ring inside another is a hole (Berlin inside Brandenburg)
        g = Polygon()
        for r in o:
            pts = rp(r)
            if len(pts) >= 3: g = g.symmetric_difference(Polygon(pts).buffer(0))
        return g
    return h, [eo(o) for o in h['o']]

h4, a4, _ = read(f4)
_, g4 = shapes(f4)

def best_match(groups, old_path):
    """each group (key -> member shapes' union) to the earlier unit holding most of it; one earlier unit per group"""
    ho, go = shapes(old_path)
    out = {}
    for k, g in groups.items():
        share = [(g.intersection(o).area, j) for j, o in enumerate(go) if o.intersects(g)]
        out[k] = ho['u'][max(share)[1]] if share else None
    used = collections.Counter(u['id'] for u in out.values() if u)
    return ho, out, [i for i, n in used.items() if n > 1]

# level 3: the current districts
for u in h4['u']: u['p'] = 'DE3-' + u['c'][:5]
write(os.path.join(outd, 'de-4.wyar'), h4, a4)
# a name two districts share (Karlsruhe the city and the district around it) takes its kind, as the earlier file did
twice = {n for n, c in collections.Counter(r['GEN'] for r in krs).items() if c > 1}
units3 = [{'id': 'DE3-' + r['AGS'], 'n': r['GEN'] + (', ' + r['BEZ'] if r['GEN'] in twice else ''), 'c': r['AGS']}
          for r in sorted(krs, key=lambda r: r['GEN'])]
skel = os.path.join(outd, '_skel.wyar')
write(skel, {'t': h4['t'], 'u': units3, 'o': [[] for _ in units3], 'f': 1}, [])
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'de-4.wyar'), skel,
                os.path.join(outd, 'de-3.wyar')], check=True)

# level 2: NUTS-2 regions, the earlier units kept
by2 = collections.defaultdict(list)
for k, u in enumerate(h4['u']): by2[nuts[u['c']][:4]].append(k)
ho2, m2, twice2 = best_match({k: unary_union([g4[i] for i in v]) for k, v in by2.items()}, o2)
h3, a3, _ = read(os.path.join(outd, 'de-3.wyar'))
k3to2 = {}
for k, v in by2.items():
    for i in v: k3to2['DE3-' + h4['u'][i]['c'][:5]] = m2[k]['id']
for u in h3['u']: u['p'] = k3to2[u['id']]
write(os.path.join(outd, 'de-3.wyar'), h3, a3)
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'de-3.wyar'), o2,
                os.path.join(outd, 'de-2.wyar')], check=True)

# level 1: the Länder, the earlier units kept
by1 = collections.defaultdict(list)
for k, u in enumerate(h4['u']): by1[u['c'][:2]].append(k)
ho1, m1, twice1 = best_match({k: unary_union([g4[i] for i in v]) for k, v in by1.items()}, o1)
k2to1 = {}
for k, v in by1.items():
    for i in v: k2to1[k3to2['DE3-' + h4['u'][i]['c'][:5]]] = m1[k]['id']
h2, a2, _ = read(os.path.join(outd, 'de-2.wyar'))
for u in h2['u']: u['p'] = k2to1[u['id']]
write(os.path.join(outd, 'de-2.wyar'), h2, a2)
subprocess.run([sys.executable, os.path.join(P, 'd2_dissolve.py'), os.path.join(outd, 'de-2.wyar'), o1,
                os.path.join(outd, 'de-1.wyar')], check=True)
h1, a1, _ = read(os.path.join(outd, 'de-1.wyar'))
for u in h1['u']: u.pop('p', None)
write(os.path.join(outd, 'de-1.wyar'), h1, a1)

# the earlier districts' ids, each to the new district of the same name in the same Land when there is one (the earlier
# file also held the districts' water and sea parts as units of their own), else to the one holding most of its area
ho3, go3 = shapes(o3)
_, gn3 = shapes(os.path.join(outd, 'de-3.wyar'))
def plain(n): return n.replace(', Kreisfreie Stadt', '').replace(' (DE)', '').strip().lower()
byname = collections.defaultdict(list)
for j, u in enumerate(h3['u']): byname[plain(u['n'])].append(j)
with open(os.path.join(outd, 'de-3-moves.tsv'), 'w', encoding='utf-8') as f:
    f.write('old\tnew\told name\tnew name\tshare\n')
    for u, g in zip(ho3['u'], go3):
        share = sorted(((g.intersection(n).area, j) for j, n in enumerate(gn3) if n.intersects(g)), reverse=True)
        named = byname.get(plain(u['n']), [])
        if len(named) > 1 and share:
            near = [j for j in named if gn3[j].distance(g) < 0.5]
            named = near[:1] if near else []
        # a shared name is only trusted where that district holds most of the earlier one (Leipzig the rural
        # district is not Leipzig the city)
        if len(named) == 1 and share and (gn3[named[0]].intersection(g).area / g.area) < 0.5:
            named = []
        if len(named) == 1:
            j = named[0]
            f.write(f"{u['id']}\t{h3['u'][j]['id']}\t{u['n']}\t{h3['u'][j]['n']}\tname\n"); continue
        if not share: f.write(f"{u['id']}\t\t{u['n']}\t\t0\n"); continue
        a, j = share[0]
        f.write(f"{u['id']}\t{h3['u'][j]['id']}\t{u['n']}\t{h3['u'][j]['n']}\t{a / g.area:.2f}\n")
os.remove(skel)
print({'municipalities': len(h4['u']), 'districts': len(h3['u']), 'nuts2': len(h2['u']), 'laender': len(h1['u']),
       'nuts2 matched twice': twice2, 'laender matched twice': twice1})

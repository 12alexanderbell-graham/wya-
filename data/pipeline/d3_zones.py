#!/usr/bin/env python3
"""D3, TOWNS FOLLOW THE VIEW: which towns lie in each item of the map a borders view can move, for town-zones.json
(the old app's TownZones: item -> file -> town keys). Items: every disputed piece ("p:<name>", the world file's
"piece:<name>" units) and the places a view can give away or merge ("o:<id>"). A town is in an item when its point is
inside the item's outline in the world file (Equal Earth, as the app draws it).

usage: d3_zones.py WORLD.wyam WORLD-META.json TOWNS_DIR OLD_ZONES.json OUT_ZONES.json [--only-new OLD_TOWNS_DIR]
  without --only-new: every town; with it, the old file's memberships are kept as they were and only towns that are
  not in the old towns files are added (the merge never re-keys or moves an old town).
"""
import json, math, struct, sys, glob, os, zlib, collections
import numpy as np
from matplotlib.path import Path

wyam, metaf, towns_dir, old_zones_f, out_f = sys.argv[1:6]
only_new = '--only-new' in sys.argv
old_towns_dir = sys.argv[sys.argv.index('--only-new') + 1] if only_new else None

A1, A2, A3, A4 = 1.340264, -0.081106, 0.000893, 0.003796
M = math.sqrt(3) / 2
def raw(lon, lat):
    l = math.radians(lon); p = math.radians(lat)
    th = math.asin(M * math.sin(p)); t2 = th * th; t6 = t2 * t2 * t2
    return (l * math.cos(th) / (M * (A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2))),
            th * (A1 + A2 * t2 + t6 * (A3 + A4 * t2)))
RX = raw(180, 0)[0]; RY = raw(0, 90)[1]; S = 1000 / (2 * RX)
def project(lon, lat):
    x, y = raw(lon, lat); return ((x + RX) * S, (RY - y) * S)

meta = json.load(open(metaf)); keys = meta['unitKeys']
b = open(wyam, 'rb').read(); o = 4
o += 4; o += 8
nu, = struct.unpack_from('<I', b, o); o += 4
o += 2 * nu
nr, = struct.unpack_from('<I', b, o); o += 4
unit_rings = collections.defaultdict(list)
for _ in range(nr):
    u, = struct.unpack_from('<H', b, o); o += 2
    n, = struct.unpack_from('<I', b, o); o += 4
    pts = np.frombuffer(b, dtype='<f4', count=2 * n, offset=o).reshape(-1, 2).astype(float); o += 8 * n
    if u != 0xFFFF: unit_rings[u].append(pts)

old_zones = json.load(open(old_zones_f))
oitems = {k[2:] for k in old_zones['items'] if k.startswith('o:')}
items = {}
for u, k in enumerate(keys):
    if k.startswith('piece:'): items['p:' + k[6:]] = unit_rings[u]
    elif k.split('|')[0] in oitems or k.startswith('x-'):
        items.setdefault('o:' + k.split('|')[0], []).extend(unit_rings[u])

def rd(p): return json.loads(zlib.decompress(open(p, 'rb').read(), -15))
old_keys = set()
if only_new:
    for f in glob.glob(os.path.join(old_towns_dir, 'towns-*.wyat')):
        cc = os.path.basename(f)[6:-5]
        for r in rd(f): old_keys.add(f'{cc}/{r[6]}' if r[6] else f'{cc}/{r[0]}')

towns = []
for f in sorted(glob.glob(os.path.join(towns_dir, 'towns-*.wyat'))):
    cc = os.path.basename(f)[6:-5]
    for r in rd(f):
        key = f'{cc}/{r[6]}' if r[6] else f'{cc}/{r[0]}'
        if only_new and key in old_keys: continue
        towns.append((cc, key, project(r[4], r[3])))
P = np.array([t[2] for t in towns]) if towns else np.zeros((0, 2))

found = collections.defaultdict(lambda: collections.defaultdict(list))
for item, rings in items.items():
    inside = np.zeros(len(P), dtype=bool)
    for ring in rings:
        if len(ring) < 3: continue
        lo = ring.min(0); hi = ring.max(0)
        box = (P[:, 0] >= lo[0]) & (P[:, 0] <= hi[0]) & (P[:, 1] >= lo[1]) & (P[:, 1] <= hi[1])
        if not box.any(): continue
        idx = np.nonzero(box)[0]
        hit = Path(ring).contains_points(P[idx])
        inside[idx[hit]] ^= True  # even-odd: a hole's ring takes its towns back out
    for i in np.nonzero(inside)[0]:
        cc, key, _ = towns[i]
        found[item][cc].append(key)

# the world file's outlines are coarser than the towns: a town just over a border can fall inside the neighbour's
# item (Chinese towns on the Yalu inside North Korea's outline), and no distance from the edge tells a slip from a
# real town in a narrow piece (Majdal Shams is 0.02 units inside the Golan). So an item keeps only the towns of the
# files that can hold it: the files its old zones had; for a disputed piece, the sides of the dispute
# (disputes.json: its options, host and controller); for a place, its own file and the file most of its towns are in
disputes = {d['id']: d for d in json.load(open(os.path.join(os.path.dirname(metaf), 'disputes.json')))['list']}
dropped = collections.Counter()
for item, files in found.items():
    allowed = set(old_zones['items'].get(item, {}))
    if item.startswith('p:') and item[2:] in disputes:
        d = disputes[item[2:]]
        allowed |= set(d.get('options') or []) | {d.get('host'), d.get('controller')}
    else:
        # a place drawn apart whose towns GeoNames files under another country
        HOST = {'x-akrotiri': 'gb', 'x-dhekelia': 'gb', 'x-athos': 'gr', 'x-rapa': 'cl', 'x-abk': 'ge', 'x-sos': 'ge',
                'x-pmr': 'md', 'x-som': 'so', 'x-ncy': 'cy'}
        allowed |= {item[2:], HOST.get(item[2:]), max(files, key=lambda f: len(files[f]))}
    for f in list(files):
        if f not in allowed:
            dropped[f'{item} {f}'] += len(files[f]); del files[f]
print('left out as border slips:', dict(dropped), file=sys.stderr)

out = {'v': 1, 'capitals': old_zones.get('capitals', {}), 'items': {}}
if only_new:
    for item, files in old_zones['items'].items():
        out['items'][item] = {f: list(k) for f, k in files.items()}
for item, files in found.items():
    for f, ks in files.items():
        have = out['items'].setdefault(item, {}).setdefault(f, [])
        for k in ks:
            if k not in have: have.append(k)
json.dump(out, open(out_f, 'w'), ensure_ascii=False, separators=(',', ':'))
print(json.dumps({it: {f: len(k) for f, k in fs.items()} for it, fs in sorted(found.items())}, ensure_ascii=False))

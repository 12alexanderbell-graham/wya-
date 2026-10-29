# The world map's own outlines of the same places (world.wyam v2), redrawn from the same fine geometry as the
# detailed tiles (truth.pkl), simplified to the world map's detail, so the line does not jump when the map hands
# over from the world to the 500 m tiles.
#   python3 worldfix.py <in world.wyam> <world-meta.json> <out world.wyam>
import sys, struct, json, math, pickle
import numpy as np
from shapely.geometry import Polygon, LineString, Point
from shapely.ops import unary_union, transform
from shapely import STRtree
import rebuild as R

A1, A2, A3, A4 = 1.340264, -0.081106, 0.000893, 0.003796
M = math.sqrt(3) / 2
def raw(lon, lat):
    lam = np.radians(lon); phi = np.radians(lat)
    th = np.arcsin(M * np.sin(phi)); t2 = th * th; t6 = t2 ** 3
    x = lam * np.cos(th) / (M * (A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2)))
    y = th * (A1 + A2 * t2 + t6 * (A3 + A4 * t2))
    return x, y
RX = raw(180.0, 0.0)[0]; RY = raw(0.0, 90.0)[1]; S = 1000 / (2 * RX)
def proj(lon, lat):
    x, y = raw(np.asarray(lon), np.asarray(lat)); return (x + RX) * S, (RY - y) * S

src, metap, dst = sys.argv[1:4]
metaout = sys.argv[4] if len(sys.argv) > 4 else None
b = open(src, 'rb').read()
assert b[:4] == b'WYAM' and struct.unpack_from('<I', b, 4)[0] == 2
W, H = struct.unpack_from('<ff', b, 8); o = 16
nu = struct.unpack_from('<I', b, o)[0]; o += 4
owners = list(struct.unpack_from('<%dH' % nu, b, o)); o += 2 * nu
nr = struct.unpack_from('<I', b, o)[0]; o += 4
rings = []
for _ in range(nr):
    u, n = struct.unpack_from('<HI', b, o); o += 6
    f = struct.unpack_from('<%df' % (2 * n), b, o); o += 8 * n
    rings.append([u, [(f[2 * i], f[2 * i + 1]) for i in range(n)]])
ns = struct.unpack_from('<I', b, o)[0]; o += 4
segs = [list(struct.unpack_from('<8f', b, o + 32 * i)) for i in range(ns)]
keys = json.load(open(metap))['unitKeys']
assert len(keys) == nu
ui = {k: i for i, k in enumerate(keys)}
meta = json.load(open(metap))
pidx = {p['id']: i for i, p in enumerate(meta['places'])}
disp = {d['id']: d for d in json.load(open(sys.argv[5]))['list']} if len(sys.argv) > 5 else {}
def wk(k): return k[2:] if k.startswith('o:') else 'piece:' + k[2:]

T = pickle.load(open('truth.pkl', 'rb'))['groups']
# pieces new to the data (Sool, Moroccan-held Western Sahara): a unit of their own, its base owner its controller
for gname, (parents, children) in T.items():
    for k, _ in children:
        if wk(k) not in ui:
            d = disp.get(k[2:], {})
            owners.append(pidx.get(d.get('controller') or d.get('default'), 65535))
            ui[wk(k)] = len(keys); keys.append(wk(k)); nu += 1
            meta['unitKeys'].append(wk(k))
            if 'unitConts' in meta: meta['unitConts'].append([d.get('side') or 'Africa'])
            meta.setdefault('pieceConts', {})[wk(k)] = {o: [d.get('side') or 'Africa'] for o in d.get('options', [])}
            print('new unit', wk(k), owners[-1])
TOL = 0.004   # map units (one is about 40 km): about 160 m, finer than the world map's own lines
SLIV = 0.01
for gname, (parents, children) in T.items():
    gu = [ui[wk(k)] for k in parents + [k for k, _ in children] if wk(k) in ui]
    gset = set(gu)
    old = {}
    for u in gu:
        g = R.geo_of([pts for uu, pts in rings if uu == u])
        if not g.is_empty: old[u] = g
    if not old: continue
    ch = []
    for k, fine in children:
        if wk(k) not in ui: continue
        pf = transform(lambda x, y, z=None: proj(x, y), fine).simplify(TOL / 4)
        ch.append((ui[wk(k)], pf))
    ps = [ui[wk(k)] for k in parents if wk(k) in ui]
    R.Q = 1e-6
    new = R.partition(old, ps, ch, SLIV)
    new = {u: g.simplify(TOL) for u, g in new.items()}
    # rings
    rings = [r for r in rings if r[0] not in gset]
    for u, g in new.items():
        for rg in R.rings_of(g): rings.append([u, rg])
    # lines
    cands = [u for u, g in new.items() if not g.is_empty]
    parts, pk = [], []
    for u in cands:
        for p in R.polys(new[u]): parts.append(p); pk.append(u)
    tree = STRtree(parts)
    out = []
    for s in segs:
        ua, ub = int(s[6]), int(s[7])
        ain = ua in gset; bin_ = ub != 65535 and ub >= 0 and ub in gset and s[5] > 0
        if not ain and not bin_: out.append(s); continue
        if ain and bin_: continue
        m = Point((s[0] + s[2]) / 2, (s[1] + s[3]) / 2)
        o2 = pk[int(tree.query_nearest(m)[0])]
        s = s[:]
        if ain: s[6] = float(o2)
        else: s[7] = float(o2)
        out.append(s)
    for ii, i in enumerate(cands):
        for j in cands[ii + 1:]:
            gi, gj = new[i], new[j]
            if gi.distance(gj) > 1e-5: continue
            for l in R.lines_of(gi.boundary.intersection(gj.boundary)):
                dist = 0.0
                for a, c in zip(l, l[1:]):
                    L = math.hypot(c[0] - a[0], c[1] - a[1])
                    if L == 0: continue
                    out.append([a[0], a[1], c[0], c[1], dist, 2.0, float(i), float(j)]); dist += L
    segs = out
    print(gname, {keys[u]: round(g.area, 3) for u, g in new.items()})

ob = bytearray(b'WYAM'); ob += struct.pack('<I', 2); ob += struct.pack('<ff', W, H)
ob += struct.pack('<I', nu)
for w in owners: ob += struct.pack('<H', w)
ob += struct.pack('<I', len(rings))
for u, p in rings:
    ob += struct.pack('<HI', u, len(p)); ob += struct.pack('<%df' % (2 * len(p)), *[c for q in p for c in q])
ob += struct.pack('<I', len(segs))
for s in segs: ob += struct.pack('<8f', *s)
open(dst, 'wb').write(ob)
if metaout: json.dump(meta, open(metaout, 'w'), ensure_ascii=False)
print('rings', len(rings), 'segs', len(segs), 'bytes', len(ob))

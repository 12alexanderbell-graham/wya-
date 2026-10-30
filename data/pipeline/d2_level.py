#!/usr/bin/env python3
"""D2. A FINER LEVEL from geoBoundaries' TopoJSON into the app's region file (<cc>-<lvl>.wyar: "WYAR", u32 1, u32 n,
n bytes of JSON {t: [sx, sy, tx, ty], u: [{id, n, c}], o: per unit its rings as arc indices (~i reversed), f}, u32 arcs,
their starts, then every point as absolute quantized int32 x, y; raw DEFLATE). The arcs are shared, so simplifying
each arc once (Douglas-Peucker, ends kept) keeps neighbours' borders on one line.

usage: d2_level.py SOURCE.topojson CC LEVEL OUT.wyar TOLERANCE_DEG [lon0 lat0 lon1 lat1]
  the box keeps only units whose middle is inside it (France's communes without its overseas places, which are
  places of their own on the map)
"""
import json, sys, math
sys.path.insert(0, __import__('os').path.dirname(__file__))
from wyar import write

src, cc, lvl, out, tol = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], float(sys.argv[5])
box = list(map(float, sys.argv[6:10])) if len(sys.argv) >= 10 else None
t = json.load(open(src))
sx, sy = t['transform']['scale']; tx, ty = t['transform']['translate']
arcs = []
for a in t['arcs']:
    x = y = 0; pts = []
    for dx, dy in a: x += dx; y += dy; pts.append((x, y))
    arcs.append(pts)
geoms = list(t['objects'].values())[0]['geometries']

def rings_of(g):
    if g['type'] == 'Polygon': return g['arcs']
    if g['type'] == 'MultiPolygon': return [r for p in g['arcs'] for r in p]
    return []
def ring_pts(r):
    pts = []
    for i in r: pts += arcs[i] if i >= 0 else arcs[~i][::-1]
    return pts

keep = []
for g in geoms:
    rs = rings_of(g)
    if not rs: continue
    p = [q for r in rs for q in ring_pts(r)]
    lon = sum(q[0] for q in p) / len(p) * sx + tx; lat = sum(q[1] for q in p) / len(p) * sy + ty
    if box and not (box[0] <= lon <= box[2] and box[1] <= lat <= box[3]): continue
    keep.append((g['properties'].get('shapeName', ''), g['properties'].get('shapeISO', '') or '', rs))
keep.sort(key=lambda k: k[0])

# Douglas-Peucker per arc in quantized units; a ring made of a single arc keeps at least 4 points
def dp(pts, eps):
    if len(pts) <= 2: return pts
    stack = [(0, len(pts) - 1)]; keepi = {0, len(pts) - 1}
    while stack:
        a, b = stack.pop()
        (x1, y1), (x2, y2) = pts[a], pts[b]
        dx, dy = x2 - x1, y2 - y1; L = math.hypot(dx, dy)
        best, bi = -1, -1
        for i in range(a + 1, b):
            x, y = pts[i]
            d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / L if L else math.hypot(x - x1, y - y1)
            if d > best: best, bi = d, i
        if best > eps: keepi.add(bi); stack += [(a, bi), (bi, b)]
    return [pts[i] for i in sorted(keepi)]
used = sorted({(i if i >= 0 else ~i) for _, _, rs in keep for r in rs for i in r})
single = {(r[0] if r[0] >= 0 else ~r[0]) for _, _, rs in keep for r in rs if len(r) == 1}
eps = tol / ((sx + sy) / 2)
new_index = {}; out_arcs = []
for i in used:
    s = dp(arcs[i], eps)
    if i in single and len(s) < 4:
        n = len(arcs[i]); s = [arcs[i][k] for k in sorted({0, n // 3, 2 * n // 3, n - 1})] if n >= 4 else arcs[i]
    new_index[i] = len(out_arcs); out_arcs.append(s)
def remap(i): return new_index[i] if i >= 0 else ~new_index[~i]
prefix = cc.upper() if len(cc) == 2 else cc
units = [{'id': f'{"FRA" if cc == "fr" else prefix}{lvl}{k + 1}', 'n': n, 'c': c} for k, (n, c, _) in enumerate(keep)]
o = [[[remap(i) for i in r] for r in rs] for _, _, rs in keep]
write(out, {'t': [sx, sy, tx, ty], 'u': units, 'o': o, 'f': 1}, out_arcs)
pts = sum(len(a) for a in out_arcs)
print(json.dumps({'units': len(units), 'arcs': len(out_arcs), 'points': pts, 'source points': sum(len(arcs[i]) for i in used)}))

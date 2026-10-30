# Time zones by point (BUILD-BOOK Part 17.4 D13): timezone-boundary-builder's zones (release 2025b, timezones.geojson,
# ODbL, from OpenStreetMap), simplified (0.002 degrees, about 200 m; small pieces such as Baarle's enclaves at 0.0003)
# and packed for the app: names, then each polygon's rings as zigzag varint deltas on a 1e-4 degree grid, the whole
# raw-deflated. Read by Store/TimeZones.swift (`zone(lat:lon:)`).
#   python3 tz-pack.py combined.json timezones.wytz
import sys, json, struct, zlib
from shapely.geometry import shape
from shapely import simplify, make_valid
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
names = sorted({f['properties']['tzid'] for f in d['features']})
zi = {n: i for i, n in enumerate(names)}
out = bytearray(b'WYTZ' + struct.pack('<II', 1, len(names)))
for n in names:
    b = n.encode(); out += struct.pack('<B', len(b)) + b
polys = []
for f in d['features']:
    g = make_valid(shape(f['geometry']))
    for p in getattr(g, 'geoms', [g]):
        if p.geom_type != 'Polygon' or p.is_empty: continue
        tol = 0.0003 if p.area < 0.05 else 0.002
        q = simplify(p, tol, preserve_topology=True)
        for r in getattr(q, 'geoms', [q]):
            if r.geom_type == 'Polygon' and not r.is_empty:
                polys.append((zi[f['properties']['tzid']], [list(r.exterior.coords)[:-1]] + [list(h.coords)[:-1] for h in r.interiors]))
out += struct.pack('<I', len(polys))
px = py = 0
def v(z):
    z = (z << 1) ^ (z >> 63)
    while True:
        b = z & 0x7f; z >>= 7
        if z: out.append(b | 0x80)
        else: out.append(b); return
nv = 0
for z, rings in polys:
    rings = [r for r in rings if len(r) >= 3]
    out += struct.pack('<HH', z, len(rings))
    for r in rings:
        out += struct.pack('<I', len(r))
        for x, y in r:
            qx, qy = round(x * 1e4), round(y * 1e4)
            v(qx - px); v(qy - py); px, py = qx, qy; nv += 1
co = zlib.compressobj(9, zlib.DEFLATED, -15)
blob = co.compress(bytes(out)) + co.flush()
open(dst, 'wb').write(blob)
print(len(names), 'zones', len(polys), 'polygons', nv, 'points', len(out), 'bytes raw', len(blob), 'packed')

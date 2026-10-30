#!/usr/bin/env python3
"""One topology per country per level, in the app's own format.

Each country is drawn on its own, full width, so detail is set by THAT COUNTRY'S extent, not
by a single world-wide percentage: Germany's sixteen Länder need more vertices per kilometre
than Russia's eighty-three federal subjects, because on screen they are the same size.
mapshaper's own resolution= does this, but it measures the bounding box, and Russia's box is
360 degrees wide because Chukotka sits past the antimeridian - which collapsed Russia into
stripes. So the extent is measured here, with the antimeridian unwrapped, and passed as an
interval in degrees."""
import json, glob, os, subprocess, sys, math, collections, shutil

LVL  = sys.argv[1] if len(sys.argv) > 1 else 'ADM1'
CELL = float(sys.argv[2]) if len(sys.argv) > 2 else 1400.0   # target cells across the screen
RAW  = '/home/claude/gb/raw'
TMP  = '/home/claude/gb/tmp-' + LVL
OUT  = '/home/claude/gb/out-' + LVL
for d in (TMP, OUT):
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)

# what this level is CALLED in this country: Region, Land, Prefecture, Canton, State
CANON = {}
for x in json.load(open('/home/claude/gb/catalogue.json')):
    if x['boundaryType'] == LVL:
        c = (x.get('boundaryCanonical') or '').strip()
        if c and c.lower() not in ('unknown', 'nan', 'none') and len(c) < 40:
            CANON[x['boundaryISO']] = c
app = json.load(open('/home/claude/work/reference/run/redo/src/mapdata/countries.json'))
by_a3 = {c['a3']: c['id'] for c in app if c.get('a3')}
HAND = {'XKX':'xk', 'ESH':'eh', 'PSE':'ps', 'TWN':'tw', 'HKG':'hk', 'MAC':'mo'}

import re as _re
_MOJI = _re.compile(r'[\u00c3\u00c2][\x80-\u00ff]')
def repair(t):
    """three of geoBoundaries' files are double-encoded; this puts the names back"""
    if not t or not _MOJI.search(t): return t
    for _ in range(3):
        try: u = t.encode('latin-1').decode('utf-8')
        except Exception: break
        if u == t: break
        t = u
        if not _MOJI.search(t): break
    return t

def coords(geom):
    t = geom['type']
    if t == 'Polygon':
        for ring in geom['coordinates']:
            for p in ring: yield p
    elif t == 'MultiPolygon':
        for poly in geom['coordinates']:
            for ring in poly:
                for p in ring: yield p

def extent(feats):
    lons, lats = [], []
    for ft in feats:
        for x, y in coords(ft['geometry']): lons.append(x); lats.append(y)
    if not lons: return 1.0, 1.0
    west = [x for x in lons if x < -120]; east = [x for x in lons if x > 120]
    if west and east: lons = [x + 360 if x < 0 else x for x in lons]   # unwrap the antimeridian
    spanx = max(lons) - min(lons); spany = max(lats) - min(lats)
    mid = (max(lats) + min(lats)) / 2
    return max(spanx * math.cos(math.radians(mid)), 1e-4), max(spany, 1e-4)

index, stats, fails = {}, [], []
for f in sorted(glob.glob('%s/*-%s.geojson' % (RAW, LVL))):
    iso3 = os.path.basename(f).split('-')[0]
    cid  = by_a3.get(iso3) or HAND.get(iso3)
    if not cid: fails.append(iso3 + ' no app country'); continue
    g = json.load(open(f, encoding='utf-8'))
    feats = [ft for ft in g.get('features', []) if ft.get('geometry')]
    if not feats: continue
    feats.sort(key=lambda ft: ((ft['properties'].get('shapeName') or '').lower(),
                               ft['properties'].get('shapeID') or ''))
    rows = []
    for i, ft in enumerate(feats, 1):
        p = ft['properties']
        rid = '%s%s%d' % (iso3, LVL[3], i)
        ft['properties'] = {'rid': rid}
        rec = {'id': rid, 'n': repair((p.get('shapeName') or '').strip()) or ('Unit %d' % i)}
        c = repair((p.get('shapeISO') or '').strip())
        if c and c.lower() not in ('none', 'nan'): rec['c'] = c
        rows.append(rec)
    sx, sy = extent(feats)
    interval = max(sx, sy) / CELL
    src = '%s/%s.geojson' % (TMP, iso3)
    json.dump({'type':'FeatureCollection','features':feats}, open(src, 'w'), ensure_ascii=False)
    dst = '%s/%s.json' % (TMP, iso3)
    r = subprocess.run(['mapshaper', src, '-simplify', 'interval=%.8f' % interval,
                        'keep-shapes', 'planar', '-o', 'format=topojson',
                        'quantization=200000', 'id-field=rid', 'drop-table', dst],
                       capture_output=True, text=True)
    if r.returncode or not os.path.exists(dst):
        fails.append(iso3 + ' mapshaper: ' + (r.stderr or '')[:100]); continue
    t = json.load(open(dst))
    lay = list(t['objects'].values())[0]
    objs = {}
    for geo in lay.get('geometries', []):
        rid = geo.get('id')
        # mapshaper writes a null geometry for a shape simplification emptied out
        if rid and geo.get('arcs') and geo.get('type') in ('Polygon', 'MultiPolygon'):
            objs[rid] = {'type': geo['type'], 'arcs': geo['arcs']}
    rows = [r for r in rows if r['id'] in objs]     # a unit with no geometry is not a unit
    pack = {'transform': t['transform'], 'arcs': t['arcs'], 'objects': objs, 'units': rows}
    payload = json.dumps(pack, separators=(',', ':'), ensure_ascii=False)
    js = 'REGIONPUT(%s,%d,%s);\n' % (json.dumps(cid), int(LVL[3]), payload)
    op = '%s/%s-%s.js' % (OUT, cid, LVL[3])
    open(op, 'w').write(js)
    index[cid] = {'n': len(rows), 'k': CANON.get(iso3, '')}
    stats.append((cid, len(rows), os.path.getsize(op)))
    os.remove(src); os.remove(dst)

json.dump(index, open('/home/claude/gb/index-%s.json' % LVL, 'w'), ensure_ascii=False)
tot = sum(s[2] for s in stats)
print('%s: %d countries, %d units, %.1f MB total, biggest:' % (
      LVL, len(stats), sum(s[1] for s in stats), tot/1048576))
for c, n, b in sorted(stats, key=lambda s: -s[2])[:8]: print('   %-6s %5d units %7.0f KB' % (c, n, b/1024))
if fails: print('FAILED:', fails[:10], len(fails))

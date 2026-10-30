#!/usr/bin/env python3
"""One GeoJSON of every ADM1 unit on earth, with a short stable id, ready for mapshaper."""
import json, glob, os, sys, collections
LVL = sys.argv[1] if len(sys.argv) > 1 else 'ADM1'
app = json.load(open('/home/claude/work/reference/run/redo/src/mapdata/countries.json'))
by_a3 = {c['a3']: c['id'] for c in app if c.get('a3')}
HAND = {'XKX':'xk', 'ESH':'eh', 'PSE':'ps', 'TWN':'tw', 'HKG':'hk', 'MAC':'mo'}
out, index, nomatch = [], collections.defaultdict(list), collections.Counter()
for f in sorted(glob.glob('/home/claude/gb/raw/*-%s.geojson' % LVL)):
    iso3 = os.path.basename(f).split('-')[0]
    cid = by_a3.get(iso3) or HAND.get(iso3)
    if not cid: nomatch[iso3] += 1
    g = json.load(open(f, encoding='utf-8'))
    feats = [ft for ft in g.get('features', []) if ft.get('geometry')]
    feats.sort(key=lambda ft: (ft['properties'].get('shapeName') or '').lower())
    for i, ft in enumerate(feats, 1):
        p = ft['properties']
        rid = '%s%s%d' % (iso3, LVL[3], i)
        ft['properties'] = {'rid': rid}
        out.append(ft)
        rec = {'id': rid, 'n': (p.get('shapeName') or '').strip() or ('Unit %d' % i)}
        c = (p.get('shapeISO') or '').strip()
        if c and c.lower() not in ('none', 'nan', ''): rec['c'] = c
        if cid: index[cid].append(rec)
        else:   index['?' + iso3].append(rec)
json.dump({'type':'FeatureCollection','features':out},
          open('/home/claude/gb/all-%s.geojson' % LVL, 'w'), ensure_ascii=False)
json.dump(index, open('/home/claude/gb/index-%s.json' % LVL, 'w'), ensure_ascii=False)
print(LVL, 'features:', len(out), 'countries:', len(index),
      'MB', round(os.path.getsize('/home/claude/gb/all-%s.geojson' % LVL)/1048576, 1))
if nomatch: print('no app country for:', dict(nomatch))

#!/usr/bin/env python3
"""Put back what the first cities pass dropped: elevation, the time zone, the GeoNames id and
the feature code. Matched on the country and the point, which is exact - the names in the two
files are the same names."""
import json, io, os, collections
CI = {}
for line in io.open('/home/claude/dl/countryInfo.txt', encoding='utf-8'):
    if line.startswith('#') or not line.strip(): continue
    f = line.split('\t')
    if len(f) > 4: CI[f[0]] = f[4]          # ISO2 -> country name
G = collections.defaultdict(list)
n = 0
for line in io.open('/home/claude/dl/cities500.txt', encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    if len(f) < 18: continue
    cc = f[8]
    try: lat, lon = round(float(f[4]), 3), round(float(f[5]), 3)
    except ValueError: continue
    G[(cc, lat, lon)].append({'gid': int(f[0]), 'fc': f[7],
                              'ele': (int(f[15]) if f[15].strip() else (int(f[16]) if f[16].strip() else None)),
                              'tz': f[17]})
    n += 1
print('geonames rows:', n, 'keys:', len(G))
cities = json.load(io.open('/home/claude/work/reference/data/cities.json', encoding='utf-8'))
name2cc = {v: k for k, v in CI.items()}
hit = miss = 0
for country, rows in cities.items():
    cc = name2cc.get(country)
    for r in rows:
        ll = r.get('ll') or []
        if len(ll) != 2: continue
        found = None
        for dlat in (0, 0.001, -0.001):
            for dlon in (0, 0.001, -0.001):
                k = (cc, round(ll[0] + dlat, 3), round(ll[1] + dlon, 3))
                if k in G: found = G[k][0]; break
            if found: break
        if not found: miss += 1; continue
        hit += 1
        if found['ele'] is not None: r['ele'] = found['ele']
        if found['tz']: r['tz'] = found['tz']
        r['gid'] = found['gid']
        r['fc'] = found['fc']
json.dump(cities, io.open('/home/claude/facts/cities-v2.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('cities matched:', hit, ' unmatched:', miss)
print('MB', round(os.path.getsize('/home/claude/facts/cities-v2.json')/1048576, 2))

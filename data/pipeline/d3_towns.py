#!/usr/bin/env python3
"""D3. EVERY TOWN: the old towns files (towns-<file>.wyat: raw DEFLATE of JSON rows
[name, region, population, lat, lon, kind, geonames id, part of]) merged with GeoNames cities500
(every populated place over 500 people and every seat of an administrative division down to PPLA4).

The merge never re-keys: every old row is kept exactly as it was (its name, region, part); a GeoNames
place joins only if its id is not in the old files already. Sections of a city (PPLX) are left out:
the old files decided which sections belong to which city (parts.py), and a new section on its own
would be a second dot inside its city.

usage: d3_towns.py OLD_TOWNS_DIR GEONAMES_DIR OUT_DIR
"""
import collections, glob, json, os, sys, zlib

old_dir, gn_dir, out_dir = sys.argv[1:4]

def read_wyat(path):
    return json.loads(zlib.decompress(open(path, 'rb').read(), -15))

def write_wyat(path, rows):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode()
    open(path, 'wb').write(c.compress(data) + c.flush())

files = {}
for f in sorted(glob.glob(os.path.join(old_dir, 'towns-*.wyat'))):
    files[os.path.basename(f)[6:-5]] = read_wyat(f)
old_count = sum(len(r) for r in files.values())
old_ids = {r[6] for rows in files.values() for r in rows if r[6]}

import math, unicodedata
def fold(t):
    return ''.join(c for c in unicodedata.normalize('NFKD', t.casefold()) if not unicodedata.combining(c))
def km(a, b, c, d):
    x = math.radians(d - b) * math.cos(math.radians((a + c) / 2)); y = math.radians(c - a)
    return 6371 * math.hypot(x, y)
# old rows with no GeoNames id (all of Britain's, for one): a GeoNames place is the same town when one of its names
# is the old row's name and it lies within 15 km; it is left out, the old row standing for it
noid = collections.defaultdict(list)
for f, rows in files.items():
    for r in rows:
        if not r[6]: noid[fold(r[0])].append((r[3], r[4]))

admin1 = {}
for line in open(os.path.join(gn_dir, 'admin1CodesASCII.txt'), encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if len(p) >= 2: admin1[p[0]] = p[1]

# GeoNames country code -> the app's towns file; the places GeoNames keeps as one country but the
# app keeps apart are split by their first-level division
SPLIT = {
    'SH': {'SH.01': 'sh-ac', 'SH.02': 'sh-hl', 'SH.03': 'sh-ta'},
    'BQ': {'BQ.BO': 'x-bq-bo', 'BQ.SA': 'x-bq-sa', 'BQ.SE': 'x-bq-se'},
}
def file_for(cc, a1):
    if cc in SPLIT: return SPLIT[cc].get(f'{cc}.{a1}')
    f = cc.lower()
    return f if f in files else None

added = collections.Counter(); skipped = collections.Counter(); sections = 0
new_rows = collections.defaultdict(list)
for line in open(os.path.join(gn_dir, 'cities500.txt'), encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    gid = int(p[0]); name = p[1]; lat = float(p[4]); lon = float(p[5])
    fcode = p[7]; cc = p[8]; a1 = p[10]; pop = int(p[14] or 0)
    if gid in old_ids: continue
    names = {fold(name), fold(p[2])} | {fold(a) for a in p[3].split(',') if a}
    if any(km(lat, lon, a, b) < 15 for n in names for (a, b) in noid.get(n, ())):
        skipped['same as an old row with no id'] += 1; continue
    if fcode == 'PPLX': sections += 1; continue
    if fcode in ('PPLH', 'PPLQ', 'PPLW'): skipped['historical/abandoned'] += 1; continue
    f = file_for(cc, a1)
    if f is None: skipped[cc] += 1; continue
    kind = 2 if fcode == 'PPLC' else 1 if fcode == 'PPLA' else 0
    new_rows[f].append([name, admin1.get(f'{cc}.{a1}', ''), pop, round(lat, 3), round(lon, 3), kind, gid, ''])
    added[f] += 1

os.makedirs(out_dir, exist_ok=True)
total = 0
for f, rows in files.items():
    # old rows first, in their own order (never changed); new ones after, biggest first
    merged = rows + sorted(new_rows.get(f, []), key=lambda r: (-r[2], r[0]))
    write_wyat(os.path.join(out_dir, f'towns-{f}.wyat'), merged)
    total += len(merged)

report = {
    'old towns': old_count, 'new towns': sum(added.values()), 'total': total,
    'sections left out (PPLX)': sections,
    'not placed (code: count)': dict(skipped.most_common()),
    'most added': dict(added.most_common(15)),
}
json.dump(report, open(os.path.join(out_dir, 'D3-REPORT.json'), 'w'), indent=1, ensure_ascii=False)
print(json.dumps(report, indent=1, ensure_ascii=False))

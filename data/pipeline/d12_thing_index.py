"""D12's things part: every thing of D5 in one search index, famous first: rows [name, file (cc), Wikidata id, kind,
fame, lat, lon, other names ("JFK": an airport's IATA code from Wikidata P238, CC0)], gzipped for the data server (native/things/things-index-1.wyti)."""
import os, sys, json, gzip
src, dst = sys.argv[1], sys.argv[2]
iata = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else {}
rows = []
for f in sorted(os.listdir(src)):
    if not (f.startswith('things-') and f.endswith('-2.wyth.gz')): continue
    cc = f[7:-10]
    for r in json.load(gzip.open(os.path.join(src, f))):
        rows.append([r[1], cc, r[0], r[2], r[5], r[3], r[4], '|'.join(iata.get(r[0], []))])
rows.sort(key=lambda r: (-r[4], r[0]))
with gzip.open(dst, 'wb', compresslevel=9) as g: g.write(json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode())
print(len(rows), os.path.getsize(dst))

"""D12's towns part: every town of D3 in one search index, biggest first.
rows: [name, file, GeoNames id, people, lat, lon, kind, region]; written gzipped for the data server."""
import os, sys, json, zlib, gzip, glob
src, dst = sys.argv[1], sys.argv[2]
rows = []
for p in sorted(glob.glob(src + '/towns-*.wyat')):
    f = os.path.basename(p)[6:-5]
    raw = open(p, 'rb').read()
    try: data = json.loads(raw)
    except Exception: data = json.loads(zlib.decompress(raw, -15))
    for r in data:
        if len(r) < 7: continue
        name, region, people, lat, lon, kind, gid = r[:7]
        rows.append([name, f, gid or 0, people or 0, round(lat, 4), round(lon, 4), kind or 0, region or ""])
rows.sort(key=lambda r: (-r[3], r[0]))
out = json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode()
with gzip.open(dst, 'wb', compresslevel=9) as g: g.write(out)
print(len(rows), len(out), os.path.getsize(dst))

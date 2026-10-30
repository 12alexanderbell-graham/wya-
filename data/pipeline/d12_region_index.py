"""D12's regions part: the first two region levels of every place in one search index, each region by its own name
and (where its ISO 3166-2 code has one on Wikidata, P300) its English name too ("Bavaria" for Bayern).
rows: [name, place id, row, region id]; written gzipped for the data server.
usage: d12_region_index.py <regions dir> <out .gz> <iso2 csv: code,en>"""
import sys, os, glob, json, zlib, struct, gzip, csv
src, dst = sys.argv[1], sys.argv[2]
english = {}
if len(sys.argv) > 3:
    for r in csv.reader(open(sys.argv[3], encoding='utf-8')):
        if len(r) == 2 and r[0] != 'code': english.setdefault(r[0], r[1])
def header(path):
    raw = open(path, 'rb').read()
    try: b = zlib.decompress(raw, -15)
    except Exception: b = raw
    jn = struct.unpack_from('<I', b, 8)[0]
    return json.loads(b[12:12 + jn])
rows = []
for p in sorted(glob.glob(src + '/*.wyar')):
    cc, row = os.path.basename(p)[:-5].rsplit('-', 1)
    if int(row) > 2: continue
    seen = set()
    for u in header(p)['u']:
        if u['id'] in seen: continue
        seen.add(u['id'])
        rows.append([u['n'], cc, int(row), u['id']])
        en = english.get(u.get('c', ''))
        if en and en.casefold() != u['n'].casefold():
            rows.append([en, cc, int(row), u['id']])
out = json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode()
with gzip.open(dst, 'wb', compresslevel=9) as g: g.write(out)
print(len(rows), len(out), os.path.getsize(dst))

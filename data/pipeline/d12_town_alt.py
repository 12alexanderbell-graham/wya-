"""D12's towns part, other names: each indexed town's other names from GeoNames' cities500 (CC BY 4.0), so search
finds Tiflis, Москва, 東京. Output {gid: "name|name|..."} gzipped for the data server. Names equal to the town's own
(folded) are left out; a town under 100,000 people keeps at most 8 other names, a bigger one all (400 at most)."""
import sys, json, gzip, unicodedata
index, cities, dst = sys.argv[1], sys.argv[2], sys.argv[3]
rows = json.load(gzip.open(index))
want = {r[2]: (r[0], r[3]) for r in rows if r[2]}
def fold(s): return ''.join(c for c in unicodedata.normalize('NFKD', s.casefold()) if not unicodedata.combining(c))
out = {}
for line in open(cities, encoding='utf-8'):
    c = line.rstrip('\n').split('\t')
    gid = int(c[0])
    if gid not in want or not c[3]: continue
    name, people = want[gid]
    seen = {fold(name), fold(c[1]), fold(c[2])}
    alts = []
    for a in c[3].split(','):
        a = a.strip(); f = fold(a)
        if not a or f in seen or len(a) > 40: continue
        seen.add(f); alts.append(a)
    cap = 400 if people >= 100000 else 8
    if alts: out[str(gid)] = '|'.join(alts[:cap])
data = json.dumps(out, ensure_ascii=False, separators=(',', ':')).encode()
with gzip.open(dst, 'wb', compresslevel=9) as g: g.write(data)
print(len(want), len(out), len(data))

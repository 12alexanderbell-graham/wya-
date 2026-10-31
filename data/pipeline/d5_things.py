"""D5's things: every place of the server's places-next (Wikidata items with a point) that is a thing to go to, in one
of the twelve kinds (thing-kinds.json, from d5_thing_kinds.py, with a checker's fixes), per country. A thing with a
settlement among its classes (a town: towns come from the town data) or not a place to go is left out.
rows: [Wikidata id, name, kind (0 city ... 11 other, Part 7.3's order), lat, lon, fame (3 World Heritage or 40+ Wikipedias, 2 from 12,
1 from 4, 0), description, photo or ""], famous first; written gzipped to native/things/things-<cc>-3.wyth."""
import os, sys, json, gzip
src, kinds_path, fixes_path, heritage_path, dst = sys.argv[1:6]
# how known each thing is: its Wikipedia articles (Wikidata sitelinks, d5_sitelinks.py)
links = json.load(open(sys.argv[6])) if len(sys.argv) > 6 else {}
AIRPORTS = {'Q1248784', 'Q94993988', 'Q644371', 'Q62447', 'Q21836433', 'Q106643740'}
KINDS = ["city", "area", "landmark", "mountain", "water", "nature", "spot", "stay", "station", "route", "event", "other"]
kinds = json.load(open(kinds_path))
if os.path.exists(fixes_path): kinds.update(json.load(open(fixes_path)))
heritage = set(json.load(gzip.open(heritage_path)).keys())
os.makedirs(dst, exist_ok=True)
total = kept = 0
by = {}
for f in sorted(os.listdir(src)):
    if not f.endswith('.json.gz'): continue
    cc = f[:-8]
    items = json.load(gzip.open(os.path.join(src, f)))
    rows = []
    for q, v in items.items():
        total += 1
        ks = [kinds[c] for c in v.get('kind', []) if c in kinds and kinds[c] != 'unknown']
        # a settlement in any of its classes is a town (Berlin is a "capital" and a "state" too), never a thing
        if not ks or 'town' in ks or ks[0] == 'drop' or ks[0] not in KINDS: continue
        ll = v.get('ll')
        if not ll or len(ll) != 2 or not v.get('n'): continue
        img = (v.get('img') or [''])[0]
        n = links.get(q, 0)
        # fame: 3 World Heritage or 40+ Wikipedias, 2 from 12, 1 from 4 (or 2 with a photo), 0 the rest
        fame = 3 if q in heritage or n >= 40 else 2 if n >= 12 else 1 if n >= 4 or (img and n >= 2) else 0
        # stations other than airports at most 1 (Apple Maps shows a city's stops only close in)
        if ks[0] == 'station' and not any(c in AIRPORTS for c in v.get('kind', [])): fame = min(fame, 1)
        rows.append([q, v['n'], KINDS.index(ks[0]), round(ll[0], 5), round(ll[1], 5), fame, v.get('d', ''), img, n])
    # the best known first
    rows.sort(key=lambda r: (-r[5], -r[8], r[1]))
    for r in rows: r.pop()
    kept += len(rows)
    for r in rows: by[r[2]] = by.get(r[2], 0) + 1
    if rows:
        with gzip.open(os.path.join(dst, f'things-{cc}-3.wyth.gz'), 'wb', compresslevel=9) as g:
            g.write(json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode())
print(total, kept, {KINDS[k]: n for k, n in sorted(by.items())})

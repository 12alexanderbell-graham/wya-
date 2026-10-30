#!/usr/bin/env python3
"""D12, first part: every country's and territory's names in every language, for search (place-names.json:
place id -> names). From GeoNames countryInfo.txt (each ISO code's GeoNames id) and alternateNamesV2.txt, without
links, codes and transliteration rows; names that fold (case and accents) to the same text are kept once.

usage: d12_country_names.py GEONAMES_DIR world-meta.json OUT.json
"""
import collections, json, sys, unicodedata
gn, metaf, outf = sys.argv[1:4]
ci = {}
for line in open(f'{gn}/countryInfo.txt', encoding='utf-8'):
    if line.startswith('#'): continue
    p = line.rstrip('\n').split('\t')
    if len(p) > 16 and p[16]: ci[int(p[16])] = p[0].lower()
ids = {p['id'] for p in json.load(open(metaf))['places']}
want = {g: c for g, c in ci.items() if c in ids}
skip = {'link', 'wkdt', 'post', 'iata', 'icao', 'faac', 'unlc', 'fr_1793', 'phon', 'piny'}
names = collections.defaultdict(list)
with open(f'{gn}/alternateNamesV2.txt', encoding='utf-8') as f:
    for line in f:
        p = line.split('\t', 4)
        if int(p[1]) in want and p[2] not in skip: names[want[int(p[1])]].append(p[3])
def fold(t): return ''.join(c for c in unicodedata.normalize('NFKD', t.casefold()) if not unicodedata.combining(c))
out = {}
for c, ns in names.items():
    seen = set(); out[c] = []
    for n in ns:
        k = fold(n).strip()
        if len(k) >= 2 and k not in seen: seen.add(k); out[c].append(n)
json.dump(out, open(outf, 'w'), ensure_ascii=False, separators=(',', ':'))
print(len(out), 'places,', sum(map(len, out.values())), 'names')

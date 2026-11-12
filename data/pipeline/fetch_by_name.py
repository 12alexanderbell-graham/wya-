#!/usr/bin/env python3
"""Third pass: the cities with no GeoNames id (New York City, Seoul ...), found on Wikidata by their English name
with an image and a place within 25 km of the city's, the nearest such item that has a population (P1082: a ship or a building named after the town has none; the
first run gave Portland, Oregon a tugboat called Portland). Keys "cc/name@lat,lon" (the city's own
point as the server gives it: a country has many towns of one name, 13 Washingtons in the United States)."""
import gzip, json, math, os, sys, time, urllib.parse, urllib.request
ROOT = os.getcwd()
CITIES = os.path.join(ROOT, 'server/public.nosync/v1/cities')
OUT = os.path.join(ROOT, 'reference/data/city-images.json')
have = json.load(open(OUT))
# (the first run keyed by "cc/name": gone, with what it asked)
for k in [k for k in have if '/' in k and '@' not in k]: del have[k]
if '--again' in sys.argv:
    have.pop('_asked3', None)
    for k in [k for k in have if '@' in k]: del have[k]
# --alt: the big cities (100,000 people and more) still without one, by the item's other names too ("Washington" is
# Washington, D.C.'s)
ALT = '--alt' in sys.argv
MARK = '_asked4' if ALT else '_asked3'
want = {}   # name -> [(cc, lat, lon)]
for fn in sorted(os.listdir(CITIES)):
    if fn.endswith('.json.gz'):
        cc = fn[:-8]
        for c in json.load(gzip.open(os.path.join(CITIES, fn))):
            if not c.get('gid') and c.get('ll') and not (ALT and ((c.get('p') or 0) < 100000 or '%s/%s@%s,%s' % (cc, c['n'], c['ll'][0], c['ll'][1]) in have)):
                want.setdefault(c['n'], []).append((cc, c['ll'][0], c['ll'][1]))
done = set(have.get(MARK, []))
names = [n for n in sorted(want) if n not in done and '"' not in n and '\\' not in n]
print(len(names), 'names to ask', flush=True)
def km(a, b, c, d):
    p = math.pi / 180; x = (d - b) * p * math.cos((a + c) / 2 * p); y = (c - a) * p
    return math.hypot(x, y) * 6371
B = 150
for i in range(0, len(names), B):
    part = names[i:i + B]
    q = ('SELECT ?name ?img ?co WHERE { VALUES ?name { %s } ?item %s ?name; wdt:P18 ?img; wdt:P625 ?co; wdt:P1082 ?people. }'
         % (' '.join('"%s"@en' % n for n in part), 'skos:altLabel' if ALT else 'rdfs:label'))
    req = urllib.request.Request('https://query.wikidata.org/sparql', data=urllib.parse.urlencode({'query': q, 'format': 'json'}).encode(),
                                 headers={'User-Agent': 'wya-travel-app-data/0.1 (city photos)', 'Accept': 'application/sparql-results+json'})
    for attempt in range(4):
        try: r = json.load(urllib.request.urlopen(req, timeout=90)); break
        except Exception as e: print('retry', i, e, flush=True); time.sleep(10 * (attempt + 1))
    else: print('gave up at', i); break
    best = {}
    for b in r['results']['bindings']:
        n = b['name']['value']; co = b['co']['value']
        if not co.startswith('Point('): continue
        lon, lat = map(float, co[6:-1].split())
        f = urllib.parse.unquote(b['img']['value'].rsplit('/', 1)[-1]).replace('_', ' ')
        for cc, la, lo in want.get(n, []):
            k = '%s/%s@%s,%s' % (cc, n, la, lo)
            d = km(la, lo, lat, lon)
            if d < 25 and d < best.get(k, (99, ''))[0]: best[k] = (d, f)
    for k, (d, f) in best.items(): have[k] = f
    have[MARK] = sorted(done | set(names[:i + B]))
    json.dump(have, open(OUT, 'w'), ensure_ascii=False)
    print(i + len(part), 'asked,', len([k for k in have if '/' in k]), 'by name', flush=True)
    time.sleep(1)
print('done')

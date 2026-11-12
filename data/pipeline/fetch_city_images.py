#!/usr/bin/env python3
"""Each city's photo from Wikidata: the item with the city's GeoNames id (P1566) and its image (P18).
Reads the server's cities/{cc}.json, writes reference/data/city-images.json {gid: file name on Commons}.
Run from the wya?! folder: python3 data/pipeline/fetch_city_images.py """
import gzip, json, os, sys, time, urllib.parse, urllib.request
ROOT = os.getcwd()
CITIES = os.path.join(ROOT, 'server/public.nosync/v1/cities')
OUT = os.path.join(ROOT, 'reference/data/city-images.json')
gids = []
for fn in sorted(os.listdir(CITIES)):
    if fn.endswith('.json.gz'):
        for c in json.load(gzip.open(os.path.join(CITIES, fn))):
            if c.get('gid'): gids.append(str(c['gid']))
have = json.load(open(OUT)) if os.path.isfile(OUT) else {}
# second pass: the cities still without a photo, asked through every rank of the GeoNames claim (London's and New
# York's are not their item's best rank, so wdt:P1566 missed them)
SECOND = '--all-ranks' in sys.argv
MARK = '_asked2' if SECOND else '_asked'
done = set(have.get(MARK, []))
todo = [g for g in gids if g not in done and not (SECOND and g in have)]
print(len(gids), 'cities,', len(todo), 'to ask', flush=True)
B = 800
for i in range(0, len(todo), B):
    part = todo[i:i + B]
    path = 'p:P1566/ps:P1566' if SECOND else 'wdt:P1566'
    q = 'SELECT ?g ?img WHERE { VALUES ?g { %s } ?item %s ?g; wdt:P18 ?img. }' % (' '.join('"%s"' % g for g in part), path)
    body = urllib.parse.urlencode({'query': q, 'format': 'json'}).encode()
    req = urllib.request.Request('https://query.wikidata.org/sparql', data=body,
                                 headers={'User-Agent': 'wya-travel-app-data/0.1 (city photos; contact via app)',
                                          'Accept': 'application/sparql-results+json'})
    for attempt in range(4):
        try:
            r = json.load(urllib.request.urlopen(req, timeout=90)); break
        except Exception as e:
            print('retry', i, e, flush=True); time.sleep(10 * (attempt + 1))
    else:
        print('gave up at', i); break
    for b in r['results']['bindings']:
        g = b['g']['value']; f = urllib.parse.unquote(b['img']['value'].rsplit('/', 1)[-1]).replace('_', ' ')
        have.setdefault(g, f)   # the first image the item gives
    have[MARK] = sorted(done | set(todo[:i + B]))
    json.dump(have, open(OUT, 'w'), ensure_ascii=False)
    print(i + len(part), 'asked,', len([k for k in have if not k.startswith('_')]), 'with a photo', flush=True)
    time.sleep(1)
print('done')

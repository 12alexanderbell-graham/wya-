"""How known each thing is: its Wikidata sitelinks (how many Wikipedias have a page on it), from the Wikidata Query
Service in batches (one request a minute, its current limit). Writes sitelinks-<date>.json {qid: n}."""
import json, gzip, os, sys, time, urllib.request, urllib.parse
src, dst = sys.argv[1], sys.argv[2]
ids = []
for f in sorted(os.listdir(src)):
    if f.startswith('things-') and f.endswith('-2.wyth.gz'):
        ids += [r[0] for r in json.load(gzip.open(os.path.join(src, f)))]
out = json.load(open(dst)) if os.path.exists(dst) else {}
todo = [q for q in ids if q not in out]
B = 4000
for i in range(0, len(todo), B):
    vals = ' '.join('wd:' + q for q in todo[i:i + B])
    q = 'SELECT ?i ?n WHERE { VALUES ?i { %s } ?i wikibase:sitelinks ?n }' % vals
    for attempt in range(5):
        try:
            req = urllib.request.Request('https://query.wikidata.org/sparql', data=urllib.parse.urlencode({'query': q}).encode(),
                headers={'User-Agent': 'wya-data-build/1.0', 'Accept': 'application/sparql-results+json',
                         'Content-Type': 'application/x-www-form-urlencoded'})
            d = json.load(urllib.request.urlopen(req, timeout=120))
            for b in d['results']['bindings']:
                out[b['i']['value'].rsplit('/', 1)[1]] = int(b['n']['value'])
            break
        except Exception as e:
            print('retry', i, e, flush=True); time.sleep(65)
    json.dump(out, open(dst, 'w'))
    print(i + B, len(out), flush=True)
    time.sleep(62)
print('done', len(out))

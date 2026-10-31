import json, os, sys, time, urllib.request, urllib.parse
ids = json.load(open(sys.argv[1])); dst = sys.argv[2]
out = json.load(open(sys.argv[3])) if len(sys.argv) > 3 and os.path.exists(sys.argv[3]) else {}
if os.path.exists(dst): out.update(json.load(open(dst)))
todo = [q for q in ids if q not in out]
B = 4000
for i in range(0, len(todo), B):
    vals = ' '.join('wd:' + q for q in todo[i:i + B])
    q = 'SELECT ?i ?n WHERE { VALUES ?i { %s } ?i wikibase:sitelinks ?n }' % vals
    for attempt in range(6):
        try:
            req = urllib.request.Request('https://query.wikidata.org/sparql', data=urllib.parse.urlencode({'query': q}).encode(),
                headers={'User-Agent': 'wya-data-build/1.0', 'Accept': 'application/sparql-results+json',
                         'Content-Type': 'application/x-www-form-urlencoded'})
            d = json.load(urllib.request.urlopen(req, timeout=120))
            for b in d['results']['bindings']: out[b['i']['value'].rsplit('/', 1)[1]] = int(b['n']['value'])
            break
        except Exception as e:
            print('retry', i, e, flush=True); time.sleep(65)
    json.dump(out, open(dst, 'w')); print(i + B, len(out), flush=True); time.sleep(62)
print('done', len(out), flush=True)

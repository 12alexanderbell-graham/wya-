#!/usr/bin/env python3
"""The picture, the point, the name, what it is and whose country it is, for all 67,107
places the app names. Wikivoyage tags its listings with Wikidata ids, so the whole image
layer comes from one batched query. Resumable."""
import json, os, time, urllib.parse, urllib.request
UA = 'wya-travel-app-data/1.0 (destination images; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
EP = 'https://query.wikidata.org/sparql'
OUT = '/home/claude/facts/dest-facts.json'
DONE = '/home/claude/facts/dest-done.json'

def sparql(q, tries=5):
    for k in range(tries):
        try:
            r = urllib.request.Request(EP, data=urllib.parse.urlencode({'query': q, 'format': 'json'}).encode(),
                                       headers={'User-Agent': UA, 'Accept': 'application/sparql-results+json',
                                                'Content-Type': 'application/x-www-form-urlencoded'})
            with urllib.request.urlopen(r, timeout=180) as f:
                return json.loads(f.read().decode())['results']['bindings']
        except Exception as e:
            if k == tries - 1: raise
            time.sleep(6 * (k + 1))

qs = json.load(open('/home/claude/facts/dest-qids.json'))
have = json.load(open(OUT)) if os.path.exists(OUT) else {}
done = set(json.load(open(DONE))) if os.path.exists(DONE) else set()
todo = [q for q in qs if q not in done]
print('%d ids, %d done, %d to go' % (len(qs), len(done), len(todo)), flush=True)

B = 800
for k in range(0, len(todo), B):
    chunk = todo[k:k+B]
    V = ' '.join('wd:' + x for x in chunk)
    q = ('SELECT ?i ?img ?coord ?n ?d ?kind ?cty WHERE { VALUES ?i { %s } '
         'OPTIONAL { ?i wdt:P18 ?img } '
         'OPTIONAL { ?i wdt:P625 ?coord } '
         'OPTIONAL { ?i rdfs:label ?n FILTER(lang(?n)="en") } '
         'OPTIONAL { ?i schema:description ?d FILTER(lang(?d)="en") } '
         'OPTIONAL { ?i wdt:P31 ?kind } '
         'OPTIONAL { ?i wdt:P17 ?cty } }' % V)
    try:
        rows = sparql(q)
    except Exception as e:
        print('  batch %d FAILED %s' % (k // B, str(e)[:70]), flush=True); continue
    for r in rows:
        qid = r['i']['value'].rsplit('/', 1)[-1]
        rec = have.setdefault(qid, {})
        if 'n' in r: rec['n'] = r['n']['value']
        if 'd' in r: rec['d'] = r['d']['value']
        if 'img' in r:
            f = urllib.parse.unquote(r['img']['value'].rsplit('/', 1)[-1]).replace('_', ' ')
            rec.setdefault('img', [])
            if f not in rec['img'] and len(rec['img']) < 6: rec['img'].append(f)
        if 'coord' in r:
            v = r['coord']['value']
            if v.startswith('Point('):
                try:
                    lon, lat = v[6:-1].split()
                    rec['ll'] = [round(float(lat), 5), round(float(lon), 5)]
                except Exception: pass
        for key, col in (('kind', 'kind'), ('cty', 'cty')):
            if col in r:
                v = r[col]['value'].rsplit('/', 1)[-1]
                rec.setdefault(key, [])
                if v not in rec[key] and len(rec[key]) < 4: rec[key].append(v)
    done.update(chunk)
    if (k // B) % 5 == 0 or k + B >= len(todo):
        json.dump(have, open(OUT, 'w'), ensure_ascii=False)
        json.dump(sorted(done), open(DONE, 'w'))
        wi = sum(1 for v in have.values() if v.get('img'))
        print('  %6d/%6d   %6d known   %6d with a picture' % (min(k+B, len(todo)), len(todo), len(have), wi), flush=True)
json.dump(have, open(OUT, 'w'), ensure_ascii=False)
json.dump(sorted(done), open(DONE, 'w'))
wi = sum(1 for v in have.values() if v.get('img'))
print('SAVED %d places, %d with a picture' % (len(have), wi))

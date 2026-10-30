#!/usr/bin/env python3
"""What Wikidata knows about every first-level region, joined on its ISO 3166-2 code.

3,105 of the 3,236 regions carry an ISO code, and Wikidata indexes subdivisions by exactly
that code (P300), so this is a clean join rather than a name match."""
import json, io, os, time, urllib.parse, urllib.request
UA = 'wya-travel-app-data/1.0 (region facts; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
EP = 'https://query.wikidata.org/sparql'
OUT = '/home/claude/facts/region-facts.json'

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

codes = json.load(open('/home/claude/facts/region-iso-codes.json'))
have = json.load(io.open(OUT, encoding='utf-8')) if os.path.exists(OUT) else {}
todo = [c for c in codes if c not in have]
print('%d codes, %d done, %d to go' % (len(codes), len(have), len(todo)), flush=True)
B = 250
for k in range(0, len(todo), B):
    chunk = todo[k:k+B]
    V = ' '.join('"%s"' % c for c in chunk)
    q = ('SELECT ?iso ?r ?n ?d ?img ?flag ?coa ?pop ?area ?cap ?coord ?capLabel WHERE { '
         'VALUES ?iso { %s } ?r wdt:P300 ?iso . '
         'OPTIONAL { ?r rdfs:label ?n FILTER(lang(?n)="en") } '
         'OPTIONAL { ?r schema:description ?d FILTER(lang(?d)="en") } '
         'OPTIONAL { ?r wdt:P18 ?img } '
         'OPTIONAL { ?r wdt:P41 ?flag } '
         'OPTIONAL { ?r wdt:P94 ?coa } '
         'OPTIONAL { ?r wdt:P1082 ?pop } '
         'OPTIONAL { ?r wdt:P2046 ?area } '
         'OPTIONAL { ?r wdt:P36 ?cap . ?cap rdfs:label ?capLabel FILTER(lang(?capLabel)="en") } '
         'OPTIONAL { ?r wdt:P625 ?coord } }' % V)
    try: rows = sparql(q)
    except Exception as e:
        print('  batch %d FAILED %s' % (k//B, str(e)[:70]), flush=True); continue
    def f(name, r): return r[name]['value'] if name in r else None
    for r in rows:
        iso = f('iso', r)
        rec = have.setdefault(iso, {})
        rec['q'] = f('r', r).rsplit('/', 1)[-1]
        if f('n', r): rec['n'] = f('n', r)
        if f('d', r): rec['d'] = f('d', r)
        if f('capLabel', r): rec['cap'] = f('capLabel', r)
        for key, col in (('img','img'), ('flag','flag'), ('coa','coa')):
            v = f(col, r)
            if v:
                fn = urllib.parse.unquote(v.rsplit('/', 1)[-1]).replace('_', ' ')
                rec.setdefault(key, [])
                if fn not in rec[key] and len(rec[key]) < 3: rec[key].append(fn)
        for key, col in (('pop','pop'), ('area','area')):
            v = f(col, r)
            if v:
                try: rec[key] = max(rec.get(key, 0), float(v))
                except ValueError: pass
        v = f('coord', r)
        if v and v.startswith('Point('):
            try:
                lon, lat = v[6:-1].split()
                rec['ll'] = [round(float(lat), 5), round(float(lon), 5)]
            except Exception: pass
    for c in chunk: have.setdefault(c, {})
    json.dump(have, io.open(OUT, 'w', encoding='utf-8'), ensure_ascii=False)
    got = sum(1 for v in have.values() if v.get('q'))
    print('  %5d/%5d   %5d matched on Wikidata' % (min(k+B, len(todo)), len(todo), got), flush=True)
got = sum(1 for v in have.values() if v.get('q'))
wi = sum(1 for v in have.values() if v.get('img'))
print('SAVED %d codes, %d matched, %d with a picture, %d with a flag'
      % (len(have), got, wi, sum(1 for v in have.values() if v.get('flag'))))

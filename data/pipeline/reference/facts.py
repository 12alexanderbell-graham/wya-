import os
#!/usr/bin/env python3
"""Every small fact a country page needs, from Wikidata, keyed by ISO 3166-1 alpha-2.

Wikipedia's own API is rate-limited to nothing today; the query service is not, and it is the
better source anyway - one statement per fact, with a qualifier trail, rather than a table
somebody hand-edited."""
import json, sys, time, urllib.parse, urllib.request, collections
UA = 'wya-travel-app-data/1.0 (country facts; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
EP = 'https://query.wikidata.org/sparql'

def run(q, tries=5):
    for k in range(tries):
        try:
            r = urllib.request.Request(EP, data=urllib.parse.urlencode({'query': q, 'format': 'json'}).encode(),
                                       headers={'User-Agent': UA, 'Accept': 'application/sparql-results+json',
                                                'Content-Type': 'application/x-www-form-urlencoded'})
            with urllib.request.urlopen(r, timeout=240) as f:
                return json.loads(f.read().decode())['results']['bindings']
        except Exception as e:
            if k == tries - 1: raise
            time.sleep(10 * (k + 1))

def v(row, k): 
    x = row.get(k)
    return x['value'] if x else None

OUT = collections.defaultdict(dict)

def put(iso, key, val, many=False):
    if not iso or val in (None, ''): return
    if many:
        cur = OUT[iso].setdefault(key, [])
        if val not in cur: cur.append(val)
    else:
        OUT[iso].setdefault(key, val)

# one query per fact keeps each one small enough to finish inside the service's timeout
QUERIES = [
 ('side',   'wdt:P1622', 'label', False),
 ('plug',   'wdt:P2853', 'label', True),
 ('volts',  'wdt:P2884', 'plain', True),
 ('emerg',  'wdt:P2852', 'label', True),
 ('cur',    'wdt:P38',   'label', True),
 ('idd',    'wdt:P474',  'plain', True),
 ('cap',    'wdt:P36',   'label', True),
 ('lang',   'wdt:P37',   'label', True),
 ('tz',     'wdt:P421',  'label', True),
 ('top',    'wdt:P610',  'label', False),
 ('low',    'wdt:P1589', 'label', False),
 ('anthem', 'wdt:P85',   'label', False),
 ('motto',  'wdt:P1546', 'label', False),
 ('cont',   'wdt:P30',   'label', True),
 ('drives', 'wdt:P1622', 'label', False),
]
for key, prop, kind, many in QUERIES:
    if kind == 'label':
        q = ('SELECT ?iso ?val WHERE { ?c wdt:P297 ?iso . ?c %s ?o . '
             '?o rdfs:label ?val FILTER(lang(?val)="en") }' % prop)
    else:
        q = 'SELECT ?iso ?val WHERE { ?c wdt:P297 ?iso . ?c %s ?val }' % prop
    try:
        rows = run(q)
    except Exception as e:
        print('  %-7s FAILED %s' % (key, str(e)[:80]), flush=True); continue
    n = 0
    for r in rows:
        put(v(r, 'iso'), key, v(r, 'val'), many); n += 1
    print('  %-7s %5d rows, %3d countries' % (key, n, sum(1 for c in OUT.values() if key in c)), flush=True)

# the pictures: the country's own image, its coat of arms, its flag, plus the licence line
IMG = [('pic', 'wdt:P18'), ('coa', 'wdt:P94'), ('flagimg', 'wdt:P41'), ('map', 'wdt:P242')]
for key, prop in IMG:
    q = 'SELECT ?iso ?val WHERE { ?c wdt:P297 ?iso . ?c %s ?val }' % prop
    try: rows = run(q)
    except Exception as e:
        print('  %-7s FAILED %s' % (key, str(e)[:80]), flush=True); continue
    for r in rows: put(v(r, 'iso'), key, v(r, 'val'), True)
    print('  %-7s %5d rows, %3d countries' % (key, len(rows), sum(1 for c in OUT.values() if key in c)), flush=True)

# a one-line description, which is what the AI should say when it has nothing else
q = ('SELECT ?iso ?val WHERE { ?c wdt:P297 ?iso . ?c schema:description ?val '
     'FILTER(lang(?val)="en") }')
try:
    rows = run(q)
    for r in rows: put(v(r, 'iso'), 'desc', v(r, 'val'))
    print('  desc    %5d rows' % len(rows), flush=True)
except Exception as e: print('  desc FAILED', str(e)[:80])

json.dump(OUT, open('/home/claude/facts/country-facts.json', 'w'), ensure_ascii=False)
print('SAVED', len(OUT), 'countries')

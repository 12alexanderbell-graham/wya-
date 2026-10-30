#!/usr/bin/env python3
"""Everything Wikidata holds about a country, in one pass.

The query service times out on the bigger joins and the write API is rate-limited to nothing,
but Special:EntityData is a flat file served from the CDN - a whole country in under a second.
So: pull every country's entity, take the properties a travel app needs, then resolve the
item-valued ones to English labels in one batched query at the end."""
import json, os, re, sys, time, urllib.parse, urllib.request, collections
UA = 'wya-travel-app-data/1.0 (country facts; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
OUT = '/home/claude/facts'
os.makedirs(OUT + '/ent', exist_ok=True)

def get(url, t=90):
    for k in range(4):
        try:
            r = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(r, timeout=t) as f: return f.read()
        except Exception as e:
            if k == 3: return None
            time.sleep(3 * (k + 1))

def sparql(q, tries=4):
    EP = 'https://query.wikidata.org/sparql'
    for k in range(tries):
        try:
            r = urllib.request.Request(EP, data=urllib.parse.urlencode({'query': q, 'format': 'json'}).encode(),
                                       headers={'User-Agent': UA, 'Accept': 'application/sparql-results+json',
                                                'Content-Type': 'application/x-www-form-urlencoded'})
            with urllib.request.urlopen(r, timeout=200) as f:
                return json.loads(f.read().decode())['results']['bindings']
        except Exception as e:
            if k == tries - 1: raise
            time.sleep(8 * (k + 1))

# what a country page, a stamp page and the AI all need
WANT = {
 'P1622':'drivingSide', 'P2853':'plug', 'P2884':'volts', 'P2859':'hertz',
 'P2852':'emergency', 'P38':'currency', 'P474':'callingCode', 'P36':'capital',
 'P37':'officialLanguage', 'P2936':'languageUsed', 'P421':'timezone',
 'P610':'highestPoint', 'P1589':'lowestPoint', 'P18':'image', 'P94':'coatOfArms',
 'P41':'flagImage', 'P242':'locatorMap', 'P948':'banner', 'P85':'anthem',
 'P163':'flagDescription', 'P1546':'motto', 'P1082':'population', 'P2046':'area',
 'P4010':'gdp', 'P2132':'gdpPerCapita', 'P1081':'hdi', 'P30':'continent',
 'P47':'borders', 'P571':'inception', 'P35':'headOfState', 'P6':'headOfGovernment',
 'P122':'government', 'P832':'publicHoliday', 'P463':'memberOf',
 'P2927':'waterPercent', 'P2250':'lifeExpectancy', 'P4841':'fertilityRate',
 'P1198':'unemployment', 'P395':'plateCode', 'P297':'iso2', 'P298':'iso3',
 'P299':'isoNumeric', 'P901':'fips', 'P237':'coatDescription', 'P138':'namedAfter',
 'P1589':'lowestPoint', 'P2633':'geographyOf', 'P6591':'maxTemp', 'P6591x':'x',
 'P1589y':'y', 'P17':'country', 'P361':'partOf', 'P206':'nextToWater',
 'P2929':'lowestTemp', 'P3872':'patronSaint', 'P1029':'x2',
}
ITEM_PROPS = {'P1622','P2853','P38','P36','P37','P2936','P421','P610','P1589','P30','P47',
              'P35','P6','P122','P832','P463','P138','P17','P361','P206','P3872','P85','P2852'}

def val(sn):
    dv = sn.get('mainsnak', {}).get('datavalue')
    if not dv: return None
    t, v = dv.get('type'), dv.get('value')
    if t == 'wikibase-entityid': return {'q': v.get('id')}
    if t == 'string': return v
    if t == 'quantity':
        try: return float(v['amount'])
        except Exception: return v.get('amount')
    if t == 'time': return v.get('time')
    if t == 'monolingualtext': return v.get('text')
    if t == 'globecoordinate': return [v.get('latitude'), v.get('longitude')]
    return None

def preferred(claims):
    """the statement that is marked preferred, or all of them when none is"""
    pref = [c for c in claims if c.get('rank') == 'preferred']
    keep = pref or [c for c in claims if c.get('rank') != 'deprecated']
    return keep

# every country the app carries, with its Q-id
rows = sparql('SELECT ?c ?iso WHERE { ?c wdt:P297 ?iso . ?c wdt:P31/wdt:P279* wd:Q56061 }')
byiso = {}
for r in rows:
    iso = r['iso']['value']; q = r['c']['value'].rsplit('/', 1)[-1]
    byiso.setdefault(iso, q)
print('countries with an ISO code on Wikidata:', len(byiso), flush=True)

facts, qids = {}, set()
for n, (iso, q) in enumerate(sorted(byiso.items()), 1):
    path = '%s/ent/%s.json' % (OUT, q)
    if os.path.exists(path):
        raw = open(path, 'rb').read()
    else:
        raw = get('https://www.wikidata.org/wiki/Special:EntityData/%s.json' % q)
        if not raw: print('  %s %s FAILED' % (iso, q), flush=True); continue
        open(path, 'wb').write(raw)
    try: ent = json.loads(raw)['entities'][q]
    except Exception: continue
    rec = {'q': q}
    lab = (ent.get('labels') or {}).get('en')
    if lab: rec['name'] = lab['value']
    de = (ent.get('descriptions') or {}).get('en')
    if de: rec['desc'] = de['value']
    al = (ent.get('aliases') or {}).get('en') or []
    if al: rec['alias'] = [a['value'] for a in al][:12]
    for pid, key in WANT.items():
        cl = (ent.get('claims') or {}).get(pid)
        if not cl: continue
        vals = []
        for sn in preferred(cl):
            v = val(sn)
            if v is None: continue
            if isinstance(v, dict) and 'q' in v:
                qids.add(v['q']); vals.append(v['q'])
            else: vals.append(v)
        if vals: rec[key] = vals if len(vals) > 1 else vals[0]
    sl = ent.get('sitelinks') or {}
    if 'enwiki' in sl: rec['wp'] = sl['enwiki']['title']
    if 'enwikivoyage' in sl: rec['wv'] = sl['enwikivoyage']['title']
    facts[iso] = rec
    if n % 25 == 0: print('  %3d/%3d  %s' % (n, len(byiso), iso), flush=True)

print('resolving %d item labels' % len(qids), flush=True)
labels = {}
qs = sorted(qids)
for k in range(0, len(qs), 250):
    chunk = qs[k:k+250]
    q = ('SELECT ?i ?l WHERE { VALUES ?i { %s } ?i rdfs:label ?l FILTER(lang(?l)="en") }'
         % ' '.join('wd:' + x for x in chunk))
    try:
        for r in sparql(q): labels[r['i']['value'].rsplit('/',1)[-1]] = r['l']['value']
    except Exception as e:
        print('  label batch failed', str(e)[:60], flush=True)
    print('  labels %d/%d' % (min(k+250, len(qs)), len(qs)), flush=True)

json.dump(facts, open(OUT + '/country-wikidata.json', 'w'), ensure_ascii=False)
json.dump(labels, open(OUT + '/wikidata-labels.json', 'w'), ensure_ascii=False)
print('SAVED', len(facts), 'countries,', len(labels), 'labels')

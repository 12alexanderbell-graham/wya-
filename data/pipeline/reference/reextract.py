#!/usr/bin/env python3
"""Re-read the cached entities with a better rule about which statement to believe.

France's currency came out "CFP Franc" because Wikidata lists it - true, but only of the
Pacific territories, which the statement says in a qualifier. A statement that is scoped to
part of the country, or that has an end date, is not the country's answer."""
import json, io, os, glob, collections
WANT = json.load(io.open('want.json', encoding='utf-8')) if os.path.exists('want.json') else None
import importlib.util
spec = importlib.util.spec_from_file_location('ent', '/home/claude/facts/entities.py')
# WANT/ITEM_PROPS are defined in entities.py; re-declare here rather than import (it runs on import)
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
 'P17':'country', 'P361':'partOf', 'P206':'nextToWater', 'P3872':'patronSaint',
}
SCOPE = {'P642','P518','P3005','P1001','P276','P407','P805'}   # "only of / applies to part / in"
ENDED = {'P582','P576','P1366'}                                 # end time, dissolved, replaced by

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
    return None

def when(c):
    """the point in time a statement is about, as a sortable string"""
    q = (c.get('qualifiers') or {}).get('P585')
    if not q: return ''
    try: return q[0]['datavalue']['value']['time']
    except Exception: return ''

def usable(cl):
    """the statements the country as a whole can be said to have, best first.
       Three rules, in order: a deprecated or ended statement is not true now; a preferred
       one beats the rest; a statement scoped to part of the country is not the country's
       answer when an unscoped one exists; and a series of yearly figures - population, life
       expectancy - is one fact with a date on it, so only the latest year counts."""
    live = []
    for c in cl:
        if c.get('rank') == 'deprecated': continue
        q = c.get('qualifiers') or {}
        if any(k in q for k in ENDED): continue
        live.append((0 if c.get('rank') == 'preferred' else 1,
                     1 if any(k in q for k in SCOPE) else 0, c))
    if not live: return []
    best_rank = min(x[0] for x in live)
    live = [x for x in live if x[0] == best_rank]
    if any(x[1] == 0 for x in live): live = [x for x in live if x[1] == 0]
    cs = [c for _, _, c in live]
    dated = [c for c in cs if when(c)]
    if len(dated) > 1 and len(dated) == len(cs):
        cs = [max(cs, key=when)]
    return cs

facts, qids = {}, set()
for path in sorted(glob.glob('/home/claude/facts/ent/*.json')):
    ent = json.load(io.open(path, encoding='utf-8'))
    q = os.path.basename(path)[:-5]
    e = ent['entities'].get(q)
    if not e: continue
    iso = None
    for sn in (e.get('claims') or {}).get('P297', []):
        v = val(sn)
        if isinstance(v, str): iso = v; break
    if not iso: continue
    rec = {'q': q}
    lab = (e.get('labels') or {}).get('en')
    if lab: rec['name'] = lab['value']
    de = (e.get('descriptions') or {}).get('en')
    if de: rec['desc'] = de['value']
    al = (e.get('aliases') or {}).get('en') or []
    if al: rec['alias'] = [a['value'] for a in al][:12]
    for pid, key in WANT.items():
        cl = (e.get('claims') or {}).get(pid)
        if not cl: continue
        vals = []
        for sn in usable(cl):
            v = val(sn)
            if v is None: continue
            if isinstance(v, dict) and 'q' in v:
                qids.add(v['q']); vals.append(v['q'])
            elif v not in vals: vals.append(v)
        if vals: rec[key] = vals if len(vals) > 1 else vals[0]
    sl = e.get('sitelinks') or {}
    if 'enwiki' in sl: rec['wp'] = sl['enwiki']['title']
    if 'enwikivoyage' in sl: rec['wv'] = sl['enwikivoyage']['title']
    facts[iso] = rec
json.dump(facts, io.open('country-wikidata.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('re-extracted', len(facts), 'countries,', len(qids), 'items to label')
old = set(json.load(io.open('wikidata-labels.json', encoding='utf-8')))
print('labels already held:', len(old), ' new ones needed:', len(qids - old))
json.dump(sorted(qids - old), io.open('labels-needed.json','w'))

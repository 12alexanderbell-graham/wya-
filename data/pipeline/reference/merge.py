#!/usr/bin/env python3
"""One file per country with the facts a page, a stamp and the AI all read from.
Item-valued properties are swapped for their English names; numbers stay numbers."""
import json, io, os
W = json.load(io.open('country-wikidata.json', encoding='utf-8'))
L = json.load(io.open('wikidata-labels.json', encoding='utf-8'))
ITEMS = {'drivingSide','plug','currency','capital','officialLanguage','languageUsed','timezone',
         'highestPoint','lowestPoint','continent','borders','headOfState','headOfGovernment',
         'government','publicHoliday','memberOf','namedAfter','country','partOf','nextToWater',
         'patronSaint','anthem','emergency'}
FILES = {'image','coatOfArms','flagImage','locatorMap','banner'}
out = {}
for iso, rec in W.items():
    o = {}
    for k, v in rec.items():
        if k in ITEMS:
            vals = v if isinstance(v, list) else [v]
            named = [L.get(x, x) for x in vals]
            named = [n for n in named if not (isinstance(n, str) and n.startswith('Q') and n[1:].isdigit())]
            if named: o[k] = named if len(named) > 1 else named[0]
        elif k in FILES:
            o[k] = v if isinstance(v, list) else [v]
        else:
            o[k] = v
    out[iso] = o
json.dump(out, io.open('country-facts.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('countries:', len(out), ' MB', round(os.path.getsize('country-facts.json')/1048576, 2))
fr = out.get('FR', {})
for k in ('name','desc','drivingSide','plug','volts','hertz','emergency','currency','callingCode',
          'capital','officialLanguage','timezone','highestPoint','lowestPoint','population',
          'area','lifeExpectancy','government','memberOf','image','coatOfArms','wp','wv'):
    if k in fr: print(' %-17s' % k, json.dumps(fr[k], ensure_ascii=False)[:150])
import collections
cov = collections.Counter()
for r in out.values():
    for k in r: cov[k]+=1
print('\ncoverage:', dict(sorted(cov.items(), key=lambda x:-x[1])))

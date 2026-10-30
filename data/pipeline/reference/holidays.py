#!/usr/bin/env python3
"""Public holidays, from Nager.Date (open, no key). Two years, so a trip planned for next
summer has them too."""
import json, time, urllib.request, os
UA='wya-travel-app-data/1.0 (public holidays; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
def get(u, t=40):
    for k in range(3):
        try:
            r=urllib.request.Request(u, headers={'User-Agent':UA})
            with urllib.request.urlopen(r, timeout=t) as f: return json.loads(f.read().decode())
        except Exception as e:
            if k==2: return None
            time.sleep(2*(k+1))
codes=[c['countryCode'] for c in json.load(open('/home/claude/facts/nager.json'))]
out={}
for i,cc in enumerate(codes,1):
    rows=[]
    for year in (2026, 2027):
        d=get('https://date.nager.at/api/v3/PublicHolidays/%d/%s' % (year, cc))
        for h in (d or []):
            rows.append({'d':h.get('date'),'n':h.get('name'),'local':h.get('localName'),
                         'global':h.get('global'),'types':h.get('types')})
    if rows: out[cc]=rows
    if i%25==0: print('  %3d/%3d  %s  (%d countries so far)'%(i,len(codes),cc,len(out)), flush=True)
json.dump(out, open('/home/claude/facts/holidays.json','w'), ensure_ascii=False)
print('SAVED holidays for', len(out), 'countries,', sum(len(v) for v in out.values()), 'dates')

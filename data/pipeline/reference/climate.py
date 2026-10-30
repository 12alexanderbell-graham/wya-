#!/usr/bin/env python3
"""Monthly climate for every capital: mean high, mean low, rain days and precipitation.
ERA5 reanalysis (real observed weather, 1991-2020) from Open-Meteo's archive, ten capitals
per request so the rate limit is never the problem.  That is what "when to go" needs."""
import json, time, urllib.request, urllib.parse, os, collections
UA='wya-travel-app-data/1.0 (climate; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
OUT='/home/claude/facts/climate.json'
have=json.load(open(OUT)) if os.path.exists(OUT) else {}
caps={}
for line in open('/home/claude/dl/countryInfo.txt', encoding='utf-8'):
    if line.startswith('#') or not line.strip(): continue
    f=line.split('\t')
    if len(f)>5 and f[0] and f[5]: caps[f[0]]=f[5]
coords={}
for line in open('/home/claude/dl/cities500.txt', encoding='utf-8'):
    f=line.split('\t')
    if len(f)<18: continue
    cc, name, lat, lon, feat = f[8], f[1], f[4], f[5], f[7]
    if cc in caps and (name==caps[cc] or f[2]==caps[cc]) and feat.startswith('PPLC'):
        coords.setdefault(cc, (float(lat), float(lon)))
print('capitals with coordinates:', len(coords), flush=True)
todo=[c for c in sorted(coords) if c not in have]

def months(day):
    t=day.get('time') or []
    hi=day.get('temperature_2m_max') or []; lo=day.get('temperature_2m_min') or []
    pr=day.get('precipitation_sum') or []
    mh=collections.defaultdict(list); ml=collections.defaultdict(list)
    mp=collections.defaultdict(float); mw=collections.defaultdict(int)
    for k,ds in enumerate(t):
        m=int(ds[5:7])
        if k<len(hi) and hi[k] is not None: mh[m].append(hi[k])
        if k<len(lo) and lo[k] is not None: ml[m].append(lo[k])
        if k<len(pr) and pr[k] is not None:
            mp[m]+=pr[k]
            if pr[k]>=1.0: mw[m]+=1
    years=max(1, round(len(t)/365.25))
    return [{'hi': round(sum(mh[m])/len(mh[m]),1) if mh[m] else None,
             'lo': round(sum(ml[m])/len(ml[m]),1) if ml[m] else None,
             'mm': round(mp[m]/years,1),
             'wet': round(mw[m]/years)} for m in range(1,13)]

B=3
for k in range(0, len(todo), B):
    chunk=todo[k:k+B]
    q=urllib.parse.urlencode({
      'latitude': ','.join('%.4f'%coords[c][0] for c in chunk),
      'longitude': ','.join('%.4f'%coords[c][1] for c in chunk),
      'start_date':'1991-01-01','end_date':'2020-12-31','timezone':'UTC',
      'daily':'temperature_2m_max,temperature_2m_min,precipitation_sum'})
    u='https://archive-api.open-meteo.com/v1/archive?'+q
    d=None
    for a in range(9):
        try:
            r=urllib.request.Request(u, headers={'User-Agent':UA})
            with urllib.request.urlopen(r, timeout=300) as f: d=json.loads(f.read().decode())
            break
        except Exception as e:
            print('  retry %d: %s'%(a,str(e)[:70]), flush=True); time.sleep(25*(a+1))
    if d is None:
        print('  GAVE UP on', ' '.join(chunk), flush=True); continue
    if isinstance(d, dict): d=[d]
    for cc, e in zip(chunk, d):
        have[cc]={'ll':list(coords[cc]),'months':months(e.get('daily') or {})}
    json.dump(have, open(OUT,'w'), ensure_ascii=False)
    print('  %3d/%3d  (%d done)  %s'%(min(k+B,len(todo)),len(todo),len(have),' '.join(chunk)), flush=True)
    time.sleep(2)
json.dump(have, open(OUT,'w'), ensure_ascii=False)
print('SAVED climate for %d capitals'%len(have), flush=True)

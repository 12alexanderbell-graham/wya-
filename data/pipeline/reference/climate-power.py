#!/usr/bin/env python3
"""Monthly climate for every capital, 1991-2020 (the WMO standard normal period), averaged here
from NASA POWER's daily MERRA-2 series: mean daily high, mean daily low, rainfall per month and
days with at least 1 mm.  NASA POWER is free to use, commercial use included; cite it.
One request per capital, one consistent source for all 230."""
import json, time, urllib.request, os, io, collections
UA='wya-travel-app-data/1.0 (climate; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
CAPS=json.load(io.open('/mnt/user-data/outputs/sync/capitals.json',encoding='utf-8'))
OUT='/home/claude/facts/climate-power.json'
have=json.load(io.open(OUT,encoding='utf-8')) if os.path.exists(OUT) else {}
todo=[c for c in sorted(CAPS) if c not in have]
print('%d done, %d to go'%(len(have),len(todo)),flush=True)
for i,cc in enumerate(todo,1):
    lat,lon,cap=CAPS[cc]
    u=('https://power.larc.nasa.gov/api/temporal/daily/point?parameters=T2M_MAX,T2M_MIN,PRECTOTCORR'
       '&community=RE&longitude=%.4f&latitude=%.4f&start=19910101&end=20201231&format=JSON'%(lon,lat))
    d=None
    for a in range(5):
        try:
            r=urllib.request.Request(u,headers={'User-Agent':UA})
            with urllib.request.urlopen(r,timeout=180) as f: d=json.loads(f.read().decode()); break
        except Exception as e:
            print('  %s retry %d %s'%(cc,a,str(e)[:60]),flush=True); time.sleep(10*(a+1))
    if not d: print('  GAVE UP',cc,flush=True); continue
    p=d['properties']['parameter']; fill=d['header'].get('fill_value',-999)
    hi=collections.defaultdict(list); lo=collections.defaultdict(list)
    pr=collections.defaultdict(float); wet=collections.defaultdict(int); yrs=collections.defaultdict(set)
    for k,v in p['T2M_MAX'].items():
        if v!=fill: hi[int(k[4:6])].append(v)
    for k,v in p['T2M_MIN'].items():
        if v!=fill: lo[int(k[4:6])].append(v)
    for k,v in p['PRECTOTCORR'].items():
        if v!=fill:
            m=int(k[4:6]); pr[m]+=v; yrs[m].add(k[:4])
            if v>=1.0: wet[m]+=1
    months=[]
    for m in range(1,13):
        ny=max(1,len(yrs[m]))
        months.append({'hi':round(sum(hi[m])/len(hi[m]),1) if hi[m] else None,
                       'lo':round(sum(lo[m])/len(lo[m]),1) if lo[m] else None,
                       'mm':round(pr[m]/ny,1),'wet':round(wet[m]/ny)})
    have[cc]={'cap':cap,'ll':[lat,lon],'months':months}
    if i%10==0 or i==len(todo):
        json.dump(have,io.open(OUT,'w',encoding='utf-8'),ensure_ascii=False)
        print('  %d/%d  %s'%(len(have),len(CAPS),cc),flush=True)
    time.sleep(0.4)
json.dump(have,io.open(OUT,'w',encoding='utf-8'),ensure_ascii=False)
print('SAVED %d capitals'%len(have),flush=True)

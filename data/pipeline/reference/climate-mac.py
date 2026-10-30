#!/usr/bin/env python3
"""Monthly climate for every capital (ERA5, 1991-2020, Open-Meteo archive), run from the Mac.
Resumable: reads climate.json, adds what is missing, stops cleanly before a time budget.
  python3 climate-mac.py [seconds]"""
import json, time, urllib.request, urllib.parse, os, sys, collections
T0=time.time(); BUDGET=float(sys.argv[1]) if len(sys.argv)>1 else 150
HERE=os.path.dirname(os.path.abspath(__file__))
DATA=os.path.join(HERE,'..','data')
OUT=os.path.join(DATA,'climate.json')
CAPS=json.load(open(os.path.join(HERE,'capitals.json'),encoding='utf-8'))
UA='wya-travel-app-data/1.0 (climate; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
have=json.load(open(OUT,encoding='utf-8')) if os.path.exists(OUT) else {}
todo=[c for c in sorted(CAPS) if c not in have]
print('%d done, %d to go'%(len(have),len(todo)), flush=True)
def months(day):
    t=day.get('time') or []
    hi=day.get('temperature_2m_max') or []; lo=day.get('temperature_2m_min') or []; pr=day.get('precipitation_sum') or []
    mh=collections.defaultdict(list); ml=collections.defaultdict(list); mp=collections.defaultdict(float); mw=collections.defaultdict(int)
    for k,ds in enumerate(t):
        m=int(ds[5:7])
        if k<len(hi) and hi[k] is not None: mh[m].append(hi[k])
        if k<len(lo) and lo[k] is not None: ml[m].append(lo[k])
        if k<len(pr) and pr[k] is not None:
            mp[m]+=pr[k]
            if pr[k]>=1.0: mw[m]+=1
    years=max(1,round(len(t)/365.25))
    return [{'hi':round(sum(mh[m])/len(mh[m]),1) if mh[m] else None,'lo':round(sum(ml[m])/len(ml[m]),1) if ml[m] else None,
             'mm':round(mp[m]/years,1),'wet':round(mw[m]/years)} for m in range(1,13)]
B=3
for k in range(0,len(todo),B):
    if time.time()-T0>BUDGET-25: print('out of time, resume later', flush=True); break
    ch=todo[k:k+B]
    q=urllib.parse.urlencode({'latitude':','.join('%.4f'%CAPS[c][0] for c in ch),'longitude':','.join('%.4f'%CAPS[c][1] for c in ch),
        'start_date':'1991-01-01','end_date':'2020-12-31','timezone':'UTC','daily':'temperature_2m_max,temperature_2m_min,precipitation_sum'})
    try:
        r=urllib.request.Request('https://archive-api.open-meteo.com/v1/archive?'+q, headers={'User-Agent':UA})
        with urllib.request.urlopen(r,timeout=60) as f: d=json.loads(f.read().decode())
    except Exception as e:
        print('  failed %s: %s'%(' '.join(ch),str(e)[:60]), flush=True)
        if '429' in str(e): break
        continue
    if isinstance(d,dict): d=[d]
    for cc,e in zip(ch,d): have[cc]={'ll':CAPS[cc][:2],'months':months(e.get('daily') or {})}
    json.dump(have,open(OUT,'w',encoding='utf-8'),ensure_ascii=False)
    print('  %d/%d  %s'%(len(have),len(CAPS),' '.join(ch)), flush=True)
    time.sleep(1.0)
json.dump(have,open(OUT,'w',encoding='utf-8'),ensure_ascii=False)
print('SAVED %d of %d capitals'%(len(have),len(CAPS)), flush=True)

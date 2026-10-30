#!/usr/bin/env python3
"""Check each temperature source against real weather-station normals (Meteostat, used here only
as a yardstick, never shipped).  For every capital with a station within 25 km and less than
150 m height difference, compare mean daily high and low for all 12 months."""
import json, io, gzip, math, os, urllib.request, collections, statistics, time
CAPS=json.load(io.open('/mnt/user-data/outputs/sync/capitals.json',encoding='utf-8'))
P=json.load(io.open('/home/claude/facts/climate-power.json',encoding='utf-8'))
E=json.load(io.open('/home/claude/facts/climate-final.json',encoding='utf-8'))
CH={}
for v in ('tasmax','tasmin'):
    for m in range(1,13):
        d=json.load(open('/home/claude/facts/chelsa/%s-%02d.json'%(v,m)))
        for cc,x in d.items(): CH.setdefault(cc,{}).setdefault(v,[None]*12)[m-1]=x
st=json.load(gzip.open('/tmp/st.json.gz'))
def km(a,b,c,d):
    p=math.pi/180; x=(d-b)*p*math.cos((a+c)/2*p); y=(c-a)*p; return 6371*math.hypot(x,y)
cityel={cc:E[cc].get('elev') for cc in CAPS if cc in E}
pick={}
for s in st:
    loc=s.get('location') or {}; la,lo=loc.get('latitude'),loc.get('longitude')
    if la is None: continue
    inv=(s.get('inventory') or {}).get('normals') or {}
    if not inv or not inv.get('start'): continue
    for cc,(cla,clo,_) in CAPS.items():
        if abs(la-cla)>0.3 or abs(lo-clo)>0.4: continue
        dk=km(cla,clo,la,lo)
        if dk>25: continue
        ce=cityel.get(cc); se=loc.get('elevation')
        if ce is not None and se is not None and abs(ce-se)>150: continue
        if cc not in pick or dk<pick[cc][1]: pick[cc]=(s['id'],dk,se)
print('capitals with a usable station:',len(pick),flush=True)
os.makedirs('/tmp/norm',exist_ok=True)
truth={}
for cc,(sid,dk,se) in sorted(pick.items()):
    p='/tmp/norm/%s.csv.gz'%sid
    if not os.path.exists(p):
        try:
            urllib.request.urlretrieve('https://bulk.meteostat.net/v2/normals/%s.csv.gz'%sid,p)
        except Exception: continue
    rows=[l.split(',') for l in gzip.open(p,'rt').read().splitlines() if l]
    best=None
    for per in (('1991','2020'),('1981','2010'),('1971','2000'),('1961','1990')):
        r=[x for x in rows if x[0]==per[0] and x[1]==per[1]]
        if len(r)==12 and all(x[3] and x[4] for x in r): best=r; break
    if not best: continue
    truth[cc]={'hi':[float(x[4]) for x in sorted(best,key=lambda x:int(x[2]))],
               'lo':[float(x[3]) for x in sorted(best,key=lambda x:int(x[2]))],'per':best[0][0]}
print('with full normals:',len(truth),flush=True)
def err(src):
    h=[];l=[]; per={}
    for cc,t in truth.items():
        s=src(cc)
        if not s: continue
        eh=[abs(a-b) for a,b in zip(s[0],t['hi'])]; el=[abs(a-b) for a,b in zip(s[1],t['lo'])]
        h+=eh; l+=el; per[cc]=(statistics.mean(eh),statistics.mean(el))
    return statistics.mean(h),statistics.mean(l),per
srcs={
 'POWER raw':      lambda cc:([m['hi'] for m in P[cc]['months']],[m['lo'] for m in P[cc]['months']]) if cc in P else None,
 'POWER + height': lambda cc:([m['hi'] for m in E[cc]['months']],[m['lo'] for m in E[cc]['months']]) if cc in E else None,
 'CHELSA':         lambda cc:(CH[cc]['tasmax'],CH[cc]['tasmin']) if cc in CH else None,
}
res={}
for k,f in srcs.items():
    h,l,per=err(f); res[k]=per
    print('%-15s mean error: high %.2f C, low %.2f C'%(k,h,l))
# the worst capitals for the chosen one
w=sorted(res['CHELSA'].items(),key=lambda x:-(x[1][0]+x[1][1]))[:12]
print('\nworst CHELSA capitals (hi err, lo err) vs POWER+height:')
for cc,(a,b) in w:
    c,d=res['POWER + height'][cc]
    print('  %s %-14s CHELSA %.1f/%.1f   POWER+h %.1f/%.1f   station period %s'%(cc,CAPS[cc][2][:14],a,b,c,d,truth[cc]['per']))
json.dump({'truth':truth,'pick':pick},open('/home/claude/facts/validation.json','w'))

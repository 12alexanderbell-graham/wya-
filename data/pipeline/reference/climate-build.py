import json,io,gzip,statistics
S={}
for v in ('tasmax','tasmin','pr'):
    for m in range(1,13):
        d=json.load(open('s_%s_%02d.json'%(v,m)))
        for k,x in d.items(): S.setdefault(k,{}).setdefault(v,[None]*12)[m-1]=x
P=json.load(open('/home/claude/chelsa/points.json'))
CAPS=json.load(io.open('/mnt/user-data/outputs/sync/capitals.json',encoding='utf-8'))
POW=json.load(open('/home/claude/facts/climate-power.json'))
V=json.load(open('/home/claude/facts/validation.json')); TC=V['truth']
TAB={(0,False):2.3,(0,True):2.25,(1,False):1.7,(1,True):1.95,(2,False):0.95,(2,True):1.7}
def band(lat): a=abs(lat); return 0 if a<23.5 else (1 if a<40 else 2)
def warm(lat,i): return (3<=i<=8) if lat>=0 else (i<=2 or i>=9)
def series(k):
    lat=P[k][0]; s=S.get(k)
    if not s or None in s['tasmax'] or None in s['tasmin']: return None
    hi=[round(s['tasmax'][i]+TAB[(band(lat),warm(lat,i))],1) for i in range(12)]
    lo=[round(s['tasmin'][i],1) for i in range(12)]
    mm=[int(round(x)) if x is not None else None for x in s['pr']]
    return hi,lo,mm
ABOUT={'temperature':'CHELSA v2.1 climatologies (1 km grid, 1981-2010). Mean daily highs raised by the bias measured against weather stations, by latitude band and season (tropics +2.3/+2.3, subtropics +1.7 winter/+1.9 summer, mid and high latitudes +0.9 winter/+1.7 summer C). Lows as published.',
  'rain':'CHELSA v2.1 mean monthly precipitation, mm',
  'accuracy':'Fitted on 118 capitals, then tested on 625 other weather stations it had never seen: mean daily highs within 1.0 C on average, lows within 1.4 C (lows in cities, where the capitals were measured, within 1.1 C); monthly rainfall within 13% (median).',
  'credit':'Karger, D.N. et al. (2017) Climatologies at high resolution for the earth land surface areas. Scientific Data 4:170122. CHELSA, CC BY 4.0',
  'licence':'CC BY 4.0: commercial use allowed with the credit above'}
# capitals: CHELSA temperature and rain, NASA POWER rain days
cap={'_about':dict(ABOUT, fields='12 months Jan-Dec. hi/lo = mean daily high/low C, mm = mean monthly rainfall, wet = mean days with at least 1 mm (NASA POWER daily 1991-2020)',
       credit=ABOUT['credit']+'; rain days: NASA Langley Research Center POWER Project')}
for cc,(lat,lon,name) in sorted(CAPS.items()):
    hi,lo,mm=series('k'+cc)
    cap[cc]={'cap':name,'ll':[lat,lon],'months':[{'hi':hi[i],'lo':lo[i],'mm':mm[i],'wet':POW[cc]['months'][i]['wet']} for i in range(12)]}
# rain check on the capitals' stations: CHELSA vs POWER
pc=[];pp=[]
for cc,(sid,dk,se) in V['pick'].items():
    if cc not in TC: continue
    rows=[l.split(',') for l in gzip.open('/tmp/norm/%s.csv.gz'%sid,'rt').read().splitlines() if l]
    r=sorted([x for x in rows if x[0]==TC[cc]['per']],key=lambda x:int(x[2]))
    if len(r)==12 and all(x[5] for x in r):
        for i,x in enumerate(r):
            b=float(x[5]); pc.append(abs(cap[cc]['months'][i]['mm']-b)/max(b,10)); pp.append(abs(POW[cc]['months'][i]['mm']-b)/max(b,10))
print('capitals rain vs stations: CHELSA median %.0f%%, NASA POWER %.0f%%'%(100*statistics.median(pc),100*statistics.median(pp)))
eh=statistics.mean([abs(cap[cc]['months'][i]['hi']-TC[cc]['hi'][i]) for cc in TC for i in range(12)])
el=statistics.mean([abs(cap[cc]['months'][i]['lo']-TC[cc]['lo'][i]) for cc in TC for i in range(12)])
print('capitals vs their stations: hi %.2f lo %.2f'%(eh,el))
json.dump(cap,io.open('/mnt/user-data/outputs/sync/climate.json','w',encoding='utf-8'),ensure_ascii=False)
# cities and regions: compact arrays
C=json.load(io.open('/home/claude/facts/cities-v2.json',encoding='utf-8'))
cities={'_about':dict(ABOUT,fields='key = GeoNames id (the "gid" in cities.json), or "<place>/<city name>" for the cities.json entries that have no gid. hi, lo, mm: 12 values each, January to December.')}
for place,lst in C.items():
    for c in lst:
        k=('c%d'%c['gid']) if c.get('gid') else ('n'+place+'/'+c['n'])
        if k not in S: continue
        s=series(k)
        if s: cities[str(c['gid']) if c.get('gid') else place+'/'+c['n']]={'n':c['n'],'hi':s[0],'lo':s[1],'mm':s[2]}
json.dump(cities,io.open('/mnt/user-data/outputs/sync/climate-cities.json','w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
R=json.load(io.open('/home/claude/facts/region-facts.json',encoding='utf-8'))
regs={'_about':dict(ABOUT,fields='key = ISO 3166-2 region code (as in region-facts.json), sampled at the point region-facts gives for the region. hi, lo, mm: 12 values each, January to December.')}
for k,v in R.items():
    s=series('r'+k) if ('r'+k) in S else None
    if s: regs[k]={'n':v.get('n'),'hi':s[0],'lo':s[1],'mm':s[2]}
json.dump(regs,io.open('/mnt/user-data/outputs/sync/climate-regions.json','w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
import os
for f in ('climate.json','climate-cities.json','climate-regions.json'):
    p='/mnt/user-data/outputs/sync/'+f; d=json.load(io.open(p,encoding='utf-8'))
    print('%-22s %6d entries  %6.1f MB'%(f,len(d)-1,os.path.getsize(p)/1e6))

#!/usr/bin/env python3
"""NASA POWER's grid cell is about 50 km across, so for a capital on a plateau or in a valley the
cell's average height is wrong and so is its temperature. Correct each capital's highs and lows by
the standard lapse rate, 6.5 C per 1000 m, from the cell's height to the city's own height."""
import json, io, time, urllib.request, os
UA='wya-travel-app-data/1.0 (climate; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
P=json.load(io.open('/home/claude/facts/climate-power.json',encoding='utf-8'))
EL='/home/claude/facts/power-cell-elev.json'
cell=json.load(io.open(EL)) if os.path.exists(EL) else {}
for cc,v in P.items():
    if cc in cell: continue
    lat,lon=v['ll']
    u=('https://power.larc.nasa.gov/api/temporal/climatology/point?parameters=T2M&community=RE'
       '&longitude=%.4f&latitude=%.4f&format=JSON'%(lon,lat))
    for a in range(4):
        try:
            r=urllib.request.Request(u,headers={'User-Agent':UA})
            with urllib.request.urlopen(r,timeout=60) as f: d=json.loads(f.read().decode())
            cell[cc]=d['geometry']['coordinates'][2]; break
        except Exception as e: time.sleep(5*(a+1))
    time.sleep(0.25)
json.dump(cell,io.open(EL,'w'))
# the city's own height: GeoNames elevation, else its SRTM value
city={}
for line in io.open('/home/claude/dl/cities500.txt',encoding='utf-8'):
    f=line.split('\t')
    if len(f)<18 or not f[7].startswith('PPLC') or f[8] not in P: continue
    lat,lon=float(f[4]),float(f[5])
    if abs(lat-P[f[8]]['ll'][0])>0.01 or abs(lon-P[f[8]]['ll'][1])>0.01: continue
    e=f[15].strip() or f[16].strip()
    if e and e!='-9999': city[f[8]]=int(float(e))
out={}
for cc,v in P.items():
    ce=city.get(cc); ge=cell.get(cc)
    dt=round((ge-ce)*0.0065,2) if (ce is not None and ge is not None) else 0.0
    ms=[{'hi':round(m['hi']+dt,1),'lo':round(m['lo']+dt,1),'mm':m['mm'],'wet':m['wet']} for m in v['months']]
    out[cc]={'cap':v['cap'],'ll':v['ll'],'elev':ce,'cellElev':ge,'correction':dt,'months':ms}
meta={'_source':'NASA POWER daily (MERRA-2), 1991-2020, averaged per month; temperatures corrected to the city\'s height at 6.5 C/km',
      '_licence':'NASA POWER data are free to use, including commercially; cite "NASA Langley Research Center POWER Project"',
      '_fields':'hi/lo = mean daily high/low C, mm = mean rainfall that month, wet = mean days with >= 1 mm'}
out.update(meta)
json.dump(out,io.open('/home/claude/facts/climate-final.json','w',encoding='utf-8'),ensure_ascii=False)
print('cells %d, city heights %d'%(len(cell),len(city)))
big=sorted(((abs(o['correction']),cc) for cc,o in out.items() if not cc.startswith('_')),reverse=True)[:10]
for _,cc in big:
    o=out[cc]; print('  %s %-14s city %5sm cell %5sm  %+.1fC   Jan hi %s  Jul hi %s'%(cc,o['cap'][:14],o['elev'],round(o['cellElev']),o['correction'],o['months'][0]['hi'],o['months'][6]['hi']))

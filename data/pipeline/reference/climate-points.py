import json,io
pts={}
C=json.load(io.open('/home/claude/facts/cities-v2.json',encoding='utf-8'))
for place,lst in C.items():
    for c in lst:
        if c.get('ll') and c.get('gid'): pts['c%d'%c['gid']]=c['ll']
R=json.load(io.open('/home/claude/facts/region-facts.json',encoding='utf-8'))
for k,v in R.items():
    if v.get('ll'): pts['r'+k]=v['ll']
CAPS=json.load(io.open('/mnt/user-data/outputs/sync/capitals.json',encoding='utf-8'))
for k,v in CAPS.items(): pts['k'+k]=v[:2]
T=json.load(open('/home/claude/chelsa/station-truth.json'))
for k,v in T.items(): pts['s'+k]=v['ll']
json.dump(pts,open('/home/claude/chelsa/points.json','w'))
print(len(pts),'points:',sum(k[0]=='c' for k in pts),'cities',sum(k[0]=='r' for k in pts),'regions',sum(k[0]=='k' for k in pts),'capitals',sum(k[0]=='s' for k in pts),'stations')

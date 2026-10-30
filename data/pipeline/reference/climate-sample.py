import sys,json,rasterio,collections,numpy as np
from rasterio.windows import Window
f=sys.argv[1]
P=json.load(open('/home/claude/chelsa/points.json'))
out={}
with rasterio.open('/home/claude/chelsa/'+f) as s:
    sc,off=s.scales[0],s.offsets[0]
    rows=collections.defaultdict(list)
    for k,(lat,lon) in P.items():
        r,c=s.index(lon,lat)
        if 0<=r<s.height and 0<=c<s.width: rows[r].append((k,c))
    for r in sorted(rows):
        line=s.read(1,window=Window(0,r,s.width,1))[0]
        for k,c in rows[r]:
            x=int(line[c])
            if x==65535 or (x==0 and not f.startswith("pr")):  # sea or no data: look up to 3 cells around for land
                w=line[max(0,c-3):c+4]; w=w[(w!=65535)] if f.startswith("pr") else w[(w!=0)&(w!=65535)]
                x=int(np.median(w)) if len(w) else None
            out[k]=None if x is None else round(x*sc+off,1)
json.dump(out,open('/home/claude/chelsa/s_'+f.replace('.tif','.json'),'w'))
print(f,len(out),sum(v is None for v in out.values()),'empty',flush=True)

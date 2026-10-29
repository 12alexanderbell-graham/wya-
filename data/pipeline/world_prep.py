# world.wyam v2 + world-meta.json + disputes.json, from the OLD APP'S OWN DATA, not the older test fixture the first
# build used. v2: every line keeps its two units, so the app decides per borders view which lines are drawn (no seam
# baked in).
import json, math, struct, os, sys
# the old app's Map folder (world.json, world-arcs.bin): the first argument, or WYA_OLD_MAP
P=os.path.join(sys.argv[1] if len(sys.argv)>1 else os.environ["WYA_OLD_MAP"], "")
d=json.load(open(P+"world.json")); t=d['topo']
b=open(P+"world-arcs.bin","rb").read()
n=struct.unpack_from("<I",b,0)[0]
starts=struct.unpack_from("<%dI"%(n+1),b,4); base=4+4*(n+1); total=starts[n]
xy=struct.unpack_from("<%di"%(2*total),b,base)
sx,sy=t['transform']['scale']; tx,ty=t['transform']['translate']
A1,A2,A3,A4=1.340264,-0.081106,0.000893,0.003796; M=math.sqrt(3)/2
def raw(lon,lat):
    lam=math.radians(lon); phi=math.radians(lat)
    th=math.asin(M*math.sin(phi)); t2=th*th; t6=t2**3
    x=lam*math.cos(th)/(M*(A1+3*A2*t2+t6*(7*A3+9*A4*t2)))
    y=th*(A1+A2*t2+t6*(A3+A4*t2))
    return x,y
RX=raw(180,0)[0]; RY=raw(0,90)[1]; S=1000/(2*RX)
def proj(lon,lat):
    x,y=raw(lon,lat); return ((x+RX)*S, (RY-y)*S)
HEIGHT=2*RY*S
def arcpts(i):
    rev=i<0; j=~i if rev else i
    pts=[(xy[2*k]*sx+tx, xy[2*k+1]*sy+ty) for k in range(starts[j],starts[j+1])]
    return pts[::-1] if rev else pts
def polys(obj):
    if obj['type']=='Polygon': return [obj['arcs']]
    if obj['type']=='MultiPolygon': return obj['arcs']
    return []
places=d['countries']; pid={p['id']:i for i,p in enumerate(places)}
objowner={}
for p in places:
    for o in p.get('objs',[]): objowner[o]=p['id']
disp={x['id']:x for x in d['disputes']['list']}
units=[]  # (owner index or 65535 [the old base owner, kept for the continents script], key)
rings=[]
usage={}  # arc -> [unit index]
def addobj(key,obj,owner):
    u=len(units); units.append((pid.get(owner,65535) if owner else 65535, key))
    for poly in polys(obj):
        for ring in poly:
            pts=[]
            for a in ring:
                p=arcpts(a); pts.extend(p if not pts else p[1:])
                j=~a if a<0 else a
                usage.setdefault(j,[]).append(u)
            if len(pts)>=3: rings.append((u,[proj(lo,la) for lo,la in pts]))
for k,obj in t['objects'].items():
    addobj(k,obj,objowner.get(k))
for k,obj in t['pieces'].items():
    dd=disp.get(k,{})
    owner=dd.get('controller') if dd.get('controller') in pid else dd.get('default')
    if owner not in pid: owner=None
    addobj('piece:'+k,obj,owner)
# lines
segs=[]
for j,us in usage.items():
    us=list(dict.fromkeys(us))
    ua=us[0]; ub=us[1] if len(us)>1 else -1
    kind = 0.0 if ub<0 else 1.0
    pts=[proj(xy[2*k]*sx+tx, xy[2*k+1]*sy+ty) for k in range(starts[j],starts[j+1])]
    dist=0
    for a,bq in zip(pts,pts[1:]):
        L=math.hypot(bq[0]-a[0],bq[1]-a[1])
        if L==0: continue
        segs.append((a[0],a[1],bq[0],bq[1],dist,2*kind,float(ua),float(ub))); dist+=L
lakes=[]
for lk in t['lakes']:
    for r in lk['r']:
        if len(r)>=3: lakes.append([proj(lo,la) for lo,la in r])
out=bytearray(b'WYAM'); out+=struct.pack('<I',2); out+=struct.pack('<ff',1000.0,HEIGHT)
out+=struct.pack('<I',len(units))
for owner,key in units: out+=struct.pack('<H',owner)
allr=[(u,p) for u,p in rings]+[(65535,p) for p in lakes]
out+=struct.pack('<I',len(allr))
for u,p in allr:
    out+=struct.pack('<HI',u,len(p))
    out+=struct.pack('<%df'%(2*len(p)),*[c for q in p for c in q])
out+=struct.pack('<I',len(segs))
for s in segs: out+=struct.pack('<8f',*s)
open('world.wyam','wb').write(out)
# THE DIAMONDS: the data's tiny places, less the ones whose biggest piece of land is over 90 km across (about 2.25 map
# units), which show as land well before any diamond would cover them: Abkhazia, South Ossetia, Transnistria, the
# Kerguelen (French Southern Territories), South Georgia
from collections import defaultdict
piece=defaultdict(float)
for u,pts in rings:
    key=units[u][1]
    if key.startswith('piece:'): continue
    o=objowner.get(key)
    if not o: continue
    xs=[q[0] for q in pts]; ys=[q[1] for q in pts]
    piece[o]=max(piece[o],max(max(xs)-min(xs),max(ys)-min(ys)))
TINY_MAX=2.25
untiny=[p['id'] for p in places if p.get('tiny') and piece[p['id']]>TINY_MAX]
print('no longer diamonds:',untiny)
meta=[]
for p in places:
    cx,cy=proj(*p['c'])
    meta.append({'id':p['id'],'n':p['n'],'s':p.get('s',p['n']),'k':p['k'],'cont':p.get('cont'),'c':[round(cx,3),round(cy,3)],
                 'll':p['c'],'official':p.get('official'),'alt':p.get('alt') or [],'tiny':bool(p.get('tiny',False)) and piece[p['id']]<=TINY_MAX,'ext':p.get('ext'),
                 'junk':p.get('junk',False),'objs':[o for o in p.get('objs',[]) if o in t['objects']]})
json.dump({'places':meta,'aliases':d['meta'].get('searchAliases',{}),'cont':d['meta']['contMeta'],'height':HEIGHT,
           'unitKeys':[k for _,k in units]},open('world-meta.json','w'),ensure_ascii=False)
F=('id','name','options','controller','default','pref','un','host','entity','side','owner','claimants')
dl=[{f:x.get(f) for f in F}|{'piece':x['id'] in t['pieces']} for x in d['disputes']['list']]
json.dump({'list':dl,'views':d['disputes'].get('views',[]),'povs':d['disputes'].get('povs',[]),
           'unrecognised':d['disputes'].get('unrecognised',{}),
           'jure':{"guantanamo-bay-usnb":"cu","baykonur":"kz","w-sahara":"eh"}},open('disputes.json','w'),ensure_ascii=False)
print('units',len(units),'rings',len(rings),'lakes',len(lakes),'segs',len(segs),'bytes',len(out))

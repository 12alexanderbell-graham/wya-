import os, sys
import json, math
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'world_prep.py')).read().split('# lines')[0])   # units, rings, places, pid, disp, t
conts=[c['k'] for c in d['meta']['contMeta']]
byid={p['id']:p for p in places}
def sliced(p): return any('|' in o for o in p.get('objs',[]))
def pconts(p):
    s=[c for c in (p.get('cont'),p.get('cont2')) if c]
    if sliced(p): s=[c for c in s if any(o.split('|')[1:2]==[c] for o in p['objs'])]
    return s
# centroid of rings by unit
unit_rings={}
for u,pts in rings: unit_rings.setdefault(u,[]).append(pts)
def nearest_slice(owner, pts):
    p=byid[owner]; best=None; bd=1e18
    cx=sum(x for x,_ in pts)/len(pts); cy=sum(y for _,y in pts)/len(pts)
    for ui,(oi,key) in enumerate(units):
        if '|' in key and key.split('|')[0]==owner:
            for r in unit_rings.get(ui,[]):
                for x,y in r[::4]:
                    dd=(x-cx)**2+(y-cy)**2
                    if dd<bd: bd=dd; best=key.split('|')[1]
    return best
unitConts=[]
for ui,(oi,key) in enumerate(units):
    if key.startswith('piece:'):
        dd=disp.get(key[6:],{})
        side=dd.get('side')
        if side: unitConts.append([side]); continue
        owner=places[oi]['id'] if oi!=65535 else None
        if owner in byid:
            p=byid[owner]
            if sliced(p):
                pts=[q for r in unit_rings.get(ui,[]) for q in r]
                k=nearest_slice(owner,pts) if pts else None
                unitConts.append([k] if k else pconts(p))
            else: unitConts.append(pconts(p))
        else: unitConts.append([])
        continue
    if '|' in key: unitConts.append([key.split('|')[1]]); continue
    owner=places[oi]['id'] if oi!=65535 else None
    unitConts.append(pconts(byid[owner]) if owner else [])
def pieceCont(ui,owner):
    dd=disp.get(units[ui][1][6:],{})
    if dd.get('side'): return [dd['side']]
    if owner not in byid: return []
    p=byid[owner]
    if sliced(p):
        pts=[q for r in unit_rings.get(ui,[]) for q in r]
        k=nearest_slice(owner,pts) if pts else None
        return [k] if k else pconts(p)
    return pconts(p)
pieceConts={}
for ui,(oi,key) in enumerate(units):
    if not key.startswith('piece:'): continue
    dd=disp.get(key[6:],{})
    opts=set((dd.get('options') or [])+[dd.get('controller'),dd.get('default'),dd.get('pref')])
    pieceConts[key]={o:pieceCont(ui,o) for o in opts if o in byid}
placeConts=[pconts(p) for p in places]
def box(rs):
    xs=[x for r in rs for x,_ in r]; ys=[y for r in rs for _,y in r]
    return [min(xs),min(ys),max(xs),max(ys)]
def entityBox(i,k):
    rs=[r for ui,(oi,key) in enumerate(units) if oi==i and k in unitConts[ui] for r in unit_rings.get(ui,[])]
    if not rs: return None
    bs=[box([r]) for r in rs]
    big=max(range(len(bs)),key=lambda j:(bs[j][2]-bs[j][0])*(bs[j][3]-bs[j][1]))
    mx=(bs[big][0]+bs[big][2])/2; my=(bs[big][1]+bs[big][3])/2
    B=bs[big]
    def gap(b): return max(B[0]-b[2], b[0]-B[2], B[1]-b[3], b[1]-B[3], 0)
    # the core: the biggest ring and what lies within 15 map units of it (no far islands)
    sel=[b for b in bs if gap(b)<15]
    return [min(b[0] for b in sel),min(b[1] for b in sel),max(b[2] for b in sel),max(b[3] for b in sel)]
def counts(p): return p['k'] in ('country','entity')
far={'Micronesia','Polynesia'}
def members(k): return [i for i,p in enumerate(places) if k in placeConts[i]]
def shift(b,k):
    if k=='Oceania' and (b[0]+b[2])/2<300: return [b[0]+1000,b[1],b[2]+1000,b[3]]
    return b
def pad0(w,h): return max(w,h)*0.05+3
def union(bs): return [min(b[0] for b in bs),min(b[1] for b in bs),max(b[2] for b in bs),max(b[3] for b in bs)]
def padded(b):
    p=pad0(b[2]-b[0],b[3]-b[1]); return [b[0]-p,b[1]-p,b[2]+p,b[3]+p]
def contFrame(k):
    bs=[shift(b,k) for i in members(k) if not places[i].get('tiny') and counts(places[i]) for b in [entityBox(i,k)] if b]
    if not bs: bs=[shift(b,k) for i in members(k) if not places[i].get('tiny') for b in [entityBox(i,k)] if b]
    return padded(union(bs)) if bs else None
def contView(k):
    cb=contFrame(k)
    if cb is None: return None
    inv=lambda i: k!='Oceania' or places[i].get('sub') not in far
    bs=[shift(b,k) for i in members(k) if inv(i) and not places[i].get('tiny') and counts(places[i]) for b in [entityBox(i,k)] if b]
    if not bs: return cb
    u=union(bs)
    if k=='Oceania': cb=padded(u)
    grew=False
    for i in members(k):
        if not inv(i) or places[i].get('tiny') or counts(places[i]): continue
        b=entityBox(i,k)
        if not b: continue
        b=shift(b,k)
        touches=b[2]>cb[0] and b[0]<cb[2] and b[3]>cb[1] and b[1]<cb[3]
        past=b[0]<cb[0] or b[2]>cb[2] or b[1]<cb[1] or b[3]>cb[3]
        if touches and past:
            grew=True; u=union([u,b])
    return padded(u) if grew else cb
Y72=proj(0,72)[1]
def cut(v):
    # the continent seen geographically: nothing north of 72 N stretches it (the Arctic islands)
    return [v[0], max(v[1], Y72-3), v[2], v[3]]
views={k:[round(x,3) for x in cut(contView(k))] for k in conts if k!='Antarctica' and contView(k)}
print(views)
m=json.load(open('world-meta.json'))
m['unitConts']=unitConts; m['pieceConts']=pieceConts; m['placeConts']=placeConts; m['contViews']=views
json.dump(m,open('world-meta.json','w'),ensure_ascii=False)
print(len(unitConts), sum(1 for u in unitConts if not u), 'units without continent')

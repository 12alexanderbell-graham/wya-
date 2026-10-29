# every land border on the map, by the pair of places it is between: how long, how finely drawn (median segment, km)
import wyad, numpy as np, sys, json
d,h,b=wyad.pack(sys.argv[1])
acc={}
for t in h['tiles']:
    th,items,xl=wyad.tile(d,b,t)
    keys=[k for k,_ in items]
    lines=[]
    for e in th.get('e',[]):
        a,bb,ri,st,n=e
        rg=items[a][1][ri]; lines.append((a,bb,[rg[(st+i)%len(rg)] for i in range(n)]))
    for a,bb,l in xl: lines.append((a,bb,l))
    for a,bb,l in lines:
        if bb<0 or len(l)<2: continue
        p=tuple(sorted((keys[a],keys[bb])))
        A=np.array(l); s=np.hypot(*(np.diff(A,axis=0)*[np.cos(np.radians(A[:,1].mean())),1]).T)*111
        acc.setdefault(p,[]).append(s)
out=[]
for p,v in acc.items():
    s=np.concatenate(v); out.append((p,float(np.median(s)),float(s.sum())))
json.dump(out,open(sys.argv[2],'w'))

import json,statistics,random,collections
T=json.load(open('station-truth.json'))
S={}
for v in ('tasmax','tasmin','pr'):
    for m in range(1,13):
        d=json.load(open('s_%s_%02d.json'%(v,m)))
        for k,x in d.items():
            if k[0]=='s': S.setdefault(k[1:],{}).setdefault(v,[None]*12)[m-1]=x
def band(lat): a=abs(lat); return 0 if a<23.5 else (1 if a<40 else 2)
def warm(lat,i): return (3<=i<=8) if lat>=0 else (i<=2 or i>=9)
ids=[i for i in T if i in S and None not in S[i]['tasmax']]
print('independent stations:',len(ids))
# the table fitted on capitals earlier
CAPT={(0,False):2.3,(0,True):2.25,(1,False):1.7,(1,True):1.95,(2,False):0.95,(2,True):1.7}
def mae(ids,f,kind):
    e=[abs(f(i,m)-T[i][kind][m]) for i in ids for m in range(12)]; return statistics.mean(e)
raw_hi=mae(ids,lambda i,m:S[i]['tasmax'][m],'hi')
cap_hi=mae(ids,lambda i,m:S[i]['tasmax'][m]+CAPT[(band(T[i]['ll'][0]),warm(T[i]['ll'][0],m))],'hi')
raw_lo=mae(ids,lambda i,m:S[i]['tasmin'][m],'lo')
print('highs: raw CHELSA %.2f   with capital-fitted correction %.2f'%(raw_hi,cap_hi))
print('lows : raw CHELSA %.2f'%raw_lo)
res=collections.defaultdict(list); resl=collections.defaultdict(list)
for i in ids:
    lat=T[i]['ll'][0]
    for m in range(12):
        res[(band(lat),warm(lat,m))].append(T[i]['hi'][m]-S[i]['tasmax'][m])
        resl[(band(lat),warm(lat,m))].append(T[i]['lo'][m]-S[i]['tasmin'][m])
for k in sorted(res): print('  %s %s n=%d  hi bias %+.2f  lo bias %+.2f'%(['trop','subt','mid/high'][k[0]],'summer' if k[1] else 'winter',len(res[k]),statistics.median(res[k]),statistics.median(resl[k])))
# 20 random splits over the 625: fit table on half, test on other half; hi and lo
random.seed(5); th=[];tl=[];bh=[];bl=[]
for t in range(20):
    random.shuffle(ids); A,B=ids[:len(ids)//2],ids[len(ids)//2:]
    tabh=collections.defaultdict(list); tabl=collections.defaultdict(list)
    for i in A:
        lat=T[i]['ll'][0]
        for m in range(12):
            k=(band(lat),warm(lat,m)); tabh[k].append(T[i]['hi'][m]-S[i]['tasmax'][m]); tabl[k].append(T[i]['lo'][m]-S[i]['tasmin'][m])
    tabh={k:statistics.median(v) for k,v in tabh.items()}; tabl={k:statistics.median(v) for k,v in tabl.items()}
    th.append(mae(B,lambda i,m:S[i]['tasmax'][m]+tabh[(band(T[i]['ll'][0]),warm(T[i]['ll'][0],m))],'hi'))
    tl.append(mae(B,lambda i,m:S[i]['tasmin'][m]+tabl[(band(T[i]['ll'][0]),warm(T[i]['ll'][0],m))],'lo'))
    bh.append(mae(B,lambda i,m:S[i]['tasmax'][m],'hi')); bl.append(mae(B,lambda i,m:S[i]['tasmin'][m],'lo'))
print('held-out: hi raw %.2f -> corrected %.2f ; lo raw %.2f -> corrected %.2f'%(statistics.mean(bh),statistics.mean(th),statistics.mean(bl),statistics.mean(tl)))
# rain
pairs=[(S[i]['pr'][m],T[i]['mm'][m]) for i in ids for m in range(12) if T[i]['mm'][m] is not None and S[i]['pr'][m] is not None]
print('rain: %d station-months; median CHELSA/station ratio %.2f; median abs diff %.0f mm; median rel diff %.0f%%'%(len(pairs),statistics.median([a/max(b,1) for a,b in pairs if b>5]),statistics.median([abs(a-b) for a,b in pairs]),100*statistics.median([abs(a-b)/max(b,10) for a,b in pairs])))

"""Place every guide under its country, add its Wikidata id, and write one file per country
the way the listings are stored, so the app loads only the country it is showing."""
import json, io, os, collections, re
G=json.load(io.open('wv-guides-all.json',encoding='utf-8'))
Q=json.load(io.open('wv-qids.json',encoding='utf-8'))
AC=json.load(io.open('/home/claude/dl/article-country.json',encoding='utf-8'))   # article -> ISO2 (23,082)
# country articles themselves -> ISO2, from the country guides
WV=json.load(io.open('/home/claude/dl/wv-countries-v2.json',encoding='utf-8'))
CF=json.load(io.open('/home/claude/facts/country-facts.json',encoding='utf-8'))
name2cc={}
for cc,v in CF.items():
    for n in [v.get('name')]+list(v.get('alias') or []):
        if n: name2cc.setdefault(n.lower(),cc)
cc_of={}
for t in G:
    if t in AC: cc_of[t]=AC[t]
    elif G[t]['kind']=='country' and t.lower() in name2cc: cc_of[t]=name2cc[t.lower()]
# walk IsPartOf upward for the rest
def up(t,depth=0):
    if t in cc_of: return cc_of[t]
    if depth>12 or t not in G: return None
    p=G[t].get('in')
    if not p: return None
    r=up(p,depth+1)
    if r: cc_of[t]=r
    return r
for t in G: up(t)
os.makedirs('wv-guides',exist_ok=True)
by=collections.defaultdict(dict); nocc=[]
for t,v in G.items():
    v=dict(v)
    if t in Q: v['q']=Q[t]
    cc=cc_of.get(t)
    if cc: by[cc.lower()][t]=v
    else: nocc.append(t)
for cc,d in by.items():
    json.dump(d,io.open('wv-guides/%s.json'%cc,'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
json.dump({t:G[t] for t in nocc},io.open('wv-guides/_no-country.json','w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
tot=sum(os.path.getsize('wv-guides/'+f) for f in os.listdir('wv-guides'))
print('countries',len(by),'placed',sum(len(d) for d in by.values()),'no country',len(nocc),'size %.1f MB'%(tot/1e6))
print('no-country sample', nocc[:15])
fr=json.load(io.open('wv-guides/fr.json',encoding='utf-8')); k='Lyon' if 'Lyon' in fr else list(fr)[0]
print(k, json.dumps(fr[k],ensure_ascii=False)[:900])

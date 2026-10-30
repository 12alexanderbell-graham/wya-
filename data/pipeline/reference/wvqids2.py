import os
import json, urllib.parse, urllib.request, time
UA='wya-travel-app-data/1.0 (wikivoyage pageprops; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
G=json.load(open('/home/claude/guides/wv-guides-all.json',encoding='utf-8'))
Q=json.load(open('/home/claude/guides/wv-qids.json',encoding='utf-8'))
todo=[t for t in G if t not in Q]
print('guides',len(G),'have qid',len(G)-len(todo),'to ask',len(todo),flush=True)
for k in range(0,len(todo),50):
    ch=todo[k:k+50]
    body=urllib.parse.urlencode({'action':'query','prop':'pageprops','ppprop':'wikibase_item','titles':'|'.join(ch),'format':'json','formatversion':2,'redirects':1}).encode()
    for a in range(5):
        try:
            r=urllib.request.Request('https://en.wikivoyage.org/w/api.php',data=body,headers={'User-Agent':UA})
            d=json.loads(urllib.request.urlopen(r,timeout=60).read().decode()); break
        except Exception as e: time.sleep(5*(a+1)); d={}
    for p in (d.get('query',{}) or {}).get('pages',[]):
        q=(p.get('pageprops') or {}).get('wikibase_item')
        if q: Q[p['title']]=q
    if (k//50)%40==0: print(' ',k,len(Q),flush=True)
    time.sleep(0.3)
json.dump(Q,open('/home/claude/guides/wv-qids.json','w'),ensure_ascii=False)
print('SAVED',len(Q),'guides with a qid',sum(1 for t in G if t in Q))

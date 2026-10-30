import os
"""Which Wikidata item each Wikivoyage article is about, so a guide can be joined to
destinations.json, region-facts.json and the photographs."""
import json, urllib.parse, urllib.request, time
UA='wya-travel-app-data/1.0 (wikivoyage sitelinks; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
out={}; off=0; step=20000
while True:
    q='''SELECT ?item ?name WHERE { ?a schema:about ?item ; schema:isPartOf <https://en.wikivoyage.org/> ; schema:name ?name . } ORDER BY ?item LIMIT %d OFFSET %d'''%(step,off)
    u='https://query.wikidata.org/sparql?format=json&query='+urllib.parse.quote(q)
    for a in range(5):
        try:
            r=urllib.request.Request(u,headers={'User-Agent':UA,'Accept':'application/sparql-results+json'})
            with urllib.request.urlopen(r,timeout=300) as f: d=json.loads(f.read().decode()); break
        except Exception as e:
            print('retry',a,str(e)[:80],flush=True); time.sleep(30*(a+1)); d=None
    if not d: break
    b=d['results']['bindings']
    for x in b: out[x['name']['value']]=x['item']['value'].rsplit('/',1)[-1]
    print('offset',off,'got',len(b),'total',len(out),flush=True)
    if len(b)<step: break
    off+=step; time.sleep(5)
json.dump(out,open('/home/claude/guides/wv-qids.json','w'),ensure_ascii=False)
print('SAVED',len(out))

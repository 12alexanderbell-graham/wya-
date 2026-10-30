import os
#!/usr/bin/env python3
"""Every UNESCO World Heritage site: where it is, which country, the year it was inscribed,
why (the criteria), whether it is in danger, and a photograph.  From Wikidata, which is not
rate-limited."""
import json, io, urllib.parse, urllib.request, time
UA='wya-travel-app-data/1.0 (world heritage; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
Q='''SELECT ?s ?sLabel ?sDesc ?coord ?cc ?start ?crit ?critLabel ?img ?danger ?kind ?kindLabel WHERE {
  ?s p:P1435 ?st . ?st ps:P1435 wd:Q9259 .
  OPTIONAL { ?st pq:P580 ?start }
  OPTIONAL { ?s wdt:P625 ?coord }
  OPTIONAL { ?s wdt:P17 ?country . ?country wdt:P297 ?cc }
  OPTIONAL { ?s wdt:P2614 ?crit }
  OPTIONAL { ?s wdt:P18 ?img }
  OPTIONAL { ?s wdt:P31 ?kind }
  BIND(EXISTS{ ?s wdt:P1435 wd:Q2497649 } AS ?danger)
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}'''
u='https://query.wikidata.org/sparql?format=json&query='+urllib.parse.quote(Q)
for a in range(5):
    try:
        r=urllib.request.Request(u, headers={'User-Agent':UA,'Accept':'application/sparql-results+json'})
        with urllib.request.urlopen(r, timeout=300) as f: d=json.loads(f.read().decode())
        break
    except Exception as e:
        print('retry',a,str(e)[:90], flush=True); time.sleep(15*(a+1)); d=None
if not d: raise SystemExit('no answer from wikidata')
out={}
for b in d['results']['bindings']:
    q=b['s']['value'].rsplit('/',1)[-1]
    e=out.setdefault(q,{'n':None,'d':None,'ll':None,'cc':[],'year':None,'crit':[],'img':[],'danger':False,'kind':[]})
    if 'sLabel' in b and not e['n']: e['n']=b['sLabel']['value']
    if 'sDesc' in b and not e['d']: e['d']=b['sDesc']['value']
    if 'coord' in b and not e['ll']:
        v=b['coord']['value']
        if v.startswith('Point('):
            lon,lat=v[6:-1].split(); e['ll']=[round(float(lat),5),round(float(lon),5)]
    if 'cc' in b and b['cc']['value'] not in e['cc']: e['cc'].append(b['cc']['value'])
    if 'start' in b and not e['year']: e['year']=b['start']['value'][:4]
    if 'critLabel' in b:
        c=b['critLabel']['value']
        if c not in e['crit']: e['crit'].append(c)
    if 'img' in b:
        f=urllib.parse.unquote(b['img']['value'].rsplit('/',1)[-1]).replace('_',' ')
        if f not in e['img']: e['img'].append(f)
    if b.get('danger',{}).get('value')=='true': e['danger']=True
    if 'kindLabel' in b:
        k=b['kindLabel']['value']
        if k not in e['kind'] and not k.startswith('Q'): e['kind'].append(k)
json.dump(out, io.open('/home/claude/extra/unesco.json','w',encoding='utf-8'), ensure_ascii=False)
withll=sum(1 for v in out.values() if v['ll']); withimg=sum(1 for v in out.values() if v['img'])
print('SAVED %d world heritage sites, %d with coordinates, %d with a photograph, %d in danger'
      % (len(out), withll, withimg, sum(1 for v in out.values() if v['danger'])), flush=True)

import json, urllib.request, urllib.parse, time
names=["Albert Park Circuit","Shanghai International Circuit","Suzuka International Racing Course","Miami International Autodrome","Circuit Gilles Villeneuve","Circuit de Monaco","Circuit de Barcelona-Catalunya","Red Bull Ring","Silverstone Circuit","Circuit de Spa-Francorchamps","Hungaroring","Circuit Zandvoort","Monza Circuit","Madring","Baku City Circuit","Sepang International Circuit","Marina Bay Street Circuit","Circuit of the Americas","Autódromo Hermanos Rodríguez","Interlagos Circuit","Las Vegas Strip Circuit","Lusail International Circuit","Yas Marina Circuit"]
out={}
for n in names:
    q='''SELECT ?i ?l ?coord WHERE { SERVICE wikibase:mwapi { bd:serviceParam wikibase:endpoint "www.wikidata.org"; wikibase:api "EntitySearch"; mwapi:search "%s"; mwapi:language "en". ?i wikibase:apiOutputItem mwapi:item. }
      ?i wdt:P625 ?coord . ?i rdfs:label ?l FILTER(lang(?l)="en") } LIMIT 3''' % n
    for a in range(4):
        try:
            req=urllib.request.Request('https://query.wikidata.org/sparql', data=urllib.parse.urlencode({'query':q}).encode(),
                headers={'User-Agent':'wya-data-build/1.0','Accept':'application/sparql-results+json','Content-Type':'application/x-www-form-urlencoded'})
            d=json.load(urllib.request.urlopen(req, timeout=60))
            out[n]=[(b['i']['value'].rsplit('/',1)[1], b['l']['value'], b['coord']['value']) for b in d['results']['bindings']]
            print(n, out[n], flush=True); break
        except Exception as e:
            print('retry', n, e, flush=True); time.sleep(62)
    json.dump(out,open('tracks.json','w'))
    time.sleep(61)
print('done', flush=True)

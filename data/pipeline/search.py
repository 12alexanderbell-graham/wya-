import json, sys, time, urllib.parse, urllib.request
qs=sys.argv[1:]
for q in qs:
    url="https://nominatim.openstreetmap.org/search?q=%s&format=json&limit=6"%urllib.parse.quote(q)
    req=urllib.request.Request(url,headers={'User-Agent':'wya-map-build/1.0'})
    try: r=json.load(urllib.request.urlopen(req,timeout=20))
    except Exception as e: print('==',q,'ERR',e); continue
    print('==',q)
    for x in r:
        if x['osm_type']=='relation': print('  ',x['osm_id'],x.get('class'),x.get('type'),x.get('addresstype'),x['display_name'][:90])
    time.sleep(1.1)

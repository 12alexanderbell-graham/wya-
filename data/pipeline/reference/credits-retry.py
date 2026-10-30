import os
#!/usr/bin/env python3
"""Ask again about the pictures that came back empty, in small batches and one at a time at the
end, so an empty answer means the file really is not on Commons."""
import json, io, re, time, urllib.parse, urllib.request
UA='wya-travel-app-data/1.0 (image licences; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
COM='https://commons.wikimedia.org/w/api.php'
OUT='/home/claude/facts/image-credits.json'
out=json.load(io.open(OUT,encoding='utf-8'))
def api(**p):
    p.setdefault('format','json'); p.setdefault('formatversion',2)
    body=urllib.parse.urlencode(p).encode()
    for k in range(5):
        try:
            r=urllib.request.Request(COM,data=body,headers={'User-Agent':UA})
            with urllib.request.urlopen(r,timeout=80) as f: return json.loads(f.read().decode('utf-8'))
        except Exception as e:
            if k==4: print('   dead:',str(e)[:60],flush=True); return None
            time.sleep(3*(k+1))
def strip(h): return re.sub(r'\s+',' ',re.sub(r'<[^>]+>',' ',h or '')).strip()
def take(d):
    got=0
    for pg in (d.get('query',{}) or {}).get('pages',[]) or []:
        t=pg.get('title','')[5:]
        if pg.get('missing'): out[t]={'missing':True}; continue
        ii=(pg.get('imageinfo') or [{}])[0]; em=ii.get('extmetadata') or {}
        def g(k):
            v=(em.get(k) or {}).get('value'); return strip(v) if v else None
        rec={}
        for k,col in (('lic','LicenseShortName'),('by','Artist'),('src','Credit'),
                      ('terms','UsageTerms'),('attrib','AttributionRequired')):
            v=g(col)
            if v: rec[k]=v[:170]
        lu=(em.get('LicenseUrl') or {}).get('value')
        if lu: rec['url']=lu
        if ii.get('url'): rec['file']=ii['url']
        if rec: out[t]=rec; got+= 1 if rec.get('lic') else 0
    return got
todo=[k for k,v in out.items() if not v.get('lic') and not v.get('missing')]
print('%d to ask again about'%len(todo),flush=True)
B=20; fixed=0
for i in range(0,len(todo),B):
    ch=todo[i:i+B]
    d=api(action='query',prop='imageinfo',iiprop='extmetadata|url',titles='|'.join('File:'+t for t in ch))
    if d: fixed+=take(d)
    if (i//B)%20==0:
        json.dump(out,io.open(OUT,'w',encoding='utf-8'),ensure_ascii=False)
        print('  %5d/%5d  %d newly credited'%(min(i+B,len(todo)),len(todo),fixed),flush=True)
    time.sleep(0.2)
# whatever is still blank, ask about singly
left=[k for k,v in out.items() if not v.get('lic') and not v.get('missing')]
print('%d still blank, asking singly'%len(left),flush=True)
for i,t in enumerate(left,1):
    d=api(action='query',prop='imageinfo',iiprop='extmetadata|url',titles='File:'+t)
    if d: fixed+=take(d)
    if not out.get(t,{}).get('lic'): out.setdefault(t,{})['missing']=True
    if i%100==0:
        json.dump(out,io.open(OUT,'w',encoding='utf-8'),ensure_ascii=False)
        print('   singly %d/%d'%(i,len(left)),flush=True)
    time.sleep(0.15)
json.dump(out,io.open(OUT,'w',encoding='utf-8'),ensure_ascii=False)
lic=sum(1 for v in out.values() if v.get('lic'))
print('DONE %d pictures, %d with a licence, %d genuinely not on Commons'
      %(len(out),lic,sum(1 for v in out.values() if v.get('missing'))),flush=True)

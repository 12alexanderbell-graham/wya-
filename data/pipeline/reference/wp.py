import os
#!/usr/bin/env python3
"""The small facts a country page needs, from Wikipedia's own tables, through the API
(action=parse gives the rendered HTML, which parses far more reliably than wikitext)."""
import json, re, time, urllib.parse, urllib.request, sys
UA='wya-travel-app-data/1.0 (country facts; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
_last=[0.0]
def api(base, **p):
    dt=time.time()-_last[0]
    if dt<1.0: time.sleep(1.0-dt)
    _last[0]=time.time()
    p.setdefault('format','json'); p.setdefault('formatversion',2)
    url=base+'?'+urllib.parse.urlencode(p)
    for k in range(4):
        try:
            r=urllib.request.Request(url, headers={'User-Agent':UA})
            with urllib.request.urlopen(r, timeout=60) as f: return json.loads(f.read().decode())
        except Exception as e:
            if k==3: return {}
            time.sleep(5*(k+1))
    return {}
def page_html(title, wiki='https://en.wikipedia.org/w/api.php'):
    d=api(wiki, action='parse', page=title, prop='text', disabletoc=1)
    return (d.get('parse') or {}).get('text') or ''
if __name__=='__main__':
    h=page_html(sys.argv[1] if len(sys.argv)>1 else 'Mains electricity by country')
    print(len(h))
    open('/home/claude/facts/last.html','w').write(h)

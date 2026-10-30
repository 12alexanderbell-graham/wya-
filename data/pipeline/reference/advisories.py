#!/usr/bin/env python3
"""What three governments currently tell their own citizens about travelling to each country.
Three sources on purpose, because a single government's advisory is that government's view:
the United States (State Department), the United Kingdom (FCDO) and Canada (GAC).  Each is
stored under its own name with its own wording and date; nothing is merged into one score."""
import json, io, re, time, urllib.request, urllib.parse, os
UA='wya-travel-app-data/1.0 (travel advisories; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
OUT='/home/claude/extra/advisories.json'
out=json.load(io.open(OUT,encoding='utf-8')) if os.path.exists(OUT) else {}
def get(u, raw=False, tries=4):
    for a in range(tries):
        try:
            r=urllib.request.Request(u, headers={'User-Agent':UA})
            with urllib.request.urlopen(r, timeout=90) as f:
                b=f.read(); return b if raw else json.loads(b.decode('utf-8'))
        except Exception as e:
            if a==tries-1: return None
            time.sleep(4*(a+1))
def strip(h): return re.sub(r'\s+',' ', re.sub(r'<[^>]+>',' ', h or '')).strip()

# ---- Canada: one JSON, every country, level 1-4 plus regional advisories --------------
ca=get('https://data.international.gc.ca/travel-voyage/index-alpha-eng.json')
n=0
if ca:
    LEVEL={0:'Exercise normal security precautions',1:'Exercise a high degree of caution',
           2:'Avoid non-essential travel',3:'Avoid all travel'}
    for cc, v in (ca.get('data') or {}).items():
        e=v.get('eng') or {}
        lvl=v.get('advisory-state')
        rec={'name':e.get('name') or v.get('country-eng'),
             'level':lvl,
             'text':e.get('advisory-text') or LEVEL.get(lvl),
             'updated':(v.get('date-published') or {}).get('date'),
             'friendlyDate':e.get('friendly-date'),
             'regionalAdvisory':bool(v.get('has-regional-advisory')),
             'warning':bool(v.get('has-advisory-warning')),
             'lastChange':e.get('recent-updates') or v.get('recent-updates-type'),
             'url':'https://travel.gc.ca/destinations/'+(e.get('url-slug') or '')}
        out.setdefault(cc,{})['ca']=rec; n+=1
    out.setdefault('_meta',{})['ca']={'source':'Global Affairs Canada, travel.gc.ca',
        'licence':'Open Government Licence - Canada',
        'generated':((ca.get('metadata') or {}).get('generated') or {}).get('date')}
print('Canada: %d countries' % n, flush=True)

# ---- United States: the advisories RSS, one item per country -------------------------
us=get('https://travel.state.gov/_res/rss/TAsTWs.xml', raw=True)
n=0
if us:
    xml=us.decode('utf-8','replace')
    for item in re.findall(r'<item>(.*?)</item>', xml, re.S):
        def tag(t):
            m=re.search(r'<%s>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</%s>'%(t,t), item, re.S)
            return m.group(1).strip() if m else None
        title=tag('title') or ''
        m=re.match(r'(.*?)\s*[-–]\s*(Level\s*\d[^,;]*)', title)
        country=(m.group(1) if m else title).strip()
        level=(m.group(2) if m else None)
        out.setdefault('_us',{})[country]={'level':level,'title':title,
            'text':strip(tag('description'))[:900],'url':tag('link'),'updated':tag('pubDate')}
        n+=1
    out.setdefault('_meta',{})['us']={'source':'U.S. Department of State, travel.state.gov',
        'licence':'U.S. Government work, public domain','feed':'https://travel.state.gov/_res/rss/TAsTWs.xml'}
print('United States: %d advisories' % n, flush=True)

# ---- United Kingdom: gov.uk content API, one call per country ------------------------
idx=get('https://www.gov.uk/api/content/foreign-travel-advice')
links=[]
if idx:
    def walk(o):
        if isinstance(o,dict):
            if o.get('base_path','').startswith('/foreign-travel-advice/'):
                links.append((o['base_path'], o.get('title')))
            for v in o.values(): walk(v)
        elif isinstance(o,list):
            for v in o: walk(v)
    walk(idx)
seen=set(); links=[l for l in links if not (l[0] in seen or seen.add(l[0]))]
print('United Kingdom: %d countries to ask about' % len(links), flush=True)
uk=out.setdefault('_uk',{})
for i,(bp,title) in enumerate(links,1):
    if title in uk: continue
    d=get('https://www.gov.uk/api/content'+urllib.parse.quote(bp))
    if not d: continue
    det=d.get('details') or {}
    parts=det.get('parts') or []
    summary=''
    for p in parts:
        if p.get('slug') in ('summary','warnings-and-insurance') or not summary:
            summary=strip(p.get('body'))[:1200]
            if p.get('slug')=='summary': break
    uk[title]={'alert':strip(det.get('alert_status') and ' '.join(det['alert_status']) or ''),
               'change':strip(det.get('change_description') or '')[:400],
               'summary':summary, 'updated':(d.get('public_updated_at') or '')[:10],
               'url':'https://www.gov.uk'+bp}
    if i%25==0:
        json.dump(out, io.open(OUT,'w',encoding='utf-8'), ensure_ascii=False)
        print('  UK %d/%d' % (i,len(links)), flush=True)
    time.sleep(0.25)
out.setdefault('_meta',{})['uk']={'source':'UK Foreign, Commonwealth & Development Office, gov.uk',
    'licence':'Open Government Licence v3.0'}
json.dump(out, io.open(OUT,'w',encoding='utf-8'), ensure_ascii=False)
print('SAVED  Canada %d · United States %d · United Kingdom %d'
      % (sum(1 for k,v in out.items() if not k.startswith('_') and v.get('ca')),
         len(out.get('_us',{})), len(out.get('_uk',{}))), flush=True)

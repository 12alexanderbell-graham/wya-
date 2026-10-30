# -*- coding: utf-8 -*-
"""A written guide for every destination on Wikivoyage, not only the 248 countries: the
opening paragraphs, Understand, Get in, Get around, See, Do, Eat, Drink, Sleep, Stay safe,
Connect and Go next as plain prose (the listings are already in wv-listings), plus where the
article sits (IsPartOf), its coordinates, its banner, what kind of place it is and how
finished the article is.  CC BY-SA 4.0, Wikivoyage: the app must credit and link it."""
import bz2, re, io, json, os, sys, collections
sys.path.insert(0, '/home/claude/dl')
SEC = re.compile(r'^(={2,6})\s*([^=\n]+?)\s*\1\s*$', re.M)
def sections(t):
    marks = [(m.start(), m.end(), len(m.group(1)), m.group(2).strip()) for m in SEC.finditer(t)]
    out = []
    for i, (pos, e, lvl, name) in enumerate(marks):
        end = len(t)
        for j in range(i + 1, len(marks)):
            if marks[j][2] <= lvl: end = marks[j][0]; break
        out.append((name, lvl, t[e:end]))
    return out, (marks[0][0] if marks else len(t))
def norm(s): return re.sub(r'[^a-z ]+', '', s.lower()).strip()
NAMES = {
 'understand':['understand','background','history'], 'getin':['get in','getting in','arrive'],
 'around':['get around','getting around'], 'see':['see','see and do','sights','attractions'],
 'do':['do','activities'], 'buy':['buy','shopping'], 'eat':['eat','eat and drink','food'],
 'drink':['drink','nightlife','drinks'], 'sleep':['sleep','accommodation'],
 'safe':['stay safe','safety','stay safe and healthy'], 'connect':['connect','communicate'],
 'next':['go next','nearby'], 'climate':['climate','weather','when to go'],
 'districts':['districts'], 'cities':['cities','cities and towns','towns','towns and villages'],
 'other':['other destinations']}
CAP = {'intro':900,'understand':1100,'getin':900,'around':700,'see':700,'do':700,'buy':450,
       'eat':550,'drink':400,'sleep':450,'safe':650,'connect':300,'next':500,'climate':600}
def clean(s):
    s = re.sub(r'\[\[(?:File|Image):[\s\S]*?\]\]', ' ', s)
    for _ in range(4): s = re.sub(r'\{\{[^{}]*\}\}', ' ', s)
    s = re.sub(r'\{\|[\s\S]*?\|\}', ' ', s)                      # tables
    s = re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', r'\1', s)
    s = re.sub(r'\[https?://\S+\s+([^\]]+)\]', r'\1', s); s = re.sub(r'\[https?://\S+\]', ' ', s)
    s = re.sub(r"'''?", '', s)
    s = re.sub(r'<ref[\s\S]*?</ref>|<ref[^>]*/>|<!--[\s\S]*?-->|<[^>]+>', ' ', s)
    s = re.sub(r'^\s*=+.*?=+\s*$', ' ', s, flags=re.M)
    s = re.sub(r'^[*#:;]+\s*', '', s, flags=re.M)
    s = re.sub(r'&nbsp;', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()
def cut(s, n):
    if len(s) <= n: return s
    s = s[:n]; k = max(s.rfind('. '), s.rfind('! '), s.rfind('? '))
    return (s[:k+1] if k > n*0.5 else s.rsplit(' ',1)[0]+' …')
STATUS = re.compile(r'\{\{\s*(star|guide|usable|outline|stub)(city|district|region|country|park|airport|itinerary|topic|diveguide|phrasebook|ruralarea|continent|travel ?topic)?\s*[|}]', re.I)
PART = re.compile(r'\{\{\s*[Ii]s\s*[Pp]art\s*[Oo]f\s*\|\s*([^}|]+)')
GEO = re.compile(r'\{\{\s*[Gg]eo\s*\|\s*(-?[\d.]+)\s*\|\s*(-?[\d.]+)')
BAN = re.compile(r'\{\{\s*[Pp]agebanner\s*\|\s*(?:[Ff]ile:)?([^|}\n]+)')
REDIR = re.compile(r'#\s*redirect', re.I)
DAB = re.compile(r'\{\{\s*(disamb|disambiguation|dab)\b', re.I)
def scan(h):
    title=None; inpage=False; buf=[]
    for line in h:
        if '<title>' in line:
            m=re.search(r'<title>(.*?)</title>',line); title=m.group(1) if m else None
        if '<text' in line: inpage=True; buf=[]
        if inpage: buf.append(line)
        if '</text>' in line and inpage:
            inpage=False
            if title and ':' not in title: yield title, ''.join(buf)
import html
out={}; kinds=collections.Counter()
with bz2.open('/home/claude/dl/wikivoyage.xml.bz2','rt',encoding='utf-8') as f:
    for title, raw in scan(f):
        t = html.unescape(re.sub(r'^.*?<text[^>]*>', '', raw, count=1, flags=re.S).rsplit('</text>',1)[0])
        if REDIR.match(t.strip()[:30]) or DAB.search(t[:3000]): continue
        st = STATUS.search(t)
        if not st: continue                                   # travel topics, phrasebooks etc. carry other templates; keep only places
        status, kind = st.group(1).lower(), (st.group(2) or 'city').lower().replace(' ','')
        if kind in ('phrasebook','traveltopic','topic','itinerary','diveguide'): continue
        secs, first = sections(t)
        rec = {'kind':kind, 'status':status}
        m = PART.search(t);  rec['in'] = m.group(1).strip() if m else None
        m = GEO.search(t)
        if m:
            try: rec['ll'] = [round(float(m.group(1)),5), round(float(m.group(2)),5)]
            except ValueError: pass
        m = BAN.search(t); rec['banner'] = m.group(1).strip() if m else None
        intro = cut(clean(t[:first]), CAP['intro'])
        if intro: rec['intro'] = intro
        byname = {}
        for nm, lvl, body in secs:
            if lvl == 2: byname.setdefault(norm(nm), body)
        for key, names in NAMES.items():
            body = next((byname[n] for n in names if n in byname), None)
            if body is None: continue
            if key in ('districts','cities','other'):
                items = [ (mm.group(2) or mm.group(1)).strip() for mm in re.finditer(r'^\*\s*(?:\'{2,3})?\s*\[\[([^\]|]+)(?:\|([^\]]+))?\]\]', body, re.M)]
                items += [ re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', r'\1', mm.group(1)).strip() for mm in re.finditer(r'\{\{\s*marker[^}]*?name\s*=\s*([^|}]+)', body)]
                items = [i for i in dict.fromkeys(items) if i][:30]
                if items: rec[key] = items
            else:
                txt = cut(clean(body), CAP[key])
                if len(txt) > 30: rec[key] = txt
        out[title] = rec; kinds[kind] += 1
json.dump(out, io.open('/home/claude/guides/wv-guides-all.json','w',encoding='utf-8'), ensure_ascii=False)
print('guides', len(out), dict(kinds.most_common()), flush=True)
st = collections.Counter(v['status'] for v in out.values()); print('status', dict(st))
print('with intro', sum(1 for v in out.values() if v.get('intro')), 'with coords', sum(1 for v in out.values() if v.get('ll')))

#!/usr/bin/env python3
"""Wikivoyage's listings, properly.

The first pass kept only a name, a point and one line of text. Every {{see}}, {{do}}, {{eat}},
{{drink}}, {{buy}}, {{sleep}} and {{listing}} on Wikivoyage also carries the address, how to
get there, the phone, the website, the opening hours, the price and a Wikidata id - which is
what a travel app actually shows - and it sits in a section that says what KIND of thing it
is. All of that is taken here.
CC BY-SA 4.0, Wikivoyage."""
import bz2, re, io, json, os, collections

SEC = re.compile(r'^(={2,6})\s*([^=\n]+?)\s*\1\s*$', re.M)
KINDS = ('see','do','eat','drink','buy','sleep','listing','marker','vcard','go','view')

def clean(s):
    s = re.sub(r'\[\[(?:File|Image):[\s\S]*?\]\]', ' ', s or '')
    for _ in range(3): s = re.sub(r'\{\{[^{}]*\}\}', ' ', s)
    s = re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', r'\1', s)
    s = re.sub(r'\[(?:https?://\S+)\s+([^\]]*)\]', r'\1', s)
    s = re.sub(r"'''?", '', s)
    s = re.sub(r'<ref[\s\S]*?</ref>|<[^>]+>', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()

def templates(t):
    """every {{...}} in the text, with its name and its raw body, nesting handled"""
    out, i, n = [], 0, len(t)
    while True:
        i = t.find('{{', i)
        if i < 0: break
        depth, j = 0, i
        while j < n - 1:
            if t[j:j+2] == '{{': depth += 1; j += 2; continue
            if t[j:j+2] == '}}':
                depth -= 1; j += 2
                if depth == 0: break
                continue
            j += 1
        body = t[i+2:j-2]
        name = body.split('|', 1)[0].strip().lower()
        out.append((name, body))
        i = j if j > i else i + 2
    return out

def fields(body):
    """split a template body on | at depth zero, and keep the key=value pairs"""
    d, depth, cur = {}, 0, ''
    for ch in body:
        if ch in '{[': depth += 1
        elif ch in '}]': depth -= 1
        if ch == '|' and depth <= 0:
            if '=' in cur:
                k, v = cur.split('=', 1); d[k.strip().lower()] = v.strip()
            cur = ''
        else: cur += ch
    if '=' in cur:
        k, v = cur.split('=', 1); d[k.strip().lower()] = v.strip()
    return d

def num(x):
    try: return float(x)
    except Exception: return None

WANT = [('name','n'), ('alt','alt'), ('address','addr'), ('directions','dir'),
        ('phone','tel'), ('tollfree','tel2'), ('email','mail'), ('url','url'),
        ('hours','open'), ('checkin','in'), ('checkout','out'), ('price','price'),
        ('lastedit','edit'), ('wikipedia','wp'), ('image','img')]

def sections(t):
    marks = [(m.start(), m.end(), len(m.group(1)), m.group(2).strip()) for m in SEC.finditer(t)]
    out, i = [], 0
    if marks and marks[0][0] > 0: out.append(('', 0, t[:marks[0][0]]))
    for i, (pos, e, lvl, name) in enumerate(marks):
        end = len(t)
        for j in range(i + 1, len(marks)):
            if marks[j][2] <= lvl: end = marks[j][0]; break
        out.append((name, lvl, t[e:end]))
    if not marks: out.append(('', 0, t))
    return out

def top_section(secs, body_start):
    return None

articles = {}
title = None; inpage = False; buf = []; pages = 0
with bz2.open('/home/claude/dl/wikivoyage.xml.bz2', 'rt', encoding='utf-8') as f:
    for line in f:
        if '<title>' in line:
            m = re.search(r'<title>(.*?)</title>', line); title = m.group(1) if m else None
        if '<text' in line: inpage = True; buf = []
        if inpage: buf.append(line)
        if '</text>' in line and inpage:
            inpage = False; pages += 1
            if not title or ':' in title: continue
            t = ''.join(buf)
            if re.search(r'#\s*redirect', t[:400], re.I): continue
            if '{{see' not in t.lower() and '{{listing' not in t.lower() and '{{do' not in t.lower(): continue
            rows = []
            for secname, lvl, body in sections(t):
                sec = re.sub(r'[^a-z ]+', '', secname.lower()).strip()
                for name, tb in templates(body):
                    if name not in KINDS: continue
                    d = fields(tb)
                    nm = clean(d.get('name') or '')
                    if not nm: continue
                    rec = {'k': name, 'sec': sec or None}
                    for src, key in WANT:
                        v = d.get(src)
                        if v:
                            v = clean(v)
                            if v: rec[key] = v[:220]
                    lat, lon = num(d.get('lat')), num(d.get('long') or d.get('lon'))
                    if lat is not None and lon is not None: rec['ll'] = [round(lat,5), round(lon,5)]
                    wd = (d.get('wikidata') or '').strip()
                    m2 = re.match(r'(Q[1-9][0-9]{0,11})', wd)
                    if m2: rec['wd'] = m2.group(1)
                    con = clean(d.get('content') or d.get('description') or '')
                    if con: rec['d'] = con[:500]
                    rec = {k2: v2 for k2, v2 in rec.items() if v2 not in (None, '')}
                    if len(rec) > 2: rows.append(rec)
            if rows: articles[title] = rows
print('pages read:', pages, ' articles with listings:', len(articles), flush=True)
tot = sum(len(v) for v in articles.values())
print('listings:', tot)
c = collections.Counter()
for rows in articles.values():
    for r in rows:
        for k in r: c[k] += 1
print('fields:', dict(sorted(c.items(), key=lambda x: -x[1])))
json.dump(articles, io.open('/home/claude/dl/wv-listings-v2.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('MB', round(os.path.getsize('/home/claude/dl/wv-listings-v2.json')/1048576, 1))
p = articles.get('Paris') or []
print('\nParis, first three:')
for r in p[:3]: print(' ', json.dumps(r, ensure_ascii=False)[:280])

# -*- coding: utf-8 -*-
"""Wikivoyage country articles, second pass.

The first pass cut every section at the NEXT heading of any level, so "Get in" ended the
moment "=== By plane ===" began and came out empty for two thirds of the world; it also
looked for one exact heading name, so Kenya's "Cities and major towns" was not Cities, and
it threw away {{Regionlist}}, which is how a country's regions are actually written.
This pass fixes those three things and keeps the same output shape.
CC BY-SA 4.0, Wikivoyage."""
import bz2, re, io, json, os, collections

S = '/home/claude/work/reference/run/redo/src/'
world = [x['name'] for x in json.load(io.open(S + 'world.json', encoding='utf-8'))]
ALIAS = {'Britain':['United Kingdom'], 'States':['United States of America','United States'],
 'Korea':['South Korea'], 'Czechia':['Czech Republic'], 'Faroes':['Faroe Islands'],
 'Congo (Kinshasa)':['Democratic Republic of the Congo'], 'Congo (Brazzaville)':['Republic of the Congo'],
 'Vatican':['Vatican City'], "Côte d'Ivoire":['Ivory Coast'], 'Holland':['Netherlands'],
 'Myanmar':['Burma'], 'Eswatini':['Swaziland'], 'East Timor':['Timor-Leste'],
 'Cape Verde':['Cabo Verde'], 'Macau':['Macao'],
 'Georgia':['Georgia (country)'], 'Sint Maarten':['Sint Maarten (Netherlands)','Saint Martin (Netherlands)']}
# a title can reach a country three ways, and the better way must win whatever order the
# dump happens to be in: an alias we wrote down beats the bare name, which beats a title we
# only found by following a redirect.
# one article can serve two of our places - Wikivoyage has one "Saint Martin" for the whole
# island and redirects Sint Maarten to it - so a title carries a LIST of claims.
want = {}   # title.lower() -> [(country, priority), ...]
def claim(title, country, prio):
    want.setdefault(title.lower(), []).append((country, prio))
for n in world:
    claim(n, n, 1)
    for a in ALIAS.get(n, []): claim(a, n, 0)

SEC = re.compile(r'^(={2,6})\s*([^=\n]+?)\s*\1\s*$', re.M)

def sections(t):
    """every heading, with its body running to the next heading of the SAME OR HIGHER level -
       so a section keeps its own subsections instead of ending at the first one."""
    marks = [(m.start(), m.end(), len(m.group(1)), m.group(2).strip()) for m in SEC.finditer(t)]
    out = []
    for i, (pos, e, lvl, name) in enumerate(marks):
        end = len(t)
        for j in range(i + 1, len(marks)):
            if marks[j][2] <= lvl: end = marks[j][0]; break
        out.append((name, lvl, t[e:end]))
    return out

def norm(s): return re.sub(r'[^a-z ]+', '', s.lower()).strip()

# what each of our fields is called out there, in the order we prefer them
FIELD_NAMES = {
 'regions':  ['regions', 'regions and cities', 'provinces', 'states', 'counties', 'districts', 'islands and regions'],
 'cities':   ['cities', 'cities and towns', 'cities and major towns', 'major cities', 'main cities',
              'towns', 'towns and cities', 'cities and villages', 'destinations'],
 'other':    ['other destinations', 'other destination', 'national parks', 'parks',
              'natural attractions', 'cultural sites', 'islands', 'other places', 'countryside'],
 'understand':['understand', 'background'],
 'getin':    ['get in', 'getting in', 'arrive'],
 'visas':    ['visas', 'visa', 'entry requirements', 'visa requirements', 'entry'],
 'around':   ['get around', 'getting around'],
 'see':      ['see', 'see and do', 'sights', 'attractions'],
 'do':       ['do', 'activities', 'itineraries'],
 'buy':      ['buy', 'money', 'shopping'],
 'eat':      ['eat', 'eat and drink', 'food', 'cuisine'],
 'drink':    ['drink', 'drinks', 'nightlife'],
 'sleep':    ['sleep', 'accommodation', 'where to stay'],
 'safe':     ['stay safe', 'safety', 'crime'],
 'health':   ['stay healthy', 'health', 'medical'],
 'climate':  ['climate', 'weather', 'when to go'],
 'talk':     ['talk', 'language', 'languages'],
 'respect':  ['respect', 'etiquette', 'customs and etiquette'],
 'connect':  ['connect', 'internet', 'communications', 'stay in touch'],
 'next':     ['go next', 'nearby'],
}
CAP = {'intro':1200,'understand':1500,'getin':2000,'visas':1500,'around':1200,'see':1500,'do':1500,
       'buy':1500,'eat':900,'drink':900,'sleep':900,'safe':1500,'health':900,'climate':1200,
       'talk':900,'respect':900,'connect':700,'next':600}
LIST_FIELDS = ('regions', 'cities', 'other')

def clean(s):
    s = re.sub(r'\[\[(?:File|Image):[\s\S]*?\]\]', ' ', s)
    for _ in range(3): s = re.sub(r'\{\{[^{}]*\}\}', ' ', s)
    s = re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', r'\1', s)
    s = re.sub(r"'''?", '', s)
    s = re.sub(r'<ref[\s\S]*?</ref>|<ref[^>]*/>|<[^>]+>', ' ', s)
    s = re.sub(r'^[*#:;]+\s*', '', s, flags=re.M)
    s = re.sub(r'^\s*===+.*?===+\s*$', ' ', s, flags=re.M)
    s = re.sub(r'^\s*==.*?==\s*$', ' ', s, flags=re.M)
    return re.sub(r'\s+', ' ', s).strip()

def _num(x):
    try: float(x); return True
    except Exception: return False

def fields(body):
    d = {}
    depth = 0; cur = ''
    for ch in body:                      # split on | but not inside a nested template or link
        if ch in '{[': depth += 1
        elif ch in '}]': depth -= 1
        if ch == '|' and depth <= 0: 
            if '=' in cur: k, v = cur.split('=', 1); d[k.strip().lower()] = v.strip()
            cur = ''
        else: cur += ch
    if '=' in cur: k, v = cur.split('=', 1); d[k.strip().lower()] = v.strip()
    return d

def _nm(v):
    m = re.search(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]', v or '')
    if m: return (m.group(2) or m.group(1)).strip(), m.group(1).strip()
    return (clean(v or '') or None), None

MARK  = re.compile(r'^[*#]+\s*(?:\'{2,3})?\s*\{\{\s*marker\s*\|([\s\S]*?)\}\}\s*(?:\(([^)]{1,60})\))?[ \t]*(.*)$', re.M)
PLAIN = re.compile(r'^[*#]+\s*(?:\'{2,3})?\s*\[\[([^\]|]+)(?:\|([^\]]+))?\]\](?:\'{2,3})?\s*(?:\(([^)]{1,60})\))?[ \t]*(.*)$', re.M)
DASH  = re.compile(r'^[\s—–\-−:,;]+')

def dests(sec):
    out, seen = [], set()
    for m in MARK.finditer(sec or ''):
        d = fields(m.group(1)); label, target = _nm(d.get('name'))
        if not label or label in seen: continue
        seen.add(label)
        rec = {'n': label, 'p': target, 'nat': (m.group(2) or None),
               'd': (DASH.sub('', clean(m.group(3) or ''))[:320] or None)}
        if _num(d.get('lat')) and _num(d.get('long')): rec['ll'] = [float(d['lat']), float(d['long'])]
        if d.get('wikidata'): rec['wd'] = d['wikidata']
        out.append(rec)
    for m in PLAIN.finditer(sec or ''):
        label = (m.group(2) or m.group(1)).strip()
        if not label or label in seen: continue
        seen.add(label)
        out.append({'n': label, 'p': m.group(1).strip(), 'nat': (m.group(3) or None),
                    'd': (DASH.sub('', clean(m.group(4) or ''))[:320] or None)})
    return out

RLIST = re.compile(r'\{\{\s*[Rr]egion\s*list\s*\|([\s\S]*?)\n\}\}')
def regionlist(t):
    """{{Regionlist | region1name=... | region1description=... | region1items=... }}"""
    out = []
    for m in RLIST.finditer(t):
        d = fields(m.group(1))
        n = 1
        while True:
            nm = d.get('region%dname' % n)
            if not nm: break
            label, target = _nm(nm)
            if label:
                rec = {'n': label, 'p': target,
                       'd': (clean(d.get('region%ddescription' % n, ''))[:320] or None)}
                items = d.get('region%ditems' % n)
                if items:
                    got = [(mm.group(2) or mm.group(1)).strip()
                           for mm in re.finditer(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]', items)]
                    if got: rec['in'] = got[:14]
                col = d.get('region%dcolor' % n)
                if col: rec['col'] = col
                out.append(rec)
            n += 1
            if n > 40: break
    return out

def pick(secs, names):
    """the first section whose heading is one of these names, preferring the earlier names"""
    byname = {}
    for nm, lvl, body in secs: byname.setdefault(norm(nm), body)
    for want_name in names:
        if want_name in byname: return byname[want_name]
    return ''

REDIR = re.compile(r'#\s*redirect\s*\[\[([^\]|#]+)', re.I)

def scan(handle):
    """yields (title, text) for every article page in the dump"""
    title = None; inpage = False; buf = []
    for line in handle:
        if '<title>' in line:
            m = re.search(r'<title>(.*?)</title>', line); title = m.group(1) if m else None
        if '<text' in line: inpage = True; buf = []
        if inpage: buf.append(line)
        if '</text>' in line and inpage:
            inpage = False
            if title and ':' not in title: yield title, ''.join(buf)

# PASS ONE: where do our names redirect to? "Czechia" and seven others are redirect pages,
# and taking the redirect as the article is what emptied them last time.
extra = {}
with bz2.open('/home/claude/dl/wikivoyage.xml.bz2', 'rt', encoding='utf-8') as f:
    for title, t in scan(f):
        hits = want.get(title.lower())
        if not hits: continue
        m = REDIR.search(t[:400])
        if not m: continue
        target = m.group(1).replace('_', ' ').strip()   # the dump writes "Saint_Martin"
        if target.lower().endswith('(disambiguation)'): continue
        for country, _ in hits: extra.setdefault(target.lower(), set()).add(country)
print('redirects followed:', len(extra), flush=True)
for k, cs in extra.items():
    have = {c for c, _ in want.get(k, [])}
    for c in cs:
        if c not in have: claim(k, c, 2)

out = {}
title = None; inpage = False; buf = []; npages = 0
with bz2.open('/home/claude/dl/wikivoyage.xml.bz2', 'rt', encoding='utf-8') as f:
    for line in f:
        if '<title>' in line:
            m = re.search(r'<title>(.*?)</title>', line); title = m.group(1) if m else None
        if '<text' in line: inpage = True; buf = []
        if inpage: buf.append(line)
        if '</text>' in line and inpage:
            inpage = False; npages += 1
            if not title or ':' in title: continue
            hits = want.get(title.lower())
            if not hits: continue
            todo = [(k, p) for k, p in hits if k not in out or out[k]['_p'] > p]
            if not todo: continue
            t = ''.join(buf)
            # a redirect page ("#REDIRECT [[Czech Republic]]") was being taken as the article
            # and locking the real one out - Czechia, Myanmar and forty others came out empty
            if re.search(r'#\s*redirect', t[:400], re.I): continue
            # a disambiguation page is not an article: plain "Georgia" on Wikivoyage is a
            # list of places called Georgia, and it was standing in for the country
            if re.search(r'\{\{\s*disambig', t, re.I): continue
            secs = sections(t)
            m0 = SEC.search(t)
            rec = {'intro': clean(t[:m0.start()] if m0 else t)[:CAP['intro']] or None}
            for fld, names in FIELD_NAMES.items():
                body = pick(secs, names)
                if fld in LIST_FIELDS:
                    got = dests(body)
                    if fld == 'regions' and not got: got = regionlist(body) or regionlist(t)
                    if fld == 'other' and not got:
                        # some articles spread these over several named sections
                        for nm2 in FIELD_NAMES['other'][1:]:
                            got = dests(pick(secs, [nm2]))
                            if got: break
                    rec[fld] = got
                else:
                    rec[fld] = clean(body)[:CAP.get(fld, 900)] or None
            for k2, p2 in todo:
                out[k2] = dict(rec, _p=p2)
for v in out.values(): v.pop('_p', None)
print('pages read:', npages, ' countries:', len(out))
json.dump(out, io.open('/home/claude/dl/wv-countries-v2.json', 'w', encoding='utf-8'), ensure_ascii=False)
print('MB', round(os.path.getsize('/home/claude/dl/wv-countries-v2.json') / 1048576, 2))
c = collections.Counter()
for k, v in out.items():
    for f2, val in v.items():
        if val: c[f2] += 1
print('filled:', dict(sorted(c.items())))
r = out.get('Russia', {})
print('RU cities :', [x['n'] for x in r.get('cities', [])][:9])
print('RU other  :', [x['n'] for x in r.get('other', [])][:9])
print('RU regions:', [x['n'] for x in r.get('regions', [])][:9])
print('RU getin  :', (r.get('getin') or '')[:160])
nod = [k for k, v in out.items() if not v.get('other') and not v.get('cities')]
print('no cities AND no other:', len(nod), nod[:12])

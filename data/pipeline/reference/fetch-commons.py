#!/usr/bin/env python3
"""
fetch-commons.py — run this on YOUR Mac, not in the cloud.

Wikimedia is rate-limiting the cloud container's address (HTTP 429 on everything), so the two
jobs that need Commons are stuck there. Your machine's address is clean, so this does them
from here instead. It only reads from the network and only writes into reference/data/.
It never deletes anything.

  1. a real passport-cover SVG for every passport the app carries
  2. the coats of arms still missing

Run:   python3 reference/tools/fetch-commons.py
Stop:  Ctrl-C. It picks up where it left off if you run it again.
"""
import json, os, re, sys, time, unicodedata, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))          # the wya?! folder
DATA = os.path.join(ROOT, 'reference', 'data')
SRC  = os.path.join(ROOT, 'reference', 'run', 'redo', 'src')
CACHE = os.path.join(DATA, '_commons-cache')
os.makedirs(DATA, exist_ok=True); os.makedirs(CACHE, exist_ok=True)

UA  = 'wya-travel-app-data/1.0 (passport and coat-of-arms survey; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
COM = 'https://commons.wikimedia.org/w/api.php'
_last = [0.0]

def api(**p):
    dt = time.time() - _last[0]
    if dt < 0.4: time.sleep(0.4 - dt)
    _last[0] = time.time()
    p.setdefault('format', 'json'); p.setdefault('formatversion', 2)
    url = COM + '?' + urllib.parse.urlencode(p)
    for k in range(5):
        try:
            r = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(r, timeout=60) as f:
                return json.loads(f.read().decode('utf-8'))
        except Exception as e:
            if k == 4:
                print('   ! api gave up:', type(e).__name__, getattr(e, 'code', ''))
                return {}
            time.sleep(3 * (k + 1))
    return {}

def grab(url):
    for k in range(4):
        try:
            r = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(r, timeout=90) as f:
                return f.read()
        except Exception:
            if k == 3: return None
            time.sleep(3 * (k + 1))

def fold(s):
    s = unicodedata.normalize('NFD', s or '')
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', s.lower())).strip()

# ---------------------------------------------------------------- 1. passports
PASSWORD = re.compile(r'\b(passport|passports|pasaporte|passeport|passaporto|passaporte|'
                      r'reisepass|paspoort|paszport|pasport|passaport)\b')
BLOCK = re.compile(r'wiki letter|voting box|sound icon|orthographic projection|coat of arms|'
                   r'flag of|commons ?logo|ambox|stub|wv banner|wikivoyage|question book|'
                   r'nuvola|crystal |gnome |oojs|disambig|padlock|folder|speaker|'
                   r'location map|map of|globe|emblem of|seal of|edit icon|wikidata|'
                   r'^symbol |ambox|text document|office building|aiga')
VARIANT = re.compile(r'diplomat|service|official|emergency|temporary|alien|refugee|laissez|'
                     r'seafarer|collective|travel document|certificate|visa|requirement|'
                     r'photo|data page|inside|back cover|stamp\b|page\b|banner|icon|logo|'
                     r'\b1[89]\d\d\b|\bold\b|former|historic')

ALIAS_PATH = os.path.join(HERE, 'country-aliases.json')
ALIAS = json.load(open(ALIAS_PATH, encoding='utf-8')) if os.path.exists(ALIAS_PATH) else {}

def plural_names(country, extra):
    """every name the world files this country under: its own, its official name, its
       demonym ("Afghan Passport.svg" is Afghanistan's), its local name and the big European
       languages. Without the demonym half the covers on Commons do not match at all."""
    ns = {fold(country), re.sub(r'^the ', '', fold(country))}
    for e in extra: ns.add(fold(e))
    for e in ALIAS.get(country, []): ns.add(fold(e))
    return {n for n in ns if len(n) >= 4}

EXTRA = {
 'United States':['american','united states'], 'United Kingdom':['british','united kingdom'],
 'Netherlands':['dutch','netherlands'], 'Switzerland':['swiss'], 'Czechia':['czech'],
 'South Korea':['south korean','korean','republic of korea'], 'North Korea':['north korean'],
 'Ivory Coast':['ivorian','cote d ivoire'], 'Cape Verde':['cape verdean','cabo verde'],
 'East Timor':['timorese','timor leste'], 'Eswatini':['swazi','eswatini','swaziland'],
 'Myanmar':['burmese','myanmar','burma'], 'Vatican':['vatican','holy see'],
 'Palestine':['palestinian'], 'Taiwan':['taiwan','republic of china'],
 'Germany':['german','reisepass'], 'Austria':['austrian','osterreich'], 'Russia':['russian'],
 'Spain':['spanish','espana'], 'France':['french','francais'], 'Italy':['italian','italiano'],
 'Poland':['polish','polski'], 'Greece':['greek','hellenic'], 'Sweden':['swedish','svenskt'],
 'Norway':['norwegian','norsk'], 'Denmark':['danish','dansk'], 'Finland':['finnish','suomen'],
 'Portugal':['portuguese','portugues'], 'Belgium':['belgian','belgisch'],
 'Ireland':['irish'], 'Turkey':['turkish','turkiye'], 'Egypt':['egyptian'],
 'Brazil':['brazilian','brasileiro'], 'Mexico':['mexican','mexicano'], 'Japan':['japanese'],
 'China':['chinese','peoples republic of china'], 'India':['indian'],
 'Indonesia':['indonesian'], 'Nigeria':['nigerian'], 'Kenya':['kenyan'],
 'South Africa':['south african'], 'Argentina':['argentine','argentinian'],
 'Canada':['canadian'], 'Australia':['australian'], 'New Zealand':['new zealand'],
}

# A name is only this country's if no OTHER country has a longer name in the same title.
# "Cayman Islands Passport.svg" matches Iceland through "Island" (Icelandic and German for
# Iceland) and the Cayman Islands through "cayman islands" - the longer one wins, and that is
# the whole rule. A handful of words are never a match on their own.
GENERIC = {'island','islands','republic','state','states','union','territory','saint','new',
           'north','south','east','west','central','united','isle','federation','kingdom',
           'indies','antilles','province','city','free','great','land'}

def _usable(names):
    return [n for n in names if n not in GENERIC and len(n) >= 4]

_ALL = None
def all_countries():
    """every country the app carries, with the names it is filed under"""
    global _ALL
    if _ALL is None:
        colours = json.load(open(os.path.join(SRC, 'passports-colours.json'), encoding='utf-8'))
        _ALL = {c: _usable(plural_names(c, EXTRA.get(c, []))) for c in colours}
    return _ALL

def best_match(title):
    """(country, how long the matched name was) for the country this title belongs to"""
    t = fold(title)
    best, blen = None, 0
    for c, names in all_countries().items():
        for n in names:
            if len(n) > blen and re.search(r'(?<![a-z])' + re.escape(n) + r'(?![a-z])', t):
                best, blen = c, len(n)
    return best, blen

def ok(title, names, country):
    t = fold(title)
    if BLOCK.search(t): return False
    if not PASSWORD.search(t): return False
    who, _ = best_match(title)
    return who == country

def rank(title, size, names):
    t = fold(title); s = 0
    if VARIANT.search(t): s += 80
    safe = [n for n in sorted(names, key=len, reverse=True) if n not in GENERIC]
    if safe and re.fullmatch(r'(' + '|'.join(re.escape(n) for n in safe)
                    + r') (passport|passports)( cover)?( svg)?', t): s -= 50
    if 'cover' in t: s -= 8
    s += len(t) // 6
    s -= min(25, size // 40000)
    return s

def search(q, cap=200):
    out, off = [], 0
    while off < cap:
        d = api(action='query', list='search', srsearch=q, srnamespace=6, srlimit=50, sroffset=off)
        hits = d.get('query', {}).get('search', [])
        out += [h['title'][5:] for h in hits]
        c = d.get('continue', {}).get('sroffset')
        if not c: break
        off = c
    return out

def cat_files(title):
    out, cont = [], None
    while True:
        p = dict(action='query', list='categorymembers', cmtitle=title, cmtype='file', cmlimit=500)
        if cont: p['cmcontinue'] = cont
        d = api(**p)
        out += [m['title'][5:] for m in d.get('query', {}).get('categorymembers', [])]
        cont = d.get('continue', {}).get('cmcontinue')
        if not cont: return out

def info(titles):
    got = {}
    titles = list(titles)
    for k in range(0, len(titles), 50):
        d = api(action='query', prop='imageinfo', iiprop='size|url|mime|extmetadata',
                titles='|'.join('File:' + t for t in titles[k:k+50]))
        for pg in d.get('query', {}).get('pages', []):
            for ii in pg.get('imageinfo', []):
                em = ii.get('extmetadata') or {}
                got[pg['title'][5:]] = {
                    'size': ii.get('size', 0), 'url': ii.get('url', ''),
                    'mime': ii.get('mime', ''),
                    'lic': (em.get('LicenseShortName') or {}).get('value', ''),
                    'by': re.sub(r'<[^>]+>', '', (em.get('Artist') or {}).get('value', ''))[:120],
                }
    return got

def looks_like_a_passport(svg):
    """a cover is portrait and has some drawing in it - not a 160x160 icon"""
    if not svg or len(svg) < 2000: return False
    head = svg[:4000].decode('utf-8', 'ignore') if isinstance(svg, bytes) else svg[:4000]
    w = re.search(r'\bwidth\s*=\s*"([\d.]+)', head)
    h = re.search(r'\bheight\s*=\s*"([\d.]+)', head)
    if w and h:
        try:
            W, H = float(w.group(1)), float(h.group(1))
            if W > 0 and H > 0 and not (1.15 <= H / W <= 1.9): return False
        except ValueError: pass
    return True

def do_passports():
    colours = json.load(open(os.path.join(SRC, 'passports-colours.json'), encoding='utf-8'))
    out_path = os.path.join(DATA, 'passport-vectors.json')
    creds_path = os.path.join(DATA, 'passport-vectors-credits.json')
    have = json.load(open(out_path, encoding='utf-8')) if os.path.exists(out_path) else {}
    creds = json.load(open(creds_path, encoding='utf-8')) if os.path.exists(creds_path) else {}
    todo = [c for c in sorted(colours) if c not in have]
    print('PASSPORTS: %d already here, %d to look for\n' % (len(have), len(todo)))
    for i, country in enumerate(todo, 1):
        try: tick()
        except OutOfTime:
            json.dump(have, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
            json.dump(creds, open(creds_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
            print('\n(out of time for this run - %d done, run again to carry on)' % len(have)); return
        names = plural_names(country, EXTRA.get(country, []))
        seen = set()
        seen.update(search('intitle:passport ' + country, 60))
        dems = [d for d in ALIAS.get(country, [])[:3] if fold(d) != fold(country)]
        for dem in dems[:2]:
            seen.update(search('intitle:passport ' + dem, 40))
        seen.update(cat_files('Category:Passports of ' + country))
        cands = [t for t in seen if t.lower().endswith('.svg') and ok(t, names, country)]
        if not cands:
            print('%3d/%3d %-32s -' % (i, len(todo), country), flush=True); continue
        meta = info(cands)
        best = sorted([t for t in cands if meta.get(t, {}).get('url')],
                      key=lambda t: rank(t, meta[t]['size'], names))
        picked = None
        for t in best[:4]:
            raw = grab(meta[t]['url'])
            if raw and looks_like_a_passport(raw):
                picked = (t, raw); break
        if not picked:
            print('%3d/%3d %-32s - (%d candidates, none looked right)' % (i, len(todo), country, len(best)), flush=True)
            continue
        t, raw = picked
        have[country] = raw.decode('utf-8', 'ignore')
        creds[country] = {'file': t, 'lic': meta[t]['lic'], 'by': meta[t]['by'],
                          'url': 'https://commons.wikimedia.org/wiki/File:' + urllib.parse.quote(t.replace(' ', '_'))}
        print('%3d/%3d %-32s %s  [%s]' % (i, len(todo), country, t[:44], meta[t]['lic'][:20]), flush=True)
        if i % 3 == 0:
            json.dump(have, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
            json.dump(creds, open(creds_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    json.dump(have, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
    json.dump(creds, open(creds_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('\nPASSPORTS DONE: %d of %d have a vector cover' % (len(have), len(colours)))

# ---------------------------------------------------------------- 2. coats of arms
def do_coats():
    need_path = os.path.join(DATA, 'coats-still-needed.json')
    if not os.path.exists(need_path):
        print('\nCOATS: nothing listed as missing, skipping'); return
    need = json.load(open(need_path, encoding='utf-8'))
    if isinstance(need, dict): need = list(need.keys())
    out_path = os.path.join(DATA, 'coats-of-arms-extra.json')
    creds_path = os.path.join(DATA, 'coats-of-arms-extra-credits.json')
    have = json.load(open(out_path, encoding='utf-8')) if os.path.exists(out_path) else {}
    creds = json.load(open(creds_path, encoding='utf-8')) if os.path.exists(creds_path) else {}
    todo = [c for c in need if c not in have]
    print('\nCOATS OF ARMS: %d to look for\n' % len(todo))
    for i, country in enumerate(todo, 1):
        try: tick()
        except OutOfTime:
            json.dump(have, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
            json.dump(creds, open(creds_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
            print('\n(out of time for this run - %d done, run again to carry on)' % len(have)); return
        seen = set()
        seen.update(search('intitle:"coat of arms" ' + country + ' filetype:drawing', 50))
        seen.update(search('intitle:emblem ' + country + ' filetype:drawing', 50))
        seen.update(cat_files('Category:Coats of arms of ' + country))
        names = plural_names(country, EXTRA.get(country, []))
        cands = [t for t in seen if t.lower().endswith('.svg')
                 and re.search(r'coat of arms|emblem|seal', fold(t))
                 and any(n in fold(t) for n in names)
                 and not re.search(r'\b1[5-9]\d\d\b|\b19[0-8]\d\b|historic|former|province|region|city|municipal', fold(t))]
        if not cands:
            print('%3d/%3d %-32s -' % (i, len(todo), country), flush=True); continue
        meta = info(cands)
        best = sorted([t for t in cands if meta.get(t, {}).get('url')],
                      key=lambda t: (len(fold(t)), -meta[t]['size']))
        raw = grab(meta[best[0]]['url'])
        if not raw: 
            print('%3d/%3d %-32s - (download failed)' % (i, len(todo), country), flush=True); continue
        t = best[0]
        have[country] = raw.decode('utf-8', 'ignore')
        creds[country] = {'file': t, 'lic': meta[t]['lic'], 'by': meta[t]['by'],
                          'url': 'https://commons.wikimedia.org/wiki/File:' + urllib.parse.quote(t.replace(' ', '_'))}
        print('%3d/%3d %-32s %s  [%s]' % (i, len(todo), country, t[:44], meta[t]['lic'][:20]), flush=True)
        if i % 3 == 0:
            json.dump(have, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
            json.dump(creds, open(creds_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    json.dump(have, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
    json.dump(creds, open(creds_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('\nCOATS DONE: %d found' % len(have))

DEADLINE = [None]
class OutOfTime(Exception): pass
def tick():
    if DEADLINE[0] and time.time() > DEADLINE[0]: raise OutOfTime()

if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if len(sys.argv) > 2: DEADLINE[0] = time.time() + float(sys.argv[2])
    if what in ('all', 'passports'): do_passports()
    if what in ('all', 'coats'):     do_coats()
    print('\nEverything written into reference/data/. Nothing was deleted.')

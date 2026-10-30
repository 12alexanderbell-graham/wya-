#!/usr/bin/env python3
"""The licence, the author and the attribution line for every photograph the app would show.
A Wikimedia picture without its credit cannot be used, so this is what makes the image layer
usable at all.  Sharded: run as  credits.py <shard> <of>  so several can work at once."""
import json, io, os, re, sys, time, urllib.parse, urllib.request
UA = 'wya-travel-app-data/1.0 (image licences; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
COM = 'https://commons.wikimedia.org/w/api.php'
SH, OF = (int(sys.argv[1]), int(sys.argv[2])) if len(sys.argv) > 2 else (0, 1)
OUT = '/home/claude/facts/credits/part-%d.json' % SH
os.makedirs('/home/claude/facts/credits', exist_ok=True)
_last = [0.0]

def api(**p):
    dt = time.time() - _last[0]
    if dt < 0.2: time.sleep(0.2 - dt)
    _last[0] = time.time()
    p.setdefault('format', 'json'); p.setdefault('formatversion', 2)
    body = urllib.parse.urlencode(p).encode()
    for k in range(6):
        try:
            r = urllib.request.Request(COM, data=body, headers={'User-Agent': UA})
            with urllib.request.urlopen(r, timeout=80) as f:
                return json.loads(f.read().decode('utf-8'))
        except Exception as e:
            if k == 5: return {}
            time.sleep(3 * (k + 1))
    return {}

def strip(h): return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', h or '')).strip()

names, seen = [], set()
for src in ('/home/claude/facts/dest-facts.json', '/home/claude/facts/region-facts.json',
            '/home/claude/facts/country-facts.json'):
    d = json.load(io.open(src, encoding='utf-8'))
    for v in d.values():
        for key in ('img', 'flag', 'coa', 'image', 'coatOfArms', 'flagImage', 'banner', 'locatorMap'):
            g = v.get(key)
            if isinstance(g, str): g = [g]
            for f in (g or []):
                if isinstance(f, str) and f not in seen: seen.add(f); names.append(f)
mine = [n for i, n in enumerate(names) if i % OF == SH]
old = {}
for p in ('/home/claude/facts/image-credits.json', OUT):
    if os.path.exists(p): old.update(json.load(io.open(p, encoding='utf-8')))
out = {k: v for k, v in old.items() if k in set(mine)}
todo = [n for n in mine if n not in out]
print('shard %d/%d: %d pictures, %d already, %d to ask about' % (SH, OF, len(mine), len(out), len(todo)), flush=True)
for k in range(0, len(todo), 50):
    chunk = todo[k:k+50]
    d = api(action='query', prop='imageinfo', iiprop='extmetadata|url',
            iiextmetadatafilter='LicenseShortName|Artist|Credit|AttributionRequired|LicenseUrl|UsageTerms',
            titles='|'.join('File:' + t for t in chunk))
    for pg in d.get('query', {}).get('pages', []):
        t = pg.get('title', '')[5:]
        ii = (pg.get('imageinfo') or [{}])[0]
        em = ii.get('extmetadata') or {}
        def g(key):
            v = (em.get(key) or {}).get('value')
            return strip(v) if v else None
        rec = {}
        for key, col in (('lic','LicenseShortName'), ('by','Artist'), ('src','Credit'),
                         ('terms','UsageTerms'), ('attrib','AttributionRequired')):
            v = g(col)
            if v: rec[key] = v[:170]
        lu = (em.get('LicenseUrl') or {}).get('value')
        if lu: rec['url'] = lu
        if ii.get('url'): rec['file'] = ii['url']
        out[t] = rec
    for t in chunk: out.setdefault(t, {})
    if (k // 50) % 20 == 0 or k + 50 >= len(todo):
        json.dump(out, io.open(OUT, 'w', encoding='utf-8'), ensure_ascii=False)
        wl = sum(1 for v in out.values() if v.get('lic'))
        print('  shard %d: %6d/%6d asked   %6d have a licence' % (SH, min(k+50, len(todo)), len(todo), wl), flush=True)
json.dump(out, io.open(OUT, 'w', encoding='utf-8'), ensure_ascii=False)
print('SHARD %d DONE %d pictures, %d with a licence' % (SH, len(out), sum(1 for v in out.values() if v.get('lic'))), flush=True)

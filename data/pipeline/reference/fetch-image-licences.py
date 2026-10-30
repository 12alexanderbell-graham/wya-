#!/usr/bin/env python3
"""
fetch-image-licences.py — run on YOUR Mac.

The destination photographs come from Wikidata, which gives the Commons filename but not the
licence. A picture without a licence cannot be used, so this asks Commons for the licence, the
author and the attribution line of every one of them, fifty at a time. Resumable.

  python3 reference/tools/fetch-image-licences.py
"""
import json, os, re, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
DATA = os.path.join(ROOT, 'reference', 'data')
UA   = 'wya-travel-app-data/1.0 (image licences; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
COM  = 'https://commons.wikimedia.org/w/api.php'
_last = [0.0]

def api(**p):
    dt = time.time() - _last[0]
    if dt < 0.35: time.sleep(0.35 - dt)
    _last[0] = time.time()
    p.setdefault('format', 'json'); p.setdefault('formatversion', 2)
    url = COM + '?' + urllib.parse.urlencode(p)
    for k in range(5):
        try:
            r = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(r, timeout=70) as f:
                return json.loads(f.read().decode('utf-8'))
        except Exception as e:
            if k == 4: return {}
            time.sleep(3 * (k + 1))
    return {}

def strip(h): return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', h or '')).strip()

dest = json.load(open(os.path.join(DATA, 'destinations.json'), encoding='utf-8'))
names = []
seen = set()
for v in dest.values():
    for f in (v.get('img') or []):
        if f not in seen: seen.add(f); names.append(f)
out_path = os.path.join(DATA, 'image-credits.json')
out = json.load(open(out_path, encoding='utf-8')) if os.path.exists(out_path) else {}
todo = [n for n in names if n not in out]
budget = float(sys.argv[1]) if len(sys.argv) > 1 else 0
deadline = time.time() + budget if budget else None
print('%d pictures, %d already credited, %d to ask about' % (len(names), len(out), len(todo)), flush=True)

for k in range(0, len(todo), 50):
    if deadline and time.time() > deadline:
        print('\n(out of time - %d credited, run again to carry on)' % len(out), flush=True); break
    chunk = todo[k:k+50]
    d = api(action='query', prop='imageinfo', iiprop='extmetadata|url|size|mime',
            titles='|'.join('File:' + t for t in chunk))
    pages = d.get('query', {}).get('pages', [])
    for pg in pages:
        t = pg.get('title', '')[5:]
        ii = (pg.get('imageinfo') or [{}])[0]
        em = ii.get('extmetadata') or {}
        def g(key):
            v = (em.get(key) or {}).get('value')
            return strip(v) if v else None
        rec = {}
        lic = g('LicenseShortName')
        if lic: rec['lic'] = lic
        au = g('Artist')
        if au: rec['by'] = au[:160]
        cr = g('Credit')
        if cr: rec['src'] = cr[:160]
        att = g('AttributionRequired')
        if att: rec['attrib'] = att
        lu = (em.get('LicenseUrl') or {}).get('value')
        if lu: rec['url'] = lu
        if ii.get('url'): rec['file'] = ii['url']
        out[t] = rec
    # a title Commons did not return at all still counts as asked, or we loop on it forever
    for t in chunk: out.setdefault(t, {})
    if (k // 50) % 20 == 0 or k + 50 >= len(todo):
        json.dump(out, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
        withlic = sum(1 for v in out.values() if v.get('lic'))
        print('  %6d/%6d asked   %6d have a licence' % (min(k+50, len(todo)), len(todo), withlic), flush=True)
json.dump(out, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False)
withlic = sum(1 for v in out.values() if v.get('lic'))
print('SAVED %d pictures, %d with a licence' % (len(out), withlic))

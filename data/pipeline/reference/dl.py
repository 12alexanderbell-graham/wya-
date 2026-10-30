#!/usr/bin/env python3
"""geoBoundaries gbOpen, one file per country per level. CC BY 4.0, open sources only.
Natural Earth's admin-1 was whatever each country's file happened to hold - France came out
as departments - so this takes the levels as geoBoundaries defines them, per country."""
import json, os, sys, time, urllib.request, collections
import concurrent.futures as cf

UA = 'wya-travel-app-data/1.0 (region boundaries; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
OUT = '/home/claude/gb/raw'
os.makedirs(OUT, exist_ok=True)
LEVELS = sys.argv[1].split(',') if len(sys.argv) > 1 else ['ADM1']

cat = json.load(open('/home/claude/gb/catalogue.json'))
rows = []
for x in cat:
    if x['boundaryType'] not in LEVELS: continue
    try: n = int(float(x.get('admUnitCount') or 0))
    except Exception: n = 0
    rows.append((x['boundaryISO'], x['boundaryType'], n, x.get('boundaryCanonical') or '',
                 x.get('simplifiedGeometryGeoJSON') or '', x.get('gjDownloadURL') or ''))

def lfs(url):
    """geoBoundaries keeps these in Git LFS: github.com/.../raw/<sha>/<path> hands back a
       126-byte pointer, and media.githubusercontent.com/media/... hands back the file."""
    return url.replace('https://github.com/', 'https://media.githubusercontent.com/media/') \
              .replace('/raw/', '/', 1) if 'github.com/' in url else url

def fetch(row):
    iso, lvl, n, canon, simp, full = row
    simp, full = lfs(simp), lfs(full)
    path = '%s/%s-%s.geojson' % (OUT, iso, lvl)
    if os.path.exists(path) and os.path.getsize(path) > 200:
        return iso, lvl, n, os.path.getsize(path), 'cached'
    for url in (simp, full):
        if not url: continue
        for k in range(3):
            try:
                r = urllib.request.Request(url, headers={'User-Agent': UA})
                with urllib.request.urlopen(r, timeout=180) as f:
                    data = f.read()
                if len(data) < 200: break
                open(path, 'wb').write(data)
                return iso, lvl, n, len(data), 'simplified' if url == simp else 'full'
            except Exception as e:
                if k == 2: break
                time.sleep(2 * (k + 1))
    return iso, lvl, n, 0, 'FAILED'

done, bad, total = 0, [], 0
with cf.ThreadPoolExecutor(max_workers=6) as ex:
    for iso, lvl, n, size, how in ex.map(fetch, rows):
        done += 1; total += size
        if how == 'FAILED': bad.append(iso + '/' + lvl)
        if done % 20 == 0 or how == 'FAILED':
            print('%3d/%3d  %s %s  %5d units  %7.1f KB  %s' % (done, len(rows), iso, lvl, n, size/1024, how), flush=True)
print('DONE', done, 'files, %.1f MB' % (total/1048576), 'failed:', bad)

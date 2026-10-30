#!/usr/bin/env python3
"""The region levels for the data server (Part 17.7): every level file of every place, the newest copy of each (D1b's
cut files, D1's new places, D2's rebuilt countries, then the earlier app's files), gzipped into the server's
`public.nosync/v1/native/regions/` (the dev server serves only `.gz` files, with Content-Encoding: gzip), with the
merged levels table beside them. The app asks for `native/regions/<place>-<row>.wyar`.

usage: serve_regions.py OUT_DIR LEVELS.json -- FOLDER [FOLDER ...]   (newest first)
"""
import gzip, os, shutil, sys
args = sys.argv[1:]
cut = args.index('--')
out, table, folders = args[0], args[1], args[cut + 1:]
os.makedirs(out, exist_ok=True)
names = set()
for f in folders:
    names |= {n for n in os.listdir(f) if n.endswith('.wyar')}
done = 0
for n in sorted(names):
    src = next(os.path.join(f, n) for f in folders if os.path.exists(os.path.join(f, n)))
    with open(src, 'rb') as a, gzip.GzipFile(os.path.join(out, n + '.gz'), 'wb', compresslevel=1, mtime=0) as b:
        shutil.copyfileobj(a, b)
    done += 1
with open(table, 'rb') as a, gzip.GzipFile(os.path.join(out, 'region-levels.json.gz'), 'wb', mtime=0) as b:
    shutil.copyfileobj(a, b)
print({'files': done})

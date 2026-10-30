#!/usr/bin/env python3
"""D10, the first region levels in the app: for every place in the levels table, its coarsest level in use (the
fewest units: a file's level number is its row in the table, which is not top-down where a reform added a row at the
end) is copied into the app's Regions folder, taken from the first of the given folders that has it (the newest data
first: D1b's cut files, D1's new places, D2's rebuilt countries, then the earlier app's files). The merged table goes
beside them as region-levels.json.

usage: d10_pack.py OUT_DIR LEVELS.json [OVERRIDE_LEVELS.json ...] -- FOLDER [FOLDER ...]
"""
import json, os, shutil, sys
args = sys.argv[1:]
cut = args.index('--')
out, tables, folders = args[0], args[1:cut], args[cut + 1:]
os.makedirs(out, exist_ok=True)
levels = {}
for t in tables:
    levels.update(json.load(open(t)))
missing, sizes = [], 0
for cc, rows in sorted(levels.items()):
    used = [(r['n'], i) for i, r in enumerate(rows) if r.get('n', 0) > 0]
    if not used: continue
    n, i = min(used)
    name = f'{cc}-{i + 1}.wyar'
    src = next((os.path.join(f, name) for f in folders if os.path.exists(os.path.join(f, name))), None)
    if not src: missing.append(name); continue
    shutil.copyfile(src, os.path.join(out, name)); sizes += os.path.getsize(src)
    for r in rows: r.pop('first', None)
    rows[i]['first'] = True
json.dump(levels, open(os.path.join(out, 'region-levels.json'), 'w'), ensure_ascii=False, separators=(',', ':'))
print({'places': len(levels), 'files': len([f for f in os.listdir(out) if f.endswith('.wyar')]), 'bytes': sizes,
       'missing': missing})

#!/usr/bin/env python3
"""Put every level's files in one folder and write the little table the page carries."""
import json, os, glob, shutil, sys
SRC = '/home/claude/work/reference/run/redo/src'
DST = SRC + '/regions'
os.makedirs(DST, exist_ok=True)
levels = [l for l in ('ADM1','ADM2','ADM3','ADM4') if os.path.isdir('/home/claude/gb/out-' + l)]
table = {}
n = 0
for lvl in levels:
    idx = json.load(open('/home/claude/gb/index-%s.json' % lvl))
    i = int(lvl[3])
    for f in glob.glob('/home/claude/gb/out-%s/*.js' % lvl):
        shutil.copy(f, DST + '/' + os.path.basename(f)); n += 1
    for cc, row in idx.items():
        arr = table.setdefault(cc, [])
        while len(arr) < i: arr.append(0)
        arr[i - 1] = {'n': row['n'], 'k': row['k']} if row.get('k') else {'n': row['n']}
for cc in table:
    while table[cc] and not table[cc][-1]: table[cc].pop()
json.dump(table, open(SRC + '/mapdata/region-levels.json','w'), ensure_ascii=False, separators=(',',':'))
size = sum(os.path.getsize(os.path.join(DST,f)) for f in os.listdir(DST))
print('levels:', levels)
print('files:', n, ' %.1f MB' % (size/1048576))
print('table:', len(table), 'countries,',
      os.path.getsize(SRC + '/mapdata/region-levels.json')//1024, 'KB')
print('fr:', table.get('fr'), ' de:', table.get('de'), ' jp:', table.get('jp'), ' it:', table.get('it'))

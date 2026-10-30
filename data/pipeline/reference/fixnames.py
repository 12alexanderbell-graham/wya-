#!/usr/bin/env python3
"""Three of geoBoundaries' files are double-encoded - "RegiÃ£o AutÃ³noma" where the source
meant "Região Autónoma" - so the names come through as mojibake. This puts them back."""
import json, re, glob, os, sys
MOJI = re.compile(r'[ÃÂ][\x80-\xbf -ÿ]')
def repair(t):
    if not t or not MOJI.search(t): return t
    for _ in range(3):
        try: u = t.encode('latin-1').decode('utf-8')
        except Exception: break
        if u == t: break
        t = u
        if not MOJI.search(t): break
    return t
changed = files = 0
for f in sorted(glob.glob('/home/claude/gb/out-ADM*/*.js')):
    s = open(f, encoding='utf-8').read()
    i = s.index(',{'); j = s.rindex(');')
    head, pack = s[:i+1], json.loads(s[i+1:j])
    hit = 0
    for u in pack.get('units', []):
        for k in ('n', 'c'):
            if k in u:
                v = repair(u[k])
                if v != u[k]: u[k] = v; hit += 1
    if hit:
        open(f, 'w', encoding='utf-8').write(head + json.dumps(pack, separators=(',',':'), ensure_ascii=False) + ');\n')
        changed += hit; files += 1
print('repaired', changed, 'names in', files, 'files')

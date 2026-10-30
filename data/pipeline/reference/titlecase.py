#!/usr/bin/env python3
"""Some sources shout: ROMANIA's 3,220 communes come through as "BUCURESTI SECTORUL 1".
Ten thousand of them across the set. One capital is enough."""
import json, glob, re
SMALL = {'de','da','do','das','dos','del','della','di','du','des','el','la','le','les','los',
         'y','e','i','and','of','the','van','von','den','der','al','bin','ibn','na','sur','sous'}
def tc(t):
    if len(t) <= 3 or t != t.upper() or not any(c.isalpha() for c in t): return t
    out, first = [], True
    for w in re.split(r'(\s+|-|/|\(|\))', t.lower()):
        if not w.strip() or len(w) == 1 and not w.isalpha(): out.append(w); continue
        if not first and w in SMALL: out.append(w)
        else: out.append(w[:1].upper() + w[1:])
        if w.strip(): first = False
    s = ''.join(out)
    # roman numerals and single letters stay shouted: "Sectorul Ii" -> "Sectorul II"
    s = re.sub(r'\b(I{1,3}|IV|V|VI{0,3}|IX|X{1,3})\b', lambda m: m.group(0).upper(),
               re.sub(r'\b(Ii+|Iv|Vi+|Ix|Xi*)\b', lambda m: m.group(0).upper(), s))
    return s
hit = files = 0
for f in sorted(glob.glob('/home/claude/gb/out-ADM*/*.js')):
    s = open(f, encoding='utf-8').read()
    i = s.index(',{'); j = s.rindex(');')
    head, pack = s[:i+1], json.loads(s[i+1:j])
    n = 0
    for u in pack.get('units', []):
        v = tc(u.get('n', ''))
        if v != u.get('n'): u['n'] = v; n += 1
    if n:
        open(f, 'w', encoding='utf-8').write(head + json.dumps(pack, separators=(',',':'), ensure_ascii=False) + ');\n')
        hit += n; files += 1
print('title-cased', hit, 'names in', files, 'files')

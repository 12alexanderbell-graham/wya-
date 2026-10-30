#!/usr/bin/env python3
"""Put the shards back together and say, honestly, how much of the image layer is usable."""
import json, io, glob, collections, re
out = {}
if __import__('os').path.exists('/home/claude/facts/image-credits.json'):
    out.update(json.load(io.open('/home/claude/facts/image-credits.json', encoding='utf-8')))
for p in sorted(glob.glob('/home/claude/facts/credits/part-*.json')):
    d = json.load(io.open(p, encoding='utf-8')); out.update(d)
    print('  %-22s %6d' % (p.rsplit('/',1)[-1], len(d)))
json.dump(out, io.open('/home/claude/facts/image-credits.json','w',encoding='utf-8'), ensure_ascii=False)

wanted, seen = [], set()
for src in ('dest-facts.json','region-facts.json','country-facts.json'):
    d = json.load(io.open('/home/claude/facts/'+src, encoding='utf-8'))
    for v in d.values():
        for key in ('img','flag','coa','image','coatOfArms','flagImage','banner','locatorMap'):
            g = v.get(key)
            if isinstance(g, str): g = [g]
            for f in (g or []):
                if isinstance(f, str) and f not in seen: seen.add(f); wanted.append(f)
lic  = sum(1 for v in out.values() if v.get('lic'))
by   = sum(1 for v in out.values() if v.get('by'))
none = [k for k in wanted if not out.get(k, {}).get('lic')]
print('\n%d pictures wanted' % len(wanted))
print('%d asked about, %d have a licence, %d also name the author' % (len(out), lic, by))
print('%d have no licence line and cannot be shown' % len(none))
c = collections.Counter(re.sub(r'\s+',' ', v['lic'])[:44] for v in out.values() if v.get('lic'))
print('\nlicences:')
for k, n in c.most_common(16): print('  %6d  %s' % (n, k))
free = sum(n for k,n in c.items() if re.match(r'(cc|public domain|pd|no restrictions|attribution)', k, re.I))
print('\n%d of %d (%.1f%%) are under a Creative Commons or public-domain licence' % (free, lic, 100.0*free/max(1,lic)))
json.dump(none[:4000], io.open('/home/claude/facts/image-nolicence.json','w',encoding='utf-8'), ensure_ascii=False)

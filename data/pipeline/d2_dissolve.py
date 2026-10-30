#!/usr/bin/env python3
"""D2, one set of borders for every level: a coarser level rebuilt from the finest one's arcs, so a canton's border
is exactly its communes' outer border, a department's exactly its arrondissements' (shared borders stay when levels
change). A group's border is every arc used once by its members (an arc between two members is inside
the group); the arcs are chained into rings end to end. The coarser level keeps its own units (ids, names, codes:
its selection is the data's) and takes only their shapes from the finer level.

usage: d2_dissolve.py FINE.wyar COARSE.wyar OUT.wyar [NEXT_COARSER.wyar]
  FINE's units carry `p` (their unit in COARSE); with NEXT_COARSER, OUT's units get `p` in it by the larger share of
  their area (d2_parents' rule), for the next round
"""
import sys, os, collections
sys.path.insert(0, os.path.dirname(__file__))
from wyar import read, write

fine, coarse, out = sys.argv[1:4]
nxt = sys.argv[4] if len(sys.argv) > 4 else None
hf, arcs, _ = read(fine)
hc, _, _ = read(coarse)
ids = [u['id'] for u in hc['u']]
members = collections.defaultdict(list)
for k, u in enumerate(hf['u']): members[u.get('p')].append(k)

def chain(used):
    # used: arc refs (i or ~i) on the group's border, each a directed piece from its first point to its last
    def ends(r):
        a = arcs[r] if r >= 0 else arcs[~r][::-1]
        return a[0], a[-1]
    by_start = collections.defaultdict(list)
    for r in used: by_start[ends(r)[0]].append(r)
    rings, left = [], set(used)
    while left:
        r0 = left.pop(); ring = [r0]; cur = ends(r0)[1]; start = ends(r0)[0]
        while cur != start:
            nxt_ = next((r for r in by_start[cur] if r in left), None)
            if nxt_ is None: break
            left.discard(nxt_); ring.append(nxt_); cur = ends(nxt_)[1]
        rings.append(ring)
    return rings

o, empty, open_rings = [], [], 0
for cid in ids:
    count = collections.Counter(); first = {}
    for k in members.get(cid, []):
        for ring in hf['o'][k]:
            for r in ring:
                i = r if r >= 0 else ~r
                count[i] += 1; first.setdefault(i, r)
    border = [first[i] for i, n in count.items() if n % 2 == 1]
    if not border: empty.append(cid); o.append([]); continue
    rings = chain(border)
    for ring in rings:
        a = ring[0]; b = ring[-1]
        s = (arcs[a] if a >= 0 else arcs[~a][::-1])[0]; e = (arcs[b] if b >= 0 else arcs[~b][::-1])[-1]
        if s != e: open_rings += 1
    o.append(rings)

h = {'t': hf['t'], 'u': [dict(u) for u in hc['u']], 'o': o, 'f': hf.get('f', 1)}
for u in h['u']: u.pop('p', None)
# only the arcs the coarser level uses, renumbered
used = sorted({(r if r >= 0 else ~r) for rs in o for ring in rs for r in ring})
new = {i: k for k, i in enumerate(used)}
h['o'] = [[[new[r] if r >= 0 else ~new[~r] for r in ring] for ring in rs] for rs in o]
out_arcs = [arcs[i] for i in used]
write(out, h, out_arcs)
if nxt:
    import subprocess
    subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'd2_parents.py'), out, nxt], check=True)
print({'units': len(ids), 'with no finer units (left without a shape)': empty, 'rings not closed': open_rings,
       'arcs': len(out_arcs)})

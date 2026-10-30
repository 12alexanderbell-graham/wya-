#!/usr/bin/env python3
"""D2, the nesting: each unit of a finer level gets its parent in the level above (`p`, the parent's id): the parent
holding most of its area (the old nesting fix), as a level's units do not always lie wholly inside one unit above
(a French commune can straddle two cantons, and the coarser level's simplified border cuts small units).

usage: d2_parents.py CHILD.wyar PARENT.wyar   (writes CHILD.wyar again with `p` on every unit)
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from wyar import read, write
from shapely.geometry import Polygon
from shapely.strtree import STRtree
from shapely.ops import unary_union
child, parent = sys.argv[1:3]
def shapes(h, arcs):
    sx, sy, tx, ty = h['t']
    def rp(r):
        pts = []
        for i in r: pts += arcs[i] if i >= 0 else arcs[~i][::-1]
        return [(x * sx + tx, y * sy + ty) for x, y in pts]
    out = []
    for o in h['o']:
        ps = [Polygon(rp(r)).buffer(0) for r in o if len(rp(r)) >= 3]
        out.append(unary_union(ps) if ps else Polygon())
    return out
hc, ac, _ = read(child); hp, ap, _ = read(parent)
gc = shapes(hc, ac); gp = shapes(hp, ap)
tree = STRtree(gp)
whole = part = none = 0
for u, g in zip(hc['u'], gc):
    best, bi = 0.0, None
    for j in tree.query(g):
        a = gp[j].intersection(g).area
        if a > best: best, bi = a, j
    if bi is None:
        # off every parent (a coastal unit past the coarser coast): the nearest
        bi = min(range(len(gp)), key=lambda j: gp[j].distance(g)); none += 1
    elif best >= 0.9 * g.area: whole += 1
    else: part += 1
    u['p'] = hp['u'][bi]['id']
write(child, hc, ac)
print({'units': len(gc), 'mostly in one parent (90%+)': whole, 'split, given to the larger share': part, 'off every parent, given to the nearest': none})

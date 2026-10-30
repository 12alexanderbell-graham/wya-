#!/usr/bin/env python3
"""D1b, region units on the map's piece lines: every country's region files cut along the same lines the map draws for
its disputed and de facto pieces (truth.py's fine shapes where they exist, the data's own shapes otherwise), so a
region map follows whichever borders view is chosen.

A unit that a piece line crosses becomes parts with the same `id`; a part inside a piece carries `q` (the piece key,
`p:<id>` as in disputes.json). A unit wholly inside a piece keeps its shape and gets `q`. On a region map the app draws,
for a piece held by H in the chosen view, the parts tagged with it from H's own file when H's file has any, else from
the file of the place the piece is drawn with; untagged units are always their country's.

Rules:
- the files checked for a piece are those of its possible holders (options, host, controller in disputes.json);
- smaller pieces are taken first, so a piece inside another (the Golan, the UNDOF zone) keeps its own parts;
- when one side of a cut is under 3% of the unit and under about 200 km2 (a slip between the region data's outline
  and the piece's), the unit is not cut: it goes whole to the larger side;
- crumbs under about 1 km2 left by a cut, and leftovers outside every piece under 3% of the unit (gaps between two
  pieces' sources), join the largest part of the unit;
- a piece that is a whole place (Kosovo, Taiwan) takes its own place's file whole, uncut;
- a piece reaches 8 km out to sea (never onto other land), so the data's coarse coast never cuts a coastal unit.

usage: d1b_pieces.py <old Regions folder> <original detail-100m.wyad> <disputes.json> <truth.pkl> <nepieces.pkl> <out>
"""
import sys, os, json, pickle, collections
sys.path.insert(0, os.path.dirname(__file__))
from wyar import read, write
from shapely.geometry import Polygon, MultiPolygon, box
from shapely.ops import unary_union
from shapely import make_valid
from shapely.affinity import affine_transform
import shapely

regdir, detail, dfile, tfile, nfile, out = sys.argv[1:7]
os.makedirs(out, exist_ok=True)
D = json.load(open(dfile))
truth = pickle.load(open(tfile, 'rb'))['groups']
NE = pickle.load(open(nfile, 'rb'))

fine = {}
for g, (parents, kids) in truth.items():
    for k, s in kids: fine[k] = make_valid(s)

# the whole shapes of the entity places the data does not keep as pieces (Israel, North Korea, ...): from the tiles
need = {'o:' + x['entity'] for x in D['list'] if x['entity']} - set(fine) - set(NE)
extra = {}
if need:
    import wyad, rebuild as R
    d, h, b = wyad.pack(detail)
    acc = collections.defaultdict(list)
    for t in h['tiles']:
        th, items, xl = wyad.tile(d, b, t)
        for k, rs in items:
            if k in need:
                g = R.geo_of(rs)
                if not g.is_empty: acc[k].append(g)
    extra = {k: unary_union(v) for k, v in acc.items()}

def shape_of(key):
    for src in (fine, NE, extra):
        if key in src: return make_valid(src[key])
    return None

pieces, entity_of = {}, {}
for x in D['list']:
    key = 'p:' + x['id']
    s = shape_of(key)
    if s is None and x['entity']:
        s = shape_of('o:' + x['entity'])
    if key == 'p:w-sahara' and s is not None and 'p:w-sahara-morocco' in fine:
        s = s.difference(fine['p:w-sahara-morocco'])
    if s is None or s.is_empty:
        print('no shape for', key); continue
    holders = set(x['options']) | {x['host'], x['controller']}
    pieces[key] = (s, {h for h in holders if h})
    if x['entity']: entity_of[key] = x['entity']

# a piece's coast: the data's coastline is coarser than the region data's, so a piece reaches SEA km out to sea (never
# onto another place's land); otherwise every coastal unit would be cut along the coarse coast
SEA = 0.08
import wyad, rebuild as R
d_, hd_, b_ = wyad.pack(detail)
reach = {k: s.buffer(SEA).bounds for k, (s, _) in pieces.items()}
own = {}
for x in D['list']:
    own['p:' + x['id']] = {'p:' + x['id']} | ({'o:' + x['entity']} if x['entity'] else set())
land = collections.defaultdict(list)
for t in hd_['tiles']:
    th, items, xl = wyad.tile(d_, b_, t)
    for k, rs in items:
        pts = [q for r in rs for q in r]
        if not pts: continue
        x0 = min(q[0] for q in pts); x1 = max(q[0] for q in pts); y0 = min(q[1] for q in pts); y1 = max(q[1] for q in pts)
        hit = [pk for pk, bb in reach.items() if k not in own[pk] and x0 <= bb[2] and bb[0] <= x1 and y0 <= bb[3] and bb[1] <= y1]
        if hit:
            g = R.geo_of(rs)
            for pk in hit: land[pk].append(g)
for k, (s, holders) in list(pieces.items()):
    others = unary_union(land[k]) if land[k] else Polygon()
    pieces[k] = (make_valid(s.union(s.buffer(SEA).difference(others))), holders)

files = collections.defaultdict(list)
for f in sorted(os.listdir(regdir)):
    if f.endswith('.wyar'): files[f.rsplit('-', 1)[0]].append(f)

def ring_pts(arcs, ring):
    pts = []
    for r in ring:
        a = arcs[r] if r >= 0 else arcs[~r][::-1]
        pts.extend(a if not pts else a[1:])
    return pts

def unit_geom(pts_rings):
    # even-odd over the rings: holes and islands alike, whatever their direction
    ps = [make_valid(Polygon(pts)) for pts in pts_rings if len(pts) >= 4]
    if not ps: return Polygon()
    if len(ps) == 1: return ps[0]
    # depth of each ring by how many others hold one of its points (even: land, odd: a hole); one level of islands in
    # lakes is the deepest the region data has
    tree = shapely.STRtree(ps)
    land, holes = [], []
    for i, p in enumerate(ps):
        pt = p.representative_point()
        d = sum(1 for j in tree.query(pt, predicate='within') if j != i)
        (holes if d % 2 else land).append(p)
    g = shapely.union_all(land)
    return make_valid(g.difference(shapely.union_all(holes))) if holes else g

def polys(g):
    if g.is_empty: return []
    if isinstance(g, Polygon): return [g]
    return [q for p in getattr(g, 'geoms', []) for q in polys(p)]

def rings_of(g):
    out_ = []
    for p in polys(g):
        for r in [p.exterior] + list(p.interiors):
            pts = [(int(round(x)), int(round(y))) for x, y in r.coords]
            dd = [pts[0]]
            for q in pts[1:]:
                if q != dd[-1]: dd.append(q)
            if len(dd) >= 4 and dd[0] == dd[-1]: out_.append(dd)
    return out_

def build_arcs(units_rings):
    """topology from point rings: rings cut at every point where their neighbours differ, equal arcs shared"""
    nb = collections.defaultdict(set)
    for rings in units_rings:
        for r in rings:
            n = len(r) - 1
            for i in range(n):
                p = r[i]; a = r[i - 1] if i else r[n - 1]; c = r[i + 1]
                nb[p].add(frozenset((a, c)))
    junction = {p for p, s in nb.items() if len(s) > 1}
    arcs, index, out_rings = [], {}, []
    for rings in units_rings:
        ur = []
        for r in rings:
            pts = r[:-1]
            n = len(pts)
            js = [i for i, p in enumerate(pts) if p in junction]
            if not js: js = [min(range(n), key=lambda i: pts[i])]
            s = js[0]; pts = pts[s:] + pts[:s] + [pts[s]]
            cuts = [i for i, p in enumerate(pts) if p in junction] or [0]
            if cuts[-1] != len(pts) - 1: cuts.append(len(pts) - 1)
            if cuts[0] != 0: cuts.insert(0, 0)
            refs = []
            for a_, b_ in zip(cuts, cuts[1:]):
                seg = tuple(pts[a_:b_ + 1])
                if seg in index: refs.append(index[seg])
                elif seg[::-1] in index: refs.append(~index[seg[::-1]])
                else:
                    index[seg] = len(arcs); arcs.append(list(seg)); refs.append(index[seg])
            ur.append(refs)
        out_rings.append(ur)
    return arcs, out_rings

report = {}
order = sorted(pieces, key=lambda k: pieces[k][0].area)
for cc in sorted(files):
    # the piece that is the whole place last, so it takes only what the other pieces leave (Western Sahara less the
    # part Morocco holds)
    mine = sorted([k for k in order if cc in pieces[k][1]], key=lambda k: entity_of.get(k) == cc)
    if not mine: continue
    for f in files[cc]:
        h, arcs, _ = read(os.path.join(regdir, f))
        sx, sy, tx, ty = h['t']
        # degrees to the file's integer grid
        mat = [1 / sx, 0, 0, 1 / sy, -tx / sx, -ty / sy]
        allx = [x for a in arcs for x, _ in a]; ally = [y for a in arcs for _, y in a]
        if not allx: continue
        fb = box(min(allx), min(ally), max(allx), max(ally))
        loc = [(k, affine_transform(pieces[k][0], mat)) for k in mine]
        loc = [(k, s) for k, s in loc if s.intersects(fb)]
        if not loc: continue
        crumb = 1e-4 / (sx * sy)
        slip = 0.02 / (sx * sy)
        new_u, new_rings, changed, cut = [], [], 0, []
        lb = [s.bounds for _, s in loc]
        for ui, u in enumerate(h['u']):
            rings = h['o'][ui]
            pr = [ring_pts(arcs, r) for r in rings]
            xs = [x for r in pr for x, _ in r]; ys = [y for r in pr for _, y in r]
            near = xs and any(b[0] <= max(xs) and min(xs) <= b[2] and b[1] <= max(ys) and min(ys) <= b[3] for b in lb)
            g = unit_geom(pr) if near else Polygon()
            hits = [(k, s) for k, s in loc if s.intersects(g)] if not g.is_empty else []
            if not hits:
                new_u.append(u); new_rings.append(pr); continue
            area = g.area
            rest = g; parts = []
            for k, s in hits:
                if entity_of.get(k) == cc:
                    # the place's own file and the piece that is the whole place: what is left is the piece's, uncut
                    parts.append((k, rest)); rest = Polygon(); break
                inside = make_valid(rest.intersection(s))
                if inside.area <= 0: continue
                parts.append((k, inside)); rest = make_valid(rest.difference(s))
            parts.append((None, rest))
            parts = [(k, p) for k, p in parts if p.area > 0]
            big = max(parts, key=lambda kp: kp[1].area)
            if big[1].area >= 0.97 * area and area - big[1].area < slip:
                # a slip, not a cut: the unit whole, to the larger side
                uu = dict(u)
                if big[0]: uu['q'] = big[0]; changed += 1
                new_u.append(uu); new_rings.append(pr); continue
            # a leftover outside every piece under 3% of the unit is a gap between two pieces' sources, not land of
            # the country's own: it joins the largest part too
            small = lambda k, p: p is not big[1] and (p.area < crumb or (k is None and p.area < 0.03 * area))
            kept = [(k, p) for k, p in parts if not small(k, p)]
            crumbs = [p for k, p in parts if small(k, p)]
            if crumbs:
                kept = [(k, make_valid(unary_union([p] + crumbs)) if p is big[1] else p) for k, p in kept]
            for k, p in kept:
                uu = dict(u)
                if k: uu['q'] = k
                rs = rings_of(p)
                if rs: new_u.append(uu); new_rings.append(rs)
            changed += 1; cut.append([u.get('id'), [k or cc for k, _ in kept]])
        if not changed: continue
        out_arcs, out_r = build_arcs(new_rings)
        h2 = dict(h); h2['u'] = new_u; h2['o'] = out_r
        write(os.path.join(out, f), h2, out_arcs)
        # check: an arc used once is an outer border; count those not on the old outer border's points
        uses = collections.Counter(i if i >= 0 else ~i for rs in out_r for ring in rs for i in ring)
        report[f] = {'units': len(h['u']), 'now': len(new_u), 'tagged': sum(1 for u in new_u if 'q' in u),
                     'cut': cut, 'arcs': [len(arcs), len(out_arcs)],
                     'pieces': sorted({u['q'] for u in new_u if 'q' in u})}
        print(f, report[f]['units'], '->', report[f]['now'], 'tagged', report[f]['tagged'], report[f]['pieces'])
json.dump(report, open(os.path.join(out, 'd1b-report.json'), 'w'), indent=1, ensure_ascii=False)

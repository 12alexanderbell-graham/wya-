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
- when one side of a cut is under 3% of the unit and under about 20 km2 (a slip between the region data's outline
  and the piece's), the unit is not cut: it goes whole to the larger side;
- crumbs under about 1 km2 left by a cut, and leftovers outside every piece under 3% of the unit (gaps between two
  pieces' sources), join the largest part of the unit;
- a piece that is a whole place (Kosovo, Taiwan) takes its own place's file whole, uncut;
- a sliver inside a piece (under 3% of its unit) joins the part of the same piece it shares the longest border with,
  so region borders follow the piece's line (the unit loses that sliver to its neighbour);
- every cut is made on the file's own integer grid, then all the file's outlines are noded together and each part's
  rings are rebuilt from the faces between those lines, so neighbours share every point.

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

# the part Morocco holds is drawn in truth.py as a box less the Polisario's land: only its part in Western Sahara
# (within 7 km of the data's own outline) is the piece, never Morocco proper north of 27.67°N
if 'p:w-sahara-morocco' in pieces and 'o:eh' in NE:
    s_, h_ = pieces['p:w-sahara-morocco']
    pieces['p:w-sahara-morocco'] = (make_valid(s_.intersection(NE['o:eh'].buffer(0.07))), h_)

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
        # held by another ring as a whole (a point of it could lie in a hole of its own outer ring)
        d = sum(1 for j in tree.query(p, predicate='within') if j != i)
        (holes if d % 2 else land).append(p)
    g = shapely.union_all(land)
    return make_valid(g.difference(shapely.union_all(holes))) if holes else g

def polys(g):
    if g.is_empty: return []
    if isinstance(g, Polygon): return [g]
    return [q for p in getattr(g, 'geoms', []) for q in polys(p)]

def area_only(g):
    """the polygons of a result, without the lines or points an overlay or make_valid can leave"""
    ps = polys(g)
    return ps[0] if len(ps) == 1 else MultiPolygon(ps) if ps else Polygon()

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

def faces_to_rings(pg, pu, crumb):
    lines = shapely.union_all([g.boundary for g in pg if not g.is_empty], grid_size=1)
    faces = [f for f in shapely.get_parts(shapely.polygonize(shapely.get_parts(lines))) if f.area > 0]
    tree = shapely.STRtree(pg)
    owner = []
    for f in faces:
        rp = f.representative_point()
        # a face inside two parts stays in both (the region data has a few overlapping units; they keep their shapes)
        c = [int(k) for k in tree.query(rp, predicate='intersects')]
        if not c and f.area < crumb:
            # a crumb between two parts (no one's): to the neighbour it borders longest
            nb = [int(k) for k in tree.query(f.buffer(1), predicate='intersects')]
            if nb: c = [max(nb, key=lambda k: f.boundary.intersection(pg[k].buffer(1)).length)]
        owner.append(c)
    segs = collections.defaultdict(collections.Counter)
    for f, os_ in zip(faces, owner):
        for r in [f.exterior] + list(f.interiors):
            cs = [(int(round(x)), int(round(y))) for x, y in r.coords]
            for a, b in zip(cs, cs[1:]):
                if a != b:
                    for o in os_: segs[o][(a, b) if a < b else (b, a)] += 1
    out_u, out_r = [], []
    for k, u in enumerate(pu):
        edges = [e for e, n in segs[k].items() if n % 2 == 1]
        if not edges: continue
        adj = collections.defaultdict(list)
        for a, b in edges: adj[a].append(b); adj[b].append(a)
        used = set(); rings = []
        for a, b in edges:
            if (a, b) in used: continue
            ring = [a, b]; used.add((a, b) if a < b else (b, a)); prev, cur = a, b
            while cur != a:
                nxt = next((n for n in adj[cur] if ((cur, n) if cur < n else (n, cur)) not in used), None)
                if nxt is None: break
                used.add((cur, nxt) if cur < nxt else (nxt, cur)); ring.append(nxt); prev, cur = cur, nxt
            if ring[0] == ring[-1] and len(ring) >= 4: rings.append(ring)
        if rings: out_u.append(u); out_r.append(rings)
    return out_u, out_r

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
        # on the file's own integer grid, and every cut made on it, so both sides of a seam get the same points
        loc = [(k, area_only(make_valid(shapely.set_precision(affine_transform(pieces[k][0], mat), 1.0)))) for k in mine]
        loc = [(k, s) for k, s in loc if s.intersects(fb)]
        if not loc: continue
        crumb = 1e-4 / (sx * sy)
        slip = 0.002 / (sx * sy)
        new_u, new_rings, changed, cut, geoms, merged = [], [], 0, [], [], 0
        own_file = cc in set(entity_of.values())
        lb = [s.bounds for _, s in loc]
        for ui, u in enumerate(h['u']):
            rings = h['o'][ui]
            pr = [ring_pts(arcs, r) for r in rings]
            xs = [x for r in pr for x, _ in r]; ys = [y for r in pr for _, y in r]
            near = xs and any(b[0] <= max(xs) and min(xs) <= b[2] and b[1] <= max(ys) and min(ys) <= b[3] for b in lb)
            g = area_only(unit_geom(pr)) if near else Polygon()
            hits = [(k, s) for k, s in loc if s.intersects(g)] if not g.is_empty else []
            if not hits:
                new_u.append(u); new_rings.append(pr); geoms.append(None); continue
            area = g.area
            rest = g; parts = []; whole_rest = None; rest_in = 1
            for k, s in hits:
                if entity_of.get(k) == cc:
                    # the place's own file and the piece that is the whole place: what is left is the piece's, uncut
                    whole_rest = rest
                    rest_in = shapely.intersection(rest, s, grid_size=1).area / rest.area if rest.area else 1
                    parts.append((k, rest)); rest = Polygon(); break
                inside = area_only(make_valid(shapely.intersection(rest, s, grid_size=1)))
                if inside.area <= 0: continue
                parts.append((k, inside)); rest = area_only(make_valid(shapely.difference(rest, s, grid_size=1)))
            parts.append((None, rest))
            parts = [(k, p) for k, p in parts if p.area > 0]
            big = max(parts, key=lambda kp: kp[1].area)
            if big[1].area >= 0.97 * area and area - big[1].area < slip:
                # a slip, not a cut: the unit whole, to the larger side
                uu = dict(u)
                if big[0]: uu['q'] = big[0]; changed += 1
                new_u.append(uu); new_rings.append(pr); geoms.append((g, area, True, None) if big[0] else None); continue
            # a leftover outside every piece under 3% of the unit is a gap between two pieces' sources, not land of
            # the country's own: it joins the largest part too
            # the rest that goes to the whole place is a leftover too when it lies mostly outside the place's shape
            # (the Golan district beyond the piece's line); in a disputed place's own file every leftover is a slip
            small = lambda k, p: p is not big[1] and (p.area < crumb
                                                      or (k is None and p.area < (0.10 if own_file else 0.03) * area)
                                                      or (p is whole_rest and (p.area < 0.03 * area or rest_in < 0.5)))
            kept = [(k, p) for k, p in parts if not small(k, p)]
            crumbs = [p for k, p in parts if small(k, p)]
            if crumbs:
                kept = [(k, area_only(make_valid(shapely.union_all([p] + crumbs, grid_size=1))) if p is big[1] else p) for k, p in kept]
            for k, p in kept:
                uu = dict(u)
                if k: uu['q'] = k
                if p.area > 0: new_u.append(uu); new_rings.append(None); geoms.append((p, area, p is big[1], pr))
            changed += 1; cut.append([u.get('id'), [k or cc for k, _ in kept]])
        if not changed: continue
        # a sliver inside a piece (under 3% of its unit, where the region data's line and the piece's differ) joins the
        # part of the same piece it shares the longest border with, so the region borders follow the piece's line
        alive = [True] * len(new_u)
        for i, gi in enumerate(geoms):
            if not gi or gi[2] or 'q' not in new_u[i] or gi[0].area >= 0.03 * gi[1]: continue
            near_ = gi[0].buffer(2)
            best_, bl = None, 0
            for j, gj in enumerate(geoms):
                if j == i or not gj or not alive[j] or new_u[j].get('q') != new_u[i]['q'] or new_u[j]['id'] == new_u[i]['id']: continue
                if not gj[0].intersects(near_): continue
                l = gi[0].boundary.intersection(gj[0].buffer(2)).length
                if l > bl: best_, bl = j, l
            if best_ is not None:
                gj = geoms[best_]
                geoms[best_] = (area_only(make_valid(shapely.union_all([gj[0], gi[0]], grid_size=1))), gj[1], gj[2],
                                (gj[3] or []) + (gi[3] or []))
                alive[i] = False; merged += 1
        keep_i = [i for i in range(len(new_u)) if alive[i]]
        # ONE SET OF LINES FOR THE WHOLE FILE: the cuts' snap rounding can drop a vertex an uncut neighbour still has,
        # and a unit left whole by the slip rule keeps its own line while its neighbour is cut on the piece's; so every
        # part's outline is noded together, the faces between the lines are given to the part holding them, and each
        # part's rings are its faces' outer edges: neighbours then share exactly the same points
        pg = [geoms[i][0] if geoms[i] and new_rings[i] is None else area_only(unit_geom(new_rings[i])) for i in keep_i]
        pu = [new_u[i] for i in keep_i]
        new_u, new_rings = faces_to_rings(pg, pu, crumb)
        out_arcs, out_r = build_arcs(new_rings)
        h2 = dict(h); h2['u'] = new_u; h2['o'] = out_r
        write(os.path.join(out, f), h2, out_arcs)
        # check: an arc used once is an outer border; count those not on the old outer border's points
        uses = collections.Counter(i if i >= 0 else ~i for rs in out_r for ring in rs for i in ring)
        report[f] = {'units': len(h['u']), 'now': len(new_u), 'tagged': sum(1 for u in new_u if 'q' in u), 'slivers joined': merged,
                     'cut': cut, 'arcs': [len(arcs), len(out_arcs)],
                     'pieces': sorted({u['q'] for u in new_u if 'q' in u})}
        print(f, report[f]['units'], '->', report[f]['now'], 'tagged', report[f]['tagged'], report[f]['pieces'])
json.dump(report, open(os.path.join(out, 'd1b-report.json'), 'w'), indent=1, ensure_ascii=False)

# Rebuilds the detailed tiles of the de facto / disputed places from their fine geometry (truth.pkl), so their borders
# are at the same detail as every other border. Only the items of the affected groups change; every other item, its
# rings and its lines stay byte for byte as they were. python3 rebuild.py <in.wyad> <out.wyad> <sliver radius in
# degrees>
import sys, json, struct, zlib, pickle, math
from shapely.geometry import Polygon, MultiPolygon, LineString, Point, box
from shapely.ops import unary_union, linemerge
from shapely import make_valid, set_precision, STRtree
import wyad

Q = 1e-5  # the tiles' own grid

def geo_of(rings):
    """an item's rings (even-odd) as one valid area"""
    g = None
    for r in rings:
        if len(r) < 3: continue
        p = make_valid(Polygon(r))
        p = unary_union([q for q in getattr(p, 'geoms', [p]) if q.geom_type in ('Polygon', 'MultiPolygon')]) if p.geom_type == 'GeometryCollection' else p
        g = p if g is None else g.symmetric_difference(p)
    return g if g is not None else Polygon()

def polys(g):
    if g.is_empty: return []
    if g.geom_type == 'Polygon': return [g]
    if g.geom_type == 'MultiPolygon': return list(g.geoms)
    if g.geom_type == 'GeometryCollection':
        out = []
        for q in g.geoms: out += polys(q)
        return out
    return []

def clean(g):
    g = set_precision(make_valid(g), Q)
    return unary_union(polys(g)) if polys(g) else Polygon()

def opening(g, r):
    return g.buffer(-r, join_style='mitre').buffer(r, join_style='mitre')

def contact(a, b, eps):
    """length of a's outline that runs along b"""
    return a.boundary.intersection(b.buffer(eps)).length

def partition(old, parents, children, r):
    """old: key -> area of the group's items in this tile. Returns key -> new area."""
    L = clean(unary_union(list(old.values())))
    if L.is_empty: return {}
    new = {}
    taken = Polygon()
    for k, fine in children:
        c = clean(fine.intersection(L).difference(taken))
        new[k] = c
        taken = clean(unary_union([taken, c]))
    rest = clean(L.difference(taken))
    ps = [p for p in parents if p in old] or parents[:1]
    # what is left goes to the parent it was before; a bit that was no parent's (the old shape of a child that the
    # fine shape does not reach) goes to a parent only if it lies along that parent, else back to the child it lies
    # along: so where a child's fine edge falls short of a border with a place outside the group (Arunachal's fine
    # shape against China), the strip stays the child's and never becomes a ribbon of the parent
    part = {p: (clean(rest.intersection(old[p])) if p in old else Polygon()) for p in ps}
    left = clean(rest.difference(unary_union(list(part.values()))))
    for comp in polys(left):
        per = comp.length
        if per == 0: continue
        bp = max(ps, key=lambda p: contact(comp, part[p], Q * 3) if not part[p].is_empty else -1)
        pl = contact(comp, part[bp], Q * 3) if not part[bp].is_empty else 0
        def score(k):
            if new[k].is_empty: return -1
            c = contact(comp, new[k], Q * 3)
            return c * (1.5 if k in old and comp.intersection(old[k]).area > 0.5 * comp.area else 1)
        bk = max((k for k, _ in children), key=score)
        kl = score(bk)
        if pl > 0.25 * per or kl <= 0:
            part[bp] = clean(unary_union([part[bp], comp]))
        else:
            new[bk] = clean(unary_union([new[bk], comp]))
    new.update(part)
    # slivers: thin bits of a parent left between a child and the outline of the group (the fine line and the
    # tile's own simplified border never quite meet) go to the child they lie along
    if r > 0:
        for p in ps:
            P = new[p]
            if P.is_empty: continue
            thin = clean(P.difference(opening(P, r)))
            for comp in polys(thin):
                per = comp.length
                if per == 0: continue
                best, bl = None, 0
                for k, _ in children:
                    if new[k].is_empty: continue
                    l = contact(comp, new[k], Q * 3)
                    if l > bl: best, bl = k, l
                if best and bl > 0.3 * per:
                    new[best] = clean(unary_union([new[best], comp]))
                    P = clean(P.difference(comp))
            new[p] = P
    return new

def rings_of(g):
    out = []
    for p in polys(g):
        ext = list(p.exterior.coords)[:-1]
        if len(ext) >= 3: out.append(ext)
        for h in p.interiors:
            hr = list(h.coords)[:-1]
            if len(hr) >= 3: out.append(hr)
    return out

def lines_of(g):
    """a geometry's line parts as point lists, merged where they join"""
    ls = []
    def walk(q):
        if q.is_empty: return
        if q.geom_type == 'LineString': ls.append(q)
        elif q.geom_type == 'LinearRing': ls.append(LineString(q.coords))
        elif hasattr(q, 'geoms'):
            for z in q.geoms: walk(z)
    walk(g)
    if not ls: return []
    m = linemerge(ls)
    out = []
    def put(q):
        if q.geom_type == 'LineString': out.append(list(q.coords))
        elif hasattr(q, 'geoms'):
            for z in q.geoms: put(z)
    put(m)
    return [l for l in out if len(l) >= 2]

class Writer:
    def __init__(self, x, y):
        self.qx = round(x * 1e5); self.qy = round(y * 1e5); self.out = bytearray()
    def pt(self, lon, lat):
        nx = round(lon * 1e5); ny = round(lat * 1e5)
        for v in (nx - self.qx, ny - self.qy):
            z = (v << 1) ^ (v >> 63)
            while True:
                b = z & 0x7f; z >>= 7
                if z: self.out.append(b | 0x80)
                else: self.out.append(b); break
        self.qx, self.qy = nx, ny

def rebuild_tile(t, th, items, xl, groups, r):
    x, y = t[0], t[1]
    keys = [k for k, _ in items]
    # resolve the ring-indexed lines to points
    lines = []  # (a, b, pts, e-entry or None)
    for e in th.get('e', []):
        a, b, ri, st, n = e
        rg = items[a][1][ri]
        lines.append((a, b, [rg[(st + i) % len(rg)] for i in range(n)], e))
    for a, b, l in xl:
        lines.append((a, b, l, None))
    tb = box(x, y, x + TS, y + TS)
    touched = set()
    newgeo = {}
    gofk = {}
    for gname, (parents, children) in groups.items():
        gkeys = set(parents) | {k for k, _ in children}
        present = {k for k in keys if k in gkeys}
        if not present: continue
        # only where one of the group's pieces is, or one of their fine shapes reaches (a tile of India alone, far from
        # Kashmir, is left exactly as it was)
        if not (present & {k for k, _ in children}) and not any(PREP[k].intersects(tb) for k, _ in children): continue
        clash = present & set(newgeo)
        assert not clash, ('a place in two groups in one tile', clash, x, y)
        old = {k: geo_of(items[keys.index(k)][1]) for k in present}
        ch = [(k, f.intersection(tb)) for k, f in children]
        new = partition(old, parents, ch, r)
        for k, g in new.items():
            newgeo[k] = g; gofk[k] = gname
        touched |= gkeys
    if not newgeo: return None
    # items: the same order; new ones at the end
    order = list(keys)
    for k in newgeo:
        if k not in order and not newgeo[k].is_empty: order.append(k)
    idx = {k: i for i, k in enumerate(order)}
    newgeo = {k: g for k, g in newgeo.items() if k in idx}
    rings = []
    for i, k in enumerate(order):
        if k in newgeo: rings.append(rings_of(newgeo[k]))
        else: rings.append(items[i][1])
    gidx = {idx[k] for k in newgeo}
    gof = {idx[k]: gofk[k] for k in newgeo}
    # lines
    keep_e, xs = [], []
    cands = [i for i in gidx if not newgeo[order[i]].is_empty]
    trees = {}
    for gname in set(gof.values()):
        parts, pk = [], []
        for i in cands:
            if gof[i] != gname: continue
            for p in polys(newgeo[order[i]]): parts.append(p); pk.append(i)
        if parts: trees[gname] = (STRtree(parts), pk)
    def owner_near(seg, old):
        g = gof.get(old)
        if g not in trees: return old
        tr, pk = trees[g]
        m = Point((seg[0][0] + seg[1][0]) / 2, (seg[0][1] + seg[1][1]) / 2)
        return pk[int(tr.query_nearest(m)[0])]
    for a, b, pts, e in lines:
        ain, bin_ = a in gidx, (b >= 0 and b in gidx)
        if not ain and not bin_:
            if e is not None: keep_e.append(e)
            else: xs.append((a, b, pts))
            continue
        if ain and bin_ and gof[a] == gof[b]: continue  # inside one group: rebuilt below
        # the group side(s) of the same line, per segment (a coast, a border with any other place)
        runs = []
        for i in range(1, len(pts)):
            seg = [pts[i - 1], pts[i]]
            o = (owner_near(seg, a) if ain else a, owner_near(seg, b) if bin_ else b)
            if runs and runs[-1][0] == o: runs[-1][1].append(pts[i])
            else: runs.append([o, seg[:]])
        for (oa, ob), rp in runs:
            xs.append((oa, ob, rp))
    gl = sorted(cands)
    for ii, i in enumerate(gl):
        for j in gl[ii + 1:]:
            if gof[i] != gof[j]: continue
            gi, gj = newgeo[order[i]], newgeo[order[j]]
            if gi.distance(gj) > Q: continue
            shared = gi.boundary.intersection(gj.boundary)
            for l in lines_of(shared):
                xs.append((i, j, l))
    # write
    head_p = [[k, [len(rg) for rg in rings[i]]] for i, k in enumerate(order)]
    w = Writer(x, y)
    for rs in rings:
        for rg in rs:
            for p in rg: w.pt(p[0], p[1])
    head_x = []
    for a, b, l in xs:
        if len(l) < 2: continue
        head_x.append([a, b, len(l)])
        for p in l: w.pt(p[0], p[1])
    head = json.dumps({'p': head_p, 'e': keep_e, 'x': head_x}, separators=(',', ':')).encode()
    raw = b'WYAD' + struct.pack('<II', 1, len(head)) + head + bytes(w.out)
    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    return co.compress(raw) + co.flush(), {k: newgeo[k] for k in newgeo}

if __name__ == '__main__':
    src, dst, r = sys.argv[1], sys.argv[2], float(sys.argv[3])
    T = pickle.load(open('truth.pkl', 'rb'))['groups']
    from shapely.prepared import prep
    PREP = {k: prep(f) for _, cs in T.values() for k, f in cs}
    d, h, base = wyad.pack(src)
    TS = h['size']
    allkeys = set()
    for ps, cs in T.values(): allkeys |= set(ps) | {k for k, _ in cs}
    blobs = []
    changed = 0
    for t in h['tiles']:
        x, y, off, ln = t
        blob = d[base + off: base + off + ln]
        th, items, xl = wyad.tile(d, base, t)
        if any(k in allkeys for k, _ in items):
            res = rebuild_tile(t, th, items, xl, T, r)
            if res:
                blob = res[0]; changed += 1
        blobs.append((x, y, blob))
    tiles, off = [], 0
    for x, y, bl in blobs:
        tiles.append([x, y, off, len(bl)]); off += len(bl)
    head = json.dumps({'level': h['level'], 'size': h['size'], 'tiles': tiles}, separators=(',', ':')).encode()
    with open(dst, 'wb') as f:
        f.write(b'WYDP' + struct.pack('<II', 1, len(head)) + head)
        for _, _, bl in blobs: f.write(bl)
    print('tiles changed', changed, 'of', len(h['tiles']))

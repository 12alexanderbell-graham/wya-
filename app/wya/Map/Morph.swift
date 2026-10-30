import Foundation
import simd

/// THE DETAIL MORPH (Step 1d; the book's D20, done as each tile is read instead of in the data files, so no rebuild of
/// the data can ever drop it and the files don't grow). Nothing appears at once. Every point of a finer
/// level gets a second place: where it lies on the coarser level's outline of the same place. Across the zoom band the
/// finer level is drawn alone, each point moving from that second place (morph 0: it looks like the coarser level) to
/// its true place (morph 1), tied to the zoom, so a pinch that stops half way leaves it half way and pinching back
/// undoes it. A ring the coarser level doesn't have (a small island, a lake) grows from its own centre. Points on a
/// tile's cut edge stay where they are, so neighbouring tiles always meet.
nonisolated final class MorphIndex: @unchecked Sendable {
    private let pts: [SIMD2<Float>]
    private let cum: [Float]
    /// per segment: its first point, its second, its ring, the ring's place (-2: a lake of the coarse world)
    private let segA: [Int32], segB: [Int32], segRing: [Int32], segPlace: [Int32]
    private let ringLen: [Float]
    private let ringStart: [Int], ringCount: [Int]
    /// each place's rings, and the coarse world's lakes (-2)
    private let ringsOf: [Int32: [Int32]]
    private let cell: Float
    /// the segments by grid cell over the index's own box, laid flat (each cell's run in `cellSegs`)
    private let gx0: Int, gy0: Int, gw: Int, gh: Int
    private let cellStart: [Int32]
    private let cellSegs: [Int32]
    /// the places it has any outline of (a point of a place it lacks is not looked for at all)
    private let has: Set<Int32>

    /// rings: each its points, its place, and per point whether it lies on a tile's cut edge (a segment between two such
    /// points is a cut, not a real coast or border, and is left out)
    init(rings: [(points: [SIMD2<Float>], place: Int, cut: [Bool]?)], cell: Float) {
        var p: [SIMD2<Float>] = [], c: [Float] = []
        var a: [Int32] = [], b: [Int32] = [], r: [Int32] = [], pl: [Int32] = []
        var lens: [Float] = []
        var starts: [Int] = [], counts: [Int] = []
        var of: [Int32: [Int32]] = [:]
        for (ri, ring) in rings.enumerated() {
            of[Int32(ring.place), default: []].append(Int32(ri))
            let n = ring.points.count
            let s = p.count
            starts.append(s); counts.append(n)
            var run: Float = 0
            for i in 0 ..< n {
                p.append(ring.points[i]); c.append(run)
                run += simd_length(ring.points[(i + 1) % n] - ring.points[i])
            }
            lens.append(run)
            guard n >= 2 else { continue }
            for i in 0 ..< n {
                let j = (i + 1) % n
                if let cut = ring.cut, cut[i] && cut[j] { continue }
                a.append(Int32(s + i)); b.append(Int32(s + j)); r.append(Int32(ri)); pl.append(Int32(ring.place))
            }
        }
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for q in p { lo = simd_min(lo, q); hi = simd_max(hi, q) }
        if p.isEmpty { lo = .zero; hi = .zero }
        let x0 = Int((lo.x / cell).rounded(.down)), y0 = Int((lo.y / cell).rounded(.down))
        let w = Int((hi.x / cell).rounded(.down)) - x0 + 1, h = Int((hi.y / cell).rounded(.down)) - y0 + 1
        // two passes: count each cell's segments, then lay them out
        var count = [Int32](repeating: 0, count: w * h + 1)
        func cells(_ si: Int, _ f: (Int) -> Void) {
            let q0 = p[Int(a[si])], q1 = p[Int(b[si])]
            let cx0 = Int((min(q0.x, q1.x) / cell).rounded(.down)) - x0, cx1 = Int((max(q0.x, q1.x) / cell).rounded(.down)) - x0
            let cy0 = Int((min(q0.y, q1.y) / cell).rounded(.down)) - y0, cy1 = Int((max(q0.y, q1.y) / cell).rounded(.down)) - y0
            guard (cx1 - cx0 + 1) * (cy1 - cy0 + 1) <= 64 else { return }   // a stray long cut; never a real outline
            for x in cx0 ... cx1 { for y in cy0 ... cy1 { f(y * w + x) } }
        }
        for si in 0 ..< a.count { cells(si) { count[$0 + 1] += 1 } }
        for i in 0 ..< w * h { count[i + 1] += count[i] }
        var fill = count
        var segs = [Int32](repeating: 0, count: Int(count[w * h]))
        for si in 0 ..< a.count { cells(si) { segs[Int(fill[$0])] = Int32(si); fill[$0] += 1 } }
        pts = p; cum = c; segA = a; segB = b; segRing = r; segPlace = pl; ringLen = lens; ringStart = starts; ringCount = counts; ringsOf = of; self.cell = cell
        gx0 = x0; gy0 = y0; gw = w; gh = h; cellStart = count; cellSegs = segs; has = Set(pl)
    }

    /// the nearest point of the place's outline (or a coarse lake's) within `maxR`: where, on which ring, how far along
    /// it, and how far away
    func nearest(_ p: SIMD2<Float>, place: Int, maxR: Float, ring only: Int32 = -1) -> (q: SIMD2<Float>, ring: Int32, u: Float, d: Float)? {
        if place >= 0 && !has.contains(Int32(place)) && !has.contains(-2) { return nil }
        let cx = Int((p.x / cell).rounded(.down)) - gx0, cy = Int((p.y / cell).rounded(.down)) - gy0
        let maxK = Int((maxR / cell).rounded(.up))
        var best: (q: SIMD2<Float>, ring: Int32, u: Float, d: Float)?
        var bestD = Float.greatestFiniteMagnitude
        let P = Int32(place)
        func visit(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < gw, y < gh else { return }
            let c = y * gw + x
            var k = Int(cellStart[c])
            let e = Int(cellStart[c + 1])
            while k < e {
                let s = Int(cellSegs[k]); k += 1
                let pp = segPlace[s]
                guard place < 0 || pp == P || pp == -2 else { continue }
                if only >= 0 && segRing[s] != only { continue }
                let a = pts[Int(segA[s])], b = pts[Int(segB[s])]
                let ab = b - a
                let l2 = simd_length_squared(ab)
                let t = l2 > 0 ? min(1, max(0, simd_dot(p - a, ab) / l2)) : 0
                let q = a + t * ab
                let d = simd_length(p - q)
                if d < bestD { bestD = d; best = (q, segRing[s], cum[Int(segA[s])] + t * l2.squareRoot(), d) }
            }
        }
        var k = 0
        while k <= maxK {
            if k == 0 { visit(cx, cy) } else {
                for x in cx - k ... cx + k { visit(x, cy - k); visit(x, cy + k) }
                for y in cy - k + 1 ... cy + k - 1 { visit(cx - k, y); visit(cx + k, y) }
            }
            // anything in a further ring of cells is at least k cells away
            if bestD <= Float(k) * cell { break }
            k += 1
        }
        if bestD > maxR { return nil }
        return best
    }

    /// whether the coarse level has the place's land at a point (inside its rings by the even-odd rule, and not in one
    /// of the coarse world's lakes)
    func land(_ p: SIMD2<Float>, place: Int) -> Bool {
        func inside(_ rs: [Int32]) -> Bool {
            var c = false
            for ri in rs {
                let s = ringStart[Int(ri)], n = ringCount[Int(ri)]
                guard n >= 3 else { continue }
                var j = s + n - 1
                for i in s ..< s + n {
                    let a = pts[i], q = pts[j]
                    if (a.y > p.y) != (q.y > p.y), p.x < (q.x - a.x) * (p.y - a.y) / (q.y - a.y) + a.x { c.toggle() }
                    j = i
                }
            }
            return c
        }
        guard place >= 0, let rs = ringsOf[Int32(place)], inside(rs) else { return false }
        if let lakes = ringsOf[-2], inside(lakes) { return false }
        return true
    }

    /// whether the coarse level has anyone's land at a point (not in one of its lakes)
    func anyLand(_ p: SIMD2<Float>) -> Bool {
        for (k, _) in ringsOf where k >= 0 { if land(p, place: Int(k)) { return true } }
        return false
    }

    /// A LINE OF ITS OWN (not along a ring): the points that lie on the coarse outline are laid on it; each other point
    /// is held at the nearer of the anchors either side of it along the line (each laid on its own nearest place, one
    /// line drew a long double stroke across Norway at the band's start); a line with no point on the coarse outline
    /// grows out of its middle. Points on a cut edge stay.
    func lineFrom(points: [SIMD2<Float>], place: Int, cut: [Bool], close: Float, maxR: Float) -> [SIMD2<Float>] {
        let n = points.count
        guard n > 0 else { return points }
        var out = points
        var anchor = [SIMD2<Float>?](repeating: nil, count: n)
        for i in 0 ..< n {
            if cut[i] { anchor[i] = points[i] }
            else if let h = nearest(points[i], place: place, maxR: maxR), h.d < close { anchor[i] = h.q }
        }
        guard anchor.contains(where: { $0 != nil }) else {
            let mid = points[n / 2]
            return points.map { _ in mid }
        }
        var s = [Float](repeating: 0, count: n)
        for i in 1 ..< n { s[i] = s[i - 1] + simd_length(points[i] - points[i - 1]) }
        var prev: Int? = nil
        var nextOf = [Int?](repeating: nil, count: n)
        var nx: Int? = nil
        for i in stride(from: n - 1, through: 0, by: -1) { if anchor[i] != nil { nx = i }; nextOf[i] = nx }
        for i in 0 ..< n {
            if let q = anchor[i] { out[i] = q; prev = i; continue }
            let a = prev, b = nextOf[i]
            if let a, let b { out[i] = s[i] - s[a] <= s[b] - s[i] ? anchor[a]! : anchor[b]! }
            else if let a { out[i] = anchor[a]! }
            else if let b { out[i] = anchor[b]! }
        }
        return out
    }

    /// the point `u` along a coarse ring (wrapping round it)
    private func at(ring: Int32, u: Float) -> SIMD2<Float> {
        let ri = Int(ring), s = ringStart[ri], n = ringCount[ri], L = ringLen[ri]
        guard n > 0 else { return .zero }
        guard n > 1, L > 0 else { return pts[s] }
        var v = u.truncatingRemainder(dividingBy: L)
        if v < 0 { v += L }
        // the last point at or before v
        var lo = 0, hi = n - 1
        while lo < hi { let m = (lo + hi + 1) / 2; if cum[s + m] <= v { lo = m } else { hi = m - 1 } }
        let a = pts[s + lo], b = pts[s + (lo + 1) % n]
        let segEnd = lo + 1 < n ? cum[s + lo + 1] : L
        let l = segEnd - cum[s + lo]
        return l > 0 ? a + (b - a) * ((v - cum[s + lo]) / l) : a
    }

    #if DEBUG
    /// test only (driver "probe x y"): rings near this map point log how they were laid, to this file
    nonisolated(unsafe) static var probe: SIMD2<Float>?
    nonisolated(unsafe) static var probeFile: String = ""
    static func note(_ s: String) {
        guard !probeFile.isEmpty else { return }
        let url = URL(fileURLWithPath: probeFile)
        let line = Data((s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() } else { try? line.write(to: url) }
    }
    #endif

    /// THE SECOND PLACE OF EVERY POINT of a finer level's rings. `close`: how near the coarse outline a point on a
    /// tile's cut edge must be to be laid on it; `maxR`: how far to look at all.
    func from(points: [SIMD2<Float>], rings: [[Range<Int>]], places: [Int], cut: [Bool], pin: [Bool], close: Float, maxR: Float) -> [SIMD2<Float>] {
        var out = points
        for (ii, rs) in rings.enumerated() {
            let place = places[ii]
            for r in rs where r.count >= 3 {
                #if DEBUG
                // test only: a ring whose morph start spreads far wider than the ring itself is logged (probe.log)
                defer {
                    if !Self.probeFile.isEmpty {
                        var a0 = SIMD2<Float>(repeating: .greatestFiniteMagnitude), a1 = -a0
                        var b0 = a0, b1 = -a0
                        for i in r { a0 = simd_min(a0, points[i]); a1 = simd_max(a1, points[i]); b0 = simd_min(b0, out[i]); b1 = simd_max(b1, out[i]) }
                        let w = simd_length(a1 - a0), fw = simd_length(b1 - b0)
                        if fw > 2 * w + 0.02 {
                            Self.note(String(format: "wide start: place %d n %d cuts %d true %.3f %.3f %.3f %.3f (%.3f) start %.3f %.3f %.3f %.3f (%.3f)",
                                             place, r.count, r.filter { cut[$0] }.count, a0.x, a0.y, a1.x, a1.y, w, b0.x, b0.y, b1.x, b1.y, fw))
                        }
                    }
                }
                #endif
                var near: [(q: SIMD2<Float>, ring: Int32, u: Float, d: Float)?] = []
                near.reserveCapacity(r.count)
                var nCut = 0
                var votes: [Int32: Int] = [:]
                for i in r {
                    let h = nearest(points[i], place: place, maxR: maxR)
                    // a point on the tile's cut edge is decided once the ring is known (below)
                    if cut[i] { nCut += 1; near.append(nil); continue }
                    if let h { votes[h.ring, default: 0] += 1 }
                    near.append(h)
                }
                let own = r.count - nCut
                var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
                for i in r { lo = simd_min(lo, points[i]); hi = simd_max(hi, points[i]) }
                // A RING HAS ITS COUNTERPART when its points lie, as a rule, close to the coarse outline for its size:
                // the middle distance under a sixth of how wide it is (a mainland with far more detailed coasts, a big
                // lake both levels have, an island both have). A lake or an island only the finer level has lies as far
                // from the nearest coarse outline as it is wide, or farther: it grows out of its own centre. (Tested on
                // Norway's fjords and lakes and Sweden's lakes: a fixed "how close" made the big lakes vanish at the
                // band's start; laid on the coast they became slivers.)
                var ds: [Float] = []
                ds.reserveCapacity(own)
                for (k, i) in r.enumerated() where !cut[i] { ds.append(near[k]?.d ?? maxR) }
                ds.sort()
                let median = ds.isEmpty ? 0 : ds[ds.count / 2]
                let wide = simd_length(hi - lo)
                // and at least half its points found an outline of its place within reach at all
                let counterpart = own > 0 && median <= wide / 6 && median < maxR
                #if DEBUG
                if let pr = Self.probe, pr.x >= lo.x - 0.05, pr.x <= hi.x + 0.05, pr.y >= lo.y - 0.05, pr.y <= hi.y + 0.05 {
                    Self.note(String(format: "probe ring place %d n %d cut %d median %.4f wide %.4f counterpart %d votes %@ box %.3f %.3f %.3f %.3f",
                                     place, r.count, nCut, median, wide, counterpart ? 1 : 0, votes.description, lo.x, lo.y, hi.x, hi.y))
                }
                #endif
                if !counterpart {
                    // land the coarser level has too, only drawn with another place (a border the finer level draws
                    // differently: the Aouzou strip, Bir Tawil): it is there from the start and stays where it is; growing
                    // it from a point showed the sea through a hole the shape of the tile
                    if wide > 0.5 && anyLand((lo + hi) / 2) { continue }
                    if nCut > 0 {
                        // a ring the coarser level doesn't have, cut by the tile's edge (a lake across two tiles): the
                        // whole ring, its cut points too, goes to the middle of its points on the cut edge, the same
                        // points in both tiles, so both halves grow out of one point and meet (laid on the cut edge
                        // itself, its shore drew a double line along the tile's side)
                        var c = SIMD2<Float>(0, 0)
                        var k = 0
                        for i in r where cut[i] { c += points[i]; k += 1 }
                        c /= Float(max(1, k))
                        for i in r { out[i] = c }
                        continue
                    }
                    // a ring the coarser level doesn't have: it grows out of its own centre
                    var c = SIMD2<Float>(0, 0)
                    for i in r { c += points[i] }
                    c /= Float(r.count)
                    for i in r { out[i] = c }
                    continue
                }
                // A POINT ON THE TILE'S CUT EDGE, decided by the point (and its ring's coarse counterpart) so the two
                // tiles that share it decide the same: where the coarse level has this place's land there, it stays;
                // where it has water (a lake or a fjord cut by the tile's edge), it goes to the nearest point of the
                // coarse ring the rest of its ring lies on (kept where it was, the cut lake's edge drew a long sliver
                // along the tile's side; sent to any shore, a lake became a triangle between three lakes)
                let target = votes.max(by: { $0.value < $1.value })?.key ?? -1
                for (k, i) in r.enumerated() where cut[i] {
                    // (anyone's land: where the finer level draws a border the coarser one doesn't have, the land is
                    // there in both, and the ring on the other side of the cut keeps its point there too)
                    if pin[i] || place < 0 || land(points[i], place: place) || anyLand(points[i]) { near[k] = (points[i], -1, 0, 0); continue }
                    if let h = nearest(points[i], place: place, maxR: 3 * maxR, ring: target) { near[k] = (h.q, -1, 0, h.d) }
                    else { near[k] = (points[i], -1, 0, 0) }
                }
                // ALONG THE COARSE OUTLINE IN ORDER (nearest points alone folded: a fjord's far bank or a lake's far
                // shore laid on another stretch drew long slivers across the land half way through the band). The points
                // that lie on the coarse outline (within `close`) are anchors; between two anchors on the same coarse
                // ring every point takes its place along that ring by how far along the fine ring it is, so a fjord
                // between them closes onto the coast between them and nothing crosses. Between anchors on two different
                // coarse rings (two lakes the finer level joins by a channel) each point takes its nearest place.
                let n = r.count
                for (k, i) in r.enumerated() { out[i] = near[k]?.q ?? points[i] }
                var s = [Float](repeating: 0, count: n)
                for k in 1 ..< n { s[k] = s[k - 1] + simd_length(points[r.lowerBound + k] - points[r.lowerBound + k - 1]) }
                let S = s[n - 1] + simd_length(points[r.lowerBound] - points[r.upperBound - 1])
                var anchors: [Int] = []
                // the cut edge's points are anchors too, where they were decided above (runs that crossed a cut kept
                // each point's own nearest place, and jumped between lakes: triangles across Sweden at the band's start)
                for k in 0 ..< n {
                    if cut[r.lowerBound + k] { if near[k] != nil { anchors.append(k) } }
                    else if let h = near[k], h.d < close { anchors.append(k) }
                }
                guard anchors.count >= 2 else { continue }
                // each coarse ring's direction for this fine ring: the way most anchor steps along it go
                var dirVote: [Int32: Float] = [:]
                for j in 0 ..< anchors.count {
                    let ha = near[anchors[j]]!, hb = near[anchors[(j + 1) % anchors.count]]!
                    guard ha.ring == hb.ring, ha.ring >= 0 else { continue }
                    let L = ringLen[Int(ha.ring)]
                    var du = hb.u - ha.u
                    if du > L / 2 { du -= L } else if du < -L / 2 { du += L }
                    dirVote[ha.ring, default: 0] += du > 0 ? 1 : (du < 0 ? -1 : 0)
                }
                /// a run no rule lays well: its first half held at the anchor it leaves, its second half at the one it
                /// reaches (each point on its own nearest place jumped between lakes and drew triangles across the land)
                func hold(_ a: Int, _ b: Int, _ count: Int, _ sa: Float, _ sb: Float, _ qa: SIMD2<Float>, _ qb: SIMD2<Float>) {
                    for m in 1 ..< count {
                        let k = (a + m) % n
                        let sk = k > a ? s[k] : s[k] + S
                        out[r.lowerBound + k] = sk - sa <= sb - sk ? qa : qb
                    }
                }
                for j in 0 ..< anchors.count {
                    let a = anchors[j], b = anchors[(j + 1) % anchors.count]
                    let ha = near[a]!, hb = near[b]!
                    let count = b > a ? b - a : n - a + b
                    guard count > 1 else { continue }
                    // a run across a cut edge keeps the nearest places (the cut decides there)
                    let sa = s[a], sb = b > a ? s[b] : s[b] + S
                    guard sb > sa else { continue }
                    // from or to a cut edge's point: held at the two ends
                    if ha.ring < 0 || hb.ring < 0 { hold(a, b, count, sa, sb, ha.q, hb.q); continue }
                    var along = ha.ring == hb.ring
                    let L = ringLen[Int(ha.ring)]
                    let dir: Float = (dirVote[ha.ring] ?? 0) >= 0 ? 1 : -1
                    var du = (hb.u - ha.u) * dir
                    du = du.truncatingRemainder(dividingBy: L); if du < 0 { du += L }
                    // a step back, or most of a lap: not a stretch to share out
                    if du > L / 2 { along = false }
                    // never a stretch of the coarse ring far longer than the fine run itself (two anchors either side of
                    // a narrow neck, the coarse ring's way between them round a whole peninsula: a small lake was laid
                    // out over 100 km): those points keep their nearest places
                    let longest = 3 * (sb - sa) + 4 * close
                    if along && du > longest { hold(a, b, count, sa, sb, ha.q, hb.q); continue }
                    if along {
                        for m in 1 ..< count {
                            let k = (a + m) % n
                            let f = ((k > a ? s[k] : s[k] + S) - sa) / (sb - sa)
                            out[r.lowerBound + k] = at(ring: ha.ring, u: ha.u + dir * du * f)
                        }
                        continue
                    }
                    // the same ring the wrong way round: the points keep their nearest places
                    guard ha.ring != hb.ring else { hold(a, b, count, sa, sb, ha.q, hb.q); continue }
                    // FROM ONE COARSE RING TO ANOTHER (a lake the finer level joins to the sea, or to another lake, by
                    // a channel the coarser level doesn't have): the run goes along the first ring to where the two
                    // rings come closest on this run, across that gap, and along the second ring to its anchor. Both
                    // banks of the channel cross at the same gap, so the channel has no width at the band's start and
                    // opens out of that one line (laid straight from anchor to anchor, the two banks drew a wedge
                    // across the land between three lakes)
                    var best = (k: -1, d: Float.greatestFiniteMagnitude, qa: SIMD2<Float>.zero, ua: Float(0), qb: SIMD2<Float>.zero, ub: Float(0))
                    for m in 1 ..< count {
                        let k = (a + m) % n
                        guard let x = nearest(points[r.lowerBound + k], place: place, maxR: 3 * maxR, ring: ha.ring),
                              let y = nearest(points[r.lowerBound + k], place: place, maxR: 3 * maxR, ring: hb.ring) else { continue }
                        let d = simd_length(x.q - y.q)
                        if d < best.d { best = (k, d, x.q, x.u, y.q, y.u) }
                    }
                    guard best.k >= 0 else { hold(a, b, count, sa, sb, ha.q, hb.q); continue }
                    let sk = best.k > a ? s[best.k] : s[best.k] + S
                    func arc(_ ring: Int32, _ u0: Float, _ u1: Float) -> Float {
                        let L = ringLen[Int(ring)]
                        var d = abs(u1 - u0).truncatingRemainder(dividingBy: L)
                        if d > L / 2 { d = L - d }
                        return d
                    }
                    if arc(ha.ring, ha.u, best.ua) > longest || arc(hb.ring, best.ub, hb.u) > longest || best.d > longest {
                        hold(a, b, count, sa, sb, ha.q, hb.q); continue
                    }
                    func stretch(_ ring: Int32, from u0: Float, to u1: Float, _ f: Float) -> SIMD2<Float> {
                        let L = ringLen[Int(ring)]
                        var d = u1 - u0
                        if d > L / 2 { d -= L } else if d < -L / 2 { d += L }
                        return at(ring: ring, u: u0 + d * f)
                    }
                    for m in 1 ..< count {
                        let k = (a + m) % n
                        let sk2 = k > a ? s[k] : s[k] + S
                        if sk2 <= sk {
                            let f = sk > sa ? (sk2 - sa) / (sk - sa) : 1
                            out[r.lowerBound + k] = stretch(ha.ring, from: ha.u, to: best.ua, f)
                        } else {
                            let f = sb > sk ? (sk2 - sk) / (sb - sk) : 1
                            out[r.lowerBound + k] = stretch(hb.ring, from: best.ub, to: hb.u, f)
                        }
                    }
                }
            }
        }
        // NO RING IS EVER LAID OUT WIDER THAN IT IS: a ring whose morph start spreads far wider than the ring itself (a
        // lake or a small island the rules above laid along a long stretch of a coarse outline, drawing its shore as a
        // big triangle across the land half way through the band) grows out of its own centre instead, as a ring the
        // coarser level doesn't have does
        for rs in rings {
            for r in rs where r.count >= 3 {
                var a0 = SIMD2<Float>(repeating: .greatestFiniteMagnitude), a1 = -a0
                var b0 = a0, b1 = -a0
                for i in r { a0 = simd_min(a0, points[i]); a1 = simd_max(a1, points[i]); b0 = simd_min(b0, out[i]); b1 = simd_max(b1, out[i]) }
                let w = simd_length(a1 - a0), fw = simd_length(b1 - b0)
                // only a whole ring inside the tile: a piece cut by the tile's edge is laid by the cut-edge rule above
                guard fw > 1.5 * w + 0.01, !r.contains(where: { cut[$0] }) else { continue }
                var c = SIMD2<Float>(0, 0)
                for i in r { c += points[i] }
                c /= Float(r.count)
                for i in r { out[i] = c }
            }
        }
        return out
    }
}

/// The coarse outlines a tile's morph is laid on, kept while they are used: the world's (for the 500 m tiles), built
/// once, and each 10° tile of the 500 m level (for the 100 m tiles inside it), the last 24.
nonisolated final class MorphSources: @unchecked Sendable {
    private let lock = NSLock()
    private var world: MorphIndex?
    private var tiles: [Int64: MorphIndex] = [:]
    private var order: [Int64] = []

    func world(_ w: World) -> MorphIndex {
        lock.lock(); defer { lock.unlock() }
        if let world { return world }
        var rings: [(points: [SIMD2<Float>], place: Int, cut: [Bool]?)] = []
        for u in 0 ..< w.unitRings.count {
            for ri in w.unitRings[u] {
                let r = w.rings[ri]
                rings.append((Array(w.points[r.start ..< r.start + r.count]), w.unitOwner[u], nil))
            }
        }
        for ri in w.lakeRings {
            let r = w.rings[ri]
            rings.append((Array(w.points[r.start ..< r.start + r.count]), -2, nil))
        }
        let m = MorphIndex(rings: rings, cell: 0.5)
        world = m
        return m
    }

    func tile(_ key: Int64, make: () -> MorphIndex?) -> MorphIndex? {
        lock.lock()
        if let t = tiles[key] { lock.unlock(); return t }
        lock.unlock()
        guard let m = make() else { return nil }
        lock.lock(); defer { lock.unlock() }
        tiles[key] = m; order.append(key)
        if order.count > 24 { tiles[order.removeFirst()] = nil }
        return m
    }
}

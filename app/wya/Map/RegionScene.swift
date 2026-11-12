import Foundation
import simd

/// ONE COUNTRY'S REGIONS AS THE MAP DRAWS THEM (Part 6.5): its units' rings laid in the map's Equal Earth, as fans for
/// the stencil (even-odd, so a ring inside another of the same unit is a hole), the lines between two regions as the
/// lines' segments, and each entry's box and rings for the finger. Built off the main thread from the bundled file
/// (or a downloaded finer level later), before the country's land changes (6.4: never "blue for a second").
nonisolated final class RegionScene: @unchecked Sendable {
    /// the place on the world map whose regions these are, its id as the files name it, the level's row in the table
    let place: Int
    let id: String
    let row: Int
    let level: RegionCatalog.Level
    /// the distinct regions (a unit cut by a piece line is one region), their names, their parents one level up
    let unitIDs: [String]
    let unitNames: [String]
    let unitParents: [String?]
    /// each drawn entry's region
    let entryUnit: [Int]
    /// the fans' points and index, each entry's run in it
    let points: [SIMD2<Float>]
    let fans: [UInt32]
    let runs: [(start: Int, count: Int)]
    /// the lines between regions, ten floats a segment: its ends, where its ends lie along their border (0 to 1), unused
    let segs: [Float]
    /// THE PARENTS' BORDERS: of those lines, the ones between two regions of different parents (a state's line among
    /// its counties'), in the same layout; drawn again, bolder, so the level above reads through the deeper one.
    /// Empty where the regions share one parent or have none
    let bold: [Float]
    /// each entry's box and rings in map units, for the finger
    private let boxes: [SIMD4<Float>]
    private let rings: [[[SIMD2<Float>]]]
    /// the regions' box (every part, far ones included)
    let box: SIMD4<Float>
    /// A REGION THAT CAN BE LOST (12 Nov): one standing alone in the sea (its box touches no other region's), on a level
    /// of at most 200 regions: the middle of its biggest piece (x, y) and how big its land is (z, map units: the width
    /// of a circle with all its pieces' area, so an atoll's thin rim 12 points long counts as the speck it is).
    /// Such a region is the map's diamond while it is under 6 points across (an island country's regions are specks at
    /// the country's size: Tuvalu's nine atolls over 600 km). z is infinite for every other region: a region that
    /// touches its neighbours is part of land that can be seen, however small it is (France's communes get none).
    let unitSpot: [SIMD3<Float>]
    /// each region's box (all its entries), for VoiceOver's elements
    func unitBox(_ u: Int) -> SIMD4<Float>? {
        var out: SIMD4<Float>?
        guard u >= 0, u < unitEntries.count else { return nil }
        for e in unitEntries[u] {
            let b = boxes[e]
            out = out.map { SIMD4(min($0.x, b.x), min($0.y, b.y), max($0.z, b.z), max($0.w, b.w)) } ?? b
        }
        return out
    }

    /// `above`: the next coarser level's file, for a file whose regions do not name their parents (France's
    /// departments): each region's parent is then the coarser region most of it lies in
    init?(place: Int, id: String, row: Int, file f: RegionFile, above: RegionFile? = nil) {
        guard let rows = RegionCatalog.shared.levels[id], row >= 1, row <= rows.count else { return nil }
        self.place = place; self.id = id; self.row = row; level = rows[row - 1]
        var ids: [String] = [], names: [String] = [], parents: [String?] = [], index: [String: Int] = [:]
        var eu: [Int] = [], pts: [SIMD2<Float>] = [], fan: [UInt32] = [], rn: [(Int, Int)] = []
        var bx: [SIMD4<Float>] = [], rs: [[[SIMD2<Float>]]] = []
        var all = SIMD4<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        for u in f.units {
            let ui: Int
            if let i = index[u.id] { ui = i } else {
                ui = ids.count; index[u.id] = ui; ids.append(u.id); names.append(u.name); parents.append(u.parent)
            }
            eu.append(ui)
            let s = fan.count
            var b = SIMD4<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            var mine: [[SIMD2<Float>]] = []
            for ring in u.rings where ring.count >= 3 {
                let m = Self.project(ring)
                let start = UInt32(pts.count)
                pts += m
                for i in 1 ..< m.count - 1 { fan += [start, start + UInt32(i), start + UInt32(i + 1)] }
                for p in m { b = SIMD4(min(b.x, p.x), min(b.y, p.y), max(b.z, p.x), max(b.w, p.y)) }
                mine.append(m)
            }
            rn.append((s, fan.count - s))
            bx.append(b); rs.append(mine)
            if !mine.isEmpty { all = SIMD4(min(all.x, b.x), min(all.y, b.y), max(all.z, b.z), max(all.w, b.w)) }
        }
        // each border between two regions as its segments, with where each lies along its border (0 at one end, 1 at
        // the other), so a border can draw in from both its ends and undraw back into them (A6.9)
        var sg: [Float] = []
        for line in f.inner where line.count >= 2 {
            let m = Self.project(line)
            var cum: [Float] = [0]
            for i in 1 ..< m.count { cum.append(cum[i - 1] + simd_distance(m[i - 1], m[i])) }
            let total = max(cum[m.count - 1], 1e-9)
            for i in 0 ..< m.count - 1 {
                let a = m[i], c = m[i + 1]
                sg += [a.x, a.y, c.x, c.y, cum[i] / total, cum[i + 1] / total, 0, 0, 0, 0]
            }
        }
        guard !rn.isEmpty, all.x < all.z else { return nil }
        // the parents' borders: a line's segment is an edge of the rings on both its sides (the file's arcs are the
        // rings' own points), so each segment takes the parents of the rings it is an edge of; two different: bold
        var bd: [Float] = []
        var parentIndex: [String: Int32] = [:]
        var pidx: [Int32] = parents.map { p in
            guard let p else { return 0 }
            if let i = parentIndex[p] { return i }
            let i = Int32(parentIndex.count + 1); parentIndex[p] = i; return i
        }
        if parentIndex.isEmpty, let above {
            pidx = Self.parents(of: f, in: above, index: index, count: ids.count)
            // (and the regions know them: a department's card names its region, and its stamp reaches it)
            var aboveIDs: [String] = [], seenAbove = Set<String>()
            for u in above.units where seenAbove.insert(u.id).inserted { aboveIDs.append(u.id) }
            parents = pidx.map { $0 > 0 && Int($0) <= aboveIDs.count ? aboveIDs[Int($0) - 1] : nil }
            parentIndex = Dictionary(uniqueKeysWithValues: Set(pidx).filter { $0 > 0 }.map { (String($0), $0) })
        }
        if parentIndex.count > 1 {
            func key(_ p: SIMD2<Float>, _ q: SIMD2<Float>) -> SIMD4<Int32> {
                let a = SIMD2(Int32((p.x * 2e4).rounded()), Int32((p.y * 2e4).rounded()))
                let b = SIMD2(Int32((q.x * 2e4).rounded()), Int32((q.y * 2e4).rounded()))
                return (a.x, a.y) < (b.x, b.y) ? SIMD4(a.x, a.y, b.x, b.y) : SIMD4(b.x, b.y, a.x, a.y)
            }
            // (-1: no ring seen yet; -2: rings of two parents)
            var sides: [SIMD4<Int32>: Int32] = [:]
            sides.reserveCapacity(sg.count / 10)
            for i in stride(from: 0, to: sg.count, by: 10) { sides[key(SIMD2(sg[i], sg[i + 1]), SIMD2(sg[i + 2], sg[i + 3]))] = -1 }
            for (e, mine) in rs.enumerated() {
                let par = pidx[eu[e]]
                for m in mine {
                    for j in m.indices {
                        let k = key(m[j], m[(j + 1) % m.count])
                        guard let v = sides[k], v != -2 else { continue }
                        sides[k] = v == -1 || v == par ? par : -2
                    }
                }
            }
            for i in stride(from: 0, to: sg.count, by: 10)
            where sides[key(SIMD2(sg[i], sg[i + 1]), SIMD2(sg[i + 2], sg[i + 3]))] == -2 { bd += sg[i ..< i + 10] }
        }
        bold = bd
        unitIDs = ids; unitNames = names; unitParents = parents; entryUnit = eu
        var ue = [[Int]](repeating: [], count: ids.count)
        for (e, u) in eu.enumerated() { ue[u].append(e) }
        unitEntries = ue
        points = pts; fans = fan; runs = rn; segs = sg
        boxes = bx; rings = rs; box = all
        var spots = [SIMD3<Float>](repeating: SIMD3(0, 0, .infinity), count: ids.count)
        if ids.count <= 200 {
            var ub = [SIMD4<Float>?](repeating: nil, count: ids.count)
            var big = [(area: Float, c: SIMD2<Float>, across: Float, box: SIMD4<Float>)?](repeating: nil, count: ids.count)
            var pieces: [(u: Int, box: SIMD4<Float>)] = []
            var land = [Float](repeating: 0, count: ids.count)
            for (e, u) in eu.enumerated() {
                let b = bx[e]
                guard b.x <= b.z else { continue }
                ub[u] = ub[u].map { SIMD4(min($0.x, b.x), min($0.y, b.y), max($0.z, b.z), max($0.w, b.w)) } ?? b
                for ring in rs[e] {
                    var r = SIMD4<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
                    for p in ring { r = SIMD4(min(r.x, p.x), min(r.y, p.y), max(r.z, p.x), max(r.w, p.y)) }
                    let a = (r.z - r.x) * (r.w - r.y)
                    // (the ring's own area, by the shoelace sum)
                    var s: Float = 0
                    for i in ring.indices { let p = ring[i], q = ring[(i + 1) % ring.count]; s += (p.x - r.x) * (q.y - r.y) - (q.x - r.x) * (p.y - r.y) }
                    land[u] += abs(s) / 2
                    if a > (big[u]?.area ?? -1) { big[u] = (a, SIMD2((r.x + r.z) / 2, (r.y + r.w) / 2), max(r.z - r.x, r.w - r.y), r) }
                    pieces.append((u, r))
                }
            }
            // (alone: its biggest piece's box meets no piece of another region. Piece by piece, not region by region:
            // the Seychelles' outer islands are one region whose box holds every other region's islands)
            for u in ids.indices {
                guard ub[u] != nil, let g = big[u] else { continue }
                let b = g.box
                var alone = true
                for p in pieces where p.u != u {
                    let o = p.box
                    if b.x <= o.z, o.x <= b.z, b.y <= o.w, o.y <= b.w { alone = false; break }
                }
                if alone { spots[u] = SIMD3(g.c.x, g.c.y, 2 * (land[u] / .pi).squareRoot()) }
            }
        }
        unitSpot = spots
    }

    /// EACH REGION'S PARENT BY WHERE IT LIES (a file that names none): four points inside the region's biggest ring
    /// (its middle, and three points a little in from its edge toward the middle) are looked up in the coarser level's
    /// regions; the one holding most of them is the parent (its number from 1; 0: none)
    private static func parents(of f: RegionFile, in above: RegionFile, index: [String: Int], count: Int) -> [Int32] {
        func area(_ r: [SIMD2<Double>]) -> Double {
            var a = 0.0
            for i in r.indices { let p = r[i], q = r[(i + 1) % r.count]; a += p.x * q.y - q.x * p.y }
            return a / 2
        }
        func holds(_ r: [SIMD2<Double>], _ p: SIMD2<Double>) -> Bool {
            var inside = false
            var j = r.count - 1
            for i in r.indices {
                let a = r[i], b = r[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                j = i
            }
            return inside
        }
        // the coarser regions: their number by id, each entry's box and rings
        var number: [String: Int32] = [:]
        var up: [(n: Int32, box: SIMD4<Double>, rings: [[SIMD2<Double>]])] = []
        for u in above.units {
            let n = number[u.id] ?? Int32(number.count + 1)
            number[u.id] = n
            var b = SIMD4<Double>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            for r in u.rings { for p in r { b = SIMD4(min(b.x, p.x), min(b.y, p.y), max(b.z, p.x), max(b.w, p.y)) } }
            up.append((n, b, u.rings))
        }
        // each region's biggest ring (over all its entries)
        var biggest = [[SIMD2<Double>]?](repeating: nil, count: count)
        var size = [Double](repeating: 0, count: count)
        for u in f.units {
            guard let ui = index[u.id] else { continue }
            for r in u.rings where r.count >= 3 {
                let a = abs(area(r))
                if a > size[ui] { size[ui] = a; biggest[ui] = r }
            }
        }
        return biggest.map { ring in
            guard let r = ring else { return 0 }
            let a = area(r)
            var c = SIMD2<Double>(0, 0)
            if abs(a) > 1e-12 {
                for i in r.indices {
                    let p = r[i], q = r[(i + 1) % r.count], w = p.x * q.y - q.x * p.y
                    c += (p + q) * w
                }
                c /= 6 * a
            } else { c = r.reduce(SIMD2<Double>(0, 0), +) / Double(r.count) }
            let samples = [c] + [r.count / 6, r.count / 2, r.count * 5 / 6].map { r[$0] + (c - r[$0]) * 0.15 }
            var votes: [Int32: Int] = [:]
            for p in samples {
                for u in up where p.x >= u.box.x && p.x <= u.box.z && p.y >= u.box.y && p.y <= u.box.w {
                    // (even-odd over the entry's rings: a ring inside another is a hole)
                    if u.rings.reduce(false, { $0 != holds($1, p) }) { votes[u.n, default: 0] += 1; break }
                }
            }
            return votes.max { $0.value < $1.value }?.key ?? 0
        }
    }

    /// a ring or line in the map's units; one lying mostly past 180° east (the old files' 0 to 360) is brought round to
    /// its place west of the date line, as the world draws it
    static func project(_ ring: [SIMD2<Double>]) -> [SIMD2<Float>] {
        let mean = ring.reduce(0) { $0 + $1.x } / Double(max(1, ring.count))
        let shift: Double = mean > 180 ? -360 : mean < -180 ? 360 : 0
        return ring.map { EqualEarth.project(lon: $0.x + shift, lat: $0.y) }
    }

    /// a region's rings, all its entries' (Apple's map draws them: Map/AppleWorld.swift)
    func unitRings(_ u: Int) -> [[SIMD2<Float>]] {
        entryUnit.indices.filter { entryUnit[$0] == u }.flatMap { rings[$0] }
    }

    /// the region under a map point (the smallest whose rings hold it), or nil
    func unit(at p: SIMD2<Float>) -> Int? {
        var best: (Int, Float)?
        for e in runs.indices {
            let b = boxes[e]
            guard p.x >= b.x, p.x <= b.z, p.y >= b.y, p.y <= b.w else { continue }
            var inside = false
            for r in rings[e] {
                var j = r.count - 1
                for i in 0 ..< r.count {
                    let a = r[i], c = r[j]
                    if (a.y > p.y) != (c.y > p.y), p.x < (c.x - a.x) * (p.y - a.y) / (c.y - a.y) + a.x { inside.toggle() }
                    j = i
                }
            }
            guard inside else { continue }
            let area = (b.z - b.x) * (b.w - b.y)
            if best == nil || area < best!.1 { best = (entryUnit[e], area) }
        }
        return best?.0
    }

    /// the region nearest a point that none holds (a coast drawn a little inside the true one: a find on the shore), by
    /// its parts' boxes, within `reach` map units; nil past it
    func nearestUnit(_ p: SIMD2<Float>, reach: Float) -> Int? {
        // (nearest box first; among boxes it is inside, the smallest)
        var best: (Int, Float, Float)?
        for e in runs.indices {
            let b = boxes[e]
            guard b.x <= b.z else { continue }
            let dx = max(b.x - p.x, 0, p.x - b.z), dy = max(b.y - p.y, 0, p.y - b.w)
            let d = (dx * dx + dy * dy).squareRoot(), area = (b.z - b.x) * (b.w - b.y)
            guard d <= reach else { continue }
            if best == nil || d < best!.1 || (d == best!.1 && area < best!.2) { best = (entryUnit[e], d, area) }
        }
        return best?.0
    }

    /// a region's box in map units (all its parts)
    func box(of unit: Int) -> SIMD4<Float>? {
        var b: SIMD4<Float>?
        for e in entryUnit.indices where entryUnit[e] == unit {
            let x = boxes[e]
            guard x.x <= x.z else { continue }
            b = b.map { SIMD4(min($0.x, x.x), min($0.y, x.y), max($0.z, x.z), max($0.w, x.w)) } ?? x
        }
        return b
    }

    /// each region's entries
    let unitEntries: [[Int]]
    /// the entries of a set of regions (what the renderer fills for them)
    func entries(of units: Set<Int>) -> [Int] { units.sorted().flatMap { unitEntries[$0] } }
}

/// WHAT A CHANGE OF REGION MAP DRAWS (A6.9, the yes of): the borders both levels have stay as they are; borders
/// only the new level has draw in from both their
/// ends; borders only the old level had undraw back into their ends (0.4 s each). Opening a country, every border is
/// new (drawing in from the outline, A6.7); leaving it, every border is old (undrawing into the outline, A6.13).
nonisolated final class RegionLines: @unchecked Sendable {
    let shared: [Float]
    let new: [Float]
    let old: [Float]
    /// when it starts (the new borders after `delay`, the old ones at once)
    var start: CFTimeInterval
    let delay: Double
    /// the test driver's slow motion for frame checks (1 = real speed)
    nonisolated(unsafe) static var slow: Double = 1

    init(shared: [Float], new: [Float], old: [Float], start: CFTimeInterval, delay: Double) {
        self.shared = shared; self.new = new; self.old = old; self.start = start; self.delay = delay
    }

    /// from one scene to the next (either may be nil): segments matched by their two ends, either way round
    static func between(_ a: RegionScene?, _ b: RegionScene?, start: CFTimeInterval, delay: Double) -> RegionLines {
        let olds = a?.segs ?? [], news = b?.segs ?? []
        func key(_ g: ArraySlice<Float>) -> SIMD4<Int32> {
            let i = g.startIndex
            let p = SIMD2(Int32((g[i] * 2e4).rounded()), Int32((g[i + 1] * 2e4).rounded()))
            let q = SIMD2(Int32((g[i + 2] * 2e4).rounded()), Int32((g[i + 3] * 2e4).rounded()))
            return (p.x, p.y) < (q.x, q.y) ? SIMD4(p.x, p.y, q.x, q.y) : SIMD4(q.x, q.y, p.x, p.y)
        }
        var oldKeys = Set<SIMD4<Int32>>()
        oldKeys.reserveCapacity(olds.count / 10)
        for i in stride(from: 0, to: olds.count, by: 10) { oldKeys.insert(key(olds[i ..< i + 10])) }
        var shared: [Float] = [], new: [Float] = []
        var used = Set<SIMD4<Int32>>()
        for i in stride(from: 0, to: news.count, by: 10) {
            let g = news[i ..< i + 10], k = key(g)
            if oldKeys.contains(k) { shared += g; used.insert(k) } else { new += g }
        }
        var old: [Float] = []
        if !used.isEmpty || a != nil {
            for i in stride(from: 0, to: olds.count, by: 10) where !used.contains(key(olds[i ..< i + 10])) { old += olds[i ..< i + 10] }
        }
        return RegionLines(shared: shared, new: new, old: old, start: start, delay: delay)
    }
}

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
    /// the lines between regions in the lines' layout (ends, the ends at the draw's start, distance along, kind): each
    /// segment starts as nothing at its first end and grows to its second, so the borders draw along their length
    let segs: [Float]
    /// each entry's box and rings in map units, for the finger
    private let boxes: [SIMD4<Float>]
    private let rings: [[[SIMD2<Float>]]]
    /// the regions' box (every part, far ones included)
    let box: SIMD4<Float>

    init?(place: Int, id: String, row: Int, file f: RegionFile) {
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
        var sg: [Float] = []
        for line in f.inner where line.count >= 2 {
            let m = Self.project(line)
            for i in 0 ..< m.count - 1 {
                let a = m[i], c = m[i + 1]
                sg += [a.x, a.y, c.x, c.y, a.x, a.y, a.x, a.y, 0, 0]
            }
        }
        guard !rn.isEmpty, all.x < all.z else { return nil }
        unitIDs = ids; unitNames = names; unitParents = parents; entryUnit = eu
        points = pts; fans = fan; runs = rn; segs = sg
        boxes = bx; rings = rs; box = all
    }

    /// a ring or line in the map's units; one lying mostly past 180° east (the old files' 0 to 360) is brought round to
    /// its place west of the date line, as the world draws it
    static func project(_ ring: [SIMD2<Double>]) -> [SIMD2<Float>] {
        let mean = ring.reduce(0) { $0 + $1.x } / Double(max(1, ring.count))
        let shift: Double = mean > 180 ? -360 : mean < -180 ? 360 : 0
        return ring.map { EqualEarth.project(lon: $0.x + shift, lat: $0.y) }
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

    /// the entries of a set of regions (what the renderer fills for them)
    func entries(of units: Set<Int>) -> [Int] { entryUnit.indices.filter { units.contains(entryUnit[$0]) } }
}

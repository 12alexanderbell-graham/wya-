import Foundation
import simd

/// ONE PLACE'S TOWNS AS THE MAP DRAWS THEM (7.4): every town with a built-up shape as fans for the stencil, the biggest
/// first, so the towns a zoom shows are one run from the start; each size class's run, so its colour can come in across
/// its own zoom band; each town's point; each shape's box and rings for the finger. Built off the main thread.
nonisolated final class TownScene: @unchecked Sendable {
    let cc: String
    /// the towns, biggest first
    let towns: [Town]
    let index: [String: Int]
    /// the shapes' fan points and index; each town's run (nil: no shape)
    let points: [SIMD2<Float>]
    let fans: [UInt32]
    let runs: [(start: Int, count: Int)?]
    /// where each town is (map units)
    let at: [SIMD2<Float>]
    /// the size classes: each class's last town (exclusive) and the population it starts at
    static let classes: [Int] = [1_000_000, 300_000, 100_000, 30_000, 10_000, 3_000, 0]
    let classEnd: [Int]
    /// where each class's fans end in the index
    let classFanEnd: [Int]
    private let boxes: [SIMD4<Float>?]
    private let rings: [[[SIMD2<Float>]]]

    init(cc: String, towns raw: [Town], shapes: [UrbanFile.Shape]) {
        self.cc = cc
        let towns = raw.enumerated().sorted { a, b in a.element.people != b.element.people ? a.element.people > b.element.people : a.offset < b.offset }.map(\.element)
        self.towns = towns
        var ix: [String: Int] = [:]
        for (i, t) in towns.enumerated() where ix[t.id] == nil { ix[t.id] = i }
        index = ix
        var byKey: [String: UrbanFile.Shape] = [:]
        for s in shapes where byKey[s.key] == nil { byKey[s.key] = s }
        var pts: [SIMD2<Float>] = [], fan: [UInt32] = []
        var rn: [(Int, Int)?] = [], bx: [SIMD4<Float>?] = [], rs: [[[SIMD2<Float>]]] = []
        var ce: [Int] = [], cfe: [Int] = []
        var cls = 0
        for (i, t) in towns.enumerated() {
            while cls < Self.classes.count - 1 && t.people < Self.classes[cls] { ce.append(i); cfe.append(fan.count); cls += 1 }
            guard let s = byKey[t.id] else { rn.append(nil); bx.append(nil); rs.append([]); continue }
            let start = fan.count
            var b = SIMD4<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            var mine: [[SIMD2<Float>]] = []
            for ring in s.rings where ring.count >= 3 {
                let m = ring.map { EqualEarth.project(lon: $0.x, lat: $0.y) }
                let s0 = UInt32(pts.count)
                pts += m
                for k in 1 ..< m.count - 1 { fan += [s0, s0 + UInt32(k), s0 + UInt32(k + 1)] }
                for p in m { b = SIMD4(min(b.x, p.x), min(b.y, p.y), max(b.z, p.x), max(b.w, p.y)) }
                mine.append(m)
            }
            rn.append(fan.count > start ? (start, fan.count - start) : nil)
            bx.append(mine.isEmpty ? nil : b)
            rs.append(mine)
        }
        while ce.count < Self.classes.count { ce.append(towns.count); cfe.append(fan.count) }
        points = pts; fans = fan; runs = rn; boxes = bx; rings = rs
        classEnd = ce; classFanEnd = cfe
        at = towns.map { EqualEarth.project(lon: $0.lon, lat: $0.lat) }
    }

    /// the town under a map point: a shape holding it, else (shapeless towns shown as dots) the nearest dot within
    /// `reach`; only towns of the classes shown (`upTo` towns)
    func town(at p: SIMD2<Float>, reach: Float, upTo n: Int, dots: Bool) -> Int? {
        let n = min(n, towns.count)
        var best: (Int, Float)?
        for i in 0 ..< n {
            guard let b = boxes[i], p.x >= b.x, p.x <= b.z, p.y >= b.y, p.y <= b.w else { continue }
            var inside = false
            for r in rings[i] {
                var j = r.count - 1
                for k in 0 ..< r.count {
                    let a = r[k], c = r[j]
                    if (a.y > p.y) != (c.y > p.y), p.x < (c.x - a.x) * (p.y - a.y) / (c.y - a.y) + a.x { inside.toggle() }
                    j = k
                }
            }
            if inside {
                let area = (b.z - b.x) * (b.w - b.y)
                if best == nil || area < best!.1 { best = (i, area) }
            }
        }
        if let best { return best.0 }
        guard dots else { return nil }
        var near: (Int, Float)?
        for i in 0 ..< n where dots || runs[i] == nil {
            let d = simd_distance(at[i], p)
            if d <= reach, near == nil || d < near!.1 { near = (i, d) }
        }
        return near?.0
    }
}

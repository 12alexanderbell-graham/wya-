import Foundation
import simd

/// A SET'S PLACES AS THEIR OWN SHAPES (9 Nov: Places is the map and Regions again with real named things; an area
/// thing, a sea, a mountain range, a lake, an island, a desert, has its boundary and fills when it is yours, as a
/// country does). The shapes come with the set (`native/collections/shapes-<id>-1.wyau`, the towns' shape format, each
/// keyed by its place's id); built as fans for the stencil the way a country's towns are (TownScene), with each
/// shape's box and rings for the finger. Built off the main thread.
///
/// On the map an area thing that is not yours is only its name, as on any map (a sea has no outline); under a finger
/// its whole shape darkens; yours is filled lime, wished blue.
nonisolated final class SetScene: @unchecked Sendable {
    /// the set's id ("seas")
    let id: String
    /// its places are water (they darken as water does under a finger)
    var water: Bool { ["oceans", "seas", "lakes", "famouslakes", "rivers"].contains(id) }
    /// its places that are not yours are not tinted: a sea (its limits are lines across open water), a lake and an
    /// island (the map draws them already); each is its mark until it is wide enough on screen for its name
    var untinted: Bool { water || id == "famousislands" }
    /// its places have a drawn boundary (a national park has a border, an outline)
    var outlined: Bool { id == "parks" }
    /// the boundaries as the map's line segments (10 floats each: the two ends, the same again for the lines' morph,
    /// how far along its ring, 0), and each place's run in them; only an outlined set has any
    let segs: [Float]
    let segRuns: [String: (start: Int, count: Int)]
    /// each shaped place's run in the fans, by its id
    let runs: [String: (start: Int, count: Int)]
    let points: [SIMD2<Float>]
    let fans: [UInt32]
    private let boxes: [String: SIMD4<Float>]
    private let rings: [String: [[SIMD2<Float>]]]
    /// the shaped places, the biggest first (a finger inside two takes the smaller, so it is asked last to first)
    private let order: [String]

    init(id: String, shapes: [UrbanFile.Shape]) {
        self.id = id
        var pts: [SIMD2<Float>] = [], fan: [UInt32] = []
        var rn: [String: (Int, Int)] = [:], bx: [String: SIMD4<Float>] = [:], rs: [String: [[SIMD2<Float>]]] = [:]
        var ord: [String] = []
        let lined = id == "parks"
        var sg: [Float] = [], sr: [String: (Int, Int)] = [:]
        for s in shapes where rn[s.key] == nil {
            let start = fan.count
            let seg0 = sg.count / 10
            var b = SIMD4<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            var mine: [[SIMD2<Float>]] = []
            for ring in s.rings where ring.count >= 3 {
                let m = ring.map { EqualEarth.project(lon: $0.x, lat: $0.y) }
                let s0 = UInt32(pts.count)
                pts += m
                for k in 1 ..< m.count - 1 { fan += [s0, s0 + UInt32(k), s0 + UInt32(k + 1)] }
                for p in m { b = SIMD4(min(b.x, p.x), min(b.y, p.y), max(b.z, p.x), max(b.w, p.y)) }
                mine.append(m)
                if lined {
                    var along: Float = 0
                    for k in m.indices {
                        let a = m[k], c = m[(k + 1) % m.count]
                        sg += [a.x, a.y, c.x, c.y, a.x, a.y, c.x, c.y, along, 0]
                        along += simd_length(c - a)
                    }
                }
            }
            guard fan.count > start else { continue }
            rn[s.key] = (start, fan.count - start)
            if lined { sr[s.key] = (seg0, sg.count / 10 - seg0) }
            bx[s.key] = b
            rs[s.key] = mine
            ord.append(s.key)
        }
        points = pts; fans = fan; runs = rn; boxes = bx; rings = rs
        segs = sg; segRuns = sr
        order = ord.sorted { a, b in
            let x = bx[a]!, y = bx[b]!
            return (x.z - x.x) * (x.w - x.y) > (y.z - y.x) * (y.w - y.y)
        }
    }

    /// a place's box on the map
    func box(_ id: String) -> SIMD4<Float>? { boxes[id] }
    /// how far across its shape is (the longer side of its box, map units)
    func across(_ id: String) -> Float? { boxes[id].map { max($0.z - $0.x, $0.w - $0.y) } }

    /// the place whose shape holds a map point (the smallest of them: a sea inside an ocean's box)
    /// (`among`: only the places of the list that is up answer, a set cut down to its seas has no ocean under a finger)
    func hit(at p: SIMD2<Float>, among: Set<String>? = nil) -> String? {
        for id in order.reversed() {
            if let among, !among.contains(id) { continue }
            guard let b = boxes[id], p.x >= b.x, p.x <= b.z, p.y >= b.y, p.y <= b.w, let rs = rings[id] else { continue }
            var inside = false
            for r in rs {
                var j = r.count - 1
                for k in 0 ..< r.count {
                    let a = r[k], c = r[j]
                    if (a.y > p.y) != (c.y > p.y), p.x < (c.x - a.x) * (p.y - a.y) / (c.y - a.y) + a.x { inside.toggle() }
                    j = k
                }
            }
            if inside { return id }
        }
        return nil
    }
}

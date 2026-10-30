#if DEBUG
import Foundation
import simd

/// TEST ONLY, Step 1f: every piece of every place is pressed at a point inside it, at the world level, at the 500 m
/// tiles and at the 100 m tiles, through the same calls a finger makes (the diamonds first, then the smallest piece
/// within the fingertip). Every press that picks another place is written to snaps/measure.log ("hittest"), with the
/// totals.
@MainActor
enum HitTest {
    static func run(map: MapController) {
        guard let w = map.world, let det = map.details else { FrameStats.log("wya hittest: no map yet"); return }
        // a point inside each piece: its ring's middle if that is inside, else the first of a 9 x 9 grid over it that is
        var targets: [(place: Int, p: SIMD2<Float>, size: Float)] = []
        var noPoint = 0
        for u in 0 ..< w.unitRings.count {
            let i = w.unitOwner[u]
            guard i >= 0, !w.places[i].junk else { continue }
            for ri in w.unitRings[u] {
                let r = w.rings[ri]
                guard r.count >= 3 else { continue }
                func inRing(_ q: SIMD2<Float>) -> Bool {
                    var c = false
                    var jp = r.start + r.count - 1
                    for j in r.start ..< r.start + r.count {
                        let a = w.points[j], e = w.points[jp]
                        if (a.y > q.y) != (e.y > q.y), q.x < (e.x - a.x) * (q.y - a.y) / (e.y - a.y) + a.x { c.toggle() }
                        jp = j
                    }
                    return c
                }
                let b = r.box
                // the deepest of the ring's middle and a 9 x 9 grid over it (the point farthest from its edges), so the
                // press is on the piece and not on a border another level draws a little differently
                var found: SIMD2<Float>?
                var depth: Float = -1
                var c = SIMD2<Float>(0, 0)
                for j in r.start ..< r.start + r.count { c += w.points[j] }
                c /= Float(r.count)
                var cands = [c]
                for gy in 1 ..< 10 { for gx in 1 ..< 10 {
                    cands.append(SIMD2(b.x + (b.z - b.x) * Float(gx) / 10, b.y + (b.w - b.y) * Float(gy) / 10))
                } }
                // a hole's ring (an enclave's edge inside the place) is not a piece of it: most of its inside is
                // another place
                let inside = cands.filter(inRing)
                let mine = inside.filter { w.place(at: $0) == i }
                if !inside.isEmpty && mine.count * 2 < inside.count { continue }
                for q in mine {
                    var dmin = Float.greatestFiniteMagnitude
                    var jp = r.start + r.count - 1
                    for j in r.start ..< r.start + r.count {
                        let a = w.points[jp], e = w.points[j], ae = e - a
                        let l2 = simd_length_squared(ae)
                        let tt = l2 > 0 ? min(1, max(0, simd_dot(q - a, ae) / l2)) : 0
                        dmin = min(dmin, simd_length(q - (a + tt * ae)))
                        jp = j
                    }
                    if dmin > depth { depth = dmin; found = q }
                }
                if let f = found { targets.append((i, f, max(b.z - b.x, b.w - b.y))) } else { noPoint += 1 }
            }
        }
        let c0 = map.c, k0 = map.k
        defer { map.c = c0; map.k = k0 }
        // the three levels at a zoom each: the world at home and closer; the 500 m tiles about 1,000 km across; the
        // 100 m tiles about 150 km across (a map unit is about 40 km)
        let w0 = map.worldKMin
        let levels: [(name: String, k: Double, tiles: String?)] = [("world home", w0, nil), ("world x2.5", w0 * 2.5, nil),
                                                                   ("500 m", 17.6, "500m"), ("100 m", 117, "100m")]
        let center = CGPoint(x: map.view.width / 2, y: map.view.height / 2)
        for lv in levels {
            var wrong = 0, tested = 0
            var lines: [String] = []
            for t in targets {
                map.c = SIMD2(Double(t.p.x), Double(t.p.y)); map.k = lv.k
                let reach = Float(10 / lv.k), tiny = Float(14 / lv.k)
                // the finger's rule as MapController.hit has it, on this level's shapes
                var under: Int?
                if let lname = lv.tiles {
                    guard let tile = det.testTile(at: t.p, level: lname) else { continue }
                    under = DetailMaps.place(in: [tile], at: t.p, reach: reach, tiny: tiny, small: { w.places[$0].tiny })
                } else {
                    under = w.place(at: t.p, reach: reach, tiny: tiny)
                }
                var got = under
                if let d = map.diamond(at: center), d.d <= 8 || under == nil || under == d.place || w.places[under!].tiny { got = d.place }
                tested += 1
                if got != t.place {
                    wrong += 1
                    if lines.count < 400 {
                        let lat = EqualEarth.lat(y: Double(t.p.y)), lon = EqualEarth.lon(x: Double(t.p.x), lat: lat)
                        lines.append(String(format: "  %@ (piece %.1f km, at %.3f %.3f) -> %@", w.places[t.place].id, Double(t.size) * 40,
                                            lon, lat, got.map { w.places[$0].id } ?? "nothing"))
                    }
                }
            }
            FrameStats.log("wya hittest \(lv.name): \(tested - wrong) of \(tested) pieces picked themselves (no inside point: \(noPoint))")
            for l in lines { FrameStats.log(l) }
        }
    }
}
#endif

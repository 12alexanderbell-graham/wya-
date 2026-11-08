import SwiftUI
import simd

/// A MAP'S OWN SHAPE (Places' shelf, 9 Nov): the outline of what a map shows, from the map's own rings (the same
/// geometry the map draws), fitted into a unit box with its proportions kept. Built once per map and kept; the rings are
/// thinned to about 1,500 points so the world's outline draws as fast as a country's.
@MainActor
enum MapShapes {
    struct Shape { let path: Path; let aspect: CGFloat }
    private static var kept: [String: Shape] = [:]

    /// the places' land (nil: every place, the world)
    static func land(_ key: String, places: [Int]?, world w: World) -> Shape? {
        if let s = kept[key] { return s }
        let wanted = places.map(Set.init)
        var rings: [World.Ring] = []
        for r in w.rings where r.unit >= 0 && r.unit < w.unitOwner.count {
            let owner = w.unitOwner[r.unit]
            guard owner >= 0, owner < w.places.count, !w.places[owner].junk else { continue }
            if let wanted { if !wanted.contains(owner) { continue } } else if w.places[owner].id == "aq" { continue }
            rings.append(r)
        }
        guard !rings.isEmpty else { return nil }
        // the box of what is drawn (a far-flung island counts: it is part of the place)
        var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude), hi = -lo
        for r in rings { lo = simd_min(lo, SIMD2(r.box.x, r.box.y)); hi = simd_max(hi, SIMD2(r.box.z, r.box.w)) }
        let size = hi - lo
        guard size.x > 0, size.y > 0 else { return nil }
        let total = rings.reduce(0) { $0 + $1.count }
        let step = max(1, total / 1500)
        // a ring too small to see at 64 pt is left out (an islet is a speck of nothing)
        let least = max(size.x, size.y) / 140
        let s = max(size.x, size.y)
        var p = Path()
        for r in rings {
            guard max(r.box.z - r.box.x, r.box.w - r.box.y) >= least || rings.count < 4 else { continue }
            var first = true
            var i = r.start
            let end = r.start + r.count
            while i < end {
                let q = (w.points[i] - lo) / s
                let pt = CGPoint(x: CGFloat(q.x), y: CGFloat(q.y))
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                i += min(step, max(1, (end - i) / 3))
            }
            p.closeSubpath()
        }
        let shape = Shape(path: p, aspect: CGFloat(size.x / size.y))
        kept[key] = shape
        return shape
    }

    /// a collection's stops as points in their own box
    static func points(_ key: String, _ at: [SIMD2<Float>]) -> (pts: [CGPoint], aspect: CGFloat)? {
        guard !at.isEmpty else { return nil }
        var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude), hi = -lo
        for a in at { lo = simd_min(lo, a); hi = simd_max(hi, a) }
        let size = simd_max(hi - lo, SIMD2(1, 1))
        let s = max(size.x, size.y)
        return (at.map { a in let q = (a - lo) / s; return CGPoint(x: CGFloat(q.x), y: CGFloat(q.y)) }, CGFloat(size.x / size.y))
    }
}

/// a unit-box shape drawn into its frame, centred, proportions kept
struct FittedShape: SwiftUI.Shape {
    let path: Path
    let aspect: CGFloat
    func path(in rect: CGRect) -> Path {
        let w = min(rect.width, rect.height * aspect), h = w / max(aspect, 0.001)
        let x = rect.midX - w / 2, y = rect.midY - h / 2
        // the unit box's long side is 1: scale by the drawn box's long side
        let k = max(w, h)
        return path.applying(CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: x, ty: y))
    }
}

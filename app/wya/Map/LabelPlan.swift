import UIKit
import simd

/// THE LABEL PLAN (31 Oct: names appeared and vanished as the zoom changed): every name the
/// map can show gets, once, the zoom from which it shows, worked out so it never overlaps a name that came before it.
/// On screen a name is up exactly when the zoom is past its own zoom, so zooming in only ever adds names and zooming out
/// takes them away in the reverse order; panning never changes which are up (the old way picked the 8 best in view every
/// frame, so names swapped as you zoomed and moved).
///
/// How a name's zoom is found: names in the order they first can show (their own threshold, then rank). Two labels of
/// fixed screen size pinned to map points stop overlapping for good past a zoom of their own (`separation`), because
/// zooming in only moves their points apart. A name's zoom is its threshold, or past every earlier name's separation
/// from it where that earlier name is up before they separate. So a name never has to leave once it is up.
struct LabelPlan {
    struct Item {
        /// the item's id ("t:fr#12" for a town, "h:Q243" for a thing)
        let id: String
        /// its point in map units
        let at: SIMD2<Double>
        /// its label's box relative to the point, in screen points (a town's name centred on it; a thing's mark and
        /// name to its right)
        let box: CGRect
        /// the zoom from which it may show at all (its own rule: a town's shape 12 pt across, a thing's fame band)
        let threshold: Double
        /// higher first among names with the same threshold
        let rank: Double
    }
    /// each item's zoom, by id
    private(set) var zoom: [String: Double] = [:]
    /// the items by their zoom, lowest first (a frame stops at the first one past the camera's zoom)
    private(set) var ordered: [(id: String, zoom: Double)] = []

    /// `gap`: the room kept between two names, in points
    init(_ items: [Item], gap: CGFloat = 4) {
        let order = items.indices.sorted { a, b in
            items[a].threshold != items[b].threshold ? items[a].threshold < items[b].threshold : items[a].rank > items[b].rank
        }
        guard let lowest = order.first.map({ max(1e-9, items[$0].threshold) }) else { return }
        // a grid in map units: two names can only meet past the lowest threshold within this reach of each other
        let maxW = items.map { Double($0.box.width) }.max() ?? 0, maxH = items.map { Double($0.box.height) }.max() ?? 0
        let maxOff = items.map { Double(max(abs($0.box.minX), abs($0.box.maxX), abs($0.box.minY), abs($0.box.maxY))) }.max() ?? 0
        let reach = (Swift.max(maxW, maxH) + 2 * maxOff + Double(gap)) / lowest
        let cell = Swift.max(reach, 1e-9)
        var grid: [SIMD2<Int>: [Int]] = [:]
        var placed = [Double](repeating: .infinity, count: items.count)
        for b in order {
            let B = items[b]
            var z = B.threshold
            let c = SIMD2(Int((B.at.x / cell).rounded(.down)), Int((B.at.y / cell).rounded(.down)))
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    for a in grid[c &+ SIMD2(dx, dy)] ?? [] {
                        let s = Self.separation(items[a], B, gap: Double(gap))
                        // only an earlier name that is up before they separate keeps this one back
                        if s > placed[a], s > z { z = s }
                    }
                }
            }
            placed[b] = z
            grid[c, default: []].append(b)
        }
        for i in items.indices { zoom[items[i].id] = placed[i] }
        ordered = items.indices.map { (items[$0].id, placed[$0]) }.sorted { $0.zoom < $1.zoom }
    }

    /// the zoom past which two labels never overlap again (0 when they never overlap)
    static func separation(_ A: Item, _ B: Item, gap g: Double) -> Double {
        let d = B.at - A.at
        // on one axis: B's box minus A's box (screen) is d * k + e; they overlap there while -(B's size + g) < d*k + e <
        // A's size + g
        func axisEnd(_ d: Double, _ e: Double, _ lo: Double, _ hi: Double) -> Double {
            // overlap while lo < d*k + e < hi; the zoom past which d*k + e stays outside for good
            if abs(d) < 1e-12 { return (lo < e && e < hi) ? .infinity : 0 }
            return d > 0 ? Swift.max(0, (hi - e) / d) : Swift.max(0, (lo - e) / d)
        }
        let ex = Double(B.box.minX - A.box.minX), ey = Double(B.box.minY - A.box.minY)
        let x = axisEnd(d.x, ex, -(Double(B.box.width) + g), Double(A.box.width) + g)
        let y = axisEnd(d.y, ey, -(Double(B.box.height) + g), Double(A.box.height) + g)
        return Swift.min(x, y)
    }
}

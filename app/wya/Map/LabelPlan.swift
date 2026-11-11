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
        /// other boxes it may take instead (a mark's name to its left, under it, over it): the one that lets it show
        /// soonest is taken, the first on a tie
        var alts: [CGRect] = []
    }
    /// which box each item took (0: its own, n: its nth other), by id
    private(set) var choice: [String: Int] = [:]
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
        let every = items.flatMap { [$0.box] + $0.alts }
        let maxW = every.map { Double($0.width) }.max() ?? 0, maxH = every.map { Double($0.height) }.max() ?? 0
        let maxOff = every.map { Double(max(abs($0.minX), abs($0.maxX), abs($0.minY), abs($0.maxY))) }.max() ?? 0
        let reach = (Swift.max(maxW, maxH) + 2 * maxOff + Double(gap)) / lowest
        let cell = Swift.max(reach, 1e-9)
        var grid: [SIMD2<Int>: [Int]] = [:]
        var placed = [Double](repeating: .infinity, count: items.count)
        var boxes = items.map(\.box)
        for b in order {
            let B = items[b]
            let c = SIMD2(Int((B.at.x / cell).rounded(.down)), Int((B.at.y / cell).rounded(.down)))
            var near: [Int] = []
            for dx in -1 ... 1 { for dy in -1 ... 1 { near += grid[c &+ SIMD2(dx, dy)] ?? [] } }
            var best = Double.infinity, pick = 0
            for (n, box) in ([B.box] + B.alts).enumerated() {
                var z = B.threshold
                for a in near {
                    let s = Self.separation(items[a].at, boxes[a], B.at, box, gap: Double(gap))
                    // only an earlier name that is up before they separate keeps this one back
                    if s > placed[a], s > z { z = s }
                }
                if z < best { best = z; pick = n }
                if z <= B.threshold { break }
            }
            placed[b] = best
            boxes[b] = pick == 0 ? B.box : B.alts[pick - 1]
            if pick != 0 { choice[B.id] = pick }
            grid[c, default: []].append(b)
        }
        for i in items.indices { zoom[items[i].id] = placed[i] }
        ordered = items.indices.map { (items[$0].id, placed[$0]) }.sorted { $0.zoom < $1.zoom }
    }

    /// the zoom past which two labels never overlap again (0 when they never overlap)
    static func separation(_ A: Item, _ B: Item, gap g: Double) -> Double { separation(A.at, A.box, B.at, B.box, gap: g) }
    static func separation(_ aAt: SIMD2<Double>, _ aBox: CGRect, _ bAt: SIMD2<Double>, _ bBox: CGRect, gap g: Double) -> Double {
        let d = bAt - aAt
        // on one axis: B's box minus A's box (screen) is d * k + e; they overlap there while -(B's size + g) < d*k + e <
        // A's size + g
        func axisEnd(_ d: Double, _ e: Double, _ lo: Double, _ hi: Double) -> Double {
            // overlap while lo < d*k + e < hi; the zoom past which d*k + e stays outside for good
            if abs(d) < 1e-12 { return (lo < e && e < hi) ? .infinity : 0 }
            return d > 0 ? Swift.max(0, (hi - e) / d) : Swift.max(0, (lo - e) / d)
        }
        let ex = Double(bBox.minX - aBox.minX), ey = Double(bBox.minY - aBox.minY)
        let x = axisEnd(d.x, ex, -(Double(bBox.width) + g), Double(aBox.width) + g)
        let y = axisEnd(d.y, ey, -(Double(bBox.height) + g), Double(aBox.height) + g)
        return Swift.min(x, y)
    }
}

import UIKit
import simd

// HISTORY LINES (Part 13): one journey you can read from where it started to where it ended, never a web and no dots
// (23 Oct 15:58: "they were just a big web of the same colored lines. Like, no one knows where you started and
// ended"). Your stops in date order, each leg bowed a tenth of its length to the right of travel (a leg flown twice
// bows to the other side the second time), 1.5 pt at the start widening evenly to 2.5 pt at the end in screen points,
// black at the start through our blue to white at the end (Q13.1: "I guess black to blue to white"), with a 0.5 pt
// black 50% edge where it crosses land so the white end reads on white and lime. A small glass capsule names the start
// and the end ("Lisbon · Mar 2024"), beside the line, never on it.

/// THE JOURNEY: the stops of one mode in range, and the legs between them in map units (worked out once per range)
struct HistoryTrack {
    struct Stop { let key: PlaceKey; let place: Int; let at: SIMD2<Double>; let from: LocalDay; let name: String }
    let stops: [Stop]
    /// every leg as points in map units, the whole journey's segments in order with whether each crosses land
    let points: [SIMD2<Double>]
    let land: [Bool]
    /// the segment index each leg starts at (a leg's capsule and its tap)
    let legStart: [Int]

    /// Countries (13.3): every dated visit and lived span of your stamped countries and territories, by arrival day,
    /// one stop per visit; on a continent, its stops only. Range: the last 12 months (no home yet to find the latest
    /// trip from, 13.4), all time when those are empty.
    @MainActor static func countries(world w: World, continent: String?, today: LocalDay = LocalDay(Date(), in: .current)) -> HistoryTrack? {
        let cal = MarkStore.shared.calendar
        let all = cal.spans.filter { ($0.kind == .visit || $0.kind == .lived) && $0.key.kind == .country && MarkStore.shared.state($0.key).stamped }
        let yearAgo = LocalDay(y: today.y - 1, m: today.m, d: min(today.d, 28))
        var spans = all.filter { $0.to >= yearAgo }
        if spans.isEmpty { spans = all }
        var stops: [Stop] = []
        for e in spans {
            guard let i = w.placeIndex[e.key.id] ?? w.placeIndex[e.key.id.uppercased()] ?? w.placeIndex[e.key.id.lowercased()] else { continue }
            if let c = continent, !w.inCont(i, c) { continue }
            // two stops in the same place one after the other make no leg: the line carries on from there
            if stops.last?.place == i { continue }
            let p = w.places[i]
            stops.append(Stop(key: e.key, place: i, at: SIMD2(p.c[0], p.c[1]), from: e.from, name: p.n))
        }
        guard !stops.isEmpty else { return nil }
        return HistoryTrack(stops: stops, world: w)
    }

    @MainActor init(stops: [Stop], world w: World) {
        self.stops = stops
        var pts: [SIMD2<Double>] = []
        var starts: [Int] = []
        var seen: [String: Int] = [:]
        let n = 24
        for j in 0 ..< max(0, stops.count - 1) {
            let a = stops[j].at, b = stops[j + 1].at
            let d = b - a, len = simd_length(d)
            starts.append(max(0, pts.count - 1))
            guard len > 1e-6 else { continue }
            // the same two places again: the other side (so two trips never draw on one another)
            let pair = [stops[j].place, stops[j + 1].place].sorted().map(String.init).joined(separator: "-")
            let again = seen[pair, default: 0]
            seen[pair] = again + 1
            let side: Double = again % 2 == 0 ? 1 : -1
            // right of travel on the map (y runs down): (-dy, dx); the bow a tenth of the length at the middle
            let normal = SIMD2(-d.y, d.x) / len * side
            let ctrl = (a + b) / 2 + normal * (len * 0.2)
            for s in 0 ... n {
                if s == 0 && !pts.isEmpty { continue }
                let t = Double(s) / Double(n)
                let u = 1 - t
                pts.append(u * u * a + 2 * u * t * ctrl + t * t * b)
            }
        }
        if pts.isEmpty, let only = stops.first { pts = [only.at] }
        points = pts
        legStart = starts
        // land under each segment's middle (the edge only there); a long journey skips the look-ups
        if pts.count > 1, pts.count < 1600 {
            land = (0 ..< pts.count - 1).map { i in
                let m = (pts[i] + pts[i + 1]) / 2
                return w.place(at: SIMD2(Float(m.x), Float(m.y))) != nil
            }
        } else {
            land = Array(repeating: true, count: max(0, pts.count - 1))
        }
    }

    /// the line's colour at a share of its length: black, through our blue, to white
    static func colour(_ t: Double) -> UIColor {
        let blue = SIMD3<Double>(0x78 / 255.0, 0xae / 255.0, 0xf8 / 255.0)
        let v = t < 0.5 ? blue * (t / 0.5) : blue + (SIMD3<Double>(1, 1, 1) - blue) * ((t - 0.5) / 0.5)
        return UIColor(red: v.x, green: v.y, blue: v.z, alpha: 1)
    }
}

/// THE LINE ON THE MAP, drawn for each frame's camera (over the map, under the chrome; it takes no touch)
final class HistoryLineView: UIView {
    private let startCap = HistoryCapsule()
    private let endCap = HistoryCapsule()
    private var track: HistoryTrack?
    private var shown: CGFloat = 0
    private weak var map: MapController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        addSubview(startCap); addSubview(endCap)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ m: MapController) {
        map = m
        let t = m.historyTrack
        if t == nil && track == nil { if !isHidden { isHidden = true }; return }
        isHidden = false
        if let t { track = t }
        shown = m.historyShown
        guard let track else { return }
        // the capsules ride the ends: the start one is up from the beginning, the end one once the head arrives (A13.2)
        if let first = track.stops.first {
            let p0 = m.screenPoint(track.points.first ?? first.at)
            let dir = track.points.count > 1 ? m.screenPoint(track.points[1]) : CGPoint(x: p0.x + 1, y: p0.y)
            startCap.set(Self.words(first), near: p0, awayFrom: dir, visible: shown > 0.001 && m.historyTrack != nil)
        }
        if let last = track.stops.last, track.stops.count > 1 {
            let pn = m.screenPoint(track.points.last ?? last.at)
            let prev = track.points.count > 1 ? m.screenPoint(track.points[track.points.count - 2]) : CGPoint(x: pn.x - 1, y: pn.y)
            endCap.set(Self.words(last), near: pn, awayFrom: prev, visible: shown > 0.999 && m.historyTrack != nil)
        } else { endCap.set("", near: .zero, awayFrom: .zero, visible: false) }
        if m.historyTrack == nil && shown <= 0.001 { self.track = nil; isHidden = true }
        setNeedsDisplay()
    }

    static func words(_ s: HistoryTrack.Stop) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "MMM yyyy"
        var c = DateComponents(); c.year = s.from.y; c.month = s.from.m; c.day = s.from.d
        let d = Calendar(identifier: .gregorian).date(from: c).map { f.string(from: $0) } ?? ""
        return "\(s.name) · \(d)"
    }

    override func draw(_ rect: CGRect) {
        guard let track, let m = map, track.points.count > 1, let g = UIGraphicsGetCurrentContext() else { return }
        let segs = track.points.count - 1
        // drawn along its length to the share shown (A13.1, A13.3): whole segments, then the part of the next
        let upto = Double(shown) * Double(segs)
        let scr = track.points.map { m.screenPoint($0) }
        g.setLineCap(.round); g.setLineJoin(.round)
        func seg(_ i: Int) -> (CGPoint, CGPoint)? {
            guard Double(i) < upto else { return nil }
            let a = scr[i]
            var b = scr[i + 1]
            let part = min(1, upto - Double(i))
            if part < 1 { b = CGPoint(x: a.x + (b.x - a.x) * part, y: a.y + (b.y - a.y) * part) }
            return (a, b)
        }
        // the land edge first (0.5 pt black 50% each side), then the line itself over it
        for i in 0 ..< segs where track.land[i] {
            guard let (a, b) = seg(i) else { break }
            let t = Double(i) / Double(segs)
            g.setStrokeColor(UIColor.black.withAlphaComponent(0.5).cgColor)
            g.setLineWidth(1.5 + t + 1)
            g.move(to: a); g.addLine(to: b); g.strokePath()
        }
        for i in 0 ..< segs {
            guard let (a, b) = seg(i) else { break }
            let t = Double(i) / Double(segs)
            g.setStrokeColor(HistoryTrack.colour(t).cgColor)
            g.setLineWidth(1.5 + t)
            g.move(to: a); g.addLine(to: b); g.strokePath()
        }
    }
}

/// A START OR END CAPSULE: 13 pt words in a 28 pt clear glass capsule, 8 pt beside the line's end on the side away from
/// the line; it grows from the stop's point and goes back into it (A13.2, simplified to one grow about the point)
final class HistoryCapsule: UIView {
    private let glass: UIVisualEffectView
    private let label = UILabel()
    private var showing = false

    init() {
        glass = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        glass.layer.cornerRadius = 14
        glass.clipsToBounds = true
        addSubview(glass)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .black
        glass.contentView.addSubview(label)
        alpha = 1
        transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ words: String, near p: CGPoint, awayFrom q: CGPoint, visible: Bool) {
        if label.text != words { label.text = words; label.sizeToFit() }
        let w = label.bounds.width + 20, h: CGFloat = 28
        // the side away from the line: from the line's next point back through the end, 8 pt past the capsule's half
        var dx = p.x - q.x, dy = p.y - q.y
        let len = max(0.001, hypot(dx, dy)); dx /= len; dy /= len
        let reach = 8 + abs(dx) * w / 2 + abs(dy) * h / 2
        var centre = CGPoint(x: p.x + dx * reach, y: p.y + dy * reach)
        // never off the screen (a start on the map's edge, Portugal): kept 8 pt inside it
        if let sv = superview?.bounds, sv.width > w + 16 {
            centre.x = min(sv.maxX - w / 2 - 8, max(sv.minX + w / 2 + 8, centre.x))
            centre.y = min(sv.maxY - h / 2 - 8, max(sv.minY + h / 2 + 8, centre.y))
        }
        bounds = CGRect(x: 0, y: 0, width: w, height: h)
        glass.frame = bounds
        label.frame = CGRect(x: 10, y: (h - label.bounds.height) / 2, width: label.bounds.width, height: label.bounds.height)
        if visible != showing {
            showing = visible
            // grows from the stop's point (its anchor at the point's side) and goes back into it
            UIView.animate(springDuration: 0.42, bounce: 0) {
                self.transform = visible ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
            }
        }
        center = centre
    }
}

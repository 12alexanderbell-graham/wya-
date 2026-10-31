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
    struct Stop { let key: PlaceKey; let place: Int; let at: SIMD2<Double>; let from: LocalDay; let name: String; let ll: SIMD2<Double> }
    let stops: [Stop]
    /// every leg as points in map units, the whole journey's segments in order with whether each crosses land
    let points: [SIMD2<Double>]
    let land: [Bool]
    /// the segment index each leg starts at (a leg's capsule and its tap)
    let legStart: [Int]

    /// Countries (13.3): every dated visit and lived span of your stamped countries and territories, by arrival day,
    /// one stop per visit; on a continent, its stops only. All time (the range picks from these).
    @MainActor static func countryStops(world w: World, continent: String?) -> [Stop] {
        let cal = MarkStore.shared.calendar
        let all = cal.spans.filter { ($0.kind == .visit || $0.kind == .lived) && $0.key.kind == .country && MarkStore.shared.state($0.key).stamped }
        var stops: [Stop] = []
        for e in all {
            guard let i = w.placeIndex[e.key.id] ?? w.placeIndex[e.key.id.uppercased()] ?? w.placeIndex[e.key.id.lowercased()] else { continue }
            if let c = continent, !w.inCont(i, c) { continue }
            let p = w.places[i]
            stops.append(Stop(key: e.key, place: i, at: SIMD2(p.c[0], p.c[1]), from: e.from, name: p.n,
                              ll: SIMD2(p.ll.first ?? 0, p.ll.count > 1 ? p.ll[1] : 0)))
        }
        return stops
    }
    /// the stops in a range of days, two in the same place one after the other made one (the line carries on from there)
    static func within(_ all: [Stop], _ lo: LocalDay, _ hi: LocalDay) -> [Stop] {
        var out: [Stop] = []
        for s in all where lo <= s.from && s.from <= hi {
            if out.last?.place == s.place { continue }
            out.append(s)
        }
        return out
    }
    /// the default range (13.4): the latest trip needs a home (Profile, not built), so the last 12 months; all time when
    /// those are empty
    static func defaultRange(_ all: [Stop], today: LocalDay) -> (LocalDay, LocalDay)? {
        guard let first = all.first?.from, let last = all.last?.from else { return nil }
        let yearAgo = LocalDay(y: today.y - 1, m: today.m, d: min(today.d, 28))
        if all.contains(where: { $0.from >= yearAgo }) { return (max(first, yearAgo), max(last, today)) }
        return (first, max(last, today))
    }
    /// the journey's length, along the great circles between the stops (km)
    var km: Int {
        var d = 0.0
        for j in 0 ..< max(0, stops.count - 1) {
            let a = stops[j].ll * .pi / 180, b = stops[j + 1].ll * .pi / 180
            let h = pow(sin((b.y - a.y) / 2), 2) + cos(a.y) * cos(b.y) * pow(sin((b.x - a.x) / 2), 2)
            d += 2 * 6371 * asin(min(1, sqrt(h)))
        }
        return Int(d.rounded())
    }

    /// `land`: look up the land under each segment for the edge (skipped while a handle is dragged; done on release)
    @MainActor init(stops: [Stop], world w: World, land findLand: Bool = true) {
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
        if findLand, pts.count > 1, pts.count < 1600 {
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

/// THE LINE ON THE MAP: its paths made once in map units, in 40 pieces along its length (each its own colour and width
/// on the way from black to white, 1.5 to 2.5 pt), and only moved with the camera each frame (one transform, the widths
/// divided by the zoom so they stay in screen points); drawn along by each piece's stroke end. Over the map, under the
/// names; it takes no touch.
final class HistoryLineView: UIView {
    private let startCap = HistoryCapsule()
    private let endCap = HistoryCapsule()
    private var track: HistoryTrack?
    private var builtCount = -1
    private let holder = CALayer()
    private var pieces: [(line: CAShapeLayer, edge: CAShapeLayer?, t: CGFloat, from: CGFloat, to: CGFloat)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(holder)
        addSubview(startCap); addSubview(endCap)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(_ t: HistoryTrack) {
        holder.sublayers?.forEach { $0.removeFromSuperlayer() }
        pieces = []
        let pts = t.points
        let segs = pts.count - 1
        guard segs > 0 else { return }
        let n = min(40, segs)
        var edges: [CAShapeLayer] = []
        var lines: [CAShapeLayer] = []
        for j in 0 ..< n {
            let a = j * segs / n, b = (j + 1) * segs / n
            let line = CGMutablePath(), edge = CGMutablePath()
            line.move(to: CGPoint(x: pts[a].x, y: pts[a].y))
            for i in a ..< b { line.addLine(to: CGPoint(x: pts[i + 1].x, y: pts[i + 1].y)) }
            var anyLand = false
            for i in a ..< b where t.land[i] {
                anyLand = true
                edge.move(to: CGPoint(x: pts[i].x, y: pts[i].y)); edge.addLine(to: CGPoint(x: pts[i + 1].x, y: pts[i + 1].y))
            }
            let share = CGFloat(a) / CGFloat(segs)
            let l = CAShapeLayer()
            l.path = line; l.fillColor = nil; l.lineCap = .round; l.lineJoin = .round
            l.strokeColor = HistoryTrack.colour(Double(share)).cgColor
            var e: CAShapeLayer?
            if anyLand {
                let x = CAShapeLayer()
                x.path = edge; x.fillColor = nil; x.lineCap = .round; x.lineJoin = .round
                x.strokeColor = UIColor.black.withAlphaComponent(0.5).cgColor
                edges.append(x); e = x
            }
            lines.append(l)
            pieces.append((l, e, share, CGFloat(a) / CGFloat(segs), CGFloat(b) / CGFloat(segs)))
        }
        // every edge under every line, so a piece's edge never crosses over the line before it
        for e in edges { holder.addSublayer(e) }
        for l in lines { holder.addSublayer(l) }
    }

    func update(_ m: MapController) {
        let t = m.historyTrack
        if t == nil && track == nil { if !isHidden { isHidden = true }; return }
        isHidden = false
        if let t, t.points.count != builtCount || track == nil || t.stops.count != track!.stops.count || t.points.first != track!.points.first {
            track = t; builtCount = t.points.count; build(t)
        }
        let shown = m.historyShown
        guard let track else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // map units to screen: (m - c) * k + the view's middle
        let k = CGFloat(m.k)
        var tr = CATransform3DMakeTranslation(bounds.width / 2, bounds.height / 2, 0)
        tr = CATransform3DScale(tr, k, k, 1)
        tr = CATransform3DTranslate(tr, -CGFloat(m.c.x), -CGFloat(m.c.y), 0)
        holder.frame = bounds
        holder.bounds = bounds
        holder.anchorPoint = .zero
        holder.position = .zero
        holder.sublayerTransform = tr
        for p in pieces {
            let w = (1.5 + p.t) / k
            p.line.lineWidth = w
            p.edge?.lineWidth = w + 1 / k
            // drawn along: each piece from 0 to 1 as the shown share passes over it
            let end = max(0, min(1, (shown - p.from) / max(0.0001, p.to - p.from)))
            p.line.strokeEnd = end
            p.edge?.strokeEnd = end
            p.line.isHidden = end <= 0
            p.edge?.isHidden = end <= 0
        }
        CATransaction.commit()
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
        if m.historyTrack == nil && shown <= 0.001 { self.track = nil; builtCount = -1; isHidden = true }
    }

    static func words(_ s: HistoryTrack.Stop) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "MMM yyyy"
        var c = DateComponents(); c.year = s.from.y; c.month = s.from.m; c.day = s.from.d
        let d = Calendar(identifier: .gregorian).date(from: c).map { f.string(from: $0) } ?? ""
        return "\(s.name) · \(d)"
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

/// THE RANGE BAR (13.4): drawn on the water (no glass of its own), the water's width − 32 and 44 pt tall, its centre
/// at the water's top + 156. The track a 1 pt black 50% line from your first dated stop's year to today, a 4 pt black
/// line between the two handles (24 pt black circles, 44 pt to touch), the years under it (13 pt, black inside the
/// range, black 50% outside; every year while each has 30 pt, else every 2nd, 5th, 10th).
import SwiftUI

struct HistoryBar: View {
    let map: MapController
    let width: CGFloat
    @State private var lastEnd = 0

    var body: some View {
        if let info = map.historyInfo {
            let span = max(1, Double(info.last - info.first))
            let x = { (d: Int) -> CGFloat in 12 + CGFloat(Double(d - info.first) / span) * (width - 24) }
            let lo = x(info.lo), hi = x(info.hi)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Palette.ink.opacity(0.5)).frame(width: width - 24, height: 1).position(x: width / 2, y: 22)
                Rectangle().fill(Palette.ink).frame(width: max(0, hi - lo), height: 4).position(x: (lo + hi) / 2, y: 22)
                ForEach(years(info), id: \.self) { y in
                    let d = info.dayNumber(LocalDay(y: y, m: 1, d: 1))
                    let inside = d >= info.lo && d <= info.hi
                    Text(String(y)).font(.footnote).foregroundStyle(Palette.ink.opacity(inside ? 1 : 0.5))
                        .fixedSize().position(x: x(max(info.first, d)) + 14, y: 40)
                        .onTapGesture {
                            Feel.tap()
                            withAnimation(Motion.settle) {
                                map.setHistoryRange(lo: max(info.first, d), hi: min(info.last, info.dayNumber(LocalDay(y: y, m: 12, d: 31))))
                            }
                        }
                }
                handle(lo, info: info, isLow: true)
                handle(hi, info: info, isLow: false)
            }
            .frame(width: width, height: 44)
            .contextMenu {
                Button("Last 12 months") { map.setHistoryRange(lo: max(info.first, info.last - 365), hi: info.last) }
                Button("This year") { map.setHistoryRange(lo: max(info.first, info.dayNumber(LocalDay(y: info.lastYear, m: 1, d: 1))), hi: info.last) }
                Button("All time") { map.setHistoryRange(lo: info.first, hi: info.last) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Range")
            .accessibilityValue("\(info.text(info.lo)) to \(info.text(info.hi))")
        }
    }

    private func years(_ info: HistoryInfo) -> [Int] {
        let first = info.firstYear, last = info.lastYear
        let n = max(1, last - first + 1)
        let each = (width - 24) / CGFloat(n)
        let step = each >= 30 ? 1 : each * 2 >= 30 ? 2 : each * 5 >= 30 ? 5 : 10
        return stride(from: first, through: last, by: 1).filter { ($0 - first) % step == 0 }
    }

    private func handle(_ at: CGFloat, info: HistoryInfo, isLow: Bool) -> some View {
        Circle().fill(Palette.ink).frame(width: 24, height: 24)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(x: at, y: 22)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("historybar"))
                .onChanged { v in
                    let share = Double((v.location.x - 12) / (width - 24))
                    var d = info.first + Int((share * Double(info.last - info.first)).rounded())
                    let end = d <= info.first ? -1 : d >= info.last ? 1 : 0
                    if end != 0, end != lastEnd { Feel.tick() }
                    lastEnd = end
                    d = min(info.last, max(info.first, d))
                    if isLow { map.setHistoryRange(lo: min(d, info.hi), hi: info.hi, live: true) }
                    else { map.setHistoryRange(lo: info.lo, hi: max(d, info.lo), live: true) }
                }
                .onEnded { _ in lastEnd = 0; map.setHistoryRange(lo: info.lo, hi: info.hi) })
    }
}

/// what the caption and the bar show while history is up: the range (as day numbers from the first stop), the stops in
/// it and the length
struct HistoryInfo: Equatable {
    /// day numbers: days since 1 Jan 1970 (so a range is two integers)
    var first: Int, last: Int, lo: Int, hi: Int
    var count: Int
    var km: Int
    var firstYear: Int { Self.day(first).y }
    var lastYear: Int { Self.day(last).y }
    func dayNumber(_ d: LocalDay) -> Int { Self.number(d) }
    static func number(_ d: LocalDay) -> Int {
        var c = DateComponents(); c.year = d.y; c.month = d.m; c.day = d.d; c.timeZone = TimeZone(identifier: "UTC")
        let cal = Calendar(identifier: .gregorian)
        return Int(((cal.date(from: c) ?? Date()).timeIntervalSince1970 / 86400).rounded(.down))
    }
    static func day(_ n: Int) -> LocalDay { LocalDay(Date(timeIntervalSince1970: Double(n) * 86400 + 3600), in: TimeZone(identifier: "UTC")!) }
    func text(_ n: Int) -> String {
        let d = Self.day(n)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "MMM yyyy"
        var c = DateComponents(); c.year = d.y; c.month = d.m; c.day = d.d
        return Calendar(identifier: .gregorian).date(from: c).map { f.string(from: $0) } ?? ""
    }
    /// the caption's three lines (13.4): "Mar 2024 – Oct 2026", 14, "places · 9,840 km"
    var caption: (name: String, count: Int, tail: String) {
        let a = text(lo), b = text(hi)
        let nf = NumberFormatter(); nf.numberStyle = .decimal; nf.locale = Locale(identifier: "en_GB")
        let km = nf.string(from: NSNumber(value: km)) ?? "\(km)"
        return (a == b ? a : "\(a) – \(b)", count, (count == 1 ? "place" : "places") + (count > 1 ? " · \(km) km" : ""))
    }
}

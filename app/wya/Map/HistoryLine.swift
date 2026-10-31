import UIKit
import SwiftUI
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
    /// Places (13.3): the towns, things and your own places you stamped, by their dated visits; only the current map's
    /// places when a map is current (its countries). (The day you added an undated one is not in the calendar index
    /// yet, so undated ones are left out, as Countries' are.)
    @MainActor static func placeStops(world w: World, countries: Set<String>?) -> [Stop] {
        let cal = MarkStore.shared.calendar
        var stops: [Stop] = []
        for e in cal.spans where (e.kind == .visit || e.kind == .lived) && MarkStore.shared.state(e.key).stamped {
            var found: (cc: String, name: String, lon: Double, lat: Double)?
            switch e.key.kind {
            case .town:
                if let h = TownIndex.shared.hit(e.key.id) { found = (h.file, h.name, h.lon, h.lat) }
            case .thing:
                if let h = ThingIndex.shared.hit(e.key.id) { found = (h.file, h.name, h.lon, h.lat) }
                else if let it = CollectionStore.shared.item(e.key) {
                    // a collection's stop: its point is already in map units (its longitude and latitude worked back
                    // from it for the km: 31 Oct 06:25, a Formula 1 journey read "0 km")
                    if let i = w.placeIndex[it.cc] ?? w.placeIndex[it.cc.uppercased()], countries?.contains(it.cc.lowercased()) ?? true {
                        let at = SIMD2(Double(it.at.x), Double(it.at.y)), g = EqualEarth.unproject(at)
                        stops.append(Stop(key: e.key, place: i, at: at, from: e.from, name: it.name, ll: SIMD2(g.lon, g.lat)))
                    }
                    continue
                }
            case .yours:
                if let o = OwnPlaces.shared.place(e.key.id) { found = (o.cc, o.name, o.lon, o.lat) }
            default: break
            }
            guard let f = found, countries?.contains(f.cc.lowercased()) ?? true,
                  let i = w.placeIndex[f.cc] ?? w.placeIndex[f.cc.uppercased()] ?? w.placeIndex[f.cc.lowercased()] else { continue }
            let q = EqualEarth.project(lon: f.lon, lat: f.lat)
            stops.append(Stop(key: e.key, place: i, at: SIMD2(Double(q.x), Double(q.y)), from: e.from, name: f.name, ll: SIMD2(f.lon, f.lat)))
        }
        return stops
    }

    /// the stops in a range of days, two in the same place one after the other made one (the line carries on from there)
    static func within(_ all: [Stop], _ lo: LocalDay, _ hi: LocalDay) -> [Stop] {
        var out: [Stop] = []
        for s in all where lo <= s.from && s.from <= hi {
            if out.last?.key == s.key || (s.key.kind == .country && out.last?.place == s.place) { continue }
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
    /// a leg's capsule (A13.5) and the leg it names
    private let legCap = HistoryCapsule()
    private var legShown: Int?
    /// what a tap on the journey found (13.4's table): a start or end capsule, or a leg within 12 pt
    enum Hit { case start, end, leg(Int) }
    private var track: HistoryTrack?
    private var builtCount = -1
    private let holder = CALayer()
    private var pieces: [(line: CAShapeLayer, edge: CAShapeLayer?, t: CGFloat, from: CGFloat, to: CGFloat)] = []

    /// the one on screen (the test driver's `history tap`)
    nonisolated(unsafe) static weak var current: HistoryLineView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        Self.current = self
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(holder)
        addSubview(startCap); addSubview(endCap); addSubview(legCap)
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
        // the capsules ride the ends: the start one is up from the beginning, the end one once the head arrives (A13.2);
        // kept in the room between the head and the water, and away while their stop is off the screen (31 Oct 07:30: the
        // end's capsule stood over the head with Silverstone far off the top)
        let rr = m.layout.room(sheetTop: m.sheetTop > 0 ? m.sheetTop : m.layout.top(.quarter))
        let room = CGRect(x: 0, y: rr.lowerBound, width: bounds.width, height: rr.upperBound - rr.lowerBound)
        let seen = room.insetBy(dx: -24, dy: -24)
        // the leg's capsule beside its middle, on the side its bow goes (the chord's middle is inside the bow)
        // (first: a leg's capsule names both its ends, so a start or end capsule it would overlap steps back while it is
        // up; 31 Oct 07:45, at world zoom the three crossed one another)
        var legRect: CGRect?
        if let j = legShown, m.historyTrack != nil, shown > 0.999, j + 1 < track.stops.count, let r = Self.legRange(track, j) {
            let pm = m.screenPoint(track.points[(r.lowerBound + r.upperBound) / 2])
            var q = m.screenPoint((track.stops[j].at + track.stops[j + 1].at) / 2)
            if hypot(pm.x - q.x, pm.y - q.y) < 1 {
                let n = m.screenPoint(track.points[min(r.upperBound, (r.lowerBound + r.upperBound) / 2 + 1)])
                q = CGPoint(x: pm.x + (n.y - pm.y), y: pm.y - (n.x - pm.x))
            }
            legCap.set(Self.legWords(track.stops[j], track.stops[j + 1]), near: pm, awayFrom: q, in: room, visible: seen.contains(pm))
            legRect = legCap.isShown ? legCap.planned : nil
        } else {
            legShown = nil
            legCap.hide()
        }
        if let first = track.stops.first {
            let p0 = m.screenPoint(track.points.first ?? first.at)
            let dir = track.points.count > 1 ? m.screenPoint(track.points[1]) : CGPoint(x: p0.x + 1, y: p0.y)
            startCap.set(Self.words(first), near: p0, awayFrom: dir, in: room, avoid: legRect, visible: shown > 0.001 && m.historyTrack != nil && seen.contains(p0))
        }
        if let last = track.stops.last, track.stops.count > 1 {
            let pn = m.screenPoint(track.points.last ?? last.at)
            let prev = track.points.count > 1 ? m.screenPoint(track.points[track.points.count - 2]) : CGPoint(x: pn.x - 1, y: pn.y)
            endCap.set(Self.words(last), near: pn, awayFrom: prev, in: room, avoid: legRect, visible: shown > 0.999 && m.historyTrack != nil && seen.contains(pn))
        } else { endCap.hide() }
        if m.historyTrack == nil && shown <= 0.001 { self.track = nil; builtCount = -1; isHidden = true }
    }

    /// THE JOURNEY'S HOLD MENU (13.4): Share this journey · Open the start · Open the end (the line, a leg or a capsule)
    func menu(_ m: MapController) -> UIMenu? {
        guard let track, let first = track.stops.first, let last = track.stops.last else { return nil }
        let after = { (f: @escaping () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
        let share = UIAction(title: "Share this journey") { [weak self] _ in after { self?.shareJourney(m) } }
        let start = UIAction(title: "Open the start") { _ in after { Self.openPage(first, m) } }
        let end = UIAction(title: "Open the end", attributes: track.stops.count > 1 ? [] : .disabled) { _ in
            after { Self.openPage(last, m) }
        }
        return UIMenu(children: [share, start, end])
    }
    /// a stop's place page, through the page link (as Share's links open)
    private static func openPage(_ s: HistoryTrack.Stop, _ m: MapController) {
        guard let u = URL(string: "wya://page/\(s.key.description)") else { return }
        Task { @MainActor in
            if !(await DeepLink.open(u, map: m, close: {})) { Feel.refuse() }
        }
    }
    /// SHARE THIS JOURNEY: a square picture (no rounded corners) of the map as it is now, the line and its capsules on it,
    /// the room between the head and the water, our logo small in its corner, through the system share sheet
    func shareJourney(_ m: MapController, present: Bool = true) {
        guard let map = superview, let track else { return }
        let rr = m.layout.room(sheetTop: m.sheetTop > 0 ? m.sheetTop : m.layout.top(.quarter))
        let side = min(map.bounds.width, rr.upperBound - rr.lowerBound)
        // centred on the journey as it is on screen (31 Oct 10:58: centred on the room, it cut the line's top off), kept
        // inside the map
        let pts = track.points.map { m.screenPoint($0) }
        let lo = CGPoint(x: pts.map(\.x).min() ?? map.bounds.midX, y: pts.map(\.y).min() ?? map.bounds.midY)
        let hi = CGPoint(x: pts.map(\.x).max() ?? map.bounds.midX, y: pts.map(\.y).max() ?? map.bounds.midY)
        let cx: CGFloat = Swift.min(map.bounds.maxX - side / 2, Swift.max(map.bounds.minX + side / 2, (lo.x + hi.x) / 2))
        let cy: CGFloat = Swift.min(map.bounds.maxY - side / 2, Swift.max(map.bounds.minY + side / 2, (lo.y + hi.y) / 2))
        let crop = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
        let logo = ImageRenderer(content: LogoMark().frame(width: 40, height: 40))
        logo.scale = 3
        let mark = logo.uiImage
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let img = UIGraphicsImageRenderer(size: crop.size, format: format).image { _ in
            map.drawHierarchy(in: CGRect(origin: CGPoint(x: -crop.minX, y: -crop.minY), size: map.bounds.size), afterScreenUpdates: false)
            mark?.draw(in: CGRect(x: side - 40 - 14, y: side - 40 - 14, width: 40, height: 40))
        }
        #if DEBUG
        if let d = img.pngData() { try? d.write(to: URL(fileURLWithPath: Snap.dir + "/journey.png")) }
        #endif
        guard present else { return }
        let vc = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        var top = root
        while let next = top?.presentedViewController { top = next }
        top?.present(vc, animated: true)
    }

    /// TEST ONLY (the test driver's `history …`): on|off; tap <x> <y> (a tap on the journey there, as the map's
    /// confirmed tap hands it over); share; open start|end (the menu's rows); pull <dy> (the water grabbed at its top,
    /// moved dy pt, let go still). Kept out of the driver's one long switch, which compiles slowly.
    static func drive(_ p: [String], map: MapController?, water: Water?, head: HeadState?) async {
        let a = p.count > 1 ? p[1] : ""
        switch a {
        case "tap":
            guard p.count > 3, let m = map, let v = current else { return }
            let pt = CGPoint(x: Double(p[2]) ?? 0, y: Double(p[3]) ?? 0)
            if let h = v.hit(pt, m) {
                NSLog("wya history tap %@", String(describing: h))
                v.tapped(h, m)
            } else {
                NSLog("wya history tap: nothing")
                v.dismissLeg(m)
            }
        case "share":
            // (the picture only, into the test folder; "share sheet" also opens the system sheet)
            if let m = map, let v = current { v.shareJourney(m, present: p.count > 2 && p[2] == "sheet") }
        case "open":
            guard p.count > 2, let m = map, let t = m.historyTrack, let first = t.stops.first, let last = t.stops.last else { return }
            let s: HistoryTrack.Stop = p[2] == "end" ? last : first
            guard let u = URL(string: "wya://page/" + s.key.description) else { return }
            let ok: Bool = await DeepLink.open(u, map: m, close: {})
            let said: String = ok ? "opened" : "not opened"
            NSLog("wya history open %@: %@", s.key.description, said)
        case "pull":
            guard p.count > 2, let w = water else { return }
            let dy = CGFloat(Double(p[2]) ?? 0)
            let y0: CGFloat = w.level
            w.begin(at: CGPoint(x: 220, y: y0))
            for i in 1 ... 10 { w.move(to: CGPoint(x: 220, y: y0 + dy * CGFloat(i) / 10)) }
            try? await Task.sleep(for: .milliseconds(300))
            w.end(velocity: 0)
            let state: String = head?.history == true ? "on" : "off"
            NSLog("wya history pull %.0f: history %@", Double(dy), state)
        default:
            head?.history = a == "on"
        }
    }

    /// the capsules up, in this view's points (the map's names and marks keep clear of them)
    var capsuleFrames: [CGRect] {
        guard !isHidden else { return [] }
        return [startCap, endCap, legCap].filter(\.isShown).map(\.planned)
    }

    /// the points of leg `j` (none for two stops in one place)
    static func legRange(_ t: HistoryTrack, _ j: Int) -> ClosedRange<Int>? {
        guard j < t.legStart.count else { return nil }
        let a = t.legStart[j], b = j + 1 < t.legStart.count ? t.legStart[j + 1] : t.points.count - 1
        return b > a ? a ... b : nil
    }

    /// a tap at `p` (screen points): the capsules first, then the nearest leg within 12 pt; only with the whole line
    /// drawn
    func hit(_ p: CGPoint, _ m: MapController) -> Hit? {
        guard let track, m.historyTrack != nil, m.historyShown > 0.999 else { return nil }
        if startCap.isShown, startCap.frame.insetBy(dx: -2, dy: -2).contains(p) { return .start }
        if endCap.isShown, endCap.frame.insetBy(dx: -2, dy: -2).contains(p) { return .end }
        if legCap.isShown, legCap.frame.insetBy(dx: -2, dy: -2).contains(p) { return legShown.map { .leg($0) } }
        var best: (j: Int, d: CGFloat)?
        for j in 0 ..< track.legStart.count {
            guard let r = Self.legRange(track, j) else { continue }
            var a = m.screenPoint(track.points[r.lowerBound])
            for i in r.lowerBound ..< r.upperBound {
                let b = m.screenPoint(track.points[i + 1])
                let d = Self.distance(p, a, b)
                if d < 12, d < (best?.d ?? .infinity) { best = (j, d) }
                a = b
            }
        }
        return best.map { .leg($0.j) }
    }
    /// a confirmed tap on what `hit` found: a capsule frames its stop; a leg shows its capsule, or takes it away
    func tapped(_ h: Hit, _ m: MapController) {
        guard let track, !track.stops.isEmpty else { return }
        Feel.tap()
        switch h {
        case .start: legShown = nil; m.frameHistoryStop(track.stops[0])
        case .end: legShown = nil; m.frameHistoryStop(track.stops[track.stops.count - 1])
        case .leg(let j): legShown = legShown == j ? nil : j
        }
        m.needsFrame = true
    }
    /// any other tap on the map takes a leg's capsule away (13.4)
    func dismissLeg(_ m: MapController) {
        guard legShown != nil else { return }
        legShown = nil
        m.needsFrame = true
    }
    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        let along: CGFloat = l2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2 : 0
        let t: CGFloat = Swift.max(0, Swift.min(1, along))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
    /// "Lisbon → Madrid · 3–9 Mar 2024" (13.4): the two stops' arrival days, the month and year said once where shared
    static func legWords(_ a: HistoryTrack.Stop, _ b: HistoryTrack.Stop) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB")
        let mon = { (m: Int) in f.shortMonthSymbols[max(0, min(11, m - 1))] }
        let A = a.from, B = b.from
        let span: String
        if A.y == B.y && A.m == B.m {
            span = A.d == B.d ? "\(A.d) \(mon(A.m)) \(A.y)" : "\(A.d)–\(B.d) \(mon(A.m)) \(A.y)"
        } else if A.y == B.y {
            span = "\(A.d) \(mon(A.m)) – \(B.d) \(mon(B.m)) \(A.y)"
        } else {
            span = "\(A.d) \(mon(A.m)) \(A.y) – \(B.d) \(mon(B.m)) \(B.y)"
        }
        return "\(a.name) → \(b.name) · \(span)"
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
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var isShown: Bool { showing }
    /// away, words kept as they were
    func hide() {
        guard showing else { return }
        showing = false
        isHidden = true
    }

    /// where it stands at rest (its frame without the grow)
    private(set) var planned: CGRect = .zero
    func set(_ words: String, near p: CGPoint, awayFrom q: CGPoint, in room: CGRect, avoid: CGRect? = nil, visible: Bool) {
        if label.text != words { label.text = words; label.sizeToFit() }
        // never wider than the screen less 16 pt each side (a long leg's words end in "…")
        let most = room.width - 32 - 20
        if label.bounds.width > most { label.bounds.size.width = most }
        label.lineBreakMode = .byTruncatingMiddle
        let w = label.bounds.width + 20, h: CGFloat = 28
        // the side away from the line: from the line's next point back through the end, 8 pt past the capsule's half
        var dx = p.x - q.x, dy = p.y - q.y
        let len = max(0.001, hypot(dx, dy)); dx /= len; dy /= len
        // its nearest edge 8 pt from the point along that way (31 Oct 07:27: the sum of both half sizes put a long
        // capsule 40 pt and more away from its stop)
        let ax = abs(dx), ay = abs(dy)
        let byWidth: CGFloat = ax > 0.001 ? w / 2 / ax : CGFloat.infinity
        let byHeight: CGFloat = ay > 0.001 ? h / 2 / ay : CGFloat.infinity
        let reach: CGFloat = 8 + Swift.min(byWidth, byHeight)
        var centre = CGPoint(x: p.x + dx * reach, y: p.y + dy * reach)
        // never off the screen (a start on the map's edge, Portugal): kept 8 pt inside it; when that would put it over
        // its own point, under the point, else over it (the capsule covered Silverstone's dot at the screen's edge)
        if case let sv = room, sv.width > w + 16, sv.height > h + 16 {
            func kept(_ c: CGPoint) -> CGPoint {
                CGPoint(x: min(sv.maxX - w / 2 - 8, max(sv.minX + w / 2 + 8, c.x)),
                        y: min(sv.maxY - h / 2 - 8, max(sv.minY + h / 2 + 8, c.y)))
            }
            func covers(_ c: CGPoint) -> Bool {
                CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h).insetBy(dx: -6, dy: -6).contains(p)
            }
            centre = kept(centre)
            if covers(centre) {
                // over the point when the line leaves it downwards, under it when upwards (never across the line)
                let below = kept(CGPoint(x: p.x, y: p.y + 8 + h / 2)), above = kept(CGPoint(x: p.x, y: p.y - 8 - h / 2))
                let first = dy < 0 ? above : below, second = dy < 0 ? below : above
                centre = !covers(first) ? first : second
            }
        }
        bounds = CGRect(x: 0, y: 0, width: w, height: h)
        planned = CGRect(x: centre.x - w / 2, y: centre.y - h / 2, width: w, height: h)
        let visible = visible && !(avoid?.intersects(planned.insetBy(dx: -4, dy: -4)) ?? false)
        glass.frame = bounds
        label.frame = CGRect(x: 10, y: (h - label.bounds.height) / 2, width: label.bounds.width, height: label.bounds.height)
        if visible != showing {
            showing = visible
            // (31 Oct: no growing and shrinking for its own sake: it is there, or not)
            isHidden = !visible
        }
        center = centre
    }
}

/// THE RANGE BAR (13.4; redrawn 31 Oct 11:40 after "your slider sucks"): an iOS slider with two thumbs, drawn on the
/// water (no glass of its own), the water's width - 32. The track a 6 pt capsule of black 12% from your first dated stop
/// to today; the range a 6 pt black capsule between the thumbs; the thumbs white 28 pt circles with Apple's soft
/// shadow (44 pt to touch), as a UISlider's; the years under the track only when the track spans more than one, each
/// centred under its own stretch (black inside the range, black 50% outside), every 2nd, 5th or 10th when crowded.
/// The caption above says the range's dates, so nothing under the thumbs repeats it.
struct HistoryBar: View {
    let map: MapController
    let width: CGFloat
    @State private var lastEnd = 0
    /// the track's ends (the thumbs' centres can reach them)
    private var inset: CGFloat { 14 }

    var body: some View {
        if let info = map.historyInfo {
            let span = max(1, Double(info.last - info.first))
            let x = { (d: Int) -> CGFloat in inset + CGFloat(Double(d - info.first) / span) * (width - 2 * inset) }
            let lo = x(info.lo), hi = x(info.hi)
            let trackY: CGFloat = 16
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.ink.opacity(0.12))
                    .frame(width: width - 2 * inset + 6, height: 6).position(x: width / 2, y: trackY)
                Capsule().fill(Palette.ink)
                    .frame(width: max(6, hi - lo + 6), height: 6).position(x: (lo + hi) / 2, y: trackY)
                ForEach(years(info), id: \.self) { y in
                    let a = max(info.first, info.dayNumber(LocalDay(y: y, m: 1, d: 1)))
                    let b = min(info.last, info.dayNumber(LocalDay(y: y, m: 12, d: 31)))
                    let inside = b >= info.lo && a <= info.hi
                    Text(String(y)).font(.footnote.weight(.medium)).foregroundStyle(Palette.ink.opacity(inside ? 1 : 0.5))
                        .fixedSize().position(x: (x(a) + x(b)) / 2, y: 40)
                        .onTapGesture {
                            Feel.tap()
                            withAnimation(Motion.settle) { map.setHistoryRange(lo: a, hi: b) }
                        }
                }
                handle(lo, info: info, isLow: true, y: trackY)
                handle(hi, info: info, isLow: false, y: trackY)
            }
            .frame(width: width, height: 50)
            .coordinateSpace(.named("historybar"))
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
        guard last > first else { return [] }
        let n = max(1, last - first + 1)
        let each = (width - 2 * inset) / CGFloat(n)
        let step = each >= 30 ? 1 : each * 2 >= 30 ? 2 : each * 5 >= 30 ? 5 : 10
        return stride(from: first, through: last, by: 1).filter { ($0 - first) % step == 0 }
    }

    private func handle(_ at: CGFloat, info: HistoryInfo, isLow: Bool, y: CGFloat) -> some View {
        Circle().fill(Palette.white)
            .shadow(color: Palette.ink.opacity(0.18), radius: 4, y: 1)
            .overlay(Circle().stroke(Palette.ink.opacity(0.06), lineWidth: 0.5))
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(x: at, y: y)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("historybar"))
                .onChanged { v in
                    let share = Double((v.location.x - inset) / (width - 2 * inset))
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

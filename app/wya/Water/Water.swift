import SwiftUI

/// THE WATER: the tab capsule and the sheet are one body of glass; the sheet pours up out of the capsule and drains
/// back into it. So there is no surface simulation any more, nothing that keeps moving on its own and nothing that can
/// build up: the glass is one shape worked out from two numbers (the droplet model of the old app's GlassForm):
/// `level`, where the body's top edge is, and `drop`, how far a droplet reaches out of that edge towards your finger.
/// The body follows the finger on a soft spring with no bounce; whatever it lags behind is the droplet, so a quick pull
/// leads with a round drop and the body fills in behind it, and the moment you stop the body catches up and the drop
/// goes back into it. At full it is the page: the screen's own edges and corners, no droplet, no movement.
@MainActor
@Observable
final class Water {
    typealias Stop = SheetStop

    /// where everything sits on this phone; set from the window before the first frame
    var layout = Layout.placeholder {
        didSet { if oldValue != layout { relayout() } }
    }
    var screen: CGSize { CGSize(width: layout.W, height: layout.H) }
    func y(_ s: Stop) -> CGFloat { layout.top(s) }

    /// the body's top edge
    private(set) var level: CGFloat = Layout.placeholder.top(.quarter)
    /// how far the droplet reaches past the top edge (up), in points
    private(set) var drop: CGFloat = 0
    /// where along the edge the droplet hangs
    private(set) var dropX: CGFloat = 201
    private(set) var stop: Stop = .quarter
    /// true while a finger holds the water
    private(set) var held = false
    /// MAP SETTINGS are the water's content (Part 5.2): set while the gear is out; `settingsFrom` is the stop the water
    /// was at before, where it goes back to when they close
    var settings = false
    /// the rows' words are in (they roll in once the old content has gone, and out before it comes back)
    var settingsWords = false
    @ObservationIgnored var settingsFrom: Stop?

    /// MAP SETTINGS OPEN (A5.1): the water rises to 50% if it is lower (at 50% or full it stays), the caption's words
    /// roll out and the Cosmos moves down out of the water; then the rows' words roll in
    func openSettings() {
        guard !settings else { return }
        settingsFrom = stop
        settings = true
        if stop == .closed || stop == .quarter { go(.half) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.settings else { return }
            withAnimation(Motion.quick) { self.settingsWords = true }
        }
    }
    /// MAP SETTINGS CLOSE (A5.2): the rows' words roll out first; then the water goes back to the stop it was at (or
    /// stays where a pull's release took it) and the Cosmos and the caption come back by their own rules
    func closeSettings() {
        guard settings else { return }
        withAnimation(.smooth(duration: 0.15)) { settingsWords = false }
        let back = settingsFrom
        settingsFrom = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, !self.settingsWords else { return }
            self.settings = false
            if let back, self.stop == .half, back != .half, self.grab == nil { self.go(back) }
        }
    }
    /// DETAILS are the water's content (Part 4.4): the water rises to 50% (or stays if higher); `detailsFrom` is the
    /// stop it goes back to when they close; `detailsWords` as settingsWords
    var details = false
    var detailsWords = false
    @ObservationIgnored var detailsFrom: Stop?
    func openDetails() {
        guard !details else { return }
        detailsFrom = stop
        details = true
        if stop == .closed || stop == .quarter { go(.half) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.details else { return }
            withAnimation(Motion.quick) { self.detailsWords = true }
        }
    }
    /// `rolled`: the sheet's words have already rolled out (back to the Stamped list, A4.21), so no wait for them
    func closeDetails(rolled: Bool = false) {
        guard details else { return }
        withAnimation(.smooth(duration: 0.15)) { detailsWords = false }
        let back = detailsFrom
        detailsFrom = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + (rolled ? 0 : 0.18)) { [weak self] in
            guard let self, !self.detailsWords else { return }
            self.details = false
            // back to where it was, unless a pull's release already took it somewhere below 50%
            if let back, self.stop != back, self.stop.rawValue >= Stop.half.rawValue, self.grab == nil, !self.settings { self.go(back) }
        }
    }

    /// THE UPLOAD SHEET is the water's content (Part 9.3): at 25% (the water comes there from where it was);
    /// `uploadFrom` is the stop it goes back to when it closes
    var upload = false
    @ObservationIgnored var uploadFrom: Stop?
    func openUpload() {
        guard !upload else { return }
        uploadFrom = stop
        upload = true
        if stop != .quarter { go(.quarter) }
    }
    func closeUpload() {
        guard upload else { return }
        upload = false
        let back = uploadFrom
        uploadFrom = nil
        if let back, back != stop, grab == nil { go(back) }
    }

    /// THE STAMPED LIST is the water's content (Part 4.6): opened by the caption's number, at full; `listFrom` is the
    /// stop it goes back to
    var stampedList = false
    @ObservationIgnored var listFrom: Stop?
    func openList() {
        guard !stampedList else { return }
        listFrom = stop
        stampedList = true
        if stop != .full { go(.full) }
    }
    /// closed by the number again or a pull (`to` nil: stay where the pull left it)
    /// the list stays on screen this long after it is closed, while its rows leave (A4.19 reversed)
    var listLeaving = false
    @ObservationIgnored private var leaveJob = 0
    func closeList(to: Stop? = nil, back: Bool = true) {
        guard stampedList else { return }
        stampedList = false
        listLeaving = true
        leaveJob += 1
        let job = leaveJob
        DispatchQueue.main.asyncAfter(deadline: .now() + StampedList.leaving(StampedList.animated)) { [weak self] in
            if self?.leaveJob == job { self?.listLeaving = false }
        }
        let s = to ?? (back ? listFrom : nil)
        listFrom = nil
        if let s, s != stop { go(s) }
    }

    /// THE START CREDIT (BUILD-BOOK 1.4, A1.20): the OpenStreetMap words on the water; once at every cold launch, for
    /// 5 s or until the first touch on the map
    var credit = false
    @ObservationIgnored private(set) var creditDone = false
    func showCredit() {
        guard !creditDone else { return }
        credit = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38 + 5) { [weak self] in self?.hideCredit() }
    }
    /// back down into the edge, from wherever it is; not again until the next cold launch
    func hideCredit() {
        // a touch before it has started doesn't count: it is still shown once
        guard !creditDone, credit else { return }
        creditDone = true
        credit = false
    }

    // MARK: the shape's numbers, from the level
    struct Form: Equatable {
        var box: CGRect
        var corner: CGFloat
        /// 0 in the capsule, 1 once it is the sheet
        var sheet: CGFloat
        /// 0 up to half, 1 at full (the page)
        var page: CGFloat
        var drop: CGFloat
        var dropX: CGFloat
        var top: CGFloat { box.minY }
        var bottom: CGFloat { box.maxY }
        var left: CGFloat { box.minX }
        var right: CGFloat { box.maxX }
    }

    func form(level l: CGFloat? = nil) -> Form {
        let L = layout
        let lv = l ?? level
        let A = L.capsule
        let Q = L.top(.quarter), Hf = L.top(.half)
        // out of the capsule: the top edge rises first, and the sides and the bottom widen to the sheet's in the
        // second part of the way (the old sheetBase)
        let q = Flow.clamp01((A.minY - lv) / max(1, A.minY - Q))
        let wide = Flow.smooth(0.3, 1, q)
        // past half it becomes the page: its edges go out to the screen's
        let pg = Flow.clamp01((Hf - lv) / max(1, Hf))
        let pageEase = pg * pg * (3 - 2 * pg)
        // at full the glass has no edge anywhere on the screen: on the way there its sides, its bottom and its top go
        // on out past the screen's own edges, so no rim or corner is ever seen
        let past = Self.pastEdge * pageEase
        let inset = L.sheetInset * (1 - pageEase) - past
        let left = Flow.lerp(A.minX, inset, wide)
        let right = Flow.lerp(A.maxX, L.W - inset, wide)
        let bottom = Flow.lerp(A.maxY, L.H - inset, wide)
        let corner = Flow.lerp(Flow.lerp(L.capsuleCorner, L.sheetCorner, Flow.smooth(0, 0.7, q)), L.screenCorner, pageEase)
        let top = min(lv - past, bottom - 2 * L.capsuleCorner)
        return Form(box: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                    corner: corner, sheet: wide, page: pg,
                    drop: drop * (1 - pageEase), dropX: dropX)
    }

    /// how far past the screen's edges the glass reaches at full, so its rim and corners are off the screen
    nonisolated static let pastEdge: CGFloat = 60

    // MARK: touch
    @ObservationIgnored private var body = Spring1(Layout.placeholder.top(.quarter), response: 0.42, damping: 1)
    @ObservationIgnored private var dropSpring = Spring1(0, response: 0.3, damping: 1)
    @ObservationIgnored private var grab: (level: CGFloat, y: CGFloat, from: Stop)?
    @ObservationIgnored private var fingerTop: CGFloat = 0
    @ObservationIgnored private var lastPassed: Stop?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var landingSpeed: CGFloat = 0
    /// a move into the capsule waiting for the caption's words to roll out
    @ObservationIgnored private var pendingGo: UUID?
    /// pulled up from half, past the point where a release goes on to full
    @ObservationIgnored private var pastCommit = false

    /// a finger has started to move the water (the head puts settings or the AI away then)
    @ObservationIgnored var onTouch: (() -> Void)?
    /// the Map tab tapped again: what a reset closes besides the water and the camera (2.3)
    @ObservationIgnored var onMapAgain: (() -> Void)?
    /// another tab chosen
    @ObservationIgnored var onTabChange: (() -> Void)?

    func begin(at p: CGPoint) {
        // caught before a waiting move into the capsule started: it is still where it was
        if pendingGo != nil {
            pendingGo = nil
            stop = Stop.allCases.min(by: { abs(layout.top($0) - body.value) < abs(layout.top($1) - body.value) }) ?? stop
        }
        grab = (body.value, p.y, stop)
        pastCommit = false
        fingerTop = body.value
        dropX = p.x
        held = true
        lastPassed = stop
        run()
    }

    func move(to p: CGPoint) {
        guard let g = grab else { return }
        let L = layout
        dropX = p.x
        // where the top edge would be if it were glued to the finger
        var t = g.level + (p.y - g.y)
        let lo = L.top(.full), hi = L.top(.closed)
        // past full it does not go at all: no give and no spring back at the top
        if t < lo { t = lo }
        // the upload sheet has no 50% while choosing: pulled up, the water gives 12 pt and no more (9.3)
        if upload, UploadState.shared.phase != .review, t < L.top(.quarter) { t = L.top(.quarter) - Flow.rubber(L.top(.quarter) - t, 12) }
        // under the capsule it does not go either
        if t > hi { t = hi + Flow.rubber(t - hi, 10) }
        // from 50% up to full it is harder: above half the water follows at 0.75 for the first 60 points, then 1:1,
        // with a tick at the point past which a release goes to full (BUILD-BOOK 2.3)
        let Hf = L.top(.half)
        if g.from != .full && t < Hf {
            let over = Hf - t
            t = Hf - (over <= 60 ? over * 0.75 : 45 + (over - 60))
            let past = t <= Hf * 0.55
            if past != pastCommit { pastCommit = past; Feel.tick() }
        }
        fingerTop = t
        // pulled out of the capsule, the first 40 points are only the droplet; then the body fills in behind it
        var target = t
        if g.from == .closed {
            let s = hi - t
            if s > 0 { target = hi - Water.behind(s) }
        }
        body.target = target
        body.response = 0.16
        body.damping = 1
        // a soft tick at each height it passes (once)
        if let near = Stop.allCases.min(by: { abs(L.top($0) - t) < abs(L.top($1) - t) }),
           abs(L.top(near) - t) < 4, near != lastPassed {
            lastPassed = near
            Feel.tick()
        }
        run()
    }

    func end(velocity v: CGFloat) {
        guard let g = grab else { return }
        grab = nil
        held = false
        // the upload sheet: pulled down (past 40 pt or flicked) it closes and the water goes back to where it was;
        // pulled up it settles back to 25% with a refuse (9.3)
        // the review (9.5) can be pulled up to its rows like any sheet; pulled down past 25% it is left
        // (a flick down from higher up goes to the next stop; only a pull or flick down from about 25% leaves it)
        if upload, UploadState.shared.phase == .review, fingerTop <= layout.top(.quarter) + 40,
           v <= 300 || fingerTop < layout.top(.quarter) - 40 {
            // falls through to the ordinary stops below
        } else if upload {
            let q = layout.top(.quarter)
            if fingerTop > q + 40 || v > 300 {
                go(.quarter, speed: v, released: true)
                UploadState.shared.close()
            } else {
                if fingerTop < q - 4 { Feel.refuse() }
                go(.quarter, speed: v, released: true)
            }
            return
        }
        // a flick goes on to the next height its way, otherwise the nearest; never more than one height from where
        // it was picked up
        let order = Stop.allCases
        let here = fingerTop
        var best = order.min(by: { abs(layout.top($0) - here) < abs(layout.top($1) - here) }) ?? .quarter
        if abs(v) > 300 {
            let up = v < 0
            let cur = order.min(by: { abs(layout.top($0) - here) < abs(layout.top($1) - here) }) ?? g.from
            let beyond = order.filter { up ? layout.top($0) < here - 6 : layout.top($0) > here + 6 }
            if let next = up ? beyond.max(by: { layout.top($0) < layout.top($1) }) : beyond.min(by: { layout.top($0) < layout.top($1) }) {
                best = next
            } else { best = cur }
        }
        // between half and full the commit points decide (BUILD-BOOK 2.3): up from half it goes on to full only past
        // 45% of the way or flicked faster than 1,100 pt/s; down from full it goes to half only past 35% of the way or
        // flicked faster than 900 pt/s
        let Hf = layout.top(.half)
        if g.from != .full && here < Hf - 1 && v <= 300 {
            best = (here <= Hf * 0.55 || v < -1100) ? .full : .half
        } else if g.from == .full && here < Hf && v >= -300 {
            best = (here >= Hf * 0.35 || v > 900) ? .half : .full
        }
        if abs(best.rawValue - g.from.rawValue) > 1 {
            best = order[g.from.rawValue + (best.rawValue > g.from.rawValue ? 1 : -1)]
        }
        go(best, speed: v, released: true)
    }

    /// to a height. A release has the softest give at the end (water settling); anything else lands without one;
    /// the page never bounces against the screen's edges.
    func go(_ s: Stop, speed: CGFloat = 0, released: Bool = false) {
        // sent into the capsule (not let go by a finger) with the caption's words showing: the words roll out first
        // (0.15 s), then the water goes down, so the edge never passes over them (A2.5; the old content leaves first)
        if s == .closed, !released, level <= layout.capsule.minY - 134, stop != .closed {
            stop = s
            let me = UUID()
            pendingGo = me
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.pendingGo == me, self.stop == .closed, self.grab == nil else { return }
                self.pendingGo = nil
                self.body.target = self.layout.top(.closed)
                self.body.response = 0.42
                self.body.damping = 1
                self.run()
            }
            return
        }
        pendingGo = nil
        stop = s
        body.target = layout.top(s)
        // Reduce Motion: the same settle, shorter (Part 19)
        body.response = (s == .full ? 0.5 : 0.42) * (Motion.reduce ? 0.65 : 1)
        body.damping = (released && s != .full && abs(speed) > 900) ? 0.9 : 1
        landingSpeed = abs(speed)
        run()
    }


    private func relayout() {
        // a new screen (the first layout, or the phone turned): sit at the same height, no movement
        body.target = layout.top(stop)
        body.snap()
        level = body.value
        drop = 0
        dropSpring.value = 0; dropSpring.target = 0
    }

    /// how far the body's edge has come for a droplet pulled `s` past the capsule: nothing for the first 40 points,
    /// then it follows ever more closely, at most 120 points behind (GlassForm's `behind`)
    nonisolated static func behind(_ s: CGFloat) -> CGFloat {
        let x = max(0, s - 40)
        return x - 80 * (1 - exp(-x / 80))
    }

    // MARK: the movement: two springs with no bounce, stepped only while something moves
    private func run() {
        guard !running else { return }
        running = true
        Clock.shared.run(self, step: { [weak self] dt in self?.step(dt) ?? false },
                         frame: { [weak self] in self?.publish() })
    }

    @ObservationIgnored private var pubLevel: CGFloat = Layout.placeholder.top(.quarter)
    @ObservationIgnored private var pubDrop: CGFloat = 0

    private func step(_ dt: CGFloat) -> Bool {
        body.step(dt)
        // the droplet is what the body lags behind the finger, upward only, and at most 90 points
        let lead = grab != nil ? min(90, max(0, body.value - fingerTop)) : 0
        dropSpring.target = lead
        dropSpring.response = grab != nil ? 0.06 : 0.28
        dropSpring.step(dt)
        if dropSpring.value < 0 { dropSpring.value = 0; dropSpring.velocity = max(0, dropSpring.velocity) }
        let moving = grab != nil || !body.settled || !dropSpring.settled
        if !moving {
            body.snap(); dropSpring.snap()
            if landingSpeed > 0 { Feel.land(speed: landingSpeed); landingSpeed = 0 }
        }
        pubLevel = body.value
        pubDrop = dropSpring.value

        if !moving { running = false; publish() }
        return moving
    }

    private func publish() {
        if level != pubLevel { level = pubLevel }
        if drop != pubDrop { drop = pubDrop }
    }
}

/// The water's outline: a rounded box whose top edge carries the droplet (GlassForm's outline: the drop is a hill,
/// wide at its foot and round at its end, flowing into the edge and its corners; one closed curve, no straight line
/// anywhere it shouldn't be).
nonisolated struct WaterShape: Shape {
    var form: Water.Form

    func path(in rect: CGRect) -> Path {
        let b = form.box
        guard b.width > 1, b.height > 1 else { return Path() }
        let pts = DropOutline.points(b, corner: form.corner, cx: form.dropX, drop: form.drop)
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        // a smooth curve through the points: each segment is a quadratic through the midpoints
        for i in 1 ..< pts.count {
            let a = pts[i - 1], c = pts[i]
            p.addQuadCurve(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2), control: a)
        }
        p.addLine(to: pts[pts.count - 1])
        p.closeSubpath()
        return p
    }
}

/// GlassForm's outline maths (the old app's), for a top edge.
nonisolated enum DropOutline {
    static func smooth(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        guard b > a else { return x < a ? 0 : 1 }
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
    /// how wide the droplet is: from 42 points (just out) to the whole edge (long)
    static func spread(_ d: CGFloat) -> CGFloat { smooth(0, 40, d) }
    /// how round its end is
    static func roundness(_ d: CGFloat) -> CGFloat { smooth(0, 36, d) }
    /// the droplet's height across its width (`v` 0 at its foot, 1 in the middle): a hill, wide at its foot and
    /// round at its top
    static func profile(_ v: CGFloat, round r: CGFloat) -> CGFloat {
        let v = min(1, max(0, v))
        let point = 1 - cos(.pi * v / 2)
        let pulled = pow((1 - cos(.pi * v)) / 2, 1.6)
        return point + (pulled - point) * min(1, max(0, r))
    }

    static func points(_ b: CGRect, corner: CGFloat, cx: CGFloat, drop d: CGFloat, steps: Int = 48) -> [CGPoint] {
        let R = max(0, min(corner, b.width / 2, b.height / 2))
        let half = b.width / 2
        let w = spread(d)
        let a = min(half, 21 + (half - 21) * w)
        let lo = b.minX + a, hi = b.maxX - a
        let c0 = lo <= hi ? min(max(cx, lo), hi) : b.midX
        let mid = c0 + (b.midX - c0) * w * 0.6
        let r = roundness(d)
        func inset(_ x: CGFloat) -> CGFloat {
            let e = min(x - b.minX, b.maxX - x)
            guard R > 0, e < R else { return 0 }
            let t = R - max(0, e)
            return R - max(0, R * R - t * t).squareRoot()
        }
        func bulge(_ x: CGFloat) -> CGFloat {
            guard d > 0.3, a > 0.5 else { return 0 }
            let u = abs(x - mid) / a
            return u >= 1 ? 0 : d * profile(1 - u, round: r)
        }
        var xs: [CGFloat] = [b.minX, b.maxX]
        for i in 0 ... steps { xs.append(b.minX + b.width * (1 - cos(.pi * CGFloat(i) / CGFloat(steps))) / 2) }
        if d > 0.3 { for i in 0 ... steps { xs.append(mid - a + 2 * a * CGFloat(i) / CGFloat(steps)) } }
        xs = xs.map { min(b.maxX, max(b.minX, $0)) }.sorted()
        var edge: [CGFloat] = []
        for x in xs where edge.last.map({ x - $0 > 0.25 }) ?? true { edge.append(x) }

        var pts: [CGPoint] = []
        pts.reserveCapacity(edge.count + 20)
        // the top edge, left to right, with the droplet rising out of it
        for x in edge { pts.append(CGPoint(x: x, y: b.minY + inset(x) - bulge(x))) }
        // the bottom corners and edge, right to left
        func arc(_ x: CGFloat, _ y: CGFloat, _ from: CGFloat, _ to: CGFloat) {
            for i in 0 ... 8 {
                let t = from + (to - from) * CGFloat(i) / 8
                pts.append(CGPoint(x: x + R * cos(t), y: y + R * sin(t)))
            }
        }
        arc(b.maxX - R, b.maxY - R, 0, .pi / 2)
        arc(b.minX + R, b.maxY - R, .pi / 2, .pi)
        pts.append(pts[0])
        return pts
    }
}

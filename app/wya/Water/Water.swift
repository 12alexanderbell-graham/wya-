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
    // (8 Nov: each open and close is its own job: a close within the open's first 0.35 s used to let the open's
    // words come in after the close had looked, so the close never finished and the sheet stayed with the gear gone)
    @ObservationIgnored private var settingsJob = 0
    @ObservationIgnored private var settingsClosing = false
    func openSettings() {
        // opened again while closing: the close is called off and the words come back
        if settings, settingsClosing {
            settingsJob += 1; settingsClosing = false
            settingsFrom = stop
            let me = settingsJob
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self, self.settings, me == self.settingsJob else { return }
                withAnimation(Motion.quick) { self.settingsWords = true }
            }
            return
        }
        guard !settings else { return }
        // (Details or Verify up at 50% go as settings come: the water goes back to the card's 25%, not their 50%)
        settingsFrom = details && stop == .half ? .quarter : stop
        // over the menu (6.3): from the menu stop down to 50% while the rows leave; closing brings the menu back
        if regions { leaveMenuRows() }
        settings = true
        if stop == .closed || stop == .quarter || regions { go(.half) }
        settingsJob += 1
        let me = settingsJob
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.settings, me == self.settingsJob else { return }
            withAnimation(Motion.quick) { self.settingsWords = true }
        }
    }
    /// MAP SETTINGS CLOSE (A5.2): the rows' words roll out first; then the water goes back to the stop it was at (or
    /// stays where a pull's release took it) and the Cosmos and the caption come back by their own rules
    func closeSettings() {
        guard settings, !settingsClosing else { return }
        settingsClosing = true
        settingsJob += 1
        let me = settingsJob
        withAnimation(.smooth(duration: 0.15)) { settingsWords = false }
        let back = settingsFrom
        settingsFrom = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, me == self.settingsJob else { return }
            self.settingsClosing = false
            self.settings = false
            if self.regions { self.go(.half); return }
            if let back, self.stop == .half, back != .half, self.grab == nil { self.go(back) }
        }
    }
    /// REGIONS' SELECTION MENU is the water's content (6.3): the water is at full, and a drag on it scrolls the list and
    /// never moves it.
    /// `regions` is on from the wheel landing on Regions until a country is picked or another mode comes; while
    /// settings or the upload sheet are up over it the water goes where they need it, and back to the menu after.
    var regions = false
    /// when the map's mode last changed: what the change swaps in and out of the water goes with no movement
    @ObservationIgnored var modeSwitchedAt: CFTimeInterval = 0
    var modeSwitching: Bool { CACurrentMediaTime() - modeSwitchedAt < 0.4 }
    /// the menu's rows are still on screen, leaving through the list's bottom edge as the water goes down
    var menuLeaving = false
    @ObservationIgnored private var menuJob = 0
    /// a place's page is up (16.1): the Regions list steps aside for it as for settings, and is back when it closes
    var pageUp = false
    var menuShown: Bool { regions && !settings && !details && !upload && !pageUp }
    /// the head, for the menu's search (set once by the screen)
    @ObservationIgnored weak var head: HeadState?
    /// the menu is the whole screen, as the old native app's Regions list was (clear glass with the world under
    /// it); never a height between half and full (30 Oct 22:35:
    ///)
    var menuTop: CGFloat { layout.top(.full) }
    /// where the water rests for a stop (the menu's own place while it shows)
    func restTop(_ s: Stop) -> CGFloat { menuShown ? menuTop : (historyUp && s == .quarter) ? layout.top(.quarter) - 56 : layout.top(s) }
    /// HISTORY (13.4): the 25% water risen 56 pt to hold the range bar ("history height")
    var historyUp = false
    /// A6.5: the water goes to the menu stop from wherever it is (it is never a stop a drag can reach)
    /// Coming into Regions it is simply there, with no movement (a mode change has no motion);
    /// `instant: false` keeps the move for the Map tab's way back to the list
    func openMenu(instant: Bool = false) {
        menuJob += 1
        menuLeaving = false
        regions = true
        if instant { jump(.half) } else { go(.half) }
    }
    /// leaving the menu (another mode, or a country picked): the water goes to `to` while the rows leave through the
    /// list's bottom soft edge; they are kept on screen until the water is down
    func closeMenu(to s: Stop = .quarter, instant: Bool = false) {
        guard regions else { return }
        // the rows leave only if they were showing (not from under settings or the upload sheet); leaving Regions for
        // another mode, they simply go with it
        if menuShown, !instant { leaveMenuRows() }
        regions = false
        if instant, !settings, !upload {
            if settingsFrom == .half { settingsFrom = .quarter }
            if uploadFrom == .half { uploadFrom = .quarter }
            jump(s); return
        }
        // what settings or the upload go back to when they close: never the list's stop
        if settingsFrom == .half { settingsFrom = .quarter }
        if uploadFrom == .half { uploadFrom = .quarter }
        if settings || upload { return }
        go(s)
    }
    /// the rows stay on screen while the water takes them down through the list's bottom edge
    private func leaveMenuRows() {
        menuLeaving = true
        menuJob += 1
        let job = menuJob
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.menuJob == job { self?.menuLeaving = false }
        }
    }

    /// DETAILS are the water's content (Part 4.4): the water rises to 50% (or stays if higher); `detailsFrom` is the
    /// stop it goes back to when they close; `detailsWords` as settingsWords
    var details = false
    var detailsWords = false
    @ObservationIgnored var detailsFrom: Stop?
    // (the same jobs as settings': a close in the open's first 0.35 s left Details, or Verify, up with no place)
    @ObservationIgnored private var detailsJob = 0
    @ObservationIgnored private var detailsClosing = false
    func openDetails() {
        if details, detailsClosing {
            detailsJob += 1; detailsClosing = false
            detailsFrom = stop
            let me = detailsJob
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self, self.details, me == self.detailsJob else { return }
                withAnimation(Motion.quick) { self.detailsWords = true }
            }
            return
        }
        guard !details else { return }
        detailsFrom = stop
        details = true
        if stop == .closed || stop == .quarter { go(.half) }
        detailsJob += 1
        let me = detailsJob
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.details, me == self.detailsJob else { return }
            withAnimation(Motion.quick) { self.detailsWords = true }
        }
    }
    /// `rolled`: the sheet's words have already rolled out (back to the Stamped list, A4.21), so no wait for them
    func closeDetails(rolled: Bool = false) {
        guard details, !detailsClosing else { return }
        detailsClosing = true
        detailsJob += 1
        let me = detailsJob
        withAnimation(.smooth(duration: 0.15)) { detailsWords = false }
        let back = detailsFrom
        detailsFrom = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + (rolled ? 0 : 0.18)) { [weak self] in
            guard let self, me == self.detailsJob else { return }
            self.detailsClosing = false
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
        if regions { leaveMenuRows() }
        upload = true
        if stop != .quarter { go(.quarter) }
    }
    func closeUpload() {
        guard upload else { return }
        upload = false
        let back = uploadFrom
        uploadFrom = nil
        if regions { go(.half); return }
        if let back, back != stop, grab == nil { go(back) }
    }

    /// THE STAMPED LIST is the water's content (Part 4.6): opened by the caption's number, at full; `listFrom` is the
    /// stop it goes back to
    var stampedList = false
    /// a place's page is up and its own sheet is in the water (16.6)
    var pageSheet = false
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
    func closeList(to: Stop? = nil, back: Bool = true, instant: Bool = false) {
        guard stampedList else { return }
        stampedList = false
        // (a mode change: simply gone, never leaving over the next mode's own rows)
        if instant { listLeaving = false; listFrom = nil; return }
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
    /// a mode picked from the Map tab's hold menu (11.5): the mode, and the current one ("Countries")
    @ObservationIgnored var onModePick: ((Int) -> Void)?
    @ObservationIgnored var currentMode: (() -> Int)?

    func begin(at p: CGPoint) {
        // the menu stop: a drag scrolls the list, the water stays (6.3)
        if menuShown { return }
        // caught before a waiting move into the capsule started: it is still where it was
        if pendingGo != nil {
            pendingGo = nil
            stop = Stop.allCases.min(by: { abs(layout.top($0) - body.value) < abs(layout.top($1) - body.value) }) ?? stop
        }
        grab = (body.value, p.y, stop)
        Hints.shared.usedWater()
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
        // a plain sheet under the finger, one to one, with hard ends: no give past a stop, no harder band above 50%,
        // no ticks, no droplet, no lag behind the finger
        // the upload sheet has no 50% while choosing (9.3), and at history height the line needs the map (13.4):
        // pulled up, it stays at its own height
        if upload, UploadState.shared.phase != .review { t = max(t, L.top(.quarter)) }
        if historyUp, !stampedList, !details { t = max(t, restTop(.quarter)) }
        // the Route row (Pins) is the caption's line at 25%: nothing above it to show (its 50% was empty glass)
        if PinRoutes.shared.open { t = max(t, L.top(.quarter)) }
        // over the plain Countries map the water goes no higher than 50% (no full-screen solar system); full is for
        // what fills it (a list, settings, Details, a page's sheet, the other modes' sheets)
        if !fullAllowed { t = max(t, L.top(.half)) }
        if t > hi { t = hi }
        fingerTop = t
        body.target = t
        body.snap()
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
        // HISTORY HEIGHT (13.4): pulled up it settles back with a refuse; pulled (or flicked) down to 25% or below,
        // history turns off and the water settles at 25% (the tool's own off, A13.3)
        // (the journey's rows up at full: a pull down puts them away and the water goes back to history height, 13.4)
        if historyUp, stampedList {
            if fingerTop > layout.top(.full) + 40 || v > 300 { closeList() } else { go(.full, speed: v, released: true) }
            return
        }
        if historyUp, !details {
            let q = layout.top(.quarter)
            if fingerTop >= q - 4 || v > 300 {
                head?.history = false
                historyUp = false
                go(.quarter, speed: v, released: true)
            } else {
                if fingerTop < restTop(.quarter) - 4 { Feel.refuse() }
                go(.quarter, speed: v, released: true)
            }
            return
        }
        // where a release goes (a plain sheet's rule): the stop nearest to where the sheet would coast to at this
        // speed (0.1 s of it), never more than one stop from where it was picked up
        let order = Stop.allCases
        let projected = fingerTop + v * 0.1
        var best = order.min(by: { abs(layout.top($0) - projected) < abs(layout.top($1) - projected) }) ?? .quarter
        if best == .full, !fullAllowed { best = .half }
        if PinRoutes.shared.open, best == .half || best == .full { best = .quarter }
        if abs(best.rawValue - g.from.rawValue) > 1 {
            best = order[g.from.rawValue + (best.rawValue > g.from.rawValue ? 1 : -1)]
        }
        go(best, speed: v, released: true)
    }

    /// to a height. A release has the softest give at the end (water settling); anything else lands without one;
    /// the page never bounces against the screen's edges.
    /// THE WATER'S FIRST-TIME HINT (A3.15): its top rises 24 pt and settles back, 0.8 s, the one time it moves by
    /// itself; a finger takes it from wherever it is
    /// whether the water may be pulled to full: not over the plain Countries map
    var fullAllowed: Bool {
        stampedList || settings || details || upload || pageSheet || regions || (head?.mode ?? .countries) != .countries
    }

    func hint() {
        // (no more: the water never moves by itself)
    }

    /// the water at a stop at once, no movement (a mode's own content swapped in, not moved)
    func jump(_ s: Stop) {
        pendingGo = nil
        landingSpeed = 0
        stop = s
        body.target = restTop(s)
        body.snap()
        pubLevel = body.value
        level = body.value
    }

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
        // (full only where something fills it: over the plain Countries map 50% is the top)
        let s = s == .full && !fullAllowed ? .half : s
        stop = s
        body.target = restTop(s)
        // Reduce Motion: the same settle, shorter (Part 19)
        body.response = 0.35 * (Motion.reduce ? 0.65 : 1)
        // (never past its stop: a fast fling at 0.9 let the sheet overshoot a little, 8 Nov)
        body.damping = 1
        // (no landing haptic: a plain sheet lands silently)
        landingSpeed = 0
        run()
    }


    private func relayout() {
        // a new screen (the first layout, or the phone turned): sit at the same height, no movement
        body.target = restTop(stop)
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
        // (no droplet any more: the sheet is under the finger)
        let lead: CGFloat = 0
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

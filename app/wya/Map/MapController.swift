import SwiftUI
import simd

/// What the map shows and where the camera is. The camera is a centre in map units and a scale in points per map unit;
/// the Metal view reads it every frame. The rules it keeps: - the world's height fills the screen at home: the
/// northernmost land (83.6°N) at the top edge, the South Pole at the bottom edge; no panning up or down at that zoom -
/// the camera never shows past the world: not above the north edge, not under Antarctica, not zoomed out past the
/// world's size, at any moment, a pinch held included - the map never moves on its own: only your fingers, the zoom
/// column and a search result move it
@MainActor
@Observable
final class MapController {
    // MARK: the world
    @ObservationIgnored private(set) var world: World?
    @ObservationIgnored private(set) var relief: Relief?
    private(set) var ready = false

    // MARK: what's on the map (a demo account for now: see DemoAccount)
    var stamped: Set<Int> = []
    var wished: Set<Int> = []
    /// the moon's stop: 0 Both, 1 Stamped, 2 Stamped+, 3 Wishlist+, 4 Wishlist (the + views come with counts)
    var filter = 0 { didSet { needsFrame = true } }
    /// the moon is held: the caption shows the filter's name
    var moonHeld = false
    var showsStamped: Bool { filter <= 2 }
    var showsWished: Bool { filter == 0 || filter >= 3 }
    /// the place darkened under a finger (or for a moment after a search); the tap is felt only under a finger
    /// a finger has landed on the map (the head puts settings or the AI away then, and the touch goes on as normal)
    @ObservationIgnored var onTouch: (() -> Void)?
    @ObservationIgnored var pressed: Int? { didSet { if pressed != oldValue { if pressed != nil && touching { Feel.tap() }; needsFrame = true } } }
    /// the lock: the map still moves, but pressing a place does nothing
    var locked = false
    /// the sun picked: the words show your streak instead of the count, and the fire rises
    var sunPicked = false
    /// weeks in a row with a new stamp (the demo account's, until accounts exist)
    var streakWeeks = 3
    /// the test driver's way to choose a planet as a tap would (simulator only)
    var testPlanet: Int?
    /// the test driver holding the moon at an angle in degrees, nil to let go (simulator only)
    var testMoon: Double?
    /// places in the world you haven't stamped: one star each in the night
    var placesLeft: Int {
        let s = stamped
        guard ready, let w = world else { return 0 }
        return max(0, w.countable - s.count)
    }

    // MARK: the camera
    @ObservationIgnored var c = SIMD2<Double>(500, 244)
    @ObservationIgnored var k: Double = 1.8
    @ObservationIgnored var view = CGSize(width: 402, height: 874)
    /// where the chrome sits on this phone (the open map is between the head and the sheet)
    @ObservationIgnored var layout = Layout.placeholder
    @ObservationIgnored private(set) var homeX: Double = 500
    /// true while a frame is wanted (the Metal view goes to 30 a second when nothing moves)
    @ObservationIgnored var needsFrame = true
    /// THE PLACE UNDER A FINGER (screen point): a diamond within its reach, else the smallest place under it in what is
    /// drawn (the detailed tiles, or the world's shapes when zoomed out); a fingertip is about 10 points, so a piece
    /// smaller than that within it is what was meant
    func hit(at p: CGPoint) -> Int? {
        guard let w = world else { return nil }
        let m = mapPoint(p)
        let mp = SIMD2(Float(m.x), Float(m.y)), reach = Float(10 / k), tiny = Float(14 / k)
        if let d = diamond(at: p) { return d }
        if let det = details, det.drawsTiles { return det.place(at: mp, reach: reach, tiny: tiny) }
        return w.place(at: mp, reach: reach, tiny: tiny)
    }
    /// HOW DARK A STAR HAS TO BE TO BE SEEN HERE: 0 over the sea, where white light shows; a little over a wished
    /// (blue) place; more over a stamped (lime) place; most over the white land. From what is drawn at this screen
    /// point (the detailed tiles when they are shown, else the world's shapes), with no finger's reach.
    func groundDark(at p: CGPoint) -> Double {
        guard let w = world else { return 0 }
        let m = mapPoint(p)
        let mp = SIMD2(Float(m.x), Float(m.y))
        let i: Int?
        if let det = details, det.drawsTiles { i = det.place(at: mp, reach: 0, tiny: 0) } else { i = w.place(at: mp) }
        guard let i else { return 0 }
        if showsStamped && stamped.contains(i) { return 0.45 }
        if wished.contains(i) { return 0.15 }
        return 0.8
    }
    /// the detailed maps (set by the renderer), so a touch is answered from what is drawn
    @ObservationIgnored weak var details: DetailMaps?
    /// the camera's level for the zoom column: at home or not
    private(set) var atHome = true
    /// as close as it goes: the plus dims to 50% like the minus does at home
    private(set) var atMax = false
    /// the world at home, nothing to reset: the reset dims to 50% (BUILD-BOOK 1.9)
    private(set) var atRest = true

    @ObservationIgnored private var flight: (from: SIMD3<Double>, to: SIMD3<Double>, t: Double, dur: Double, glide: Bool)?
    @ObservationIgnored var touching = false

    static let north = 2.2081   // map y of 83.64°N, the northernmost land (Greenland)

    // MARK: loading
    func load() async {
        guard world == nil else { return }
        let loaded: (World, Relief)? = await Task.detached(priority: .userInitiated) {
            guard let w = try? World.load(), let r = try? Relief.load() else { return nil }
            return (w, r)
        }.value
        guard let (w, r) = loaded else { return }
        world = w
        relief = r
        let demo = DemoAccount.make(w)
        stamped = demo.stamped
        wished = demo.wished
        homeX = Self.homeLongitudeX(w)
        tinyPlaces = w.places.indices.filter { w.places[$0].tiny && !w.places[$0].junk }
        // each tiny place's biggest piece across, in map units (the Vatican's is a speck)
        var big = [Double](repeating: 0, count: w.places.count)
        for (u, owner) in w.unitOwner.enumerated() where owner >= 0 {
            for ri in w.unitRings[u] {
                let b = w.rings[ri].box
                big[owner] = max(big[owner], Double(max(b.z - b.x, b.w - b.y)))
            }
        }
        // the size you actually see when close: the detailed map's (the world file's Vatican is a fifth of its true
        // 1 km, so its diamond went on while its own shape was already showing beside it)
        tinyBig = w.places.indices.map { i in w.places[i].dsz ?? (big[i] > 0 ? big[i] : 0.028) }
        goHome(animated: false)
        ready = true
        needsFrame = true
    }

    /// Home is centred on the phone's region's longitude, else 12°E.
    static func homeLongitudeX(_ w: World) -> Double {
        if let r = Locale.current.region?.identifier.lowercased(), let i = w.placeIndex[r] {
            return w.places[i].c[0]
        }
        return Double(EqualEarth.project(lon: 12, lat: 0).x)
    }

    // MARK: the small places
    /// the places too small to see at the world's size, drawn as diamonds
    @ObservationIgnored private(set) var tinyPlaces: [Int] = []
    /// one zoom for all of them: past it they are big enough to see as themselves
    var diamondsShown: Bool { k < kMin * 6 }
    @ObservationIgnored private(set) var tinyBig: [Double] = []
    /// THE DIAMONDS GO TOGETHER, except a place that would be lost when they go: one still under 6 points across at
    /// that zoom keeps its diamond until its own shape is 6 points across, so there is always something to see and
    /// touch
    func showsDiamond(_ i: Int) -> Bool {
        if diamondsShown { return true }
        guard i < tinyBig.count else { return false }
        return tinyBig[i] * kMin * 6 < 6 && tinyBig[i] * k < 6
    }
    var anyDiamond: Bool { diamondsShown || tinyPlaces.contains { showsDiamond($0) } }
    /// the diamond under a point of the screen, if they are shown
    func diamond(at s: CGPoint) -> Int? {
        guard let w = world else { return nil }
        var best: (Int, Double)?
        for i in tinyPlaces where showsDiamond(i) {
            let pl = w.places[i]
            let sx = (pl.c[0] - c.x) * k + Double(view.width) / 2, sy = (pl.c[1] - c.y) * k + Double(view.height) / 2
            let d = hypot(sx - Double(s.x), sy - Double(s.y))
            if d < 14, d < (best?.1 ?? 1e9) { best = (i, d) }
        }
        return best?.0
    }

    // MARK: limits
    var bottom: Double { Double(world?.height ?? 486.717) }
    var worldKMin: Double { Double(view.height) / (bottom - Self.north) }
    /// as far out as the fingers go: the world, or on a continent the continent's own view (the old atRest)
    var kMin: Double { continentK ?? worldKMin }
    /// on a continent: its view's zoom, which never changes with the sheet (the old continentW)
    @ObservationIgnored private(set) var continentK: Double?
    /// on a continent: its frame, the view held inside it
    @ObservationIgnored private(set) var continentFrame: SIMD4<Double>?
    /// on a continent: the camera height that puts it in the middle of the room above the 50% sheet
    @ObservationIgnored private(set) var continentY: Double?
    /// the continent the map draws (the rest of the world in the flat blue): it changes at the turn of a flight from
    /// one continent to another, at the world between them (the old renderer.setContinent)
    @ObservationIgnored private(set) var drawnContinent: String?
    /// as close as the old app: a quarter of a map unit across the screen, about 10 km; the slices carry the detail
    /// that far
    var kMax: Double { Double(view.width) / 0.25 }

    /// the centre that keeps the land on screen, at scale `k`; on a continent its view is held to the continent's frame
    /// side to side (the old MapCamera.cbox)
    func clamped(_ p: SIMD2<Double>, _ k: Double) -> SIMD2<Double> {
        let hw = Double(view.width) / 2 / k, hh = Double(view.height) / 2 / k
        // sideways the sea goes on past the world's edge (the relief runs 90° further each way), so the pieces moved
        // over the date line beside their country (Chukotka's tip, the Aleutians) can be seen whole: the camera may go
        // a quarter of a screen past either edge
        var lo = hw / 2, hi = 1000 - hw / 2
        if let f = continentFrame {
            let fx0 = max(0, f.x), fx1 = min(1000, f.z)
            if fx1 - fx0 >= 2 * hw { lo = max(lo, fx0 + hw); hi = min(hi, fx1 - hw) } else { lo = (fx0 + fx1) / 2; hi = lo }
            lo = min(max(lo, hw), 1000 - hw); hi = max(min(hi, 1000 - hw), lo)
        }
        let x = min(max(p.x, lo), hi)
        var y0 = Self.north + hh, y1 = bottom - hh
        if y0 > y1 { y0 = (Self.north + bottom) / 2; y1 = y0 }
        // on a continent's map the view is held to the continent, not the world (the old cbox): it may sit past the
        // world's edge, where everything is the same flat blue, so the continent is in the middle of the room
        if let cy = continentY { y0 = min(y0, cy); y1 = max(y1, cy) }
        return SIMD2(x, min(max(p.y, y0), y1))
    }

    func mapPoint(_ s: CGPoint) -> SIMD2<Double> {
        c + (SIMD2(Double(s.x), Double(s.y)) - SIMD2(Double(view.width), Double(view.height)) / 2) / k
    }

    // MARK: fingers (from the Metal view, which owns the touches: one owner, so nothing ever jumps) The old app's rule:
    // the camera is held inside the world on every touch, even with a pinch held; there is no rubber band past the
    // north edge, past Antarctica or out past the world's size.

    /// a finger is down: anything moving stops where it is
    func grab() {
        // halfway from one continent to another: the new one is there at once, where the camera is
        if let then = afterFlight { afterFlight = nil; then() }
        flight = nil; touching = true
        needsFrame = true
    }
    /// moved by the fingers, in points
    func pan(by d: SIMD2<Double>) {
        c = clamped(c - d / k, k)
        updateHome()
        needsFrame = true
    }
    /// zoomed by the fingers about a point on the screen (the point under them stays under them)
    func zoom(by f: Double, about s: CGPoint) {
        let anchor = mapPoint(s)
        let nk = min(kMax, max(kMin, k * f))
        let sp = SIMD2(Double(s.x), Double(s.y)) - SIMD2(Double(view.width), Double(view.height)) / 2
        k = nk
        c = clamped(anchor - sp / nk, nk)
        updateHome()
        needsFrame = true
    }
    /// the fingers are off. A quick one-finger flick glides on (never after a pinch); the glide's end is inside the world
    func release(velocity v: SIMD2<Double>?) {
        touching = false
        if let v, simd_length(v) > 250 {
            let target = clamped(c - v * 0.26 / k, k)
            fly(to: target, k: k, dur: 0.62, glide: true)
        }
        needsFrame = true
    }

    func doubleTap(at s: CGPoint) {
        let target = min(kMax, k * 1.8)
        let p = mapPoint(s)
        let sp = SIMD2(Double(s.x), Double(s.y)) - SIMD2(Double(view.width), Double(view.height)) / 2
        fly(to: clamped(p - sp / target, target), k: target, dur: 0.45)
    }

    // MARK: the zoom column
    /// held plus (1) or minus (-1), 0 when not held; and how long it has been held
    @ObservationIgnored var holdZoom: Int = 0 { didSet { if holdZoom != oldValue { holdTime = 0; needsFrame = true } } }
    @ObservationIgnored private var holdTime: Double = 0
    func zoomIn() {
        let t = min(kMax, k * 1.6); fly(to: clamped(c, t), k: t, dur: 0.45)
    }
    func zoomOut() {
        let t = max(kMin, k / 1.6); fly(to: clamped(c, t), k: t, dur: 0.45)
    }
    /// the continent picked from its planet, nil for the world: the caption names it and counts it
    var continent: String?

    /// your count and the total, for the world or the picked continent
    var count: (n: Int, of: Int) {
        // read the observed values first, so a view that asks before the world has loaded still updates when it does
        let s = stamped, k0 = continent
        guard ready, let w = world else { return (0, 263) }
        guard let k = k0 else { return (s.count, w.countable) }
        // the old Cosmos.share: the continent's members (a country across two counts in both)
        var n = 0, of = 0
        for i in w.places.indices where w.inCont(i, k) { of += 1; if stamped.contains(i) { n += 1 } }
        return (n, of)
    }

    func goHome(animated: Bool = true) {
        continent = nil
        offContinent()
        let target = clamped(SIMD2(homeX, (Self.north + bottom) / 2), worldKMin)
        if animated { fly(to: target, k: worldKMin, dur: Self.flight) } else { k = worldKMin; c = target; updateHome() }
    }
    private func offContinent() {
        drawnContinent = nil; continentFrame = nil; continentK = nil; continentY = nil
        updateHome()
        needsFrame = true
    }
    /// A search result: the place fills the open map's width, 16 points from each side, or its height if it is a tall
    /// one, centred between the head and the sheet's top as it is now; a tiny place is shown among its neighbours, not
    /// blown up. It darkens for a moment so the eye finds it (BUILD-BOOK 1.10).
    func show(place i: Int, sheetTop: CGFloat? = nil) {
        guard let w = world else { return }
        let p = w.places[i]
        if continent != nil || drawnContinent != nil { continent = nil; offContinent() }
        let W = Double(view.width)
        let top = Double(layout.headBottom) + 8, bottom = Double(sheetTop ?? layout.top(.quarter)) - 12
        let roomH = max(80, bottom - top)
        var mid = SIMD2(p.c[0], p.c[1])
        var target: Double
        if !p.tiny, let f = w.frame(of: i) {
            let fw = max(0.05, Double(f.z - f.x)), fh = max(0.05, Double(f.w - f.y))
            target = min((W - 32) / fw, roomH / fh)
            mid = SIMD2(Double(f.x + f.z) / 2, Double(f.y + f.w) / 2)
        } else {
            let ext = max(2.0, p.ext ?? 10)
            target = W * 0.35 / (ext * 2.8)
        }
        if p.tiny { target = min(target, kMin * 9) }
        target = min(kMax, max(kMin, target))
        let centre = mid + SIMD2(0, (Double(view.height) / 2 - (top + bottom) / 2) / target)
        #if DEBUG
        NSLog("wya show %@ frame %@ k %.3f (kMin %.3f) room %.0f-%.0f", p.id, String(describing: w.frame(of: i)), target, kMin, top, bottom)
        #endif
        fly(to: clamped(centre, target), k: target, dur: 0.8)
        flash(i)
    }

    /// the place darkened for 1.2 s, as under a finger
    private func flash(_ i: Int) {
        pressed = i
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            if let self, self.pressed == i, !self.touching { self.pressed = nil }
        }
    }

    /// the old CameraCurve.flightDuration: the critically damped 0.44 s spring's settling time × 0.9
    static let flight = 0.58

    /// THE CONTINENT SWITCH (the old MapView.setContinent and MapCamera.onContinent, as they were): - its view is the
    /// old contView frame, fitted to fill the room above the 50% sheet (its height, or for a tall one its width; a wide
    /// one runs past the screen's sides), its middle in the middle of that room - the map stays put under the sheet
    /// after that - the rest of the world and the sea go into the one flat blue as the camera goes in (the renderer) -
    /// from one continent to another the camera goes out to the world first, the rest coming back, then into the new
    /// one; picked again on the way, the last pick wins
    func show(continent k: String) {
        if k == "World" { goHome(); return }
        guard let w = world else { return }
        continent = k
        guard let f = w.contViews[k] else {
            // Antarctica: its own polar map is not built yet; the rest goes and the world stays where it is
            offContinent(); drawnContinent = k
            return
        }
        let W = Double(view.width)
        let top = Double(layout.headBottom) + 22, bottom = Double(layout.top(.half)) - 14
        let roomH = max(80, bottom - top)
        let s = max(W / (f.z - f.x), roomH / (f.w - f.y))
        let mid = SIMD2((f.x + f.z) / 2, (f.y + f.w) / 2)
        // in the middle of the room, always: zoomed in as far as it takes for the continent's middle to sit in the
        // room's middle with the screen still inside the world, so nothing past the world's edge is ever shown
        let H = Double(view.height), roomMid = (top + bottom) / 2
        let kTop = roomMid / max(1, mid.y - Self.north)
        let kBottom = (H - roomMid) / max(1, self.bottom - mid.y)
        let nk = min(kMax, max(worldKMin, W / min(W / s, 1000), kTop, kBottom))
        let centre = mid + SIMD2(0, (Double(view.height) / 2 - (top + bottom) / 2) / nk)
        #if DEBUG
        NSLog("wya continent %@ frame %.1f %.1f %.1f %.1f k %.3f -> %.3f view %.0fx%.0f room %.0f-%.0f", k, f.x, f.y, f.z, f.w, self.k, nk, view.width, view.height, top, bottom)
        #endif
        let go = { [weak self] in
            guard let self else { return }
            self.drawnContinent = k; self.continentFrame = f; self.continentK = nk
            self.updateHome()
            self.fly(to: self.clamped(centre, nk), k: nk, dur: Self.flight)
        }
        if let was = drawnContinent, was != k, was != "Antarctica" {
            // out to the world, the rest coming back, then in
            offContinent()
            let home = clamped(SIMD2(homeX, (Self.north + self.bottom) / 2), worldKMin)
            fly(to: home, k: worldKMin, dur: Self.flight, then: go)
        } else {
            go()
        }
    }

    #if DEBUG
    /// test only: the camera on a longitude and latitude at a zoom (in multiples of the world's size)
    func look(lon: Double, lat: Double, zoom: Double) {
        let q = EqualEarth.project(lon: lon, lat: lat)
        let t = min(kMax, max(kMin, kMin * zoom))
        fly(to: clamped(SIMD2(Double(q.x), Double(q.y)), t), k: t, dur: 0.5)
    }
    #endif

    private func fly(to p: SIMD2<Double>, k nk: Double, dur: Double, glide: Bool = false, then: (() -> Void)? = nil) {
        flight = (SIMD3(c.x, c.y, log(k)), SIMD3(p.x, p.y, log(nk)), 0, dur, glide)
        afterFlight = then
        needsFrame = true
    }
    /// what happens when this flight lands (the second half of a continent-to-continent move)
    @ObservationIgnored private var afterFlight: (() -> Void)?

    private func updateHome() {
        let h = k <= kMin * 1.01
        if h != atHome { atHome = h }
        let m = k >= kMax * 0.99
        if m != atMax { atMax = m }
        // at the world's size, on the world, centred where home puts it
        let hx = clamped(SIMD2(homeX, (Self.north + bottom) / 2), worldKMin).x
        let r = continent == nil && drawnContinent == nil && k <= worldKMin * 1.01 && abs(c.x - hx) < 0.5
        if r != atRest { atRest = r }
    }

    // MARK: every frame
    /// moves what moves; returns true while something still does
    func step(_ dt: Double) -> Bool {
        // HOLDING PLUS OR MINUS: the zoom keeps going about the screen's middle, gently faster the longer it is held,
        // from one doubling a second to three at 1.2 s, until the limit or the finger lifts
        if holdZoom != 0 {
            flight = nil
            holdTime += dt
            let rate = (1 + 2 * Flow.smooth(0, 1.2, CGFloat(holdTime))) * log(2.0)
            let before = k
            zoom(by: exp(Double(holdZoom) * Double(rate) * min(dt, 1.0 / 30)),
                 about: CGPoint(x: view.width / 2, y: view.height / 2))
            if k == before { holdZoom = 0 }
            return true
        }
        guard var f = flight else { return false }
        // a flight is seen whole: a slow frame is a pause, never a jump
        f.t = min(1, f.t + min(dt, 1.0 / 30) / f.dur)
        // a glide slows to a stop; any other flight is the old camera curve (critically damped, 0.44 s)
        let e: Double
        if f.glide { e = 1 - pow(1 - f.t, 3.2) } else {
            let w0 = 2 * Double.pi / 0.44, t = f.t * 0.646
            e = f.t >= 1 ? 1 : 1 - exp(-w0 * t) * (1 + w0 * t)
        }
        // the old ZoomPath.even: the zoom changes by the same factor each moment, and the point of the map that is in
        // the same place on the screen in both views stays there all the way
        let ka = exp(f.from.z), kb = exp(f.to.z)
        let nk = exp(f.from.z + (f.to.z - f.from.z) * e)
        let ca = SIMD2(f.from.x, f.from.y), cb = SIMD2(f.to.x, f.to.y)
        if abs(kb - ka) / ka > 1e-4 {
            let fixed = (cb * kb - ca * ka) / (kb - ka)
            c = clamped(fixed - (fixed - ca) * (ka / nk), nk)
        } else {
            c = clamped(ca + (cb - ca) * e, nk)
        }
        k = nk
        updateHome()
        if f.t >= 1 {
            flight = nil
            let then = afterFlight
            afterFlight = nil
            then?()
        } else {
            flight = f
        }
        return true
    }
}

/// Equal Earth (Šavrič, Patterson, Jenny 2018), the same numbers as the old app and tools/prep.py, into the
/// 1000-wide map box.
nonisolated enum EqualEarth {
    static let A1 = 1.340264, A2 = -0.081106, A3 = 0.000893, A4 = 0.003796
    static let M = 3.0.squareRoot() / 2
    static func raw(_ lon: Double, _ lat: Double) -> (Double, Double) {
        let l = lon * .pi / 180, p = lat * .pi / 180
        let th = asin(M * sin(p)), t2 = th * th, t6 = t2 * t2 * t2
        return (l * cos(th) / (M * (A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2))),
                th * (A1 + A2 * t2 + t6 * (A3 + A4 * t2)))
    }
    static let RX = raw(180, 0).0
    static let RY = raw(0, 90).1
    static let S = 1000 / (2 * RX)
    static func project(lon: Double, lat: Double) -> SIMD2<Float> {
        let (x, y) = raw(lon, lat)
        return SIMD2(Float((x + RX) * S), Float((RY - y) * S))
    }
    /// the world's width along the parallel at map y (360° there): the shift between the world and its copy past the
    /// date line (the same as wrapStep in MapShaders)
    static func wrapStep(y: Double) -> Double {
        let target = RY - y / S
        var th = target / A1
        for _ in 0 ..< 6 {
            let t2 = th * th, t6 = t2 * t2 * t2
            th -= (th * (A1 + A2 * t2 + t6 * (A3 + A4 * t2)) - target) / (A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2))
        }
        th = min(max(th, -Double.pi / 3), Double.pi / 3)
        let t2 = th * th, t6 = t2 * t2 * t2
        return 2 * Double.pi * cos(th) / (M * (A1 + 3 * A2 * t2 + t6 * (7 * A3 + 9 * A4 * t2))) * S
    }
}

/// THE DEMO ACCOUNT: there is no stamping yet (a tap opens the passport in the next build), so the map would be
/// all plain and the count 0. Until then the app starts with the same 34 stamped and 6 wished countries the
/// composition used, so lime and the count can be judged. Remove when stamping lands.
nonisolated enum DemoAccount {
    static let stampedIDs = ["fr", "es", "pt", "it", "gr", "tr", "ma", "eg", "de", "gb", "ch", "at", "hr", "nl", "be", "ie",
                             "no", "se", "dk", "pl", "cz", "tn", "jo", "il", "ae", "in", "th", "jp", "us", "br", "ar", "za",
                             "ke", "tz"]
    static let wishedIDs = ["na", "is", "ir", "et", "mg", "fi"]
    static func make(_ w: World) -> (stamped: Set<Int>, wished: Set<Int>) {
        (Set(stampedIDs.compactMap { w.placeIndex[$0] }), Set(wishedIDs.compactMap { w.placeIndex[$0] }))
    }
}

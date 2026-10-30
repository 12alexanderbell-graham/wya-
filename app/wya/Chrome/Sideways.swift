import SwiftUI

/// SIDEWAYS FULL SCREEN (Part 1.11, A1.14): the map alone, landscape, bigger. The app stays portrait; the turn is ours.
/// Enter: every card and sheet over the map closes first, then the head slides up past the top edge, the zoom column
/// off the right edge and the water pours into the capsule as the capsule slides down past the bottom edge (chrome
/// curve); when the chrome is half way the map turns a quarter about the screen's centre (0.5 s), drawn into a square
/// the size of the screen's diagonal so no corner is ever empty, and the camera frames the world (or the continent)
/// for landscape in the same move; at rest it is drawn at landscape size (the same content); then one row of marks
/// (plus, minus, reset, out of full screen) slides in along the landscape bottom edge, 0.05 s apart, each glyph upright
/// in landscape. Leave: the reverse, the camera framing portrait as it turns back; through both turns the screen never
/// shows past the world's top or bottom edge.
@Observable @MainActor
final class Sideways {
    static let shared = Sideways()

    /// anything but plain portrait (entering, sideways, leaving)
    private(set) var on = false
    /// the head, the column and the water away
    private(set) var chromeOut = false
    /// the map at its quarter turn
    private(set) var turned = false
    /// the map drawn into the diagonal square (while it turns)
    private(set) var square = false
    /// the map drawn at landscape size (at rest sideways)
    private(set) var landscape = false
    /// the four marks in (plus, minus, reset, out)
    private(set) var marks = [false, false, false, false]
    /// -1: north toward the screen's left edge (the phone turned clockwise); 1: toward the right (counterclockwise)
    private(set) var dir: Double = -1

    var atRest: Bool { on && landscape }
    #if DEBUG
    /// a frame of the turn held still (0 to 1), drawn into the diagonal square, for the frame checks
    var testTurn: Double? { didSet { square = testTurn != nil } }
    #endif
    /// the map's turn now, in degrees
    var angle: Double {
        #if DEBUG
        if let t = testTurn { return 90 * dir * t }
        #endif
        if let t = turnAt { return 90 * dir * t }
        return turned ? 90 * dir : 0
    }
    /// the turn now (0 upright, 1 sideways) while it runs, driven frame by frame with the camera
    private(set) var turnAt: Double?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var linkTarget: TurnTick?
    @ObservationIgnored private var turnStart: CFTimeInterval = 0
    @ObservationIgnored private var turnStep: ((Double) -> Void)?
    @ObservationIgnored private var turnEnd: (() -> Void)?
    /// the turn's length (Reduce Motion: shorter, never a cut)
    private var turnDur: Double { Motion.reduce ? 0.3 : 0.5 }

    /// THE TURN AND THE CAMERA AS ONE MOVE (two actions at the same time, never one after the other): each frame the map's angle and the camera take the same eased step, so the framing happens while it
    /// turns, and the camera is held so the screen never shows past the world's top or bottom edge
    private func runTurn(step: @escaping (Double) -> Void, end: @escaping () -> Void) {
        link?.invalidate()
        turnStep = step; turnEnd = end
        turnStart = CACurrentMediaTime()
        let t = TurnTick { [weak self] in self?.tick() }
        linkTarget = t
        let l = CADisplayLink(target: t, selector: #selector(TurnTick.fire))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        tick()
    }
    private func tick() {
        let x = min(1, (CACurrentMediaTime() - turnStart) / turnDur)
        // ease in and out (a smooth start and a calm landing)
        let p = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        turnStep?(p)
        if x >= 1 {
            link?.invalidate(); link = nil; linkTarget = nil
            let e = turnEnd; turnStep = nil; turnEnd = nil
            e?()
        }
    }
    private func stopTurn() {
        link?.invalidate(); link = nil; linkTarget = nil; turnStep = nil; turnEnd = nil
    }
    @ObservationIgnored private var job = 0
    @ObservationIgnored private var stopBefore: Water.Stop = .quarter
    @ObservationIgnored private weak var water: Water?
    @ObservationIgnored private weak var map: MapController?
    @ObservationIgnored private var watching: NSObjectProtocol?

    /// the sideways mark (portrait)
    func enter(water w: Water, head: HeadState, map m: MapController, close: () -> Void) {
        guard !on else { return }
        // blocked while uploads are finding or reviewing (9.3 to 9.5): the water is theirs
        if w.upload { Feel.refuse(); return }
        Feel.tap()
        close()
        head.searching = false; head.toolsOpen = false; head.putAway()
        water = w; map = m
        stopBefore = w.stop == .closed ? .quarter : w.stop
        let o = UIDevice.current.orientation
        dir = o == .landscapeLeft ? 1 : -1
        on = true
        job += 1
        let me = job
        w.go(.closed)
        withAnimation(Motion.chrome) { chromeOut = true }
        // the turn starts when the chrome is half way (0.19 s); the camera frames the world (or your continent)
        // sideways during the turn itself
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [self] in
            guard me == job else { return }
            let L = w.layout
            let portrait = CGSize(width: L.W, height: L.H)
            let from = (c: m.c, k: m.k)
            let to = m.target(for: CGSize(width: L.H, height: L.W)) { m.frameSideways() } ?? from
            square = true
            turnAt = 0
            runTurn(step: { [self] p in
                turnAt = p
                m.turnCamera(from: from, to: to, p: p, deg: 90 * p, screen: portrait)
            }, end: { [self] in
                guard me == job else { return }
                // the same picture at landscape size; nothing reloads
                turned = true; turnAt = nil
                square = false; landscape = true
                Feel.land(speed: 0)
                for k in 0 ..< 4 {
                    // the one nearest the corner first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(3 - k)) { [self] in
                        guard me == job else { return }
                        withAnimation(Motion.chrome) { marks[k] = true }
                    }
                }
            })
        }
        watch()
    }

    /// out of full screen: the mark, turning the phone back to portrait, a link, leaving the tab
    func leave(feel: Bool = true) {
        guard on else { return }
        if feel { Feel.tap() }
        job += 1
        let me = job
        stopWatching()
        withAnimation(Motion.quick) { marks = [false, false, false, false] }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            guard me == job else { return }
            let done = { [self] in
                guard me == job else { return }
                square = false
                on = false
                Feel.land(speed: 0)
                // the sheet's top as it is now (it was not followed while sideways)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                    guard me == job, let m = map, let w = water else { return }
                    m.sheetMoved(top: w.form().top)
                }
            }
            landscape = false
            // left before the turn began (a link right after entering): nothing to turn back, so it ends now
            guard turned, let m = map, let w = water else {
                stopTurn(); turnAt = nil
                // a camera the turn left part way: back inside the world for portrait
                if let m = map { if m.k < m.worldKMin { m.goHome() } else { m.holdInside() } }
                withAnimation(Motion.chrome) { chromeOut = false }
                water?.go(stopBefore)
                done(); return
            }
            let L = w.layout
            let portrait = CGSize(width: L.W, height: L.H)
            let from = (c: m.c, k: m.k)
            // where portrait puts it: a continent framed again for portrait (its room above the sheet); the world home if
            // it was zoomed out further than portrait allows, else the place you were looking at
            let to = m.target(for: portrait) {
                if let sc = m.regionScene { m.frameRegion(sc.place) }
                else if let k = m.continent ?? m.drawnContinent, m.world?.contViews[k] != nil { m.show(continent: k) }
                else if m.k < m.worldKMin { m.goHome() } else { m.holdInside() }
            } ?? from
            square = true
            turned = false
            turnAt = 1
            var chromeBack = false
            runTurn(step: { [self] p in
                turnAt = 1 - p
                m.turnCamera(from: from, to: to, p: p, deg: 90 * (1 - p), screen: portrait)
                // the chrome comes back as the turn passes half way
                if p >= 0.5, !chromeBack {
                    chromeBack = true
                    withAnimation(Motion.chrome) { chromeOut = false }
                    water?.go(stopBefore)
                }
            }, end: { [self] in
                turnAt = nil
                done()
            })
        }
    }

    /// turning the phone back to portrait leaves sideways (the interface itself stays portrait)
    private func watch() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        watching = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated {
                let s = Sideways.shared
                if s.atRest, UIDevice.current.orientation == .portrait { s.leave() }
            }
        }
    }
    private func stopWatching() {
        if let w = watching { NotificationCenter.default.removeObserver(w) }
        watching = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
}

/// THE SIDEWAYS MARKS: plus, minus, reset and out of full screen, one row along the landscape bottom edge, centred on
/// it, each glyph turned to read upright in landscape; no lock (Part 1.11)
struct SidewaysMarks: View {
    let map: MapController
    let L: Layout
    @State private var side = Sideways.shared

    var body: some View {
        let d = side.dir
        // the landscape bottom edge is the screen's right edge (north to the left) or its left edge
        let x = d < 0 ? L.W - L.side - 22 : L.side + 22
        // along it, landscape left to right: plus, minus, reset, out (landscape right is the screen's top when north
        // is to the left)
        let ys: [CGFloat] = [66, 22, -22, -66].map { L.H / 2 + (d < 0 ? $0 : -$0) }
        ZStack(alignment: .topLeading) {
            mark(0, "plus", "Zoom in", dim: map.atMax) { map.zoomIn() }.position(x: x, y: ys[0])
            mark(1, "minus", "Zoom out", dim: map.atHome) { map.zoomOut() }.position(x: x, y: ys[1])
            mark(2, "reset", map.regionScene != nil ? "Back to the country" : "Back to the world", dim: map.regionScene == nil && map.atRest) {
                if map.regionScene != nil { map.frameSideways() } else { map.closePlace(); map.goHome() }
            }.position(x: x, y: ys[2])
            mark(3, "unfullscreen", "Out of full screen", dim: false) { side.leave(feel: false) }.position(x: x, y: ys[3])
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
    }

    private func mark(_ k: Int, _ key: String, _ label: String, dim: Bool, _ act: @escaping () -> Void) -> some View {
        Button {
            if dim { Feel.refuse(); return }
            Feel.tap(); act()
        } label: {
            LimitIcon(key: key, ink: Palette.ink, dim: dim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(90 * side.dir))
        }
        .buttonStyle(BareButton())
        .accessibilityLabel(label)
        // slides in from the landscape bottom edge, at its own size
        .offset(x: side.marks[k] ? 0 : (side.dir < 0 ? 70 : -70))
        .allowsHitTesting(side.marks[k])
    }
}

/// the display link's target (a class the link may hold without holding Sideways)
private final class TurnTick: NSObject {
    let f: () -> Void
    init(_ f: @escaping () -> Void) { self.f = f }
    @objc func fire() { MainActor.assumeIsolated { f() } }
}

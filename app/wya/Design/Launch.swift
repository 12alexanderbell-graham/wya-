import SwiftUI

/// THE LAUNCH (Part 12.3, 12.4): a real loading screen, very simple, with no lag and no circles growing or shrinking.
/// It is the old app's first page
/// (OnboardingView.hello, SLICE 175), without its words and buttons: our cream, the logo big in the middle with its
/// light going round and round, the planet turning, and the logo's light thrown over the whole page by the old app's
/// own shader (LogoGlassSurface, the living field split by a giant planet's day and night). The light is drawn on its
/// own thread. When the map is ready the whole screen fades away in one piece, the map already in place under it.
@MainActor @Observable
final class Launch {
    static let shared = Launch()
    /// how far the loading screen has faded away (0 whole, 1 gone)
    var reveal: CGFloat = 0
    /// the loading screen has gone (it stops drawing)
    var done = false
    /// touches are taken once the chrome is at rest
    var settled = false
    /// THE EARTH IN THE COSMOS, on screen (global points), while the loading screen is up and the system shows (the
    /// water at 50%); the logo's sphere lands on it as the screen lifts. nil: the system is hidden, the screen just lifts
    var earth: CGRect?
    /// how far the logo's sphere has gone to the Earth (0 in the middle of the page, 1 on the Earth)
    var landing: CGFloat = 0
    /// the screen began to lift with the Earth showing, so the sphere goes to it (decided once, as it starts to lift:
    /// the Earth coming into view after that changes nothing)
    var lands = false
    /// when the logo's film started moving (the page's light turns from then, with it)
    var turnStart: CFTimeInterval?
    /// seconds the light takes to go once round
    static let turn: Double = 2.7
    /// the logo's planet across, on this screen: big, a little over a third of the width (the old first page's was a
    /// third, up to 140 pt; this page has nothing else on it)
    static func planet(_ W: CGFloat) -> CGFloat { min(W * 0.4, 190) }
    /// when this launch began (for the launch's timing in the log)
    static let startTime = CACurrentMediaTime()
    init() { _ = Self.startTime }
}

/// THE LOADING SCREEN: faded by `reveal`
struct LoadingScreen: View {
    var reveal: CGFloat
    @State private var launch = Launch.shared
    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let planet = Launch.planet(W)
            let mark = planet * 1024 / 700
            let c = CGPoint(x: W / 2, y: H / 2)
            // THE EXIT: with the Cosmos showing, the page and its light go while the sphere goes on to the Earth's place
            // at the Earth's size and becomes it; without, the whole screen lifts in one piece as before
            let earth = launch.lands ? launch.earth : nil
            let t = launch.landing
            let to = earth.map { CGPoint(x: $0.midX, y: $0.midY) } ?? c
            let at = CGPoint(x: c.x + (to.x - c.x) * t, y: c.y + (to.y - c.y) * t)
            let size = 1 + ((earth.map { $0.width / planet } ?? 1) - 1) * t
            ZStack {
                ZStack {
                    Palette.cream
                    // the logo's light over the whole page (the old first page's helloSpot, round the logo alone)
                    LogoGlassSurface(phase: GlassRender.rest, spot: Self.spot(c, planet: planet, size: g.size),
                                     still: Motion.reduce, turn: Launch.turn, turnStart: launch.turnStart)
                }
                .opacity(earth == nil ? 1 : 1 - reveal)
                // the logo at rest until its film is up, then the film turning on the video hardware (LogoTurn.swift)
                ZStack {
                    if launch.turnStart == nil { LogoMark(phase: GlassRender.rest) }
                    LogoTurnView { launch.turnStart = GlassRender.filmStart ?? CACurrentMediaTime() }
                }
                .frame(width: mark, height: mark)
                .scaleEffect(size)
                .position(at)
            }
            .frame(width: W, height: H)
            .opacity(earth == nil ? 1 - reveal : 1)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Loading")
        #if DEBUG
        .onAppear { NSLog("wya launch: loading screen up at %.3f s", CACurrentMediaTime() - Launch.startTime) }
        .onChange(of: launch.turnStart) { _, t in if let t { NSLog("wya launch: logo film turning from %.3f s (told at %.3f s)", t - Launch.startTime, CACurrentMediaTime() - Launch.startTime) } }
        #endif
    }

    static func spot(_ c: CGPoint, planet: CGFloat, size: CGSize) -> LogoLightSpot {
        let box = CGRect(x: c.x - planet / 2, y: c.y - planet / 2, width: planet, height: planet)
        let glow = CGRect(x: box.midX - box.width * 1.25, y: box.minY - box.height * 0.2,
                          width: box.width * 2.5, height: box.height * 1.4)
        return LogoLightSpot(centre: c, radius: (size.width * size.width + size.height * size.height).squareRoot() * 0.85,
                             glow: glow, strength: 0.85)
    }
}

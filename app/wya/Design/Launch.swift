import SwiftUI

/// THE LAUNCH (Part 12.3, 12.4): a real loading screen, very simple, with no lag and no circles growing or shrinking.
/// It is the old app's first page
/// (OnboardingView.hello, SLICE 175), without its words and buttons: our cream, his logo big in the middle with its
/// light going round and round, the planet turning, and the logo's light thrown over the whole page by the old app's
/// own shader (LogoGlassSurface, the living field split by a giant planet's day and night). The light is drawn on its
/// own thread. When the map is ready the whole screen lifts up and away in one piece, the map already in place under it
/// (author's default, asked).
@MainActor @Observable
final class Launch {
    static let shared = Launch()
    /// how far the loading screen has lifted away (0 whole, 1 gone), on the chrome curve
    var reveal: CGFloat = 0
    /// the loading screen has gone (it stops drawing)
    var done = false
    /// touches are taken once the chrome is at rest
    var settled = false
    /// when the logo's film started moving (the page's light turns from then, with it)
    var turnStart: CFTimeInterval?
    /// seconds the light takes to go once round
    static let turn: Double = 2.7
    /// the logo's planet across, on this screen: big, a little over a third of the width (the old first page's was a
    /// third, up to 140 pt; this page has nothing else on it)
    static func planet(_ W: CGFloat) -> CGFloat { min(W * 0.4, 190) }
}

/// THE LOADING SCREEN: lifted by `reveal` x its height
struct LoadingScreen: View {
    var reveal: CGFloat
    @State private var launch = Launch.shared
    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let planet = Launch.planet(W)
            let mark = planet * 1024 / 700
            let c = CGPoint(x: W / 2, y: H / 2)
            ZStack {
                Palette.cream
                // the logo's light over the whole page (the old first page's helloSpot, round the logo alone)
                LogoGlassSurface(phase: GlassRender.rest, spot: Self.spot(c, planet: planet, size: g.size),
                                 still: Motion.reduce, turn: Launch.turn, turnStart: launch.turnStart)
                // his logo at rest until its film is up, then the film turning on the video hardware (LogoTurn.swift)
                ZStack {
                    if launch.turnStart == nil { LogoMark(phase: GlassRender.rest) }
                    LogoTurnView { launch.turnStart = CACurrentMediaTime() }
                }
                .frame(width: mark, height: mark)
                .position(c)
            }
            .frame(width: W, height: H)
            .offset(y: -H * reveal)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    static func spot(_ c: CGPoint, planet: CGFloat, size: CGSize) -> LogoLightSpot {
        let box = CGRect(x: c.x - planet / 2, y: c.y - planet / 2, width: planet, height: planet)
        let glow = CGRect(x: box.midX - box.width * 1.25, y: box.minY - box.height * 0.2,
                          width: box.width * 2.5, height: box.height * 1.4)
        return LogoLightSpot(centre: c, radius: (size.width * size.width + size.height * size.height).squareRoot() * 0.85,
                             glow: glow, strength: 0.85)
    }
}

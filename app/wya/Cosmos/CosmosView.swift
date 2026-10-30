import SwiftUI

/// THE SYSTEM: the sun is your streak, the planets are the continents (Earth is the world), each planet's night side as
/// wide as the share of that continent you've stamped. At 50% they sit on one ring under the name and the number;
/// pulled to full the ring opens into eight orbits round the sun and they go round them. His rules it keeps: nothing
/// teleports, nothing flips places, nothing is cut. The ring is one body: the eight planets share one angle and keep
/// their places on it, so choosing one turns the whole ring the short way on a spring with no bounce, every planet
/// rolling as it travels. The orbits are drawn from the very numbers the planets sit on, so the lines open with them.
/// The moon sits where you leave it.
struct CosmosView: View {
    let water: Water
    let map: MapController
    let form: Water.Form

    // the ring: one angle on a spring (critically damped, the old app's 0.44 s)
    @State private var ringFrom: Double = 0
    @State private var ringTo: Double = 0
    @State private var ringV: Double = 0
    @State private var ringStart = Date.distantPast
    @State private var chosen = 2
    /// each planet's own turn so far (only the chosen one turns by itself), frozen where it was when it stopped
    @State private var ownSpin = Array(repeating: 0.0, count: 8)
    @State private var spinSince = Date()
    // the orbits going round at full
    @State private var fullSince: Date?
    @State private var orbitFrozen = Array(repeating: 0.0, count: 8)
    // the moon: its angle round the chosen planet, where you left it
    @State private var moonAngle: Double = CosmosView.stopAngle(0)
    @State private var moonHeld = false
    /// where the moon's tail ends: an angle that follows the moon's a little behind it, frame by frame
    @State private var trail = TrailFollower()
    /// how far the moon's ring and label are out (0 in the moon, 1 out), frame by frame inside the timeline
    @State private var heldTween = Tween(0)
    @State private var moonStop = 0
    @State private var start = Date()
    /// A2.10: the planet the moon goes into on a turn (the old chosen one), and whether the moon was already in when
    /// the turn began (then it stays in until the turn lands)
    @State private var moonFrom = 2
    @State private var moonStartsIn = false
    /// A2.13 / A2.14: the streak (the sun's size) and each planet's share (its night) ease to a new value over 0.6 s
    @State private var sunEase: Ease1?
    @State private var shareEase: [Ease1]?

    static let step = 2 * Double.pi / 8
    static let front = Double.pi / 2
    static var omega: Double { 2 * Double.pi / (Motion.reduce ? 0.28 : 0.44) }

    /// the moon's five stops: Both at the top
    static let stops = ["Both", "Stamped", "Stamped+", "Wishlist+", "Wishlist"]
    static func stopAngle(_ i: Int) -> Double { -Double.pi / 2 + Double(i) * (2 * Double.pi / 5) }
    static func nearestStop(_ a: Double) -> Int {
        var best = 0, bd = 9.0
        for i in 0 ..< 5 {
            var x = (stopAngle(i) - a).truncatingRemainder(dividingBy: 2 * .pi)
            if x > .pi { x -= 2 * .pi }; if x < -.pi { x += 2 * .pi }
            if abs(x) < bd { bd = abs(x); best = i }
        }
        return best
    }

    struct Planet { let k: String; let n: String; let size: CGFloat; let tex: String; let turn: Double; let au: Double; let yr: Double; let wide: Double }
    /// "mars = south america, venus = africa, oceania = neptune, antarctica = uranus, asia = jupiter, mercury = europe,
    /// saturn = north america", closest to furthest from the sun
    static let planets: [Planet] = [
        Planet(k: "Europe", n: "Mercury", size: 0.62, tex: "planet-mercury", turn: 62, au: 0.39, yr: 0.2408, wide: 0.383),
        Planet(k: "Africa", n: "Venus", size: 0.90, tex: "planet-venus", turn: 86, au: 0.72, yr: 0.6152, wide: 0.949),
        Planet(k: "World", n: "Earth", size: 1.00, tex: "planet-earth", turn: 44, au: 1.00, yr: 1.0, wide: 1),
        Planet(k: "South America", n: "Mars", size: 0.72, tex: "planet-mars", turn: 48, au: 1.52, yr: 1.8808, wide: 0.532),
        Planet(k: "Asia", n: "Jupiter", size: 1.55, tex: "planet-jupiter", turn: 34, au: 5.20, yr: 11.862, wide: 11.21),
        Planet(k: "North America", n: "Saturn", size: 1.35, tex: "planet-saturn", turn: 38, au: 9.58, yr: 29.457, wide: 9.45),
        Planet(k: "Antarctica", n: "Uranus", size: 1.05, tex: "planet-uranus", turn: 120, au: 19.2, yr: 84.011, wide: 4.01),
        Planet(k: "Oceania", n: "Neptune", size: 1.02, tex: "planet-neptune", turn: 56, au: 30.1, yr: 164.79, wide: 3.88),
    ]
    /// how far out each orbit is at full, 0.27 (Mercury, clear of the sun) to 1 (Neptune) (old app, Slice 126)
    static func orbit(_ i: Int) -> Double {
        let aup = planets.map { pow($0.au, 0.42) }
        let lo = aup.min()!, hi = aup.max()!
        return 0.27 + 0.73 * (0.75 * Double(i) / 7 + 0.25 * (aup[i] - lo) / (hi - lo))
    }
    /// Mercury goes round once in 20 s, the others by their years
    static func orbitSpeed(_ i: Int) -> Double { 2 * Double.pi / (20 * pow(planets[i].yr / planets[0].yr, 0.45)) }

    // MARK: where things are
    /// the room the system has: at 50% between the words and the tabs, at full the whole screen
    struct Room {
        var cx: CGFloat, cy: CGFloat
        var rx: CGFloat, ry: CGFloat       // the ring at 50%
        var rxw: CGFloat, ryw: CGFloat     // the outermost orbit at full
    }
    private func room() -> Room {
        let L = water.layout
        let p = form.page
        // at 50% the ring sits between the caption's foot (the top + 130) and the tabs; under 50% it stays there and
        // goes into the sun (A2.12: `sink`), never down over the tabs
        let halfTop = L.top(.half)
        let lo = halfTop + 130, hi = L.capsule.minY - 20
        let ringY = (lo + hi) / 2
        let cy = Flow.lerp(ringY, L.H * 0.5, p)
        let rx = min(L.W * 0.38, 178)
        let ry = min(rx * 0.5, (hi - lo) / 2 - 22)
        let rxw = min(L.W * 0.44, 206)
        let ryw = min(rxw * 0.5, L.H * 0.40)
        return Room(cx: L.W / 2, cy: cy, rx: rx, ry: ry, rxw: rxw, ryw: ryw)
    }

    /// the ring's angle now (the critically damped spring, solved exactly, so it is the same on any frame rate)
    private func theta(_ now: Date) -> (value: Double, moving: Bool) {
        let t = now.timeIntervalSince(ringStart)
        guard t > 0 else { return (ringFrom, false) }
        let x0 = ringFrom - ringTo, w = Self.omega
        let x = (x0 + (ringV + w * x0) * t) * exp(-w * t)
        return (ringTo + x, t < 0.9)
    }
    private func thetaVelocity(_ now: Date) -> Double {
        let t = max(0, now.timeIntervalSince(ringStart))
        let x0 = ringFrom - ringTo, w = Self.omega
        let a = ringV + w * x0
        return (a - w * (x0 + a * t)) * exp(-w * t)
    }

    struct Item { let i: Int; let pos: CGPoint; let size: CGFloat; let depth: Double; let face: Double }

    private func place(_ i: Int, th: Double, now: Date, r: Room) -> Item {
        let pl = Self.planets[i]
        let fk = Double(form.page)
        let orb = orbitAngle(i, now)
        let a = th + Double(i) * Self.step + orb * fk
        // the ring opens into the eight orbits: the same numbers draw the orbit lines
        let (rx, ry) = orbitRadii(i, r)
        let pos = CGPoint(x: r.cx + rx * CGFloat(cos(a)), y: r.cy + ry * CGFloat(sin(a)))
        let depth = (sin(a) + 1) / 2
        let persp = Flow.lerp(0.56 + 0.64 * depth, 0.85 + 0.30 * depth, CGFloat(fk))
        let ringSize = 27 * pl.size
        let fullSize = CGFloat(13 * pow(pl.wide, 0.33))
        // A2.9: the boost follows each planet's own place on the ring (1.3x at the front, none 45 degrees away), so it
        // changes with the turn, never with the tap
        var off = (th + Double(i) * Self.step - Self.front).truncatingRemainder(dividingBy: 2 * .pi)
        if off > .pi { off -= 2 * .pi }
        if off < -.pi { off += 2 * .pi }
        let close = max(0, 1 - abs(off) / (Double.pi / 4))
        let boost = 1 + 0.3 * CGFloat(close) * CGFloat(1 - fk)
        let size = Flow.lerp(ringSize, fullSize, CGFloat(fk)) * CGFloat(persp) * boost
        // rolling as it travels: two turns a lap, the other way to its travel, and the chosen one turning by itself on
        // top of that
        let own = ownSpin[i] + (i == chosen ? now.timeIntervalSince(spinSince) / pl.turn : 0)
        let face = -2 * (a / (2 * .pi)) + own
        return Item(i: i, pos: pos, size: size, depth: depth, face: face)
    }

    private func orbitRadii(_ i: Int, _ r: Room) -> (CGFloat, CGFloat) {
        let fk = form.page
        let o = CGFloat(Self.orbit(i))
        let rx = Flow.lerp(r.rx, r.rxw * o, fk)
        let ry = Flow.lerp(r.ry, r.ryw * (1 + 0.9 * fk) * o, fk)
        return (rx, ry)
    }

    private func orbitAngle(_ i: Int, _ now: Date) -> Double {
        if let s = fullSince { return orbitFrozen[i] + Self.orbitSpeed(i) * now.timeIntervalSince(s) }
        return orbitFrozen[i]
    }

    // MARK: drawing
    var body: some View {
        let L = water.layout
        let r = room()
        let target = Self.shares(map)
        let hidden = form.top > L.top(.quarter) - 20
        let busy = water.held || moonHeld || trail.moving(moonAngle) || heldTween.moving(Date())
            || (form.page > 0.001 && form.page < 0.999) || Date().timeIntervalSince(ringStart) < 1
            || sunEase?.moving(Date()) == true || shareEase?.contains { $0.moving(Date()) } == true
        // A2.12: under 50% the planets, the moon and the orbits go into the sun's centre as one (their top kept 12 pt
        // under the caption's foot); then the sun goes under the caption's number as its line passes over it
        let into = r.cy - 138
        let sink = min(1, max(0, (into - form.top) / (r.ry + 15)))
        let sunUnder = 1 - min(1, max(0, (form.top - into) / 58))
        let anchor = UnitPoint(x: r.cx / L.W, y: r.cy / L.H)
        // full speed while anything moves (120 a second on ProMotion phones, as the map runs: a ring at 60 judders
        // against it, 2.10); at rest the slow things (the spin, the sun's plasma) at 15 a second
        TimelineView(.animation(minimumInterval: busy || fullSince != nil ? 1.0 / 120 : 1.0 / 15, paused: hidden)) { ctx in
            let now = ctx.date
            let (th, _) = theta(now)
            let items = (0 ..< 8).map { place($0, th: th, now: now, r: r) }
            let shares = shareEase.map { e in e.map { CGFloat($0.at(now)) } } ?? target
            let sunC = CGPoint(x: r.cx, y: r.cy)
            // A2.10: by the turn's progress rr: the moon goes into the old planet over the first 30%, its host changes
            // while it is in, and it comes out of the new one over the last 30%
            let span = abs(ringFrom - ringTo)
            let rr = CGFloat(span < 1e-6 ? 1 : min(1, max(0, 1 - abs(th - ringTo) / span)))
            let ringOut = max(moonStartsIn ? 0 : 1 - Flow.smooth(0, 0.3, rr), Flow.smooth(0.7, 1, rr))
            let host = items[!moonStartsIn && rr < 0.3 ? moonFrom : chosen]
            // the moon: only round the chosen planet, at 50%, while the ring stands still; it grows out of the planet
            // and goes back into it (never fades). Every part follows something continuous, so it is seen whole on
            // every frame: the ring's distance from where it is going (it goes in as the ring sets off and comes out as
            // it lands) and the move to full the chosen planet's moon stays with it when the sun is picked too
            let moonOut: CGFloat = ringOut * (1 - Flow.smooth(0, 0.25, form.page))
            let held = CGFloat(heldTween.at(now))
            ZStack(alignment: .topLeading) {
                // the orbits, from the planets' own numbers: at 50% all eight lie on the ring (so they read as one
                // line), at full each opens out to its own all eight in one path stroked once, so where they lie
                // together (at 50%, and just as they part) they are one line, never eight lines stacking into a dark
                // band. The palette's dark grey, a hairline: never a new see-through black
                Path { p in
                    for i in 0 ..< 8 {
                        let (rx, ry) = orbitRadii(i, r)
                        p.addEllipse(in: CGRect(x: sunC.x - rx, y: sunC.y - ry, width: rx * 2, height: ry * 2))
                    }
                }
                .stroke(FullView.night(form.page) ? Palette.white : Palette.ink.opacity(0.5), lineWidth: 0.7 / max(0.05, sink))
                .scaleEffect(sink, anchor: anchor)
                ForEach(items.filter { $0.depth < 0.5 }.sorted { $0.depth < $1.depth }, id: \.i) { it in
                    planetView(it, shares: shares, sun: sunC)
                        .scaleEffect(sink, anchor: anchor)
                }
                // THE SUN IS THE STREAK'S SIZE, always, and only that: picking it only shows the number. From 0.8 of
                // its size with no streak to 1.3 at 8 weeks, then on far more slowly, so two months, a year and ten
                // years still differ
                let w = CGFloat(max(0, sunEase?.at(now) ?? Double(map.streakWeeks)))
                let g = w <= 8 ? log(1 + w) / log(9) : min(1.3, 1 + 0.3 * log(w / 8) / log(65))
                // at 50% the ring is close round it: it grows no further than the 8-week size there, opening up to the
                // full growth as the ring opens into the orbits
                let sunSize = Flow.lerp(46, 40, form.page) * (0.68 + 0.62 * min(g, Flow.lerp(1, 1.3, form.page))) * max(0.001, sunUnder)
                SunView(size: sunSize, time: now.timeIntervalSince(start), flare: min(1, g), glow: 0,
                        heat: SunView.heat(weeks: w), swell: Flow.lerp(0.35, 1, form.page))
                    .position(sunC)
                // the touch is the sun itself and a little round it, never its flares
                Color.clear
                    .frame(width: sunSize + 20, height: sunSize + 20)
                    .contentShape(Circle())
                    .position(sunC)
                    .onTapGesture { pickSun() }
                    .accessibilityElement()
                    .accessibilityLabel("Your streak")
                    .accessibilityAddTraits(.isButton)
                // NO LINE FOR THE MOON'S PATH: while it moves, a short tail of the stops' colours follows it along its
                // path, as long as it is fast, and draws back into the moon as it stops (it shortens, it never fades).
                // Drawn just under the moon, in its depth.
                let tail = trail.follow(moonAngle, at: now)
                if moonAngle.sin < 0 {
                    moonTrail(host, from: tail, out: moonOut, disc: moonDisc(host, out: moonOut, held: held))
                        .scaleEffect(sink, anchor: anchor)
                    moon(host, out: moonOut, held: held, sun: sunC, now: now)
                        .scaleEffect(sink, anchor: anchor)
                }
                ForEach(items.filter { $0.depth >= 0.5 }.sorted { $0.depth < $1.depth }, id: \.i) { it in
                    planetView(it, shares: shares, sun: sunC)
                        .scaleEffect(sink, anchor: anchor)
                }
                if moonAngle.sin >= 0 {
                    moonTrail(host, from: tail, out: moonOut, disc: moonDisc(host, out: moonOut, held: held))
                        .scaleEffect(sink, anchor: anchor)
                    moon(host, out: moonOut, held: held, sun: sunC, now: now)
                        .scaleEffect(sink, anchor: anchor)
                }
                if moonOut > 0.5 && sink > 0.99 { moonHandle(host) }
            }
            .frame(width: L.W, height: L.H, alignment: .topLeading)
            // ONE GPU PASS FOR THE WHOLE SYSTEM (Step 1c): each planet's, ring's and the sun's shader was its own
            // picture drawn apart and put together every frame (with the planets off: no late frames at full; with them,
            // 7 to 18 in 120); in a drawing group they are drawn together in one Metal pass
            .drawingGroup(opaque: false)
        }
        .onChange(of: moonHeld) { _, on in
            heldTween.go(on ? 1 : 0, dur: on ? 0.32 : 0.4, delay: on ? 0 : 0.25)
            // while you hold it the caption's name is the stop's (a label by the planet sat on the sun)
            withAnimation(Motion.quick) { map.moonHeld = on }
        }
        .onChange(of: map.testMoon) { _, a in
            if let a {
                moonAngle = a * .pi / 180; moonHeld = true
                let s = Self.nearestStop(moonAngle); map.filter = s; moonStop = s
            } else { moonHeld = false }
        }
        .onChange(of: map.testPlanet) { _, i in
            if let i { select(i); map.testPlanet = nil }
        }
        .onChange(of: form.page >= 0.999) { _, full in
            let now = Date()
            if full { fullSince = now } else if let s = fullSince {
                // A2.16: the moment it leaves full each orbit's turn is wrapped to within half a lap (the same point
                // on the orbit), so on the way down each planet goes the short way back to its slot (its turn x p)
                for i in 0 ..< 8 {
                    let a = orbitFrozen[i] + Self.orbitSpeed(i) * now.timeIntervalSince(s)
                    orbitFrozen[i] = remainder(a, 2 * .pi)
                }
                fullSince = nil
                // a planet chosen at full came to the front of its orbit; on the way down the ring turns so it is at
                // the front of the ring again when the orbits have closed (A2.18)
                aim(Self.front - Double(chosen) * Self.step, now: now)
            }
        }
        .onChange(of: map.streakWeeks, initial: true) { old, w in
            let now = Date()
            if sunEase == nil || old == w { sunEase = Ease1(Double(w)) } else { sunEase?.go(Double(w), now: now) }
        }
        .onChange(of: target, initial: true) { old, v in
            let now = Date()
            if shareEase == nil || shareEase?.count != v.count || old == v { shareEase = v.map { Ease1(Double($0)) } }
            else { for i in v.indices { shareEase?[i].go(Double(v[i]), now: now) } }
        }
    }

    @ViewBuilder
    private func planetView(_ it: Item, shares: [CGFloat], sun: CGPoint) -> some View {
        let pl = Self.planets[it.i]
        let share = shares[it.i]
        // the more of that continent you've stamped, the more of it is in night
        let lit = 1 - share
        let alpha = acos(Double(2 * lit - 1))
        // the light comes from where the sun actually is on screen, a direction that only ever turns smoothly
        let dx = Double(sun.x - it.pos.x), dy = Double(it.pos.y - sun.y)
        let len = max(1e-6, (dx * dx + dy * dy).squareRoot())
        let light = SIMD3<Float>(Float(dx / len * sin(alpha)), Float(dy / len * sin(alpha)), Float(cos(alpha)))
        PlanetBody(tex: pl.tex, size: it.size, spin: Float(it.face * 2 * .pi), light: light, ring: pl.n == "Saturn", lights: pl.n == "Earth")
            .position(it.pos)
            .contentShape(Circle().inset(by: -6))
            .onTapGesture { select(it.i) }
            .accessibilityElement()
            .accessibilityLabel("\(pl.k == "World" ? "The world" : pl.k), \(Int((share * 100).rounded())) percent")
            .accessibilityAddTraits(.isButton)
    }

    /// choosing a planet turns the ring the short way, carrying on from however it is moving now
    private func select(_ i: Int) {
        let now = Date()
        let (th, _) = theta(now)
        // where the moon is now: out (it goes into the planet it is on) or not (it stays in until the turn lands)
        let span = abs(ringFrom - ringTo)
        let rr = CGFloat(span < 1e-6 ? 1 : min(1, max(0, 1 - abs(th - ringTo) / span)))
        let out = max(moonStartsIn ? 0 : 1 - Flow.smooth(0, 0.3, rr), Flow.smooth(0.7, 1, rr))
        let onNow = !moonStartsIn && rr < 0.3 ? moonFrom : chosen
        moonStartsIn = out < 0.5
        moonFrom = onNow
        // at full the chosen one comes to the front of its own orbit (A2.18): the shared angle less its orbit's turn
        aim(Self.front - Double(i) * Self.step - orbitAngle(i, now) * Double(form.page), now: now)
        // the chosen one keeps the turn it had made by itself
        ownSpin[chosen] += now.timeIntervalSince(spinSince) / Self.planets[chosen].turn
        spinSince = now
        chosen = i
        map.sunPicked = false
        Feel.tap(); Sound.tap()
        map.show(continent: Self.planets[i].k)
    }

    /// turns the ring the short way to an angle, carrying on from however it is moving now
    private func aim(_ angle: Double, now: Date) {
        let (th, _) = theta(now)
        let v = thetaVelocity(now)
        var to = angle
        while to - th > .pi { to -= 2 * .pi }
        while to - th < -.pi { to += 2 * .pi }
        ringFrom = th; ringTo = to; ringV = v; ringStart = now
    }

    private func pickSun() {
        Feel.tap(); Sound.tap()
        map.sunPicked.toggle()
    }

    // MARK: THE MOON IS THE FILTER: turned round its planet, never pressed; it stays where you leave it; its ring (lime
    // on the stamped side, blue on the wishlist side) and the stop's name show while you hold it. / wide enough that
    // the moon clears the planet even at the top and bottom of its tilted path (0.62 high)
    private func moonRadius(_ host: Item) -> CGFloat { host.size * 0.5 / 0.62 + 12 }

    private func moonPos(_ host: Item) -> CGPoint {
        let r = moonRadius(host)
        return CGPoint(x: host.pos.x + r * CGFloat(cos(moonAngle)), y: host.pos.y + r * 0.62 * CGFloat(sin(moonAngle)))
    }

    /// The moon. Earth's is a real sphere wearing the Moon's own surface map (NASA, the maria and the craters), lit
    /// from where the sun is and turning slowly. The other planets' moons have no surface maps in the bundle, so they
    /// stay their small pictures (Phobos's lumpy shape for Mars and so on).
    @ViewBuilder
    private func moon(_ host: Item, out: CGFloat, held: CGFloat, sun: CGPoint, now: Date) -> some View {
        let disc = moonDisc(host, out: out, held: held)
        let size = disc.size, at = disc.at
        let name = Self.planets[host.i].n.lowercased()
        if name == "earth" {
            let dx = Double(sun.x - at.x), dy = Double(at.y - sun.y)
            let len = max(1e-6, (dx * dx + dy * dy).squareRoot())
            // three quarters lit, the night on the side away from the sun
            let a = 1.05
            // it turns as it goes round: like the real Moon it keeps one face to its planet, so as you take it round,
            // the side you see turns with it; the angle is where it is on its path, so it follows the finger exactly,
            // both ways
            PlanetBody(tex: "planet-moon", size: size, spin: Float(-(moonAngle - .pi / 2)),
                       light: SIMD3<Float>(Float(dx / len * sin(a)), Float(dy / len * sin(a)), Float(cos(a))),
                       ring: false, lights: false)
                .scaleEffect(max(0.001, out))
                .position(at)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Textures.image("moon-\(name)")
                .resizable()
                .frame(width: size, height: size)
                .scaleEffect(max(0.001, out))
                .position(at)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// the moon's ring while you hold it: one smooth gradient from lime to blue through the five stops: lime at Stamped
    /// on the right, blue at Wishlist on the left, the + stops on the way, Both at the top halfway between (and the
    /// bottom halfway too, so it never jumps). Drawn as a circle squashed to the moon's path, so its angles are the
    /// moon's. It comes out of the moon: drawn from the moon's place outward both ways round until it closes behind the
    /// planet, and goes back into the moon the same way (no fade, no pop). Where the moon is drawn and how big (before
    /// its shrink into the planet): held, it grows a little under the finger so you can see what you hold; going back
    /// into the planet, it moves to the planet's middle as it shrinks.
    private func moonDisc(_ host: Item, out: CGFloat, held: CGFloat) -> (at: CGPoint, size: CGFloat, shown: CGFloat) {
        let size = max(9, min(16, host.size * 0.32)) * (1 + 0.35 * held)
        let p = moonPos(host)
        return (CGPoint(x: Flow.lerp(host.pos.x, p.x, out), y: Flow.lerp(host.pos.y, p.y, out)), size, size * out)
    }

    /// THE MOON'S TAIL: from where the moon is back along its path to `from`, thick as half the moon at the moon and
    /// thinning to a point, in the colour of each stop it passes (lime on the stamped side, blue on the wishlist side,
    /// their mixes between); nothing when the moon is still
    private func moonTrail(_ host: Item, from: Double, out: CGFloat, disc: (at: CGPoint, size: CGFloat, shown: CGFloat)) -> some View {
        let to = moonAngle
        var span = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if span > .pi { span -= 2 * .pi }
        if span < -.pi { span += 2 * .pi }
        let r = moonRadius(host)
        let c = host.pos
        return Canvas { ctx, _ in
            guard abs(span) > 0.004, out > 0.5 else { return }
            let n = max(6, Int(abs(span) / 0.03))
            let w0 = disc.shown * 0.5
            func at(_ a: Double) -> CGPoint { CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * 0.62 * CGFloat(sin(a))) }
            for k in 0 ..< n {
                // k = 0 at the moon
                let a0 = to - span * Double(k) / Double(n), a1 = to - span * Double(k + 1) / Double(n)
                var p = Path()
                p.move(to: at(a0)); p.addLine(to: at(a1))
                let thin = 1 - CGFloat(k) / CGFloat(n)
                ctx.stroke(p, with: .color(Self.stopColour(a0)),
                           style: StrokeStyle(lineWidth: max(0.5, w0 * thin * thin), lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    /// the colour of the moon's path at an angle: the five stops' colours, mixed between neighbours
    static func stopColour(_ a: Double) -> Color {
        let mid = Palette.lime.mix(with: Palette.blue, by: 0.5, in: .perceptual)
        let cs = [mid, Palette.lime, Palette.lime.mix(with: Palette.blue, by: 0.25, in: .perceptual),
                  Palette.lime.mix(with: Palette.blue, by: 0.75, in: .perceptual), Palette.blue]
        var x = (a - stopAngle(0)).truncatingRemainder(dividingBy: 2 * .pi)
        if x < 0 { x += 2 * .pi }
        let f = x / (2 * .pi / 5)
        let i = Int(f) % 5, t = f - Double(Int(f))
        return cs[i].mix(with: cs[(i + 1) % 5], by: t, in: .perceptual)
    }

    /// one handle over everything, so the planet in front never takes its touch and the drag never breaks when the
    /// moon passes from behind the planet to in front of it
    private func moonHandle(_ host: Item) -> some View {
        // only 18 points round the moon, and a move under 6 points is not the moon's: a tap there is the planet's
        // (BUILD-BOOK 2.5; the old handle took Earth's taps)
        Color.clear
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .position(moonPos(host))
            .onTapGesture { select(host.i) }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { g in
                        let dx = Double(g.location.x - host.pos.x), dy = Double(g.location.y - host.pos.y) / 0.62
                        let ang = atan2(dy, dx)
                        if !moonHeld { moonHeld = true; Feel.tap() }
                        let before = Self.nearestStop(moonAngle)
                        moonAngle = ang
                        let now = Self.nearestStop(ang)
                        if now != before { Feel.tick(); Sound.tick(); withAnimation(Motion.quick) { map.filter = now }; moonStop = now }
                    }
                    .onEnded { _ in
                        // it stays where you left it; the filter is the stop it is nearest
                        moonHeld = false
                        Feel.notch(); Sound.click()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Filter")
            .accessibilityValue(Self.stops[moonStop])
            .accessibilityAdjustableAction { dir in
                let s = dir == .increment ? (moonStop + 1) % 5 : (moonStop + 4) % 5
                moonStop = s
                withAnimation(Motion.chrome) { moonAngle = Self.stopAngle(s) }
                map.filter = s
            }
    }

    /// each continent's share of its places you've stamped; Earth's is the world's
    /// worked out again only when the stamps change (Step 1c: this ran on every frame the sheet moved, all places x 8)
    private static var sharesMade: (stamped: Set<Int>, v: [CGFloat])?
    static func shares(_ m: MapController) -> [CGFloat] {
        let stamped = m.stamped    // observed first, so the planets update once the world has loaded
        guard m.ready, let w = m.world else { return Array(repeating: 0, count: 8) }
        if let s = sharesMade, s.stamped == stamped { return s.v }
        let v: [CGFloat] = planets.map { pl in
            var tot = 0, got = 0
            for (i, p) in w.places.enumerated() where pl.k == "World" ? !p.junk : w.inCont(i, pl.k) {
                tot += 1; if stamped.contains(i) { got += 1 }
            }
            return tot == 0 ? 0 : CGFloat(got) / CGFloat(tot)
        }
        sharesMade = (stamped, v)
        return v
    }
}

private extension Double { var sin: Double { Foundation.sin(self) } }

/// One planet, drawn by the sphere shader on its own surface map.
struct PlanetBody: View {
    let tex: String
    let size: CGFloat
    let spin: Float
    let light: SIMD3<Float>
    let ring: Bool
    let lights: Bool

    var body: some View {
        if Perf.shared.off.contains("planets") { Circle().fill(Palette.grey).frame(width: size, height: size).frame(width: size * 2.3, height: size * 2.3) } else {
        ZStack {
            if ring { ringHalf(front: false) }
            Rectangle()
                .frame(width: size, height: size)
                .colorEffect(ShaderLibrary.planetSphere(
                    .float2(Float(size), Float(size)), .float(spin), .float3(light.x, light.y, light.z),
                    .image(Textures.image(tex)), .image(Textures.image("earth-lights")), .float(lights ? 1 : 0), .float(0)))
            if ring { ringHalf(front: true) }
        }
        .frame(width: size * 2.3, height: size * 2.3)
        }
    }

    private func ringHalf(front: Bool) -> some View {
        Rectangle()
            .frame(width: size * 2.3, height: size * 2.3)
            .colorEffect(ShaderLibrary.saturnRing(.float2(Float(size * 2.3), Float(size * 2.3)), .float(0.32),
                                                  .float(front ? 1 : 0), .image(Textures.image("saturn-ring"))))
            .allowsHitTesting(false)
    }
}

/// THE SUN: the plasma shader, always moving. It is your streak; never a number on it: its prominences reach further
/// the longer the streak, up to a cap at 8 weeks (`flare`), and picked it glows (`glow`, 0...1 from its tween). The
/// disc itself stays the same size; the frame grows so the flares are never cut.
struct SunView: View {
    let size: CGFloat
    let time: Double
    let flare: CGFloat
    let glow: CGFloat
    /// the streak on a log scale to ten years (0...1): colour, boiling, corona and eruptions
    var heat: CGFloat = 0.0
    /// how far the red giant may swell here (0...1): less at 50%, where Earth's moon is close below
    var swell: CGFloat = 1
    /// THE STREAK AS THE STAR'S AGE: most of the life is spent in the first ten weeks, every week a clear step on (1
    /// week 0.11, 2 weeks 0.20, 4 weeks 0.34, 6 weeks 0.45, 8 weeks 0.54, 10 weeks 0.62: our sun, then swelling and
    /// reddening into a giant by about ten weeks); after that it turns white-hot slowly over the years, reaching 1 at
    /// ten years. Smooth in the weeks, no steps, no milestones.
    static func heat(weeks w: CGFloat) -> CGFloat {
        let early = 0.62 * (1 - exp(-min(w, 10) / 5)) / (1 - exp(-2))
        let late = w > 10 ? 0.38 * log(1 + (w - 10)) / log(511) : 0
        return min(1, early + late)
    }
    var body: some View {
        // the frame holds everything the star becomes (its flares, the giant, the nebula's rim) so nothing is cut
        let s = size * max(2.1 + 1.8 * flare + 1.0 * glow + 1.6 * min(1, heat / 0.3), 3.2 + 2.6 * max(0, (heat - 0.3) / 0.7))
        if Perf.shared.off.contains("sun") { Circle().fill(Palette.yellow).frame(width: size, height: size).frame(width: s, height: s) } else {
        Rectangle()
            .frame(width: s, height: s)
            .colorEffect(ShaderLibrary.sunPlasma(.float2(Float(s), Float(s)), .float(Float(time)), .float(Float(size / s)),
                                                 .float(Float(flare)), .float(Float(glow)), .float(Float(heat)), .float(Float(swell))))
            .allowsHitTesting(false)
        }
    }
}

/// A value easing from one number to another over a time, read at any moment (so things drawn inside a timeline are
/// seen whole on every frame, with no SwiftUI animation that a redraw could skip). The curve is a smoothstep: it
/// starts and ends at rest, no bounce.
/// A value easing to a new one on a critically damped spring of response 0.6 s (A2.13, A2.14: 47%, 82%, 95% of the
/// way at a quarter, half and three quarters), retargeted from its value and speed
struct Ease1: Equatable {
    var from: Double, to: Double, v0: Double = 0, start = Date.distantPast
    init(_ v: Double) { from = v; to = v }
    static var w: Double { 2 * Double.pi / (Motion.reduce ? 0.35 : 0.6) }
    func at(_ now: Date) -> Double {
        let t = max(0, now.timeIntervalSince(start)), d = from - to
        return to + (d + (v0 + Self.w * d) * t) * exp(-Self.w * t)
    }
    func speed(_ now: Date) -> Double {
        let t = max(0, now.timeIntervalSince(start)), d = from - to, b = v0 + Self.w * d
        return (b - Self.w * (d + b * t)) * exp(-Self.w * t)
    }
    func moving(_ now: Date) -> Bool { now.timeIntervalSince(start) < 1.2 }
    mutating func go(_ v: Double, now: Date) {
        let x = at(now), s = speed(now)
        from = x; v0 = s; to = v; start = now
    }
}

struct Tween: Equatable {
    var from: Double
    var to: Double
    var start = Date.distantPast
    var dur: Double = 0.3
    init(_ v: Double) { from = v; to = v }
    func at(_ now: Date) -> Double {
        let t = min(1, max(0, now.timeIntervalSince(start) / max(0.001, dur)))
        let e = t * t * (3 - 2 * t)
        return from + (to - from) * e
    }
    func moving(_ now: Date) -> Bool { now.timeIntervalSince(start) < dur + 0.05 }
    /// to a new value from wherever it is now
    mutating func go(_ v: Double, dur d: Double, delay: Double = 0) {
        let now = Date()
        from = at(now); to = v; dur = d; start = now.addingTimeInterval(delay)
    }
}

nonisolated struct SeededRandom {
    var s: UInt64
    init(seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Double(s % 1_000_000) / 1_000_000
    }
}

/// The cosmos's pictures, loaded once from the bundle.
@MainActor
enum Textures {
    private static var cache: [String: Image] = [:]
    static func image(_ name: String) -> Image {
        if let i = cache[name] { return i }
        let path = Bundle.main.path(forResource: name, ofType: "jpg") ?? Bundle.main.path(forResource: name, ofType: "png")
        // redrawn once into a plain 8-bit sRGB picture at half size: the shader takes these without conversion
        let img = path.flatMap { UIImage(contentsOfFile: $0) }.map { src -> Image in
            let w = max(1, src.size.width * src.scale / 2), h = max(1, src.size.height * src.scale / 2)
            let size = CGSize(width: w, height: src.size.height <= 1 ? 1 : h)
            let f = UIGraphicsImageRendererFormat()
            f.scale = 1; f.opaque = false; f.preferredRange = .standard
            let out = UIGraphicsImageRenderer(size: size, format: f).image { _ in src.draw(in: CGRect(origin: .zero, size: size)) }
            return Image(uiImage: out)
        } ?? Image(systemName: "circle")
        cache[name] = img
        return img
    }
}

/// An angle that follows the moon a little behind it (an exponential follow, 0.12 s), read and moved once a frame from
/// inside the timeline; a class so moving it never redraws anything by itself.
final class TrailFollower {
    private var a: Double?
    private var last: Date?
    func follow(_ target: Double, at now: Date) -> Double {
        guard let prev = a, let t0 = last else { a = target; last = now; return target }
        let dt = min(0.05, max(0, now.timeIntervalSince(t0)))
        var d = (target - prev).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        let next = prev + d * (1 - exp(-dt / 0.12))
        a = next; last = now
        return next
    }
    /// still moving (the tail is longer than a hair): the timeline keeps drawing until it has drawn back in
    func moving(_ target: Double) -> Bool {
        guard let a else { return false }
        var d = (target - a).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return abs(d) > 0.004
    }
}

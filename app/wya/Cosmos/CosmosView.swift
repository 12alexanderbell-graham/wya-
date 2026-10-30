import SwiftUI

/// THE SYSTEM: the sun is your streak, the planets are the continents (Earth is the world), each planet's night side as
/// wide as the share of that continent you've stamped. At 50% they sit on one ring under the name and the number;
/// pulled to full the ring opens into eight orbits round the sun and they go round them. The rules it keeps: nothing
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

    static let step = 2 * Double.pi / 8
    static let front = Double.pi / 2
    static let omega = 2 * Double.pi / 0.44

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
        // at 50% the ring sits between the caption's foot (the top + 130) and the tabs; under 50% it sinks with the
        // water and on down past the bottom, faster than the edge, so at 25% it is gone below the screen
        let halfTop = L.top(.half)
        let below = max(0, form.top - halfTop)
        let lo = halfTop + 130, hi = L.capsule.minY - 20
        let ringY = (lo + hi) / 2 + below * 1.7
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
        let boost: CGFloat = i == chosen ? 1 + 0.3 * CGFloat(1 - fk) : 1
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
        let hidden = form.top > L.top(.quarter) - 20
        let busy = water.held || moonHeld || trail.moving(moonAngle) || heldTween.moving(Date()) || map.flying > 0
            || (form.page > 0.001 && form.page < 0.999) || Date().timeIntervalSince(ringStart) < 1
        // full speed while anything moves; at rest the slow things (the spin, the sun's plasma) at 15 a second
        TimelineView(.animation(minimumInterval: busy || fullSince != nil ? 1.0 / 60 : 1.0 / 15, paused: hidden)) { ctx in
            let now = ctx.date
            // a planet's night grows by a stamp's share only once that stamp's star has landed in it (A2.20) or the
            // system has been seen at 50% since; it changes in one frame, as it always has (the A2.14 sweep is the
            // book's proposal, reverted with the other Cosmos changes on 30 Oct and not asked for again)
            let shares = Self.shares(map, now: now)
            let (th, _) = theta(now)
            let items = (0 ..< 8).map { place($0, th: th, now: now, r: r) }
            let host = items[chosen]
            let sunC = CGPoint(x: r.cx, y: r.cy)
            // the moon: only round the chosen planet, at 50%, while the ring stands still; it grows out of the
            // planet and goes back into it (never fades). Every part follows something continuous, so it is seen
            // whole on every frame: the ring's distance from where it is going (it goes in as the ring sets off and comes
            // out as it lands) and the move to full
            let settle = 1 - Flow.smooth(0.03, 0.30, CGFloat(abs(th - ringTo)))
            // the chosen planet's moon stays with it when the sun is picked too
            let moonOut: CGFloat = settle * (1 - Flow.smooth(0, 0.25, form.page))
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
                .stroke(FullView.night(form.page) ? Palette.white : Palette.ink.opacity(0.5), lineWidth: 0.7)
                ForEach(items.filter { $0.depth < 0.5 }.sorted { $0.depth < $1.depth }, id: \.i) { it in
                    planetView(it, shares: shares, sun: sunC)
                }
                // THE SUN IS THE STREAK'S SIZE, always, and only that: picking it only shows the number. From 0.8 of
                // its size with no streak to 1.3 at 8 weeks, then on far more slowly, so two months, a year and ten
                // years still differ
                let w = CGFloat(max(0, map.streakWeeks))
                let g = w <= 8 ? log(1 + w) / log(9) : min(1.3, 1 + 0.3 * log(w / 8) / log(65))
                // at 50% the ring is close round it: it grows no further than the 8-week size there, opening up to the
                // full growth as the ring opens into the orbits
                let sunSize = Flow.lerp(46, 40, form.page) * (0.68 + 0.62 * min(g, Flow.lerp(1, 1.3, form.page)))
                SunView(size: sunSize, time: now.timeIntervalSince(start), flare: min(1, g), glow: 0,
                        heat: SunView.heat(weeks: w), swell: Flow.lerp(0.35, 1, form.page))
                    .position(sunC)
                // the touch is the sun itself and a little round it, never its flares
                Color.clear
                    .frame(width: sunSize + 20, height: sunSize + 20)
                    .contentShape(Circle())
                    // 11.5: Your streak (as its tap); sharing it waits for its picture. Given before .position, so the
                    // lift is the sun's circle, not the whole system's frame
                    .contentShape(.contextMenuPreview, Circle())
                    .contextMenu { Button("Your streak") { if !map.sunPicked { pickSun() } } }
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
                    moon(host, out: moonOut, held: held, sun: sunC, now: now)
                }
                ForEach(items.filter { $0.depth >= 0.5 }.sorted { $0.depth < $1.depth }, id: \.i) { it in
                    planetView(it, shares: shares, sun: sunC)
                }
                if moonAngle.sin >= 0 {
                    moonTrail(host, from: tail, out: moonOut, disc: moonDisc(host, out: moonOut, held: held))
                    moon(host, out: moonOut, held: held, sun: sunC, now: now)
                }
                if moonOut > 0.5 { moonHandle(host) }
                // the stars of new stamps falling into their planets, over everything
                ForEach(0 ..< map.flying, id: \.self) { j in fallingStar(j, items: items, now: now) }
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
                for i in 0 ..< 8 { orbitFrozen[i] += Self.orbitSpeed(i) * now.timeIntervalSince(s) }
                fullSince = nil
            }
        }
        // THE STARS OF NEW STAMPS FALL (A2.20) the first time the full view is seen after them: once the water is 97%
        // of the way there (the last 3% of its spring takes 1.6 s more, measured 30 Oct; waiting for all of it left
        // the full view standing still for over a second first)
        .onChange(of: form.page >= 0.97) { _, there in
            if there { map.startFalls() }
        }
        // seen at 50% (the ring in its room, not sunk with the water): the waiting stamps' shares show in the night now
        .onChange(of: form.page < 0.001 && form.top <= L.top(.half) + 40 && map.falls.contains { !$0.seen }, initial: true) { _, v in
            if v { map.fallsSeen() }
        }
        // the planet at the front is always the map's continent (Earth for the world)
        .onChange(of: map.continent) { _, c in
            let k = c ?? "World"
            if Self.planets[chosen].k != k, let j = Self.planets.firstIndex(where: { $0.k == k }) { turnRing(to: j) }
        }
        .onChange(of: form.page < 0.001) { _, half in
            // back at 50%: the orbits' own turns ease home with the ring, so the chosen planet is at the front again
            if half { withAnimation(Motion.chrome) { orbitFrozen = orbitFrozen.map { $0 - ($0 / (2 * .pi)).rounded() * 2 * .pi } } }
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
            // the tap and the hold on a clear disc over the planet (the planet and 6 pt round it), given before it is
            // placed: a shape given after .position is a circle in the whole system's frame and missed planets away from
            // the middle. The planet itself takes no touch (its frame is 2.3 times it, for Saturn's ring), and is not
            // the menu's lift: drawn by its shader outside the system it lifts as a black square
            .allowsHitTesting(false)
            .overlay {
                Color.clear
                    .frame(width: it.size + 12, height: it.size + 12)
                    .contentShape(Circle())
                    .contentShape(.contextMenuPreview, Circle())
                    .onTapGesture { select(it.i) }
                    .contextMenu { planetMenu(it.i) }
            }
            .position(it.pos)
            .allowsHitTesting(form.page < 0.5)
            .accessibilityElement()
            .accessibilityLabel("\(pl.k == "World" ? "The world" : pl.k), \(Int((share * 100).rounded())) percent")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select(it.i) }
    }

    /// choosing a planet turns the ring the short way, carrying on from however it is moving now
    private func select(_ i: Int) {
        turnRing(to: i)
        map.sunPicked = false
        Feel.tap(); Sound.tap()
        map.show(continent: Self.planets[i].k)
    }

    /// the ring turned so planet i is at the front (a pick here, or the map's continent changed elsewhere: the Map tab
    /// again, a search result, the caption's menu)
    private func turnRing(to i: Int) {
        let now = Date()
        let (th, _) = theta(now)
        let v = thetaVelocity(now)
        var to = Self.front - Double(i) * Self.step
        while to - th > .pi { to -= 2 * .pi }
        while to - th < -.pi { to += 2 * .pi }
        // the chosen one keeps the turn it had made by itself
        ownSpin[chosen] += now.timeIntervalSince(spinSince) / Self.planets[chosen].turn
        spinSince = now
        ringFrom = th; ringTo = to; ringV = v; ringStart = now
        chosen = i
    }

    /// A PLANET'S HOLD MENU (11.5): Open the continent (as its tap) · Its stamped list (the list scoped to it). Earth:
    /// a continent by name, or the world. Sharing waits for its picture.
    @ViewBuilder private func planetMenu(_ i: Int) -> some View {
        if Self.planets[i].k == "World" {
            Section {
                ForEach(Self.planets.indices.filter { Self.planets[$0].k != "World" }.sorted { Self.planets[$0].k < Self.planets[$1].k },
                        id: \.self) { j in
                    Button(Self.planets[j].k) { select(j) }
                }
            }
            Button("The world") { select(i) }
        } else {
            Button("Open \(Self.planets[i].k)") { select(i) }
            Button("Its stamped list") {
                // the list is scoped to the continent the map is on, whatever the ring last chose
                if map.continent != Self.planets[i].k { select(i) }
                // none stamped there: nothing to list (as the caption's number refuses at 0)
                guard (map.shares[Self.planets[i].k]?.have ?? 0) > 0 else { Feel.refuse(); return }
                // once Apple's menu has closed and the flight has started
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { water.openList() }
            }
        }
    }

    /// a filter stop from the moon's menu: the moon moves along its path there, the colours change behind
    private func pickStop(_ st: Int) {
        Feel.tick()
        // a menu that began over a drag's first points: the hold is over
        moonHeld = false
        moonStop = st
        map.filter = st
        // along its path the short way round (its angle stepped, so it never cuts across as a straight line), on the
        // chrome curve's shape, 0.38 s
        let from = moonAngle
        var to = Self.stopAngle(st)
        while to - from > .pi { to -= 2 * .pi }
        while to - from < -.pi { to += 2 * .pi }
        pickJob += 1
        let me = pickJob, start = Date()
        Task { @MainActor in
            while me == pickJob {
                // Reduce Motion: the same move, shorter (Part 19)
                let t = min(1, Date().timeIntervalSince(start) / (Motion.reduce ? 0.2 : 0.38))
                moonAngle = from + (to - from) * Double(Flow.smooth(0, 1, CGFloat(t)))
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }
    @State private var pickJob = 0

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
            // 11.5: the five filter stops; the moon goes along its path to the one picked (before .position, so the
            // lift is the moon's own circle)
            .contentShape(.contextMenuPreview, Circle())
            .contextMenu {
                ForEach(0 ..< 5, id: \.self) { st in
                    Button(Self.stops[st]) { pickStop(st) }.disabled(st == moonStop)
                }
            }
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
    /// read from the Count service (Store/Count.swift), the same numbers the caption shows; MapController works them
    /// out again only when the stamps or the Count setting change (Step 1c: never per frame)
    /// less the stamps whose star has not landed yet (A2.20)
    static func shares(_ m: MapController, now: Date = Date()) -> [CGFloat] {
        let sh = m.shares    // observed first, so the planets update once the world has loaded
        guard m.ready else { return Array(repeating: 0, count: 8) }
        var held: [String: Int] = [:]
        for (j, f) in m.falls.enumerated() where !f.seen && m.fallProgress(j, at: now) < 1 {
            for k in f.held { held[k, default: 0] += 1 }
        }
        return planets.map { pl in
            let s = sh[pl.k] ?? MapCounts.Share()
            return s.total == 0 ? 0 : CGFloat(max(0, s.have - held[pl.k, default: 0])) / CGFloat(s.total)
        }
    }

    /// A STAMP'S STAR FALLS INTO ITS PLANET (A2.20): from its own spot, along a curve bowed away from the sun, into
    /// its continent's planet wherever that is now, shrinking as it goes (full size, 90% a quarter of the way, 70%
    /// half, 40% three quarters, gone as it lands); 0.7 s each, 0.1 s apart. Until its turn it sits where it was.
    @ViewBuilder
    private func fallingStar(_ j: Int, items: [Item], now: Date) -> some View {
        let L = water.layout
        let t = map.fallProgress(j, at: now)
        let sun = CGPoint(x: L.W / 2, y: L.H / 2)
        if t < 1, j < map.falls.count, map.falls[j].into < items.count,
           let st = PlasmaStars.star(map.placesLeft + j, size: CGSize(width: L.W, height: L.H), sun: sun),
           !L.capsule.contains(st.at) {
            // grown as the stars under the edge are (the same rule as PlasmaStars), so it starts exactly as it was
            let grow = Double(Flow.smooth(0.5, 0.8, form.page)) * min(1, max(0, Double(st.at.y - form.top) / 28))
            if grow > 0.01 {
                let from = st.at, to = items[map.falls[j].into].pos
                let dx = to.x - from.x, dy = to.y - from.y
                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                let a = CGPoint(x: mid.x - dy * 0.25, y: mid.y + dx * 0.25), b = CGPoint(x: mid.x + dy * 0.25, y: mid.y - dx * 0.25)
                let ctrl = hypot(a.x - sun.x, a.y - sun.y) > hypot(b.x - sun.x, b.y - sun.y) ? a : b
                let p = Self.curve(from, ctrl, to, CGFloat(t * t * (3 - 2 * t)))
                let w = PlasmaStars.sprite * CGFloat(st.scale * grow * Self.fallSize(t))
                PlasmaStars.shared[st.picture]
                    .resizable()
                    .frame(width: w, height: w)
                    .position(p)
            }
        }
    }
    /// a point u of the way along the curve from a through c to b
    static func curve(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ u: CGFloat) -> CGPoint {
        let v = 1 - u
        let wa = v * v, wc = 2 * v * u, wb = u * u
        let x: CGFloat = wa * a.x + wc * c.x + wb * b.x
        let y: CGFloat = wa * a.y + wc * c.y + wb * b.y
        return CGPoint(x: x, y: y)
    }
    /// the falling star's size through its fall, between the book's frames
    static func fallSize(_ t: Double) -> Double {
        let f = [1, 0.9, 0.7, 0.4, 0]
        let x = min(1, max(0, t)) * 4
        let i = min(3, Int(x))
        return f[i] + (f[i + 1] - f[i]) * (x - Double(i))
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

/// The stars: one per place left, placed once (the same sky every time), drifting left in three layers.
struct Stars: View {
    let count: Int
    let time: Double
    var body: some View {
        Canvas { ctx, size in
            var g = SeededRandom(seed: 987654)
            let speeds: [Double] = [0.8, 1.6, 2.8]
            for i in 0 ..< count {
                let u = g.next(), v = g.next(), s = g.next(), tw = g.next(), ph = g.next()
                let layer = i % 3
                var x = u * Double(size.width) - time * speeds[layer]
                x = x.truncatingRemainder(dividingBy: Double(size.width)); if x < 0 { x += Double(size.width) }
                let y = v * Double(size.height)
                // a clear space round the sun in the middle
                let dx = x - Double(size.width) / 2, dy = y - Double(size.height) / 2
                if dx * dx + dy * dy < 62 * 62 { continue }
                let r = 0.8 + s * 0.65 + (layer == 2 ? 0.35 : 0)
                // three in ten twinkle, softly
                let a = tw < 0.3 ? 0.3 + 0.6 * (0.5 - 0.5 * cos((time / 5.5 + ph) * 2 * .pi)) : 0.4 + s * 0.45
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Palette.white.opacity(a)))
            }
        }
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

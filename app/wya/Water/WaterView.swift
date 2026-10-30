import SwiftUI

/// The water on screen: clear glass on the droplet outline, what rides inside it, and the tab capsule with its three
/// tabs, which is its own glass the whole time. The sheet's glass and the capsule's glass are in one container, so out
/// of the capsule they are one body of water and at rest they are the capsule.
struct WaterView: View {
    let water: Water
    let map: MapController
    @Binding var tab: Int

    var body: some View {
        let f = water.form()
        let L = water.layout
        let shape = WaterShape(form: f)
        ZStack(alignment: .topLeading) {
            // the sheet's glass
            // the sheet's glass and the undo drop in one container: the drop is the water's own glass rising out of
            // its edge (Part 3.10), never glass on glass
            GlassEffectContainer(spacing: 20) {
                ZStack(alignment: .topLeading) {
                    if !Perf.shared.off.contains("sheetglass") {
                        Color.clear
                            .frame(width: L.W, height: L.H)
                            .glassEffect(.clear, in: shape)
                            .allowsHitTesting(false)
                    }
                    UndoDrop(water: water, form: f)
                }
                .frame(width: L.W, height: L.H, alignment: .topLeading)
            }

            // what rides inside it, cut only by the water's own curved outline (never a straight mask)
            if !Perf.shared.off.contains("sheet") {
                SheetContent(water: water, map: map, form: f)
                    .frame(width: L.W, height: L.H, alignment: .topLeading)
                    .mask(shape)
                    .allowsHitTesting(f.sheet > 0.5)
            }

            // the OpenStreetMap credit, on the map just above the water (outside the water's own outline)
            StartCredit(water: water, form: f)

            // the tabs sit on the water itself; at full the night leaves the capsule's place clear, so they are still
            // on that same glass
            if !Perf.shared.off.contains("tabs") { tabs(L) }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { g in
                    if !dragging { dragging = true; water.onTouch?(); water.begin(at: g.startLocation) }
                    water.move(to: g.location)
                }
                .onEnded { g in
                    dragging = false
                    water.end(velocity: g.velocity.height)
                }
        )
    }

    @State private var dragging = false

    /// the Map tab tapped again (the tab and the test driver run this one function)
    static func mapAgain(water: Water, map: MapController) {
        water.go(.quarter)
        map.goHome()
        water.onMapAgain?()
    }
    /// the logical Lists and Profile icons were a test; back to the square and the triangle; a new key, so a phone that
    /// stored the test's choice forgets it
    @AppStorage("tabIconsLogical2") private var logicalTabs = false

    private func tabs(_ L: Layout) -> some View {
        // the logical icons while he tests them (TabIconsTest.swift); off = the circle, square and triangle
        let keys = logicalTabs ? ["tab-map", "tab-lists-b", "tab-profile-b"] : ["tab-map", "tab-lists", "tab-profile"]
        let names = ["Map", "Lists", "Profile"]
        let spacing: CGFloat = (L.capsule.width - 8) / 3
        // the tabs are always on clear glass over the map (at full too), so always the dark ink
        let ink: Color = Palette.ink
        return ZStack(alignment: .topLeading) {
            ForEach(0 ..< 3, id: \.self) { i in
                Button {
                    if i == tab && i == 0 {
                        // the Map tab again resets, in one tap: the water to 25% and the map home, and what a reset
                        // closes (search, the tools, settings)
                        Self.mapAgain(water: water, map: map)
                    }
                    if i != tab { water.onTabChange?() }
                    tab = i
                    Feel.tap()
                    Sound.tap()
                } label: {
                    Icon5(key: keys[i], on: i == tab, ink: i == tab ? ink : ink.opacity(0.5), size: 24)
                        .frame(width: spacing, height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[i])
                .accessibilityAddTraits(i == tab ? .isSelected : [])
                .position(x: L.W / 2 + CGFloat(i - 1) * spacing, y: L.capsule.midY)
            }
        }
    }
}

/// THE FULL VIEW: at full the water is clear glass to the top with the map behind it, the solar system in the middle,
/// the head and the tabs staying black, a light mist and stars. `light` is the switch the build book asks for (2.6):
/// false brings back the dark night.
enum FullView {
    static let light = true
    /// whether the chrome turns white for the night at this point of the move to full
    static func night(_ page: CGFloat) -> Bool { !light && page > 0.55 }
}

/// What the water holds: at 25% the name and number; at 50% the system; at full the light space (BUILD-BOOK 2.6).
/// Everything in it moves with the water's top edge; nothing fades in or out. Closing, it all goes down with the
/// edge into the capsule and on under it; at full the words have gone up and off with the edge.
struct SheetContent: View {
    let water: Water
    let map: MapController
    let form: Water.Form

    var body: some View {
        let L = water.layout
        let (count, total) = map.count
        ZStack(alignment: .topLeading) {
            // the full view's space: the mist and the stars over the map (light), or the old night; either leaves the
            // capsule's place as the water's own clear glass
            Group {
                if Perf.shared.off.contains("stars") {
                    Color.clear
                } else {
                    PlasmaStars(page: form.page, top: form.top, stars: map.placesLeft, sun: CGPoint(x: L.W / 2, y: L.H / 2), map: map,
                                size: CGSize(width: L.W, height: L.H))
                }
            }
            .frame(width: L.W, height: L.H)
            .mask(CapsuleHole(capsule: L.capsule).fill(style: FillStyle(eoFill: true)))

            // MAP SETTINGS OPEN (Part 5, A5.1): the solar system moves down as one piece out through the
            // water's bottom, under the tabs, its own motion untouched (asked him; default), and back up on close
            if !Perf.shared.off.contains("cosmos") {
                CosmosView(water: water, map: map, form: form)
                    // (back only once the list's rows have left: never both at once)
                    .offset(y: water.settings || water.details || water.stampedList || water.listLeaving || water.upload ? water.layout.H - form.top : 0)
                    .animation(Motion.chrome, value: water.settings || water.details || water.stampedList || water.listLeaving || water.upload)
            }
            if water.settings { MapSettingsSheet(water: water, map: map, form: form) }
            // THE UPLOAD SHEET (Part 9.3) at 25%, the caption's words out while it is up
            if water.upload { UploadSheet(water: water, form: form).transition(.identity) }
            // DETAILS (Part 4.4): the same place in the water as settings, the Cosmos out of the way the same way
            // (its contents are there in one frame once the water has risen; no fade, no words rolling yet)
            if water.details && water.detailsWords {
                // the same place in the water holds Verify (4.5) when that is what opened it
                if VerifyState.shared.isOpen { VerifySheet(water: water, map: map, form: form).transition(.identity) }
                else { DetailsSheet(water: water, form: form).transition(.identity) }
            }
            // THE STAMPED LIST (Part 4.6) under the caption, which stays; hidden while Details from a row is up
            let captionY = max(L.headBottom + 12 + 52, form.top + 72)
            if (water.stampedList || water.listLeaving) && !water.details {
                StampedList(water: water, map: map, form: form, top: captionY + 56).transition(.identity)
            }

            // the name and number: at full they stay under the head
            if !Perf.shared.off.contains("caption") { Caption(name: map.moonHeld ? CosmosView.stops[map.filter] : map.sunPicked ? "Streak" : (map.continent ?? "World"),
                    count: map.sunPicked ? map.streakWeeks : count,
                    tail: map.sunPicked ? (map.streakWeeks == 1 ? "week" : "weeks") : "of \(total)",
                    night: FullView.night(form.page), visible: captionShown)
                // always 72 pt under the top edge; its words are there only when the whole caption fits in the water
                // above the capsule, and roll in and out by the text roll as the edge crosses that line (A2.5), so the
                // edge never cuts a word and no word passes over the tabs. Past half it rides the edge up at its full
                // size and stops under the head, where it stays at full.
                .position(x: L.W / 2, y: max(L.headBottom + 12 + 52, form.top + 72))
                // never drawn over the tabs: the water going down to the capsule moves faster than a roll, so the
                // last of a roll out is under the capsule's top (author's call, A2.5)
                .frame(width: L.W, height: L.H, alignment: .topLeading)
                .mask(alignment: .top) { Rectangle().frame(height: L.capsule.minY - 2) } }
            // THE NUMBER OPENS THE STAMPED LIST (4.6.2): at 25%, 50% or full while it shows your count; above 0 only
            // (at 0 it refuses); with the list up the same tap closes it
            if captionShown, !map.sunPicked, !map.moonHeld, !water.settings, !water.details, !water.upload {
                Color.clear
                    .frame(width: 180, height: 76)
                    .contentShape(Rectangle())
                    .position(x: L.W / 2, y: captionY + 4)
                    .onTapGesture {
                        if water.stampedList { Feel.tap(); water.closeList() }
                        else if count > 0 { Feel.tap(); CardState.shared.close(map: map); water.openList() }
                        else { Feel.refuse() }
                    }
                    .accessibilityLabel("Stamped list")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .onChange(of: captionFits, initial: true) { _, fits in
            // in on the quick curve; out faster (0.15 s), so it has gone before the edge comes down to the tabs
            if captionShown != fits { withAnimation(fits ? Motion.quick : .smooth(duration: Motion.reduce ? 0.1 : 0.15)) { captionShown = fits } }
        }
    }

    /// A2.5: the top at or above the capsule's top less 134 pt (PM 739, 17e 627: 10 pt under the 25% stop); and not
    /// on its way into the capsule (sent there, not held), so the words go as the water starts down, not after
    private var captionFits: Bool {
        form.top <= water.layout.capsule.minY - 134 && !(water.stop == .closed && !water.held) && !water.settings && !water.details
            && !water.upload
    }
    @State private var captionShown = false
}

/// THE FULL VIEW IS CLEAR GLASS WITH STARS: no field, no mist, nothing spreading from the sun; the water stays the
/// clear glass it is everywhere else, the map under it, the tabs on the same glass. Only the stars, one for each place
/// you have left. Each star is the sun's plasma and only that (; 11:39: "There's no white circle with a gray outline
/// ... It's just the plasma ... stop putting them at 50% opacity"): white tongues of light round a soft bright middle,
/// no disc, no rim, at full strength; small. White light can't be seen on the white land, so each star's light is
/// darkened as much as the ground under it needs: white over the sea, darker over land. They come with the water's top
/// edge, never all at once and never from a point in the middle: past half, as the edge goes up over a star, that star
/// grows out of its own middle to its size, and goes back into it as the edge comes down. Drawn from eight star
/// pictures made once (each a moment of the plasma), so a moving sheet only places pictures; at rest nothing is drawn
/// again.
struct PlasmaStars: View {
    let page: CGFloat
    let top: CGFloat
    let stars: Int
    let sun: CGPoint
    let map: MapController
    let size: CGSize
    @State private var sprites: [Image] = []
    /// how dark each star is drawn (0 white light; more over light ground: MapController.groundDark), worked out once
    /// as the view heads for full, before any star shows, so a star never changes while it is seen
    @State private var dark: [Double] = []

    static let sprite: CGFloat = 30
    /// the plasma's own radius as a share of the picture (its light reaches about three times as far)
    static let disc: CGFloat = 0.22

    var body: some View {
        // past half the stars can come; each as the edge has gone 28 points above it
        let open = Flow.smooth(0.5, 0.8, page)
        ZStack {
            // below half nothing is drawn at all (not even an empty canvas each frame the sheet moves)
            if open > 0 && !sprites.isEmpty { canvas(open: open) }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .task { if sprites.isEmpty { sprites = Self.makeSprites(); Self.shared = sprites } }
        // WORKED OUT AHEAD, OFF THE MAIN THREAD (Step 1c found it: done all at once as the sheet headed for full it held
        // the screen 350 ms, 229 stars x 3 lookups; then done a few stars a frame on the main thread it still took a few
        // ms of every frame of the next pan or pinch): once each time the camera comes to rest or the marks change, a
        // quarter second later, every lookup on a background thread; the stars only show past half way to full, by
        // when it is long done
        .task(id: Key(stars: drawn, rest: map.restVersion, marks: map.stamped.count &* 4096 &+ map.wished.count,
                      w: Int(size.width), h: Int(size.height))) {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            #if DEBUG
            let t0 = CACurrentMediaTime()
            #endif
            let stars = drawn
            var g = SeededRandom(seed: 987654)
            var pts: [CGPoint] = []
            pts.reserveCapacity(stars * 3)
            for _ in 0 ..< stars {
                let u = g.next(), v = g.next(); _ = g.next(); _ = g.next()
                let x = u * Double(size.width), y = v * Double(size.height)
                pts += [CGPoint(x: x, y: y), CGPoint(x: x - 4, y: y), CGPoint(x: x + 4, y: y)]
            }
            let d = await map.groundDark(at: pts)
            if Task.isCancelled { return }
            dark = (0 ..< stars).map { (d[3 * $0] + d[3 * $0 + 1] + d[3 * $0 + 2]) / 3 }
            Self.sharedDark = dark
            #if DEBUG
            NSLog("wya stars grounds %d stars over %.0f ms", stars, (CACurrentMediaTime() - t0) * 1000)
            #endif
        }
    }

    /// THE STARS IN ONE CANVAS DRAWN BY THE GPU (Step 1c: drawn by the CPU into a screen-sized picture, every frame of the
    /// move to full cost 8 ms and 14 late frames in 120; as 229 separate layers the render server fell to 20 frames a
    /// second). In a drawing group each star is one textured square on the GPU; each picture is resolved once a frame.
    private func canvas(open: CGFloat) -> some View {
        // the stars falling now are drawn by the Cosmos, which knows where their planets are (A2.20)
        let air = stars ..< stars + map.flying
        return Canvas { ctx, size in
            var g = SeededRandom(seed: 987654)
            var resolved: [Int: GraphicsContext.ResolvedImage] = [:]
            for i in 0 ..< drawn {
                let u = g.next(), v = g.next(), s = g.next(), k = g.next()
                if air.contains(i) { continue }
                let x = u * Double(size.width), y = v * Double(size.height)
                if hypot(x - Double(sun.x), y - Double(sun.y)) < 64 { continue }
                let grow = Double(open) * min(1, max(0, (y - Double(top)) / 28))
                guard grow > 0.01 else { continue }
                // most small, a few bigger, as real brightness goes: seen by being full white light, not by size
                let scale = Self.scale(s) * grow
                let w = Double(Self.sprite) * scale
                // the same plasma, its light darkened as much as the ground under it needs (white over the sea): one of
                // the pictures already darkened to the nearest level (a filter per star cost a layer per star, every
                // frame the sheet moved; Step 1c)
                let n = Self.picture(i, k: k, dark: dark, count: sprites.count)
                let r = resolved[n] ?? ctx.resolve(sprites[n])
                resolved[n] = r
                ctx.draw(r, in: CGRect(x: x - w / 2, y: y - w / 2, width: w, height: w))
            }
        }
        .drawingGroup()
    }

    private struct Key: Hashable { let stars: Int; let rest: Int; let marks: Int; let w: Int; let h: Int }

    /// the places left, and the stamped ones whose star has not fallen yet (they stay where they were until then)
    private var drawn: Int { stars + map.falls.count }
    /// a star's size for its third number (most small, a few bigger)
    static func scale(_ s: Double) -> Double { 0.3 + 0.4 * pow(s, 2.4) }
    /// which picture star i is drawn with: its darkness level, then one of that level's eight moments
    static func picture(_ i: Int, k: Double, dark: [Double], count: Int) -> Int {
        let d = i < dark.count ? dark[i] : 0
        let level = levels.indices.min { abs(levels[$0] - d) < abs(levels[$1] - d) } ?? 0
        let set = count / levels.count
        return level * set + Int(k * Double(set)) % set
    }
    /// star i where it sits in a view of this size (nil when it is never drawn: too close to the sun), its size and
    /// its picture, for the Cosmos to draw it as it falls
    @MainActor static func star(_ i: Int, size: CGSize, sun: CGPoint) -> (at: CGPoint, scale: Double, picture: Int)? {
        guard !shared.isEmpty else { return nil }
        var g = SeededRandom(seed: 987654)
        for _ in 0 ..< i { _ = g.next(); _ = g.next(); _ = g.next(); _ = g.next() }
        let u = g.next(), v = g.next(), s = g.next(), k = g.next()
        let x = u * Double(size.width), y = v * Double(size.height)
        if hypot(x - Double(sun.x), y - Double(sun.y)) < 64 { return nil }
        return (CGPoint(x: x, y: y), scale(s), picture(i, k: k, dark: sharedDark, count: shared.count))
    }
    /// the pictures and darknesses the stars were last drawn with, for the falling ones
    @MainActor static var shared: [Image] = []
    @MainActor static var sharedDark: [Double] = []

    /// the darkness levels a star is drawn at (the grounds' values and their means: sea, wished, stamped, land)
    static let levels: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.8]

    /// eight moments of the white plasma at each darkness level, drawn once (no disc, no rim, no shadow)
    @MainActor static func makeSprites() -> [Image] {
        levels.flatMap { d in (0 ..< 8).compactMap { i -> Image? in
            let content = Rectangle()
                .frame(width: sprite, height: sprite)
                .colorEffect(ShaderLibrary.starPlasma(.float2(Float(sprite), Float(sprite)), .float(Float(i) * 7.3 + 1),
                                                      .float(Float(disc)), .float(1.0)))
                .colorMultiply(Color(white: 1 - d))
            .frame(width: sprite, height: sprite)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            renderer.isOpaque = false
            return renderer.uiImage.map { Image(uiImage: $0) }
        } }
    }
}

/// Everything except the tab capsule's place.
nonisolated struct CapsuleHole: Shape {
    var capsule: CGRect
    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -200, dy: -200))
        p.addRoundedRect(in: capsule, cornerSize: CGSize(width: capsule.height / 2, height: capsule.height / 2), style: .continuous)
        return p
    }
}

/// The name and the count (Apple's way, as in Weather and Fitness): the name in SF semibold, the number big in SF
/// Rounded, the total at body size in the secondary ink, set tight on one centre line.
struct Caption: View {
    var name: String
    var count: Int
    var tail: String
    var night: Bool
    /// A2.5: the words there (rolled in) or not (each line a placeholder of spaces of about its width, never an empty
    /// string, which SwiftUI would insert with a blur and a fade); in rises, out goes down
    var visible = true
    @ScaledMetric(relativeTo: .largeTitle) private var big: CGFloat = 64

    var body: some View {
        let ink: Color = night ? Palette.white : Palette.ink
        let way = visible ? 1.0 : 0.0
        VStack(spacing: 0) {
            // a new name rolls in letter by letter, the way the number does, never swapped in place
            Text(visible ? name : Self.blank(name, "\u{2002}"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(ink)
                .contentTransition(.numericText(value: way))
                .animation(Motion.quick, value: name)
            Text(visible ? "\(count)" : Self.blank("\(count)", "\u{2007}"))
                .font(.system(size: big, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .contentTransition(.numericText(value: visible ? Double(count) : -1))
                .animation(Motion.quick, value: count)
                .padding(.top, -6)
            Text(visible ? tail : Self.blank(tail, "\u{2002}"))
                .font(.headline)
                .foregroundStyle(ink.opacity(0.5))
                .contentTransition(.numericText(value: way))
                .padding(.top, -8)
        }
        .multilineTextAlignment(.center)
        .fixedSize()
        // Apple's text styles (Part 0.8: title2 22, headline 17, the number 64 scaled with largeTitle), up to the
        // largest standard size: past it the caption would not fit above the capsule at 25% (the AX sizes are Part 19)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) \(tail)")
        .accessibilityHidden(!visible)
    }

    /// a line's placeholder: one space per character (en spaces for words, figure spaces for digits)
    static func blank(_ s: String, _ space: String) -> String { String(repeating: space, count: max(1, s.count)) }
}

/// THE START CREDIT: plain words on the map just above the water's top edge, at the sheet's inner left, no box of its
/// own; in and out by the text roll like every word; at each cold launch until 5 s or the first touch on the map, while
/// the water is low enough for its caption.
struct StartCredit: View {
    let water: Water
    let form: Water.Form
    @State private var shown = false
    var body: some View {
        let L = water.layout
        // (and not above 50%: higher, the water's top is under the head and the words would sit over the status bar)
        let fits = form.top <= L.capsule.minY - 134 && form.top >= L.top(.half) - 2 && !(water.stop == .closed && !water.held)
        Text(shown ? "© OpenStreetMap" : "\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}")
            .font(.caption)
            .foregroundStyle(Palette.ink.opacity(0.5))
            .contentTransition(.numericText(value: shown ? 1 : 0))
            .fixedSize()
            .padding(.leading, L.sheetInset + 16)
            .padding(.top, form.top - 22)
            .frame(width: L.W, height: L.H, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(!shown)
            .accessibilityLabel("Map data from OpenStreetMap")
            .onChange(of: water.credit && fits) { _, on in withAnimation(on ? Motion.quick : .smooth(duration: 0.15)) { shown = on } }
    }
}

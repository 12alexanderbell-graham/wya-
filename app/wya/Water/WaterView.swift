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
            Color.clear
                .frame(width: L.W, height: L.H)
                .glassEffect(.clear, in: shape)
                .allowsHitTesting(false)

            // what rides inside it, cut only by the water's own curved outline (never a straight mask)
            SheetContent(water: water, map: map, form: f)
                .frame(width: L.W, height: L.H, alignment: .topLeading)
                .mask(shape)
                .allowsHitTesting(f.sheet > 0.5)

            // the tabs sit on the water itself; at full the night leaves the capsule's place clear, so they are still
            // on that same glass
            tabs(L)
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

    private func tabs(_ L: Layout) -> some View {
        let keys = ["tab-map", "tab-lists", "tab-profile"]
        let names = ["Map", "Lists", "Profile"]
        let spacing: CGFloat = (L.capsule.width - 8) / 3
        // the tabs are always on clear glass over the map (at full too), so always the dark ink
        let ink: Color = Palette.ink
        return ZStack(alignment: .topLeading) {
            ForEach(0 ..< 3, id: \.self) { i in
                Button {
                    if i == tab && i == 0 {
                        // the Map tab again: a sheet goes back to its rest, else the map flies home
                        if water.stop != .quarter { water.go(.quarter) } else { map.goHome() }
                    }
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
/// the head and the tabs staying black, a light mist and stars. `light` is the switch the build book asks for (2.6:
/// "built behind a switch, the old look kept until it passes"): false brings back the dark night.
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
        // how far out of the capsule it is (0 in it, 1 at 25%): the words sit a little lower until then, so they
        // go down into the water with the edge and never sit in the capsule
        let rise = Flow.clamp01((L.capsule.minY - form.top) / max(1, L.capsule.minY - L.top(.quarter)))
        ZStack(alignment: .topLeading) {
            // the full view's space: the mist and the stars over the map (light), or the old night; either leaves the
            // capsule's place as the water's own clear glass
            Group {
                if FullView.light {
                    PlasmaStars(page: form.page, top: form.top, stars: map.placesLeft, sun: CGPoint(x: L.W / 2, y: L.H / 2), map: map,
                                size: CGSize(width: L.W, height: L.H))
                } else {
                    NightSky(page: form.page, stars: map.placesLeft, edge: form.top)
                }
            }
            .frame(width: L.W, height: L.H)
            .mask(CapsuleHole(capsule: L.capsule).fill(style: FillStyle(eoFill: true)))

            if !Perf.shared.off.contains("cosmos") { CosmosView(water: water, map: map, form: form) }

            // at full there is no text: the name and number ride the edge up and off the top
            Caption(name: map.moonHeld ? CosmosView.stops[map.filter] : map.sunPicked ? "Streak" : (map.continent ?? "World"),
                    count: map.sunPicked ? map.streakWeeks : count,
                    tail: map.sunPicked ? (map.streakWeeks == 1 ? "week" : "weeks") : "of \(total)",
                    night: FullView.night(form.page))
                // it hangs from the top edge: out of the capsule it comes down from behind the edge into its place, so
                // it never passes over the tabs. Past half it rides the edge up at its full size and stops under the
                // head, where it stays at full. The edge goes on past it, so the edge is never over the words.
                .position(x: L.W / 2, y: max(L.headBottom + 12 + 52, form.top + 72 - (1 - rise) * 170))
        }
    }
}

/// THE FULL VIEW IS CLEAR GLASS WITH STARS: no field, no mist, nothing spreading from the sun; the water stays the
/// clear glass it is everywhere else, the map under it, the tabs on the same glass. Only the stars, one for each place
/// you have left. Each star is the sun's plasma and only that: white tongues of light round a soft bright middle, no
/// disc, no rim, at full strength; small. White light can't be seen on the white land, so each star's light is darkened
/// as much as the ground under it needs: white over the sea, darker over land. They come with the water's top edge,
/// never all at once and never from a point in the middle: past half, as the edge goes up over a star, that star grows
/// out of its own middle to its size, and goes back into it as the edge comes down. Drawn from eight star pictures made
/// once (each a moment of the plasma), so a moving sheet only places pictures; at rest nothing is drawn again.
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
        Canvas { ctx, size in
            guard !sprites.isEmpty else { return }
            var g = SeededRandom(seed: 987654)
            // past half the stars can come; each as the edge has gone 28 points above it
            let open = Flow.smooth(0.5, 0.8, page)
            for i in 0 ..< stars {
                let u = g.next(), v = g.next(), s = g.next(), k = g.next()
                let x = u * Double(size.width), y = v * Double(size.height)
                if hypot(x - Double(sun.x), y - Double(sun.y)) < 64 { continue }
                let grow = Double(open) * min(1, max(0, (y - Double(top)) / 28))
                guard grow > 0.01 else { continue }
                // most small, a few bigger, as real brightness goes: seen by being full white light, not by size
                let scale = (0.3 + 0.4 * pow(s, 2.4)) * grow
                let w = Double(Self.sprite) * scale
                let img = sprites[Int(k * Double(sprites.count)) % sprites.count]
                let d = i < dark.count ? dark[i] : 0
                var c = ctx
                // the same plasma, its light darkened as much as the ground under it needs (white over the sea)
                if d > 0.01 { c.addFilter(.colorMultiply(Color(white: 1 - d))) }
                c.draw(img, in: CGRect(x: x - w / 2, y: y - w / 2, width: w, height: w))
            }
        }
        .allowsHitTesting(false)
        .task { if sprites.isEmpty { sprites = Self.makeSprites() } }
        .task(id: Key(coming: page > 0.3, stars: stars)) { if page > 0.3 { dark = grounds() } }
    }

    private struct Key: Hashable { let coming: Bool; let stars: Int }

    /// each star's darkness: the ground at its middle and either side of it (so a star on a coast takes the mean)
    private func grounds() -> [Double] {
        var g = SeededRandom(seed: 987654)
        var out: [Double] = []
        out.reserveCapacity(stars)
        for _ in 0 ..< stars {
            let u = g.next(), v = g.next(); _ = g.next(); _ = g.next()
            let x = u * Double(size.width), y = v * Double(size.height)
            let pts = [CGPoint(x: x, y: y), CGPoint(x: x - 4, y: y), CGPoint(x: x + 4, y: y)]
            out.append(pts.map { map.groundDark(at: $0) }.reduce(0, +) / Double(pts.count))
        }
        return out
    }

    /// eight moments of the white plasma, drawn once (no disc, no rim, no shadow)
    @MainActor static func makeSprites() -> [Image] {
        (0 ..< 8).compactMap { i in
            let content = Rectangle()
                .frame(width: sprite, height: sprite)
                .colorEffect(ShaderLibrary.starPlasma(.float2(Float(sprite), Float(sprite)), .float(Float(i) * 7.3 + 1),
                                                      .float(Float(disc)), .float(1.0)))
            .frame(width: sprite, height: sprite)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            renderer.isOpaque = false
            return renderer.uiImage.map { Image(uiImage: $0) }
        }
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

    var body: some View {
        let ink: Color = night ? Palette.white : Palette.ink
        VStack(spacing: 0) {
            // a new name rolls in letter by letter, the way the number does, never swapped in place
            Text(name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .animation(Motion.quick, value: name)
            Text("\(count)")
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .contentTransition(.numericText(value: Double(count)))
                .animation(Motion.quick, value: count)
                .padding(.top, -6)
            Text(tail)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.opacity(0.5))
                .padding(.top, -8)
        }
        .multilineTextAlignment(.center)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(count) \(tail)")
    }
}

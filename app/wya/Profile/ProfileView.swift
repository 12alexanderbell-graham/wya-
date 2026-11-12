import SwiftUI

/// THE PROFILE AT REST: one screen that does not scroll. The living gradient edge to edge, and on it one centred
/// column: your picture, your name in the app's own font, your handle, your code and your bio. Every size is one the
/// app already has: the picture is three 44 pt controls across, the gaps are the 16 pt side margin, the words are
/// Apple's text sizes. The column is placed once, for a name of one line and a bio of two: that column's middle is the
/// middle of the room between the top safe edge and the water at 25%. The picture stays exactly there whatever the
/// words under it are (a longer name or bio runs further down; a missing line leaves its room), and wherever the water
/// is pulled. The three numbers are in the water (ProfileWater).
struct ProfileView: View {
    let water: Water
    @State private var store = ProfileStore.shared

    static let picture: CGFloat = 132
    static let gap: CGFloat = 16
    /// the column the page is placed for: the picture, the name's line, the handle's, the code's, two lines of bio
    static let column: CGFloat = picture + gap + 41 + 4 + 22 + gap + 25 + gap + 44
    /// the gradient's strength (saturation, power): the stronger pair the first app kept for a picture's gradient; at
    /// the field's own (1.16, 2.0) the page was pale. The test driver can set it to compare (0 0 = the field's own)
    static var look = SIMD2<Double>(1.42, 2.9)

    var body: some View {
        let L = water.layout
        let me = store.me
        let mid = (L.safeTop + L.top(.quarter)) / 2
        let top = (mid - Self.column / 2).rounded()
        ZStack(alignment: .topLeading) {
            LivingField(saturation: Self.look.x, power: Self.look.y)
                .frame(width: L.W, height: L.H)
            VStack(spacing: 0) {
                picture(me)
                if !me.name.isEmpty {
                    Text(me.name)
                        .font(Typeface.nature(34, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .padding(.top, Self.gap)
                }
                if !store.handleShown.isEmpty {
                    Text(store.handleShown)
                        .font(.body)
                        .foregroundStyle(Palette.ink.opacity(0.5))
                        .lineLimit(1)
                        // (clear of the name's descenders)
                        .padding(.top, 4)
                }
                if !me.code.isEmpty {
                    Text(me.code)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .padding(.top, Self.gap)
                }
                if !me.bio.isEmpty {
                    Text(me.bio)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                        .padding(.top, Self.gap)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: L.W - 2 * L.circle)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(width: L.W, height: L.H - top, alignment: .top)
            .offset(y: top)
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        // (the map is under this page: no touch goes through to it)
        .contentShape(Rectangle())
        .onTapGesture {}
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
        .accessibilityElement(children: .contain)
    }

    /// the picture: a full circle with no outline; with no photo, the first letter of your name in the app's font
    private func picture(_ me: ProfileStore.Me) -> some View {
        ZStack {
            Circle().fill(Palette.ink)
            if let first = me.name.trimmingCharacters(in: .whitespaces).first {
                Text(String(first).uppercased())
                    .font(Typeface.nature(Self.picture * 0.5, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.white)
                    .dynamicTypeSize(.large)
            }
        }
        .frame(width: Self.picture, height: Self.picture)
        .accessibilityHidden(true)
    }
}

/// THE PROFILE'S WATER AT 25%: the three numbers, your stats, your stamps and your badge levels, in three equal columns
/// across the water, each the map sheet's own big number at the very height the map's number has (76 pt under the
/// water's top), so your stamps in the middle stand where the map's count stands. No words, no boxes, no marks. They count up the first time the Profile is opened after
/// the app starts; they are there only while the whole line fits above the capsule and roll out before the water's
/// edge comes down to them, as the map's caption does.
struct ProfileWater: View {
    let water: Water
    let form: Water.Form
    let map: MapController
    /// the Map tab, as its button opens it (the stamps number's tap)
    var openMap: () -> Void = {}
    @State private var numbers = ProfileNumbers.shared
    @State private var shown = false
    /// how far the count up has come, 0...1 (1 once it has run)
    @State private var run: Double = ProfileWater.counted ? 1 : 0
    /// the count up has run since the app started
    static var counted = false
    @ScaledMetric(relativeTo: .largeTitle) private var big: CGFloat = 64

    var body: some View {
        let L = water.layout
        let column = (L.W - 2 * L.sheetInset) / 3
        let values = [numbers.stats, numbers.stamps, numbers.badges]
        let names = ["stats", "stamps", "badge levels"]
        // (four digits and more: all three a size down together, so each still fits its column)
        let size: CGFloat = (values.max() ?? 0) >= 1000 ? big * 0.75 : big
        let fits = form.top <= L.capsule.minY - 134 && !(water.stop == .closed && !water.held)
        ZStack(alignment: .topLeading) {
            if numbers.ready {
                ForEach(0 ..< 3, id: \.self) { i in
                    let v = Int((Double(values[i]) * run).rounded())
                    Text(shown ? v.formatted() : Caption.blank(values[i].formatted(), "\u{2007}"))
                        .font(.system(size: size, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .contentTransition(run < 1 ? .identity : .numericText(value: shown ? Double(v) : -1))
                        .frame(width: column)
                        .position(x: L.W / 2 + CGFloat(i - 1) * column, y: form.top + 76)
                        .accessibilityLabel("\(values[i]) \(names[i])")
                        // (the stamps number is read as its button, below)
                        .accessibilityHidden(i == 1)
                }
            }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        // (never drawn over the tabs)
        .mask(alignment: .top) { Rectangle().frame(height: L.capsule.minY - 2) }
        .allowsHitTesting(false)
        // THE STAMPS NUMBER OPENS YOUR MAP, as you left it (each number opens what it counts; the stats and the badge
        // levels have no pages yet, so they take no tap)
        .overlay(alignment: .topLeading) {
            if numbers.ready, shown {
                Color.clear
                    .frame(width: column, height: max(44, size + 12))
                    .contentShape(Rectangle())
                    .onTapGesture { openMap() }
                    .position(x: L.W / 2, y: form.top + 76)
                    .accessibilityElement()
                    .accessibilityLabel("\(numbers.stamps) stamps")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { openMap() }
            }
        }
        .onChange(of: fits, initial: true) { was, f in
            guard shown != f else { return }
            // (the tab opening: the numbers are simply there; the water pulled: they roll out and in at its edge)
            if was == f || water.tabSwitching { shown = f }
            else { withAnimation(f ? Motion.quick : .smooth(duration: Motion.reduce ? 0.1 : 0.15)) { shown = f } }
        }
        // (counted again when your marks change, and when the map's own count does: the Count setting, the borders)
        .task(id: numbers.asks + " \(map.shares["World"]?.have ?? -1)/\(map.shares["World"]?.total ?? -1) \(CountKind.current)") {
            await numbers.count(map: map)
        }
        .task(id: numbers.ready) {
            // THE COUNT UP, once: from nought to each number over 0.8 s, quick first and slowing to the end
            guard numbers.ready, !Self.counted else { return }
            Self.counted = true
            if Motion.reduce { run = 1; return }
            // (plain steps, each digit simply the next: a roll on every step smeared the digits into each other)
            let steps = 24
            for k in 1 ... steps {
                try? await Task.sleep(for: .milliseconds(34))
                let t = Double(k) / Double(steps)
                run = 1 - pow(1 - t, 3)
            }
            run = 1
        }
    }
}

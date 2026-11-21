import SwiftUI
import PhotosUI

/// EDITING YOUR PROFILE ON THE PROFILE ITSELF: no Edit button and no other screen. A tap on your name, handle or bio
/// makes that line its own text box where it stands (the keyboard's Done, or a tap anywhere else, keeps it); a tap on
/// the picture brings the picture sheet into the water at 50% (the colour picker, Upload, your flags); a tap on the
/// nationalities line brings your nationalities there. Pulling the water down puts a sheet away.
@MainActor
@Observable
final class ProfileEdit {
    static let shared = ProfileEdit()
    enum Field: Hashable { case name, handle, bio }
    enum Sheet { case picture, nationalities, ground, stats, badges }
    /// the line being typed in
    var field: Field? {
        didSet {
            // the handle's typing begun and ended: what it was, and whether it changed (its window, W06)
            if field == .handle, oldValue != .handle { handleBefore = ProfileStore.shared.me.handle }
            if oldValue == .handle, field != .handle { ProfileStore.shared.handleEdited(from: handleBefore) }
        }
    }
    @ObservationIgnored private var handleBefore = ""
    /// the handle tapped while its window is shut: the line says when it opens, for a moment
    var handleLockedNote = false
    /// what the water holds instead of the three numbers
    private(set) var sheet: Sheet?
    /// the nationalities' search is being typed in (the water goes to full, clear of the keyboard)
    var searching = false
    /// your photos are open to choose the picture from
    var choosingPhoto = false
    /// what is typed in the nationalities' search
    var query = ""
    /// the badge shown alone in your badges (nil: all of them)
    var badge: String?

    func open(_ s: Sheet, water: Water) {
        field = nil
        searching = false
        if s == .stats || s == .badges {
            withAnimation(Motion.chrome) { sheet = s }
            water.go(.closed)
            return
        }
        sheet = s
        water.go(.half)
        // (the water could not rise: no sheet left hidden under 25%)
        if water.stop != .half { sheet = nil }
    }
    /// the sheet put away; `move: false` when the water has already gone down by itself
    func close(water: Water, move: Bool = true) {
        guard sheet != nil else { return }
        sheet = nil
        searching = false
        query = ""
        badge = nil
        if move { water.go(.quarter) }
    }
    /// a tap off whatever is being edited: typing ends (kept), a sheet goes
    func end(water: Water) {
        field = nil
        close(water: water)
    }

    // MARK: your nationalities

    /// as place ids ("de", "us"), the first being the passport the app shows (Part 14): the map's home, search's
    /// suggestions and a place's visa line read the same list
    var nationalities: [String] = UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []
    func setNationalities(_ n: [String], map: MapController) {
        nationalities = n
        if n.isEmpty { UserDefaults.standard.removeObject(forKey: MapController.nationalitiesKey) }
        else { UserDefaults.standard.set(n, forKey: MapController.nationalitiesKey) }
        map.refreshHome()
        // a flag picture whose nationality went is your initial again
        if let p = ProfileStore.shared.me.picture, p.hasPrefix("flag:"), !n.contains(String(p.dropFirst(5))) {
            ProfileStore.shared.set { $0.picture = nil }
        }
    }
}

extension ColourPick {
    /// as sRGB, 0 to 1 (what the living gradient draws in)
    var srgb: SIMD3<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(min(1, max(0, Double(r))), min(1, max(0, Double(g))), min(1, max(0, Double(b))))
    }
    /// an sRGB colour (0 to 1) as the picker holds it (OKLab, Björn Ottosson's): where the picker's marker starts for
    /// one of the app's own colours
    static func from(srgb c: SIMD3<Double>) -> ColourPick {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let r = lin(c.x), g = lin(c.y), b = lin(c.z)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let h = (atan2(B, A) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let light = min(lightTop, max(lightBottom, L))
        let most = OKLCH.maxChroma(light: light, hue: h)
        return ColourPick(hue: h, light: light, strength: most > 0 ? min(1, (A * A + B * B).squareRoot() / most) : 0)
    }
    /// the living gradient's own four (teal, lime, blue, cream) as picks
    @MainActor static let field: [ColourPick] = ["teal", "lime", "blue", "cream"].map { from(srgb: Palette.named[$0] ?? .one) }
}

/// THE BACKGROUND SHEET (water at 50%): the living gradient's colours, two to four, as circles, the one being changed
/// in the picker's own white ring, a plus for another while there are fewer than four, a hold on one to remove it while
/// there are more than two; under them the colour picker and the strength, the page behind following the finger
/// (its suggested colour your picture's)
struct ProfileGroundSheet: View {
    let width: CGFloat
    @State private var store = ProfileStore.shared
    @State private var at = 0
    @State private var pick = (ProfileStore.shared.me.ground ?? ColourPick.field)[0]

    private var four: [ColourPick] { store.me.ground ?? ColourPick.field }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ForEach(0 ..< four.count, id: \.self) { k in
                    Button {
                        Feel.tap()
                        at = k
                        pick = four[k]
                    } label: {
                        Circle().fill(four[k].color).frame(width: 44, height: 44)
                            .overlay { if k == at { Circle().strokeBorder(.white, lineWidth: 2) } }
                            .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(k == at ? 0.5 : 0.15), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if four.count > 2 {
                            Button("Remove", role: .destructive) { remove(k) }
                        }
                    }
                    .accessibilityLabel("Background colour \(k + 1)")
                    .accessibilityValue(ColourNames.name(four[k]))
                    .accessibilityAddTraits(k == at ? .isSelected : [])
                    .accessibilityAction(named: "Remove") { if four.count > 2 { remove(k) } }
                }
                // another colour (four at most): the one being changed again, to be moved on the picker
                if four.count < 4 {
                    Button {
                        Feel.tap()
                        var g = four
                        g.append(pick)
                        store.set { $0.ground = g }
                        at = g.count - 1
                    } label: {
                        Icon5(key: "plus", ink: Palette.ink, size: 20)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a colour")
                }
                Spacer(minLength: 0)
            }
            ColourPicker(colour: Binding(get: { pick }, set: { c in
                pick = c
                set(c, keep: false)
            }), suggested: store.me.picture == nil ? store.me.colour : nil, width: width) { c in set(c, keep: true) }
            // THE STRENGTH, calm to strong, the page behind following the finger; kept when it lifts
            Slider(value: Binding(get: { store.me.groundStrength ?? 0.5 }, set: { v in store.set({ $0.groundStrength = v }, keep: false) }),
                   in: 0 ... 1) { Text("Strength") } onEditingChanged: { on in
                if !on { store.set({ $0.groundStrength = store.me.groundStrength ?? 0.5 }, keep: true) }
            }
            .tint(Palette.ink)
            .accessibilityValue("\(Int(((store.me.groundStrength ?? 0.5) * 100).rounded())) percent")
        }
        .frame(width: width, alignment: .leading)
    }
    private func set(_ c: ColourPick, keep: Bool) {
        var g = four
        g[min(at, g.count - 1)] = c
        store.set({ $0.ground = g }, keep: keep)
    }
    private func remove(_ k: Int) {
        guard four.count > 2 else { return }
        Feel.lift()
        var g = four
        g.remove(at: k)
        store.set { $0.ground = g }
        at = min(at, g.count - 1)
        pick = g[at]
    }
}

/// YOUR STATS (the stats number's tap; the water at full): each group's title, then its rows, the name on the left
/// and the value on the right; in the "of 58" at 50%. A pull down puts it away.
struct ProfileStatsList: View {
    let width: CGFloat
    let room: CGFloat
    @State private var numbers = ProfileNumbers.shared
    /// the gaps between the rows (EdgeRows): the list's visible height ends in one, whole rows only
    @State private var cuts: [CGFloat] = []
    /// the list is scrolled (its top goes out softly)
    @State private var scrolled = false

    var body: some View {
        let all = numbers.groups.map { ($0.title, $0.rows) } + numbers.sections.map { ($0.name, $0.rows) }
        let h = EdgeRows.fit(room, cuts: cuts)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.offset) { i, g in
                    // (a size and a weight over its stats' bold names, so it still reads as their title)
                    Text(g.0).font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                        .padding(.top, i == 0 ? 8 : 36).padding(.bottom, 4)
                        .edgeRow()
                        .accessibilityAddTraits(.isHeader)
                    ForEach(g.1) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(r.label).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            // (a long value goes onto a second line, never cut off:)
                            value(r.value).lineLimit(3).multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                        }
                        .padding(.vertical, 6)
                        .frame(minHeight: 34)
                        .edgeRow()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .padding(.bottom, 16)
            .coordinateSpace(name: EdgeRows.space)
            .onPreferenceChange(EdgeRows.self) { cuts = EdgeRows.cuts($0) }
        }
        .scrollTargetBehavior(GapSnap(cuts: cuts))
        .scrollBlur()
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 1 }) { _, v in scrolled = v }
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: scrolled ? 20 : 0)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
            }
        }
        .frame(width: width, height: h, alignment: .top)
        .frame(width: width, height: room, alignment: .top)
    }
    /// : the count in black, "of 58" at 50%; anything else as it is; never bold (the stat's name is)
    private func value(_ v: String) -> Text {
        if let r = v.range(of: " of "), v[..<r.lowerBound].allSatisfy({ $0.isNumber || $0 == "," }) {
            return Text(v[..<r.lowerBound]).font(.body.monospacedDigit()).foregroundStyle(Palette.ink)
                + Text(" of " + v[r.upperBound...]).font(.body.monospacedDigit()).foregroundStyle(Palette.ink.opacity(0.5))
        }
        return Text(v).font(.body.monospacedDigit()).foregroundStyle(Palette.ink)
    }
}

/// A BADGE'S DISC: a full circle in its level's colour, no icon and no number on it. Lime, blue, silver (the palette's
/// grey), gold (its yellow), diamond (white under clear glass, the shine)
struct BadgeDisc: View {
    let level: Int
    let size: CGFloat
    static func colour(_ l: Int) -> Color { [Palette.lime, Palette.lime, Palette.blue, Palette.grey, Palette.yellow, Palette.white][min(max(l, 0), 5)] }
    var body: some View {
        Circle().fill(Self.colour(level))
            .overlay { if level >= 5 { Circle().fill(.clear).glassEffect(.clear, in: .circle) } }
            .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
            .frame(width: size, height: size)
    }
}

/// YOUR BADGES (the badge levels' number; the water at full): three across, highest levels first, each its disc and
/// its name; a tap shows it alone (its level, what you have, what the next level needs, what it counts), the back
/// arrow returns to all of them
struct ProfileBadgesList: View {
    let width: CGFloat
    let room: CGFloat
    @State private var numbers = ProfileNumbers.shared
    @State private var edit = ProfileEdit.shared
    @State private var pos = ScrollPosition(edge: .top)
    private var open: String? {
        get { edit.badge }
        nonmutating set { edit.badge = newValue }
    }

    private var all: [Badge] { Self.order(numbers.earned) }
    static func order(_ earned: [Badge]) -> [Badge] {
        earned.sorted { $0.level != $1.level ? $0.level > $1.level : $0.name < $1.name }
    }
    /// THE FIRST SCREEN OF BADGE PICTURES MADE AHEAD: each is made on the main thread (its solid, the studio's light
    /// the first time, the render), 860 ms for the first and 40 to 80 ms for each after, so the Badges page froze for
    /// up to 2 s as it slid in. Made one at a time while the Profile sits still, they are there when it is tapped.
    @MainActor private static var warmed = false
    @MainActor static func prewarm(width: CGFloat, scale: CGFloat) async {
        guard !warmed else { return }
        let numbers = ProfileNumbers.shared
        for _ in 0 ..< 20 where !numbers.ready { try? await Task.sleep(for: .milliseconds(250)) }
        guard numbers.ready, !Task.isCancelled else { return }
        warmed = true
        let cell = (width - 2 * 12) / 3
        let px = Int((min(88, cell - 8) * scale).rounded())
        for b in order(numbers.earned).prefix(18) {
            guard !Task.isCancelled else { warmed = false; return }
            let form = BadgeArt.shared.form(b), level = BadgeLevel.of(b)
            if BadgeArt.shared.cached(form, level, px: px) == nil { _ = await BadgeArt.shared.image(form, level, px: px, scale: scale) }
            // (a breath between them, so a touch or a frame never waits behind more than one)
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
    static func value(_ b: Badge, _ n: Int) -> String {
        switch b.unit {
        case .percent: return "\(n)%"
        case .km: return "\(n.formatted()) km"
        case .metres: return "\(n.formatted()) m"
        case .tenthDegrees: return String(format: "%.1f°", Double(n) / 10)
        case .count: return n.formatted()
        }
    }

    var body: some View {
        if let id = open, let b = all.first(where: { $0.id == id }) { one(b) } else { grid }
    }

    private var grid: some View {
        let cols = 3, gap: CGFloat = 12
        let cell = (width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap, alignment: .top), count: cols), spacing: 20) {
                ForEach(all) { b in
                    VStack(spacing: 8) {
                        BadgeArtView(badge: b, size: min(88, cell - 8), trim: true)
                        Text(b.name).font(.subheadline).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(width: cell)
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); open = b.id }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(b.name), \(Badges.levelName[min(b.level, 5)])")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .scrollTargetLayout()
            .padding(.top, 8).padding(.bottom, 16)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollBlur()
        .scrollPosition($pos)
        #if DEBUG
        .onChange(of: ScrollTest.shared.y) { _, y in pos.scrollTo(y: y) }
        #endif
        .scrollIndicators(.hidden)
        .frame(width: width, height: room)
    }

    /// A BADGE'S OWN PAGE: the badge as wide as the page lets it be, its name and level, what you have against the
    /// next level, the five levels with the one you are at, and, for a badge about a set of places, those places, the
    /// ones you have in black and the rest at 50%.
    private func one(_ b: Badge) -> some View {
        let next = b.steps.first { $0 > b.have }
        let ms = BadgeForm.members(b) ?? []
        let mine = ProfileNumbers.shared.mine
        let book = BadgeArt.shared.world.flatMap { BadgeStore.shared.book($0) }
        let names = ms.compactMap { cc in book?.world.places[cc].map { (cc, $0.s) } }.sorted { $0.1 < $1.1 }
        return ScrollView {
            VStack(spacing: 0) {
                BadgeLiveView(badge: b, size: min(width - 40, 300), hug: true)
                    .padding(.top, 4)
                Text(b.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center).padding(.top, 20)
                // its level, and the day it was reached where the app saw it
                Text(Badges.levelName[min(b.level, 5)] + (BadgeMoment.day(b.id, b.level).map { " on " + $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""))
                    .font(.body).foregroundStyle(Palette.ink.opacity(0.5)).padding(.top, 4)
                // what you have, and the next level's number at 50%
                (Text(Self.value(b, b.have)).font(.system(size: 44, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                 + Text(next.map { " of " + Self.value(b, $0) + " for " + Badges.levelName[min(5, b.level + 1)] } ?? "")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.5)))
                    .monospacedDigit()
                    .padding(.top, 20)
                // THE FIVE LEVELS, each its number over its name: reached in black, still to come at 50%
                if b.steps.count == 5 {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in
                            VStack(spacing: 2) {
                                Text(Self.value(b, b.steps[i])).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                                Text(Badges.levelName[i + 1]).font(.footnote)
                            }
                            .foregroundStyle(Palette.ink.opacity(b.level > i ? 1 : 0.5))
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 28)
                }
                // (a set's own sentence named every place again, with no word of which ones are yours)
                if names.isEmpty || b.family != "groups" {
                    Text(b.what).font(.body).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center).padding(.top, 28)
                }
                // THE PLACES IT IS ABOUT: yours in black, the rest at 50%
                if !names.isEmpty, names.count <= 80 {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 12) {
                        ForEach(names, id: \.0) { cc, n in
                            Text(n).font(.body).lineLimit(1)
                                .foregroundStyle(Palette.ink.opacity(mine.contains(cc) ? 1 : 0.5))
                                .accessibilityLabel(n + (mine.contains(cc) ? ", stamped" : ", not yet"))
                        }
                    }
                    .padding(.top, 28)
                }
            }
            .frame(width: width)
            .padding(.bottom, 24)
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
        .frame(width: width, height: room, alignment: .top)
    }
}

/// a country's flag in a circle (the picture's and the sheets' own size); nothing when the flag is missing
struct FlagCircle: View {
    let cc: String
    let size: CGFloat
    var body: some View {
        Group {
            if let f = Flags.square(cc) { f.resizable().interpolation(.high).scaledToFill() } else { Palette.ink.opacity(0.5) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
    }
}

/// THE PICTURE SHEET (water at 50%): the colour picker, the picture above taking the colour as the finger moves; then
/// your nationalities' flags; a photo by tapping the picture itself while this is up (Apple's photo picker: no permission
/// asked, the photo's middle square kept).
/// No preset colours, no premium.
struct ProfilePictureSheet: View {
    let water: Water
    let width: CGFloat
    @State private var store = ProfileStore.shared
    @State private var edit = ProfileEdit.shared
    @State private var item: PhotosPickerItem?
    @State private var pick = ProfileStore.shared.me.colour ?? ProfilePictureSheet.start

    /// THE SUGGESTED COLOUR, from what your profile already has: the strongest of your background's four
    private var suggested: ColourPick? {
        (store.me.ground ?? ColourPick.field).max { $0.strength * (1 - abs($0.light - 0.6)) < $1.strength * (1 - abs($1.light - 0.6)) }
    }
    /// the picker's spot before any colour is picked: the field at its full colour, the marker at its palest, where
    /// the picture is
    static let start = ColourPick(hue: 250, light: ColourPick.lightTop, strength: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ColourPicker(colour: Binding(get: { pick }, set: { c in
                pick = c
                store.set({ $0.colour = c; $0.picture = nil }, keep: false)
            }), suggested: suggested, width: width) { c in
                store.set { $0.colour = c; $0.picture = nil }
            }
            HStack(spacing: 12) {
                ForEach(edit.nationalities, id: \.self) { cc in
                    Button {
                        Feel.tap()
                        store.set { $0.picture = "flag:" + cc }
                    } label: { FlagCircle(cc: cc, size: 44) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Flag")
                }
                Spacer(minLength: 0)
            }
            .frame(width: width, height: 44)
        }
        .frame(width: width, alignment: .leading)
        // (a photo is chosen by tapping the picture itself while this sheet is up)
        .photosPicker(isPresented: Bindable(edit).choosingPhoto, selection: $item, matching: .images, photoLibrary: .shared())
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self) { Feel.tap(); await store.setPhoto(d) }
                else { Feel.refuse() }
                item = nil
            }
        }
    }
}

/// YOUR NATIONALITIES (water at 50%): one row each (flag, name), the first the passport the app shows; a tap on a row
/// makes it the first; its × takes it away. Under them, a field to add one: the countries whose names start with
/// what is typed (any word of the name from three letters), a tap adds it.
struct NationalitiesSheet: View {
    let water: Water
    let map: MapController
    let width: CGFloat
    let room: CGFloat
    @State private var edit = ProfileEdit.shared
    @FocusState private var typing: Bool
    private var query: String { edit.query }

    static let rowH: CGFloat = 56

    private func name(_ cc: String) -> String { map.world.flatMap { w in w.placeIndex[cc].map { w.places[$0].n } } ?? cc.uppercased() }
    private var found: [(id: String, n: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).townFolded
        guard let w = map.world else { return [] }
        let have = Set(edit.nationalities)
        // nothing typed: every country, A to Z, to pick from
        if q.isEmpty {
            let lived = { (id: String) in MarkStore.shared.state(.country(id)).lived }
            return w.places.filter { !have.contains($0.id) && $0.id.count == 2 }
                .sorted { a, b in
                    let la = lived(a.id), lb = lived(b.id)
                    return la != lb ? la : a.n.localizedStandardCompare(b.n) == .orderedAscending
                }
                .map { (id: $0.id, n: $0.n) }
        }
        var start: [(String, String)] = [], inside: [(String, String)] = []
        for p in w.places where !have.contains(p.id) {
            let f = p.n.townFolded
            if f.hasPrefix(q) { start.append((p.id, p.n)) }
            else if q.count >= 3, f.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { inside.append((p.id, p.n)) }
        }
        return Array((start.sorted { $0.1 < $1.1 } + inside.sorted { $0.1 < $1.1 }).prefix(5)).map { (id: $0.0, n: $0.1) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(edit.nationalities.enumerated()), id: \.element) { i, cc in
                    HStack(spacing: 12) {
                        FlagCircle(cc: cc, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name(cc)).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                            if i == 0 { Text("Passport").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)) }
                        }
                        Spacer(minLength: 8)
                        Button {
                            Feel.lift()
                            withAnimation(Motion.quick) { edit.setNationalities(edit.nationalities.filter { $0 != cc }, map: map) }
                        } label: {
                            Icon5Still(key: "cross", progress: 0, ink: Palette.white, size: 13)
                                .frame(width: 24, height: 24).background(Palette.ink, in: .circle)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove")
                    }
                    .frame(minHeight: Self.rowH)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard i > 0 else { return }
                        Feel.tap()
                        var n = edit.nationalities; n.remove(at: i); n.insert(cc, at: 0)
                        withAnimation(Motion.quick) { edit.setNationalities(n, map: map) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Show as passport") {
                        var n = edit.nationalities; n.remove(at: i); n.insert(cc, at: 0)
                        edit.setNationalities(n, map: map)
                    }
                }
                TextField("", text: Binding(get: { edit.query }, set: { edit.query = $0 }),
                          prompt: Text("Add a nationality").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.body).foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { if let f = found.first { add(f.id) } }
                    .frame(minHeight: Self.rowH)
                ForEach(found, id: \.id) { f in
                    HStack(spacing: 12) {
                        FlagCircle(cc: f.id, size: 28)
                        Text(f.n).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Self.rowH)
                    .contentShape(Rectangle())
                    .onTapGesture { add(f.id) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .scrollTargetLayout()
            .frame(width: width)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollBlur()
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: room)
        .onChange(of: typing) { _, t in
            edit.searching = t
            water.go(t ? .full : .half)
        }
    }
    private func add(_ cc: String) {
        Feel.tap()
        edit.query = ""
        withAnimation(Motion.quick) { edit.setNationalities(edit.nationalities + [cc], map: map) }
    }
}

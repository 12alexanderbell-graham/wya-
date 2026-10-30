import SwiftUI

/// REGIONS' LIST (BUILD-BOOK 6.3, as the old native app had it: RegionsList, map.js buildRegionList): the whole screen,
/// clear glass with the world under it, every country that has regions, by name; each row its square flag, its name,
/// and under it what its first level holds ("34 provinces", " · 2 stamped" once you have). It starts 10 pt under the head
/// and stops 10 pt above the tab bar, whole rows at rest, soft at both ends. The head's search is the list's search
/// (3 Oct). The rows ride the water's top edge as it comes up out of the capsule and go back down with it.
struct RegionsMenu: View {
    let water: Water
    let map: MapController
    let head: HeadState
    let form: Water.Form
    @State private var model = RegionsMenuModel.shared
    @State private var lifted: String?

    static let rowH: CGFloat = 56

    var body: some View {
        let L = water.layout
        let restTop = L.headBottom + 10
        // whole rows only, so no row sits cut at rest (0.7); the list's foot (and its soft edge) is where they end
        let h = max(Self.rowH, ((L.capsule.minY - 10 - restTop) / Self.rowH).rounded(.down) * Self.rowH)
        let bottom = restTop + h
        // with the water's top while it comes and goes; under the head once it is up
        let top = max(restTop, form.top + 8)
        let rows = shownRows
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    if rows.isEmpty, !query.isEmpty { missRow }
                    ForEach(rows) { r in row(r) }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollTargetBehavior(RowSnap(row: Self.rowH))
            .frame(width: L.W - 2 * L.sheetInset, height: h)
            .position(x: L.W / 2, y: top + h / 2)
            .onChange(of: query) { _, _ in reader.scrollTo("top", anchor: .top) }
            .onChange(of: water.regions) { _, on in if on { lifted = nil; reader.scrollTo("top", anchor: .top) } }
        }
        // soft at the top (under the head) and at the foot (above the tabs), never a straight cut (P3); the foot stays
        // where it is while the water moves, so rows going down with it leave through it
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            let mh = max(0, bottom - top)
            let f = mh > 0 ? min(0.5, 14 / mh) : 0.5
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: f),
                                   .init(color: .black, location: 1 - f), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: L.W, height: mh)
                .offset(y: top)
                .frame(width: L.W, height: L.H, alignment: .topLeading)
        }
        .allowsHitTesting(water.menuShown)
        .task(id: MarkStore.shared.changes) { await model.recount(map: map) }
        .onAppear { model.build(map: map) }
        .accessibilityElement(children: .contain)
    }

    private var query: String {
        head.searching ? head.query.trimmingCharacters(in: .whitespaces) : ""
    }

    /// the rows as the search leaves them: what matches, names starting with what you typed first (the head's own
    /// search order), only countries of the list
    private var shownRows: [RegionsMenuModel.Row] {
        guard !query.isEmpty else { return model.rows }
        let byPlace = Dictionary(model.rows.map { ($0.place, $0) }, uniquingKeysWith: { a, _ in a })
        return SearchResults.matches(map: map, query: query).compactMap { byPlace[$0] }
    }

    private func row(_ r: RegionsMenuModel.Row) -> some View {
        HStack(spacing: 12) {
            Group {
                if let f = Flags.square(r.flag) { f.resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: 28, height: 28)
            // the picked row's flag lifts 4 pt and grows to 1.1 about its centre (A6.7's first frame)
            .scaleEffect(lifted == r.id ? 1.1 : 1)
            .offset(y: lifted == r.id ? -4 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.headline).foregroundStyle(Palette.ink).lineLimit(2)
                Text(r.sub).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                    .contentTransition(.numericText(value: Double(r.count)))
                    .animation(Motion.quick, value: r.count)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: Self.rowH)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentShape(Rectangle())
        .onTapGesture { pick(r) }
        // APPLE'S MENU ON A ROW (11.5): Open its region map · Stamp the country (its page and Add to a list wait for
        // their parts)
        .contextMenu {
            Button("Open its region map") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pick(r) } }
            let stamped = MarkStore.shared.state(.country(r.id)).stamped
            Button(stamped ? "Unstamp the country" : "Stamp the country", role: stamped ? .destructive : nil) {
                ContentView.quickStamp(r.place, map: map)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.name), \(r.sub)")
        .accessibilityHint("Shows its regions")
        .accessibilityAddTraits(.isButton)
    }

    /// nothing matches: "Did you mean <name>?" (the nearest country of the list; a tap searches for it), else "No
    /// results" (the old app's guessNode)
    private var missRow: some View {
        let near = SearchResults.nearest(map: map, query: query).flatMap { i in model.rows.first { $0.place == i } }
        return Group {
            if let near {
                Text("Did you mean \(Text(near.name).fontWeight(.semibold))?")
                    .font(.body).foregroundStyle(Palette.ink)
                    .onTapGesture { Feel.tap(); head.query = near.name }
            } else {
                Text("No results").font(.body).foregroundStyle(Palette.ink)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: Self.rowH, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// a row tapped: its flag lifts, its region file starts loading, search closes; the flight into the country (6.4)
    private func pick(_ r: RegionsMenuModel.Row) {
        Feel.tap()
        withAnimation(Motion.quick) { lifted = r.id }
        if head.searching { head.searching = false }
        RegionsMenuModel.shared.load(r.flag)
        RegionsMenuModel.shared.onPick?(r)
    }
}

/// The menu's rows and their numbers, worked out once per launch (the list) and again as your region stamps change
/// (the numbers, off the main thread, reading only the files of countries you have stamped regions in).
@MainActor
@Observable
final class RegionsMenuModel {
    static let shared = RegionsMenuModel()
    struct Row: Identifiable, Equatable {
        let id: String
        let place: Int
        let name: String
        /// the place's id as the bundled files and flags name it (lower case)
        let flag: String
        let row: Int
        let total: Int
        /// the first level's word, singular and plural, lower case ("province", "provinces")
        let one: String
        let many: String
        var count: Int
        /// "34 provinces", and " · 2 stamped" once you have
        var sub: String {
            let n = "\(total.formatted()) \(total == 1 ? one : many)"
            return count > 0 ? n + " · \(count) stamped" : n
        }
    }
    private(set) var rows: [Row] = []
    @ObservationIgnored private var builtFor: ObjectIdentifier?
    /// what a picked row does (the flight, 6.4)
    @ObservationIgnored var onPick: ((Row) -> Void)?

    /// every place the borders view draws that has a bundled first level, by name
    func build(map: MapController) {
        guard let w = map.world, builtFor != ObjectIdentifier(w) else { return }
        builtFor = ObjectIdentifier(w)
        let cat = RegionCatalog.shared
        var out: [Row] = []
        for (i, p) in w.places.enumerated() where !p.junk {
            let id = p.id.lowercased()
            guard let f = cat.first(id), f.level.n > 0 else { continue }
            out.append(Row(id: p.id, place: i, name: p.n, flag: id, row: f.row, total: f.level.n,
                           one: Self.word(f.level.one), many: Self.word(f.level.many), count: 0))
        }
        rows = out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        Flags.prewarm(rows.map(\.flag))
    }
    /// small letters as an English word is ("34 wilayas"), but a country's own word keeps its own ("9 Bundesländer")
    static func word(_ w: String) -> String { w.unicodeScalars.allSatisfy(\.isASCII) ? w.lowercased() : w }

    /// your number per country at its first level: the region stamps (`r:` keys) counted against each country's
    /// bundled units; with no region stamps nothing is read. Each file's region ids are read once, off the main thread,
    /// and only the ids are kept (the shapes are dropped), so a stamp later counts without reading anything again.
    func recount(map: MapController) async {
        build(map: map)
        let stamped = Set(MarkStore.shared.marks.compactMap { k, s in k.kind == .region && s.stamped ? k.id : nil })
        let places = rows.map { ($0.flag, $0.row) }
        let known = idsByPlace
        let counted: (counts: [String: Int], ids: [String: Set<String>]) = stamped.isEmpty ? ([:], [:]) : await Task.detached(priority: .utility) {
            var out: [String: Int] = [:], ids = known
            for (id, row) in places {
                if ids[id] == nil {
                    guard let url = Bundle.main.url(forResource: "\(id)-\(row)", withExtension: "wyar"),
                          let d = try? Data(contentsOf: url), let f = RegionFile(data: d) else { continue }
                    ids[id] = Set(f.ids)
                }
                let n = ids[id]?.intersection(stamped).count ?? 0
                if n > 0 { out[id] = n }
            }
            return (out, ids)
        }.value
        if !counted.ids.isEmpty { idsByPlace = counted.ids }
        var next = rows
        for i in next.indices { next[i].count = counted.counts[next[i].flag] ?? 0 }
        if next != rows { rows = next }
    }
    /// each country's first-level region ids, once read
    @ObservationIgnored private var idsByPlace: [String: Set<String>] = [:]

    /// the search key over the menu: the first country the list still shows (a typo: the nearest one in the menu)
    func pickFirst(query: String, map: MapController) {
        let q = query.trimmingCharacters(in: .whitespaces)
        let byPlace = Dictionary(rows.map { ($0.place, $0) }, uniquingKeysWith: { a, _ in a })
        let near = SearchResults.nearest(map: map, query: q)
        guard let r = SearchResults.matches(map: map, query: q).lazy.compactMap({ byPlace[$0] }).first
                ?? near.flatMap({ byPlace[$0] }) else {
            Feel.refuse(); return
        }
        Feel.tap()
        load(r.flag)
        onPick?(r)
    }

    /// a country's region file read in the background (touch-down or tap), so the flight never waits on it
    func load(_ id: String) {
        guard let row = RegionCatalog.shared.first(id)?.row else { return }
        Task.detached(priority: .userInitiated) { _ = RegionCatalog.shared.file(id, row: row) }
    }
}


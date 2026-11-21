import SwiftUI

struct MapSettingsSheet: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    @State private var nav = SettingsNav.shared

    var body: some View {
        let L = water.layout
        let top = max(form.top + 16, L.headBottom + 8)
        let bottom = L.capsule.minY - 24
        let width = L.W - 2 * L.sheetInset
        NavigationStack(path: $nav.path) {
            SettingsList(map: map, width: width)
                .navigationDestination(for: String.self) { page in
                    SettingsPage(page: page, map: map, width: width) { if !nav.path.isEmpty { nav.path.removeLast() } }
                }
        }
        // closed: the next opening starts at the list's top
        .onDisappear { nav.path = []; nav.open = nil; nav.openDispute = nil; nav.show = nil }
        .frame(width: width, height: max(48, bottom - top))
        .position(x: L.W / 2, y: top + max(48, bottom - top) / 2)
        .environment(\.settingsWordsOn, water.settingsWords)
        // below full a drag on the rows is the water's (it rises to full, or comes down), as in Apple's sheets and
        // the Places shelf; at full they scroll
        .scrollDisabled(water.stop != .full)
    }
}

extension EnvironmentValues {
    /// the rows' words are in (after the water's old content has gone; out first on close, before the Cosmos returns)
    @Entry var settingsWordsOn: Bool = true
}

/// a line's placeholder for the text roll (en spaces), as the caption does it
private func blank(_ s: String) -> String { String(repeating: "\u{2002}", count: max(1, s.count)) }

private struct RowWords: View {
    let name: String
    let value: String
    var chevron = false
    var band = false
    var dim = false
    var height: CGFloat = 48
    /// a place's square flag before its name (the Borders page's countries), 28 pt, never rounded, never in a box
    var flag: String? = nil
    @State private var inList = false
    @Environment(\.settingsWordsOn) private var wordsOn

    var body: some View {
        let shown = inList && wordsOn
        let ink = band ? Color.white : Palette.ink
        HStack(spacing: 8) {
            if let flag, let img = Flags.row(flag) {
                // shown with the row's words (in one frame: a flag is not a word to roll)
                img.resizable().frame(width: 28, height: 21).frame(width: 28, height: 28).opacity(shown ? 1 : 0)
                    .transaction { $0.disablesAnimations = true; $0.animation = nil }
                    .padding(.trailing, 4)
            }
            Text(shown ? name : blank(name))
                .foregroundStyle(dim ? Palette.ink.opacity(0.5) : ink)
                .lineLimit(1)
            Spacer(minLength: 12)
            if !value.isEmpty {
                Text(shown ? value : blank(value))
                    .foregroundStyle(band ? Color.white : Palette.ink.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if chevron {
                Icon5(key: "forward", ink: Palette.ink, size: 15).opacity(shown ? 1 : 0)
                    .transaction { $0.disablesAnimations = true; $0.animation = nil }
            }
        }
        .font(.body)
        .contentTransition(.numericText(value: shown ? 1 : 0))
        .padding(.horizontal, 16)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // the current choice: the black band, the water's width; it just appears
        .background { (band && shown ? Palette.ink : Color.clear).transaction { $0.disablesAnimations = true; $0.animation = nil } }
        .contentShape(Rectangle())
        // words only while the whole row is inside the list: they roll out before an edge could cut them
        .onScrollVisibilityChange(threshold: 0.99) { v in
            withAnimation(v ? Motion.quick : .smooth(duration: 0.15)) { inList = v }
        }
    }
}

/// THE MAIN LIST: Part 5.5's four groups, 24 pt between them, no names
private struct SettingsList: View {
    let map: MapController
    let width: CGFloat
    @State private var nav = SettingsNav.shared
    @State private var settings = MapSettingsStore.shared
    private var open: String? {
        get { nav.open }
        nonmutating set { nav.open = newValue }
    }

    var body: some View {
        if map.pinsMode { pinsRows(settings.value) } else { mainList }
    }

    /// SETTINGS IN PINS: Pins is Apple's map, so its settings are Apple's look only (our map's rows did nothing
    /// there): Map, Standard, Satellite or Hybrid
    @ViewBuilder private func pinsRows(_ s: MapSettings) -> some View {
        let looks: [(String, String)] = [("apple-standard", "Standard"), ("apple-satellite", "Satellite"), ("apple-hybrid", "Hybrid")]
        let now = looks.first { $0.0 == s.pinsMap }?.1 ?? "Standard"
        // (in a scroll view as the main list: a row's words show once it is wholly in the list) its one setting's
        // three choices are out at once, the current one on the black band as every choice
        ScrollView(.vertical) {
        VStack(spacing: 0) {
            RowWords(name: "Map", value: "")
            ForEach(looks, id: \.0) { l in
                ChoiceRow(name: l.1, picked: now == l.1, delay: 0) {
                    guard now != l.1 else { return }
                    Feel.tap()
                    MapSettingsStore.shared.change { $0.pinsMap = l.0 }
                }
                .transition(.identity)
            }
        }
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .containerBackground(.clear, for: .navigation)
    }

    private var mainList: some View {
        let s = settings.value
        let rows = MapSettingsRows.all.filter { $0.shows(s) }
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0, rows[i - 1].group != row.group { Color.clear.frame(height: 24) }
                        rowView(row, s).id(row.id)
                    }
                    // RESET TO DEFAULT, last (Apple's way: a tap asks once, in its own menu, with the red word);
                    // in its not-yet look while nothing differs from the defaults
                    Color.clear.frame(height: 24)
                    let plain = MapSettingsRows.isDefault(s)
                    Menu {
                        Button("Reset map settings", role: .destructive) {
                            Feel.tap()
                            Task { await MapSettingsRows.resetAll(map: map) }
                        }
                    } label: {
                        RowWords(name: "Reset to default", value: "", dim: plain)
                    }
                    .buttonStyle(.plain)
                    .disabled(plain)
                    .id("reset")
                }
                // (a pull down from the list's top at full brings the water down, Water/WaterHandoff)
                .background(WaterHandoff())
                .scrollTargetLayout()
            }
            .scrollBlur()
            // a search result: the row brought into view (its choices already open)
            .onChange(of: nav.show, initial: true) { _, id in
                guard let id, rows.contains(where: { $0.id == id }) else { return }
                withAnimation(Motion.chrome) { proxy.scrollTo(id, anchor: .top) }
                nav.show = nil
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .containerBackground(.clear, for: .navigation)
    }

    @ViewBuilder private func rowView(_ row: SettingRow, _ s: MapSettings) -> some View {
        let choices = MapSettingsRows.choices(row, s)
        VStack(spacing: 0) {
            if let page = row.page {
                if page == "all" {
                    // the app's Settings comes with its own book: until then the row keeps its place in its look and
                    // refuses (A.1.5: never a pressable-looking control that silently does nothing)
                    RowWords(name: row.name, value: "", dim: true)
                        .onTapGesture { Feel.refuse() }
                } else {
                    NavigationLink(value: page) {
                        RowWords(name: row.name, value: pageValue(row, s), chevron: true)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { Feel.tap() })
                    // A PAGE ROW'S HOLD MENU (11.5, as a value row's): Reset to default. Borders back to de facto;
                    // Disputes every piece given back to the borders view. Unavailable when nothing is changed.
                    .contextMenu {
                        if page == "borders" {
                            Button("Reset to default") {
                                Feel.tap()
                                Task { await MapSettingsRows.set("borders", "deFacto", map: map) }
                            }
                            .disabled(row.get(s) == "deFacto")
                        } else if page == "disputes" {
                            Button("Reset to default") {
                                Feel.tap()
                                Task { for k in s.disputes.keys { await MapSettingsRows.pick(k, nil, map: map) } }
                            }
                            .disabled(s.disputes.isEmpty)
                        }
                    }
                }
            } else if MapSettingsRows.notYet.contains(row.id) {
                EmptyView()
            } else {
                RowWords(name: row.name, value: row.valueName(s))
                    .onTapGesture { tap(row, choices, s) }
                    // THE ROW'S HOLD MENU (5.3, Part 11): Reset to default, unavailable when it is already the default
                    .contextMenu {
                        if let d = row.defaultValue {
                            Button("Reset to default") {
                                Feel.tap()
                                Task { await MapSettingsRows.set(row.id, d, map: map) }
                            }
                            .disabled(row.get(s) == d)
                        }
                    }
                if open == row.id {
                    ForEach(Array(choices.enumerated()), id: \.element.id) { j, c in
                        ChoiceRow(name: c.name, picked: row.get(s) == c.id, delay: Double(j) * 0.05) {
                            pick(row, c.id)
                        }
                        .transition(.identity)
                    }
                }
            }
        }
    }

    private func pageValue(_ row: SettingRow, _ s: MapSettings) -> String {
        switch row.page {
        case "borders":
            switch s.borders {
            case nil, "deFacto": return "De facto"
            case "un": return "United Nations"
            case let k?: return BordersNames.name(k, map)
            }
        case "aiNotes": let n = AINotes.all.count; return n == 0 ? "" : "\(n)"
        default: return ""
        }
    }

    private func tap(_ row: SettingRow, _ choices: [SettingRow.Choice], _ s: MapSettings) {
        // (a two-choice row opened by a settings search shows its choices: a tap on the row closes them, as any row's)
        if choices.count == 2, open != row.id {
            // two choices: one tap switches; the value rolls; the map changes behind (notch + click: a two-state switch)
            let next = choices.first { $0.id != row.get(s) }?.id ?? choices[0].id
            // haptics only: no sound is added anywhere unless he asks
            Feel.notch()
            Task { await MapSettingsRows.set(row.id, next, map: map) }
        } else {
            Feel.tap()
            withAnimation(Motion.chrome) { open = open == row.id ? nil : row.id }
        }
    }

    private func pick(_ row: SettingRow, _ id: String) {
        Feel.tap()
        Task { await MapSettingsRows.set(row.id, id, map: map) }
        // the choices close 0.15 s after the pick, so the black is seen on the new choice first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(Motion.chrome) { if open == row.id { open = nil } } }
    }
}

/// ONE CHOICE under its row (A5.4): 44 pt; its words roll in in their own place once the rows below have moved out of
/// the way (top first), so nothing passes over anything; the picked one is the black band
private struct ChoiceRow: View {
    let name: String
    let picked: Bool
    let delay: Double
    let action: () -> Void
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                RowWords(name: name, value: "", band: picked, height: 44)
            } else {
                Color.clear.frame(height: 44)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .task {
            try? await Task.sleep(for: .milliseconds(Int((0.12 + delay) * 1000)))
            ready = true
        }
    }
}

/// a country's name from a borders key ("KOkr" in the map's data)
@MainActor
enum BordersNames {
    static func placeId(_ key: String) -> String { key == "KO" ? "kr" : key.lowercased() }
    static func name(_ key: String, _ map: MapController) -> String {
        guard let w = map.world, let i = w.placeIndex[placeId(key)] else { return key }
        return w.places[i].n
    }
}

private struct SettingsPage: View {
    let page: String
    let map: MapController
    let width: CGFloat
    let back: () -> Void
    @State private var settings = MapSettingsStore.shared
    @State private var open: String?
    @State private var nav = SettingsNav.shared

    var body: some View {
        let s = settings.value
        ScrollViewReader { proxy in
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                HStack {
                    Button { Feel.tap(); back() } label: {
                        Icon5(key: "back", ink: Palette.ink, size: 22).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.leading, 8)
                .frame(height: 48)
                switch page {
                case "borders": borders(s)
                case "disputes": disputes(s)
                case "aiNotes": AINotesPage()
                case "sources": SourcesPage()
                default: advanced(s)
                }
            }
            // (a pull down from the list's top at full brings the water down, Water/WaterHandoff)
            .background(WaterHandoff())
            .scrollTargetLayout()
        }
        .scrollBlur()
        // a search result: its row brought into view (a dispute's sides open)
        .onChange(of: nav.show, initial: true) { _, id in
            guard let id, id.hasPrefix("view:") || id.hasPrefix("dispute:") else { return }
            if let d = nav.openDispute, page == "disputes" { open = d; nav.openDispute = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(Motion.chrome) { proxy.scrollTo(id, anchor: .top) }
                nav.show = nil
            }
        }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .containerBackground(.clear, for: .navigation)
    }

    // 5.6: United Nations, De facto, then every country A to Z; tap picks, the page stays open
    @ViewBuilder private func borders(_ s: MapSettings) -> some View {
        let current = s.borders ?? "deFacto"
        viewRow("United Nations", "un", current)
        viewRow("De facto", "deFacto", current)
        Color.clear.frame(height: 24)
        ForEach(countries, id: \.key) { c in viewRow(c.name, c.key, current, flag: BordersNames.placeId(c.key)).id("view:" + c.key) }
    }
    private var countries: [(key: String, name: String)] {
        (Bundle.main.url(forResource: "disputes", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(DisputeFile.self, from: $0) }?.views ?? [])
            .map { ($0, BordersNames.name($0, map)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func viewRow(_ name: String, _ key: String, _ current: String, flag: String? = nil) -> some View {
        RowWords(name: name, value: "", band: key == current, flag: flag)
            .onTapGesture {
                Feel.tap()
                Task { await MapSettingsRows.set("borders", key, map: map) }
            }
    }

    // 5.7: one row per disputed piece by its name; its side now as the value; tap opens its sides
    @ViewBuilder private func disputes(_ s: MapSettings) -> some View {
        let list = map.world?.positions?.disputes ?? []
        ForEach(list.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }, id: \.id) { d in
            let side = map.world?.positions?.assign(d) ?? d.default
            VStack(spacing: 0) {
                RowWords(name: d.name ?? d.id, value: sideName(side))
                    .id("dispute:" + d.id)
                    .onTapGesture {
                        Feel.tap()
                        withAnimation(Motion.chrome) { open = open == d.id ? nil : d.id }
                    }
                if open == d.id {
                    let options = d.options.filter { $0 != "none" } + (d.options.contains("none") ? ["none"] : [])
                    ForEach(Array(options.enumerated()), id: \.element) { j, o in
                        ChoiceRow(name: sideName(o), picked: o == side, delay: Double(j) * 0.05) {
                            Feel.tap()
                            Task { await MapSettingsRows.pick(d.id, o, map: map) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(Motion.chrome) { if open == d.id { open = nil } }
                            }
                        }
                        .transition(.identity)
                    }
                }
            }
        }
    }
    private func sideName(_ id: String) -> String {
        if id == "none" { return "Nobody" }
        guard let w = map.world, let i = w.placeIndex[id] else { return id }
        return w.places[i].n
    }

    // 5.8: Places map, Pins map, Afghanistan's flag
    @ViewBuilder private func advanced(_ s: MapSettings) -> some View {
        // (Pins is Apple's map: our map's looks did nothing there. Places can have ours or any of Apple's.
        // Afghanistan's flag is saved but not followed yet, so it is in its look and refuses, as All settings)
        let maps: [(String, String)] = [("same", "Same as Map"), ("apple-standard", "Apple, Standard"),
                                        ("apple-satellite", "Apple, Satellite"), ("apple-hybrid", "Apple, Hybrid")]
        advancedRow("placesMap", "Places map", [maps[0], ("native", "Native")] + maps.dropFirst(), s.placesMap) { v in
            MapSettingsStore.shared.change { $0.placesMap = v }
        }
        advancedRow("pinsMap", "Pins map", maps, s.pinsMap) { v in MapSettingsStore.shared.change { $0.pinsMap = v } }
        RowWords(name: "Afghanistan's flag", value: "", dim: true).onTapGesture { Feel.refuse() }
    }
    @ViewBuilder private func advancedRow(_ id: String, _ name: String, _ choices: [(String, String)], _ current: String,
                                          _ set: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            RowWords(name: name, value: choices.first { $0.0 == current }?.1 ?? current)
                .onTapGesture {
                    Feel.tap()
                    withAnimation(Motion.chrome) { open = open == id ? nil : id }
                }
            if open == id {
                ForEach(Array(choices.enumerated()), id: \.element.0) { j, c in
                    ChoiceRow(name: c.1, picked: c.0 == current, delay: Double(j) * 0.05) {
                        Feel.tap()
                        set(c.0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(Motion.chrome) { if open == id { open = nil } } }
                    }
                    .transition(.identity)
                }
            }
        }
    }
}


/// SOURCES: what the app is made from, who made it and under what licence, as their licences ask; a tap opens the
/// source. A page's own photos and words are credited on that page (its Sources).
struct SourcesPage: View {
    struct Source: Hashable { let name: String; let what: String; let licence: String; let url: String }
    static let all: [Source] = [
        .init(name: "Natural Earth", what: "Countries' outlines", licence: "Public domain", url: "https://www.naturalearthdata.com"),
        .init(name: "OpenStreetMap contributors", what: "Coasts and borders up close, time zones", licence: "ODbL",
              url: "https://www.openstreetmap.org/copyright"),
        .init(name: "NOAA ETOPO", what: "The land's height and the sea's depth", licence: "Public domain",
              url: "https://www.ncei.noaa.gov/products/etopo-global-relief-model"),
        .init(name: "geoBoundaries", what: "Regions", licence: "CC BY 4.0", url: "https://www.geoboundaries.org"),
        .init(name: "GeoNames", what: "Towns and their names", licence: "CC BY 4.0", url: "https://www.geonames.org"),
        .init(name: "Wikidata", what: "Facts, places and World Heritage sites", licence: "CC0", url: "https://www.wikidata.org"),
        .init(name: "Wikivoyage", what: "Guides and things to do", licence: "CC BY-SA 4.0", url: "https://www.wikivoyage.org"),
        .init(name: "Wikimedia Commons", what: "Photos, flags and passport covers, each credited where it shows",
              licence: "Each picture's own", url: "https://commons.wikimedia.org"),
        .init(name: "World Bank", what: "Country figures", licence: "CC BY 4.0", url: "https://data.worldbank.org"),
        .init(name: "CHELSA (Karger et al. 2017)", what: "Climate", licence: "CC BY 4.0", url: "https://chelsa-climate.org"),
        .init(name: "NASA POWER", what: "Rain days", licence: "Public domain", url: "https://power.larc.nasa.gov"),
        .init(name: "Nager.Date", what: "Public holidays", licence: "MIT", url: "https://date.nager.at"),
        .init(name: "Governments of Canada, the US and the UK", what: "Travel advice",
              licence: "OGL-Canada, public domain, OGL v3", url: "https://travel.gc.ca"),
        .init(name: "OpenFlights", what: "Flight routes", licence: "ODbL", url: "https://openflights.org"),
        .init(name: "UN M49, via lukes/ISO-3166", what: "Which region each country is in", licence: "CC BY-SA 4.0",
              url: "https://github.com/lukes/ISO-3166-Countries-with-Regional-Codes"),
        .init(name: "IANA tz database", what: "Each country's clocks", licence: "Public domain", url: "https://www.iana.org/time-zones"),
        .init(name: "Solar System Scope", what: "The planets' surfaces, from NASA's data, resized", licence: "CC BY 4.0",
              url: "https://www.solarsystemscope.com/textures/"),
        .init(name: "Squiresy92, on Wikimedia Commons", what: "Norfolk Island's arms, on its stamp", licence: "CC BY-SA 4.0",
              url: "https://commons.wikimedia.org/wiki/File:Coat_of_arms_of_Norfolk_Island.svg"),
        .init(name: "I.fekry, on Freesound", what: "The stamp's sound", licence: "CC0", url: "https://freesound.org/s/470710/"),
        .init(name: "SpaceJoe, on Freesound", what: "The page's sound", licence: "CC0", url: "https://freesound.org/s/484968/"),
        .init(name: "qubodup, on Freesound", what: "The passport closing", licence: "CC0", url: "https://freesound.org/s/862315/"),
    ]
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.all, id: \.self) { s in
                Button {
                    Feel.tap()
                    if let u = URL(string: s.url) { openURL(u) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.body).foregroundStyle(Palette.ink)
                        Text("\(s.what) · \(s.licence)").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens \(s.name)")
            }
        }
    }
}

/// WHAT THE AI KNOWS ABOUT YOU (AINotes): the notes you told it to remember, in your words; held, Forget; typed at the
/// foot, a new one. Besides these it knows only your map, lists and plans, and says so.
private struct AINotesPage: View {
    @State private var notes = AINotes.all
    @State private var adding = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Besides your map, lists and plans, the AI keeps these in mind. Hold one to forget it.")
                .font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.bottom, 12)
            ForEach(notes, id: \.self) { n in
                // (a note may be a sentence: it wraps, where a setting's row is one line)
                Text(n).font(.body).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Forget", role: .destructive) {
                            Feel.lift()
                            AINotes.forget(n)
                            withAnimation(Motion.quick) { notes = AINotes.all }
                        }
                    }
            }
            TextField("", text: $adding, prompt: Text("Add").foregroundStyle(Palette.ink.opacity(0.5)))
                .font(.body).foregroundStyle(Palette.ink)
                .submitLabel(.done)
                .onSubmit {
                    let t = adding.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    Feel.tap()
                    AINotes.add(t)
                    adding = ""
                    withAnimation(Motion.quick) { notes = AINotes.all }
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
        }
    }
}

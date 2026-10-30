import SwiftUI

/// MAP SETTINGS IN THE WATER (Part 5.3, 5.4): the rows of MapSettingsRows in the water while the gear is out, with no
/// title, no grabber and no words under any row; Borders, Disputes and Advanced pushed Apple's way with his back arrow.
///
/// As built: black and white only; the current choice is a black band the water's width with white
/// words, and it just appears (no front, no circle); values change by Apple's text roll; a row's words are there only
/// while the whole row is inside the list, so the list's edges never cut a word (they roll out before it).
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
    }
}

extension EnvironmentValues {
    /// the rows' words are in (after the water's old content has gone; out first on close, before the Cosmos returns)
    @Entry var settingsWordsOn: Bool = true
}

/// a line's placeholder for the text roll (en spaces), as the caption does it
private func blank(_ s: String) -> String { String(repeating: "\u{2002}", count: max(1, s.count)) }

/// ONE ROW: its name on the left, its value on the right (50% black), his chevron after a page's value
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
            if let flag, let img = Flags.square(flag) {
                // shown with the row's words (in one frame: a flag is not a word to roll)
                img.resizable().frame(width: 28, height: 28).opacity(shown ? 1 : 0).padding(.trailing, 4)
            }
            Text(shown ? name : blank(name))
                .foregroundStyle(dim ? Palette.ink.opacity(0.5) : ink)
            Spacer(minLength: 12)
            if !value.isEmpty {
                Text(shown ? value : blank(value))
                    .foregroundStyle(band ? Color.white : Palette.ink.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if chevron { Icon5(key: "forward", ink: Palette.ink, size: 15).opacity(shown ? 1 : 0) }
        }
        .font(.body)
        .contentTransition(.numericText())
        .padding(.horizontal, 16)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        // the current choice: the black band, the water's width; it just appears
        .background(band && shown ? Palette.ink : .clear)
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
        let s = settings.value
        let rows = MapSettingsRows.all.filter { $0.shows(s) }
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0, rows[i - 1].group != row.group { Color.clear.frame(height: 24) }
                        rowView(row, s).id(row.id)
                    }
                }
                .scrollTargetLayout()
            }
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
                    // the app's Settings comes with its own book: until then the row keeps its place in its "not yet"
                    // look and refuses (A.1.5: never a pressable-looking control that silently does nothing)
                    RowWords(name: row.name, value: "", dim: true)
                        .onTapGesture { Feel.refuse() }
                } else {
                    NavigationLink(value: page) {
                        RowWords(name: row.name, value: pageValue(row, s), chevron: true)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { Feel.tap() })
                }
            } else {
                RowWords(name: row.name, value: row.valueName(s))
                    .onTapGesture { tap(row, choices, s) }
                if open == row.id {
                    ForEach(Array(choices.enumerated()), id: \.element.id) { j, c in
                        ChoiceRow(name: c.name, picked: row.get(s) == c.id, delay: Double(j) * 0.05) {
                            pick(row, c.id)
                        }
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
        default: return ""
        }
    }

    private func tap(_ row: SettingRow, _ choices: [SettingRow.Choice], _ s: MapSettings) {
        if choices.count == 2 {
            // two choices: one tap switches; the value rolls; the map changes behind (notch + click: a two-state switch)
            let next = choices.first { $0.id != row.get(s) }?.id ?? choices[0].id
            // haptics only: no sound is added here
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

/// a country's name from a borders key ("KO" is South Korea, "kr" in the map's data)
@MainActor
enum BordersNames {
    static func placeId(_ key: String) -> String { key == "KO" ? "kr" : key.lowercased() }
    static func name(_ key: String, _ map: MapController) -> String {
        guard let w = map.world, let i = w.placeIndex[placeId(key)] else { return key }
        return w.places[i].n
    }
}

/// A PAGE (Borders, Disputes, Advanced), pushed Apple's way inside the water, his back arrow on its top row
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
                default: advanced(s)
                }
            }
            .scrollTargetLayout()
        }
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
        let maps: [(String, String)] = [("same", "Same as Map"), ("native-detailed", "Native, Detailed"), ("native-simple", "Native, Simple"),
                                        ("apple-standard", "Apple, Standard"), ("apple-satellite", "Apple, Satellite"),
                                        ("apple-hybrid", "Apple, Hybrid")]
        advancedRow("placesMap", "Places map", maps, s.placesMap) { v in MapSettingsStore.shared.change { $0.placesMap = v } }
        advancedRow("pinsMap", "Pins map", maps, s.pinsMap) { v in MapSettingsStore.shared.change { $0.pinsMap = v } }
        advancedRow("afghanistanFlag", "Afghanistan's flag", [("tricolour", "The tricolour"), ("taliban", "The Taliban's")],
                    s.afghanistanFlag) { v in MapSettingsStore.shared.change { $0.afghanistanFlag = v } }
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
                }
            }
        }
    }
}

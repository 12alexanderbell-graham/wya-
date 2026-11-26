import Foundation

/// MAP SETTINGS' ROWS AS ONE DATA LIST (Part 5.11): the sheet, search with settings open (3.4), the hold menu's Reset,
/// VoiceOver, Settings > Map and the AI's actions all read this list, so a row exists once. Part 5.5's order and groups.
@MainActor
struct SettingRow: Identifiable {
    struct Choice: Identifiable, Sendable { let id: String; let name: String }
    let id: String
    let name: String
    /// 0 the map's look, 1 borders, 2 stamping and counting, 3 more
    let group: Int
    /// nil for a row that opens a page
    let choices: [Choice]?
    /// the page it opens (borders, disputes, advanced, all)
    let page: String?
    let defaultValue: String?
    /// shown only while this is true (Projection and Labels leave on Apple's map)
    let shows: (MapSettings) -> Bool
    let get: (MapSettings) -> String
    let set: (inout MapSettings, String) -> Void

    func valueName(_ s: MapSettings) -> String {
        let v = get(s)
        return MapSettingsRows.choices(self, s).first { $0.id == v }?.name ?? v
    }
}

@MainActor
enum MapSettingsRows {
    private static func c(_ pairs: [(String, String)]) -> [SettingRow.Choice] { pairs.map { .init(id: $0.0, name: $0.1) } }
    private static func flag(_ s: Bool) -> String { s ? "on" : "off" }

    static let all: [SettingRow] = [
        // group 1: the map's look
        .init(id: "map", name: "Map", group: 0, choices: c([("native", "Native"), ("apple", "Apple")]), page: nil, defaultValue: "native",
              shows: { _ in true }, get: { $0.map },
              set: { s, v in s.map = v; s.style = v == "apple" ? "standard" : "detailed" }),
        .init(id: "style", name: "Style", group: 0, choices: nil, page: nil, defaultValue: nil,
              shows: { _ in true }, get: { $0.style }, set: { s, v in s.style = v }),
        .init(id: "projection", name: "Projection", group: 0,
              choices: c([("equalearth", "Equal Earth"), ("classic", "Classic"), ("mercator", "Mercator")]), page: nil, defaultValue: "equalearth",
              shows: { $0.map == "native" }, get: { $0.projection }, set: { s, v in s.projection = v }),
        .init(id: "diamonds", name: "Small places", group: 0,
              choices: c([("main", "Main map"), ("everywhere", "All maps"), ("nowhere", "Nowhere")]), page: nil, defaultValue: "main",
              shows: { _ in true }, get: { $0.diamonds }, set: { s, v in s.diamonds = v }),
        .init(id: "townDots", name: "Towns", group: 0, choices: c([("off", "Off"), ("on", "On")]), page: nil, defaultValue: "off",
              shows: { _ in true }, get: { flag($0.townDots) }, set: { s, v in s.townDots = v == "on" }),
        // no Labels row: no names drawn on the map group 2: borders
        .init(id: "borders", name: "Borders", group: 1, choices: nil, page: "borders", defaultValue: nil,
              shows: { _ in true }, get: { $0.borders ?? "deFacto" }, set: { s, v in s.borders = v }),
        .init(id: "disputes", name: "Disputes", group: 1, choices: nil, page: "disputes", defaultValue: nil,
              shows: { _ in true }, get: { "\($0.disputes.count)" }, set: { _, _ in }),
        .init(id: "noPosition", name: "No stated position", group: 1,
              choices: c([("deFacto", "De facto"), ("deJure", "United Nations")]), page: nil, defaultValue: "deFacto",
              shows: { _ in true }, get: { $0.noPosition }, set: { s, v in s.noPosition = v }),
        // group 3: stamping and counting
        .init(id: "quickAlways", name: "Quick stamping", group: 2, choices: c([("off", "Off"), ("on", "Always on")]), page: nil, defaultValue: "off",
              shows: { _ in true }, get: { flag($0.quickAlways) }, set: { s, v in s.quickAlways = v == "on" }),
        .init(id: "territories", name: "Territories", group: 2,
              choices: c([("stampCountry", "Stamp the country too"), ("separate", "Separate")]), page: nil, defaultValue: "stampCountry",
              shows: { _ in true }, get: { $0.territories }, set: { s, v in s.territories = v }),
        .init(id: "count", name: "Count", group: 2, choices: c([("stamps", "Stamps"), ("countries", "Countries")]), page: nil, defaultValue: "stamps",
              shows: { _ in true }, get: { $0.count }, set: { s, v in s.count = v }),
        .init(id: "start", name: "Start", group: 2,
              choices: c([("world", "World"), ("Europe", "Europe"), ("Africa", "Africa"), ("Asia", "Asia"),
                          ("North America", "North America"), ("South America", "South America"), ("Oceania", "Oceania"),
                          ("Antarctica", "Antarctica")]), page: nil, defaultValue: "world",
              shows: { _ in true }, get: { $0.start }, set: { s, v in s.start = v }),
        .init(id: "foundPlaces", name: "Found places", group: 2, choices: c([("wait", "Wait for me"), ("stamp", "Stamp them")]), page: nil, defaultValue: "wait",
              shows: { _ in true }, get: { $0.foundPlaces }, set: { s, v in s.foundPlaces = v }),
        .init(id: "pinMarksPlace", name: "Pin stamping", group: 2, choices: c([("off", "Off"), ("on", "On")]), page: nil, defaultValue: "off",
              shows: { _ in true }, get: { flag($0.pinMarksPlace) }, set: { s, v in s.pinMarksPlace = v == "on" }),
        // TRACKING: Pins' tracking, built (Map/PinTracker.swift)
        .init(id: "tracking", name: "Tracking", group: 2,
              choices: c([("off", "Off"), ("exact", "Exact"), ("city", "City"), ("region", "About 100 km")]), page: nil, defaultValue: "off",
              shows: { _ in true }, get: { $0.pinsTrack }, set: { s, v in s.pinsTrack = v }),
        // THE AI: off, no AI section shows anywhere and Siri's wya questions say it is off
        .init(id: "ai", name: "AI", group: 2, choices: c([("on", "On"), ("off", "Off")]), page: nil, defaultValue: "on",
              shows: { _ in FirstRelease.ai }, get: { $0.ai ? "on" : "off" }, set: { s, v in s.ai = v == "on" }),
        // how long its answers are: the same answer, at the length you like (shown only while the AI is on)
        .init(id: "aiLength", name: "Answers", group: 2,
              choices: c([("0", "Shortest"), ("1", "Short"), ("2", "Normal"), ("3", "Long")]), page: nil, defaultValue: "2",
              shows: { FirstRelease.ai && $0.ai }, get: { String($0.aiLength) }, set: { s, v in s.aiLength = Int(v) ?? 2 }),
        // what it remembers about you (AINotes): its own page, each note taken out by its hold menu, new ones typed
        .init(id: "aiNotes", name: "What it knows", group: 2, choices: nil, page: "aiNotes", defaultValue: nil,
              shows: { FirstRelease.ai && $0.ai }, get: { _ in "" }, set: { _, _ in }),
        // group 4: more where the app's maps, words and pictures come from, each with its licence
        .init(id: "sources", name: "Sources", group: 3, choices: nil, page: "sources", defaultValue: nil,
              shows: { _ in true }, get: { _ in "" }, set: { _, _ in }),
        .init(id: "advanced", name: "Advanced", group: 3, choices: nil, page: "advanced", defaultValue: nil,
              shows: { _ in true }, get: { _ in "" }, set: { _, _ in }),
        .init(id: "all", name: "All settings", group: 3, choices: nil, page: "all", defaultValue: nil,
              shows: { _ in true }, get: { _ in "" }, set: { _, _ in }),
    ]

    /// ROWS THE APP DOES NOT FOLLOW YET: not shown (a greyed row that refuses a tap is a dead control). A row leaves
    /// this list when its part is built.
    static let notYet: Set<String> = ["projection"]

    /// Style's choices follow the Map row (Apple's looks only once the Map row is followed)
    static func choices(_ row: SettingRow, _ s: MapSettings) -> [SettingRow.Choice] {
        if row.id == "style" {
            return s.map == "apple" && !notYet.contains("map") ? c([("standard", "Standard"), ("satellite", "Satellite"), ("hybrid", "Hybrid")])
                                    : c([("detailed", "Detailed"), ("simple", "Simple")])
        }
        return row.choices ?? []
    }

    /// SET A ROW (the sheet, search, Reset, VoiceOver and the AI all come here): saved at once; the map follows
    @discardableResult
    static func set(_ id: String, _ value: String, map: MapController) async -> Bool {
        guard let row = all.first(where: { $0.id == id }), !notYet.contains(id) else { return false }
        let store = MapSettingsStore.shared
        let before = store.value
        let ok = row.page == "borders" || choices(row, before).contains { $0.id == value }
        guard ok else { return false }
        store.change { row.set(&$0, value) }
        await follow(before, store.value, map: map)
        return true
    }

    /// EVERY MAP SETTING BACK TO ITS DEFAULT (the list's last row): each row with a default, the borders to de facto,
    /// every dispute given back to the view, the per-mode maps to the main one; the moon's stop and recent searches
    /// are not settings and stay
    static func defaults(from s: MapSettings) -> MapSettings {
        var t = s
        let d = MapSettings()
        // (Tracking and the AI are not looks of the map: Reset leaves them as they are)
        for row in all where !notYet.contains(row.id) && row.id != "tracking" && row.id != "ai" && row.id != "aiLength" { if let v = row.defaultValue { row.set(&t, v) } }
        t.style = d.style; t.borders = s.borders == nil ? nil : "deFacto"; t.disputes = [:]; t.placesMap = d.placesMap; t.pinsMap = d.pinsMap
        return t
    }
    static func isDefault(_ s: MapSettings) -> Bool { defaults(from: s) == s }
    static func resetAll(map: MapController) async {
        let store = MapSettingsStore.shared
        let before = store.value
        let after = defaults(from: before)
        guard after != before else { return }
        store.change { $0 = after }
        await follow(before, after, map: map)
    }

    /// one dispute given to a side by hand ("none" for nobody; nil gives it back to the view)
    static func pick(_ piece: String, _ owner: String?, map: MapController) async {
        let store = MapSettingsStore.shared
        let before = store.value
        store.change { $0.disputes[piece] = owner }
        await follow(before, store.value, map: map)
    }

    /// what changes behind, as far as the built map can follow today (the others are kept and read by their parts)
    private static func follow(_ a: MapSettings, _ b: MapSettings, map: MapController) async {
        if a.borders != b.borders || a.disputes != b.disputes || a.noPosition != b.noPosition {
            await map.setBorders(b.bordersView, picks: b.disputes, fallback: b.fallbackView)
        } else if a.count != b.count {
            map.recount()
        }
        map.diamondsOff = b.diamonds == "nowhere"
        map.diamondsEverywhere = b.diamonds == "everywhere"
        map.simple = (b.map == "native" || notYet.contains("map")) && b.style == "simple"
        if a.pinsTrack != b.pinsTrack { PinTracker.shared.follow(b.pinsTrack) }
    }

    /// every row as an action the AI, Siri and links can call ( with)
    static func registerActions(map: MapController) {
        for row in all where row.page == nil || row.page == "borders" {
            Actions.shared.register(.init(id: "setting.\(row.id)", name: row.name, role: .normal, available: { true }) { arg, _ in
                guard let arg else { return false }
                return await set(row.id, arg, map: map)
            })
        }
        Actions.shared.register(.init(id: "setting.dispute", name: "Disputes", role: .normal, available: { true }) { arg, _ in
            // , or to give it back to the view
            guard let parts = arg?.split(separator: "=", omittingEmptySubsequences: false), parts.count == 2 else { return false }
            await pick(String(parts[0]), parts[1].isEmpty ? nil : String(parts[1]), map: map)
            return true
        })
    }
}

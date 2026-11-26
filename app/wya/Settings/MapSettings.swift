import Foundation

/// MAP SETTINGS (Part 5.11): the old app's MapSettings plus the rows Part 5.5 adds. Saved to map-settings.json in the
/// App Group at every change (no Save button: a change is kept the moment it is made); a file from an older build reads
/// with the defaults for what it lacks. Raw strings, so a value the app no longer knows falls back to its default.
nonisolated struct MapSettings: Codable, Equatable, Sendable {
    // group 1: the map's look
    var map = "native"              // native | apple
    var style = "detailed"          // native: detailed | simple; apple: standard | satellite | hybrid
    var projection = "equalearth"   // equalearth | classic | mercator
    var diamonds = "main"           // main | everywhere | nowhere
    var townDots = false
    var labels = false
    // group 2: borders
    /// nil until picked (the intro asks; there is no wya?! default); the map draws De facto until then., "unUS",
    /// "KO")
    var borders: String?
    /// your own side for single disputes: piece id -> place id or "none"
    var disputes: [String: String] = [:]
    var noPosition = "deFacto"      // deFacto | deJure (the UN's)
    // group 3: stamping and counting
    var quickAlways = false
    var territories = "stampCountry" // stampCountry | separate
    var count = "stamps"            // stamps | countries
    var start = "world"             // world or a continent's name
    var foundPlaces = "wait"        // wait | stamp
    var pinMarksPlace = false
    var tracking = false
    // advanced
    var placesMap = "same"          // same | native | apple-standard | apple-satellite | apple-hybrid
    var pinsMap = "same"
    /// Pins' tracking: off | exact | city | region (about 100 km); where you go drawn as pins
    var pinsTrack = "off"
    var afghanistanFlag = "tricolour" // tricolour | taliban
    /// THE AI: on unless you turn it off; always off while the app ships with no AI (FirstRelease.ai)
    var ai = true
    /// how long the AI's answers are: 0 the heart of it, 1 a sentence, 2 its normal answer, 3 the fuller one.
    /// Directness is never a setting (audit D366, D491)
    var aiLength = 2
    /// the moon's stop, set only by the moon (0 Both ... 4 Wishlist)
    var filter = 0
    /// the last 12 places opened from search, newest first (19.2; the empty field's suggestions show the first five)
    var recent: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MapSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        map = v(.map, d.map); style = v(.style, d.style); projection = v(.projection, d.projection)
        diamonds = v(.diamonds, d.diamonds); townDots = v(.townDots, d.townDots); labels = v(.labels, d.labels)
        borders = (try? c.decodeIfPresent(String.self, forKey: .borders)) ?? nil
        disputes = v(.disputes, d.disputes); noPosition = v(.noPosition, d.noPosition)
        quickAlways = v(.quickAlways, d.quickAlways); territories = v(.territories, d.territories)
        count = v(.count, d.count); start = v(.start, d.start); foundPlaces = v(.foundPlaces, d.foundPlaces)
        pinMarksPlace = v(.pinMarksPlace, d.pinMarksPlace); tracking = v(.tracking, d.tracking)
        placesMap = v(.placesMap, d.placesMap); pinsMap = v(.pinsMap, d.pinsMap); pinsTrack = v(.pinsTrack, d.pinsTrack)
        afghanistanFlag = v(.afghanistanFlag, d.afghanistanFlag); filter = v(.filter, d.filter); ai = v(.ai, d.ai); aiLength = v(.aiLength, d.aiLength)
        recent = v(.recent, d.recent)
    }

    /// the borders view the map draws
    var bordersView: Borders.View {
        switch borders {
        case nil, "deFacto": .deFacto
        case "un": .unitedNations
        case let k?: .country(k)
        }
    }
    var fallbackView: Borders.View { noPosition == "deJure" ? .unitedNations : .deFacto }
}

/// The settings' one owner on the main thread: reads the file once, writes it at every change, and tells the map what
/// changed (the borders view and disputes rebuild the map; the count recounts).
@MainActor
@Observable
final class MapSettingsStore {
    static let shared = MapSettingsStore()
    private(set) var value: MapSettings

    private static var url: URL? {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: MarkStore.group)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir = base?.appendingPathComponent("Library/Application Support", isDirectory: true) else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("map-settings.json")
    }

    /// the AI's own choice as saved (kept as it was while the first release holds the AI off, so the update that
    /// brings it finds what you had)
    private var savedAI = true
    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(MapSettings.self, from: d) {
            value = s
        } else {
            // (one there that can't be read is moved beside itself, never written over)
            if let u = Self.url, FileManager.default.fileExists(atPath: u.path) { PinRoutes.putAside(u) }
            value = MapSettings()
        }
        savedAI = value.ai
        if !FirstRelease.ai { value.ai = false }
        Self.mirror(value)
        Borders.view = value.bordersView
        Borders.picks = value.disputes
        Borders.fallback = value.fallbackView
    }

    /// change settings; saved at once
    func change(_ f: (inout MapSettings) -> Void) {
        var s = value
        f(&s)
        if !FirstRelease.ai { s.ai = false } else { savedAI = s.ai }
        guard s != value else { return }
        value = s
        Self.mirror(s)
        var kept = s
        kept.ai = savedAI
        if let u = Self.url, let d = try? JSONEncoder().encode(kept) { try? d.write(to: u, options: .atomic) }
    }

    /// what code off the main thread reads (the Count service)
    private static func mirror(_ s: MapSettings) { UserDefaults.standard.set(s.count, forKey: "mapCount") }
}

/// WHAT THE FIRST RELEASE HAS (26 Nov: it ships with no AI at all; the AI comes in an update after launch). Off, no AI
/// shows anywhere: its settings, Suggestions under lists, plans and pages, the AI's Siri questions, its badges and
/// stats. Its code stays, switched off here, for the update that brings it.
nonisolated enum FirstRelease {
    static let ai = false
}

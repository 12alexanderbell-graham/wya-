import Foundation
import CoreGraphics

/// WHO ASKED FOR AN ACTION (Part 20.7.1): it decides the haptic (the AI's actions play sounds but no haptics, since a
/// haptic answers your own touch) and is carried into the store's change (`Who`).
nonisolated enum ActionSource: String, Sendable { case you, ai, siri, link, importer = "import", undo
    var who: Who {
        switch self {
        case .you: .you
        case .ai: .ai
        case .siri: .siri
        case .link: .link
        case .importer: .importer
        case .undo: .undo
        }
    }
}

/// ONE THING THE APP CAN DO, with a stable id (Part 11.2, 20.7.1): the hold menus, the AI's tools, Siri and App
/// Intents and deep links all call the same action, so each plays exactly as if you had done it. A write is one store
/// step, so one undo takes it back.
@MainActor
struct AppAction {
    enum Role: Sendable { case normal, destructive }
    let id: String
    let name: String
    let role: Role
    /// whether it can happen now (an unavailable one keeps its place and refuses)
    let available: () -> Bool
    /// `arg`: what it acts on, as text ("fr",, "2"); nil when it needs nothing
    let perform: (_ arg: String?, _ source: ActionSource) async -> Bool
}

/// THE ACTIONS REGISTRY (Part 20.12 item 4): the Map's actions now; each part registers its own as it lands (Step 14).
@MainActor
final class Actions {
    static let shared = Actions()
    private(set) var all: [String: AppAction] = [:]
    func register(_ a: AppAction) { all[a.id] = a }

    /// run one by id; false when it is unknown, unavailable or did nothing
    @discardableResult
    func perform(_ id: String, _ arg: String? = nil, source: ActionSource = .you) async -> Bool {
        guard let a = all[id], a.available() else { return false }
        return await a.perform(arg, source)
    }

    /// THE MAP'S ACTIONS, as the built Map can do them today
    func registerMap(map: MapController, water: Water, head: HeadState) {
        let marks = MarkStore.shared
        #if DEBUG
        // two badges' art drafts over the screen, on and off (the test driver's `action review.badges`)
        register(.init(id: "review.badges", name: "Badge drafts", role: .normal, available: { true }) { _, _ in
            BadgeDraft.shared.on.toggle(); return true
        })
        // Pins' tools and their choices pressed by number (the test driver's `action pins.tool2`, `action pins.opt1`)
        for i in 0 ..< 5 {
            register(.init(id: "pins.tool\(i)", name: "Pins tool \(i)", role: .normal, available: { true }) { _, _ in
                PinsDock.press?(i); return true
            })
            register(.init(id: "pins.opt\(i)", name: "Pins choice \(i)", role: .normal, available: { true }) { _, _ in
                PinsDock.option?(i); return true
            })
        }
        // each search index timed on the queries that held the screen (the test driver's `action bench.search`)
        register(.init(id: "bench.search", name: "Time the searches", role: .normal, available: { true }) { _, _ in
            let qs = ["ny", "uk", "rome", "zz", String(repeating: "a", count: 75), "\u{1F1EB}\u{1F1F7}"]
            @MainActor func ms(_ f: () -> Void) -> Double { let t = Date(); f(); return Date().timeIntervalSince(t) * 1000 }
            // (each index asked something else first and twice over, so its kept answers are not the ones timed)
            @MainActor func evict() { for e in ["#1", "#2"] { _ = TownIndex.shared.hits(e, open: nil); _ = RegionIndex.shared.hits(e); _ = ThingIndex.shared.hits(e, open: nil); _ = CollectionStore.shared.find(e, first: nil) } }
            for q in qs {
                evict()
                let town = ms { _ = TownIndex.shared.hits(q, open: nil, limit: 6) }
                let region = ms { _ = RegionIndex.shared.hits(q) }
                let thing = ms { _ = ThingIndex.shared.hits(q, open: nil) }
                let item = ms { _ = CollectionStore.shared.find(q, first: nil) }
                let guess = ms { _ = TownIndex.shared.guess(q) }
                NSLog("wya bench %@: towns %.0f regions %.0f things %.0f sets %.0f guess %.0f ms", String(q.prefix(12)), town, region, thing, item, guess)
            }
            // (the Countries map's own: the regions, the countries, and 's nearest names)
            RegionIndex.shared.load()
            for q in qs + ["frnace", "germny"] {
                evict()
                let region = ms { _ = RegionIndex.shared.hits(q) }
                let found = ms { _ = SearchResults.matches(map: map, query: q) }
                let near = ms { _ = SearchResults.nearest(map: map, query: q) }
                let close = ms { _ = SearchResults.closest(map: map, query: q, count: 20) }
                NSLog("wya bench countries %@: regions %.0f (ready %d) matches %.0f nearest %.0f closest %.0f ms", String(q.prefix(12)),
                      region, RegionIndex.shared.ready ? 1 : 0, found, near, close)
            }
            for q in ["lucerne", "moskva"] {
                NSLog("wya bench %@ towns: %@", q, TownIndex.shared.hits(q, open: nil).map { $0.name + " " + $0.file }.joined(separator: ", "))
            }
            return true
        })
        // the badges as solids (the test driver's `action review.badges3d`)
        register(.init(id: "review.badges3d", name: "Badges in 3D", role: .normal, available: { true }) { _, _ in
            Badge3D.shared.on.toggle(); return true
        })
        // a badge's moment, with the two highest badges you have (the test driver's `action review.badgemoment`)
        register(.init(id: "review.badgemoment", name: "Badge earned", role: .normal, available: { true }) { _, _ in
            let top = ProfileNumbers.shared.earned.sorted { $0.level > $1.level }
            BadgeMoment.shared.show(BadgeMoment.shared.current == nil ? Array(top.prefix(2)) : [])
            return true
        })
        // the Map setting between ours and Apple's (the test driver's `action review.mapapple`)
        register(.init(id: "review.mapapple", name: "Map: ours or Apple's", role: .normal, available: { true }) { _, _ in
            MapSettingsStore.shared.change { $0.map = $0.map == "apple" ? "native" : "apple" }
            return true
        })
        // every country's activities worked out and written for the data server (the test driver's `action build.activities`)
        register(.init(id: "build.activities", name: "Build activities", role: .normal, available: { true }) { _, _ in
            #if targetEnvironment(simulator)
            Task.detached(priority: .utility) { await PlacePageState.buildActivitiesFiles() }
            #endif
            return true
        })
        // Places' own map, stepped through its five choices (the test driver's `action review.placesmap`)
        register(.init(id: "review.placesmap", name: "Places map", role: .normal, available: { true }) { _, _ in
            let all = ["same", "native", "apple-standard", "apple-satellite", "apple-hybrid"]
            let now = all.firstIndex(of: MapSettingsStore.shared.value.placesMap) ?? 0
            MapSettingsStore.shared.change { $0.placesMap = all[(now + 1) % all.count] }
            return true
        })
        #endif
        func place(_ arg: String?) -> (key: PlaceKey, i: Int, name: String)? {
            guard let id = arg?.lowercased(), let w = map.world, let i = w.placeIndex[id] else { return nil }
            return (.country(id), i, w.places[i].n)
        }
        let canMark = { map.ready && !map.locked }
        register(.init(id: "place.stamp", name: "Stamp", role: .normal, available: canMark) { arg, src in
            guard let p = place(arg), !marks.state(p.key).stamped else { return false }
            await marks.stamp(p.key, name: p.name, source: src == .ai ? .ai : src == .siri ? .siri : .hand, who: src.who)
            return true
        })
        register(.init(id: "place.unstamp", name: "Unstamp", role: .destructive, available: canMark) { arg, src in
            guard let p = place(arg), marks.state(p.key).stamped else { return false }
            await marks.unstamp(p.key, name: p.name, who: src.who)
            return true
        })
        register(.init(id: "place.wish", name: "Wishlist", role: .normal, available: canMark) { arg, src in
            guard let p = place(arg), !marks.state(p.key).stamped, !marks.state(p.key).wished else { return false }
            await marks.wish(p.key, name: p.name, source: src == .ai ? .ai : src == .siri ? .siri : .hand, who: src.who)
            return true
        })
        register(.init(id: "place.unwish", name: "Off the wishlist", role: .destructive, available: canMark) { arg, src in
            guard let p = place(arg), marks.state(p.key).wished else { return false }
            await marks.unwish(p.key, name: p.name, who: src.who)
            return true
        })
        register(.init(id: "map.show", name: "Show", role: .normal, available: { map.ready }) { arg, _ in
            guard let p = place(arg) else { return false }
            map.show(place: p.i, sheetTop: water.layout.top(water.stop))
            return true
        })
        register(.init(id: "map.home", name: "World", role: .normal, available: { map.ready }) { _, _ in
            if map.onApple { map.appleHome() } else { map.goHome() }
            return true
        })
        register(.init(id: "map.filter", name: "Filter", role: .normal, available: { map.ready }) { arg, _ in
            guard let s = arg.flatMap(Int.init), (0 ... 4).contains(s) else { return false }
            map.filter = s; return true
        })
        register(.init(id: "map.lock", name: "Lock", role: .normal, available: { map.ready }) { arg, _ in
            map.locked = arg.map { $0 == "on" } ?? !map.locked; return true
        })
        register(.init(id: "marks.undo", name: "Undo", role: .normal, available: { marks.canUndo }) { _, _ in
            await marks.undo(); return true
        })
    }
}

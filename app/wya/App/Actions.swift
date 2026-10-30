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
    /// `arg`: what it acts on, as text ("fr", "Europe", "2"); nil when it needs nothing
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
            map.goHome(); return true
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

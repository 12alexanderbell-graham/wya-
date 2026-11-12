import Foundation

/// THE BADGES' WORLD AND CATALOG, made once: the pack from the data server (native/badges/badges-1.wybd: each place's
/// facts, each place's towns, the capitals, the tables of time zones, scripts, high points and famous sets), joined
/// with the map's own places and the regions' table. Until the pack has come the app counts its first ninety badges
/// only; when it comes the numbers are counted again.
@MainActor @Observable
final class BadgeStore {
    static let shared = BadgeStore()

    private(set) var ready = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var pack: Pack?
    @ObservationIgnored private var made: (world: BadgeWorld, catalog: [Badge])?

    nonisolated struct Pack: Decodable, Sendable {
        let facts: [String: BadgeFacts]
        let towns: [String: Int]
        let capitals: [String]
        let tables: BadgeTables?
    }

    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .utility) {
            var pack: Pack?
            if case .ok(let d) = await Servers.data.file("native/badges/badges-1.wybd") {
                pack = try? JSONDecoder().decode(Pack.self, from: d)
                // (a kept file that cannot be read goes, so the next ask fetches it again)
                if pack == nil { DevDataClient.forget("native/badges/badges-1.wybd") }
            }
            await MainActor.run { [pack] in
                self.pack = pack
                self.loading = false
                self.ready = pack != nil
            }
        }
    }

    /// the world the badges count against and every badge the app knows, for the map's places (nil before the pack)
    func book(_ w: World) -> (world: BadgeWorld, catalog: [Badge])? {
        if let m = made { return m }
        guard let pack else { return nil }
        // (the map's own places, each with the pack's facts; a place the pack does not know is left out)
        let facts: [(id: String, f: BadgeFacts)] = w.places.filter { !$0.junk }.compactMap { p in pack.facts[p.id].map { (p.id, $0) } }
        let world = BadgeWorld(facts: facts, levels: RegionCatalog.shared.levels, towns: pack.towns, capitals: Set(pack.capitals),
                               tables: pack.tables)
        let m = (world, Badges.catalog(world))
        made = m
        return m
    }
}

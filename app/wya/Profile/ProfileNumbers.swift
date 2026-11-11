import Foundation

/// THE PROFILE'S THREE NUMBERS, counted from your own map: how many stats have something to say about you, your
/// stamps (the map's own count, by the borders and the Count you set), and your badge levels (a diamond counts five).
/// Counted again whenever your marks change; never a sample, and a number is not shown before it has been counted.
@MainActor @Observable
final class ProfileNumbers {
    static let shared = ProfileNumbers()

    private(set) var stats = 0
    private(set) var stamps = 0
    private(set) var badges = 0
    /// counted at least once since the app opened
    private(set) var ready = false
    /// the stats' rows and the badges you have, for their pages
    private(set) var groups: [StatGroup] = []
    private(set) var earned: [Badge] = []

    @ObservationIgnored private var job = 0
    static let continents = ["Europe", "Asia", "Africa", "North America", "South America", "Oceania", "Antarctica"]

    func count(map: MapController) async {
        guard map.ready, MarkStore.shared.loaded, let w = map.world else { return }
        // (the capitals among your towns are counted from the capitals' own list)
        CollectionStore.shared.load()
        job += 1
        let me = job
        let marks = MarkStore.shared.marks
        let info = await MarkStore.shared.listInfo()
        guard me == job else { return }

        var c = Counted()
        c.countries = CountKind.current == .countries
        let sh = map.shares
        c.world = (sh["World"]?.have ?? 0, sh["World"]?.total ?? 0)
        for k in Self.continents { if let s = sh[k] { c.continents[k] = (s.have, s.total) } }
        // (a place drawn as part of another counts as that one, so it is no territory of its own)
        let pos = w.positions
        let mine = Set(map.stamped.map { w.places[$0].id }.map { pos?.countedAs($0) ?? $0 })
        let kind = Dictionary(w.places.map { ($0.id, $0.k) }, uniquingKeysWith: { a, _ in a })
        c.territories = mine.filter { !(pos?.counts($0) ?? (kind[$0] == "country" || kind[$0] == "entity")) }.count
        c.lived = marks.filter { $0.key.kind == .country && $0.value.lived }.count
        c.wish = marks.filter { $0.key.kind == .country && $0.value.wished }.count
        c.streak = map.streakWeeks
        c.verified = info.values.filter(\.verified).count
        c.regions = marks.filter { $0.key.kind == .region && $0.value.stamped }.count
        c.towns = marks.filter { $0.key.kind == .town && $0.value.stamped }.count
        c.capitals = CollectionStore.shared.collection(CollectionStore.capitals)?.items.filter { marks[$0.key]?.stamped ?? false }.count ?? 0
        c.years = Set(info.filter { $0.key.hasPrefix("c:") }.compactMap(\.value.year)).count
        c.months = Badges.monthsInARow(MarkStore.shared.markDates)

        let have = Badges.earned(c)
        let levels = Badges.levels(have)

        // the stats that have something to say (a stat at nought is left out, and a group with none goes)
        func n(_ v: Int) -> String? { v > 0 ? v.formatted() : nil }
        var said: [String: String?] = [:]
        said["Stamps"] = n(c.world.have)
        said["Continents"] = n(c.continents.values.filter { $0.have > 0 }.count)
        said["Countries in Europe"] = n(c.continents["Europe"]?.have ?? 0)
        said["Share of the world"] = c.world.total > 0 && c.world.have > 0 ? "\(c.world.have * 100 / c.world.total)%" : nil
        said["Capitals"] = n(c.capitals)
        said["Cities and towns"] = n(c.towns)
        said["Regions"] = n(c.regions)
        said["Territories"] = n(c.territories)
        said["Lived in"] = n(c.lived)
        said["Wishlist"] = n(c.wish)
        // (the edges by each stamped place's own middle)
        let mids = map.stamped.compactMap { i -> (String, Double)? in
            let p = w.places[i]
            return p.ll.count == 2 ? (p.n, p.ll[1]) : nil
        }
        said["Northernmost"] = mids.max { $0.1 < $1.1 }?.0
        said["Southernmost"] = mids.count > 1 ? mids.min { $0.1 < $1.1 }?.0 : nil
        said["Years travelling"] = n(c.years)
        said["Weeks in a row"] = n(c.streak)
        said["Months in a row"] = n(c.months)
        said["Badge levels"] = n(levels)
        let rows = Stats.mine(counted: said)

        groups = rows
        earned = have
        stats = Stats.count(rows)
        stamps = c.world.have
        badges = levels
        ready = true
    }
}

import Foundation

/// THE PROFILE'S THREE NUMBERS, counted from your own map: how many stats have something to say about you, your
/// stamps (the map's own count, by the borders and the Count you set), and your badge levels (a diamond counts five).
/// Counted again whenever your marks change; never a sample, and a number is not shown before it has been counted.
/// With the badges' pack (BadgeStore) every badge and stat of the catalog is counted; before it has come, the first
/// ninety only.
@MainActor @Observable
final class ProfileNumbers {
    static let shared = ProfileNumbers()

    private(set) var stats = 0
    private(set) var stamps = 0
    private(set) var badges = 0
    /// counted at least once since the app opened
    private(set) var ready = false
    /// the stats' groups, each country's section and the badges you have, for their pages
    private(set) var groups: [StatGroup] = []
    private(set) var sections: [StatsBook.Section] = []
    private(set) var earned: [Badge] = []

    @ObservationIgnored private var job = 0
    @ObservationIgnored private var kept: (input: BadgeInput, tally: (more: [String: Int], fixed: [String: Int], steps: [String: [Int]]))?
    static let continents = ["Europe", "Asia", "Africa", "North America", "South America", "Oceania", "Antarctica"]
    /// what a set's place is, as the badges of the things you marked name it
    static let setKinds: [String: String] = ["world-heritage": "heritage", "parks": "park", "peaks": "peak", "famouslakes": "lake",
                                             "famousislands": "island"]

    /// what makes a count worth doing again: your marks, and the lists it reads having come
    var asks: String {
        "\(MarkStore.shared.changes) \(CollectionStore.shared.ready) \(BadgeStore.shared.ready) \(TownIndex.shared.ready)"
    }

    func count(map: MapController) async {
        guard map.ready, MarkStore.shared.loaded, let w = map.world else { return }
        // (the capitals' own list, the badges' pack and the towns' index: the count is made again as each comes)
        CollectionStore.shared.load()
        BadgeStore.shared.load()
        TownIndex.shared.load()
        job += 1
        let me = job
        let marks = MarkStore.shared.marks
        let rows = await MarkStore.shared.badgeRows()
        guard me == job else { return }

        let pos = w.positions
        let byID = Dictionary(w.places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = map.stamped.map { w.places[$0].id }
        let countryRows = Dictionary(rows.filter { $0.key.hasPrefix("c:") }.map { (String($0.key.dropFirst(2)), $0) }, uniquingKeysWith: { a, _ in a })
        let regionRows = rows.filter { $0.key.hasPrefix("r:") }
        let townRows = rows.filter { $0.key.hasPrefix("t:") }
        let thingRows = rows.filter { $0.key.hasPrefix("m:") }
        let store = CollectionStore.shared
        let capitals = store.collection(CollectionStore.capitals)?.items.filter { marks[$0.key]?.stamped ?? false } ?? []

        // WHAT THE APP COUNTS ITSELF
        var c = Counted()
        c.countries = CountKind.current == .countries
        let sh = map.shares
        c.world = (sh["World"]?.have ?? 0, sh["World"]?.total ?? 0)
        for k in Self.continents { if let s = sh[k] { c.continents[k] = (s.have, s.total) } }
        // (a place drawn as part of another counts as that one, so it is no territory of its own)
        let counted = Set(ids.map { pos?.countedAs($0) ?? $0 })
        c.territories = counted.filter { id in !(pos?.counts(id) ?? (byID[id]?.k == "country" || byID[id]?.k == "entity")) }.count
        c.lived = marks.filter { $0.key.kind == .country && $0.value.lived }.count
        c.wish = marks.filter { $0.key.kind == .country && $0.value.wished }.count
        c.streak = map.streakWeeks
        c.verified = rows.filter(\.verified).count
        c.regions = regionRows.count
        c.towns = townRows.count
        c.capitals = capitals.count
        c.notes = rows.filter(\.noted).count
        c.years = Badges.years(ids.compactMap { countryRows[$0] }.map { ($0.when, $0.at) })
        c.months = Badges.monthsInARow(rows.map(\.at))

        // THE CATALOG'S COUNTS, once the pack has come
        var catalog = Badges.all
        var world: BadgeWorld?
        if let book = BadgeStore.shared.book(w) {
            var y = BadgeInput()
            y.stamped = Set(ids)
            y.counted = counted
            y.regions = regionRows.filter { !$0.cc.isEmpty && $0.level > 0 }.map { (cc: $0.cc, lvl: $0.level) }
            let capitalKeys = Set(capitals.map(\.key.description))
            for t in townRows {
                // (a town's key is its country's file and its GeoNames id, "fr/2988507")
                let id = String(t.key.dropFirst(2))
                let cc = String(id.prefix { $0 != "/" }).lowercased()
                y.towns[cc, default: 0] += 1
                guard let h = TownIndex.shared.hit(id) else { continue }
                y.townFacts.append(.init(cc: cc, kind: capitalKeys.contains(t.key) ? 2 : 0, p: h.people, lat: h.lat, lon: h.lon,
                                         gid: Int(id.drop { $0 != "/" }.dropFirst()) ?? 0))
            }
            y.markIds = Set(thingRows.map { String($0.key.dropFirst(2)) })
            // YOUR HOME: the passport you show (your first nationality), for Neighbours and Farthest from home
            if let n = (UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []).first?.lowercased(),
               let p = book.world.places[n], p.c.count == 2 {
                y.home = .init(cc: n, lat: p.c[1], lon: p.c[0])
            }
            for (set, kind) in Self.setKinds {
                for it in store.collection(set)?.items ?? [] where marks[it.key]?.stamped ?? false { y.marks.append(kind) }
            }
            for it in store.collection("seas")?.items ?? [] where marks[it.key]?.stamped ?? false { y.marks.append(it.type.isEmpty ? "sea" : it.type) }
            let own = OwnPlaces.shared.all, pins = PinStore.shared.pins
            y.points = pins.map { .init(lat: $0.lat, lon: $0.lon) } + own.map { .init(lat: $0.lat, lon: $0.lon) }
            // (the places you gave a month: a stamp's own, else the first day in its details; with the place it is in)
            for r in rows {
                guard let mo = r.when.count >= 7 ? String(r.when.prefix(7)) : r.from.count >= 7 ? String(r.from.prefix(7)) : nil else { continue }
                if r.key.hasPrefix("c:") { if !r.via { y.dated.append(.init(month: mo, cc: String(r.key.dropFirst(2)))) } }
                else if !r.cc.isEmpty { y.dated.append(.init(month: mo, cc: r.cc)) }
            }
            y.dated.sort { $0.month != $1.month ? $0.month < $1.month : $0.cc < $1.cc }
            var n: [String: Int] = [:]
            n["places"] = own.count
            for (k, _) in Badges.placeKinds { n["kind-" + k] = own.filter { $0.kind == k }.count + pins.filter { $0.kind == k }.count }
            n["pins"] = pins.count
            n["rated"] = rows.filter { $0.stars > 0 }.count
            n["been-back"] = marks.filter { $0.value.stamped && $0.value.visits > 1 }.count
            n["wishes"] = rows.filter(\.came).count
            // (only the countries you gave the month you went: a first day's import of thirty past trips is not a year
            // of thirty)
            n["big-year"] = Badges.bigYear(countryRows.values.filter { !$0.via }.compactMap { r in
                r.when.count >= 4 ? Int(r.when.prefix(4)) : r.from.count >= 4 ? Int(r.from.prefix(4)) : nil
            })
            y.numbers = n
            // (the tally is the slow part: the same input is the same tally, and a new one is made off the main thread)
            let t: (more: [String: Int], fixed: [String: Int], steps: [String: [Int]])
            if let k = kept, k.input == y { t = k.tally } else {
                let bw = book.world
                t = await Task.detached(priority: .userInitiated) { Badges.tally(bw, y) }.value
                guard me == job else { return }
                kept = (y, t)
            }
            c.more = t.more; c.fixed = t.fixed; c.steps = t.steps
            catalog = book.catalog
            world = book.world
        }

        let have = Badges.earned(c, catalog: catalog)
        let levels = Badges.levels(have)
        #if DEBUG
        NSLog("wya profile counted: job %d, catalog %d, tally %d numbers (%d above 0), earned %d, levels %d", me, catalog.count, c.more.count,
              c.more.values.filter { $0 > 0 }.count, have.count, levels)
        #endif

        // THE STATS: each badge with a count is a row in its group, the app's own rows at the groups' heads; then a
        // section for every country you have been to
        let fmt = { (n: Int) in n.formatted() }
        let of = { (a: String, b: String) in a + " of " + b }
        let head = Self.head(c, rows: countryRows, ids: ids, byID: byID, regions: regionRows, towns: townRows, marks: marks,
                             earned: have.count, levels: levels)
        let page = StatsBook.page(badges: catalog.map { Badges.now($0, c) }, world: world, head: head, format: fmt, of: of)
        var mine: [String: StatsBook.Mine] = [:]
        for id in ids {
            mine[id, default: .init()].stamped = true
            mine[id]!.visits = marks[.country(id)]?.visits ?? 0
            mine[id]!.lived = marks[.country(id)]?.lived ?? false
        }
        for r in regionRows where !r.cc.isEmpty { mine[r.cc, default: .init()].regions[r.level, default: 0] += 1 }
        for t in townRows { mine[String(t.key.dropFirst(2).prefix { $0 != "/" }).lowercased(), default: .init()].towns += 1 }
        var capital: [String: String] = [:]
        for it in capitals { mine[it.cc, default: .init()].capital = true; capital[it.cc] = it.name }
        for p in OwnPlaces.shared.all where !p.cc.isEmpty { mine[p.cc, default: .init()].places += 1 }
        for r in thingRows where !r.cc.isEmpty { mine[r.cc, default: .init()].things += 1 }
        let levelsTable = RegionCatalog.shared.levels
        let secs: [StatsBook.Section] = mine.compactMap { cc, m in
            guard let p = byID[cc] else { return nil }
            let ls = (levelsTable[cc] ?? []).enumerated().filter { $0.element.n > 0 }
                .map { StatsBook.Level(lvl: $0.offset + 1, word: $0.element.many, n: $0.element.n) }
            return StatsBook.section(cc: cc, name: p.n, levels: ls, towns: world?.towns[cc] ?? 0, capital: capital[cc], mine: m,
                                     format: fmt, of: of)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        groups = page
        sections = secs
        earned = have
        stats = Stats.count(page) + secs.reduce(0) { $0 + $1.rows.count }
        stamps = c.world.have
        badges = levels
        ready = true
    }

    /// THE ROWS THAT ARE NO BADGE'S, at their groups' heads: the first and the latest, where you stamped most and went
    /// back most, the edges by name, your years, the badges themselves. Nothing to say leaves a row out.
    private static func head(_ c: Counted, rows: [String: TravelStore.BadgeRow], ids: [String], byID: [String: World.Place],
                             regions: [TravelStore.BadgeRow], towns: [TravelStore.BadgeRow], marks: [PlaceKey: MarkState],
                             earned: Int, levels: Int) -> [String: [StatRow]] {
        var head: [String: [StatRow]] = [:]
        func add(_ group: String, _ label: String, _ v: String?) {
            guard let v, !v.isEmpty else { return }
            head[group, default: []].append(StatRow(label: label, value: v))
        }
        if earned > 0 { add("Badges", "Badges", earned.formatted()); add("Badges", "Badge levels", levels.formatted()) }
        let ids = ids.filter { rows[$0] != nil }
        func name(_ id: String) -> String { byID[id]?.n ?? id }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        // the first: the month you went, else when it was stamped
        func went(_ id: String) -> String {
            let r = rows[id]!
            return r.when.isEmpty ? day.string(from: r.at) : r.when + "-01"
        }
        let first = ids.min { went($0) != went($1) ? went($0) < went($1) : $0 < $1 }
        add("Places", "First stamp", first.map { "\(name($0)), \(went($0).prefix(4))" })
        // the latest: whatever you stamped last, a country, a region or a town
        var latest: (Date, String)?
        for id in ids { let a = rows[id]!.at; if latest == nil || a > latest!.0 { latest = (a, name(id)) } }
        for r in regions + towns where !r.name.isEmpty && (latest == nil || r.at > latest!.0) { latest = (r.at, r.name) }
        add("Places", "Latest stamp", latest?.1)
        // the country with the most stamps: itself, and its regions and towns
        var most: [String: Int] = [:]
        for id in ids { most[id] = 1 }
        for r in regions where most[r.cc] != nil { most[r.cc, default: 0] += 1 }
        for t in towns {
            let cc = String(t.key.dropFirst(2).prefix { $0 != "/" }).lowercased()
            if most[cc] != nil { most[cc, default: 0] += 1 }
        }
        let top = most.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }
        add("Places", "Most stamps in one country", top.flatMap { $0.value > 1 ? "\(name($0.key)), \($0.value.formatted())" : nil })
        // the place you went back to most
        let back = ids.compactMap { id -> (String, Int)? in
            let v = marks[.country(id)]?.visits ?? 0
            return v > 1 ? (id, v) : nil
        }.max { a, b in a.1 != b.1 ? a.1 < b.1 : a.0 > b.0 }
        add("Places", "Been back most", back.map { "\(name($0.0)), \($0.1.formatted()) times" })
        // the edges, by name: each place's own middle
        let mid = ids.compactMap { id -> (String, Double, Double)? in
            guard let ll = byID[id]?.ll, ll.count == 2 else { return nil }
            return (id, ll[0], ll[1])
        }
        add("The edges", "Northernmost", mid.max { $0.2 < $1.2 }.map { name($0.0) })
        add("The edges", "Southernmost", mid.min { $0.2 < $1.2 }.map { name($0.0) })
        add("The edges", "Easternmost", mid.max { $0.1 < $1.1 }.map { name($0.0) })
        add("The edges", "Westernmost", mid.min { $0.1 < $1.1 }.map { name($0.0) })
        // your years: each country's year (the month you went, else when you stamped it)
        var perYear: [Int: Int] = [:]
        for id in ids { if let y = Int(went(id).prefix(4)), y > 0 { perYear[y, default: 0] += 1 } }
        if let busiest = perYear.max(by: { a, b in a.value != b.value ? a.value < b.value : a.key < b.key }), perYear.count > 1 {
            add("Time", "Busiest year", "\(busiest.key), \(busiest.value.formatted()) places")
        }
        let thisYear = Calendar.current.component(.year, from: Date())
        if let n = perYear[thisYear], n > 0 { add("Time", "New this year", n.formatted()) }
        if let y = perYear.keys.min() { add("Time", "First year", String(y)) }
        if c.years > 1 {
            add("Time", "New places a year", (Double(ids.count) / Double(c.years)).formatted(.number.precision(.fractionLength(0 ... 1))))
        }
        return head
    }
}

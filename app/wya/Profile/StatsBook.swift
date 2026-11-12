import Foundation

// THE STATS PAGE FROM THE CATALOG: each badge that has a count is a row in its group ("12 of 48"), the app's own rows at
// the groups' heads; and a section for every country you have been to, from its levels of regions and its towns.

nonisolated enum StatsBook {
    static func of(_ a: String, _ b: String) -> String { a + " of " + b }

    static let order = ["Places", "UN regions", "Groups of countries", "Languages", "Currencies",
                               "Capitals of each continent", "The edges", "Lines of the globe", "Time", "Passport",
                               "Your map", "Nature", "Famous sets", "Things", "The AI", "The Challenge", "Helping",
                               "Badges", "Getting around"]

    static let nature: Set<String> = ["islands", "unesco", "summits", "highpoints", "sevensummits", "parks", "lakes",
                                      "rivers", "seas", "volcanoes", "deserts", "forests", "canyons", "glaciers",
                                      "waterfalls", "beaches", "caves"]
    static let lines: Set<String> = ["arctic", "the-antarctic-circle", "the-tropics", "equator", "the-prime-meridian",
                                     "the-date-line", "four-hemispheres"]
    static let edges: Set<String> = ["far", "furthest-north", "furthest-south", "highest-place", "lowest-place",
                                     "antipodes"]
    static let unRegionIds: Set<String> = Set(Badges.unRegions.map(Badges.slug))
    static let sets: Set<String> = ["groups", "languages", "currencies", "capitals", "famous"]

    static func group(of b: Badge) -> String? {
        if b.family == "social" || b.from == "social" || Badges.launchHidden.contains(b.id) { return nil }
        if b.family == "regions" || b.family == "towns" { return nil }
        if unRegionIds.contains(b.id) { return "UN regions" }
        if b.id == "continents-in-one-year" { return "Time" }
        if lines.contains(b.id) { return "Lines of the globe" }
        if edges.contains(b.id) { return "The edges" }
        if nature.contains(b.id) { return "Nature" }
        switch b.family {
        case "groups": return "Groups of countries"
        case "languages": return "Languages"
        case "currencies": return "Currencies"
        case "capitals": return "Capitals of each continent"
        case "famous": return "Famous sets"
        case "extremes": return "The edges"
        case "months", "time", "v-time": return "Time"
        case "passport": return "Passport"
        case "map": return "Your map"
        case "things", "biggest": return "Things"
        case "ai": return "The AI"
        case "challenge": return "The Challenge"
        case "helping": return "Helping"
        case "around": return "Getting around"
        default: return "Places"
        }
    }

    static func total(of b: Badge, world w: BadgeWorld?) -> Int? {
        if let o = b.outOf, o > 0 { return o }
        if b.id == "continents" { return 7 }
        if sets.contains(b.family) || unRegionIds.contains(b.id) { return b.steps.last }
        guard let w else { return nil }
        switch b.id {
        case "islandnations": return Badges.islandCountries.filter { w.places[$0] != nil }.count
        case "landlocked": return w.countries.filter(\.landlocked).count
        case "microstates": return w.countries.filter { $0.area > 0 && $0.area < Badges.microstateArea }.count
        default: return nil
        }
    }

    static func row(_ b: Badge, world w: BadgeWorld?, format: (Int) -> String = Badges.grouped,
                           of: (String, String) -> String = StatsBook.of) -> StatRow? {
        guard b.have > 0 else { return nil }
        if let t = total(of: b, world: w), b.unit == .count {
            return StatRow(label: b.name, value: of(format(b.have), format(t)))
        }
        return StatRow(label: b.name, value: Badges.say(b.have, b.unit, format: format))
    }

    static func page(badges: [Badge], world w: BadgeWorld?, head: [String: [StatRow]] = [:],
                            foot: [String: [StatRow]] = [:], format: (Int) -> String = Badges.grouped,
                            of: (String, String) -> String = StatsBook.of) -> [StatGroup] {
        var rows: [String: [StatRow]] = [:]
        for b in badges {
            guard let g = group(of: b), let r = row(b, world: w, format: format, of: of) else { continue }
            rows[g, default: []].append(r)
        }
        return order.compactMap { g in
            var seen = Set<String>()
            let all = ((head[g] ?? []) + (rows[g] ?? []) + (foot[g] ?? [])).filter { seen.insert($0.label).inserted }
            return all.isEmpty ? nil : StatGroup(title: g, rows: all)
        }
    }

    struct Level: Sendable, Equatable {
        let lvl: Int
        let word: String
        let n: Int
        init(lvl: Int, word: String, n: Int) { self.lvl = lvl; self.word = word; self.n = n }
    }

    struct Mine: Sendable, Equatable {
        var stamped = false
        var visits = 0
        var lived = false
        var regions: [Int: Int] = [:]
        var towns = 0
        var capital = false
        var places = 0
        var things = 0
        init() {}
    }

    struct Section: Sendable, Equatable, Identifiable {
        let cc: String
        let name: String
        let rows: [StatRow]
        var id: String { cc }
    }

    static func section(cc: String, name: String, levels: [Level], towns: Int, capital: String?, mine m: Mine,
                               format: (Int) -> String = Badges.grouped, of: (String, String) -> String = StatsBook.of) -> Section? {
        var rows: [StatRow] = []
        let ls = levels.sorted { $0.n < $1.n }
        let any = m.regions.values.reduce(0, +) > 0
        for (i, l) in ls.enumerated() where l.n > 0 {
            let have = m.regions[l.lvl] ?? 0
            guard have > 0 || (i == 0 && any) else { continue }
            rows.append(StatRow(label: l.word, value: of(format(have), format(l.n))))
        }
        if m.towns > 0 {
            rows.append(StatRow(label: "Towns", value: towns > 0 ? of(format(m.towns), format(towns)) : format(m.towns)))
        }
        if m.capital, let capital { rows.append(StatRow(label: "Capital", value: capital)) }
        if m.places > 0 { rows.append(StatRow(label: "Your places", value: format(m.places))) }
        if m.things > 0 { rows.append(StatRow(label: "Things marked", value: format(m.things))) }
        if m.stamped && m.visits > 1 { rows.append(StatRow(label: "Times been", value: format(m.visits))) }
        if m.lived { rows.append(StatRow(label: "Lived here", value: "Yes")) }
        return rows.isEmpty ? nil : Section(cc: cc, name: name, rows: rows)
    }
}

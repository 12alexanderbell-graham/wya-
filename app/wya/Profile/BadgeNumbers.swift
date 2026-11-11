import Foundation

// YOUR NUMBERS: THE BADGES AND THE STATS, counted from your own map and stamps (brought over from the first app's
// core, where they were built and tested). A badge has five levels, each a count to reach (lime, blue, silver, gold,
// diamond); `live` says what it is counted from. A badge or a stat the app cannot count yet is not shown until it
// can: no number here is ever a sample.

nonisolated struct Badge: Equatable, Sendable, Identifiable {
    let id: String
    var name: String
    var steps: [Int]
    var have: Int
    var what: String
    let live: String?
    var outOf: Int? = nil
    var countsCountries = false
    var family = "v"
    var place: String? = nil
    var unit: BadgeUnit = .count
    var from = "now"
    var fixedLevel: Int? = nil

    init(_ id: String, _ name: String, _ steps: [Int], have: Int = 0, _ what: String, live: String? = nil) {
        self.id = id; self.name = name; self.steps = steps; self.have = have; self.what = what; self.live = live
    }

    init(id: String, name: String, steps: [Int], what: String, family: String, live: String?, from: String,
                place: String? = nil, unit: BadgeUnit = .count) {
        self.id = id; self.name = name; self.steps = steps; self.have = 0; self.what = what; self.live = live
        self.family = family; self.from = from; self.place = place; self.unit = unit
    }

    func counting(_ live: String?, from: String, family: String, steps: [Int]? = nil, what: String? = nil) -> Badge {
        var b = Badge(id: id, name: name, steps: steps ?? self.steps, what: what ?? self.what, family: family, live: live,
                      from: from, place: place, unit: unit)
        b.outOf = outOf
        return b
    }

    var level: Int { fixedLevel ?? steps.filter { have >= $0 }.count }
}

nonisolated enum BadgeUnit: String, Sendable, Equatable {
    case count, percent, km
    case metres
    case tenthDegrees
}

nonisolated struct Counted: Sendable {
    var countries = false
    var world = (have: 0, total: 0)
    var continents: [String: (have: Int, total: Int)] = [:]
    var territories = 0
    var lived = 0
    var wish = 0
    var streak = 0
    var verified = 0
    var regions = 0
    var towns = 0
    var capitals = 0
    var lists = 0
    var tiers = 0
    var plans = 0
    var aiPlans = 0
    var books = 0
    var notes = 0
    var years = 0
    var months = 0
    var more: [String: Int] = [:]
    var fixed: [String: Int] = [:]
    var steps: [String: [Int]] = [:]
    init() {}
}

nonisolated enum Badges {
    static let levelName = ["", "Lime", "Blue", "Silver", "Gold", "Diamond"]

    static let launchHidden: Set<String> = ["posts", "photos", "videos", "tips", "comments", "saves", "likes",
        "liked", "followers", "following", "friends", "invites", "solo", "groups", "surveys", "boards", "joined",
        "topten", "collective"]

    static let all: [Badge] = [
        Badge("countries", "Countries", [1, 10, 25, 50, 100], "Places you have a stamp in.", live: "world"),
        Badge("continents", "Continents", [1, 2, 3, 5, 7], "Continents you have set foot on.", live: "continents"),
        Badge("europe", "Europe", [5, 10, 20, 35, 48], "Countries in Europe.", live: "cont:Europe"),
        Badge("asia", "Asia", [3, 8, 15, 30, 49], "Countries in Asia.", live: "cont:Asia"),
        Badge("africa", "Africa", [1, 5, 10, 25, 54], "Countries in Africa.", live: "cont:Africa"),
        Badge("namerica", "North America", [1, 3, 8, 15, 23], "Countries in North America.", live: "cont:North America"),
        Badge("samerica", "South America", [1, 2, 5, 8, 12], "Countries in South America.", live: "cont:South America"),
        Badge("oceania", "Oceania", [1, 2, 4, 8, 14], "Countries in Oceania.", live: "cont:Oceania"),
        Badge("antarctica", "Antarctica", [1, 2, 3, 4, 5], "Stamps in Antarctica.", live: "cont:Antarctica"),
        Badge("territories", "Territories", [1, 3, 8, 20, 40], "Stamps in territories and other places not counted as countries.", live: "territories"),
        Badge("lived", "Lived in", [1, 2, 3, 5, 8], "Places you have lived.", live: "lived"),
        Badge("wishlist", "Wishlist", [1, 10, 25, 50, 100], "Places on your wishlist.", live: "wish"),
        Badge("stamps", "Verified stamps", [1, 10, 25, 50, 100], "Stamps proven by a located photograph or your location history.", live: "verified"),
        Badge("capitals", "Capitals", [1, 5, 15, 40, 100], "Capital cities you have been to.", live: "capitals"),
        Badge("cities", "Cities and towns", [1, 10, 50, 150, 500], "Cities and towns you have marked.", live: "towns"),
        Badge("regions", "Regions", [1, 10, 50, 150, 500], "Regions you have marked.", live: "regions"),
        Badge("islands", "Islands", [1, 3, 10, 25, 60], "Islands you have stood on, big or small."),
        Badge("unesco", "UNESCO", [1, 5, 15, 40, 100], "World Heritage sites you have visited."),
        Badge("summits", "Summits", [1, 3, 7, 15, 30], "Peaks you have climbed, on your own feet."),
        Badge("highpoints", "National high points", [1, 3, 10, 25, 50], "The highest point of a country, reached."),
        Badge("sevensummits", "Seven Summits", [1, 2, 3, 5, 7], "The highest peak of each continent, reached."),
        Badge("parks", "National parks", [1, 3, 10, 25, 60], "National parks you have been to."),
        Badge("lakes", "Lakes", [1, 3, 10, 25, 60], "Lakes you have been to."),
        Badge("seas", "Seas and oceans", [1, 3, 8, 15, 30], "Seas and oceans you have been on or in."),
        Badge("volcanoes", "Volcanoes", [1, 2, 5, 10, 20], "Volcanoes you have stood on."),
        Badge("deserts", "Deserts", [1, 2, 4, 8, 15], "Deserts you have crossed or slept in."),
        Badge("glaciers", "Glaciers", [1, 2, 5, 10, 20], "Glaciers you have walked on."),
        Badge("waterfalls", "Waterfalls", [1, 3, 10, 25, 50], "Waterfalls you have been to."),
        Badge("beaches", "Beaches", [1, 5, 20, 50, 150], "Beaches you have been to."),
        Badge("caves", "Caves", [1, 2, 5, 10, 20], "Caves you have been inside."),
        Badge("equator", "The equator", [1, 2, 5, 10, 20], "Times you have crossed the equator."),
        Badge("arctic", "The Arctic Circle", [1, 2, 3, 5, 10], "Times you have been north of the Arctic Circle."),
        Badge("islandnations", "Island countries", [1, 3, 8, 15, 30], "Countries that are islands or groups of islands."),
        Badge("landlocked", "Landlocked countries", [1, 3, 8, 15, 30], "Countries with no coast."),
        Badge("microstates", "Microstates", [1, 2, 3, 5, 7], "The smallest countries in the world."),
        Badge("tripoints", "Tripoints", [1, 2, 4, 8, 15], "Points where three countries meet, stood on."),
        Badge("borders", "Borders", [1, 5, 15, 40, 100], "Borders crossed by land or sea, not by air."),
        Badge("zones", "Time zones", [2, 4, 8, 12, 24], "Time zones you have woken up in."),
        Badge("trains", "Trains", [1, 5, 15, 40, 100], "Train journeys between two countries."),
        Badge("nighttrains", "Night trains", [1, 3, 10, 25, 50], "Nights spent on a train."),
        Badge("metros", "Metros", [1, 5, 15, 40, 100], "Cities whose metro you have ridden."),
        Badge("ferries", "Ferries", [1, 3, 10, 25, 60], "Crossings by boat."),
        Badge("flights", "Flights", [1, 10, 50, 150, 500], "Flights you have taken."),
        Badge("airports", "Airports", [1, 10, 25, 60, 150], "Airports you have flown from or to."),
        Badge("roadtrips", "Road trips", [1, 3, 10, 25, 50], "Trips you have driven."),
        Badge("hikes", "Hikes", [1, 5, 20, 50, 150], "Hikes you have done."),
        Badge("cycling", "By bike", [1, 3, 10, 25, 50], "Trips you have made by bike."),
        Badge("distance", "Distance", [1000, 10000, 50000, 150000, 500000], "Kilometres you have travelled."),
        Badge("far", "Far from home", [100, 1000, 5000, 10000, 20000], "The furthest you have been from your home base, in kilometres."),
        Badge("nights", "Nights away", [7, 30, 100, 365, 1000], "Nights spent outside your home base."),
        Badge("streak", "Streak", [2, 4, 8, 26, 52], "Weeks in a row you stamped, wishlisted, posted or made something.", live: "streak"),
        Badge("months", "Months in a row", [2, 4, 8, 12, 24], "Months in a row with a new stamp.", live: "months"),
        Badge("trips", "Trips", [1, 5, 15, 40, 100], "Trips you have taken."),
        Badge("longest", "Longest trip", [7, 14, 30, 60, 120], "Your longest trip, in days."),
        Badge("weekends", "Weekends away", [1, 5, 15, 40, 100], "Weekends spent away from home."),
        Badge("solotrips", "Solo trips", [1, 3, 10, 25, 50], "Trips you have taken on your own."),
        Badge("years", "Years travelling", [1, 2, 5, 10, 20], "Years you went somewhere, by your stamps' dates.", live: "years"),
        Badge("early", "First year", [1, 10, 50, 100, 365], "Days you were here in the app's first year."),
        Badge("languages", "Languages", [2, 5, 10, 20, 40], "Languages spoken in the places you have stamped."),
        Badge("currencies", "Currencies", [2, 5, 10, 20, 40], "Currencies of the places you have stamped."),
        Badge("scripts", "Alphabets", [1, 2, 4, 6, 10], "Writing systems in the places you have stamped."),
        Badge("rated", "Places rated", [1, 10, 50, 200, 1000], "Places you have given stars."),
        Badge("lists", "Lists", [1, 3, 10, 25, 50], "Lists you have made and published.", live: "mylists"),
        Badge("tierlists", "Tier lists", [1, 3, 10, 25, 50], "Tier lists you have made.", live: "tiers"),
        Badge("plans", "Plans", [1, 3, 10, 25, 50], "Plans you have made.", live: "plans"),
        Badge("aiplans", "Planned with the AI", [1, 5, 15, 40, 100], "Plans the AI made with you.", live: "aiplans"),
        Badge("books", "Photo books", [1, 2, 5, 10, 20], "Photo books you have made.", live: "books"),
        Badge("notes", "Notes", [1, 10, 50, 200, 1000], "Notes you have written on places.", live: "notes"),
        Badge("posts", "Posts", [1, 10, 50, 200, 1000], "Things you have posted."),
        Badge("photos", "Photographs", [1, 25, 100, 500, 2000], "Photographs you have posted."),
        Badge("videos", "Videos", [1, 5, 20, 50, 150], "Videos you have posted."),
        Badge("tips", "Tips", [1, 5, 20, 50, 150], "Tips you have written for a place."),
        Badge("comments", "Comments", [1, 10, 50, 200, 1000], "Comments you have written.", live: "comments"),
        Badge("shares", "Shared", [1, 10, 50, 200, 1000], "Things you have shared."),
        Badge("saves", "Saved by others", [10, 100, 1000, 10000, 100000], "How many times your things have been saved."),
        Badge("likes", "Likes", [10, 100, 1000, 10000, 100000], "Likes on the things you have posted."),
        Badge("liked", "Likes given", [10, 100, 500, 2000, 10000], "Likes you have given.", live: "liked"),
        Badge("followers", "Followers", [10, 100, 1000, 10000, 100000], "People who follow you."),
        Badge("following", "Following", [1, 10, 50, 200, 1000], "People you follow.", live: "following"),
        Badge("friends", "Friends", [1, 5, 15, 40, 100], "Friends on wya?!."),
        Badge("invites", "Invites", [1, 3, 10, 25, 50], "Friends who joined from your invite."),
        Badge("solo", "Solo", [1, 5, 15, 40, 100], "People you have met through Solo."),
        Badge("groups", "Teams", [1, 3, 10, 25, 50], "Teams you have travelled in."),
        Badge("surveys", "Surveys", [1, 10, 50, 200, 1000], "Surveys you have answered.", live: "votes"),
        Badge("boards", "Boards", [1, 3, 10, 25, 50], "Boards you have finished."),
        Badge("joined", "Boards joined", [1, 3, 10, 25, 50], "Boards you have joined.", live: "joined"),
        Badge("topten", "Top ten", [1, 3, 10, 25, 50], "Boards you finished in the top ten."),
        Badge("collective", "Collective boards", [1, 10, 50, 200, 1000], "Stamps you have added to collective boards."),
        Badge("wishes", "Wishes come true", [1, 5, 15, 40, 100], "Places from your wishlist you went on to stamp."),
        Badge("anniversary", "Years here", [1, 2, 3, 5, 10], "Years since you joined."),
    ]

    static func autoSteps(_ total: Int) -> [Int] {
        let t = Double(total)
        var s = [max(1, Int((t * 0.06).rounded())), Int((t * 0.2).rounded()), Int((t * 0.4).rounded()),
                 Int((t * 0.7).rounded()), total]
        for i in 1..<5 { s[i] = max(s[i], s[i - 1] + 1) }
        return s
    }

    static func now(_ b: Badge, _ c: Counted, launch: Bool = true, format: (Int) -> String = Badges.grouped) -> Badge {
        var o = b
        if launch {
            if b.id == "lists" { o.what = "Lists you have made." }
            if b.id == "streak" { o.what = "Weeks in a row you stamped, wishlisted or made something." }
        }
        guard let live = b.live else { return o }
        switch live {
        case "world":
            o.have = c.world.have
            o.name = c.countries ? "Countries" : "Stamps"
            o.what = (c.countries ? "Countries you have a stamp in" : "Places you have a stamp in") + ", out of " + format(c.world.total) + "."
            o.outOf = c.world.total; o.countsCountries = c.countries
        case "continents":
            o.have = c.continents.values.filter { $0.have > 0 }.count
        case let k where k.hasPrefix("cont:"):
            let name = String(k.dropFirst(5))
            let s = c.continents[name] ?? (0, 0)
            o.have = s.have
            o.steps = autoSteps(s.total)
            o.what = (!c.countries || name == "Antarctica" ? "Stamps" : "Countries") + " in " + name + ", out of " + format(s.total) + "."
            o.outOf = s.total; o.countsCountries = c.countries && name != "Antarctica"
        case "territories": o.have = c.territories
        case "lived": o.have = c.lived
        case "wish": o.have = c.wish
        case "streak": o.have = c.streak
        case "verified": o.have = c.verified
        case "regions": o.have = c.regions
        case "towns": o.have = c.towns
        case "capitals": o.have = c.capitals
        case "mylists": o.have = c.lists
        case "tiers": o.have = c.tiers
        case "plans": o.have = c.plans
        case "aiplans": o.have = c.aiPlans
        case "books": o.have = c.books
        case "notes": o.have = c.notes
        case "years": o.have = c.years
        case "months": o.have = c.months
        case "more":
            o.have = c.more[b.id] ?? 0
            o.fixedLevel = c.fixed[b.id]
            if let s = c.steps[b.id], !s.isEmpty { o.steps = s }
        default: break
        }
        return o
    }

    static func earned(_ c: Counted, catalog: [Badge] = all, launch: Bool = true) -> [Badge] {
        catalog.filter { !launch || !launchHidden.contains($0.id) && $0.from != "social" }
            .map { now($0, c, launch: launch) }
            .filter { $0.level > 0 }
            .sorted { $0.level != $1.level ? $0.level > $1.level : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func levels(_ earned: [Badge]) -> Int { earned.reduce(0) { $0 + $1.level } }

    static func years(_ stamps: [(when: String, at: Date)], calendar: Calendar = .current) -> Int {
        Set(stamps.compactMap { s -> Int? in
            if s.when.count >= 4, let y = Int(s.when.prefix(4)) { return y }
            return calendar.component(.year, from: s.at)
        }).count
    }

    static func monthsInARow(_ activity: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int {
        func m(_ d: Date) -> Int { let c = calendar.dateComponents([.year, .month], from: d); return c.year! * 12 + c.month! - 1 }
        let months = Set(activity.map(m))
        var k = m(now), n = 0
        if !months.contains(k) { k -= 1 }
        while months.contains(k) { n += 1; k -= 1 }
        return n
    }

    static func news(_ earned: [Badge], seen: [String: Int]) -> Bool {
        earned.contains { (seen[$0.id] ?? 0) < $0.level }
    }
    static func seen(_ earned: [Badge]) -> [String: Int] {
        Dictionary(earned.map { ($0.id, $0.level) }, uniquingKeysWith: { a, _ in a })
    }

    static func facts(_ b: Badge, format: (Int) -> String = Badges.grouped) -> [(plain: String, strong: String, after: String, strong2: String)] {
        let l = b.level
        func say(_ n: Int) -> String { Badges.say(n, b.unit, format: format) }
        var out: [(String, String, String, String)] = [("You have ", say(b.have), "", "")]
        if l > b.steps.count {
            out.append(("", levelName[l], " at ", "all of them, at every level"))
            out.append(("Nothing above ", levelName[l].lowercased(), "", ""))
            return out
        }
        out.append(("", levelName[l], " at ", say(b.steps[max(0, l - 1)])))
        if l < b.steps.count { out.append(("", levelName[l + 1], " at ", say(b.steps[l]))) }
        else { out.append(("Nothing above ", levelName[l].lowercased(), "", "")) }
        return out
    }

    static func say(_ n: Int, _ unit: BadgeUnit, format: (Int) -> String = Badges.grouped) -> String {
        switch unit {
        case .count: return format(n)
        case .percent: return format(n) + "%"
        case .km: return format(n) + " km"
        case .metres: return format(n) + " m"
        case .tenthDegrees: return String(n / 10) + "." + String(abs(n % 10)) + "°"
        }
    }

    static func shareLine(_ b: Badge) -> String { levelName[b.level] + " " + b.name + " on wya?!" }

    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }
}

nonisolated struct StatGroup: Equatable, Sendable, Identifiable {
    let title: String
    let rows: [StatRow]
    var id: String { title }
}
nonisolated struct StatRow: Equatable, Sendable, Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

nonisolated enum Stats {
    static let layout: [(String, [String])] = [
        ("Places", ["Stamps", "Continents", "Countries in Europe", "Share of the world", "Capitals", "Cities and towns",
                    "Regions", "Territories", "Lived in", "Wishlist", "Most stamps in one country", "First stamp",
                    "Latest stamp", "Northernmost", "Southernmost"]),
        ("Time", ["Years travelling", "Weeks in a row", "Months in a row"]),
        ("Things", ["Lists", "Plans", "Planned with the AI", "Tier lists", "Photo books", "Notes", "Badge levels"]),
    ]

    static func mine(counted: [String: String?]) -> [StatGroup] {
        layout.compactMap { g, labels in
            let kept: [StatRow] = labels.compactMap { label in
                guard let v = counted[label] ?? nil, !v.isEmpty else { return nil }
                return StatRow(label: label, value: v)
            }
            return kept.isEmpty ? nil : StatGroup(title: g, rows: kept)
        }
    }

    static func count(_ groups: [StatGroup]) -> Int { groups.reduce(0) { $0 + $1.rows.count } }

    static func shareText(_ rows: [StatRow]) -> String {
        rows.map { $0.label + ": " + $0.value }.joined(separator: "\n") + "\non wya?!"
    }
}

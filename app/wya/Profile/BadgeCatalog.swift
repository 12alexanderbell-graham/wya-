import Foundation

// EVERY BADGE THE APP KNOWS, made once against the world (brought over from the first app's core, where it was built
// and tested): the world as the badges count against it (each place's facts, its levels of regions, its towns), what
// you have as the badges count it (BadgeInput), the steps of each family, and the catalog itself. A badge whose count
// the app cannot make yet stays at nought and is not shown.

/// a place's facts as the badges' pack has them (native/badges/badges-N.wybd)
nonisolated struct BadgeFacts: Decodable, Sendable {
    let k: String
    let cont: String
    let sub: String?
    let pop: Double
    let area: Double
    let lang: [String]
    let cur: [String]
    let landlocked: Bool
    /// west, south, east, north
    let bb: [Double]
    let borders: [String]
    /// its middle [lon, lat]
    let c: [Double]
    let n: String
    let s: String
}

nonisolated struct BadgeWorld: Sendable {
    struct Country: Sendable, Equatable {
        let id: String
        let n: String
        let s: String
        let k: String
        let cont: String
        let sub: String?
        let pop: Double
        let area: Double
        let lang: [String]
        let cur: [String]
        let landlocked: Bool
        let bb: [Double]
        let borders: [String]
        let c: [Double]
    }
    struct Regions: Sendable, Equatable {
        let first: Int
        let n: Int
        let word: String
        let deep: Int
        let deepN: Int
        let below: [Int]
    }

    let places: [String: Country]
    let countries: [Country]
    let regions: [String: Regions]
    let towns: [String: Int]
    let capitals: Set<String>
    let tables: BadgeTables?

    /// `facts`: each place of the map with what the pack knows of it; `levels`: each place's levels of regions as the
    /// regions' own table has them (row 1 first)
    init(facts: [(id: String, f: BadgeFacts)], levels: [String: [RegionCatalog.Level]], towns: [String: Int], capitals: Set<String>,
         tables: BadgeTables? = nil) {
        self.tables = tables
        var ps: [String: Country] = [:]
        for (id, p) in facts {
            ps[id] = Country(id: id, n: p.n, s: p.s, k: p.k, cont: p.cont, sub: p.sub, pop: p.pop, area: p.area, lang: p.lang,
                             cur: p.cur, landlocked: p.landlocked, bb: p.bb, borders: p.borders, c: p.c)
        }
        self.places = ps
        countries = facts.filter { $0.f.k == "country" }.compactMap { ps[$0.id] }
        var rs: [String: Regions] = [:]
        for (id, _) in facts {
            // (its levels in use; one that is the level before it again is not counted twice; its regions are the level
            // the table calls its first, else the first in use)
            var ls: [(lvl: Int, n: Int, k: String, word: String, first: Bool)] = []
            for (i, r) in (levels[id] ?? []).enumerated() where r.n != 0 {
                if let pv = ls.last, pv.n == r.n, pv.k == (r.k ?? "") { continue }
                ls.append((i + 1, r.n, r.k ?? "", r.many, r.first == true))
            }
            guard let f = ls.first(where: { $0.first }) ?? ls.first, let d = ls.max(by: { $0.n < $1.n }) else { continue }
            let below = ls.filter { $0.n > f.n }.sorted { $0.n < $1.n }.map { $0.lvl }
            rs[id] = Regions(first: f.lvl, n: f.n, word: f.word, deep: d.lvl, deepN: d.n, below: below)
        }
        regions = rs
        self.towns = towns
        self.capitals = capitals
    }
}

nonisolated struct BadgeInput: Sendable {
    struct Point: Sendable, Equatable {
        let lat: Double
        let lon: Double
        init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    }
    struct TownMark: Sendable, Equatable {
        let cc: String
        let kind: Int
        let p: Int
        let lat: Double
        let lon: Double
        let gid: Int
        init(cc: String, kind: Int, p: Int, lat: Double, lon: Double, gid: Int = 0) {
            self.cc = cc; self.kind = kind; self.p = p; self.lat = lat; self.lon = lon; self.gid = gid
        }
    }
    struct Dated: Sendable, Equatable {
        let month: String
        let cc: String
        let lat: Double?
        init(month: String, cc: String, lat: Double? = nil) { self.month = month; self.cc = cc; self.lat = lat }
    }

    var stamped: Set<String> = []
    var counted: Set<String> = []
    var regions: [(cc: String, lvl: Int)] = []
    var towns: [String: Int] = [:]
    var townFacts: [TownMark] = []
    var points: [Point] = []
    var marks: [String] = []
    var dated: [Dated] = []
    var numbers: [String: Int] = [:]
    var markIds: Set<String> = []
    var markHeights: [Double] = []
    var home: Home? = nil
    struct Home: Sendable, Equatable {
        let cc: String
        let lat: Double
        let lon: Double
        init(cc: String, lat: Double, lon: Double) { self.cc = cc; self.lat = lat; self.lon = lon }
    }
    init() {}
}

nonisolated extension BadgeInput: Equatable {
    static func == (a: BadgeInput, b: BadgeInput) -> Bool {
        a.stamped == b.stamped && a.counted == b.counted && a.towns == b.towns && a.townFacts == b.townFacts
            && a.points == b.points && a.marks == b.marks && a.dated == b.dated && a.numbers == b.numbers
            && a.markIds == b.markIds && a.markHeights == b.markHeights && a.home == b.home
            && a.regions.count == b.regions.count && zip(a.regions, b.regions).allSatisfy { $0.cc == $1.cc && $0.lvl == $1.lvl }
    }
}

nonisolated extension Badges {
    static let catalogVersion = 2

    static func setSteps(_ n: Int) -> [Int] {
        if n <= 1 { return [1] }
        if n < 6 { return Array(2...n) }
        let d = Double(n)
        return increasing([max(2, Int((0.1 * d).rounded(.up))), Int((0.3 * d).rounded(.up)), Int((0.55 * d).rounded(.up)),
                           Int((0.8 * d).rounded(.up)), n])
    }

    static func regionSteps(_ n: Int) -> [Int] {
        if n <= 1 { return [1] }
        let d = Double(n)
        return increasing([1, Int((d / 3).rounded(.up)), Int((2 * d / 3).rounded(.up)), n])
    }

    static func townSteps(_ total: Int) -> [Int] {
        guard total > 0 else { return [1] }
        return increasing([3, 10, 25, 60, 150].map { min($0, total) })
    }

    static func increasing(_ s: [Int]) -> [Int] {
        var out: [Int] = []
        for x in s where out.last.map({ x > $0 }) ?? true { out.append(x) }
        return out
    }

    static let unRegions = ["Northern Europe", "Western Europe", "Southern Europe", "Eastern Europe", "Northern Africa",
        "Western Africa", "Middle Africa", "Eastern Africa", "Southern Africa", "Western Asia", "Central Asia",
        "Southern Asia", "Eastern Asia", "South-Eastern Asia", "Northern America", "Central America", "Caribbean",
        "Australia and New Zealand", "Melanesia", "Micronesia", "Polynesia"]

    static let groups: [(String, [String])] = [
        ("Nordic countries", ["dk", "fi", "is", "no", "se"]),
        ("Baltic states", ["ee", "lv", "lt"]),
        ("Benelux", ["be", "nl", "lu"]),
        ("British Isles", ["gb", "ie", "im", "gg", "je"]),
        ("Iberia", ["es", "pt", "ad", "gi"]),
        ("The Alps", ["fr", "ch", "it", "at", "de", "li", "si", "mc"]),
        ("The Caucasus", ["am", "az", "ge"]),
        ("Arabian Peninsula", ["bh", "kw", "om", "qa", "sa", "ae", "ye"]),
        ("The Levant", ["il", "jo", "lb", "ps", "sy"]),
        ("The Maghreb", ["dz", "ly", "ma", "mr", "tn", "eh"]),
        ("Horn of Africa", ["dj", "er", "et", "so"]),
        ("Mainland Southeast Asia", ["kh", "la", "mm", "th", "vn", "my"]),
        ("The Himalayas", ["bt", "cn", "in", "np", "pk"]),
        ("The Andes", ["ar", "bo", "cl", "co", "ec", "pe", "ve"]),
        ("Southern Cone", ["ar", "cl", "uy", "py"]),
        ("The Guianas", ["gy", "sr", "gf"]),
        ("Greater Antilles", ["cu", "do", "ht", "jm", "pr", "ky"]),
        ("Lesser Antilles", ["ag", "bb", "dm", "gd", "kn", "lc", "vc", "tt", "gp", "mq", "aw", "cw"]),
        ("The Mediterranean", ["es", "fr", "mc", "it", "mt", "si", "hr", "ba", "me", "al", "gr", "tr", "cy", "sy", "lb",
                               "il", "ps", "eg", "ly", "tn", "dz", "ma"]),
        ("The Danube", ["de", "at", "sk", "hu", "hr", "rs", "bg", "ro", "md", "ua"]),
        ("The Nile", ["eg", "sd", "ss", "ug", "et"]),
        ("The Amazon", ["br", "pe", "co", "bo", "ec", "ve", "gy", "sr", "gf"]),
        ("The Arctic", ["ca", "dk", "fi", "is", "no", "ru", "se", "us", "gl"]),
        ("On the equator", ["ec", "co", "br", "ga", "cg", "cd", "ug", "ke", "so", "mv", "id", "ki", "st"]),
    ]

    static let languageAreas = ["English", "French", "Arabic", "Spanish", "Portuguese", "Russian", "German", "Swahili", "Italian"]

    static let currencies: [(String, String)] = [("The euro", "EUR"), ("The US dollar", "USD"),
        ("The West African franc", "XOF"), ("The Central African franc", "XAF"), ("The East Caribbean dollar", "XCD")]

    static let islandCountries: Set<String> = ["ag", "bs", "bh", "bb", "bn", "cv", "km", "cu", "cy", "dm", "do", "tl",
        "fj", "gd", "ht", "is", "id", "ie", "jm", "jp", "ki", "mg", "mv", "mt", "mh", "mu", "fm", "nr", "nz", "pw", "pg",
        "ph", "kn", "lc", "vc", "ws", "st", "sc", "sg", "sb", "lk", "to", "tt", "tv", "gb", "vu"]

    static let microstateArea = 1000.0

    static let placeKinds: [(String, String)] = [("city", "Cities"), ("area", "Areas"), ("landmark", "Landmarks"),
        ("mountain", "Mountains"), ("water", "Water"), ("nature", "Nature"), ("spot", "Spots"), ("stay", "Stays"),
        ("station", "Stations"), ("route", "Routes"), ("event", "Events")]

    static let markBadges: [String: Set<String>] = [
        "unesco": ["heritage"], "parks": ["park"], "islands": ["island", "islands"], "rivers": ["river"],
        "seas": ["ocean", "sea", "gulf", "bay", "strait", "lagoon", "fjord", "estuary", "reef"], "deserts": ["desert"],
        "summits": ["peak", "volcano"], "lakes": ["lake"], "volcanoes": ["volcano"], "glaciers": ["glacier"],
        "waterfalls": ["waterfall"], "beaches": ["beach"], "caves": ["cave"], "forests": ["forest"], "canyons": ["canyon"]]

    static let arcticCircle = 66.5634
    static let tropic = 23.4362
    static let lineBand = 15.0

    static func slug(_ s: String) -> String {
        var out = ""
        var dash = false
        for ch in s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")) {
            if ch.isLetter && ch.isASCII || ch.isNumber {
                if dash && !out.isEmpty { out.append("-") }
                out.append(ch); dash = false
            } else { dash = true }
        }
        return out
    }

    static func catalog(_ w: BadgeWorld) -> [Badge] {
        var out: [Badge] = []
        let v = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func keep(_ id: String, family: String) {   // one of v's, counted as before
            guard var b = v[id] else { return }
            b.family = family
            if b.live == nil { b = b.counting(nil, from: waits[id] ?? "now", family: family) }
            out.append(b)
        }
        func now(_ id: String, family: String, what: String? = nil) {   // one of v's the catalog now counts
            guard let b = v[id] else { return }
            out.append(b.counting("more", from: "now", family: family, what: what))
        }
        func add(_ id: String, _ name: String, _ steps: [Int], _ what: String, family: String, counted: Bool = true,
                 from: String = "now", place: String? = nil, unit: BadgeUnit = .count) {
            out.append(Badge(id: id, name: name, steps: steps, what: what, family: family, live: counted ? "more" : nil,
                             from: counted ? "now" : from, place: place, unit: unit))
        }
        func countries(_ f: (BadgeWorld.Country) -> Bool) -> Int { w.countries.filter(f).count }

        for id in ["countries", "continents", "europe", "asia", "africa", "namerica", "samerica", "oceania", "antarctica",
                   "territories", "lived", "wishlist"] { keep(id, family: "world") }
        now("wishes", family: "world", what: "Places on your wishlist you went on to stamp, since the app counts them.")
        add("share-of-the-world", "Share of the world", [5, 10, 25, 50, 100], "Your countries, as a share of all \(w.countries.count).", family: "world", unit: .percent)
        add("world-s-people", "World's people", [5, 15, 30, 50, 75], "Your countries' people, as a share of the world's.", family: "world", unit: .percent)
        add("world-s-land", "World's land", [5, 15, 30, 50, 75], "Your countries' land, as a share of the world's.", family: "world", unit: .percent)
        add("neighbours", "Neighbours", [1, 2, 3, 5, 8], "Countries next to your home country you have stamped.", family: "world")
        now("islandnations", family: "world", what: "Countries that are islands or groups of islands, out of \(islandCountries.count).")
        now("landlocked", family: "world", what: "Countries with no coast, out of \(countries { $0.landlocked }).")
        now("microstates", family: "world", what: "Countries under 1,000 km2, out of \(countries { $0.area > 0 && $0.area < microstateArea }).")
        for r in unRegions {
            let n = countries { $0.sub == r }
            add(slug(r), r == "South-Eastern Asia" ? "South-eastern Asia" : r, setSteps(n),
                "Countries in \(r == "South-Eastern Asia" ? "South-eastern Asia" : r), out of \(n).", family: "world")
        }
        keep("capitals", family: "world")
        add("regional-capitals", "Regional capitals", [1, 5, 15, 40, 100], "Capitals of regions and states you have marked.", family: "world")
        add("big-cities", "Big cities", [1, 5, 15, 40, 100], "Cities of a million people or more you have marked.", family: "world")
        add("small-towns", "Small towns", [1, 5, 15, 40, 100], "Towns of under 5,000 people you have marked.", family: "world")
        keep("cities", family: "world")
        keep("regions", family: "world")
        add("districts", "Districts", [1, 10, 50, 150, 500], "The level below regions you have marked: counties, districts, municipalities.", family: "world")
        add("local-areas", "Local areas", [1, 10, 50, 150, 500], "The level below that, where a country has one.", family: "world")
        add("whole-countries", "Whole countries", [1, 2, 5, 10, 25], "Places with every region marked.", family: "world")
        add("deep-in-one-country", "Deep in one country", [5, 10, 25, 50, 100], "The most regions you have marked in one place.", family: "world")
        let t = w.tables
        if t != nil { now("zones", family: "world", what: "Time zones you have been in: the hours from UTC, in standard time.") }
        else { keep("zones", family: "world") }
        now("languages", family: "world", what: "Official languages of the places you have stamped.")
        now("currencies", family: "world", what: "Currencies of the places you have stamped.")
        if t != nil { now("scripts", family: "world", what: "Writing systems of the official languages where you have stamped.") ; out[out.count - 1].steps = [2, 3, 5, 8, 12] }
        else { keep("scripts", family: "world") }
        now("far", family: "world", what: "The farthest you are sure you have been from your home base, in km.")
        out[out.count - 1].unit = .km
        now("arctic", family: "world", what: "Places of yours north of the Arctic Circle.")
        add("the-antarctic-circle", "The Antarctic Circle", [1, 2, 3, 5, 10], "Places of yours south of the Antarctic Circle.", family: "world")
        add("the-tropics", "The tropics", [1, 3, 10, 25, 60], "Places of yours between the two tropics.", family: "world")
        now("equator", family: "world", what: "Places of yours on both sides of the equator: the side with fewer counts.")
        add("the-prime-meridian", "The prime meridian", [1, 2, 5, 10, 20], "Places of yours on both sides of the prime meridian, near it: the side with fewer counts.", family: "world")
        add("the-date-line", "The date line", [1, 2, 5, 10, 20], "Places of yours on both sides of the date line, near it: the side with fewer counts.", family: "world")
        now("tripoints", family: "world", what: "Points where three countries meet that you have marked, or been within 2 km of.")

        add("places", "Places", [1, 10, 50, 150, 500], "Places you have added to your map.", family: "map")
        for (k, n) in placeKinds {
            add("kind-" + k, n, [1, 3, 10, 25, 60], "\(n) among your places and pins.", family: "map")
        }
        add("pins", "Pins", [1, 10, 50, 150, 500], "Pins you have dropped.", family: "map")
        add("tracked", "Tracked", [1, 10, 50, 150, 500], "Pins tracking dropped for you.", family: "map")
        add("drawn-routes", "Drawn routes", [1, 3, 10, 25, 50], "Routes you have drawn.", family: "map")
        add("route-length", "Route length", [10, 100, 500, 2000, 10000], "Kilometres of the routes you have drawn.", family: "map", unit: .km)
        keep("notes", family: "map")
        now("islands", family: "map", what: "Islands and groups of islands you have marked.")
        now("unesco", family: "map", what: "World Heritage sites you have marked.")
        now("summits", family: "map", what: "Peaks and volcanoes you have marked.")
        if t != nil {
            now("highpoints", family: "map", what: "Countries' highest points you have reached: a pin or place of yours within a kilometre of the top.")
            now("sevensummits", family: "map", what: "The highest peak of each continent reached (either list's: Kosciuszko or Puncak Jaya, Elbrus or Mont Blanc).")
        } else { keep("highpoints", family: "map"); keep("sevensummits", family: "map") }
        now("parks", family: "map", what: "National parks you have marked.")
        now("lakes", family: "map", what: "Lakes you have marked.")
        add("rivers", "Rivers", [1, 3, 10, 25, 60], "Rivers you have marked.", family: "map")
        now("seas", family: "map", what: "Seas, oceans, gulfs, bays and straits you have marked.")
        now("volcanoes", family: "map", what: "Volcanoes you have marked.")
        now("deserts", family: "map", what: "Deserts you have marked.")
        add("forests", "Forests", [1, 3, 10, 25, 60], "Forests you have marked.", family: "map")
        add("canyons", "Canyons", [1, 2, 5, 10, 20], "Canyons and gorges you have marked.", family: "map")
        now("glaciers", family: "map", what: "Glaciers you have marked.")
        now("waterfalls", family: "map", what: "Waterfalls you have marked.")
        now("beaches", family: "map", what: "Beaches you have marked.")
        now("caves", family: "map", what: "Caves you have marked.")

        keep("stamps", family: "passport")
        add("dated", "Dated", [1, 10, 25, 50, 100], "Places you have given the month you went.", family: "passport")
        add("with-a-photo", "With a photo", [1, 10, 25, 50, 100], "Stamps with a photo.", family: "passport", counted: false, from: "passport")
        add("been-back", "Been back", [1, 3, 10, 25, 50], "Places you have been to more than once.", family: "passport")
        add("big-year", "Big year", [3, 5, 10, 20, 40], "The most new countries in one year, by the months you went.", family: "passport")
        now("rated", family: "passport", what: "Places you have given stars.")

        for id in ["streak", "months", "years", "anniversary", "early"] { keep(id, family: "time") }

        keep("lists", family: "things")
        add("listed", "Listed", [1, 10, 50, 200, 1000], "Things in your lists.", family: "things")
        keep("plans", family: "things")
        add("days-planned", "Days planned", [1, 5, 15, 40, 100], "Days in your plans.", family: "things")
        add("planned", "Planned", [1, 10, 50, 200, 1000], "Things on your plans' days.", family: "things")
        add("calendar", "Calendar", [1, 3, 10, 25, 50], "Plans put in your calendar.", family: "things", counted: false, from: "later")
        keep("tierlists", family: "things")
        add("ranked", "Ranked", [1, 10, 50, 200, 1000], "Things you have ranked in your tier lists.", family: "things")
        keep("books", family: "things")
        add("pages", "Pages", [1, 10, 50, 200, 1000], "Pages in your photo books.", family: "things")
        add("book-photos", "Photos", [1, 10, 50, 200, 1000], "Photo pages in your books.", family: "things")
        add("written", "Written", [1, 5, 20, 50, 150], "Pages of words in your books.", family: "things")
        add("book-videos", "Videos", [1, 5, 20, 50, 150], "Video pages in your books.", family: "things")
        add("sketches", "Sketches", [1, 5, 20, 50, 150], "Drawn pages in your books.", family: "things")

        keep("aiplans", family: "ai")
        add("made-with-the-ai", "Made with the AI", [1, 5, 15, 40, 100], "Lists and tier lists the AI made with you.", family: "ai")
        add("ai-maps", "AI maps", [1, 5, 15, 40, 100], "Maps the AI drew for you.", family: "ai")

        add("challenge", "Challenge", [1, 10, 25, 50, 100], "Verified stamps in the season.", family: "challenge", counted: false, from: "passport")
        add("best-place", "Ranked", [1, 2, 3, 4, 5], "Your best place: top 1,000, 100, 10, the podium, first.", family: "challenge", counted: false, from: "server")
        add("seasons", "Seasons", [1, 2, 5, 10, 20], "Seasons you took part in.", family: "challenge", counted: false, from: "server")

        add("votes", "Votes", [1, 3, 10, 25, 50], "Coming soon features you voted for.", family: "helping")
        add("wished-for", "Wished for", [1, 3, 10, 25, 50], "Features you voted for that came out.", family: "helping", counted: false, from: "server")
        add("spotted", "Spotted", [1, 3, 10, 25, 50], "Mistakes you reported.", family: "helping")

        for id in ["borders", "distance", "nights", "weekends", "trains", "nighttrains", "metros"] { keep(id, family: "around") }
        add("buses", "Buses", [1, 5, 15, 40, 100], "Bus journeys between two places.", family: "around", counted: false, from: "trips")
        for id in ["ferries", "flights", "airports", "roadtrips", "hikes", "cycling", "trips", "longest", "solotrips", "shares"] {
            keep(id, family: "around")
        }

        for id in ["posts", "photos", "videos", "tips", "comments", "saves", "likes", "liked", "followers", "following",
                   "friends", "invites", "solo", "groups", "surveys", "boards", "joined", "topten", "collective"] {
            keep(id, family: "social")
            out[out.count - 1].from = "social"
        }
        for (id, n, what) in [("chats", "Chats", "Chats with friends."), ("made-together", "Made together", "Things you made with friends."),
                              ("trips-together", "Trips together", "Trips you took with friends.")] {
            add(id, n, [1, 10, 50, 200, 1000], what, family: "social", counted: false, from: "social")
        }

        for (cc, r) in w.regions.sorted(by: { (w.places[$0.key]?.n ?? $0.key) < (w.places[$1.key]?.n ?? $1.key) }) {
            guard let p = w.places[cc] else { continue }
            let word = r.word.lowercased()
            add("regions-" + cc, possessive(p.s) + " " + word, regionSteps(r.n),
                "\(r.word) of \(p.n) you have marked, out of \(grouped(r.n)).", family: "regions", place: cc)
        }
        for (cc, n) in w.towns.sorted(by: { (w.places[$0.key]?.n ?? $0.key) < (w.places[$1.key]?.n ?? $1.key) }) where n > 0 {
            guard let p = w.places[cc] else { continue }
            add("towns-" + cc, "Towns of " + p.s, townSteps(n), "Towns of \(p.n) you have marked, out of \(grouped(n)).",
                family: "towns", place: cc)
        }
        for c in ["Europe", "Asia", "Africa", "North America", "South America", "Oceania"] {
            let n = countries { $0.cont == c && w.capitals.contains($0.id) }
            add("capitals-" + slug(c), "Capitals of " + c, setSteps(n), "Capitals of \(c)'s countries you have been to, out of \(n).",
                family: "capitals", place: c)
        }
        for (g, m) in groups {
            let ms = m.filter { w.places[$0] != nil }
            let n = ms.count
            let names = ms.compactMap { w.places[$0]?.s }
            let what = n <= 8 ? "Places you have stamped of these \(n): " + names.joined(separator: ", ") + "."
                : "Places you have stamped of the \(n) in it."
            add(slug(g), g, setSteps(n), what, family: "groups")
        }
        for l in languageAreas {
            let n = countries { $0.lang.contains(l) }
            add(slug(l) + "-speaking", l + "-speaking", setSteps(n), "Countries where \(l) is official, out of \(n).", family: "languages")
        }
        for (name, code) in currencies {
            let n = countries { $0.cur.contains(code) }
            add(slug(name), name, setSteps(n), "Countries that pay in \(name.prefix(1).lowercased() + name.dropFirst()), out of \(n).", family: "currencies")
        }
        for (name, n) in famous {
            let set = w.tables?.sets.first { $0.id == slug(name) }
            let k = set.map { $0.by == "continent" ? Set($0.members.compactMap(\.cont)).count : $0.members.count } ?? n
            add(slug(name), name, increasing([1, max(2, k / 4), max(3, k / 2), max(4, 3 * k / 4), k]),
                "\(name): those you have been to, out of \(k).", family: "famous", counted: set != nil, from: "data")
        }
        add("every-month", "Every month", [2, 4, 6, 9, 12], "Months of the year you have gone somewhere in, by the months you gave.", family: "months")
        add("every-season", "Every season", [2, 3, 4], "Seasons you have gone somewhere in, as they are where you went.", family: "months")
        add("new-year-away", "New Year away", [1, 2, 3, 5, 10], "New Years spent away from home.", family: "months", counted: false, from: "trips")
        add("birthday-away", "Birthday away", [1, 2, 3, 5, 10], "Birthdays spent away from home.", family: "months", counted: false, from: "trips")
        add("two-winters", "Two winters in one year", [1, 2, 3, 5, 10], "Years with a winter each side of the equator.", family: "months", counted: false, from: "trips")
        add("highest-place", "Highest place", [2000, 3000, 4000, 5000, 8000], "The highest you are known to have been: a town you stamped, a peak, volcano or lake you marked, a high point you reached.", family: "extremes", unit: .metres)
        add("lowest-place", "Lowest place", [1, 50, 100, 200, 400], "The lowest you are known to have been below the sea: a town you stamped, a lake you marked.", family: "extremes", unit: .metres)
        add("furthest-north", "Furthest north", [500, 600, 666, 700, 780], "The furthest north you are sure you were.", family: "extremes", unit: .tenthDegrees)
        add("furthest-south", "Furthest south", [350, 450, 550, 600, 666], "The furthest south you are sure you were.", family: "extremes", unit: .tenthDegrees)
        add("four-hemispheres", "Four hemispheres", [2, 3, 4], "Quarters of the world you have been in, north or south and east or west.", family: "extremes")
        add("antipodes", "Antipodes", [1, 2, 3, 5, 10], "Pairs of your places on opposite sides of the Earth.", family: "extremes")
        add("continents-in-one-year", "Continents in one year", [2, 3, 4, 5, 6], "The most continents you went to in one year, by the months you gave.", family: "extremes")
        add("biggest-list", "Biggest list", [5, 10, 25, 50, 100], "Things in your biggest list.", family: "biggest")
        add("longest-plan", "Longest plan", [2, 4, 7, 14, 30], "Days in your longest plan.", family: "biggest")
        add("biggest-book", "Biggest book", [5, 10, 25, 50, 100], "Pages in your biggest photo book.", family: "biggest")
        return out
    }

    static let waits: [String: String] = ["zones": "data", "scripts": "data", "far": "home",
        "highpoints": "data", "sevensummits": "data", "stamps": "passport",
        "anniversary": "joined", "early": "joined", "borders": "tracking", "distance": "tracking", "nights": "tracking",
        "weekends": "tracking", "trains": "trips", "nighttrains": "trips", "metros": "trips", "ferries": "trips",
        "flights": "trips", "airports": "trips", "roadtrips": "trips", "hikes": "trips", "cycling": "trips",
        "trips": "trips", "longest": "trips", "solotrips": "trips", "shares": "later"]

    static let famous: [(String, Int)] = [("The New Seven Wonders", 7), ("The Ancient Wonders' sites", 7),
        ("The New Seven Wonders of Nature", 7), ("The eight-thousanders", 14), ("The Seven Second Summits", 7),
        ("The Volcanic Seven Summits", 7), ("The Alps' 4000ers", 82), ("The US national parks", 63), ("The Munros", 282),
        ("Japan's 100 famous mountains", 100), ("The Great Lakes", 5), ("The 10 biggest cities", 10),
        ("The 10 longest rivers", 10), ("The 10 largest lakes", 10), ("The 10 largest islands", 10),
        ("The 10 largest deserts", 10), ("The 10 highest waterfalls", 10)]

    static func possessive(_ n: String) -> String { n.hasSuffix("s") ? n + "'" : n + "'s" }
}

nonisolated struct BadgeTables: Decodable, Sendable {
    struct Zones: Decodable, Sendable {
        let zones: [Int]
        let town: Int
        let except: [String: Int]
    }
    struct Peak: Decodable, Sendable {
        let n: String
        let m: Double?
        let lat: Double
        let lon: Double
    }
    struct Member: Decodable, Sendable {
        let q: String?
        let qs: [String]?
        let n: String
        let lat: Double?
        let lon: Double?
        let r: Double?
        let gid: Int?
        let place: String?
        let cont: String?
        let shape: [[[Double]]]?
        let arctic: Bool?
    }
    struct Group: Decodable, Sendable {
        let id: String
        let n: String
        let by: String?
        let members: [Member]
    }
    struct Tripoint: Decodable, Sendable {
        let cc: [String]
        let p: [Double]
        let i: Int?
        var id: String { "tp:" + cc.joined(separator: "-") + ((i ?? 1) > 1 ? "-\(i!)" : "") }
    }
    let scripts: [String: String]
    let scriptNames: [String: String]
    let zones: [String: Zones]
    let highPoints: [String: Peak]
    let sets: [Group]
    let tripoints: [Tripoint]?
    let heights: [String: Int]?
}


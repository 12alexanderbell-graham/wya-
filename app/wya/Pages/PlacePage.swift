import SwiftUI
import simd

/// A PLACE'S PAGE (Part 16), first build: a country's page from the data server's country facts (D9 as it is on the
/// server: `country/<cc>.json`), any other place with what the app carries (16.2 "No page yet": the top, the marking
/// block, your record). It grows out of what opened it (A16.1: one rounded rectangle from the origin's frame to the
/// screen, its corners always rounded, nothing fading) under the head, and goes back into it by a drag down on its top.
@MainActor
@Observable
final class PlacePageState {
    static let shared = PlacePageState()
    struct Facts {
        var prose = ""
        var rows: [(String, String)] = []
        /// For you (16.4.9): the visa line for each of your nationalities first, then each government's advice
        var visa: [String] = []
        var advice: [(who: String, text: String, when: String)] = []
        /// What is in it (16.4.8): a country's regions (first level) and its cities, most peopled first
        var regions: [Inside] = []
        var cities: [Inside] = []
        /// Highlights (16.4.6): the country's World Heritage sites for now (the server's heritage list)
        var highlights: [Highlight] = []
        /// Activities (16.4.7): Wikivoyage's "see" and "do" listings, a town's sights first (a country's from all its cities
        /// in turn, a town's its own)
        var activities: [Activity] = []
        /// the page's photo (Wikimedia Commons), shown under the marking block
        var photo: String?
        /// the prose is a Wikivoyage article's opening (else Wikidata's description), for Sources
        var proseWikivoyage = false
    }
    struct Activity: Hashable { let name: String; let line: String }
    struct Highlight: Hashable { let id: String; let name: String; let line: String; let photo: String? }
    /// the server's World Heritage list, read once
    static var heritage: [String: [String: Any]]?
    struct Inside: Hashable { let key: PlaceKey; let name: String; let line: String; let code: String?; var at: SIMD2<Float>? = nil }
    /// ONE PAGE of the stack (16.2: a row or card on a page pushes its own page on top; closing it returns to this one)
    @MainActor
    @Observable
    final class OnePage: Identifiable {
        let key: PlaceKey
        let name: String
        /// one line of what it is ("City in Hessen, Germany"); empty for a country
        let what: String
        /// the country it is in (its flag and colours)
        let country: String
        /// a region's ISO 3166-2 code (its facts on the server are keyed by it)
        let code: String?
        /// what it grew from (closing goes back into it)
        let origin: CGRect
        var facts: Facts?
        /// a photo it came with (a highlight's), for a thing the data has no row for
        var photo: String?
        /// 0 at the origin to 1 full screen
        var p: CGFloat = 0
        var drag: CGFloat = 0
        /// on its way back into its origin (the stack is not "up" for the water once every page is)
        var closing = false
        /// a line that names the place itself again ("Town in Tokyo, Japan" under Tokyo) skips it: "Town in Japan"
        static func trim(_ what: String, _ name: String, country: String = "") -> String {
            for lead in ["Town in ", "City in "] where what.hasPrefix(lead) {
                var parts = what.dropFirst(lead.count).components(separatedBy: ", ")
                if parts[0].caseInsensitiveCompare(name) == .orderedSame {
                    // ("Town in Tokyo" under Tokyo: its region has its name; its country instead)
                    if parts.count > 1 { parts.removeFirst() }
                    else if let land = Locale(identifier: "en_GB").localizedString(forRegionCode: country.uppercased()) { parts = [land] }
                }
                // ("Town in Île-de-France" under Paris, 2.1 million: a place of 100,000 people and more is a city, as
                // the menu's own word for them; the towns' index says how many, once it is read)
                var word = lead
                if lead == "Town in ", (TownIndex.shared.townPeople()[country.lowercased() + "|"
                        + name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)] ?? 0) >= 100_000 { word = "City in " }
                return word + parts.joined(separator: ", ")
            }
            // (a thing's own line from its data starts lower case: "ancient Roman amphitheatre, ...")
            return what.prefix(1).uppercased() + what.dropFirst()
        }
        init(key: PlaceKey, name: String, what: String, country: String, code: String?, origin: CGRect) {
            self.key = key; self.name = name; self.what = Self.trim(what, name, country: country); self.country = country.lowercased(); self.code = code
            self.origin = origin
        }
        func load() {
            if key.kind == .country { Task { await loadCountry(key.id.lowercased()) } }
            if key.kind == .town { Task { await loadTown(country, id: key.id) } }
            if key.kind == .region, let code { Task { await loadRegion(country, code: code) } }
            if key.kind == .thing { loadThing() }
        }
    }
    private(set) var pages: [OnePage] = []
    /// the page on top (the one you see)
    var top: OnePage? { pages.last }
    var key: PlaceKey? { top?.key }
    var name: String { top?.name ?? "" }
    var country: String { top?.country ?? "" }
    var facts: Facts? { top?.facts }
    /// how far the first page has grown (the plus rolls into Share with it, and stays Share while pages are pushed)
    var p: CGFloat { pages.first?.p ?? 0 }
    /// the test driver's scroll to the end, and its opening of Sources (checks)
    var toEnd = 0
    var sourcesTest = 0
    /// the page's own sheet asked for (Sources tapped, 16.6): the water rises to 50% with it
    var sheetAsked = 0
    /// the test driver's way into Report a mistake (a reason picked, then Send)
    var reportTest = ""
    var sendTest = 0
    /// a reason the page's sheet opens on, at Report a mistake (a hold menu's Report a wrong place)
    var reportAsked: String?
    var isOpen: Bool { !pages.isEmpty }
    /// ONE SEARCH PER SCREEN: the head's field, open over a page, narrows the page's long lists (Activities, what is in
    /// it) to what it holds; empty when search is shut
    var filter = ""
    /// a page that stays: false from the moment the last one starts closing (its close animation still running)
    var standing: Bool { pages.contains { !$0.closing } }

    /// the first page, grown from what opened it on the map, the card or the list (A16.1)
    func open(_ key: PlaceKey, name: String, what: String = "", country: String, code: String? = nil, from origin: CGRect) {
        guard pages.isEmpty else { return }
        push(key, name: name, what: what, country: country, code: code, from: origin)
    }
    /// REPORT A WRONG PLACE (11.5's town or thing menu): the page opens as from Open its page, then its sheet rises at
    /// Report a mistake with Wrong place picked (16.6)
    func openReporting(_ key: PlaceKey, name: String, what: String = "", country: String, from origin: CGRect) {
        guard pages.isEmpty else { return }
        open(key, name: name, what: what, country: country, from: origin)
        reportAsked = "Wrong place"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.sheetAsked += 1 }
    }
    /// a page pushed on top of the one up, grown from the row or card tapped on it (16.7: "its page, pushed on top")
    func push(_ key: PlaceKey, name: String, what: String = "", country: String, code: String? = nil, from origin: CGRect,
              photo: String? = nil) {
        guard key != self.key else { return }
        let page = OnePage(key: key, name: name, what: what, country: country, code: code, origin: origin)
        page.photo = photo
        pages.append(page)
        Feel.tap()
        DispatchQueue.main.async {
            withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.5, dampingFraction: 1)) { page.p = 1 }
        }
        page.load()
    }
    /// the page on top goes back into what it grew from; the one under it is there as it was
    func close() {
        // the top page still standing (a quick second back closes the page under the one already going; it used to
        // land on the closing one and do nothing)
        guard let page = pages.last(where: { $0.p > 0.5 || $0.drag > 0 }) else { return }
        page.closing = true
        withAnimation(Motion.reduce ? Motion.tight : .spring(response: 0.42, dampingFraction: 1)) { page.p = 0; page.drag = 0 } completion: { [weak self] in
            guard let self, page.p < 0.01 else { return }
            self.pages.removeAll { $0 === page }
        }
    }
    /// every page closed at once (a search result picked, the tab left)
    func closeAll() {
        guard let first = pages.first else { return }
        pages = [first]
        close()
    }
    /// every page closed, back once they have gone (a link opening a page over one already up: `open` refuses while
    /// any is up, so the old page closed and the new one never came)
    func closeAllAndWait() async {
        closeAll()
        for _ in 0 ..< 20 where isOpen { try? await Task.sleep(for: .milliseconds(50)) }
    }
}

extension PlacePageState.OnePage {
    /// A THING'S PAGE (16.2 for things, D5 as it is): its photo, its own line as the prose, its kind and where it is
    fileprivate func loadThing() {
        guard let (cc, t) = ThingStore.shared.thing(key.id) else {
            // its country's things not read yet: once they are, or (a World Heritage site the data keeps as a whole) its
            // photo and kind from what opened it
            if ThingStore.shared.things(country) == nil {
                Task { @MainActor in
                    for _ in 0 ..< 60 where ThingStore.shared.things(country) == nil { try? await Task.sleep(for: .milliseconds(100)) }
                    if ThingStore.shared.thing(key.id) != nil { loadThing(); return }
                    seedOnly()
                }
            } else { seedOnly() }
            return
        }
        var out = PlacePageState.Facts()
        if !t.photo.isEmpty { out.photo = t.photo }
        // (its own line is already under its name; no prose repeating it)
        out.rows.append(("Kind", t.kindName.capitalized))
        let ll = EqualEarth.unproject(SIMD2(Double(t.at.x), Double(t.at.y)))
        // where it is in words (the nearest town and its country), the numbers only when no town is near; the towns'
        // index read first if it is not yet (it is read once, in the background)
        if !TownIndex.shared.ready {
            TownIndex.shared.load()
            Task { @MainActor in
                for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                if TownIndex.shared.ready, self.key.kind == .thing { self.loadThing() }
            }
        }
        let land = Locale(identifier: "en_GB").localizedString(forRegionCode: cc.uppercased()) ?? ""
        if let town = TownIndex.shared.nearest(lat: ll.lat, lon: ll.lon, km: 40) {
            out.rows.append(("Where", [town.name, land].filter { !$0.isEmpty && $0 != town.name }.joined(separator: ", ")))
        } else {
            out.rows.append(("Where", land.isEmpty ? String(format: "%.4f, %.4f", ll.lat, ll.lon) : land))
        }
        facts = out
    }
    private func seedOnly() {
        var out = PlacePageState.Facts()
        out.photo = photo
        facts = out
    }
    fileprivate func loadCountry(_ cc: String) async {
        // (the things' index: the checked spelling of an activity's name, F147)
        ThingIndex.shared.load()
        guard case .ok(let d) = await Servers.data.file("country/\(cc).json"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], key.id.lowercased() == cc else { return }
        let f = j["facts"] as? [String: Any] ?? [:]
        var out = PlacePageState.Facts()
        if let g = j["guide"] as? [String: Any], let intro = g["intro"] as? String { out.prose = PlacePageState.cut(PlacePageState.plain(intro), 620); out.proseWikivoyage = true }
        else if let desc = f["desc"] as? String { out.prose = desc.prefix(1).uppercased() + desc.dropFirst() + "." }
        // its photo (Wikidata's image of the country), at the top as every page's (12 Nov 14:10)
        if let img = (f["image"] as? [String])?.first ?? f["image"] as? String { out.photo = img }
        func s(_ k: String) -> String? {
            switch f[k] {
            case let v as String: return v
            // (each once: Germany's capital came as "Berlin, Berlin", the city and the state)
            case let v as [String]: var seen = Set<String>(); return v.filter { seen.insert($0).inserted }.prefix(3).joined(separator: ", ")
            case let v as NSNumber: return v.stringValue
            default: return nil
            }
        }
        if let v = s("capital") { out.rows.append(("Capital", v)) }
        if let v = f["population"] as? NSNumber { out.rows.append(("People", PlacePageState.big(v.doubleValue))) }
        if let v = PlacePageState.area(f["area"], cc: cc) { out.rows.append(("Area", v + " km²")) }
        if let z = PlacePageState.zones(f["timezone"], cc: cc) { out.rows.append(z) }
        if let c = f["currency"] as? [[String: Any]], let first = c.first {
            let n = (first["name"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            out.rows.append(("Currency", [n, (first["sym"] as? String).map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")))
        }
        if let v = s("officialLanguage") { out.rows.append(("Languages", v)) }
        if let v = s("drivingSide") { out.rows.append(("Driving side", v.capitalized)) }
        if let v = PlacePageState.plugs(f["plug"]) { out.rows.append(("Plugs", v)) }
        if let v = s("callingCode") { out.rows.append(("Calling code", v)) }
        if let e = f["emergency"] as? [String], let first = e.first { out.rows.append(("Emergency", first)) }
        // (the Netherlands here is the one in Europe, the Caribbean islands places of their own: Wikidata's highest point
        // is Mount Scenery, on Saba)
        if let v = cc == "nl" ? "Vaalserberg" : s("highestPoint") { out.rows.append(("Highest point", v)) }
        // each government's advice, with who says it and when it was checked
        let adv = j["advisories"] as? [String: Any] ?? [:]
        if let ca = adv["ca"] as? [String: Any], let t = ca["text"] as? String {
            out.advice.append(("Canada", t, PlacePageState.day(ca["updated"] as? String)))
        }
        if let us = adv["us"] as? [String: Any], let l = us["level"] as? String {
            out.advice.append(("United States", l.replacingOccurrences(of: #"^Level \d+: "#, with: "", options: .regularExpression),
                               PlacePageState.day(us["updated"] as? String)))
        }
        if let uk = adv["uk"] as? [String: Any], let a = uk["alert"] as? String, !a.isEmpty {
            let t = a.replacingOccurrences(of: "_", with: " ")
            out.advice.append(("United Kingdom", t.prefix(1).uppercased() + t.dropFirst(), PlacePageState.day(uk["updated"] as? String)))
        }
        // what is in it: the first level's regions (by people, from the server's regions where it has them) and the cities
        if let first = RegionCatalog.shared.first(cc), let file = await RegionCatalog.shared.fetch(cc, row: first.row) {
            var pop: [String: Double] = [:]
            if case .ok(let rd) = await Servers.data.file("regions/\(cc).json"),
               let all = try? JSONSerialization.jsonObject(with: rd) as? [String: Any] {
                for (k, v) in all { pop[k] = ((v as? [String: Any])?["pop"] as? NSNumber)?.doubleValue }
            }
            var seen = Set<String>()
            let word = RegionsMenuModel.word(first.level.one)
            out.regions = file.units.filter { seen.insert($0.id).inserted }
                .sorted { (pop[$0.code ?? ""] ?? 0) > (pop[$1.code ?? ""] ?? 0) }
                .map { u in PlacePageState.Inside(key: PlaceKey(.region, u.id), name: u.name,
                                   line: pop[u.code ?? ""].map { "\(word.prefix(1).uppercased() + word.dropFirst()) · \(PlacePageState.big($0)) people" }
                                       ?? word.prefix(1).uppercased() + word.dropFirst(),
                                   code: u.code) }
        }
        if case .ok(let cd) = await Servers.data.file("cities/\(cc).json"),
           let all = try? JSONSerialization.jsonObject(with: cd) as? [[String: Any]] {
            out.cities = all.compactMap { t in
                guard let n = t["n"] as? String, let gid = (t["gid"] as? NSNumber)?.intValue else { return nil }
                let r = t["r"] as? String ?? ""
                let ll = t["ll"] as? [NSNumber]
                return PlacePageState.Inside(key: PlaceKey(.town, "\(cc)/\(gid)"), name: n, line: r, code: nil,
                              at: ll.flatMap { $0.count == 2 ? EqualEarth.project(lon: $0[1].doubleValue, lat: $0[0].doubleValue) : nil })
            }
        }
        // highlights: the country's World Heritage sites (the list the server's country file names)
        if let ids = j["heritage"] as? [String], !ids.isEmpty {
            if PlacePageState.heritage == nil, case .ok(let hd) = await Servers.data.file("heritage.json"),
               let all = try? JSONSerialization.jsonObject(with: hd) as? [String: [String: Any]] { PlacePageState.heritage = all }
            // (the best known first, by the country's things' own order, as its activities are ranked: France's
            // opened on a fort listed in 2023, the newest first)
            var known: [String: Int] = [:]
            if case .ok(let td) = await Servers.data.file("native/things/things-\(cc)-3.wyth"),
               let rows = try? JSONSerialization.jsonObject(with: td) as? [[Any]] {
                for (i, r) in rows.enumerated() { if let q = r.first as? String, known[q] == nil { known[q] = i } }
            }
            let ranked = ids.enumerated().sorted { a, b in
                let x = known[a.element] ?? Int.max, y = known[b.element] ?? Int.max
                return x != y ? x < y : a.offset < b.offset
            }.map(\.element)
            out.highlights = ranked.compactMap { q in
                guard let h = PlacePageState.heritage?[q], let n = h["n"] as? String else { return nil }
                let year = h["year"] as? String
                return PlacePageState.Highlight(id: q, name: n, line: year.map { "World Heritage since \($0)" } ?? "World Heritage",
                                 photo: (h["img"] as? [String])?.first)
            }
        }
        // the guide's own main cities first (Rome, then Bologna ... for Italy), the rest after
        let mainCities = ((j["guide"] as? [String: Any])?["cities"] as? [[String: Any]])?.compactMap { $0["n"] as? String } ?? []
        out.activities = await PlacePageState.activities(cc, town: nil, first: mainCities)
        // (a page opened since this one began loading keeps its own facts)
        guard key.id.lowercased() == cc else { return }
        facts = out
        // the visa lines: for each of your nationalities (Profile), what its passport needs here
        let name = (f["name"] as? String) ?? (j["name"] as? String) ?? ""
        let nats = (UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []).filter { $0 != cc }
        var visa: [String] = []
        for n in nats {
            guard case .ok(let nd) = await Servers.data.file("country/\(n).json"),
                  let nj = try? JSONSerialization.jsonObject(with: nd) as? [String: Any],
                  let v = (nj["visaFromHere"] as? [String: Any])?[name] as? String else { continue }
            let who = ((nj["facts"] as? [String: Any])?["name"] as? String) ?? (nj["name"] as? String) ?? n.uppercased()
            visa.append(PlacePageState.visa(v) + "\n" + "With your passport from \(who)")
        }
        guard key.id.lowercased() == cc else { return }
        facts?.visa = visa
    }

    /// A TOWN'S FACTS (16.4.5: People, Height, Local time, Climate) from the server's cities (D9 as it is), by its
    /// GeoNames id
    fileprivate func loadTown(_ cc: String, id: String) async {
        // (a town with no GeoNames id is keyed by its name, "gb/London": found by it, the most peopled of that name;
        // London's and New York's pages had no facts at all)
        let last = String(id.split(separator: "/", maxSplits: 1).last ?? "")
        guard case .ok(let d) = await Servers.data.file("cities/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]],
              let t = Int(last).flatMap({ gid in all.first(where: { ($0["gid"] as? NSNumber)?.intValue == gid }) })
                ?? all.filter({ $0["gid"] == nil && $0["n"] as? String == last })
                      .max(by: { (($0["p"] as? NSNumber)?.intValue ?? 0) < (($1["p"] as? NSNumber)?.intValue ?? 0) }),
              key.id == id else { return }
        var out = PlacePageState.Facts()
        // (a capital says so first: Paris's page never said it is France's)
        if CollectionStore.shared.collection(CollectionStore.capitals)?.items.contains(where: { $0.key == key }) == true,
           let land = Locale(identifier: "en_GB").localizedString(forRegionCode: cc.uppercased()) { out.rows.append(("Capital of", land)) }
        if let p = t["p"] as? NSNumber, p.intValue > 0 { out.rows.append(("People", PlacePageState.big(p.doubleValue))) }
        if let e = t["ele"] as? NSNumber { out.rows.append(("Height", "\(e.intValue) m")) }
        if let z = t["tz"] as? String, let tz = TimeZone(identifier: z) {
            let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "HH:mm"
            out.rows.append(("Local time", f.string(from: Date())))
        }
        if let c = t["climate"] as? [String: Any], let hi = c["hi"] as? [NSNumber], let lo = c["lo"] as? [NSNumber], hi.count == 12, lo.count == 12 {
            out.rows.append(("Climate", "\(Int(hi[6].doubleValue.rounded()))° Jul · \(Int(lo[0].doubleValue.rounded()))° Jan"))
        }
        if let n = t["n"] as? String { out.activities = await PlacePageState.activities(cc, town: n) }
        // its photo (Wikidata's image of the place with this GeoNames id) and its opening words (its Wikivoyage
        // article's), as a country's page has them (12 Nov 14:10: every page the same)
        if let img = (t["img"] as? [String])?.first ?? t["img"] as? String { out.photo = img }
        if let n = t["n"] as? String, let ll = t["ll"] as? [NSNumber], ll.count == 2,
           let intro = await PlacePageState.guideIntro(cc, name: n, lat: ll[0].doubleValue, lon: ll[1].doubleValue) {
            out.prose = PlacePageState.cut(PlacePageState.plain(intro), 620); out.proseWikivoyage = true
        }
        guard key.id == id else { return }
        facts = out
    }

    /// A REGION'S FACTS (16.4.5: People, Area, Capital, its parent) from the server's regions (level 1, by ISO code)
    fileprivate func loadRegion(_ cc: String, code: String) async {
        guard case .ok(let d) = await Servers.data.file("regions/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = all[code] as? [String: Any], self.code == code else { return }
        var out = PlacePageState.Facts()
        if let desc = r["d"] as? String { out.prose = desc.prefix(1).uppercased() + desc.dropFirst() + "." }
        // its photo (Wikidata's) and, where Wikivoyage has an article for it, that article's opening words in place of the
        // one-line description (12 Nov 14:10: every page the same)
        if let img = (r["img"] as? [String])?.first { out.photo = img }
        if let n = r["n"] as? String, let ll = r["ll"] as? [NSNumber], ll.count == 2,
           let intro = await PlacePageState.guideIntro(cc, name: n, lat: ll[0].doubleValue, lon: ll[1].doubleValue, within: 150) {
            out.prose = PlacePageState.cut(PlacePageState.plain(intro), 620); out.proseWikivoyage = true
        }
        if let p = r["pop"] as? NSNumber { out.rows.append(("People", PlacePageState.big(p.doubleValue))) }
        if let a = r["area"] as? NSNumber { out.rows.append(("Area", PlacePageState.big(a.doubleValue) + " km²")) }
        if let c = r["cap"] as? String { out.rows.append(("Capital", c)) }
        facts = out
    }

}

extension PlacePageState {
    /// A PLACE'S OPENING WORDS: its own Wikivoyage article, found in the country's index by its title (the place's name,
    /// or its name with a bracket after it, "Albert (France)") and lying within `within` km of it (25 for a town, more for
    /// a region, whose point is its middle); the nearest if several. Nil when it has none, or the article has no intro.
    static func guideIntro(_ cc: String, name: String, lat: Double, lon: Double, within: Double = 25) async -> String? {
        func km(_ a: Double, _ b: Double) -> Double {
            let p = Double.pi / 180
            let x = (b - lon) * p * cos((a + lat) / 2 * p), y = (a - lat) * p
            return (x * x + y * y).squareRoot() * 6371
        }
        // (the United Kingdom's articles are filed by its four nations: London is in gb-eng)
        let files = cc == "gb" ? ["gb", "gb-eng", "gb-sct", "gb-wls", "gb-nir"] : [cc]
        var best: (file: String, key: String, km: Double)?
        for file in files {
            guard case .ok(let d) = await Servers.data.file("placeindex/\(file).json"),
                  let rows = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { continue }
            for r in rows where r.count >= 6 {
                guard let title = r[0] as? String, title == name || title.hasPrefix(name + " ("),
                      let a = (r[3] as? NSNumber)?.doubleValue, let b = (r[4] as? NSNumber)?.doubleValue, let key = r[5] as? String else { continue }
                let k = km(a, b)
                if k < within, k < (best?.km ?? .infinity) { best = (file, key, k) }
            }
        }
        guard let file = best?.file, let key = best?.key, case .ok(let pd) = await Servers.data.file("place/\(file)/\(key).json"),
              let j = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
              let intro = (j["g"] as? [String: Any])?["intro"] as? String, !intro.isEmpty else { return nil }
        return intro
    }

    /// THE ACTIVITIES (16.4.7), Wikivoyage's "see" and "do" listings as rows, the best known first. One rule for every
    /// town and every country (12 Nov: France's list opened with a scooter hire, New York's with a discount pass):
    /// - a big city's guide is split into districts ("Rome/Colosseo"): they are the city's own listings;
    /// - how well known a listing is comes from the country's things (ThingStore's file: fame 3 World Heritage or in 40+
    ///   Wikipedias, then 2, 1, 0), found by the listing's Wikidata id; a listing the guide links to Wikidata or Wikipedia
    ///   without being one of the things comes next; one with no link at all (a tour firm, a pass) last;
    /// - at each fame, sights before things to do; within a city, the things' own order (the most famous first);
    /// - a country's: one from each city in turn at each rank, the guide's main cities first. A guide that is not one
    ///   place (its listings lie more than 400 km apart: a region, an itinerary, a topic) comes after the towns and
    ///   does not put its title on its rows.
    static func activities(_ cc: String, town: String?, first: [String] = []) async -> [Activity] {
        guard case .ok(let d) = await Servers.data.file("listings/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: [[String: Any]]] else { return [] }
        // the country's things: Wikidata id -> (fame, place in the file)
        var fame: [String: (fame: Int, at: Int)] = [:]
        if case .ok(let td) = await Servers.data.file("native/things/things-\(cc)-3.wyth"),
           let rows = try? JSONSerialization.jsonObject(with: td) as? [[Any]] {
            for (i, r) in rows.enumerated() where r.count > 5 {
                if let q = r[0] as? String, let f = (r[5] as? NSNumber)?.intValue, fame[q] == nil { fame[q] = (f, i) }
            }
        }
        let city = { (k: String) in k.split(separator: "/", maxSplits: 1).first.map(String.init) ?? k }
        // each city's listings: its own article's first, then its districts' in their order
        var byCity: [String: [[String: Any]]] = [:]
        for k in all.keys.sorted(by: { ($0.contains("/") ? 1 : 0, $0) < ($1.contains("/") ? 1 : 0, $1) }) {
            byCity[city(k), default: []] += all[k] ?? []
        }
        // one place, or a guide to many (its listings more than 400 km apart)
        let wide = { (ls: [[String: Any]]) -> Bool in
            let pts = ls.compactMap { ($0["ll"] as? [NSNumber]).flatMap { $0.count == 2 ? ($0[0].doubleValue, $0[1].doubleValue) : nil } }
            guard pts.count > 1, let la0 = pts.map(\.0).min(), let la1 = pts.map(\.0).max(),
                  let lo0 = pts.map(\.1).min(), let lo1 = pts.map(\.1).max() else { return false }
            let ns = (la1 - la0) * 111, ew = (lo1 - lo0) * 111 * cos((la0 + la1) / 2 * .pi / 180)
            return max(ns, ew) > 400
        }
        let rest = byCity.keys.sorted().filter { !first.contains($0) }
        let wideOnes = town == nil ? Set(rest.filter { wide(byCity[$0] ?? []) }) : []
        let cities = town.map { [$0] } ?? (first.filter { byCity[$0] != nil } + rest.filter { !wideOnes.contains($0) } + rest.filter { wideOnes.contains($0) })
        var seen = Set<String>()
        // ranks[r][c]: city c's rows of rank r with their place in the things' file
        var ranks = [[[(at: Int, row: Activity)]]](repeating: [[(at: Int, row: Activity)]](repeating: [], count: cities.count), count: 10)
        for (ci, c) in cities.enumerated() {
            for l in byCity[c] ?? [] {
                guard let k = l["k"] as? String, k == "see" || k == "do", let n = l["n"] as? String else { continue }
                let q = l["wd"] as? String
                let name = Self.corrected(plain(n), wd: q)
                guard !name.isEmpty, !seen.contains(name.lowercased()), q.map({ !seen.contains($0) }) ?? true else { continue }
                seen.insert(name.lowercased())
                if let q { seen.insert(q) }
                let known = q.flatMap { fame[$0] }
                let r: Int
                if let known { r = (known.fame >= 3 ? 0 : known.fame == 2 ? 2 : 4) + (k == "see" ? 0 : 1) }
                else if q != nil || l["wp"] != nil { r = k == "see" ? 6 : 7 }
                else { r = k == "see" ? 8 : 9 }
                let desc = (l["d"] as? String).map { plain($0) } ?? ""
                let line = brief(town != nil || wideOnes.contains(c) ? desc : (desc.isEmpty ? c : "\(c) · \(desc)"), 112)
                ranks[r][ci].append((known?.at ?? Int.max, Activity(name: name, line: line)))
            }
        }
        var out: [Activity] = []
        for byCityRows in ranks {
            let lists = byCityRows.map { $0.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element.row) }
            // a town's: the rank whole; a country's: one from each city in turn (the first rows were all one city's)
            var i = 0
            while lists.contains(where: { i < $0.count }) {
                for list in lists where i < list.count { out.append(list[i]) }
                i += 1
            }
        }
        return out
    }

    /// "90" -> "visa free for 90 days"; the rest as they are written
    static func visa(_ v: String) -> String {
        if let d = Int(v) { return d < 0 ? "no entry" : "visa free for \(d) days" }
        return v.prefix(1).uppercased() + v.dropFirst()
    }
    /// a checked date as "21 Sep 2026" where it can be read, else as it is
    static func day(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        for f in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "EEE, dd MMM yyyy"] {
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = f
            if let d = df.date(from: String(s.prefix(f.count + 2)).trimmingCharacters(in: .whitespaces)) ?? df.date(from: s) {
                return d.formatted(.dateTime.day().month(.abbreviated).year())
            }
        }
        return s
    }

    /// the source's HTML entities as the characters they stand for
    /// THE SOURCE'S SPELLING CORRECTED, never simplified (F147, his data rule): Wikivoyage writes "Théatre" where the
    /// name is Théâtre. A name with a Wikidata id takes the label our things carry for it when the two differ only in
    /// accents and case (Wikidata's is the checked spelling); others go through the table of corrections made by hand
    static func corrected(_ name: String, wd: String?) -> String {
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        if let wd, let label = ThingIndex.shared.hit(wd)?.name, label != name, fold(label) == fold(name) { return label }
        var t = name
        for (wrong, right) in fixes where t.contains(wrong) { t = t.replacingOccurrences(of: wrong, with: right) }
        // a name the source began in small letters ("théâtre La Coupole") begins with its capital, as a name does;
        // never an article's elision ("l'Arc de Triomphe" is how the French write it)
        if let c = t.first, c.isLowercase, !t.hasPrefix("l'"), !t.hasPrefix("l\u{2019}"), !t.hasPrefix("d'") {
            t = c.uppercased() + t.dropFirst()
        }
        return t
    }
    /// our corrections over the source's text, word for word (added as they are found)
    static let fixes: [(String, String)] = [
        // (only whole spellings that are wrong wherever they appear: "Chateau Marmont" is that hotel's own name)
        ("Théatre", "Théâtre"),
    ]

    static func plain(_ s: String) -> String {
        var t = s
        // ("&amp;" first: the source writes some marks twice over, "&amp;ndash;", and Australia's page read)
        for (e, c) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
                       ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"), ("&hellip;", "\u{2026}"), ("&rsquo;", "\u{2019}"),
                       ("&lsquo;", "\u{2018}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"), ("&eacute;", "é")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        // numbered ones ("&#8212;", "&#x2014;")
        if t.contains("&#"), let re = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let r = Range(m.range, in: t), let hx = Range(m.range(at: 1), in: t), let num = Range(m.range(at: 2), in: t),
                      let v = UInt32(t[num], radix: t[hx].isEmpty ? 10 : 16), let u = Unicode.Scalar(v) else { continue }
                t.replaceSubrange(r, with: String(Character(u)))
            }
        }
        // editors' notes left in the source ("<!-- ... -->") are not text: taken out, and one left open runs to the end
        if t.contains("<!--") {
            t = t.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "(?s)<!--.*$", with: "", options: .regularExpression)
            t = t.trimmingCharacters(in: .whitespaces)
        }
        // what the source's dropped marks leave behind: an empty bracket ("Germany (German: ) is"), a picture's tail
        // ("|310x310px]]"), a bracket opening on a comma, a space before a comma
        if t.contains(" )") || t.contains("( ") || t.contains(" ,") || t.contains("px]]") {
            t = t.replacingOccurrences(of: "\\s*\\((?:\\p{Lu}[\\p{L} ]{1,24}:)?[\\s,;]*\\)", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\s*\\|?\\d+(?:x\\d+)?px\\]\\]", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\(\\s*,\\s*", with: "(", options: .regularExpression)
            t = t.replacingOccurrences(of: "(\\w) ,", with: "$1,", options: .regularExpression)
        }
        // a picture's or link's closing marks left with nothing before them ("]] Île-de-France is ..."), and a link's
        // opening ones with nothing after: never words
        if t.contains("]]") || t.contains("[[") {
            t = t.replacingOccurrences(of: "^[\\s\\]|]+", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\[\\[|\\]\\]", with: "", options: .regularExpression)
        }
        return t
    }

    /// up to n characters, cut at a whole sentence (16.4: prose)
    static func cut(_ s: String, _ n: Int) -> String {
        guard s.count > n else { return s }
        let head = String(s.prefix(n))
        if let r = head.range(of: ". ", options: .backwards) { return String(head[..<r.lowerBound]) + "." }
        return head
    }
    /// A ROW'S LINE CUT TO WHAT TWO LINES HOLD, AT A SENTENCE OR A WORD (the row cut it itself, in the middle of a
    /// word: "Staff assist if yo…"): whole sentences while they fit; a first sentence too long is cut at its last
    /// whole word, with the mark of more
    static func brief(_ s: String, _ n: Int) -> String {
        guard s.count > n else { return s }
        let head = String(s.prefix(n))
        if let r = head.range(of: ". ", options: .backwards), head.distance(from: head.startIndex, to: r.lowerBound) >= n / 3 {
            return String(head[..<r.lowerBound]) + "."
        }
        guard let sp = head.lastIndex(of: " ") else { return head }
        return String(head[..<sp]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:\u{2013}\u{2014}-(")) + "\u{2026}"
    }
    static func big(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1f billion", v / 1e9) }
        if v >= 1_000_000 { return String(format: "%.1f million", v / 1e6) }
        return Int(v).formatted()
    }
    /// A PLACE'S AREA as the page writes it. The server's figure is Wikidata's: where it gives several (Bosnia: 10,
    /// 51,187 and 51,209.2; the page read "10 km²") the largest is the place's. Two are another thing's and are
    /// given here: France's 643,801 is the Republic with its overseas regions, which are places of their own in the
    /// app (metropolitan France: 543,940, the land register's figure); Macau's 115.3 counts its sea (its land: 33.3 in
    /// 2024, the government's yearbook). Under 10 km² one decimal ("2.1", "0.5"; the Vatican read "0 km²").
    static func area(_ v: Any?, cc: String) -> String? {
        // (Norway without Svalbard and Jan Mayen, each a place of its own here: the Nordic Council's figure; the
        // Netherlands in Europe with its lakes and rivers, without the sea: Wikidata's gave its waters too)
        let own: [String: Double] = ["fr": 543_940, "mo": 33.3, "no": 323_781, "nl": 41_543]
        let all = (v as? [NSNumber])?.map(\.doubleValue) ?? (v as? NSNumber).map { [$0.doubleValue] } ?? []
        guard let a = own[cc] ?? all.max(), a > 0 else { return nil }
        return a < 10 ? String(format: "%.1f", a) : big(a)
    }
    /// THE TIME ZONES ROW: offsets only ("UTC+01:00"), each once, in order; more than three as a span. A place's
    /// zones are the time zone database's own for it (zone.tab, bundled as place-zones.json: 247
    /// places, 417 zones; public domain), each as its clock stands now, so the row is right through summer time and
    /// when a country changes its clocks. The server's list is Wikidata's and was wrong where it mattered most: Russia
    /// read "UTC+02:00", Australia "UTC+10:00", the United States, India and Chile nothing, Bosnia its winter and
    /// summer offsets as two zones. It answers only for a place
    /// the database does not list (Kosovo, the parts of the United Kingdom): where that place's own zones are named
    /// by id, theirs; else the offsets written.
    private static let placeZones: [String: [String]] = {
        guard let u = Bundle.main.url(forResource: "place-zones", withExtension: "json"), let d = try? Data(contentsOf: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: [String]] else { return [:] }
        return j
    }()
    static func zones(_ raw: Any?, cc: String) -> (String, String)? {
        func text(_ m: Int) -> String { String(format: "UTC%@%02d:%02d", m < 0 ? "-" : "+", abs(m) / 60, abs(m) % 60) }
        func minutes(_ s: String) -> Int? {
            guard s.hasPrefix("UTC") else { return nil }
            let rest = s.dropFirst(3)
            guard let sign = rest.first else { return 0 }
            let n = rest.dropFirst().split(separator: ":").compactMap { Int($0) }
            guard let h = n.first else { return nil }
            let m = h * 60 + (n.count > 1 ? n[1] : 0)
            return sign == "-" || sign == "\u{2212}" ? -m : m
        }
        let every = (raw as? [String]) ?? (raw as? String).map { [$0] } ?? []
        let known = (placeZones[cc] ?? []).compactMap { TimeZone(identifier: $0) }
        let own = known.isEmpty ? every.filter { $0.contains("/") }.compactMap { TimeZone(identifier: $0) } : known
        let named = Set(own.map { $0.secondsFromGMT() / 60 })
        let m = (named.isEmpty ? Set(every.compactMap(minutes)) : named).sorted()
        guard let first = m.first, let last = m.last else {
            // (words only, for a place the database does not list: the words)
            return every.isEmpty ? nil : (every.count == 1 ? "Time zone" : "Time zones", every.prefix(3).joined(separator: ", "))
        }
        if m.count == 1 { return ("Time zone", text(first)) }
        return ("Time zones", m.count <= 3 ? m.map(text).joined(separator: ", ") : "\(text(first)) to \(text(last))")
    }
    /// THE PLUGS BY THEIR LETTERS ("Type C, E, F"), as travellers and adapters name them. The server's words are
    /// Wikidata's labels, a mix of trade names and standards ( on Monaco's page). The British family's label alone
    /// is the old round-pin D (Monaco,
    /// Senegal, Madagascar, Chad: C, D, E ... in the published lists); beside a British standard of its own it adds
    /// nothing.
    static func plugs(_ v: Any?) -> String? {
        let names = (v as? [String]) ?? (v as? String).map { [$0] } ?? []
        let british = names.contains("BS 1363") || names.contains("BS 546")
        var letters = Set<String>()
        for n in names {
            switch n {
            case "NEMA 1-15": letters.insert("A")
            case "NEMA 5-15": letters.insert("B")
            case "Europlug": letters.insert("C")
            case "BS 546": letters.insert("D")
            case "Schuko": letters.insert("F")
            case "BS 1363": letters.insert("G")
            case "AS/NZS 3112": letters.insert("I")
            case "SN 441011": letters.insert("J")
            case "IEC 60906-1": letters.insert("N")
            case "AC power plugs and sockets: British and related types": if !british { letters.insert("D") }
            default: if n.hasPrefix("Type "), n.count == 6, let l = n.last { letters.insert(String(l)) }
            }
        }
        return letters.isEmpty ? nil : "Type " + letters.sorted().joined(separator: ", ")
    }
}

/// THE PAGE (16.3, 16.4)
struct PlacePageView: View {
    let map: MapController
    let water: Water
    @State private var stack = PlacePageState.shared
    /// the water's stop before the page came (it goes back there when the page closes)
    @State private var before: Water.Stop?

    var body: some View {
        // every page of the stack, the top one last (the ones under it stay as they were, scrolled where they were)
        ZStack {
            ForEach(stack.pages) { page in
                PageLayer(map: map, water: water, page: page, top: page === stack.top)
            }
        }
        // (from the moment the last page starts closing, not once it has gone: what closed it may move the water
        // itself, a search pick or the Map tab, and the page's stop must not undo that)
        .onChange(of: stack.standing) { _, open in
            water.pageUp = open
            if open { before = water.stop; water.go(.closed) }
            else {
                let sheet = water.pageSheet
                water.pageSheet = false
                // back to where it was only if nothing else has moved the water since (the page put it at the capsule,
                // or its own sheet had it at 50%)
                if let b = before, water.stop == .closed || sheet { water.go(b) }
                before = nil
            }
        }
        // THE PAGE'S OWN SHEET (16.6): the water pulled up from the tab capsule, or Sources tapped, comes to 50% holding
        // the page's sheet; back down to the capsule, the sheet goes
        .onChange(of: water.stop) { _, s in
            guard stack.standing else { return }
            if s == .closed { water.pageSheet = false; return }
            if !water.pageSheet { water.pageSheet = true }
            if s == .quarter { water.go(.half) }
        }
        .onChange(of: stack.sheetAsked) { _, _ in
            guard stack.standing else { return }
            water.pageSheet = true
            water.go(.half)
        }
    }
}

/// ONE PAGE of the stack, grown from its origin
private struct PageLayer: View {
    let map: MapController
    let water: Water
    let page: PlacePageState.OnePage
    let top: Bool
    @State private var ground: [Color] = []
    @GestureState private var headerLive = false
    /// where the long lists start in the page (the head's search takes the page there), and the scroll's place
    @State private var listsY: CGFloat?
    @State private var spot = ScrollPosition(edge: .top)

    var body: some View { pageBody }

    @ViewBuilder private var pageBody: some View {
        let L = water.layout
        do {
            let key = page.key
            let full = CGRect(x: 0, y: 0, width: L.W, height: L.H)
            let p = page.p * (1 - min(0.6, page.drag / (L.H * 1.2)))
            let r = CGRect(x: page.origin.minX + (full.minX - page.origin.minX) * p,
                           y: page.origin.minY + (full.minY - page.origin.minY) * p + page.drag * 0.5,
                           width: page.origin.width + (full.width - page.origin.width) * p,
                           height: page.origin.height + (full.height - page.origin.height) * p)
            // (at full, the screen's own corner: a fixed 55 left triangles of map at the corners of phones rounded less)
            let corner = min(page.origin.height / 2, 22) + (L.screenCorner - min(page.origin.height / 2, 22)) * p
            // (31 Oct 03:07: opening and leaving "strange"; the way Apple's zoom does it) what is under the page dims a
            // little as it grows, and the page itself fades over its first and last stretch, so it never lands as a small
            // card on the map where it opened from (the camera may have moved since)
            Color.black.opacity(0.12 * Double(p))
                .frame(width: L.W, height: L.H)
                .allowsHitTesting(false)
            content(key, L: L)
                .frame(width: L.W, height: L.H)
                // one scale for both sides (the way Apple's zoom grows a view): the page is never squeezed or stretched on
                // the way; the rounded rectangle growing from what opened it shows as much of it as fits (31 Oct 03:07)
                .scaleEffect(r.width / L.W, anchor: .topLeading)
                .offset(x: r.minX, y: r.minY)
                .frame(width: L.W, height: L.H, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous).offset(x: r.minX, y: r.minY).size(r.size))
                .opacity(min(1, Double(p) / 0.3))
                .allowsHitTesting(top && page.p > 0.98)
                .onAppear { ground = Self.colours(page.country) }
                .onChange(of: page.country) { _, c in ground = Self.colours(c) }
        }
    }


    @ViewBuilder private func content(_ key: PlaceKey, L: Layout) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(spacing: 32) {
                top(key, L: L)
                marking(key)
                // a thing's photo (Commons; credited in Sources), the content's width, 4:3, corners 22
                if let f = page.facts, let ph = f.photo, let u = Self.commons(ph, width: 1200) {
                    Color.clear
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .overlay { PagePhoto(url: u) }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                if let f = page.facts, !f.prose.isEmpty {
                    Text(f.prose).font(.body).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let f = page.facts, !f.rows.isEmpty { factsGrid(f.rows) }
                if let f = page.facts, !f.highlights.isEmpty { highlights(f.highlights, L: L).id("highlights") }
                // ("lists": where the head's search takes the page, the first of its long lists)
                // (where the first long list starts: the head's search brings its title under the field)
                if let f = page.facts, !f.activities.isEmpty {
                    ActivitiesList(all: f.activities)
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("page")).minY }) { listsY = $0 }
                }
                if let f = page.facts, !f.regions.isEmpty {
                    insideList("Regions", f.regions)
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("page")).minY }) { y in
                            if f.activities.isEmpty { listsY = y }
                        }
                }
                if let f = page.facts, !f.cities.isEmpty { insideList("Cities", f.cities) }
                // (Suggestions stays away until it has something in it: a title over nothing was useless words, 12 Nov)
                if MarkStore.shared.state(key).stamped { record(key) }
                if page.facts != nil { SourcesRow(facts: page.facts!, kind: key.kind) }
                Color.clear.frame(height: 140).id("end")
            }
            .padding(.horizontal, 16)
            .coordinateSpace(.named("page"))
            // the ground scrolls with the page (one layer behind the whole scroll, 16.3)
            .background(alignment: .top) { groundView(L: L) }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($spot)
        // the one blur under the head, only once words scroll under it (16.3)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // and at the bottom, under the tabs' capsule, so a row there fades instead of being cut by it
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // (the system's edge never reached it here: the page is laid out over the whole screen) the page's own white
        // coming up under the capsule, so rows fade into it and are never cut by its edge
        .overlay(alignment: .bottom) {
            LinearGradient(stops: [.init(color: Palette.white.opacity(0), location: 0), .init(color: Palette.white.opacity(0.85), location: 0.45),
                                   .init(color: Palette.white, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: L.H - L.capsule.minY + 28)
                .allowsHitTesting(false)
        }
        .onChange(of: PlacePageState.shared.toEnd) { _, n in reader.scrollTo(n == 1 ? "highlights" : "end", anchor: .top) }
        // what is typed in the head's field narrows the long lists: the page goes to them as the first letter comes
        // (they were under the photo and the prose, out of sight, while they changed)
        .onChange(of: PlacePageState.shared.filter.isEmpty) { _, empty in
            guard top, !empty, let y = listsY else { return }
            // (the list's title 130 pt down, under the head's field)
            withAnimation(Motion.chrome) { spot.scrollTo(y: max(0, y - 130)) }
        }
        // THE TABS DRAW IN as the page goes down (past its top), and open again as it comes back up (F141; Apple's
        // minimising tab bar)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
            guard top else { return }
            let want: CGFloat = new > 60 && new > old + 2 ? 1 : (new < old - 6 || new <= 60) ? 0 : water.mini
            if want != water.mini { withAnimation(Motion.chrome) { water.mini = want } }
        }
        .onDisappear { if top, water.mini != 0 { withAnimation(Motion.chrome) { water.mini = 0 } } }
        }
        .background(Palette.white)
    }

    /// THE TOP (16.4.1): a country's flag (4:3, 64 pt tall) centred 24 pt under the head's foot, its name under it; any
    /// other place its country's flag small and its line of what it is. Pulling it down closes the page (A16.1)
    private func top(_ key: PlaceKey, L: Layout) -> some View {
        VStack(spacing: 12) {
            if key.kind == .country, let f = Flags.wide(page.country) {
                f.resizable().aspectRatio(4 / 3, contentMode: .fit).frame(height: 64)
            } else if let f = Flags.square(page.country) {
                f.resizable().frame(width: 29, height: 29)
            }
            Text(page.name).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                // THE NAME'S HOLD MENU (16.7), the same actions as the page's sheet: Show in passport (a stamped country),
                // Share (Its book and Add to a list wait for the books and Lists)
                .contextMenu {
                    Section(page.name) {
                        if key.kind == .country, MarkStore.shared.state(key).stamped {
                            Button("Show in passport") {
                                PlacePageState.shared.closeAll()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { BookState.shared.open(showing: key.id) }
                            }
                        }
                        if let u = URL(string: "wya://page/\(key.description)") {
                            ShareLink(item: u, subject: Text(page.name), message: Text(page.name)) { Text("Share") }
                        }
                    }
                }
            if !page.what.isEmpty {
                Text(page.what).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, L.headBottom + 24)
        .contentShape(Rectangle())
        // (in the screen's space: the header moves and shrinks with the drag, so measured in its own space the page
        // followed at two thirds of the finger and shook, 8 Nov; a cancelled drag springs the page back)
        .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($headerLive) { _, live, _ in live = true }
            .onChanged { v in page.drag = max(0, v.translation.height) }
            .onEnded { v in
                if v.translation.height > 120 || v.predictedEndTranslation.height > 260 { PlacePageState.shared.close() }
                else { withAnimation(.spring(response: 0.42, dampingFraction: 1)) { page.drag = 0 } }
            })
        .onChange(of: headerLive) { _, live in
            if !live, page.drag > 0, page.p > 0.5 { withAnimation(.spring(response: 0.42, dampingFraction: 1)) { page.drag = 0 } }
        }
    }

    /// THE MARKING BLOCK (16.4.2): the stamping card's own buttons
    private func marking(_ key: PlaceKey) -> some View {
        let s = MarkStore.shared.state(key)
        return HStack(spacing: 12) {
            Button {
                Task {
                    if s.stamped { Feel.lift(); await MarkStore.shared.unstamp(key, name: page.name) }
                    else { Feel.stamp(); await MarkStore.shared.stamp(key, name: page.name) }
                }
            } label: {
                Text(s.stamped ? "Stamped" : "Stamp").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .glassEffect(s.stamped ? PageGlass.control.tint(Palette.lime) : PageGlass.control, in: .capsule)
            }
            Button {
                guard !s.stamped else { Feel.refuse(); return }
                Feel.tap()
                Task {
                    if s.wished { await MarkStore.shared.unwish(key, name: page.name) }
                    else { await MarkStore.shared.wish(key, name: page.name) }
                }
            } label: {
                Text("Wishlist").font(.body.weight(.semibold)).foregroundStyle(Palette.ink.opacity(s.stamped ? 0.5 : 1)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .glassEffect(s.wished ? PageGlass.control.tint(Palette.blue) : PageGlass.control, in: .capsule)
            }
        }
        .buttonStyle(.plain)
    }

    /// HIGHLIGHTS (16.4.6): a sideways row, one card wide with the next peeking 24 pt; the photo fills the card's top
    /// (square corners, 16:10; real photos from Wikimedia Commons, credited in Sources), its name 17 pt semibold and one
    /// line 15 pt black 50% under it; the plus at the photo's top right wishes it
    private func highlights(_ all: [PlacePageState.Highlight], L: Layout) -> some View {
        let w = L.W - 32 - 24
        return VStack(alignment: .leading, spacing: 12) {
            Text("Highlights").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(all, id: \.self) { h in highlightCard(h, w: w) }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
    private func highlightCard(_ h: PlacePageState.Highlight, w: CGFloat) -> some View {
        // (its key as a thing's: `m:wd:Q…`, the same mark as the thing on the map)
        let key = PlaceKey(.thing, "wd:" + h.id)
        let st = MarkStore.shared.state(key)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let f = h.photo, let u = Self.commons(f, width: 800) {
                        PagePhoto(url: u)
                    } else { Palette.cream }
                }
                .frame(width: w, height: w * 10 / 16)
                // (the page's photo corner, as a thing's page: these were cut square)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button {
                    Feel.tap()
                    Task {
                        if st.wished { await MarkStore.shared.unwish(key, name: h.name) }
                        else { await MarkStore.shared.wish(key, name: h.name, cc: page.country) }
                    }
                } label: {
                    Icon5(key: "plus", ink: Palette.ink, size: 22)
                        .frame(width: 44, height: 44)
                        .glassEffect(st.wished ? PageGlass.control.tint(Palette.blue) : PageGlass.control, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(st.wished ? "Remove \(h.name) from your wishlist" : "Add \(h.name) to your wishlist")
                .padding(8)
            }
            Text(h.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            Text(h.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .frame(width: w, alignment: .leading)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [cardFrames] f in cardFrames.at[h.id] = f }
        // its page, pushed on top, growing out of the card (16.7)
        .onTapGesture {
            ThingStore.shared.load(page.country)
            PlacePageState.shared.push(key, name: h.name, what: h.line, country: page.country,
                                       from: cardFrames.at[h.id] ?? .zero, photo: h.photo)
        }
    }
    /// each highlight card's frame on screen (a plain box: scrolling redraws nothing)
    @State private var cardFrames = CardFrames()
    final class CardFrames { var at: [String: CGRect] = [:] }
    /// a Commons file at a width (Special:FilePath)
    static func commons(_ file: String, width: Int) -> URL? {
        let name = file.replacingOccurrences(of: " ", with: "_")
        guard let e = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/\(e)?width=\(width)")
    }

    /// WHAT IS IN IT (16.4.8): a list with its own search field, five rows (the most peopled), then Show more; a row is a
    /// flag, its name and one line; its plus stamps it; a tap opens its page
    private func insideList(_ title: String, _ all: [PlacePageState.Inside]) -> some View {
        InsideList(title: title, all: all, country: page.country, countryName: page.key.kind == .country ? page.name : (map.world?.placeIndex[page.country].map { map.world!.places[$0].n } ?? ""), map: map)
    }

    /// YOUR RECORD (16.4.10, only when stamped): big numbers in the Profile's style (64 pt rounded over 15 pt labels):
    /// the times; on a country its regions ("12 of 16") and cities. The month waits for the visits' dates (Part 9.9)
    private func record(_ key: PlaceKey) -> some View {
        let st = MarkStore.shared.state(key)
        var items: [(String, String)] = []
        if st.visits > 0 { items.append(("\(st.visits)", st.visits == 1 ? "time" : "times")) }
        if key.kind == .country, let f = page.facts {
            if !f.regions.isEmpty {
                let n = f.regions.filter { MarkStore.shared.state($0.key).stamped }.count
                items.append(("\(n)", "of \(f.regions.count) regions"))
            }
            let cc = page.country + "/"
            let towns = MarkStore.shared.marks.filter { $0.key.kind == .town && $0.value.stamped && $0.key.id.hasPrefix(cc) }.count
            items.append(("\(towns)", towns == 1 ? "city" : "cities"))
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your record").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    VStack(spacing: 0) {
                        Text(it.0).font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Palette.ink).contentTransition(.numericText())
                        Text(it.1).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// SUGGESTIONS (16.4.9, renamed): only its title and what it will be made from, nothing
    /// in it yet: the suggestions come with Profile and the AI. The visa and advice data
    /// stay in Facts for then.
    private func suggestions() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggestions").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            Text("Based on your passport and history").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// FACTS (16.4.5): two columns, each value 17 pt semibold over its label 15 pt black 50%, a thin line between rows
    private func factsGrid(_ rows: [(String, String)]) -> some View {
        let pairs = stride(from: 0, to: rows.count, by: 2).map { (rows[$0], $0 + 1 < rows.count ? rows[$0 + 1] : nil) }
        return VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { n, pair in
                if n > 0 { Rectangle().fill(Palette.ink.opacity(0.5)).frame(height: 0.5) }
                HStack(alignment: .top, spacing: 16) {
                    fact(pair.0)
                    if let b = pair.1 { fact(b) } else { Color.clear.frame(maxWidth: .infinity) }
                }
                .padding(.vertical, 12)
            }
        }
    }
    private func fact(_ f: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(f.1).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            Text(f.0).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // A FACT HELD (11.5): Copy (its value) · Report a mistake (the page's sheet at Report a mistake, Wrong
        // number picked, 16.6)
        .contextMenu {
            Section(f.0) {
                Button("Copy") { UIPasteboard.general.string = f.1 }
                Button("Report a mistake") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        PlacePageState.shared.reportAsked = "Wrong number"
                        PlacePageState.shared.sheetAsked += 1
                    }
                }
            }
        }
    }

    /// THE GROUND (16.3): the flag's colours, each the nearest of the palette's, strong at the top and gentle further
    /// down, one layer behind the whole top
    private func groundView(L: Layout) -> some View {
        let c = ground.isEmpty ? [Palette.cream] : ground
        let top = c[0].opacity(0.85)
        // the ground goes on above the page's top in its strongest colour, so pulling the page down past its top shows
        // more of the same ground, never white
        return VStack(spacing: 0) {
            Rectangle().fill(top).frame(height: L.H)
            LinearGradient(stops: [
                .init(color: top, location: 0),
                .init(color: (c.count > 1 ? c[1] : c[0]).opacity(0.45), location: 0.35),
                .init(color: (c.count > 2 ? c[2] : c[0]).opacity(0.12), location: 0.7),
                .init(color: Palette.white.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: L.H * 0.75)
        }
        .offset(y: -L.H)
        .allowsHitTesting(false)
    }

    /// a flag's colours: drawn small, each pixel the nearest of the twelve, the commonest first (white and ink left
    /// out where others exist, so the ground is the flag's own colour)
    static func colours(_ id: String) -> [Color] {
        let entries = Array(Palette.named)
        let names: [(Color, SIMD3<Double>)] = entries.map { (Color(red: $0.value.x, green: $0.value.y, blue: $0.value.z), $0.value) }
        guard let ui = Flags.wideImage(id), let cg = ui.cgImage else { return [] }
        let w = 16, h = 12
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var count = [Int](repeating: 0, count: names.count)
        for i in 0 ..< w * h {
            let c = SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) / 255
            var best = 0, bd = Double.infinity
            for (n, v) in names.enumerated() { let d = simd_length_squared(v.1 - c); if d < bd { bd = d; best = n } }
            count[best] += 1
        }
        let order = count.indices.filter { count[$0] > 0 }.sorted { count[$0] > count[$1] }
        let plain: Set<String> = ["white", "ink", "cream"]
        let coloured = order.filter { !plain.contains(entries[$0].key) }
        let use = coloured.isEmpty ? order : coloured
        return use.prefix(3).map { names[$0].0 }
    }
}

/// one of a page's "What is in it" lists (16.4.8)
private struct InsideList: View {
    let title: String
    let all: [PlacePageState.Inside]
    let country: String
    let countryName: String
    let map: MapController
    @State private var shown = 5
    /// each row's frame on screen (the page it pushes grows out of it); a plain box, so scrolling redraws nothing
    @State private var frames = Frames()
    final class Frames { var at: [PlaceKey: CGRect] = [:] }

    var body: some View {
        // (searched by the head's field, one search per screen: typing shows every row that matches)
        let q = PlacePageState.shared.filter.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let rows = q.isEmpty ? all : all.filter { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
        let limit = q.isEmpty ? shown : rows.count
        // (a list with nothing that matches goes while searching)
        if q.isEmpty || !rows.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            ForEach(rows.prefix(limit), id: \.self) { r in row(r) }
            if rows.count > limit {
                Button { shown += 10 } label: {  // (the next rows are simply there, no fade, 8 Nov)
                    Text("Show more").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        }
    }

    private func row(_ r: PlacePageState.Inside) -> some View {
        let s = MarkStore.shared.state(r.key)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                // (a long commune, "Saint-Remy-en-Bouzemont-...", gets a little smaller before it is ever cut)
                Text(r.name).font(.body).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                if !r.line.isEmpty { Text(r.line).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.8) }
            }
            Spacer(minLength: 8)
            Button {
                Task {
                    if r.key.kind == .town {
                        // a town with its region chain and its country (A16.7, the unstamp rule)
                        if s.stamped { Feel.lift(); await TownStamps.unstamp(r.key, name: r.name, cc: country) }
                        else {
                            Feel.stamp()
                            await TownStamps.stamp(r.key, name: r.name, cc: country, source: .hand,
                                                   place: map.world?.placeIndex[country], at: r.at)
                        }
                    } else if s.stamped { Feel.lift(); await MarkStore.shared.unstamp(r.key, name: r.name) }
                    else { Feel.stamp(); await MarkStore.shared.stamp(r.key, name: r.name, cc: country) }
                }
            } label: {
                // the plus; stamped, the card's own "Stamped" capsule (no tick, 0.8.4; no lone lime circle, 30 Oct 21:42)
                if s.stamped {
                    Text("Stamped").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).frame(height: 44)
                        .glassEffect(PageGlass.control.tint(Palette.lime), in: .capsule)
                } else {
                    Icon5(key: "plus", ink: Palette.ink, size: 22)
                        .frame(width: 44, height: 44)
                        .glassEffect(PageGlass.control, in: .circle)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.stamped ? "Take the stamp off \(r.name)" : "Stamp \(r.name)")
        }
        .frame(height: 52)
        // the 52 pt rows hold their two lines up to the largest standard size
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [frames] f in frames.at[r.key] = f }
        .onTapGesture {
            // its page, pushed on top, growing out of this row (16.7); closing it goes back into the row
            let page = PlacePageState.shared
            page.push(r.key, name: r.name, what: r.key.kind == .town ? "Town in \(r.line), \(countryName)" : "\(r.line.components(separatedBy: " · ").first ?? "Region") of \(countryName)",
                         country: country, code: r.code, from: frames.at[r.key] ?? .zero)
        }
    }
}

/// SOURCES (16.4.11, 16.6): a row "Sources" at the page's foot; a tap raises the page's own sheet (16.6) to 50%, which
/// lists the sources the page drew on: Wikivoyage's text (CC BY-SA), Wikidata's and GeoNames' facts, each photo with
/// its author and licence from the server's Commons credits, and the governments whose advice is shown. (The visa
/// rules' and the climate figures' own sources are not recorded in the server's data yet, so they are not named.)
struct SourcesRow: View {
    let facts: PlacePageState.Facts
    let kind: PlaceKey.Kind

    var body: some View {
        Button {
            Feel.tap()
            PlacePageState.shared.sheetAsked += 1
        } label: {
            Text("Sources").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: PlacePageState.shared.sourcesTest) { _, _ in PlacePageState.shared.sheetAsked += 1 }
    }

    /// the page's sources as (what, who and the licence) pairs, in the page's order
    static func lines(_ facts: PlacePageState.Facts, kind: PlaceKey.Kind, credits: [String: String], id: String = "") -> [(String, String)] {
        var out: [(String, String)] = []
        if facts.proseWikivoyage, !facts.prose.isEmpty { out.append(("Text", "Wikivoyage, CC BY-SA")) }
        else if !facts.prose.isEmpty { out.append(("Text", kind == .thing ? "Wikidata, CC0" : "Wikidata")) }
        if let f = facts.photo { out.append(("Photo", (credits[f] ?? f) + ", Wikimedia Commons")) }
        if !facts.rows.isEmpty { out.append(("Facts", kind == .town ? "GeoNames, CC BY 4.0" : kind == .thing ? "Wikidata, CC0" : "Wikidata")) }
        for h in facts.highlights {
            guard let f = h.photo else { continue }
            out.append(("Photo of \(h.name)", (credits[f] ?? f) + ", Wikimedia Commons"))
        }
        if !facts.activities.isEmpty { out.append(("Activities", "Wikivoyage, CC BY-SA")) }
        // (where the page has its regions: the places whose regions, or outline, are geoBoundaries' (gbOpen, CC BY 4.0))
        let cc = id.lowercased()
        if kind == .country, ["sm", "li", "ad", "to", "tv", "fm", "gm"].contains(cc) { out.append(("Regions", "geoBoundaries, CC BY 4.0")) }
        if kind == .country, cc == "va" { out.append(("Outline", "geoBoundaries, CC BY 4.0")) }
        for a in facts.advice { out.append(("Advice", "The \(a.who) government")) }
        return out
    }

    /// each photo's author and licence from the server's credits (256 shards by the FNV-1a of the file name)
    static func credits(_ facts: PlacePageState.Facts) async -> [String: String] {
        var out: [String: String] = [:]
        var shards: [String: [String: Any]] = [:]
        for f in facts.highlights.compactMap(\.photo) + (facts.photo.map { [$0] } ?? []) {
            let sh = Self.shard(f)
            if shards[sh] == nil, case .ok(let d) = await Servers.data.file("credits/\(sh).json"),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { shards[sh] = j }
            if let c = shards[sh]?[f] as? [String: Any] {
                out[f] = [c["by"] as? String, c["lic"] as? String].compactMap { $0 }.joined(separator: ", ")
            }
        }
        // the rest (the World Heritage photos are not in the server's credits) from Commons itself: each file's author and
        // licence short name, in one request
        let missing = (facts.highlights.compactMap(\.photo) + (facts.photo.map { [$0] } ?? [])).filter { out[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 50) {
            let batch = Array(missing[start ..< min(missing.count, start + 50)])
            var c = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
            c.queryItems = [.init(name: "action", value: "query"), .init(name: "format", value: "json"),
                            .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "extmetadata"),
                            .init(name: "titles", value: batch.map { "File:" + $0 }.joined(separator: "|"))]
            guard let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let pages = (j["query"] as? [String: Any])?["pages"] as? [String: Any] else { continue }
            for case let pg as [String: Any] in pages.values {
                guard let title = pg["title"] as? String,
                      let meta = ((pg["imageinfo"] as? [[String: Any]])?.first?["extmetadata"]) as? [String: Any] else { continue }
                func v(_ k: String) -> String? { ((meta[k] as? [String: Any])?["value"] as? String).map(Self.text) }
                let file = String(title.dropFirst(5))
                let key = batch.first { $0.replacingOccurrences(of: "_", with: " ") == file } ?? file
                // (an artist's wiki signature keeps its time stamp, "historicair 11:41, 15 October 2006 (UTC)": the name alone)
                let artist = v("Artist")?.replacingOccurrences(of: #"\s*\d{1,2}:\d{2},\s*\d{1,2}\s+\p{L}+\s+\d{4}\s*\(UTC\)"#,
                                                               with: "", options: .regularExpression)
                out[key] = [artist, v("LicenseShortName")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
        }
        return out
    }
    /// a Commons field's HTML as plain words
    static func text(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// FNV-1a of the file name's UTF-8 bytes, its low byte in hex (the server's shard_of)
    static func shard(_ name: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in name.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        return String(format: "%02x", h & 0xff)
    }
}

/// ONE GLASS ON A PAGE (16.3, Part 0.7): everything glass
/// on a place's page (the head's circles and search the whole time the page is up, the marking block, the lists'
/// fields and buttons) is the logically frosted glass, and never changes kind while it moves
enum PageGlass {
    /// TRIAL (31 Oct 11:47, may be reversed): Apple's split as asked for, the navigation and the small controls clear,
    /// the rest frosted. Set to false and every glass is as before (all of it frosted while a page is up).
    static let clearControls = true
    /// a page's surfaces and its text fields (frosted, so typed words read over the page)
    static let on: SwiftUI.Glass = .regular
    /// a page's buttons and chips
    static var control: SwiftUI.Glass { clearControls ? .clear : .regular }
    /// the head's circles (search, the plus and its tools): navigation, clear on the map and over a page
    @MainActor static var head: SwiftUI.Glass { clearControls ? .clear : surface }
    /// the water and what rises out of it, search's results box, the map's word capsules: the system's own frosted
    /// glass everywhere, so it follows iOS 27's Liquid Glass slider
    /// and its legibility. (The passport's pages stay clear:.)
    @MainActor static var surface: SwiftUI.Glass { .regular }
}


/// ACTIVITIES (16.4.7; the word chosen, never "See and do"): its own search field, the first five rows, then Show more; each
/// row its name and one line (Wikivoyage's words, credited in Sources)
private struct ActivitiesList: View {
    let all: [PlacePageState.Activity]
    @State private var shown = 5

    var body: some View {
        // (searched by the head's field, one search per screen)
        let q = PlacePageState.shared.filter.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let rows = q.isEmpty ? all : all.filter {
            ($0.name + " " + $0.line).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q)
        }
        let limit = q.isEmpty ? shown : rows.count
        if q.isEmpty || !rows.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activities").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
            ForEach(rows.prefix(limit), id: \.self) { a in
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                    if !a.line.isEmpty {
                        Text(a.line).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(2)
                    }
                }
                // (one gap between rows whatever their lines: a row of one line was centred in 52 pt, so the row
                // after a two-line one sat 10 pt nearer than the others)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if rows.count > limit {
                Button { shown += 10 } label: {  // (the next rows are simply there, no fade, 8 Nov)
                    Text("Show more").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        }
    }
}

/// A PAGE'S PHOTO, fetched once and kept: scrolling a row of them back and forth shows each as it was, never blank
/// again while it reloads (AsyncImage keeps nothing)
struct PagePhoto: View {
    let url: URL
    @State private var image: UIImage?
    private static let kept: NSCache<NSURL, UIImage> = { let c = NSCache<NSURL, UIImage>(); c.countLimit = 120; return c }()

    var body: some View {
        // a kept photo is drawn at once, before any task runs
        if let i = image ?? Self.kept.object(forKey: url as NSURL) {
            Image(uiImage: i).resizable().scaledToFill()
        } else {
            Palette.cream.task(id: url) {
                guard let (d, _) = try? await URLSession.shared.data(from: url), let i = UIImage(data: d) else { return }
                let ready = await i.byPreparingForDisplay() ?? i
                Self.kept.setObject(ready, forKey: url as NSURL)
                image = ready
            }
        }
    }
}

import SwiftUI
import Vision
import simd
import MapKit

/// A PLACE'S PAGE (Part 16), first build: a country's page from the data server's country facts (D9 as it is on the
/// server: `country/<cc>.json`), any other place with what the app carries (16.2: the top, the marking block, your
/// record). It grows out of what opened it (A16.1: one rounded rectangle from the origin's frame to the screen, its
/// corners always rounded, nothing fading) under the head, and goes back into it by a drag down on its top.
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
        /// the cards' title: a country's World Heritage sites are its, a sight's neighbours
        var highlightsTitle = "Highlights"
        /// Activities (16.4.7): Wikivoyage's "see" and "do" listings, a town's sights first (a country's from all its cities
        /// in turn, a town's its own)
        var activities: [Activity] = []
        /// the page's photo (Wikimedia Commons), shown under the marking block
        var photo: String?
        /// the prose is a Wikivoyage article's opening (else Wikidata's description), for Sources
        var proseWikivoyage = false
        /// or English Wikipedia's opening, where no guide has a word on it
        var proseWikipedia = false
    }
    struct Activity: Hashable { let name: String; let line: String; var wd: String? = nil }
    struct Highlight: Hashable {
        let id: String; let name: String; let line: String; let photo: String?
        /// a site of several countries (the Carpathians' beech forests are eighteen countries'): its picture may be another's
        var shared = false
    }
    /// the server's World Heritage list, read once
    static var heritage: [String: [String: Any]]?
    /// a World Heritage site's name: its record's, else (a record that has only its id,: 1,546 of 3,460) the World
    /// Heritage set's ("Caral"), else nil
    @MainActor static func heritageName(_ q: String) -> String? {
        if let n = heritage?[q]?["n"] as? String, n.range(of: #"^Q[0-9]+$"#, options: .regularExpression) == nil { return n }
        return CollectionStore.shared.collection("world-heritage")?.items.first { $0.id == q }?.name
    }
    struct Inside: Hashable { let key: PlaceKey; let name: String; let line: String; let code: String?; var at: SIMD2<Float>? = nil
        /// its own photo (a Commons file, as its page shows it), or ""
        var photo = "" }
    /// ONE PAGE of the stack (16.2: a row or card on a page pushes its own page on top; closing it returns to this one)
    @MainActor
    @Observable
    final class OnePage: Identifiable {
        let key: PlaceKey
        let name: String
        /// one line of what it is; empty for a country
        var what: String
        /// the country it is in (its flag and colours)
        let country: String
        /// a region's ISO 3166-2 code (its facts on the server are keyed by it)
        let code: String?
        /// what it grew from (closing goes back into it)
        let origin: CGRect
        var facts: Facts?
        /// everything it asks for has come (or given up): the page shows only then, so nothing arrives after it and
        /// moves what is already there
        var settled = false
        /// a photo it came with (a highlight's), for a thing the data has no row for
        var photo: String?
        /// 0 at the origin to 1 full screen
        var p: CGFloat = 0
        var drag: CGFloat = 0
        /// on its way back into its origin (the stack is not "up" for the water once every page is)
        var closing = false
        /// a line that names the place itself again ( under Tokyo) skips it:
        static func trim(_ what: String, _ name: String, country: String = "") -> String {
            for lead in ["Town in ", "City in "] where what.hasPrefix(lead) {
                var parts = what.dropFirst(lead.count).components(separatedBy: ", ")
                if parts[0].caseInsensitiveCompare(name) == .orderedSame {
                    // ( under Tokyo: its region has its name; its country instead)
                    if parts.count > 1 { parts.removeFirst() }
                    else if let land = Locale(identifier: "en_GB").localizedString(forRegionCode: country.uppercased()) { parts = [land] }
                }
                // ( under Paris, 2.1 million: a place of 100,000 people and more is a city, as the menu's own word
                // for them; the towns' index says how many, once it is read)
                var word = lead
                if lead == "Town in ", (TownIndex.shared.townPeople()[country.lowercased() + "|"
                        + name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)] ?? 0) >= 100_000 { word = "City in " }
                return word + parts.joined(separator: ", ")
            }
            // (a thing's own line from its data starts lower case:)
            return what.prefix(1).uppercased() + what.dropFirst()
        }
        init(key: PlaceKey, name: String, what: String, country: String, code: String?, origin: CGRect) {
            self.key = key; self.name = name; self.what = Self.trim(what, name, country: country); self.country = country.lowercased(); self.code = code
            self.origin = origin
        }
        func load() {
            if key.kind == .country { Task { await loadCountry(key.id.lowercased()); settled = true } }
            else if key.kind == .town { Task { await loadTown(country, id: key.id); settled = true } }
            else if key.kind == .region { Task { await loadRegion(country, code: code ?? ""); settled = true } }
            else if key.kind == .thing { loadThing() }
            else { settled = true }
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
        if !pages.isEmpty, pages.allSatisfy(\.closing) { pages.removeAll() }
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
    /// a page pushed on top of the one up, grown from the row or card tapped on it (16.7:)
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
        guard let (cc, t) = ThingStore.shared.thing(key.id) ?? (ThingStore.shared.things(country.lowercased()) != nil ? setThing() : nil) else {
            // its country's things not read yet: once they are, or (a World Heritage site the data keeps as a whole) its
            // photo and kind from what opened it
            if ThingStore.shared.things(country.lowercased()) == nil {
                ThingStore.shared.load(country.lowercased())
                Task { @MainActor in
                    for _ in 0 ..< 100 where ThingStore.shared.things(country.lowercased()) == nil { try? await Task.sleep(for: .milliseconds(100)) }
                    if ThingStore.shared.thing(key.id) != nil || (ThingStore.shared.things(country.lowercased()) != nil && setThing() != nil) { loadThing(); return }
                    seedOnly()
                }
            } else { seedOnly() }
            return
        }
        if what.isEmpty, t.line.isEmpty, let l = setLine() { what = l }
        var out = PlacePageState.Facts()
        if !t.photo.isEmpty { out.photo = PlacePageState.photo(t.photo) }
        if out.photo == nil {
            out.photo = CollectionStore.shared.all.lazy.compactMap { c in c.items.first { $0.key == self.key }?.photo }
                .compactMap { PlacePageState.photo($0) }.first
        }
        // (its own line is already under its name; no prose repeating it) (a set that says what it is names it: Lake
        // Baikal read)
        let kind = setKind() ?? t.kindName
        let vague = ["water", "nature"].contains(kind)
        if !["spot", "other", "area", "landmark"].contains(kind), !vague, !what.lowercased().contains(kind) {
            out.rows.append(("Kind", kind.prefix(1).uppercased() + kind.dropFirst()))
        }
        out.rows += setFacts()
        let ll = EqualEarth.unproject(SIMD2(Double(t.at.x), Double(t.at.y)))
        // where it is in words (the nearest town and its country), the numbers only when no town is near; the towns'
        // index read first if it is not yet (it is read once, in the background)
        if !TownIndex.shared.ready {
            TownIndex.shared.load()
            Task { @MainActor in
                for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                if TownIndex.shared.ready, self.key.kind == .thing { self.loadThing() } else { self.settled = true }
            }
        }
        let land = PlacePageState.countryName(cc)
        var own = Set(CollectionStore.shared.all.compactMap { c in c.items.first { $0.key == key } }.flatMap { $0.ccs.map { $0.lowercased() } })
        if !cc.isEmpty { own.insert(cc.lowercased()) }
        var whereTown = TownIndex.shared.place(lat: ll.lat, lon: ll.lon, km: 40)
        if let n = whereTown, !own.isEmpty, !own.contains(n.file.lowercased()) {
            let k = cos(ll.lat * .pi / 180)
            let mine = TownIndex.shared.nearest(lat: ll.lat, lon: ll.lon, count: 12).first { (h: TownIndex.Hit) -> Bool in
                let dy: Double = (h.lat - ll.lat) * 111.2
                let dx: Double = (h.lon - ll.lon) * 111.2 * k
                return own.contains(h.file.lowercased()) && dx * dx + dy * dy <= 1600
            }
            whereTown = mine ?? n
        }
        if let town = whereTown {
            let land = PlacePageState.countryName(town.file)
            let big = setArea() >= 100 || town.name.townFolded == self.name.townFolded
            // (the town's first-level division as its record names it, its first name where it gives two,)
            let region = town.region.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let name = big ? (region.isEmpty || self.name.townFolded.contains(region.townFolded) ? "" : region) : town.name
            // (a big place of several countries says them: Lake Geneva,)
            let several = big && own.count > 1
            if several {
                let names: [String] = own.sorted().prefix(3).map { PlacePageState.countryName($0) }.filter { !$0.isEmpty }
                if !names.isEmpty { out.rows.append(("Where", names.joined(separator: ", "))) }
            } else if name.isEmpty {
                if !land.isEmpty { out.rows.append(("Where", land)) }
            } else if !what.localizedCaseInsensitiveContains(name) {
                out.rows.append(("Where", land.isEmpty || land == name ? name : name + ", " + land))
            }
        } else {
            let names: [String] = own.sorted().prefix(3).map { PlacePageState.countryName($0) }.filter { !$0.isEmpty }
            let lands: String = land.isEmpty ? names.joined(separator: ", ") : land
            if !lands.isEmpty { out.rows.append(("Where", lands)) }
        }
        // (no Where that the line under its name says whole: over)
        out.rows.removeAll { r in
            r.0 == "Where" && r.1.split(separator: ",").allSatisfy { what.localizedCaseInsensitiveContains($0.trimmingCharacters(in: .whitespaces)) }
        }
        // NEARBY: the best known sights with a photo within 2 km, as cards like a country's highlights, each how far
        // it is
        let size = Double(setArea())
        let reach = size > 0 ? min(90, max(2, size.squareRoot() / 2)) : kind == "mountain" ? 10 : 2
        var lands = [cc.lowercased()]
        for c in CollectionStore.shared.all { if let i = c.items.first(where: { $0.key == key }) { lands += i.ccs } }
        if let f = TownIndex.shared.nearest(lat: ll.lat, lon: ll.lon, km: max(40, reach))?.file { lands.append(f.lowercased()) }
        lands = lands.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        let unread = lands.filter { ThingStore.shared.things($0) == nil }
        if !unread.isEmpty {
            for u in unread { ThingStore.shared.load(u) }
            let id = key.id
            Task { @MainActor in
                for _ in 0 ..< 60 where unread.contains(where: { ThingStore.shared.things($0) == nil }) { try? await Task.sleep(for: .milliseconds(100)) }
                if self.key.id == id, !unread.contains(where: { ThingStore.shared.things($0) == nil }) { self.loadThing() }
            }
        }
        let mine = SIMD2(ll.lat, ll.lon)
        let near = lands.flatMap { ThingStore.shared.things($0) ?? [] }.compactMap { o -> (ThingStore.Thing, Double)? in
            guard o.id != t.id, !o.photo.isEmpty, PlacePageState.photo(o.photo) != nil, !["station", "stay", "route", "event"].contains(o.kindName) else { return nil }
            let p = EqualEarth.unproject(SIMD2(Double(o.at.x), Double(o.at.y)))
            let dy = (p.lat - mine.x) * 111.2, dx = (p.lon - mine.y) * 111.2 * cos(mine.x * .pi / 180)
            let km = (dx * dx + dy * dy).squareRoot()
            return km <= reach ? (o, km) : nil
        }
        // (as well known, a sports ground after the sights, then the nearest, as the other cards)
        .sorted { a, b in
            let sa = PlacePageState.isStudy(a.0.name), sb = PlacePageState.isStudy(b.0.name)
            let va = PlacePageState.isVenue(a.0.name, a.0.line), vb = PlacePageState.isVenue(b.0.name, b.0.line)
            return sa != sb ? !sa : va != vb ? !va : a.0.fame != b.0.fame ? a.0.fame > b.0.fame : a.1 < b.1
        }
        .prefix(6)
        if !near.isEmpty {
            out.highlights = near.map { o, km in
                let d = km < 1 ? "\(Int((km * 1000 / 50).rounded()) * 50) m away" : km < 10 ? String(format: "%.1f km away", km) : "\(Int(km.rounded())) km away"
                return PlacePageState.Highlight(id: o.id, name: o.name, line: d, photo: PlacePageState.photo(o.photo))
            }
            out.highlightsTitle = "Nearby"
        }
        facts = out
        // ITS TEXT: the guide's own listing of it, where a Wikivoyage guide lists it (by its Wikidata id, else its
        // name), so a castle's page says what the castle is
        let id = key.id, name = self.name, wd = t.id
        let landsNow = lands
        Task { @MainActor in
            var d = await PlacePageState.listingText(cc, wd: wd, name: name)
            if d == nil {
                // (and by its name without and the like: the Grand Canyon's article is)
                let bare = name.replacingOccurrences(of: " (National Park|National Monument|National Historical Park|Nature Reserve|Biosphere Reserve)$", with: "", options: .regularExpression)
                let others = bare == name ? [] : [bare.townFolded, ("Mount " + bare).townFolded]
                d = await PlacePageState.guideIntro(cc, name: name, lat: ll.lat, lon: ll.lon, within: 30, others: others)
                // (an article of exactly its name further off, where the thing is that big: the Great Barrier Reef's,
                // 2,300 km long, is 436 km from its point)
                if d == nil { d = await PlacePageState.guideIntro(cc, name: name, lat: ll.lat, lon: ll.lon, within: 500) }
                // (and in the other countries its sets give it: the Dead Sea, filed under Israel, has its article in
                // Jordan's guide,,)
                for other in landsNow where d == nil && other != cc.lowercased() {
                    d = await PlacePageState.guideIntro(other, name: name, lat: ll.lat, lon: ll.lon, within: 30, others: others)
                }
            }
            if d == nil {
                let me = name.townFolded, k = cos(ll.lat * .pi / 180)
                func close(_ la: Double, _ lo: Double) -> Bool {
                    let dy = (la - ll.lat) * 111.2, dx = (lo - ll.lon) * 111.2 * k
                    return dx * dx + dy * dy <= 900
                }
                let inside = (ThingStore.shared.things(cc.lowercased()) ?? []).filter { o in
                    let n = o.name.townFolded
                    guard o.id != wd, n.count >= 5, n != me, me.contains(n) else { return false }
                    let p = EqualEarth.unproject(SIMD2(Double(o.at.x), Double(o.at.y)))
                    return close(p.lat, p.lon)
                }.sorted { $0.fame > $1.fame }
                for o in inside.prefix(3) where d == nil {
                    d = await PlacePageState.listingText(cc, wd: o.id, name: o.name)
                }
                if d == nil {
                    let words = name.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" }).map(String.init)
                    for w in words where d == nil && w.count >= 4 && w.first?.isUppercase == true {
                        if let t = TownIndex.shared.hits(w, open: cc.lowercased(), limit: 3).first(where: { $0.name.townFolded == w.townFolded && $0.file.lowercased() == cc.lowercased() && close($0.lat, $0.lon) }) {
                            d = await PlacePageState.guideIntro(cc, name: t.name, lat: t.lat, lon: t.lon)
                        }
                    }
                }
            }
            // (or the article that lists it, where that article is named for it: Angkor Wat is listed, without words,
            // in)
            if d == nil, let art = await PlacePageState.listingArticle(cc, wd: wd),
               art.townFolded.split(separator: " ").contains(where: { w in w.count >= 4 && name.townFolded.split(separator: " ").contains(w) }) {
                d = await PlacePageState.guideIntro(cc, name: art, lat: ll.lat, lon: ll.lon, within: 30)
            }
            var fromWikipedia = false
            if d == nil, let w = await PlacePageState.wikipediaIntro(wd: wd, name: name, lat: ll.lat, lon: ll.lon) { d = w; fromWikipedia = true }
            if let d, self.key.id == id, self.facts?.prose.isEmpty == true {
                self.facts?.prose = PlacePageState.whole(PlacePageState.cut(PlacePageState.plain(d, name: name), 620))
                self.facts?.proseWikivoyage = !fromWikipedia
                self.facts?.proseWikipedia = fromWikipedia
            }
            // (its town still to come: the page waits for that answer too)
            if TownIndex.shared.ready { self.settled = true }
        }
    }
    /// what a Places set knows of it and its own record does not: a peak's height, a park's, lake's or island's area
    /// a set's place's line from its sets, or nil
    private func setLine() -> String? {
        let words = ["world-heritage": "World Heritage site", "peaks": "Mountain", "ranges": "Mountain range",
                     "famouslakes": "Lake", "lakes": "Lake", "famousislands": "Island", "islands": "Island",
                     "parks": "Protected area", "seas": "Sea", "landmarks": "Landmark"]
        var word: String?, ccs: [String] = []
        for c in CollectionStore.shared.all {
            guard let i = c.items.first(where: { $0.key == key }) else { continue }
            if ccs.isEmpty { ccs = i.ccs.isEmpty ? [i.cc] : i.ccs }
            if word == nil || c.id == "world-heritage" { word = words[c.id] ?? word }
        }
        guard let word else { return nil }
        let names = ccs.prefix(3).map { PlacePageState.countryName($0) }.filter { !$0.isEmpty }
        let lands = names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return lands.isEmpty ? word : word + " in " + lands
    }
    /// a set's place as a thing (its kind by its set, no line of its own), or nil
    private func setThing() -> (cc: String, thing: ThingStore.Thing)? {
        guard key.kind == .thing else { return nil }
        let its = CollectionStore.shared.all.compactMap { c in c.items.first { $0.key == key } }
        guard let i = its.first else { return nil }
        let k = ThingStore.kinds.firstIndex(of: setKind() == "lake" ? "water" : setKind() == "island" ? "nature" : setKind() ?? "landmark") ?? 2
        let cc = i.cc.isEmpty ? country.lowercased() : i.cc
        return (cc, ThingStore.Thing(id: i.id, name: i.name, kind: k, at: i.at, fame: min(3, i.fame), line: "", photo: its.lazy.map(\.photo).first { !$0.isEmpty } ?? ""))
    }
    private func setKind() -> String? {
        let named = ["peaks": "mountain", "ranges": "mountain range", "famouslakes": "lake", "lakes": "lake",
                     "famousislands": "island", "islands": "island"]
        for c in CollectionStore.shared.all {
            guard let k = named[c.id], c.items.contains(where: { $0.key == key }) else { continue }
            return k
        }
        return nil
    }
    private func setArea() -> Int {
        CollectionStore.shared.all.compactMap { c in c.items.first { $0.key == key }?.area }.max() ?? 0
    }
    private func setFacts() -> [(String, String)] {
        // (every set it is in: Lake Baikal's World Heritage record has no area, its lakes record has)
        let its = CollectionStore.shared.all.compactMap { c in c.items.first { $0.key == key } }
        let height = its.map(\.height).max() ?? 0, area = its.map(\.area).max() ?? 0
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_GB")
        var rows: [(String, String)] = []
        // (not what the line under its name says already: over)
        if height > 0, let n = f.string(from: height as NSNumber), !what.contains(n) { rows.append(("Height", "\(n) m")) }
        if area > 0, let n = f.string(from: area as NSNumber), !what.contains(n) { rows.append(("Area", "\(n) km²")) }
        return rows
    }
    private func seedOnly() {
        var out = PlacePageState.Facts()
        out.photo = photo.flatMap { PlacePageState.photo($0) }
        out.rows = setFacts()
        facts = out
        settled = true
    }
    fileprivate func loadCountry(_ cc: String) async {
        // (the things' index: the checked spelling of an activity's name, F147)
        ThingIndex.shared.load()
        let nats0 = (UserDefaults.standard.stringArray(forKey: MapController.nationalitiesKey) ?? []).filter { $0 != cc }
        let paths = ["country/\(cc).json", "regions/\(cc).json", "cities/\(cc).json", "heritage.json",
                     ThingStore.file(cc), "native/activities/\(cc).json"] + nats0.map { "country/\($0).json" }
        await withTaskGroup(of: Void.self) { g in
            for p in paths { g.addTask { _ = await Servers.data.file(p) } }
        }
        var got: Data?
        for attempt in 0 ..< 3 {
            let answer = await Servers.data.file("country/\(cc).json")
            if case .ok(let d) = answer, (try? JSONSerialization.jsonObject(with: d)) != nil { got = d; break }
            NSLog("wya page %@: no data on try %d", cc, attempt + 1)
            if case .ok = answer { DevDataClient.forget("country/\(cc).json") }
            try? await Task.sleep(for: .milliseconds(700))
        }
        guard let d = got, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], key.id.lowercased() == cc else { return }
        let f = j["facts"] as? [String: Any] ?? [:]
        var out = PlacePageState.Facts()
        if let g = j["guide"] as? [String: Any], let intro = g["intro"] as? String { out.prose = PlacePageState.cut(PlacePageState.plain(intro, name: name), 620); out.proseWikivoyage = true }
        else if let desc = f["desc"] as? String { out.prose = desc.prefix(1).uppercased() + desc.dropFirst() + "." }
        // its photo (Wikidata's image of the country), at the top as every page's
        out.photo = PlacePageState.photo(f["image"])
        func s(_ k: String) -> String? {
            switch f[k] {
            case let v as String: return v
            // (each once: Germany's capital came as, the city and the state)
            case let v as [String]: var seen = Set<String>(); return v.filter { seen.insert($0).inserted }.prefix(3).joined(separator: ", ")
            case let v as NSNumber: return v.stringValue
            default: return nil
            }
        }
        let capitals = ["gb-eng": "London", "gb-sct": "Edinburgh", "gb-wls": "Cardiff", "gb-nir": "Belfast", "ag": "St. John's",
                        "bq": "Kralendijk", "sj": "Longyearbyen"]
        if let v = capitals[cc] ?? s("capital") { out.rows.append(("Capital", v)) }
        let wbPeople = ((j["worldbank"] as? [String: Any])?["population"] as? [Any])?.first as? NSNumber
        if let v = wbPeople ?? (f["population"] as? NSNumber) { out.rows.append(("People", PlacePageState.big(v.doubleValue))) }
        if let v = PlacePageState.area(f["area"], cc: cc) { out.rows.append(("Area", v + " km²")) }
        if let z = PlacePageState.zones(f["timezone"], cc: cc) { out.rows.append(z) }
        // (and the currency: the UK's nations, Ascension and Svalbard had none; Zimbabwe's first was the Botswana pula,
        // Cuba's the convertible peso, gone since 2021)
        let currencies = ["gb-eng": "British pound (£)", "gb-sct": "British pound (£)", "gb-wls": "British pound (£)",
                          "gb-nir": "British pound (£)", "ac": "Saint Helena pound (£)", "sj": "Norwegian krone (kr)",
                          "zw": "Zimbabwe Gold (ZiG)", "cu": "Cuban peso ($)",
                          "ge": "Georgian lari (₾)", "gl": "Danish krone (kr.)", "gm": "Gambian dalasi (D)", "mk": "Macedonian denar (den)",
                          "ve": "Venezuelan bolívar (Bs.)", "sh": "Saint Helena pound (£)"]
        if let v = currencies[cc] { out.rows.append(("Currency", v)) }
        else if let c = f["currency"] as? [[String: Any]], let first = c.first {
            let n = (first["name"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            out.rows.append(("Currency", [n, (first["sym"] as? String).map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")))
        }
        if let v = PlacePageState.languages(f["officialLanguage"], used: f["languageUsed"], cc: cc) { out.rows.append(("Languages", v)) }
        if let v = s("drivingSide") { out.rows.append(("Driving side", v.capitalized)) }
        if let v = PlacePageState.plugs(f["plug"]) { out.rows.append(("Plugs", v)) }
        if let v = s("callingCode") { out.rows.append(("Calling code", v)) }
        // (a list, or one number: the United States', Canada's and Australia's came as one and were left out)
        // (and by hand where the record has none: the UK's nations, Australia's and France's territories and others)
        let emergencies = ["gb-eng": "999", "gb-sct": "999", "gb-wls": "999", "gb-nir": "999", "fk": "999", "cx": "000", "cc": "000",
                           "nf": "000", "gf": "112", "bl": "112", "mf": "112", "wf": "112", "sj": "112", "mp": "911", "sx": "911", "bq": "911"]
        if let first = emergencies[cc] ?? (f["emergency"] as? [String])?.first ?? (f["emergency"] as? String) { out.rows.append(("Emergency", first)) }
        // (the Netherlands here is the one in Europe, the Caribbean islands places of their own: Wikidata's highest point
        // is Mount Scenery, on Saba)
        // (and Australia's is the mainland's, not Mawson Peak on Heard Island; the United States had none)
        let peaks = ["nl": "Vaalserberg", "au": "Mount Kosciuszko", "us": "Denali", "gb-eng": "Scafell Pike", "gb-sct": "Ben Nevis",
                     "gb-wls": "Yr Wyddfa (Snowdon)", "gb-nir": "Slieve Donard"]
        if let v = peaks[cc] ?? s("highestPoint") {
            out.rows.append(("Highest point", v))
        }
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
        var regionLooks: ([String: String], [String: Set<String>]) = ([:], [:])
        // what is in it: the first level's regions (by people, from the server's regions where it has them) and the cities
        if let first = RegionCatalog.shared.first(cc), let file = await RegionCatalog.shared.fetch(cc, row: first.row) {
            var pop: [String: Double] = [:], img: [String: String] = [:]
            // (its capital and its names, for a region with no photo to take its capital's or biggest city's)
            var capOf: [String: String] = [:], namesOf: [String: Set<String>] = [:]
            var nameOf: [String: String] = [:]
            var byName: [String: String] = [:]
            let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            if case .ok(let rd) = await Servers.data.file("regions/\(cc).json"),
               let all = try? JSONSerialization.jsonObject(with: rd) as? [String: Any] {
                for (k, v) in all {
                    let r = v as? [String: Any]
                    pop[k] = (r?["pop"] as? NSNumber)?.doubleValue
                    if let f = PlacePageState.photo(r?["img"]) { img[k] = f }
                    for n in (r?["u"] as? [String]) ?? [] { byName[fold(n)] = k; namesOf[k, default: []].insert(fold(n)) }
                    if let c = r?["cap"] as? String { capOf[k] = fold(c) }
                    if let n = r?["n"] as? String, !n.isEmpty { nameOf[k] = n }
                    if let n = r?["n"] as? String { namesOf[k, default: []].insert(fold(n)) }
                }
            }
            let key = { (u: RegionFile.Unit) -> String? in
                if let c = u.code, pop.keys.contains(c) { return c }
                return byName[fold(u.name)] ?? (u.code?.isEmpty == false ? u.code : nil)
            }
            var seen = Set<String>()
            let word = RegionsMenuModel.word(first.level.one)
            let units = file.units.filter { seen.insert($0.id).inserted }
            let ranked = units.sorted { a, b in (pop[key(a) ?? ""] ?? 0) > (pop[key(b) ?? ""] ?? 0) }
            let level: String = String(word.prefix(1)).uppercased() + String(word.dropFirst())
            var rows: [PlacePageState.Inside] = []
            for u in ranked {
                // (the level's word once: over is "Osaka")
                var line: String = level
                if let n = pop[key(u) ?? ""] { line = level + " · " + PlacePageState.big(n) + " people" }
                rows.append(PlacePageState.Inside(key: PlaceKey(.region, u.id), name: PlacePageState.withoutLevel(nameOf[key(u) ?? ""] ?? u.name, word),
                                                  line: line, code: key(u), photo: img[key(u) ?? ""] ?? ""))
                namesOf[key(u) ?? u.id, default: []].insert(fold(u.name))
            }
            out.regions = rows
            regionLooks = (capOf, namesOf)
        }
        if case .ok(let cd) = await Servers.data.file("cities/\(cc).json"),
           let all = try? JSONSerialization.jsonObject(with: cd) as? [[String: Any]] {
            out.cities = all.compactMap { t in
                guard let n = t["n"] as? String, !PlacePageState.notACity(t) else { return nil }
                // (its region, unless that is its own name again:, on Japan's page)
                let r0 = t["r"] as? String ?? ""
                let r = r0.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    || r0.localizedCaseInsensitiveContains(n) && r0.count <= n.count + 12 ? "" : r0
                let ll = t["ll"] as? [NSNumber]
                return PlacePageState.Inside(key: PlacePageState.cityKey(cc, t, name: n), name: n, line: r, code: nil,
                              at: ll.flatMap { $0.count == 2 ? EqualEarth.project(lon: $0[1].doubleValue, lat: $0[0].doubleValue) : nil },
                              photo: PlacePageState.photo(t["img"]) ?? "")
            }
            let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            let raw = all.compactMap { t -> (String, String, String)? in
                guard let n = t["n"] as? String, let f = PlacePageState.photo(t["img"]) else { return nil }
                return (fold(n), fold(t["r"] as? String ?? ""), f)
            }
            out.regions = out.regions.map { r in
                guard r.photo.isEmpty else { return r }
                let k = r.code ?? r.key.id
                let names = regionLooks.1[k] ?? [fold(r.name)]
                let cap = regionLooks.0[k]
                guard let f = raw.first(where: { cap != nil && $0.0 == cap! })?.2
                        ?? raw.first(where: { names.contains($0.1) || $0.1.hasPrefix(fold(r.name)) })?.2 else { return r }
                var r2 = r; r2.photo = f; return r2
            }
        }
        // highlights: the country's World Heritage sites (the list the server's country file names)
        if let ids = j["heritage"] as? [String], !ids.isEmpty {
            if PlacePageState.heritage == nil, case .ok(let hd) = await Servers.data.file("heritage.json"),
               let all = try? JSONSerialization.jsonObject(with: hd) as? [String: [String: Any]] { PlacePageState.heritage = all }
            // (the best known first, by the country's things' own order, as its activities are ranked: France's
            // opened on a fort listed in 2023, the newest first)
            var known: [String: Int] = [:]
            var spots: [(i: Int, name: String, lat: Double, lon: Double)] = []
            if case .ok(let td) = await Servers.data.file(ThingStore.file(cc)),
               let rows = try? JSONSerialization.jsonObject(with: td) as? [[Any]] {
                for (i, r) in rows.enumerated() {
                    if let q = r.first as? String, known[q] == nil { known[q] = i }
                    if r.count > 4, let n = r[1] as? String, let la = (r[3] as? NSNumber)?.doubleValue, let lo = (r[4] as? NSNumber)?.doubleValue {
                        spots.append((i, n.townFolded, la, lo))
                    }
                }
            }
            for q in ids where known[q] == nil {
                guard let h = PlacePageState.heritage?[q], let ll = h["ll"] as? [NSNumber], ll.count == 2 else { continue }
                let lat = ll[0].doubleValue, lon = ll[1].doubleValue, k = cos(lat * .pi / 180)
                let wn = (PlacePageState.heritageName(q) ?? "").townFolded
                let best = spots.filter { sp in
                    let dy = (sp.lat - lat) * 111.2, dx = (sp.lon - lon) * 111.2 * k, d = (dx * dx + dy * dy).squareRoot()
                    return d <= 1.5 || (d <= 30 && sp.name.count >= 6 && wn.contains(sp.name))
                }.map(\.i).min()
                if let best { known[q] = best }
            }
            let whole = Set(CollectionStore.shared.collection("world-heritage")?.items.map(\.id) ?? [])
            let sites = ids.filter { q in
                let h = PlacePageState.heritage?[q]
                return whole.contains(q) || (h?["year"] as? String != nil && !((h?["crit"] as? [String]) ?? []).isEmpty)
            }
            var kept: [(String, Double, Double, Bool)] = []
            let ranked = sites.enumerated().sorted { a, b in
                let x = known[a.element] ?? Int.max, y = known[b.element] ?? Int.max
                return x != y ? x < y : a.offset < b.offset
            }.map(\.element).filter { q in
                guard let h = PlacePageState.heritage?[q], let ll = h["ll"] as? [NSNumber], ll.count == 2 else { return true }
                let sig = (h["year"] as? String ?? "") + ((h["crit"] as? [String]) ?? []).joined()
                guard !sig.isEmpty else { return true }
                let lat = ll[0].doubleValue, lon = ll[1].doubleValue
                // (two whole sites of the set are never one: Kraków's Old Town and the Wieliczka salt mines, both 1978)
                let mine = whole.contains(q)
                if kept.contains(where: { k in k.0 == sig && !(k.3 && mine) && abs(k.1 - lat) * 111.2 < 10 && abs(k.2 - lon) * 111.2 * cos(lat * .pi / 180) < 10 }) { return false }
                kept.append((sig, lat, lon, mine))
                return true
            }
            out.highlights = ranked.compactMap { q in
                guard let h = PlacePageState.heritage?[q], let n = PlacePageState.heritageName(q) else { return nil }
                // (not a whole prefecture, province or state the list took in by mistake: Japan's had)
                if ((h["kind"] as? [String]) ?? []).contains(where: { $0.hasPrefix("prefecture") || $0.hasPrefix("province of") || $0.hasPrefix("state of") }) { return nil }
                let year = h["year"] as? String
                return PlacePageState.Highlight(id: q, name: n.prefix(1).uppercased() + n.dropFirst(), line: year.map { "World Heritage since \($0)" } ?? "World Heritage",
                                 photo: PlacePageState.photo(h["img"]) ?? (h["img"] as? [String])?.first, shared: ((h["cc"] as? [String])?.count ?? 1) > 1)
            }
        }
        if out.highlights.count < 8 {
            ThingStore.shared.load(cc)
            for _ in 0 ..< 60 where ThingStore.shared.things(cc) == nil { try? await Task.sleep(for: .milliseconds(100)) }
            let have = Set(out.highlights.map { $0.name.townFolded })
            let more = (ThingStore.shared.things(cc) ?? []).filter { o in
                o.fame >= 1 && (2...6).contains(o.kind) && !o.photo.isEmpty && PlacePageState.photo(o.photo) != nil
                    && !PlacePageState.isStudy(o.name) && !PlacePageState.isVenue(o.name, o.line)
                    && !have.contains(where: { $0.contains(o.name.townFolded) || o.name.townFolded.contains($0) })
            }.enumerated().sorted { a, b in a.element.fame != b.element.fame ? a.element.fame > b.element.fame : a.offset < b.offset }
            .map(\.element).prefix(8 - out.highlights.count)
            out.highlights += more.map { o in
                let l = PlacePageState.brief(o.line, 60)
                return PlacePageState.Highlight(id: o.id, name: o.name.prefix(1).uppercased() + o.name.dropFirst(), line: l.prefix(1).uppercased() + l.dropFirst(), photo: PlacePageState.photo(o.photo))
            }
        }
        // the guide's own main cities first (Rome, then Bologna ... for Italy), the rest after
        let mainCities = ((j["guide"] as? [String: Any])?["cities"] as? [[String: Any]])?.compactMap { $0["n"] as? String } ?? []
        out.activities = await PlacePageState.activities(cc, town: nil, first: mainCities)
        // a country whose own picture is a map (most are): its first sight's photo at the top instead
        if out.photo == nil { out.photo = await PlacePageState.bestSightPhoto(cc) }
        if out.photo == nil { out.photo = out.highlights.lazy.filter { !$0.shared }.compactMap { PlacePageState.photo($0.photo) }.first }
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
        settled = true
    }

    /// A TOWN'S FACTS (16.4.5: People, Height, Local time, Climate) from the server's cities (D9 as it is), by its
    /// GeoNames id
    fileprivate func loadTown(_ cc: String, id: String) async {
        // (a town with no GeoNames id is keyed by its name,: found by it, the most peopled of that name; London's and
        // New York's pages had no facts at all)
        let last = String(id.split(separator: "/", maxSplits: 1).last ?? "")
        var all: [[String: Any]] = []
        if case .ok(let d) = await Servers.data.file("cities/\(cc).json") { all = (try? JSONSerialization.jsonObject(with: d) as? [[String: Any]]) ?? [] }
        guard let t = Int(last).flatMap({ gid in all.first(where: { ($0["gid"] as? NSNumber)?.intValue == gid }) })
                ?? all.filter({ $0["gid"] == nil && $0["n"] as? String == last })
                      .max(by: { (($0["p"] as? NSNumber)?.intValue ?? 0) < (($1["p"] as? NSNumber)?.intValue ?? 0) }),
              key.id == id else { await loadSmallTown(cc, id: id, near: all); return }
        var out = PlacePageState.Facts()
        // (a capital says so first: Paris's page never said it is France's)
        if CollectionStore.shared.collection(CollectionStore.capitals)?.items.contains(where: { $0.key == key }) == true,
           case let land = PlacePageState.countryName(cc), !land.isEmpty, land != name { out.rows.append(("Capital of", land)) }
        if let p = t["p"] as? NSNumber, p.intValue > 0 { out.rows.append(("People", PlacePageState.big(p.doubleValue))) }
        if let e = t["ele"] as? NSNumber {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_GB")
            out.rows.append(("Height", "\(f.string(from: e) ?? "\(e.intValue)") m"))
        }
        var zone = (t["tz"] as? String).flatMap(TimeZone.init(identifier:))
        if zone == nil, let ll = t["ll"] as? [NSNumber], ll.count == 2 { zone = await Self.zone(lat: ll[0].doubleValue, lon: ll[1].doubleValue) }
        if let tz = zone {
            let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "HH:mm"
            out.rows.append(("Local time", f.string(from: Date())))
        }
        if let c = t["climate"] as? [String: Any], let hi = c["hi"] as? [NSNumber], let lo = c["lo"] as? [NSNumber], hi.count == 12, lo.count == 12 {
            let h = hi.map(\.doubleValue), l = lo.map(\.doubleValue)
            let hm = h.indices.max { h[$0] < h[$1] } ?? 6, lm = l.indices.min { l[$0] < l[$1] } ?? 0
            let mf = DateFormatter(); mf.locale = Locale(identifier: "en_GB")
            let mon = mf.shortMonthSymbols ?? []
            if mon.count == 12 {
                out.rows.append(("Climate", "\(Int(h[hm].rounded()))° \(mon[hm]) · \(Int(l[lm].rounded()))° \(mon[lm])"))
            }
        }
        if let n = t["n"] as? String {
            let ll = t["ll"] as? [NSNumber]
            let reach = ((t["p"] as? NSNumber)?.doubleValue ?? 0) >= 1_000_000 ? 12.0 : 5.0
            let near = ll.flatMap { $0.count == 2 ? (lat: $0[0].doubleValue, lon: $0[1].doubleValue, km: reach) : nil }
            out.activities = await PlacePageState.activities(cc, town: n, near: near)
        }
        // its photo (Wikidata's image of the place with this GeoNames id) and its opening words (its Wikivoyage
        // article's), as a country's page has them
        out.photo = PlacePageState.photo(t["img"])
        if let n = t["n"] as? String, let ll = t["ll"] as? [NSNumber], ll.count == 2,
           let intro = await PlacePageState.guideIntro(cc, name: n, lat: ll[0].doubleValue, lon: ll[1].doubleValue,
                                                       others: TownIndex.shared.otherNames(id)) {
            out.prose = PlacePageState.cut(PlacePageState.plain(intro, name: n), 620); out.proseWikivoyage = true
        }
        // ITS HIGHLIGHTS: the best known sights with a photo near it, 12 km round a city of a million, 5 km round a
        // smaller one, as a region's page has them
        if let ll = t["ll"] as? [NSNumber], ll.count == 2 {
            let reach = ((t["p"] as? NSNumber)?.doubleValue ?? 0) >= 1_000_000 ? 12.0 : 5.0
            out.highlights = await nearHighlights(cc, lat: ll[0].doubleValue, lon: ll[1].doubleValue, reach: reach)
        }
        if out.photo == nil { out.photo = out.highlights.lazy.compactMap { $0.photo }.first }
        guard key.id == id else { return }
        facts = out
        settled = true
    }

    /// A POINT'S CLOCK from Apple's maps, where the data has none; nil offline
    static func zone(lat: Double, lon: Double) async -> TimeZone? {
        guard let r = MKReverseGeocodingRequest(location: CLLocation(latitude: lat, longitude: lon)) else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<TimeZone?, Never>) in
            r.getMapItems { items, _ in c.resume(returning: items?.first?.timeZone) }
        }
    }

    /// A TOWN THE CITIES' FILE DOES NOT HAVE: what the towns' index knows of it (its people; its region is already
    /// under its name), and its guide's opening words where Wikivoyage has an article near it (its local time from
    /// the nearest town the cities' file has, which shares its clock) A TOWN'S HIGHLIGHTS: the best known sights with
    /// a photo within `reach` km of it, and the best known of the sets' places that no country's things hold
    private func nearHighlights(_ cc: String, lat: Double, lon: Double, reach: Double) async -> [PlacePageState.Highlight] {
        ThingStore.shared.load(cc)
        for _ in 0 ..< 100 where ThingStore.shared.things(cc) == nil { try? await Task.sleep(for: .milliseconds(100)) }
        let picks = (ThingStore.shared.things(cc) ?? []).enumerated().filter { _, o in
            guard !o.photo.isEmpty, PlacePageState.photo(o.photo) != nil,
                  !["station", "stay", "route", "event", "city", "area"].contains(o.kindName) else { return false }
            let p = EqualEarth.unproject(SIMD2(Double(o.at.x), Double(o.at.y)))
            let dy = (p.lat - lat) * 111.2, dx = (p.lon - lon) * 111.2 * cos(lat * .pi / 180)
            return dx * dx + dy * dy <= reach * reach
        }
        // (as well known, the sights file's own order, as a region's)
        .sorted { a, b in
            let sa = PlacePageState.isStudy(a.element.name), sb = PlacePageState.isStudy(b.element.name)
            let va = PlacePageState.isVenue(a.element.name, a.element.line), vb = PlacePageState.isVenue(b.element.name, b.element.line)
            return sa != sb ? !sa : va != vb ? !va : a.element.fame != b.element.fame ? a.element.fame > b.element.fame : a.offset < b.offset
        }
        .map(\.element)
        .prefix(8)
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_GB")
        var seen = Set(picks.map(\.id))
        let extra = ["peaks", "famouslakes", "famousislands", "parks", "landmarks"].flatMap { id in
            (CollectionStore.shared.collection(id)?.items ?? []).filter { i in
                guard i.fame == 3, !i.photo.isEmpty else { return false }
                let p = EqualEarth.unproject(SIMD2(Double(i.at.x), Double(i.at.y)))
                let dy = (p.lat - lat) * 111.2, dx = (p.lon - lon) * 111.2 * cos(lat * .pi / 180)
                return dx * dx + dy * dy <= reach * reach && PlacePageState.photo(i.photo) != nil && ThingStore.shared.thing("wd:" + i.id) == nil
            }
        }.filter { seen.insert($0.id).inserted }.prefix(2).map { (i: CollectionStore.Item) -> PlacePageState.Highlight in
            let name: String = i.name.prefix(1).uppercased() + i.name.dropFirst()
            let high: String = i.height > 0 ? (f.string(from: i.height as NSNumber) ?? "") + " m high" : ""
            return PlacePageState.Highlight(id: i.id, name: name, line: high, photo: PlacePageState.photo(i.photo))
        }
        // (after the city's best known sight: Paris opened on the Île de la Cité before the Eiffel Tower)
        var all = picks.map { o in
            let l = PlacePageState.brief(o.line, 60)
            return PlacePageState.Highlight(id: o.id, name: o.name.prefix(1).uppercased() + o.name.dropFirst(), line: l.prefix(1).uppercased() + l.dropFirst(), photo: PlacePageState.photo(o.photo))
        }
        all.insert(contentsOf: extra, at: min(1, all.count))
        return Array(all.prefix(8))
    }
    fileprivate func loadSmallTown(_ cc: String, id: String, near all: [[String: Any]]) async {
        guard let t = TownIndex.shared.hit(id), key.id == id else { return }
        var out = PlacePageState.Facts()
        if t.people > 0 { out.rows.append(("People", PlacePageState.big(Double(t.people)))) }
        let k = cos(t.lat * .pi / 180)
        let near = all.min { a, b in
            func d(_ x: [String: Any]) -> Double {
                guard let ll = x["ll"] as? [NSNumber], ll.count == 2 else { return .infinity }
                let dy = ll[0].doubleValue - t.lat, dx = (ll[1].doubleValue - t.lon) * k
                return dy * dy + dx * dx
            }
            return d(a) < d(b)
        }
        var zone = (near?["tz"] as? String).flatMap(TimeZone.init(identifier:))
        if zone == nil { zone = await Self.zone(lat: t.lat, lon: t.lon) }
        if let tz = zone {
            let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "HH:mm"
            out.rows.append(("Local time", f.string(from: Date())))
        }
        if let intro = await PlacePageState.guideIntro(cc, name: t.name, lat: t.lat, lon: t.lon, others: TownIndex.shared.otherNames(id)) {
            out.prose = PlacePageState.cut(PlacePageState.plain(intro, name: t.name), 620); out.proseWikivoyage = true
        }
        // (its highlights, 5 km round it as a smaller city's, and its photo the first of them's: Hallstatt, Positano and Zermatt opened bare)
        out.highlights = await nearHighlights(cc, lat: t.lat, lon: t.lon, reach: 5)
        if out.photo == nil { out.photo = out.highlights.lazy.compactMap { $0.photo }.first }
        guard key.id == id, !out.rows.isEmpty || !out.prose.isEmpty else { return }
        facts = out
        settled = true
    }

    /// A REGION'S FACTS (16.4.5: People, Area, Capital, its parent) from the server's regions (level 1, by ISO code)
    fileprivate func loadRegion(_ cc: String, code: String) async {
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let me = fold(name)
        guard case .ok(let d) = await Servers.data.file("regions/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = (all[code] as? [String: Any]) ?? all.values.compactMap({ $0 as? [String: Any] }).first(where: { v in
                  ((v["u"] as? [String]) ?? []).contains { fold($0) == me } || (v["n"] as? String).map(fold) == me
              }), (self.code ?? "") == code else { return }
        var out = PlacePageState.Facts()
        if let desc = r["d"] as? String { out.prose = desc.prefix(1).uppercased() + desc.dropFirst() + "." }
        // its photo (Wikidata's) and, where Wikivoyage has an article for it, that article's opening words in place
        // of the one-line description
        out.photo = PlacePageState.photo(r["img"])
        if let n = r["n"] as? String, let ll = r["ll"] as? [NSNumber], ll.count == 2,
           let intro = await PlacePageState.guideIntro(cc, name: n, lat: ll[0].doubleValue, lon: ll[1].doubleValue, within: 150) {
            out.prose = PlacePageState.cut(PlacePageState.plain(intro, name: n), 620); out.proseWikivoyage = true
        }
        if let p = r["pop"] as? NSNumber { out.rows.append(("People", PlacePageState.big(p.doubleValue))) }
        if let a = r["area"] as? NSNumber { out.rows.append(("Area", PlacePageState.big(a.doubleValue) + " km²")) }
        if let c = r["cap"] as? String { out.rows.append(("Capital", c)) }
        // ITS CITIES: the country's cities whose region is this one (by its record's name, its own, or the names its
        // record was matched by), the most peopled first, as a country's page lists them
        var names = Set([me] + ((r["u"] as? [String]) ?? []).map(fold))
        if let n = r["n"] as? String { names.insert(fold(n)) }
        if case .ok(let cd) = await Servers.data.file("cities/\(cc).json"),
           let cities = try? JSONSerialization.jsonObject(with: cd) as? [[String: Any]] {
            out.cities = cities.compactMap { t in
                guard let n = t["n"] as? String, let rr = t["r"] as? String, names.contains(fold(rr)), !PlacePageState.notACity(t) else { return nil }
                let ll = t["ll"] as? [NSNumber]
                return PlacePageState.Inside(key: PlacePageState.cityKey(cc, t, name: n), name: n, line: "", code: nil,
                              at: ll.flatMap { $0.count == 2 ? EqualEarth.project(lon: $0[1].doubleValue, lat: $0[0].doubleValue) : nil },
                              photo: PlacePageState.photo(t["img"]) ?? "")
            }
        }
        if out.photo == nil {
            let cap = (r["cap"] as? String).map(fold)
            out.photo = (out.cities.first { cap != nil && fold($0.name) == cap && !$0.photo.isEmpty }
                         ?? out.cities.first { !$0.photo.isEmpty }).map(\.photo)
        }
        // ITS HIGHLIGHTS: the best known sights with a photo inside its own outline (its units' rings, even-odd), as
        // cards like a country's World Heritage
        var rings: [[SIMD2<Double>]] = []
        for lv in RegionCatalog.shared.used(cc) {
            if let f = await RegionCatalog.shared.fetch(cc, row: lv.row) {
                let mine = f.units.filter { $0.id == key.id }
                if !mine.isEmpty { rings = mine.flatMap(\.rings); break }
            }
        }
        if !rings.isEmpty {
            ThingStore.shared.load(cc)
            // (the United States' sights take longer than four seconds to come: ten)
            for _ in 0 ..< 100 where ThingStore.shared.things(cc) == nil { try? await Task.sleep(for: .milliseconds(100)) }
            let east = rings.contains { r in r.contains { $0.x > 180 } }
            func inside(_ p0: SIMD2<Double>) -> Bool {
                let p = east && p0.x < 0 ? SIMD2(p0.x + 360, p0.y) : p0
                var odd = false
                for r in rings where r.count > 2 {
                    var j = r.count - 1
                    for i in 0 ..< r.count {
                        let a = r[i], b = r[j]
                        if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { odd.toggle() }
                        j = i
                    }
                }
                return odd
            }
            let picks = (ThingStore.shared.things(cc) ?? []).enumerated().filter { _, o in
                !o.photo.isEmpty && PlacePageState.photo(o.photo) != nil && !["station", "stay", "route", "event", "city", "area"].contains(o.kindName)
            }
            .sorted { a, b in
                let sa = PlacePageState.isStudy(a.element.name), sb = PlacePageState.isStudy(b.element.name)
                let va = PlacePageState.isVenue(a.element.name, a.element.line), vb = PlacePageState.isVenue(b.element.name, b.element.line)
                return sa != sb ? !sa : va != vb ? !va : a.element.fame != b.element.fame ? a.element.fame > b.element.fame : a.offset < b.offset
            }
            .map(\.element)
            .lazy.filter { o in
                let ll = EqualEarth.unproject(SIMD2(Double(o.at.x), Double(o.at.y)))
                return inside(SIMD2(ll.lon, ll.lat))
            }
            .prefix(8)
            var all: [PlacePageState.Highlight] = picks.map { o in
                // (Wikidata's line starts small,: a capital, as a sentence under a name)
                let l = PlacePageState.brief(o.line, 60)
                return PlacePageState.Highlight(id: o.id, name: o.name.prefix(1).uppercased() + o.name.dropFirst(), line: l.prefix(1).uppercased() + l.dropFirst(), photo: PlacePageState.photo(o.photo))
            }
            let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_GB")
            var seen = Set(all.map(\.id))
            let extra = ["parks", "peaks", "famouslakes", "famousislands", "landmarks"].flatMap { id in
                (CollectionStore.shared.collection(id)?.items ?? []).filter { i in
                    guard i.fame == 3, !i.photo.isEmpty, i.cc == cc.lowercased() || i.ccs.contains(cc.lowercased()) else { return false }
                    let ll = EqualEarth.unproject(SIMD2(Double(i.at.x), Double(i.at.y)))
                    return inside(SIMD2(ll.lon, ll.lat)) && PlacePageState.photo(i.photo) != nil && ThingStore.shared.thing("wd:" + i.id) == nil
                }
            }.filter { seen.insert($0.id).inserted }.prefix(2).map { (i: CollectionStore.Item) -> PlacePageState.Highlight in
                let name: String = i.name.prefix(1).uppercased() + i.name.dropFirst()
                let high: String = i.height > 0 ? (f.string(from: i.height as NSNumber) ?? "") + " m high" : ""
                return PlacePageState.Highlight(id: i.id, name: name, line: high, photo: PlacePageState.photo(i.photo))
            }
            all.insert(contentsOf: extra, at: min(1, all.count))
            out.highlights = Array(all.prefix(8))
        }
        if out.photo == nil { out.photo = out.highlights.lazy.compactMap { $0.photo }.first }
        facts = out
        settled = true
    }

}

extension PlacePageState {
    /// A PLACE'S OPENING WORDS: its own Wikivoyage article, found in the country's index by its title (the place's
    /// name, or its name with a bracket after it,) and lying within `within` km of it (25 for a town, more for a
    /// region, whose point is its middle); the nearest if several. Nil when it has none, or the article has no intro.
    /// `others`: its other names, folded
    static func guideIntro(_ cc: String, name: String, lat: Double, lon: Double, within: Double = 25, others: [String] = []) async -> String? {
        let wanted = Set(others)
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
                guard let title = r[0] as? String,
                      title == name || title.hasPrefix(name + " (")
                        || (!wanted.isEmpty && wanted.contains(String(title.split(separator: " (").first ?? "").townFolded)),
                      let a = (r[3] as? NSNumber)?.doubleValue, let b = (r[4] as? NSNumber)?.doubleValue, let key = r[5] as? String else { continue }
                // (its own name first: another name's guide counts as 10 km further)
                let own = title == name || title.hasPrefix(name + " (")
                let k = km(a, b) + (own ? 0 : 10)
                if k < within + (own ? 0 : 10), k < (best?.km ?? .infinity) { best = (file, key, k) }
            }
        }
        guard let file = best?.file, let key = best?.key, case .ok(let pd) = await Servers.data.file("place/\(file)/\(key).json"),
              let j = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
              let intro = (j["g"] as? [String: Any])?["intro"] as? String, !intro.isEmpty else { return nil }
        return uncaptioned(intro, name: name)
    }
    static func uncaptioned(_ s: String, name: String) -> String {
        var t = s
        if let r = t.range(of: "]]"), t.distance(from: t.startIndex, to: r.lowerBound) < 300 {
            t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if t.hasPrefix("thumb ") { t = String(t.dropFirst(6)) }
        let head = t.prefix(300)
        // (only marks that open the text: one later on,, is the cleaner's below)
        let opens = head.firstIndex(of: "|").map { head.distance(from: head.startIndex, to: $0) < 30 } ?? false
        if opens, t.hasPrefix("thumb|") || head.contains("px|") || head.contains("thumb|"), let bar = head.range(of: "|", options: .backwards) {
            let rest = String(t[bar.upperBound...])
            let n = NSRegularExpression.escapedPattern(for: name)
            if let r = rest.range(of: "\\b" + n + "( \\(| is | was | are |, )", options: .regularExpression),
               let start = rest[..<r.lowerBound].isEmpty ? nil : Optional(r.lowerBound) {
                t = String(rest[start...])
            } else { t = rest }
        }
        // (its own name dropped before "is":)
        if t.hasPrefix("is ") || t.hasPrefix("are ") { t = name + " " + t }
        t = unmarked(t)
        return t.isEmpty ? s : t
    }
    nonisolated static func unmarked(_ s: String) -> String {
        func re(_ x: String, _ p: String, _ w: String) -> String { x.replacingOccurrences(of: p, with: w, options: .regularExpression) }
        var t = s
        t = re(t, "\\{\\{[^{}]*(\\{[^{}]*\\}[^{}]*)*\\}\\}\\}?", "")
        t = re(re(t, "\\[\\[[^\\]|]*\\|([^\\]]*)\\]\\]", "$1"), "\\[\\[([^\\]]*)\\]\\]", "$1")
        t = re(t, "\\(?\\[?https?://[^\\s\\])]*\\s*\\]?\\)?", "")
        while let r = t.range(of: "]]") {
            let before = t[..<r.lowerBound]
            if let dot = before.range(of: ". ", options: .backwards), before.distance(from: dot.upperBound, to: before.endIndex) < 200 {
                t.removeSubrange(dot.upperBound..<r.upperBound)
            } else { t.removeSubrange(r) }
        }
        if let r = t.range(of: "(\\d+px\\||thumb\\||right\\||left\\||upright\\||center\\||noborder\\|)+", options: .regularExpression) {
            let before = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let after = t[r.upperBound...]
            if let next = after.range(of: "\\s(This|These|The|It|Its|In|During|There|With|Since|Located|Founded|Today|Once|From)\\s", options: .regularExpression),
               after.distance(from: after.startIndex, to: next.lowerBound) < 150, after.distance(from: after.startIndex, to: next.lowerBound) > 2 {
                t = before + " " + after[after.index(after: next.lowerBound)...]
            } else {
                t = before.count >= 60 || before.hasSuffix(".") ? before : String(after)
            }
        }
        t = re(re(re(re(t, "\\[\\[|\\]\\]", ""), " {2,}", " "), " ([.,;:)])", "$1"), "\\( *\\)", "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func activities(_ cc: String, town: String?, first: [String] = [], near: (lat: Double, lon: Double, km: Double)? = nil) async -> [Activity] {
        // (kept once worked out, beside the listings file's own size: the same file gives the same rows)
        let key = firstKey(first)
        let keep = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("activities").appendingPathComponent("\(cc)-\(key).json")
        // a country's rows ready-made by the data server (its file a few hundred rows, not the whole guide: the United
        // States' guide is 11.5 MB and took 2.5 s to read and rank the first time): taken when it was made for the
        // same main cities
        if town == nil, case .ok(let pd) = await Servers.data.file("native/activities/\(cc).json"),
           let j = try? JSONSerialization.jsonObject(with: pd) as? [String: Any], j["first"] as? String == key,
           let rows = j["rows"] as? [[String]] {
            return Self.settled(rows.compactMap { $0.count == 3 && !isTicket($0[0]) ? activity($0[0], line: $0[2], wd: $0[1].isEmpty ? nil : $0[1]) : nil })
        }
        guard case .ok(let d) = await Servers.data.file("listings/\(cc).json") else { return [] }
        // (a town's rows are never kept: its file name has no town in it, and a town's few rows come fast)
        if town == nil, let k = try? Data(contentsOf: keep), let j = try? JSONSerialization.jsonObject(with: k) as? [String: Any],
           (j["bytes"] as? NSNumber)?.intValue == d.count, let rows = j["rows"] as? [[String]] {
            return rows.compactMap { $0.count == 2 ? activity($0[0], line: $0[1], wd: nil) : nil }
        }
        var things: Data?
        if case .ok(let td) = await Servers.data.file(ThingStore.file(cc)) { things = td }
        let rows = await Task.detached(priority: .userInitiated) { Self.activityRows(d, things, town: town, first: first, near: near) }.value
        let out = Self.settled(rows.map { Self.activity($0.name, line: $0.line, wd: $0.wd) })
        // (kept only when worked out whole: ranked by the things file, the spellings checked; a list made without
        // them was kept for good)
        if town == nil, out.count > 50, things != nil, ThingIndex.shared.ready,
           let j = try? JSONSerialization.data(withJSONObject: ["bytes": d.count, "rows": out.map { [$0.name, $0.line] }] as [String: Any]) {
            try? FileManager.default.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? j.write(to: keep, options: .atomic)
        }
        return out
    }

    /// the main cities' mark (FNV-1a of their names, in order): a list made for other cities is not this one
    nonisolated static func firstKey(_ first: [String]) -> String {
        var h: UInt64 = 14695981039346656037
        for b in first.joined(separator: ",").utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 16)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// THE DATA SERVER'S READY-MADE ACTIVITIES (debug, Simulator: the test driver's `action build.activities`): every
    /// country's rows worked out by the same code the page uses, written into the server folder on the Mac
    /// (native/activities/<cc>.json, gzipped there after, as the server's files are)
    nonisolated static func buildActivitiesFiles() async {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"],
              case .ok(let cd) = await Servers.data.file("countries.json"),
              let cs = try? JSONSerialization.jsonObject(with: cd) as? [[String: Any]] else { return }
        let dir = URL(fileURLWithPath: home + "/Library/Mobile Documents/com~apple~CloudDocs/wya?!/server/public.nosync/v1/native/activities")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var made = 0
        for c in cs {
            guard let cc = c["cc"] as? String, case .ok(let d) = await Servers.data.file("listings/\(cc).json") else { continue }
            var first: [String] = []
            if case .ok(let jd) = await Servers.data.file("country/\(cc).json"),
               let j = try? JSONSerialization.jsonObject(with: jd) as? [String: Any] {
                first = ((j["guide"] as? [String: Any])?["cities"] as? [[String: Any]])?.compactMap { $0["n"] as? String } ?? []
            }
            var things: Data?
            if case .ok(let td) = await Servers.data.file(ThingStore.file(cc)) { things = td }
            // (only a list ranked by the things file and long enough to be the country's, as the page itself keeps)
            guard things != nil else { continue }
            let rows = activityRows(d, things, town: nil, first: first)
            guard rows.count > 50 else { continue }
            let j: [String: Any] = ["first": firstKey(first), "rows": rows.map { [$0.name, $0.wd ?? "", $0.line] }]
            if let out = try? JSONSerialization.data(withJSONObject: j) {
                try? out.write(to: dir.appendingPathComponent("\(cc).json"))
                made += 1
            }
        }
        NSLog("wya activities built: %d countries", made)
    }
    #endif

    /// a sports ground (its name or Wikidata's line says so): as well known as a cathedral it still comes after it,
    /// as a sight to travel for A LIST OF THINGS TO DO IN A TRAVELLER'S ORDER: each venue six places further down,
    /// and a place of study or a visitors' office twenty
    nonisolated static func settled(_ acts: [Activity]) -> [Activity] {
        acts.enumerated().sorted { a, b in
            let ka = a.offset + push(a.element), kb = b.offset + push(b.element)
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
    }
    nonisolated static func push(_ a: Activity) -> Int {
        if isStudy(a.name) { return 20 }
        return isVenue(a.name, a.line) ? 6 : 0
    }
    /// a place of study or a visitors' office: not what a traveller comes for
    nonisolated static func isStudy(_ name: String) -> Bool {
        name.range(of: #"\b(university|universit[äéà]|universidad|universidade|college|school|academy|institute of technology|welcome cent(er|re)|visitor cent(er|re)|visitors' cent(er|re))\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
    nonisolated static func isVenue(_ name: String, _ line: String) -> Bool {
        if (name + " " + line).range(of: #"amphithea|roman|ancient|antique|historic"#, options: [.regularExpression, .caseInsensitive]) != nil { return false }
        return (name + " " + line).range(of: #"\b(stadium|stadio|estadio|estádio|stade|stadion|arena|sports venue|multisports venue|racecourse|race track|racetrack|circuit|aut[oó]dromo|speedway|ballpark)\b"#,
                                  options: [.regularExpression, .caseInsensitive]) != nil
    }
    /// a pass or a city card (,,): a ticket, not a thing to see or do
    nonisolated static func isTicket(_ name: String) -> Bool {
        // (and, one word)
        name.range(of: #"(\bpass|\bpasses|citypass|city ?card|\bcard)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// the activities' rows (name as the source writes it, cleaned; its Wikidata id; its line), in their order
    nonisolated static func activityRows(_ d: Data, _ things: Data?, town: String?, first: [String],
                                         near: (lat: Double, lon: Double, km: Double)? = nil) -> [(name: String, wd: String?, line: String)] {
        guard let all = try? JSONSerialization.jsonObject(with: d) as? [String: [[String: Any]]] else { return [] }
        // the country's things: Wikidata id -> (fame, place in the file)
        var fame: [String: (fame: Int, at: Int)] = [:]
        // each thing's own line (Wikidata's), for a listing whose words are only how to get there
        var wdLine: [String: String] = [:]
        if let td = things, let rows = try? JSONSerialization.jsonObject(with: td) as? [[Any]] {
            // (a sports ground after the rest of its tier: Rome's Olympic Stadium stood third)
            for (i, r) in rows.enumerated() where r.count > 6 {
                if let q = r[0] as? String, let l = r[6] as? String, !l.isEmpty, wdLine[q] == nil { wdLine[q] = l }
                if let q = r[0] as? String, let f = (r[5] as? NSNumber)?.intValue, fame[q] == nil {
                    let venue = isVenue(r[1] as? String ?? "", r[6] as? String ?? "")
                    fame[q] = (f, (venue ? 1_000_000 : 0) + i)
                }
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
        // (a town's own guide, then the guides whose listings' middle lies within its reach, the nearest first:
        // Brooklyn's and Manhattan's for New York)
        let around: [String] = {
            guard let town, let near else { return [] }
            return byCity.keys.filter { $0 != town }.compactMap { c -> (String, Double)? in
                let pts = (byCity[c] ?? []).compactMap { ($0["ll"] as? [NSNumber]).flatMap { $0.count == 2 ? ($0[0].doubleValue, $0[1].doubleValue) : nil } }
                guard !pts.isEmpty else { return nil }
                let la = pts.map(\.0).reduce(0, +) / Double(pts.count), lo = pts.map(\.1).reduce(0, +) / Double(pts.count)
                let dy = (la - near.lat) * 111.2, dx = (lo - near.lon) * 111.2 * cos(near.lat * .pi / 180)
                let km = (dx * dx + dy * dy).squareRoot()
                return km <= near.km ? (c, km) : nil
            }
            .sorted { $0.1 < $1.1 }.map(\.0)
        }()
        let cities = town.map { [$0] + around } ?? (first.filter { byCity[$0] != nil } + rest.filter { !wideOnes.contains($0) } + rest.filter { wideOnes.contains($0) })
        var seen = Set<String>()
        // ranks[r][c]: city c's rows of rank r with their place in the things' file
        typealias Row = (name: String, wd: String?, line: String)
        var ranks = [[[(at: Int, row: Row)]]](repeating: [[(at: Int, row: Row)]](repeating: [], count: cities.count), count: 10)
        var raw: [String: (desc: String, city: String)] = [:]
        for (ci, c) in cities.enumerated() {
            for l in byCity[c] ?? [] {
                guard let k = l["k"] as? String, k == "see" || k == "do", let n = l["n"] as? String else { continue }
                let q = l["wd"] as? String
                // (spelling corrected on the main thread afterwards, by its Wikidata label)
                let name = plain(n)
                guard !isTicket(name) else { continue }
                guard !name.isEmpty, !seen.contains(name.lowercased()), q.map({ !seen.contains($0) }) ?? true else { continue }
                seen.insert(name.lowercased())
                if let q { seen.insert(q) }
                let known = q.flatMap { fame[$0] }
                let r: Int
                if let known { r = (known.fame >= 3 ? 0 : known.fame == 2 ? 2 : 4) + (k == "see" ? 0 : 1) }
                else if q != nil || l["wp"] != nil { r = k == "see" ? 6 : 7 }
                else { r = k == "see" ? 8 : 9 }
                raw[name.lowercased()] = ((l["d"] as? String) ?? "", c)
                ranks[r][ci].append((known?.at ?? Int.max, (name: name, wd: q, line: "")))
            }
        }
        var out: [Row] = []
        for byCityRows in ranks {
            let lists = byCityRows.map { $0.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element.row) }
            // a town's: the rank whole; a country's: one from each city in turn (the first rows were all one city's)
            var i = 0
            while lists.contains(where: { i < $0.count }) {
                for list in lists where i < list.count { out.append(list[i]) }
                i += 1
            }
        }
        // the best 400 (five show, ten more a tap, the page's search goes through them), each line cleaned now
        return out.prefix(400).map { r in
            let w = raw[r.name.lowercased()] ?? ("", "")
            var desc = w.desc.isEmpty ? "" : plain(w.desc)
            if desc.count < 90, desc.range(of: #"\b(exit|station|lines? to|bus|metro|subway|take the|tram)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
               let l = r.wd.flatMap({ wdLine[$0] }) {
                desc = l.prefix(1).uppercased() + l.dropFirst()
            }
            let line = brief(town != nil || wideOnes.contains(w.city) ? desc : (desc.isEmpty ? w.city : "\(w.city) · \(desc)"), 112)
            return (name: r.name, wd: r.wd, line: line)
        }
    }

    /// "90" ->; the rest as they are written
    static func visa(_ v: String) -> String {
        if let d = Int(v) { return d < 0 ? "no entry" : "visa free for \(d) days" }
        return v.prefix(1).uppercased() + v.dropFirst()
    }
    /// a checked date as where it can be read, else as it is
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

    /// the source's HTML entities as the characters they stand for THE SOURCE'S SPELLING CORRECTED, never simplified
    /// (F147, the data rule): Wikivoyage writes where the name is Théâtre. A name with a Wikidata id takes the label
    /// our things carry for it when the two differ only in accents and case (Wikidata's is the checked spelling);
    /// others go through the table of corrections made by hand AN ACTIVITY, ITS NAME CORRECTED AND A GUIDE'S ASIDE
    /// MOVED UNDER IT: ran off its row as. The name is the name; the aside leads the line under it, where it still
    /// says something (,; 372 of 33,356 listings)
    static func activity(_ name: String, line: String, wd: String?) -> Activity {
        var t = corrected(name, wd: wd), l = line
        if t.hasSuffix(")"), let open = t.range(of: " (", options: .backwards), open.lowerBound > t.startIndex {
            var aside = String(t[t.index(open.lowerBound, offsetBy: 2)..<t.index(before: t.endIndex)]).trimmingCharacters(in: .whitespaces)
            t = String(t[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let c = aside.first, c.isLowercase { aside = c.uppercased() + aside.dropFirst() }
            if !aside.isEmpty, !l.localizedCaseInsensitiveContains(aside) { l = l.isEmpty ? aside : "\(aside) · \(l)" }
        }
        return Activity(name: t, line: l, wd: wd)
    }
    static func corrected(_ name: String, wd: String?) -> String {
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        if let wd, let label = ThingIndex.shared.hit(wd)?.name, label != name, fold(label) == fold(name) { return label }
        var t = name
        for (wrong, right) in fixes where t.contains(wrong) { t = t.replacingOccurrences(of: wrong, with: right) }
        // a name the source began in small letters  begins with its capital, as a name does; never an article's
        // elision ( is how the French write it)
        if let c = t.first, c.isLowercase, !t.hasPrefix("l'"), !t.hasPrefix("l\u{2019}"), !t.hasPrefix("d'") {
            t = c.uppercased() + t.dropFirst()
        }
        return t
    }
    /// our corrections over the source's text, word for word (added as they are found)
    static let fixes: [(String, String)] = [
        // (only whole spellings that are wrong wherever they appear: is that hotel's own name)
        ("Théatre", "Théâtre"),
    ]

    nonisolated(unsafe) static let namedMark = try? NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]{1,7});")
    nonisolated(unsafe) static let numberedMark = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);")

    /// `name`: the place the text is about, so a picture's caption left in front of it can be told from its first
    /// words THE GUIDES' DISAMBIGUATION LINES OFF THE FRONT:,,, at the start of the text are dropped
    nonisolated static func withoutHatnote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let heads = [#"^If you (were|are) looking for [^,.]*, (look|go|see) (here|there)[:.]?\s*"#,
                     #"^(For|For the|For other) [^.]{0,120}?, see [^.]*\.\s*"#,
                     #"^Not to be confused with [^.]*\.\s*"#,
                     #"^This (article|page) is about [^.]*\.\s*"#,
                     #"^See (the )?(main )?[^.]{0,80}? (article|page)( for [^.]*)?\.\s*"#]
        var changed = true
        while changed {
            changed = false
            for h in heads {
                if let r = t.range(of: h, options: [.regularExpression, .caseInsensitive]), r.lowerBound == t.startIndex {
                    t.removeSubrange(r); changed = true
                }
            }
        }
        return t.isEmpty ? s : t
    }

    /// a city's key: its GeoNames id, else its name
    nonisolated static func cityKey(_ cc: String, _ t: [String: Any], name: String) -> PlaceKey {
        if let gid = (t["gid"] as? NSNumber)?.intValue { return PlaceKey(.town, "\(cc)/\(gid)") }
        return PlaceKey(.town, "\(cc)/\(name)")
    }
    /// a part of a city, or a place that was (GeoNames' PPLX, PPLH, PPLQ, PPLW), not a city of its own: Quarto
    /// Oggiaro, a district of Milan, stood third among Lombardy's cities
    nonisolated static func notACity(_ t: [String: Any]) -> Bool {
        ["PPLX", "PPLH", "PPLQ", "PPLW"].contains(t["fc"] as? String ?? "")
    }

    /// A LINE WITH A HOLE IN IT CUT BEFORE THE HOLE: the guides' text lost what their templates said (,,), about 600
    /// times; a sentence with a word then a space then a mark is cut off with all after it, and a line left with
    /// nothing keeps only its place
    nonisolated static func mended(_ line: String) -> String {
        guard let re = holeMark, re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { return line }
        let parts = line.components(separatedBy: " \u{00B7} ")
        let head = parts.count > 1 ? parts[0] : nil
        let text = parts.count > 1 ? parts.dropFirst().joined(separator: " \u{00B7} ") : line
        var kept = ""
        for piece in text.split(separator: ". ", omittingEmptySubsequences: false).map(String.init) {
            let sentence = piece
            if re.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) != nil { break }
            kept += (kept.isEmpty ? "" : ". ") + sentence
        }
        if !kept.isEmpty, !kept.hasSuffix("."), !kept.hasSuffix("\u{2026}") { kept += "." }
        if let head { return kept.isEmpty ? head : head + " \u{00B7} " + kept }
        return kept
    }
    nonisolated private static let holeMark = try? NSRegularExpression(
        pattern: "\\b(?:a|an|the|and|of|is|are|was|were|to|in|by|from|with|as|at|on) [,.;:]|\\b(?:a|an|the)[,.;:]", options: [.caseInsensitive])

    nonisolated static func plain(_ s: String, name: String? = nil) -> String {
        var t = Self.withoutHatnote(s)
        for (e, c) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
                       ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"), ("&hellip;", "\u{2026}"), ("&rsquo;", "\u{2019}"),
                       ("&lsquo;", "\u{2018}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"), ("&eacute;", "é")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        // every other named mark HTML has (,; "&lrm;" is nothing seen)
        if t.contains("&"), let re = Self.namedMark {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let r = Range(m.range, in: t), let n = Range(m.range(at: 1), in: t), let c = HTMLEntities.character(String(t[n])) else { continue }
                t.replaceSubrange(r, with: c)
            }
        }
        // numbered ones
        if t.contains("&#"), let re = Self.numberedMark {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let r = Range(m.range, in: t), let hx = Range(m.range(at: 1), in: t), let num = Range(m.range(at: 2), in: t),
                      let v = UInt32(t[num], radix: t[hx].isEmpty ? 10 : 16), let u = Unicode.Scalar(v) else { continue }
                t.replaceSubrange(r, with: String(Character(u)))
            }
        }
        // a page's own marks that a decoded turns back into: never words
        if t.contains("<") {
            t = t.replacingOccurrences(of: "<maplink\\b[^>]*?\\btext=\"([^\"]*)\"[^>…]*(?:>(?:.*?</maplink>)?)?", with: "$1",
                                       options: [.regularExpression, .caseInsensitive])
            t = t.replacingOccurrences(of: "</?(?:big|small|span|b|i|u|em|strong|sup|sub|br|div|p|font|abbr|nowiki|maplink)\\b[^>]*>", with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        // editors' notes left in the source  are not text: taken out, and one left open runs to the end
        if t.contains("<!--") {
            t = t.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "(?s)<!--.*$", with: "", options: .regularExpression)
            t = t.trimmingCharacters(in: .whitespaces)
        }
        // what the source's dropped marks leave behind: an empty bracket, a picture's tail, a bracket opening on a
        // comma, a space before a comma
        if t.contains(" )") || t.contains("( ") || t.contains(" ,") || t.contains("px]]") {
            t = t.replacingOccurrences(of: "\\s*\\((?:\\p{Lu}[\\p{L} ]{1,24}:)?[\\s,;]*\\)", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\s*\\|?\\d+(?:x\\d+)?px\\]\\]", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\(\\s*,\\s*", with: "(", options: .regularExpression)
            t = t.replacingOccurrences(of: "(\\w) ,", with: "$1,", options: .regularExpression)
        }
        // A PICTURE'S MARKS LEFT IN THE TEXT. At the start: its options go, and its caption goes up to where the text
        // starts with its own name; with no such start the caption stays, so it never takes a real sentence with it.
        // Anywhere else: from its options to the end of its caption's sentence. A template  is never words.
        let o = "(?:thumb|thumbnail|frame|frameless|border|left|right|center|none|upright(?:=[0-9.]+)?|[0-9]+(?:x[0-9]+)?px)"
        let firstWord = String(t.drop(while: \.isWhitespace).prefix { $0 != " " && $0 != "|" })
        let pictureFirst = ["thumb", "thumbnail", "frame", "frameless", "border", "left", "right", "center", "none"].contains(firstWord)
            || firstWord.hasPrefix("upright") || firstWord.hasSuffix("px")
        if pictureFirst, let r = t.range(of: "^\\s*(?:\(o)\\|)*\(o)(?:\\||\\s)", options: .regularExpression) {
            t.removeSubrange(r)
            if let name, let start = Self.articleStart(t, name) { t.removeSubrange(t.startIndex ..< start) }
            t = t.trimmingCharacters(in: .whitespaces)
        }
        if t.contains("|") {
            t = t.replacingOccurrences(of: "\\s*(?:\(o)\\|)+\(o)?[^.|]*(?:\\.|$)", with: "", options: .regularExpression)
        }
        if t.contains("{{") {
            t = t.replacingOccurrences(of: "\\{\\{[^}]*\\}+\\s*", with: "", options: .regularExpression)
        }
        // A LINK OUT: its words, never its address
        if t.contains("[http") {
            t = t.replacingOccurrences(of: "\\[https?://\\S+\\s+([^\\]]+)\\]", with: "$1", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\[https?://\\S+\\]", with: "", options: .regularExpression)
        }
        let lead = String(t.prefix(450))
        let notes = lead.contains("redirects here") || lead.contains("This article") || lead.contains("This page")
            || t.drop(while: \.isWhitespace).hasPrefix("For ")
        if notes, let r = lead.range(of: "\"?[^\".]{1,14}\"? redirects here\\.|This (?:article|page) is about", options: .regularExpression) {
            t.removeSubrange(t.startIndex ..< r.lowerBound)
        }
        if !notes { t = t.trimmingCharacters(in: .whitespaces) }
        for _ in 0 ..< (notes ? 4 : 0) {
            t = t.trimmingCharacters(in: .whitespaces)
            if let r = t.range(of: "^\"?[^\".]{1,14}\"? redirects here\\.\\s*", options: .regularExpression)
                ?? t.range(of: "^This (?:article|page) is about[^.]*\\.\\s*", options: .regularExpression) {
                t.removeSubrange(r); continue
            }
            // (a full stop after a lone capital,, ends no sentence)
            if let r = t.range(of: "^For (?:the|a|an|other|information|more|details)\\b(?:[^.]|(?<=\\b[A-Z])\\.)*?\\bsee\\b(?:[^.]|(?<=\\b[A-Z])\\.)*(?<!\\b[A-Z])\\.\\s*",
                                options: .regularExpression) {
                if let name, let see = t.range(of: " see "), let st = Self.articleStart(t, name), st > see.lowerBound, st < r.upperBound {
                    t.removeSubrange(t.startIndex ..< st)
                } else {
                    t.removeSubrange(r)
                }
                continue
            }
            break
        }
        // a bracket opening on nothing, or closing on a space
        if t.contains("( ") || t.contains(" )") {
            t = t.replacingOccurrences(of: "\\(\\s*[;,]?\\s+", with: "(", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\s+\\)", with: ")", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\s*\\(\\)", with: "", options: .regularExpression)
        }
        // a picture's or link's closing marks left with nothing before them, and a link's opening ones with nothing
        // after: never words
        if t.contains("]]") || t.contains("[[") {
            t = t.replacingOccurrences(of: "^[\\s\\]|]+", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\[\\[|\\]\\]", with: "", options: .regularExpression)
        }
        // ITS NAME IN OTHER LANGUAGES before it says what it is (:;): a bracket in the opening words that names a
        // language  or is written in another script goes; one in plain English stays
        if let open = t.prefix(240).firstIndex(of: "(") {
            var out = String(t[..<open]), rest = Substring(t[open...]), cut = false
            while let o = rest.firstIndex(of: "("), rest.distance(from: rest.startIndex, to: o) < 240 - out.count,
                  let c = rest[o...].firstIndex(of: ")") {
                let inner = rest[rest.index(after: o) ..< c]
                let named = inner.range(of: "^\\p{Lu}[\\p{L} ]{1,24}:", options: .regularExpression) != nil
                let letters = inner.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                let other = letters.filter { $0.value > 0x24F }.count
                let foreign = other >= 2 || (!letters.isEmpty && other * 2 > letters.count)
                if named || foreign {
                    out += rest[..<o]
                    while out.hasSuffix(" ") { out.removeLast() }
                    rest = rest[rest.index(after: c)...]
                    cut = true
                } else {
                    out += rest[...c]
                    rest = rest[rest.index(after: c)...]
                }
            }
            if cut { t = out + rest }
        }
        if let name, !name.isEmpty, t.hasPrefix(name + ", ") {
            let after = t.dropFirst(name.count + 2)
            if ["is ", "are ", "was ", "were "].contains(where: { after.hasPrefix($0) }) { t = name + " " + after }
        }
        // A NOTE'S NUMBER LEFT STANDING: a raised figure that follows no word or number is the source's footnote
        // mark, never text ("km²" keeps its own)
        if t.unicodeScalars.contains(where: { "\u{00B9}\u{00B2}\u{00B3}\u{2070}\u{2074}\u{2075}\u{2076}\u{2077}\u{2078}\u{2079}".unicodeScalars.contains($0) }) {
            t = t.replacingOccurrences(of: "(^|(?<=[\\s(]))[\u{00B9}\u{00B2}\u{00B3}\u{2070}\u{2074}-\u{2079}]+\\s*", with: "", options: .regularExpression)
        }
        return t
    }

    /// a thing's own words from the country's guide listings: the listing with its Wikidata id, else the first with
    /// its name (any case and accents); only a description of some length (a line of directions is not one) the
    /// guide's article that lists a thing (by its Wikidata id), or nil WIKIPEDIA'S OPENING: English Wikipedia's first
    /// paragraph for a Wikidata item (its article's title from Wikidata, then the article's summary), else for its
    /// name where that article stands within 150 km of it (a World Heritage record has no article of its own:
    /// Angkor's and the Great Wall's are the place's), without the bracket of other names and sounds after its name;
    /// kept for the app's run, a miss as ""
    static var wikipedia: [String: String] = [:]
    static func wikipediaIntro(wd: String?, name: String, lat: Double, lon: Double) async -> String? {
        let key = (wd ?? "") + "|" + name
        if let had = wikipedia[key] { return had.isEmpty ? nil : had }
        var titles: [(String, Bool)] = []
        if let wd, wd.hasPrefix("Q") {
            var c = URLComponents(string: "https://www.wikidata.org/w/api.php")!
            c.queryItems = [.init(name: "action", value: "wbgetentities"), .init(name: "format", value: "json"), .init(name: "ids", value: wd),
                            .init(name: "props", value: "sitelinks"), .init(name: "sitefilter", value: "enwiki")]
            if let u = c.url, let (d, _) = try? await URLSession.shared.data(from: u),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let e = (j["entities"] as? [String: Any])?[wd] as? [String: Any],
               let t = ((e["sitelinks"] as? [String: Any])?["enwiki"] as? [String: Any])?["title"] as? String { titles.append((t, false)) }
        }
        if titles.isEmpty {
            titles.append((name, true))
            if name.hasPrefix("The ") { titles.append((String(name.dropFirst(4)), true)) }
        }
        for (title, check) in titles {
            guard let path = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
                    .replacingOccurrences(of: "/", with: "%2F"),
                  let su = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/" + path),
                  let (sd, _) = try? await URLSession.shared.data(from: su),
                  let sj = try? JSONSerialization.jsonObject(with: sd) as? [String: Any],
                  (sj["type"] as? String) == "standard", var x = sj["extract"] as? String, x.count > 60 else { continue }
            if check {
                guard let co = sj["coordinates"] as? [String: Any], let la = (co["lat"] as? NSNumber)?.doubleValue,
                      let lo = (co["lon"] as? NSNumber)?.doubleValue else { continue }
                let dy = (la - lat) * 111.2, dx = (lo - lon) * 111.2 * cos(lat * .pi / 180)
                guard dx * dx + dy * dy <= 150 * 150 else { continue }
            }
            // (the brackets in its first sentence that give other names, sounds or dates:)
            if let dot = x.range(of: ". ") {
                var head = String(x[..<dot.lowerBound])
                head = head.replacingOccurrences(of: #"\s*\([^()]*[:;/][^()]*\)"#, with: "", options: .regularExpression)
                x = head + x[dot.lowerBound...]
            }
            wikipedia[key] = x
            return x
        }
        wikipedia[key] = ""
        return nil
    }
    static func listingArticle(_ cc: String, wd: String?) async -> String? {
        guard let wd, case .ok(let d) = await Servers.data.file("listings/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: [[String: Any]]] else { return nil }
        return all.keys.sorted().first { k in (all[k] ?? []).contains { ($0["wd"] as? String) == wd } }
    }
    static func listingText(_ cc: String, wd: String?, name: String) async -> String? {
        guard case .ok(let d) = await Servers.data.file("listings/\(cc).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: [[String: Any]]] else { return nil }
        var byID: [String] = [], byName: [String] = []
        for k in all.keys.sorted() {
            for l in all[k] ?? [] {
                guard let t = l["d"] as? String, t.count > 60 else { continue }
                if let wd, (l["wd"] as? String) == wd { byID.append(t) }
                else if let n = l["n"] as? String, n.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { byName.append(t) }
            }
        }
        let short = name.replacingOccurrences(of: "^(Mount|Mt\\.?|Lake|The) ", with: "", options: .regularExpression)
        func score(_ t: String) -> Int { (t.localizedCaseInsensitiveContains(short) ? 10_000 : 0) + t.count }
        guard var best = (byID.isEmpty ? byName : byID).max(by: { score($0) < score($1) }) else { return nil }
        for (it, verb) in [("It is ", "is "), ("It's ", "is "), ("It was ", "was ")] where best.hasPrefix(it) {
            best = name + " " + verb + best.dropFirst(it.count)
        }
        return best
    }

    /// A PAGE'S PHOTO: the first of the place's pictures that is a photo of it as you would see it there; never the
    /// place seen from space (satellite, Landsat, MODIS, Sentinel, the Blue Marble), a map (locator, location, relief,
    /// topographic) or a drawing (any .svg). None left: the page has no photo.
    /// A COUNTRY'S BEST-KNOWN SIGHT'S PHOTO: its things, famous first, the first that is a sight of its own (a
    /// landmark, a mountain, water, nature or a spot) with a photo of it as you would see it there; never one on a
    /// border, a school, a stadium, an airport, a museum's building, a place of mourning, or a picture from above
    static func bestSightPhoto(_ cc: String) async -> String? {
        guard case .ok(let d) = await Servers.data.file(ThingStore.file(cc)),
              let rows = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { return nil }
        let skip = "border|between|universit|college|school|stadium|arena|airport|station|territory|museum|concentration|camp\\b|memorial|genocide|cemetery|prison|place name"
        let fromAbove = "\\b[0-9]+\\.[0-9]+[NSEW]\\b|^A[0-9]+\\.[0-9]+|aerial image|\\bISS\\b"
        for r in rows {
            guard r.count > 7, let kind = (r[2] as? NSNumber)?.intValue, (2...6).contains(kind),
                  let name = r[1] as? String, let file = r[7] as? String, !file.isEmpty else { continue }
            let what = ((r[6] as? String) ?? "") + " " + name
            if what.range(of: skip, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if file.range(of: fromAbove, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if let f = photo(file) { return f }
        }
        return nil
    }

    /// A CITY'S BEST KNOWN SIGHT WITH A PHOTO within 10 km (its landmarks, nature and spots, never a station or an
    /// airport): its id, for a city row whose own photo is a map or a montage. Once per city
    static var sightsNear: [PlaceKey: String] = [:]
    static func sightNear(_ r: Inside, cc: String) -> String? {
        if let k = sightsNear[r.key] { return k.isEmpty ? nil : k }
        guard let at = r.at, let all = ThingStore.shared.things(cc.lowercased()) else { return nil }
        let me = EqualEarth.unproject(SIMD2(Double(at.x), Double(at.y)))
        let k = cos(me.lat * .pi / 180)
        let near = all.filter { t in
            guard !t.photo.isEmpty, (2...6).contains(t.kind), t.fame >= 2 else { return false }
            let ll = EqualEarth.unproject(SIMD2(Double(t.at.x), Double(t.at.y)))
            let dx = (ll.lon - me.lon) * k * 111.2, dy = (ll.lat - me.lat) * 111.2
            return dx * dx + dy * dy < 100
        }
        let best = near.max { $0.fame < $1.fame }?.id ?? ""
        sightsNear[r.key] = best
        return best.isEmpty ? nil : best
    }
    /// A COUNTRY'S LANGUAGES as a traveller means them: the official ones, three at most, by their usual names (
    /// Mandarin, Greek, Kurdish), without sign languages or; with none, the most used one (Uruguay, Guadeloupe); and
    /// by hand where the record is wrong for a traveller (the United States' were its territories', Azerbaijan's its
    /// sign language, the United Kingdom's nations had none)
    static func languages(_ official: Any?, used: Any?, cc: String) -> String? {
        let byHand = ["us": "English", "az": "Azerbaijani", "gb-eng": "English", "gb-sct": "English, Scots, Scottish Gaelic",
                      "gb-wls": "Welsh, English", "gb-nir": "English, Irish",
                      "za": "Zulu, Xhosa, Afrikaans, English", "no": "Norwegian, Sámi", "ml": "Bambara, French",
                      "ch": "German, French, Italian, Romansh"]
        if let v = byHand[cc] { return v }
        let names = ["Putonghua": "Mandarin", "Modern Greek": "Greek", "Kurdish language": "Kurdish",
                     "North Korean standard language": "Korean", "British English": "English", "Standard Chinese": "Mandarin",
                     "Standard Taiwanese Mandarin": "Mandarin", "Jersey Legal French": "French", "Grenadian Creole English": "English",
                     "Standard Algerian Berber": "Berber", "Standard Moroccan Tamazight": "Tamazight"]
        func clean(_ any: Any?) -> [String] {
            let all = (any as? [String]) ?? (any as? String).map { [$0] } ?? []
            var seen = Set<String>()
            return all.compactMap { n -> String? in
                guard !n.localizedCaseInsensitiveContains("sign language"), !n.hasPrefix("languages of") else { return nil }
                return names[n] ?? n
            }.filter { seen.insert($0).inserted }
        }
        let own = clean(official)
        let list = own.isEmpty ? Array(clean(used).prefix(1)) : Array(own.prefix(3))
        return list.isEmpty ? nil : list.joined(separator: ", ")
    }
    /// a country by the map's own name ("China",), else the system's
    static func countryName(_ cc: String) -> String {
        if let w = AIContext.map?.world, let i = w.placeIndex[cc.lowercased()] ?? w.placeIndex[cc.uppercased()] { return w.places[i].n }
        return Locale(identifier: "en_GB").localizedString(forRegionCode: cc.uppercased()) ?? ""
    }
    static func photo(_ any: Any?) -> String? {
        let all = (any as? [String]) ?? (any as? String).map { [$0] } ?? []
        return all.first { n in
            !n.lowercased().hasSuffix(".svg") &&
            n.range(of: "satellite|\\bnasa\\b|\\besa[0-9]*\\b|cloud-free|copernicus|envisat|eumetsat|\\bterra\\b|landsat|\\bmodis\\b|sentinel-?[0-9]|blue marble|from space|\\biss[0-9]*\\b|\\borbit|relief|topograph|\\bsrtm\\b|locator|location map|\\bmap\\b|\\bkarte\\b|\\bcarte\\b|\\bharta\\b|\\bmapa\\b|\\bkaart\\b|montage|collage|\\bflag\\b|dannebrog|coat of arms|\\bemblem\\b|quarantine|cuarentena|covid|\\.png$|\\d+\\.\\d+\\s?[NSEW]\\b|\\b[ns][0-9]+[ew][0-9]+\\b|\\.a[0-9]{7}\\.|\\bwms\\b|labell?ed|\\beo\\b|[0-9]utc\\b|[0-9]px-(250|500)m\\b|(real|true)[ -]colou?r",
                    options: [.regularExpression, .caseInsensitive]) == nil
        }
    }

    /// where a text starts with its own name and then says what it is (,,) in its first 220 characters, any case and
    /// accents; nil when it never does
    nonisolated static func articleStart(_ t: String, _ name: String) -> String.Index? {
        let head = t.prefix(220)
        var from = head.startIndex
        while let r = head.range(of: name, options: [.caseInsensitive, .diacriticInsensitive], range: from ..< head.endIndex) {
            let after = head[r.upperBound...]
            if [" is", " was", " are", " has", " lies", " sits", " (", ","].contains(where: { after.hasPrefix($0) }) {
                return r.lowerBound
            }
            from = r.upperBound
        }
        return nil
    }

    /// a text that stops mid-sentence (a listing kept to its first few hundred characters:) back to its last whole
    /// sentence; one with no whole sentence stays as it is
    static func whole(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let last = t.last, !".!?\"\u{201D})".contains(last),
              let r = t.range(of: ". ", options: .backwards) else { return t }
        return String(t[..<r.lowerBound]) + "."
    }

    /// up to n characters, cut at a whole sentence (16.4: prose)
    static func cut(_ s: String, _ n: Int) -> String {
        guard s.count > n else { return s }
        let head = String(s.prefix(n))
        if let r = head.range(of: ". ", options: .backwards) { return String(head[..<r.lowerBound]) + "." }
        return head
    }
    /// A ROW'S LINE CUT TO WHAT TWO LINES HOLD, AT A SENTENCE OR A WORD (the row cut it itself, in the middle of a
    /// word:): whole sentences while they fit; a first sentence too long is cut at its last whole word, with the mark
    /// of more
    nonisolated static func brief(_ s: String, _ n: Int) -> String {
        guard s.count > n else { return s }
        let head = String(s.prefix(n))
        if let r = head.range(of: ". ", options: .backwards), head.distance(from: head.startIndex, to: r.lowerBound) >= n / 3 {
            return String(head[..<r.lowerBound]) + "."
        }
        guard let sp = head.lastIndex(of: " ") else { return head }
        return String(head[..<sp]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:\u{2013}\u{2014}-(")) + "\u{2026}"
    }
    /// a region's name without its level's word at its end, when that leaves a name
    nonisolated static func withoutLevel(_ name: String, _ word: String) -> String {
        let w = " " + word
        guard name.count > w.count + 1, name.lowercased().hasSuffix(w.lowercased()) else { return name }
        return String(name.dropLast(w.count))
    }
    static func big(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1f billion", v / 1e9) }
        if v >= 1_000_000 { return String(format: "%.1f million", v / 1e6) }
        return Int(v).formatted()
    }
    static func area(_ v: Any?, cc: String) -> String? {
        // (Norway without Svalbard and Jan Mayen, each a place of its own here: the Nordic Council's figure; the
        // Netherlands in Europe with its lakes and rivers, without the sea: Wikidata's gave its waters too)
        let own: [String: Double] = ["fr": 543_940, "mo": 33.3, "no": 323_781, "nl": 41_543]
        let all = (v as? [NSNumber])?.map(\.doubleValue) ?? (v as? NSNumber).map { [$0.doubleValue] } ?? []
        guard let a = own[cc] ?? all.max(), a > 0 else { return nil }
        return a < 10 ? String(format: "%.1f", a) : big(a)
    }
    /// THE TIME ZONES ROW: offsets only, each once, in order; more than three as a span. A place's zones are the time
    /// zone database's own for it (zone.tab, bundled as place-zones.json: 247 places, 417 zones; public domain), each
    /// as its clock stands now, so the row is right through summer time and when a country changes its clocks. The
    /// server's list is Wikidata's and was wrong where it mattered most: Russia read, Australia, the United States,
    /// India and Chile nothing, Bosnia its winter and summer offsets as two zones. It answers only for a place the
    /// database does not list (Kosovo, the parts of the United Kingdom): where that place's own zones are named by
    /// id, theirs; else the offsets written.
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
        let named = Set(own.map { ($0.secondsFromGMT() - Int($0.daylightSavingTimeOffset())) / 60 })
        let m = (named.isEmpty ? Set(every.compactMap(minutes)) : named).sorted()
        guard let first = m.first, let last = m.last else {
            // (words only, for a place the database does not list: the words)
            return every.isEmpty ? nil : (every.count == 1 ? "Time zone" : "Time zones", every.prefix(3).joined(separator: ", "))
        }
        if m.count == 1 { return ("Time zone", text(first)) }
        return ("Time zones", m.count <= 3 ? m.map(text).joined(separator: ", ") : "\(text(first)) to \(text(last))")
    }
    /// THE PLUGS BY THEIR LETTERS, as travellers and adapters name them. The server's words are Wikidata's labels, a
    /// mix of trade names and standards ( on Monaco's page). The British family's label alone is the old round-pin D
    /// (Monaco, Senegal, Madagascar, Chad: C, D, E... in the published lists); beside a British standard of its own
    /// it adds nothing.
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
    init(map: MapController, water: Water, page: PlacePageState.OnePage, top: Bool) {
        self.map = map; self.water = water; self.page = page; self.top = top
        let c = Self.rgb(page.country)
        _groundRGB = State(initialValue: c)
        _ground = State(initialValue: c.map(Self.color))
    }
    @State private var ground: [Color] = []
    /// the same colours as the shader takes them (sRGB, 0 to 1)
    @State private var groundRGB: [SIMD3<Double>] = []
    /// how far the page is pulled down past its top: the top photo grows into it, so above the page is always the photo
    @State private var pull: CGFloat = 0
    /// how far the page's end is below the screen's bottom (the white under the capsule gives way to the ground there)
    @State private var endBelow: CGFloat = .infinity
    @GestureState private var headerLive = false
    /// where the long lists start in the page (the head's search takes the page there), and the scroll's place
    @State private var listsY: CGFloat?
    @State private var spot = ScrollPosition(edge: .top)
    /// words have gone up under the head (the top edge's blur is on)
    @State private var under = false
    /// THE PAGE'S LOADING: the page shows once its facts and its top photo are both in (the facts waited for up to 8
    /// s, the photo up to 2.5 s after them), all at once; until then the ground and the logo. The logo only after a
    /// quarter second, so a quick page never flashes it.
    @State private var shown = false
    @State private var waited = false

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
            // what is under the page dims a little as it grows, and the page itself fades over its first and last
            // stretch, so it never lands as a small card on the map where it opened from (the camera may have moved
            // since)
            Color.black.opacity(0.12 * Double(p))
                .frame(width: L.W, height: L.H)
                .allowsHitTesting(false)
            content(key, L: L)
                .frame(width: L.W, height: L.H)
                // one scale for both sides (the way Apple's zoom grows a view): the page is never squeezed or
                // stretched on the way; the rounded rectangle growing from what opened it shows as much of it as fits
                .scaleEffect(r.width / L.W, anchor: .topLeading)
                .offset(x: r.minX, y: r.minY)
                .frame(width: L.W, height: L.H, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous).offset(x: r.minX, y: r.minY).size(r.size))
                .opacity(min(1, Double(p) / 0.3))
                .allowsHitTesting(top && page.p > 0.98)
                .onAppear { groundRGB = Self.rgb(page.country); ground = groundRGB.map(Self.color) }
                .onChange(of: page.country) { _, c in groundRGB = Self.rgb(c); ground = groundRGB.map(Self.color) }
        }
    }


    @ViewBuilder private func content(_ key: PlaceKey, L: Layout) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(spacing: 32) {
                // THE PHOTO AT THE TOP: the screen's whole width, from its top edge under the head, no box; its lower
                // part dissolves into the page's gradient (a gradient edge, never a cut), and the name stands on that
                // dissolve with the buttons straight under it. No flag over a photo.
                let hero = page.facts?.photo.flatMap { Self.commons($0, width: 1400) }
                if let u = hero {
                    // (wider than the page's margins by drawing past them: the margins of everything under it stay)
                    Color.clear
                        .frame(height: Self.heroH(L) + pull)
                        .overlay(alignment: .bottom) {
                            PagePhoto(url: u) { img in
                                // a town's or a thing's gradient is its photo's colour; a country's stays its flag's
                                guard key.kind != .country, let cg = img.cgImage else { return }
                                let c = Self.rgb(cg, photo: true)
                                if !c.isEmpty { groundRGB = c; withAnimation(Motion.quick) { ground = c.map(Self.color) } }
                            }
                            // DEPTH AS YOU SCROLL: the photo goes up at two thirds of the page's pace, so the words
                            // pass over a picture further away (pulled down, it grows instead)
                            .visualEffect { c, g in
                                let y = g.frame(in: .scrollView(axis: .vertical)).minY
                                return c.offset(y: y < 0 && !Motion.reduce ? -y * 0.35 : 0)
                            }
                        }
                        .clipped()
                        // its lower third dissolves into the page along a soft, uneven line, never a straight one (P05 §2)
                        // pulled down past the top, the photo grows up into the gap (never the ground above it);
                        // the dissolve keeps its own height at the bottom
                        .mask { VStack(spacing: 0) { Rectangle().frame(height: pull); PhotoDissolve(seed: page.name) } }
                        // the name on the photo's dissolve, inside its height (the buttons follow the photo at once)
                        .overlay(alignment: .bottom) { top(key, L: L, under: true).padding(.horizontal, 16).padding(.bottom, 8) }
                        .padding(.horizontal, -16)
                        .padding(.bottom, -12)
                        .padding(.top, -pull)
                } else {
                    top(key, L: L)
                }
                marking(key)
                if let f = page.facts, !f.prose.isEmpty { PageOpening(text: f.prose).id(f.prose) }
                if let f = page.facts, !f.rows.isEmpty { factsGrid(f.rows) }
                if let f = page.facts, !f.highlights.isEmpty { highlights(f.highlights, title: f.highlightsTitle, L: L).id("highlights") }
                // ("lists": where the head's search takes the page, the first of its long lists) (where the first
                // long list starts: the head's search brings its title under the field)
                if let f = page.facts, case let shown = Set(f.highlights.map(\.id)),
                   case let acts = f.activities.filter({ $0.wd.map { !shown.contains($0) } ?? true }), !acts.isEmpty {
                    ActivitiesList(all: acts, country: page.country)
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("page")).minY }) { listsY = $0 }
                }
                if let f = page.facts, !f.regions.isEmpty {
                    insideList("Regions", f.regions)
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("page")).minY }) { y in
                            if f.activities.isEmpty { listsY = y }
                        }
                }
                if let f = page.facts, !f.cities.isEmpty { insideList("Cities", f.cities) }
                VStack(alignment: .leading, spacing: 0) {
                    if MapSettingsStore.shared.value.ai { suggestions() }
                    VStack(alignment: .leading, spacing: 32) {
                        if MarkStore.shared.state(key).stamped { record(key) }
                        if page.facts != nil { SourcesRow(facts: page.facts!, kind: key.kind) }
                    }
                }
                Color.clear.frame(height: 140).id("end")
            }
            .padding(.horizontal, 16)
            .coordinateSpace(.named("page"))
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
        .scrollPosition($spot)
        #if DEBUG
        // (the test driver's `scrolltest <y>`: the page that far down)
        .onChange(of: ScrollTest.shared.y) { _, y in spot.scrollTo(y: y) }
        #endif
        .opacity(shown ? 1 : 0)
        // at the bottom, under the tabs' capsule, the rows fade out over the ground; none at the end
        .mask {
            let f = Double(min(1, max(0, (endBelow - 40) / 220)))
            VStack(spacing: 0) {
                Color.black
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(1 - f), location: 0.55),
                                       .init(color: .black.opacity(1 - f), location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: L.H - L.capsule.minY + 64)
            }
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
        // THE TOP EDGE (Apple's scroll edge under a bar; the system's never reaches this page, laid out over the whole
        // screen): once words go up under the head they blur and fade into it, never read through its glass
        .onScrollGeometryChange(for: CGFloat.self, of: { max(0, -($0.contentOffset.y + $0.contentInsets.top)) }) { _, v in
            if v != pull { pull = v }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height + $0.contentInsets.bottom - $0.contentOffset.y - $0.containerSize.height }) { _, v in
            let r = v.rounded()
            if r != endBelow { endBelow = r }
        }
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 4 }) { _, u in
            if u != under { withAnimation(Motion.quick) { under = u } }
        }
        }
        .overlay {
            if !shown {
                // (the logo's own animation: its light turning round the line, a turn in 2.4 s; still with Reduce Motion)
                TimelineView(.animation(paused: Motion.reduce || !waited)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    LogoMark(phase: LogoMark.rest + (Motion.reduce ? 0 : t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 2 * .pi))
                }
                    .frame(width: 88, height: 88)
                    .opacity(waited ? 1 : 0)
                    .transition(.identity)
                    .animation(Motion.quick, value: waited)
                    .accessibilityLabel("Loading")
            }
        }
        // (the facts' photo fetched before the page shows, so it never pops in over a page already laid out)
        .task(id: page.settled) {
            guard !shown, page.settled else { return }
            if let u = page.facts?.photo.flatMap({ Self.commons($0, width: 1400) }) {
                await withTaskGroup(of: Void.self) { g in
                    g.addTask { await PagePhoto.prefetch(u) }
                    g.addTask { try? await Task.sleep(for: .seconds(2.5)) }
                    await g.next()
                    g.cancelAll()
                }
            }
            withAnimation(Motion.chrome) { shown = true }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            waited = true
            try? await Task.sleep(for: .milliseconds(7750))
            if !shown { withAnimation(Motion.chrome) { shown = true } }
        }
        // THE GROUND: the app's moving gradient behind the whole page, in the flag's or the photo's colours, still
        // while the page scrolls over it; under it white, so the colours stay light behind the words
        .background {
            ZStack {
                Palette.white
                // (only the page on top moves: those under it are still, never running unseen)
                LivingField(custom: groundFour, paused: !top, saturation: 1.16, power: 2.0).opacity(0.7)
            }
            .ignoresSafeArea()
        }
    }

    /// THE TOP (16.4.1): a country's flag (4:3, 64 pt tall) centred 24 pt under the head's foot, its name under it; any
    /// other place its country's flag small and its line of what it is. Pulling it down closes the page (A16.1)
    /// `under`: the photo is above it, so it sits under the photo, not under the head
    private func top(_ key: PlaceKey, L: Layout, under: Bool = false) -> some View {
        VStack(spacing: 12) {
            if under {
                // (a photo above: no flag)
            } else if key.kind == .country, let f = Flags.wide(page.country) {
                f.resizable().aspectRatio(4 / 3, contentMode: .fit).frame(height: 64)
            } else if let f = Flags.square(page.country) {
                f.resizable().frame(width: 29, height: 29)
            }
            Text(page.name).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .risesIn(key.description)
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
                    .risesIn(key.description + "|" + page.what, delay: 0.08)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, under ? 0 : L.headBottom + 24)
        .contentShape(Rectangle())
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
        // a place in a country stamps its country too; a country's own page leaves it to the store (its territories'
        // sovereign rule)
        let cc = key.kind == .country ? "" : page.country
        return HStack(spacing: 12) {
            Button {
                Task {
                    if s.stamped { Feel.lift(); await MarkStore.shared.unstamp(key, name: page.name) }
                    else { Feel.stamp(); await MarkStore.shared.stamp(key, name: page.name, cc: cc) }
                }
            } label: {
                Text(s.stamped ? "Stamped" : "Stamp").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .glassEffect(s.stamped ? PageGlass.control.tint(Palette.lime) : PageGlass.control, in: .capsule)
            }
            Button {
                guard !s.stamped else { Feel.refuse(); return }
                Feel.tap()
                Task {
                    if s.wished { await MarkStore.shared.unwish(key, name: page.name) }
                    else { await MarkStore.shared.wish(key, name: page.name, cc: cc) }
                }
            } label: {
                Text("Wishlist").font(.body.weight(.semibold)).foregroundStyle(s.wished ? Palette.white : Palette.ink.opacity(s.stamped ? 0.5 : 1)).lineLimit(1)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .glassEffect(s.wished ? PageGlass.control.tint(Palette.blue) : PageGlass.control, in: .capsule)
            }
        }
        .buttonStyle(.plain)
    }

    /// HIGHLIGHTS (16.4.6): a sideways row, one card wide with the next peeking 24 pt; the photo fills the card's top
    /// (square corners, 16:10; real photos from Wikimedia Commons, credited in Sources), its name 17 pt semibold and one
    /// line 15 pt black 50% under it; the plus at the photo's top right wishes it
    private func highlights(_ all: [PlacePageState.Highlight], title: String = "Highlights", L: Layout) -> some View {
        let w = L.W - 32 - 24
        return VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                .risesWhenSeen()
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(all, id: \.self) { h in
                        highlightCard(h, w: w)
                            .scrollTransition(.interactive, axis: .horizontal) { c, phase in
                                c.rotation3DEffect(.degrees(Motion.reduce ? 0 : phase.value * -26), axis: (x: 0, y: 1, z: 0),
                                                   anchor: phase.value > 0 ? .leading : .trailing, perspective: 0.55)
                                    .scaleEffect(Motion.reduce ? 1 : 1 - abs(phase.value) * 0.07)
                            }
                    }
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
                .clipped()
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

    /// YOUR RECORD (16.4.10, only when stamped): big numbers in the Profile's style (64 pt rounded over 15 pt
    /// labels): the times; on a country its regions  and cities. The month waits for the visits' dates (Part 9.9)
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
                            .animation(Motion.quick, value: it.0)
                        Text(it.1).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// SUGGESTIONS: PageSuggestions
    private func suggestions() -> some View {
        let all = (page.facts?.regions ?? []) + (page.facts?.cities ?? [])
        return PageSuggestions(place: page.name, pageKey: page.key.description, all: all, country: page.country,
                               countryName: page.key.kind == .country ? page.name : (map.world?.placeIndex[page.country].map { map.world!.places[$0].n } ?? ""))
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

    /// the top photo's height: three quarters of the screen's width
    static func heroH(_ L: Layout) -> CGFloat { (L.W * 0.75).rounded() }

    /// the ground's four colours: the flag's or the photo's (cream with neither)
    private var groundFour: [SIMD3<Double>] {
        let c = groundRGB.isEmpty ? [Palette.named["cream"] ?? SIMD3(0.98, 0.96, 0.94)] : groundRGB
        return (0 ..< 4).map { c[$0 % c.count] }
    }

    /// a flag's colours: drawn small, each pixel the nearest of the twelve, the commonest first (white and ink left
    /// out where others exist, so the ground is the flag's own colour)
    static func colours(_ id: String) -> [Color] { rgb(id).map(color) }
    static func rgb(_ id: String) -> [SIMD3<Double>] {
        guard let ui = Flags.wideImage(id), let cg = ui.cgImage else { return [] }
        return rgb(cg)
    }
    static func color(_ v: SIMD3<Double>) -> Color { Color(red: v.x, green: v.y, blue: v.z) }
    /// a colour's hue in degrees (0 red, 120 green, 240 blue)
    static func hue(_ c: SIMD3<Double>) -> Double {
        let mx = c.max(), mn = c.min(), d = mx - mn
        guard d > 0.0001 else { return 0 }
        var h: Double
        if mx == c.x { h = (c.y - c.z) / d } else if mx == c.y { h = (c.z - c.x) / d + 2 } else { h = (c.x - c.y) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }
    static func colours(_ cg: CGImage, photo: Bool = false) -> [Color] { rgb(cg, photo: photo).map(color) }
    /// a picture's colours the same way: a flag's, or (a town's or a thing's page, P05 §2) its photo's
    /// `photo`: a photo's greys and beiges (stone, concrete, haze) are not its colour either
    static func rgb(_ cg: CGImage, photo: Bool = false) -> [SIMD3<Double>] {
        let entries = Array(Palette.named)
        let names: [(Color, SIMD3<Double>)] = entries.map { (Color(red: $0.value.x, green: $0.value.y, blue: $0.value.z), $0.value) }
        let w = photo ? 16 : 48, h = photo ? 12 : 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let neutral: Set<String> = ["white", "ink", "cream", "grey", "beige-dark"]
        var count = [Int](repeating: 0, count: names.count)
        for i in 0 ..< w * h {
            let c = SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) / 255
            var best = 0, bd = Double.infinity
            for (n, v) in names.enumerated() { let d = simd_length_squared(v.1 - c); if d < bd { bd = d; best = n } }
            // a flag's deep colour (navy, forest green, maroon) is a colour, not black or grey: the coloured one
            // nearest by hue angle
            if !photo, neutral.contains(entries[best].key), (c.max() - c.min()) > 0.18 {
                let hc = Self.hue(c)
                var hb = Double.infinity
                for (n, v) in names.enumerated() where !neutral.contains(entries[n].key) {
                    let d = abs(Self.hue(v.1) - hc), a = min(d, 360 - d)
                    if a < hb { hb = a; best = n }
                }
            }
            count[best] += 1
        }
        // (a flag's colour is one that covers at least a fortieth of it: an emblem's edge pixels are not)
        let least = photo ? 1 : max(1, w * h / 40)
        let order = count.indices.filter { count[$0] >= least }.sorted { count[$0] > count[$1] }
        let plain: Set<String> = photo ? neutral : ["white", "ink", "cream"]
        let coloured = order.filter { !plain.contains(entries[$0].key) }
        var use = coloured.isEmpty ? order : coloured
        // a flag of one colour and white (Switzerland, Japan, Canada): its white stays in, so the ground flows
        // between the two and is never one plain colour
        if !photo, coloured.count == 1, let w = order.first(where: { plain.contains(entries[$0].key) }) { use.append(w) }
        return use.prefix(3).map { names[$0].1 }
    }
}

/// one of a page's lists (16.4.8)
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
                .risesWhenSeen()
            let alike = all.count > 1 && Set(all.map(\.line)).count == 1
            let heads = Set(all.map { $0.line.components(separatedBy: " · ").first ?? "" })
            let sameHead = all.count > 1 && heads.count == 1 && all.contains { $0.line.contains(" · ") }
            let pictured = all.contains { !$0.photo.isEmpty }
            ForEach(rows.prefix(limit), id: \.self) { r in row(r, line: !alike, pictured: pictured, dropHead: sameHead).transition(.identity) }
            if rows.count > limit {
                Button { withAnimation(Motion.quick) { shown += 10 } } label: {
                    Text("Show more").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // (straight to its new place at the list's foot, under the cut, uncovered last as the list opens: moving
                // with the rows, it passed through the first new one's words)
                .transaction { $0.animation = nil }
            }
        }
        .clipShape(SideOpenRect())
        }
    }

    private func row(_ r: PlacePageState.Inside, line: Bool = true, pictured: Bool = false, dropHead: Bool = false) -> some View {
        let s = MarkStore.shared.state(r.key)
        // (asked again once the country's sights have come: Hyderabad was looked at before them and stayed bare)
        let _ = r.photo.isEmpty ? ThingStore.shared.version : 0
        return HStack(spacing: 12) {
            if pictured {
                SetPlaceThumb(own: r.photo, thing: r.photo.isEmpty && r.key.kind == .town ? (PlacePageState.sightNear(r, cc: country) ?? "") : "",
                              cc: country, flag: false)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.body).foregroundStyle(Palette.ink).lineLimit(2)
                let said = dropHead ? r.line.components(separatedBy: " · ").dropFirst().joined(separator: " · ") : r.line
                if line, !said.isEmpty { Text(PlacePageState.mended(said)).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(2) }
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
                // the plus; stamped, the same 44 pt circle filled lime
                if s.stamped {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .glassEffect(PageGlass.control.tint(Palette.lime), in: .circle)
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
            page.push(r.key, name: r.name, what: r.key.kind == .town ? (r.line.isEmpty ? "Town in \(countryName)" : "Town in \(r.line), \(countryName)") : "\(r.line.components(separatedBy: " · ").first ?? "Region") of \(countryName)",
                         country: country, code: r.code, from: frames.at[r.key] ?? .zero)
        }
    }
}

/// SOURCES (16.4.11, 16.6): a row at the page's foot; a tap raises the page's own sheet (16.6) to 50%, which lists
/// the sources the page drew on: Wikivoyage's text (CC BY-SA), Wikidata's and GeoNames' facts, each photo with its
/// author and licence from the server's Commons credits, and the governments whose advice is shown. (The visa rules'
/// and the climate figures' own sources are not recorded in the server's data yet, so they are not named.)
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

    /// THE LISTS' PHOTOS: each as (its place's name, its Commons file)
    static func listPhotos(_ facts: PlacePageState.Facts) -> [(String, String)] {
        var out: [(String, String)] = []
        for a in facts.activities.prefix(40) {
            if let wd = a.wd, let p = ThingStore.shared.thing(wd)?.thing.photo, let f = PlacePageState.photo(p) { out.append((a.name, f)) }
        }
        // (the first forty of each: past them a list is opened ten at a time, and Italy's 663 cities asked Commons for
        // every author at once)
        for r in facts.regions.prefix(40) + facts.cities.prefix(40) where !r.photo.isEmpty { out.append((r.name, r.photo)) }
        // (a city's photo borrowed from its best known sight, credited as that sight's)
        for r in facts.cities.prefix(40) where r.photo.isEmpty {
            if let wd = PlacePageState.sightsNear[r.key], !wd.isEmpty, let t = ThingStore.shared.thing(wd)?.thing,
               let f = PlacePageState.photo(t.photo) { out.append((t.name, f)) }
        }
        return out
    }

    /// the page's sources as (what, who and the licence) pairs, in the page's order
    static func lines(_ facts: PlacePageState.Facts, kind: PlaceKey.Kind, credits: [String: String], id: String = "") -> [(String, String)] {
        var out: [(String, String)] = []
        if facts.proseWikivoyage, !facts.prose.isEmpty { out.append(("Text", "Wikivoyage, CC BY-SA")) }
        else if facts.proseWikipedia, !facts.prose.isEmpty { out.append(("Text", "Wikipedia, CC BY-SA")) }
        else if !facts.prose.isEmpty { out.append(("Text", kind == .thing ? "Wikidata, CC0" : "Wikidata")) }
        if let f = facts.photo { out.append(("Photo", (credits[f] ?? f) + ", Wikimedia Commons")) }
        if !facts.rows.isEmpty { out.append(("Facts", kind == .town ? "GeoNames, CC BY 4.0" : kind == .thing ? "Wikidata, CC0" : "Wikidata")) }
        for h in facts.highlights {
            guard let f = h.photo else { continue }
            out.append(("Photo of \(h.name)", (credits[f] ?? f) + ", Wikimedia Commons"))
        }
        if !facts.activities.isEmpty { out.append(("Activities", "Wikivoyage, CC BY-SA")) }
        for (n, f) in listPhotos(facts) { out.append(("Photo of \(n)", (credits[f] ?? f) + ", Wikimedia Commons")) }
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
        for f in facts.highlights.compactMap(\.photo) + (facts.photo.map { [$0] } ?? []) + listPhotos(facts).map(\.1) {
            let sh = Self.shard(f)
            if shards[sh] == nil, case .ok(let d) = await Servers.data.file("credits/\(sh).json"),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { shards[sh] = j }
            if let c = shards[sh]?[f] as? [String: Any] {
                out[f] = [c["by"] as? String, c["lic"] as? String].compactMap { $0 }.joined(separator: ", ")
            }
        }
        // the rest (the World Heritage photos are not in the server's credits) from Commons itself: each file's author and
        // licence short name, in one request
        let missing = (facts.highlights.compactMap(\.photo) + (facts.photo.map { [$0] } ?? []) + listPhotos(facts).map(\.1)).filter { out[$0] == nil }
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
                // (an artist's wiki signature keeps its time stamp,: the name alone)
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

/// ONE GLASS ON A PAGE: everything glass on a place's page (the head's circles and search the whole time the page is
/// up, the marking block, the lists' fields and buttons) is the logically frosted glass, and never changes kind while
/// it moves
enum PageGlass {
    /// TRIAL: Apple's split as asked for, the navigation and the small controls clear, the rest frosted. Set to false
    /// and every glass is as before (all of it frosted while a page is up).
    static let clearControls = true
    /// a page's surfaces and its text fields (frosted, so typed words read over the page)
    static let on: SwiftUI.Glass = .regular
    /// a page's buttons and chips
    static var control: SwiftUI.Glass { clearControls ? .clear : .regular }
    /// the head's circles (search, the plus and its tools): navigation, clear on the map and over a page
    @MainActor static var head: SwiftUI.Glass { clearControls ? .clear : surface }
    /// the water and what rises out of it, search's results box, the map's word capsules: the system's own frosted
    /// glass everywhere, so it follows iOS 27's Liquid Glass slider and its legibility.
    @MainActor static var surface: SwiftUI.Glass { .regular }
}


/// ACTIVITIES (16.4.7; the word chosen, never): its own search field, the first five rows, then Show more; each row
/// its name and one line (Wikivoyage's words, credited in Sources)
private struct ActivitiesList: View {
    let all: [PlacePageState.Activity]
    /// the page's country (its things' photos, its flag where a sight has none)
    var country = ""
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
                .risesWhenSeen()
            // (the photos' column only where one of the rows shown has a photo)
            let pictured = rows.prefix(limit).contains { $0.wd.map { SetPlaceThumb.file(own: "", thing: $0) != nil } ?? false }
            ForEach(rows.prefix(limit), id: \.self) { a in
                HStack(alignment: .top, spacing: 12) {
                    if pictured { SetPlaceThumb(own: "", thing: a.wd ?? "", cc: country, flag: false) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                        if !a.line.isEmpty {
                            Text(PlacePageState.mended(a.line)).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(2)
                        }
                    }
                }
                // (one gap between rows whatever their lines: a row of one line was centred in 52 pt, so the row
                // after a two-line one sat 10 pt nearer than the others)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.identity)
            }
            if rows.count > limit {
                Button { withAnimation(Motion.quick) { shown += 10 } } label: {
                    Text("Show more").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // (straight to its new place at the list's foot, under the cut, uncovered last as the list opens: moving
                // with the rows, it passed through the first new one's words)
                .transaction { $0.animation = nil }
            }
        }
        .clipShape(SideOpenRect())
        }
    }
}

/// A PAGE'S PHOTO, fetched once and kept: scrolling a row of them back and forth shows each as it was, never blank
/// again while it reloads
struct PagePhoto: View {
    let url: URL
    /// told the picture once it is there (the page takes its colours from it)
    var onImage: ((UIImage) -> Void)? = nil
    @State private var image: UIImage?
    private static let kept: NSCache<NSURL, UIImage> = { let c = NSCache<NSURL, UIImage>(); c.countLimit = 120; return c }()

    var body: some View {
        // a kept photo is drawn at once, before any task runs
        if let i = image ?? Self.kept.object(forKey: url as NSURL) {
            // filling its frame around what the photo is of, not its middle: the frame centred on the photo's main
            // object as far as the photo reaches, its middle when there is none
            GeometryReader { g in
                // (-1: looked for and none found: its middle)
                let f = Self.focus[url].flatMap { $0.x < 0 ? nil : $0 } ?? CGPoint(x: 0.5, y: 0.5)
                let k = max(g.size.width / max(i.size.width, 1), g.size.height / max(i.size.height, 1))
                let w = i.size.width * k, h = i.size.height * k
                Image(uiImage: i).resizable()
                    .frame(width: w, height: h)
                    .offset(x: min(0, max(g.size.width - w, g.size.width / 2 - f.x * w)),
                            y: min(0, max(g.size.height - h, g.size.height / 2 - f.y * h)))
            }
            .onAppear { onImage?(i) }
        } else {
            Palette.cream.task(id: url) {
                await Self.prefetch(url)
                image = Self.kept.object(forKey: url as NSURL)
            }
        }
    }

    /// a photo already fetched and kept, or nil
    static func cached(_ url: URL) -> UIImage? { kept.object(forKey: url as NSURL) }
    /// the photo fetched, its upper part taken (a standing photo) and made ready to draw, kept for the page; one fetch
    /// per photo at a time (the page's wait and the photo itself asked for it together and it came down twice)
    private static var fetching: [URL: Task<Void, Never>] = [:]
    /// `focus` false (a list's 44 pt thumbnail, drawn filled from its middle): no Vision, the photo kept as fetched
    static func prefetch(_ url: URL, focus wantFocus: Bool = true) async {
        guard kept.object(forKey: url as NSURL) == nil else { return }
        if let t = fetching[url] { await t.value; return }
        let t = Task {
            let file = disk(url)
            if let d = try? Data(contentsOf: file), let i = UIImage(data: d) {
                if wantFocus, keptFocus(url) == nil, let cg = i.cgImage {
                    focus[url] = await Self.mainObjectQueued(cg) ?? CGPoint(x: -1, y: -1)
                }
                kept.setObject(await i.byPreparingForDisplay() ?? i, forKey: url as NSURL)
                return
            }
            guard let (d, _) = try? await URLSession.shared.data(from: url), let i0 = UIImage(data: d) else { return }
            let whole: CGPoint? = if wantFocus, let cg0 = i0.cgImage { await Self.mainObjectQueued(cg0) } else { nil }
            let i = upper(i0, around: whole)
            if wantFocus, let cg = i.cgImage { focus[url] = await Self.mainObjectQueued(cg) ?? CGPoint(x: -1, y: -1) }
            let ready = await i.byPreparingForDisplay() ?? i
            kept.setObject(ready, forKey: url as NSURL)
            if let jpg = i.jpegData(compressionQuality: 0.85) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? jpg.write(to: file, options: .atomic)
            }
        }
        fetching[url] = t
        await t.value
        fetching[url] = nil
    }
}

extension PagePhoto {
    /// where a page photo is kept on the phone the photos kept before "-2", cleared once per launch
    private static var oldGone = false
    static func disk(_ url: URL) -> URL {
        var h: UInt64 = 14695981039346656037
        for b in url.absoluteString.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        if !oldGone { oldGone = true; try? FileManager.default.removeItem(at: caches.appendingPathComponent("page-photos")) }
        let dir = caches.appendingPathComponent("page-photos-2")
        return dir.appendingPathComponent(String(h, radix: 16) + ".jpg")
    }

    /// each photo's main object's middle (0 to 1 from its top left), found once and kept with the photos
    static var focus: [URL: CGPoint] = [:] { didSet { saveFocusSoon() } }
    private static var focusLoaded = false
    private static var focusSaving = false
    private static var focusFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("page-photos-2/focus.json")
    }
    /// the kept answers, read once (a photo's own is looked up before Vision is asked)
    static func keptFocus(_ url: URL) -> CGPoint?? {
        if !focusLoaded {
            focusLoaded = true
            if let d = try? Data(contentsOf: focusFile), let m = try? JSONDecoder().decode([String: [Double]].self, from: d) {
                var f: [URL: CGPoint] = [:]
                for (k, v) in m { if let u = URL(string: k) { f[u] = v.count == 2 ? CGPoint(x: v[0], y: v[1]) : CGPoint(x: -1, y: -1) } }
                focusSaving = true; focus.merge(f) { a, _ in a }; focusSaving = false
            }
        }
        guard let p = focus[url] else { return nil }
        return p.x < 0 ? .some(nil) : .some(p)
    }
    private static func saveFocusSoon() {
        guard !focusSaving else { return }
        focusSaving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            focusSaving = false
            let m = Dictionary(uniqueKeysWithValues: focus.map { ($0.key.absoluteString, $0.value.x < 0 ? [] : [Double($0.value.x), Double($0.value.y)]) })
            if let d = try? JSONEncoder().encode(m) {
                try? FileManager.default.createDirectory(at: focusFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                do { try d.write(to: focusFile, options: .atomic) } catch { NSLog("wya focus not kept: %@", "\(error)") }
            }
        }
    }
    /// A PHOTO'S MAIN OBJECT, as Vision finds it (objectness: a building, a statue, a peak; nil for a view with none,
    /// or one it is unsure of). Its middle, from the top left. VISION ON A QUEUE OF ITS OWN, one photo at a time
    private static let vision = DispatchQueue(label: "wya.page-photo-vision", qos: .utility)
    static func mainObjectQueued(_ cg: CGImage) async -> CGPoint? {
        await withCheckedContinuation { c in vision.async { c.resume(returning: mainObject(cg)) } }
    }
    nonisolated static func mainObject(_ cg: CGImage) -> CGPoint? {
        // (the simulator cannot run it,, and there it may never answer)
        #if targetEnvironment(simulator)
        return nil
        #else
        let r = VNGenerateObjectnessBasedSaliencyImageRequest()
        // (the simulator cannot run it,: there every photo keeps its middle)
        try? VNImageRequestHandler(cgImage: cg).perform([r])
        guard let o = (r.results?.first)?.salientObjects?
                .filter({ $0.confidence >= 0.3 && $0.boundingBox.width * $0.boundingBox.height >= 0.02 })
                .max(by: { $0.confidence < $1.confidence }) else { return nil }
        return CGPoint(x: o.boundingBox.midX, y: 1 - o.boundingBox.midY)
        #endif
    }

    /// A STANDING PHOTO'S UPPER PART: a square from just under its top, where a mountain, a tower or a face is; a
    /// lying photo as it is
    static func upper(_ i: UIImage, around: CGPoint? = nil) -> UIImage {
        guard i.imageOrientation == .up, let cg = i.cgImage, cg.height > cg.width else { return i }
        let w = cg.width
        let top = around.map { max(0, min(cg.height - w, Int($0.y * CGFloat(cg.height)) - w / 2)) } ?? cg.height / 20
        guard let c = cg.cropping(to: CGRect(x: 0, y: top, width: w, height: min(w, cg.height - top))) else { return i }
        return UIImage(cgImage: c, scale: i.scale, orientation: i.imageOrientation)
    }
}

/// A PHOTO'S DISSOLVE INTO ITS PAGE (P05 §2): solid down to its last third, then an uneven edge (a slow wave, the same
/// for a place every time) blurred wide, so the photo melts into the gradient under it with no straight line anywhere
struct PhotoDissolve: View {
    let seed: String
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            // (the wave's phase and size from the place's name: each page its own edge, the same each time it opens)
            let n = Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF })
            let ph = n.truncatingRemainder(dividingBy: 6.283), amp = h * (0.05 + (n.truncatingRemainder(dividingBy: 7)) / 7 * 0.04)
            Path { p in
                let base = h * 0.74
                // (drawn past the top and sides, so the blur softens only the lower edge)
                let out = h * 0.3
                p.move(to: CGPoint(x: -out, y: -out))
                p.addLine(to: CGPoint(x: w + out, y: -out))
                p.addLine(to: CGPoint(x: w + out, y: base))
                for i in stride(from: 40, through: 0, by: -1) {
                    let x = -out + (w + 2 * out) * CGFloat(i) / 40
                    let t = Double(i) / 40 * 6.283
                    let y = base + amp * CGFloat(sin(t * 1.3 + ph) * 0.6 + sin(t * 2.7 + ph * 1.7) * 0.4)
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.closeSubpath()
            }
            .fill(.black)
            .blur(radius: h * 0.09)
        }
    }
}


/// SUGGESTIONS ON A PLACE'S PAGE. When the section comes into view, the AI picks up to three of the page's own
/// regions and cities you haven't stamped, each with one line on why it suits you; a pick opens its page as its row
/// does. Nothing it can't stand behind: fewer picks, or none, and the section stays as it was. Kept for a week per
/// page, asked again once your stamps change.
private struct PageSuggestions: View {
    let place: String
    let pageKey: String
    let all: [PlacePageState.Inside]
    let country: String
    let countryName: String
    @State private var picks: [(PlacePageState.Inside, String)] = []
    @State private var asked = false
    @State private var seen = false
    @State private var frame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 0)
            if !picks.isEmpty {
                Text("Suggestions").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("Based on your passport and history").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                VStack(alignment: .leading, spacing: 0) {
                    let pictured = picks.contains { !$0.0.photo.isEmpty }
                    ForEach(picks, id: \.0.key) { r, why in
                        HStack(alignment: .top, spacing: 12) {
                            if pictured { SetPlaceThumb(own: r.photo, thing: "", cc: country, flag: false) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                                Text(why).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                        .onTapGesture { open(r) }
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, picks.isEmpty ? 0 : 32)
        // asked once it is on screen (and again if the page's places come after it was first seen)
        .onGeometryChange(for: Bool.self) { g in
            let f = g.frame(in: .global)
            return f.minY < UIScreen.main.bounds.height && f.maxY > 0
        } action: { on in seen = on; if on { load() } }
        .onChange(of: all.count) { _, _ in if seen { load() } }
    }

    private func open(_ r: PlacePageState.Inside) {
        Feel.tap()
        PlacePageState.shared.push(r.key, name: r.name,
            what: r.key.kind == .town ? (r.line.isEmpty ? "Town in \(countryName)" : "Town in \(r.line), \(countryName)")
                : "\(r.line.components(separatedBy: " · ").first ?? "Region") of \(countryName)",
            country: country, code: r.code, from: frame)
    }

    private func load() {
        guard !asked else { return }
        let open = all.filter { !MarkStore.shared.state($0.key).stamped }
        #if DEBUG
        NSLog("wya suggestions load %@ all %d open %d", pageKey, all.count, open.count)
        #endif
        guard open.count >= 2 else { return }
        asked = true
        let stampedN = MarkStore.shared.marks.values.filter(\.stamped).count
        let byName = Dictionary(open.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        func show(_ ps: [AIService.Pick]) {
            let rows = ps.compactMap { p in byName[p.name.lowercased()].map { ($0, p.why) } }
            withAnimation(Motion.chrome) { picks = rows }
        }
        if let kept = SuggestionsCache.get(pageKey, stamped: stampedN) { show(kept); return }
        let names = Array(open.prefix(60).map(\.name))
        Task {
            let r = await AIService.suggest(place: place, from: names, context: AIContext.current())
            if case .success(let ps) = r {
                SuggestionsCache.put(pageKey, stamped: stampedN, ps)
                show(ps)
            }
        }
    }
}

/// what a page's suggestions were, kept on the phone for a week (asked again when your stamps change)
@MainActor
enum SuggestionsCache {
    struct Entry: Codable { var stamped: Int; var at: Date; var picks: [AIService.Pick] }
    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("suggestions.json")
    }
    private static var all: [String: Entry] = {
        guard let u = url, let d = try? Data(contentsOf: u) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: d)) ?? [:]
    }()
    static func get(_ key: String, stamped: Int) -> [AIService.Pick]? {
        guard let e = all[key], e.stamped == stamped, Date().timeIntervalSince(e.at) < 7 * 86400 else { return nil }
        return e.picks
    }
    static func put(_ key: String, stamped: Int, _ picks: [AIService.Pick]) {
        all[key] = Entry(stamped: stamped, at: Date(), picks: picks)
        if let u = url, let d = try? JSONEncoder().encode(all) { try? d.write(to: u, options: .atomic) }
    }
}


/// A PAGE'S OPENING WORDS: its first sentences, about four lines, and "More" in the half ink after them; a tap lays
/// the rest out in place, the page under it moving down to make room
struct PageOpening: View {
    let text: String
    @State private var open = false

    var body: some View {
        let short = PlacePageState.brief(text, 240)
        let more = !open && short.count < text.count
        (Text(more ? short : text).foregroundStyle(Palette.ink)
            + Text(more ? "  More" : "").foregroundStyle(Palette.ink.opacity(0.5)))
            .font(.body)
            .contentTransition(.identity)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipShape(SideOpenRect())
            .contentShape(Rectangle())
            .onTapGesture {
                guard more else { return }
                Feel.tap()
                withAnimation(Motion.quick) { open = true }
            }
            .accessibilityAddTraits(more ? .isButton : [])
            .accessibilityHint(more ? "Shows the rest" : "")
    }
}

/// a rectangle cut at the top and bottom only: open to the sides, so a row's glass circle and its light are never cut
struct SideOpenRect: Shape {
    func path(in r: CGRect) -> Path { Path(r.insetBy(dx: -80, dy: 0)) }
}

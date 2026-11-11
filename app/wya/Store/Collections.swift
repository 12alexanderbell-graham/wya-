import Foundation
import simd

/// COLLECTIONS (7.2, D7): named lists people tick off, each from its authoritative source, read once from the data server
/// (`native/collections/collections-2.wyco`). Each item is a place (a thing's key, `m:wd:Q…`) with its point; an event
/// collection's items are dated stops ("12 Jul 2026 · Silverstone"). Only the easy ones for now (29 Oct 20:30:
///).
@MainActor
@Observable
final class CollectionStore {
    static let shared = CollectionStore()
    struct Item: Hashable {
        let id: String
        let name: String
        let cc: String
        let at: SIMD2<Float>
        /// an event stop's day ("2026-07-05") and its name ("British Grand Prix"), or ""
        let date: String
        let label: String
        /// how well known, 0-3 (which of a long list's places show first, far out); 9 in a short list: all at once
        var fame: Int = 9
        /// every country it is in (a site shared by countries is each one's)
        var ccs: [String] = []
        /// its kind within its set (a sea: "ocean", "sea", "gulf", "strait"; a World Heritage site: "cultural" ...), or ""
        var type = ""
        /// its key when it is not a thing (a capital is its town, "t:fr/2988507": one stamp for both)
        var own: String? = nil
        /// its name on the map: a list's long official name up to its first comma, colon or bracket; its card and
        /// page say it whole
        var short: String {
            guard name.count > 30 else { return name }
            let cut = name.firstIndex { ",:(–".contains($0) } ?? name.endIndex
            let head = name[..<cut].trimmingCharacters(in: .whitespaces)
            return head.count >= 8 ? head : name
        }
        var key: PlaceKey { own.flatMap { PlaceKey($0) } ?? PlaceKey(.thing, "wd:" + id) }
    }
    struct Collection: Hashable {
        let id: String
        let title: String
        /// "world", or a country's id its places are all in
        let scope: String
        let event: Bool
        let source: String
        /// its places that have a point (the map's marks)
        let items: [Item]
        /// its places with no point of their own (a list of sites spread over a country): counted, not on the map
        var offMap = 0
        /// those places' countries, one list each
        var unmapped: [[String]] = []
        /// its places' own shapes' file (an area set: seas, ranges), or nil
        var shapes: String? = nil
        /// its row's place in Places' menu (nil: not a row)
        var menu: Int? = nil
        /// how it is cut down by kind of the same thing: [kind, its name] (seas: Oceans, Seas, Gulfs and bays, Straits)
        var types: [[String]] = []
        /// which cut of which set this is ("seas|ocean|", "world-heritage||it"): one name per list of places
        var tag: String = ""
        /// how many it lists
        var total: Int { items.count + offMap }
    }
    private(set) var all: [Collection] = []
    private(set) var ready = false
    @ObservationIgnored private var loading = false

    func collection(_ id: String) -> Collection? { all.first { $0.id == id } }

    // MARK: PLACES' SETS (Places is the map and Regions again with real named things; first comes the pick
    // of what to look at, tallest mountains, seas, national parks, and then within it a narrowing, national parks in
    // one country). A set is a real list with its own name and total: the towns (the world's towns as
    // their own shapes, Towns.swift), then every collection read from the data server (World Heritage as UNESCO lists it,
    // Formula 1's season). Our twelve kinds are never a set and never shown: they file things, and a place of your own.
    /// the towns' set (not a collection: the towns' own files and shapes)
    static let towns = "towns"
    /// the menu, in its order: the towns, then the lists that last (World Heritage), then the events (a season)
    var menu: [String] { [Self.towns] + all.filter { $0.menu != nil }.sorted { ($0.menu ?? 0) < ($1.menu ?? 0) }.map(\.id) }
    func title(_ id: String) -> String { id == Self.towns ? "Cities" : collection(id)?.title ?? "" }
    /// the capitals (the cities' one kind: every national capital, each keyed as its town)
    static let capitals = "capitals"
    /// the cities people know (Cities' marks far out, where no town's own shape can show; each keyed as its town)
    static let famousCities = "famouscities"
    /// A SET'S KINDS (step two cuts the same thing down, seas of one type): [kind, its name]
    func types(_ id: String) -> [[String]] {
        if id == Self.towns { return collection(Self.capitals) == nil ? [] : [[Self.capitals, "Capitals"]] }
        return collection(id)?.types ?? []
    }
    /// a set cut down to one of its kinds, named as the kind ("Oceans"); the whole set for no kind
    func typed(_ id: String, _ type: String?) -> Collection? {
        guard let c = collection(id) else { return nil }
        guard let type, let name = c.types.first(where: { $0.first == type })?.last else { return c }
        let key = id + "|" + type
        if let t = cut[key] { return t }
        let t = Collection(id: c.id, title: name, scope: c.scope, event: c.event, source: c.source,
                           items: c.items.filter { $0.type == type }, shapes: c.shapes, tag: key + "|")
        cut[key] = t
        return t
    }
    @ObservationIgnored private var cut: [String: Collection] = [:]
    /// a list's places' ids (kept per list: the map asks every frame)
    func ids(_ c: Collection) -> Set<String> {
        if let s = idSets[c.tag] { return s }
        let s = Set(c.items.map(\.id))
        idSets[c.tag] = s
        return s
    }
    @ObservationIgnored private var idSets: [String: Set<String>] = [:]
    /// A SET NARROWED TO A COUNTRY: its places there (a place shared by countries is each one's), kept per set and country
    /// (`inside`: is a map point in that country; a shared site whose point lies in another of its countries is counted
    /// there and not marked out in the blue beside this one)
    func narrowed(_ id: String, type: String? = nil, cc: String, inside: (SIMD2<Float>) -> Bool) -> Collection? {
        let key = id + "|" + (type ?? "") + "|" + cc
        if let c = narrow[key] { return c }
        guard let c = typed(id, type) else { return nil }
        let mine = c.items.filter { $0.ccs.contains(cc) }
        let here = mine.filter { $0.ccs.count == 1 || inside($0.at) }
        let off = c.unmapped.filter { $0.contains(cc) }
        let n = Collection(id: c.id, title: c.title, scope: cc, event: c.event, source: c.source,
                           items: here, offMap: off.count + mine.count - here.count, unmapped: off, shapes: c.shapes, tag: key)
        narrow[key] = n
        return n
    }
    @ObservationIgnored private var narrow: [String: Collection] = [:]

    /// A LONG LIST'S BEST KNOWN (the whole world on screen with no country open: 3,333 national parks or 1,274 World
    /// Heritage sites are a black mass over Europe there): its first 150 (every list is kept best known first, by how
    /// many Wikipedia languages write about a place) and every one that is yours; the same for every long list (fame 3
    /// alone left 450 World Heritage sites, still a blot). Kept per list and per change of marks
    func known(_ c: Collection) -> Collection {
        let key = c.tag + "|known|\(MarkStore.shared.changes)"
        if let k = knownCut, k.key == key { return k.list }
        let items = c.items.enumerated().filter { n, it in
            if n < Self.bestKnown { return true }
            let s = MarkStore.shared.state(it.key)
            return s.stamped || s.wished
        }.map(\.element)
        let list = Collection(id: c.id, title: c.title, scope: c.scope, event: c.event, source: c.source,
                              items: items, offMap: c.offMap, unmapped: c.unmapped, shapes: c.shapes,
                              // (the tag says how many, so what is kept per list, its ids and its names' plan, is made again when one of yours joins)
                              tag: c.tag + "|known|\(items.count)")
        knownCut = (key, list)
        return list
    }
    @ObservationIgnored private var knownCut: (key: String, list: Collection)?

    /// THE SETS' OWN PLACES BY NAME (Places' search): the places of the menu's sets whose name, or a word of it, starts
    /// with what was typed ("yellowst" Yellowstone National Park, "baikal" Lake Baikal, "kili" Mount Kilimanjaro: the
    /// things' index holds none of the three). A name that starts with it before one that has it further in, the best
    /// known first, the set looked at first among equals ("taj" is the Taj Mahal with Mountain peaks up too); a place
    /// in two sets once.
    struct Found: Hashable { let list: String; let item: Item; var key: String { list + "|" + item.id } }
    func find(_ query: String, first: String?, limit: Int = 4) -> [Found] {
        let q = query.trimmingCharacters(in: .whitespaces).townFolded
        guard ready, q.count >= 2 else { return [] }
        if let l = lastFind, l.q == q, l.first == first { return l.hits }
        let word = " " + q
        var hits: [(Found, Int, Bool, Int)] = []   // found, fame (and the set looked at, and a set of shapes), starts with it, its place in its list
        for id in menu {
            guard let c = collection(id) else { continue }
            let names = foldedNames[id] ?? {
                let n = c.items.map(\.name.townFolded)
                foldedNames[id] = n
                return n
            }()
            for (n, it) in c.items.enumerated() {
                let starts = names[n].hasPrefix(q)
                guard starts || names[n].contains(word) else { continue }
                // (a place in two sets is found in the one that has its shape: Lake Baikal as the lake, not as a
                // World Heritage point in the middle of its water)
                hits.append((Found(list: id, item: it), min(3, it.fame) * 4 + (id == first ? 2 : 0) + (c.shapes != nil ? 1 : 0), starts, n))
            }
        }
        hits.sort { a, b in a.2 != b.2 ? a.2 : a.1 != b.1 ? a.1 > b.1 : a.3 < b.3 }
        var seen = Set<String>(), out: [Found] = []
        for h in hits where seen.insert(h.0.item.id).inserted {
            out.append(h.0)
            if out.count == limit { break }
        }
        lastFind = (q, first, out)
        return out
    }
    @ObservationIgnored private var foldedNames: [String: [String]] = [:]
    @ObservationIgnored private var lastFind: (q: String, first: String?, hits: [Found])?

    /// A LIST ON A CONTINENT (the rest of the world is one flat blue there, and a mark out on the blue is nobody's): its
    /// places in that continent's countries, the list's scope the continent's name. A list of places that are no
    /// country's (seas, ranges) is not cut: nil. Kept per list and continent
    func within(_ c: Collection, continent k: String, has: (String) -> Bool) -> Collection? {
        let key = c.tag + "|in|" + k
        if let x = contCuts[key] { return x }
        var list: Collection?
        if c.items.filter({ !$0.ccs.isEmpty }).count * 2 > c.items.count {
            let off = c.unmapped.filter { $0.contains(where: has) }
            list = Collection(id: c.id, title: c.title, scope: k, event: c.event, source: c.source,
                              items: c.items.filter { $0.ccs.contains(where: has) }, offMap: off.count, unmapped: off,
                              shapes: c.shapes, tag: key)
        }
        contCuts[key] = .some(list)
        return list
    }
    @ObservationIgnored private var contCuts: [String: Collection?] = [:]
    /// how long a list is before only its best known show far out
    static let longList = 600
    /// how many of a long list show with the whole world on screen
    static let bestKnown = 150

    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .utility) {
            var out: [Collection] = []
            // (collections-4 has World Heritage, its best known first; the older file if the server still holds only that)
            var data: Data?
            for f in ["native/collections/collections-13.wyco", "native/collections/collections-12.wyco", "native/collections/collections-11.wyco", "native/collections/collections-9.wyco", "native/collections/collections-8.wyco", "native/collections/collections-5.wyco", "native/collections/collections-2.wyco"] where data == nil {
                if case .ok(let d) = await Servers.data.file(f) { data = d }
            }
            if let d = data, let raw = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                for c in raw {
                    guard let id = c["id"] as? String, let t = c["title"] as? String, let items = c["items"] as? [[String: Any]] else { continue }
                    // (a short list's places all show at once; a long one's by how well known they are; an area set's
                    // each by its own size, TownNames)
                    let long = items.count > 60
                    var off: [[String]] = []
                    let its: [Item] = items.compactMap { i in
                        guard let q = i["q"] as? String, let n = i["n"] as? String else { return nil }
                        let cc = (i["cc"] as? String ?? "").lowercased()
                        let ccs = (i["ccs"] as? [String])?.map { $0.lowercased() } ?? [cc]
                        guard let ll = i["ll"] as? [NSNumber], ll.count == 2 else { off.append(ccs); return nil }
                        return Item(id: q, name: n, cc: cc,
                                    at: EqualEarth.project(lon: ll[1].doubleValue, lat: ll[0].doubleValue),
                                    date: i["d"] as? String ?? "", label: i["l"] as? String ?? "",
                                    fame: long ? (i["f"] as? NSNumber)?.intValue ?? 1 : 9, ccs: ccs,
                                    type: i["t"] as? String ?? "", own: i["k"] as? String)
                    }
                    out.append(Collection(id: id, title: t, scope: c["scope"] as? String ?? "world", event: c["event"] as? Bool ?? false,
                                          source: c["source"] as? String ?? "", items: its, offMap: off.count, unmapped: off,
                                          shapes: c["shapes"] as? String, menu: (c["menu"] as? NSNumber)?.intValue,
                                          types: c["types"] as? [[String]] ?? [], tag: id + "||"))
                }
            }
            await MainActor.run {
                let me = CollectionStore.shared
                me.all = out
                me.loading = false
                me.ready = true
            }
        }
    }

    /// a stop's line ("5 Jul 2026 · British Grand Prix")
    /// a stop of any collection read, by its key
    func item(_ key: PlaceKey) -> Item? {
        for c in all { if let it = c.items.first(where: { $0.key == key }) { return it } }
        return nil
    }

    /// a stop's day if it has come (stamping gives the place that day as a visit, D7), nil for a stop still to come or
    /// one without a day
    static func pastDay(_ day: String?) -> String? {
        guard let day, day.count == 10 else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd"
        return day <= f.string(from: Date()) ? day : nil
    }
    /// a stop still to come (it is wished with its day, not stamped with it)
    static func upcoming(_ day: String?) -> Bool {
        guard let day, day.count == 10 else { return false }
        return pastDay(day) == nil
    }

    static func line(_ i: Item) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd"
        let day = f.date(from: i.date).map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? ""
        return [day, i.label].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

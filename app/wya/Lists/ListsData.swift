import Foundation

/// THE LISTS TAB'S THINGS: your lists, plans, tier lists and photo books, as the old app kept them (its data and its
/// rules, brought over without its look): a list's items (a place, one of your own things, something from outside, or
/// a section's heading), its cover's colours and pictures, when, its note, archived and hidden; a plan's days and their
/// items (a journey's flight or train with its numbers, seat and time zones); a tier list's rows and its pool; a book's
/// pages. Kept on the phone by ListsStore.

nonisolated struct ListItem: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case place, mine, thing, section }

    var id: String
    var k: Kind
    var n: String
    var cc: String?
    var note: String
    var link: String
    var t: ThingKind?
    var ref: String?
    var pic: String?

    init(id: String = "i-" + UUID().uuidString, n: String, cc: String?, note: String = "", link: String = "") {
        self.id = id; self.k = .place; self.n = n; self.cc = cc; self.note = note; self.link = link
    }
    static func mine(_ t: ThingKind, _ ref: String) -> ListItem {
        var i = ListItem(n: "", cc: nil); i.k = .mine; i.t = t; i.ref = ref; return i
    }
    static func thing(_ n: String, note: String = "", link: String = "", pic: String? = nil) -> ListItem {
        var i = ListItem(n: n, cc: nil, note: note, link: link); i.k = .thing; i.pic = pic; return i
    }
    static func section(_ n: String) -> ListItem {
        var i = ListItem(n: n, cc: nil); i.k = .section; return i
    }

    enum CodingKeys: String, CodingKey { case id, k, n, cc, note, link, t, ref, pic }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        k = (try? c.decodeIfPresent(Kind.self, forKey: .k)) ?? .place
        n = try c.decodeIfPresent(String.self, forKey: .n) ?? ""
        cc = try c.decodeIfPresent(String.self, forKey: .cc)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        t = try? c.decodeIfPresent(ThingKind.self, forKey: .t)
        ref = try c.decodeIfPresent(String.self, forKey: .ref)
        pic = try c.decodeIfPresent(String.self, forKey: .pic)
    }

    func same(_ o: ListItem) -> Bool {
        switch (k, o.k) {
        case (.place, .place): return n == o.n && (cc == nil || o.cc == nil || cc == o.cc)
        case (.mine, .mine): return t == o.t && ref == o.ref
        default: return false
        }
    }
}

nonisolated struct MyList: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var wish: Bool
    var cols: [String]
    var cov: String
    var pics: [String]
    var items: [ListItem]
    var what: String
    var when: String
    var whenFrom: String?
    var whenTo: String?
    var note: String
    var arch: Bool
    var hid: Bool

    init(id: String = "l-" + UUID().uuidString, name: String, wish: Bool = false, cols: [String] = ["lime", "teal", "blue"],
                cov: String = "cascade", pics: [String] = [], items: [ListItem] = [], what: String = "", when: String = "",
                note: String = "", arch: Bool = false, hid: Bool = false) {
        self.id = id; self.name = name; self.wish = wish; self.cols = cols; self.cov = cov; self.pics = pics; self.items = items
        self.what = what; self.when = when; self.note = note; self.arch = arch; self.hid = hid
    }

    enum CodingKeys: String, CodingKey { case id, name, wish, cols, cov, pics, items, what, when, whenFrom, whenTo, note, arch, hid }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        wish = try c.decodeIfPresent(Bool.self, forKey: .wish) ?? false
        cols = try c.decodeIfPresent([String].self, forKey: .cols) ?? ["lime", "teal", "blue"]
        cov = try c.decodeIfPresent(String.self, forKey: .cov) ?? "cascade"
        pics = try c.decodeIfPresent([String].self, forKey: .pics) ?? []
        items = try c.decodeIfPresent([ListItem].self, forKey: .items) ?? []
        what = try c.decodeIfPresent(String.self, forKey: .what) ?? ""
        when = try c.decodeIfPresent(String.self, forKey: .when) ?? ""
        whenFrom = try c.decodeIfPresent(String.self, forKey: .whenFrom)
        whenTo = try c.decodeIfPresent(String.self, forKey: .whenTo)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        arch = try c.decodeIfPresent(Bool.self, forKey: .arch) ?? false
        hid = try c.decodeIfPresent(Bool.self, forKey: .hid) ?? false
    }

    var whenIsExact: Bool { whenFrom != nil || whenTo != nil }

    var countries: [String] {
        var seen = Set<String>(), out: [String] = []
        for i in items where i.k == .place { if let c = i.cc, !seen.contains(c) { seen.insert(c); out.append(c) } }
        return out
    }

    @discardableResult
    mutating func setDay(first: Bool, _ d: String?) -> Bool {
        let v = d.flatMap { $0.isEmpty ? nil : $0 }
        let f = first ? v : whenFrom, t = first ? whenTo : v
        guard let words = WhenWords.exact(from: f, to: t) else { return false }
        whenFrom = f; whenTo = t; when = words
        return true
    }

    mutating func setRough(_ t: String) {
        when = t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : t
        whenFrom = nil; whenTo = nil
    }

    var pictures: Set<String> { Set(pics).union(items.compactMap(\.pic)) }
}

nonisolated enum ListOnMap {
    static let colours = ["blue", "lime", "yellow", "brown", "red", "grey", "teal"]

    static func colour(_ cols: [String]) -> String {
        guard let c = cols.first, colours.contains(c) else { return "lime" }
        return c
    }

    static func places(_ items: [ListItem], colour: String, onMap: (String) -> Bool) -> (ids: [String: String], missed: Int) {
        var ids: [String: String] = [:], missed = 0
        for it in items where it.k == .place {
            if let cc = it.cc, onMap(cc) { ids[cc] = colour } else { missed += 1 }
        }
        return (ids, missed)
    }

}

nonisolated enum SoftLimit {
    static func count(_ s: String) -> Int { s.count }
    static func shown(_ s: String, _ max: Int) -> Bool { s.count >= Int((Double(max) * 0.8).rounded(.down)) }
    static func over(_ s: String, _ max: Int) -> Bool { s.count > max }
}

nonisolated enum CoverColours {
    static let all = ["lime", "blue", "teal", "yellow", "red", "brown", "grey", "ink"]

    enum Outcome: Equatable, Sendable {
        case ok
        case swapped
        case full
        case last
    }

    static func press(_ c: String, in cols: inout [String]) -> Outcome {
        if let i = cols.firstIndex(of: c) {
            guard cols.count > 1 else { return .last }
            cols.remove(at: i)
            return .ok
        }
        let not = c == "brown" ? "yellow" : c == "yellow" ? "brown" : ""
        let had = cols.contains(not)
        let rest = cols.filter { $0 != not }
        if rest.count >= 3 { return .full }
        cols = rest + [c]
        return had ? .swapped : .ok
    }
}

nonisolated enum WhenWords {
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static func day(_ d: String) -> String {
        let p = d.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return d }
        return "\(p[2]) \(months[p[1] - 1]) \(p[0])"
    }
    static func exact(from: String?, to: String?) -> String? {
        let f = from.flatMap { $0.isEmpty ? nil : $0 }, t = to.flatMap { $0.isEmpty ? nil : $0 }
        if let f, let t, t < f { return nil }
        switch (f, t) {
        case (nil, nil): return ""
        case let (f?, t?) where t != f: return day(f) + " to " + day(t)
        case let (f?, _): return day(f)
        case let (nil, t?): return day(t)
        }
    }
}

nonisolated struct PlanItem: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var at: String?
    var until: String?
    var what: String
    var place: String
    var link: String
    var note: String
    var c: String
    var cc: String?
    var go: Journey?
    init(id: String = "e-" + UUID().uuidString, at: String?, until: String? = nil, what: String, place: String,
                link: String = "", note: String = "", c: String = "", cc: String? = nil, go: Journey? = nil) {
        self.id = id; self.at = at; self.until = until; self.what = what; self.place = place
        self.link = link; self.note = note; self.c = c; self.cc = cc; self.go = go
    }
    enum CodingKeys: String, CodingKey { case id, at, until, what, place = "where", link, note, c, cc, go }
    init(from d: Decoder) throws {
        let k = try d.container(keyedBy: CodingKeys.self)
        id = try k.decodeIfPresent(String.self, forKey: .id) ?? "e-" + UUID().uuidString
        at = (try? k.decodeIfPresent(String.self, forKey: .at)).flatMap { $0?.isEmpty == false ? $0 : nil }
        until = (try? k.decodeIfPresent(String.self, forKey: .until)).flatMap { $0?.isEmpty == false ? $0 : nil }
        what = try k.decodeIfPresent(String.self, forKey: .what) ?? ""
        place = try k.decodeIfPresent(String.self, forKey: .place) ?? ""
        link = try k.decodeIfPresent(String.self, forKey: .link) ?? ""
        note = try k.decodeIfPresent(String.self, forKey: .note) ?? ""
        c = try k.decodeIfPresent(String.self, forKey: .c) ?? ""
        cc = try k.decodeIfPresent(String.self, forKey: .cc)
        go = try k.decodeIfPresent(Journey.self, forKey: .go)
    }

    var startMinutes: Int { PlanItem.minutes(at) ?? -1 }
    static func minutes(_ t: String?) -> Int? {
        guard let t else { return nil }
        let p = t.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0...23).contains(p[0]), (0...59).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }
    var span: (Int, Int)? {
        guard let a = PlanItem.minutes(at) else { return nil }
        var b = PlanItem.minutes(until) ?? a + 60
        if b <= a { b = a + 60 }
        return (a, min(b, 24 * 60))
    }
}

nonisolated struct Journey: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable { case flight, train, bus, ferry, car, walk }
    var mode: Mode
    var from: String
    var fromCC: String?
    var fromTZ: String?
    var to: String
    var toCC: String?
    var toTZ: String?
    var arrive: String?
    var days: Int
    var carrier: String
    var number: String
    var seat: String
    var ref: String
    var gate: String

    init(mode: Mode, from: String = "", fromCC: String? = nil, fromTZ: String? = nil, to: String = "", toCC: String? = nil,
                toTZ: String? = nil, arrive: String? = nil, days: Int = 0, carrier: String = "", number: String = "",
                seat: String = "", ref: String = "", gate: String = "") {
        self.mode = mode; self.from = from; self.fromCC = fromCC; self.fromTZ = fromTZ; self.to = to; self.toCC = toCC
        self.toTZ = toTZ; self.arrive = arrive; self.days = days; self.carrier = carrier; self.number = number
        self.seat = seat; self.ref = ref; self.gate = gate
    }
    enum CodingKeys: String, CodingKey { case mode, from, fromCC, fromTZ, to, toCC, toTZ, arrive, days, carrier, number, seat, ref, gate }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .flight
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        fromCC = try c.decodeIfPresent(String.self, forKey: .fromCC)
        fromTZ = try c.decodeIfPresent(String.self, forKey: .fromTZ)
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        toCC = try c.decodeIfPresent(String.self, forKey: .toCC)
        toTZ = try c.decodeIfPresent(String.self, forKey: .toTZ)
        arrive = try c.decodeIfPresent(String.self, forKey: .arrive)
        days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 0
        carrier = try c.decodeIfPresent(String.self, forKey: .carrier) ?? ""
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        seat = try c.decodeIfPresent(String.self, forKey: .seat) ?? ""
        ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? ""
        gate = try c.decodeIfPresent(String.self, forKey: .gate) ?? ""
    }

    func moments(day: String, leaves: String?) -> (Date, Date)? {
        guard let a = PlanItem.minutes(leaves), let b = PlanItem.minutes(arrive), let d0 = PlanDates.date(day) else { return nil }
        func at(_ day: Date, _ m: Int, _ tz: String?) -> Date? {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
            let ymd = utc.dateComponents([.year, .month, .day], from: day)
            return cal.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: m / 60, minute: m % 60))
        }
        guard let d1 = PlanDates.date(PlanDates.key(day, days)), let x = at(d0, a, fromTZ), let y = at(d1, b, toTZ) else { return nil }
        return (x, y)
    }

    func minutes(day: String, leaves: String?) -> Int? {
        guard let (x, y) = moments(day: day, leaves: leaves) else { return nil }
        let m = Int(y.timeIntervalSince(x) / 60)
        return m > 0 ? m : nil
    }

    static func length(_ m: Int) -> String {
        m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)"
    }
}

nonisolated struct PlanDay: Codable, Equatable, Sendable {
    var items: [PlanItem]
    init(items: [PlanItem] = []) { self.items = items }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
    }
    enum CodingKeys: String, CodingKey { case items }
}

nonisolated struct Plan: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var start: String
    var end: String
    var days: [PlanDay]
    var cols: [String]
    var cov: String
    var pics: [String]
    var arch: Bool
    var hid: Bool
    init(id: String = "p-" + UUID().uuidString, name: String, start: String, end: String? = nil, days: [PlanDay],
                cols: [String] = ["blue", "teal", "lime"], cov: String = "bands", pics: [String] = [],
                arch: Bool = false, hid: Bool = false) {
        self.id = id; self.name = name; self.start = start; self.days = days
        self.end = end ?? (start.isEmpty ? "" : PlanDates.key(start, max(0, days.count - 1)))
        self.cols = cols; self.cov = cov; self.pics = pics; self.arch = arch; self.hid = hid
    }
    enum CodingKeys: String, CodingKey { case id, name, start, end, days, cols, cov, pics, arch, hid }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? ""
        days = try c.decodeIfPresent([PlanDay].self, forKey: .days) ?? []
        let e = try c.decodeIfPresent(String.self, forKey: .end) ?? ""
        end = e.isEmpty && !start.isEmpty ? PlanDates.key(start, max(0, days.count - 1)) : e
        cols = try c.decodeIfPresent([String].self, forKey: .cols) ?? ["blue", "teal", "lime"]
        cov = try c.decodeIfPresent(String.self, forKey: .cov) ?? "bands"
        pics = try c.decodeIfPresent([String].self, forKey: .pics) ?? []
        arch = try c.decodeIfPresent(Bool.self, forKey: .arch) ?? false
        hid = try c.decodeIfPresent(Bool.self, forKey: .hid) ?? false
    }

    var count: Int { days.reduce(0) { $0 + $1.items.count } }
}

nonisolated struct TierRow: Codable, Equatable, Sendable {
    var t: String
    var items: [String]
    var c: String?
    init(t: String, items: [String], c: String? = nil) { self.t = t; self.items = items; self.c = c }
}

nonisolated struct TierList: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var rows: [TierRow]
    var pool: [String]
    var cc: [String: String]
    var note: String
    var arch: Bool
    var hid: Bool
    init(id: String = "t-" + UUID().uuidString, name: String, rows: [TierRow], pool: [String] = [],
                cc: [String: String] = [:], note: String = "", arch: Bool = false, hid: Bool = false) {
        self.id = id; self.name = name; self.rows = rows; self.pool = pool; self.cc = cc; self.note = note
        self.arch = arch; self.hid = hid
    }
    enum CodingKeys: String, CodingKey { case id, name, rows, pool, cc, note, arch, hid }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        rows = try c.decodeIfPresent([TierRow].self, forKey: .rows) ?? []
        pool = try c.decodeIfPresent([String].self, forKey: .pool) ?? []
        cc = try c.decodeIfPresent([String: String].self, forKey: .cc) ?? [:]
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        arch = try c.decodeIfPresent(Bool.self, forKey: .arch) ?? false
        hid = try c.decodeIfPresent(Bool.self, forKey: .hid) ?? false
    }

    static func blank() -> TierList {
        TierList(name: "", rows: ["S", "A", "B", "C", "D"].map { TierRow(t: $0, items: []) })
    }

    static let colours = ["blue", "lime", "yellow", "brown", "red", "grey", "teal"]
    func colour(_ i: Int) -> String { rows[i].c ?? Self.automatic(i) }
    static func automatic(_ i: Int) -> String { colours[i % colours.count] }
    var count: Int { rows.reduce(0) { $0 + $1.items.count } }

    var has: Set<String> { Set(pool).union(rows.flatMap(\.items)) }

    @discardableResult
    mutating func add(_ names: [String], country: [String: String] = [:]) -> Int {
        var have = has, n = 0
        for raw in names {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty, !have.contains(v) else { continue }
            pool.append(v); have.insert(v); n += 1
            if let c = country[raw] ?? country[v] { cc[v] = c }
        }
        return n
    }

    enum Slot: Equatable, Sendable { case pool, row(Int) }

    func slot(of name: String) -> Slot? {
        if pool.contains(name) { return .pool }
        if let i = rows.firstIndex(where: { $0.items.contains(name) }) { return .row(i) }
        return nil
    }

    @discardableResult
    mutating func move(_ name: String, to: Slot?, at: Int? = nil) -> Bool {
        guard let from = slot(of: name) else { return false }
        switch to {
        case nil:
            take(name, from); cc[name] = nil
            return true
        case .pool?:
            if from == .pool { return false }
            take(name, from); pool.append(name)
            return true
        case .row(let k)?:
            guard rows.indices.contains(k) else { return false }
            let others = rows[k].items.filter { $0 != name }
            let j = min(at ?? others.count, others.count)
            if from == .row(k), rows[k].items.firstIndex(of: name) == j { return false }
            take(name, from)
            rows[k].items.insert(name, at: min(j, rows[k].items.count))
            return true
        }
    }

    private mutating func take(_ name: String, _ from: Slot) {
        switch from {
        case .pool: pool.removeAll { $0 == name }
        case .row(let i): rows[i].items.removeAll { $0 == name }
        }
    }

    static let least = 2
    static let names = ["S", "A", "B", "C", "D", "E", "F"]

    static func nextName(_ rows: [TierRow]) -> String {
        let used = Set(rows.map(\.t))
        let all = names + "GHIJKLMNOPQRTUVWXYZ".map(String.init)
        return all.first { !used.contains($0) } ?? String(rows.count + 1)
    }

    mutating func addTier() { rows.append(TierRow(t: Self.nextName(rows), items: [])) }

    @discardableResult
    mutating func takeOut(_ i: Int) -> Bool {
        guard rows.indices.contains(i), rows.count > Self.least else { return false }
        let r = rows.remove(at: i)
        pool += r.items
        return true
    }
}

nonisolated enum TierOnMap {
    static func places(_ t: TierList, idOf: (String) -> String?, onMap: (String) -> Bool) -> (ids: [String: String], missed: Int) {
        var ids: [String: String] = [:], missed = 0
        for (i, r) in t.rows.enumerated() {
            let c = t.colour(i)
            for n in r.items {
                if let id = idOf(n), onMap(id) { ids[id] = c }
                else if let cc = t.cc[n], onMap(cc) { ids[cc] = c }
                else { missed += 1 }
            }
        }
        return (ids, missed)
    }
}

nonisolated struct BookWords: Codable, Equatable, Sendable {
    var text: String
    var tx: Double
    var ty: Double
    init(text: String = "", tx: Double = 0.5, ty: Double = 0.5) { self.text = text; self.tx = tx; self.ty = ty }
}

nonisolated struct BookPage: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var photos: [String]
    var text: String?
    var bg: String?
    var video: String?
    var poster: String?
    var sketch: String?
    var ink: String?
    var drawing: String?
    var words: BookWords?
    var place: String?

    init(id: String = "pg-" + UUID().uuidString, photos: [String] = [], text: String? = nil, bg: String? = nil,
                video: String? = nil, poster: String? = nil, sketch: String? = nil, ink: String? = nil,
                drawing: String? = nil, words: BookWords? = nil, place: String? = nil) {
        self.id = id; self.photos = photos; self.text = text; self.bg = bg; self.video = video; self.poster = poster
        self.sketch = sketch; self.ink = ink; self.drawing = drawing; self.words = words; self.place = place
    }
    enum CodingKeys: String, CodingKey { case id, photos, text, bg, video, poster, sketch, ink, drawing, words, place = "where" }

    static func words() -> BookPage { BookPage(text: "", bg: "white") }
    var isWords: Bool { text != nil }
    var isVideo: Bool { video != nil }
    var isSketch: Bool { photos.isEmpty && video == nil && text == nil && (sketch != nil || drawing != nil) }
    var picture: String? { photos.first ?? poster }
    var files: [String] { photos + [video, poster, sketch, ink, drawing].compactMap { $0 } }

    static let papers = ["white", "cream", "lime", "teal", "blue", "yellow", "red", "ink"]
    static let darkPapers: Set<String> = ["ink", "blue", "red", "brown"]
    var paper: String { bg.flatMap { Self.papers.contains($0) ? $0 : nil } ?? "white" }
}

nonisolated struct PhotoBook: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var cols: [String]
    var pages: [BookPage]
    var cover: String?
    var nameOn: Bool
    var nameAt: BookWords?
    var arch: Bool
    var hid: Bool
    init(id: String = "b-" + UUID().uuidString, name: String, cols: [String] = ["teal", "lime", "blue"],
                pages: [BookPage] = [], cover: String? = nil, nameOn: Bool = true, nameAt: BookWords? = nil,
                arch: Bool = false, hid: Bool = false) {
        self.id = id; self.name = name; self.cols = cols; self.pages = pages; self.cover = cover
        self.nameOn = nameOn; self.nameAt = nameAt; self.arch = arch; self.hid = hid
    }
    enum CodingKeys: String, CodingKey { case id, name, cols, pages, cover, nameOn, nameAt, arch, hid }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        cols = try c.decodeIfPresent([String].self, forKey: .cols) ?? ["teal", "lime", "blue"]
        pages = try c.decodeIfPresent([BookPage].self, forKey: .pages) ?? []
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        nameOn = try c.decodeIfPresent(Bool.self, forKey: .nameOn) ?? true
        nameAt = try c.decodeIfPresent(BookWords.self, forKey: .nameAt)
        arch = try c.decodeIfPresent(Bool.self, forKey: .arch) ?? false
        hid = try c.decodeIfPresent(Bool.self, forKey: .hid) ?? false
    }

    static let most = 6

    var pictures: [String] { pages.flatMap { $0.photos.isEmpty ? [$0.poster].compactMap { $0 } : $0.photos } }
    var coverPicture: String? { cover ?? pictures.first }
    var files: Set<String> { Set(pages.flatMap(\.files)).union([cover].compactMap { $0 }) }

    @discardableResult
    mutating func addPhotos(_ names: [String], at: Int) -> Int {
        guard !names.isEmpty else { return 0 }
        var made: [BookPage] = []
        var k = 0
        while k < names.count {
            made.append(BookPage(photos: Array(names[k..<min(k + Self.most, names.count)])))
            k += Self.most
        }
        pages.insert(contentsOf: made, at: max(0, min(at, pages.count)))
        return made.count
    }

    mutating func replace(_ i: Int, with new: [BookPage]) {
        guard pages.indices.contains(i), var first = new.first else { return }
        let old = pages[i]
        if !first.isWords { first.words = first.words ?? old.words; first.place = first.place ?? old.place }
        pages.replaceSubrange(i...i, with: [first] + new.dropFirst())
    }

    mutating func movePage(from: Int, to: Int) {
        guard pages.indices.contains(from), pages.indices.contains(to), from != to else { return }
        let p = pages.remove(at: from)
        pages.insert(p, at: to)
    }

    @discardableResult
    mutating func deletePage(_ i: Int) -> BookPage? {
        guard pages.indices.contains(i) else { return nil }
        return pages.remove(at: i)
    }

    var isEmpty: Bool { pages.isEmpty && cover == nil }
}

nonisolated enum ThingKind: String, Codable, Sendable, CaseIterable {
    case list, plan, tier, book
}

nonisolated enum ThingOrder: String, Codable, Sendable, CaseIterable {
    case old, new, az, own
}

nonisolated struct ListsBook: Codable, Equatable, Sendable {
    var lists: [MyList] = []
    var plans: [Plan] = []
    var tiers: [TierList] = []
    var books: [PhotoBook] = []
    var order: ThingOrder = .old
    var rank: [String: Int] = [:]

    init() {}

    enum CodingKeys: String, CodingKey { case lists, plans, tiers, books, order, rank }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        lists = try c.decodeIfPresent([MyList].self, forKey: .lists) ?? []
        plans = try c.decodeIfPresent([Plan].self, forKey: .plans) ?? []
        tiers = try c.decodeIfPresent([TierList].self, forKey: .tiers) ?? []
        books = try c.decodeIfPresent([PhotoBook].self, forKey: .books) ?? []
        order = (try? c.decodeIfPresent(ThingOrder.self, forKey: .order)) ?? .old
        rank = try c.decodeIfPresent([String: Int].self, forKey: .rank) ?? [:]
    }

    var orders: [ThingOrder] { rank.isEmpty ? [.old, .new, .az] : ThingOrder.allCases }

    func inOrder<T: Identifiable>(_ xs: [T], name: (T) -> String) -> [T] where T.ID == String {
        switch order {
        case .old: return xs
        case .new: return xs.reversed()
        case .az:
            return xs.enumerated().sorted { a, b in
                let o = name(a.element).compare(name(b.element), options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
                return o == .orderedSame ? a.offset < b.offset : o == .orderedAscending
            }.map(\.element)
        case .own:
            return xs.enumerated().sorted { a, b in
                let ra = rank[a.element.id] ?? Int.max, rb = rank[b.element.id] ?? Int.max
                return ra != rb ? ra < rb : a.offset < b.offset
            }.map(\.element)
        }
    }

    static func countsPlaces(_ items: [ListItem]) -> Bool { items.allSatisfy { $0.k == .place || $0.k == .section } }

    func holds(_ a: MyList, _ target: String, seen: Set<String> = []) -> Bool {
        if seen.contains(a.id) { return false }
        let s = seen.union([a.id])
        return a.items.contains { it in
            guard it.k == .mine, it.t == .list, let r = it.ref else { return false }
            if r == target { return true }
            guard let inner = lists.first(where: { $0.id == r }) else { return false }
            return holds(inner, target, seen: s)
        }
    }
    func wouldLoop(_ l: MyList, _ it: ListItem) -> Bool {
        guard it.k == .mine, it.t == .list, let r = it.ref else { return false }
        if r == l.id { return true }
        guard let inner = lists.first(where: { $0.id == r }) else { return false }
        return holds(inner, l.id)
    }

    @discardableResult
    mutating func keep(_ l: MyList, untitled: String = "Untitled") -> Bool {
        var x = l
        let fresh = !lists.contains { $0.id == x.id }
        let blank = fresh && !x.wish && x.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && x.items.isEmpty
        if blank { return false }
        if !x.wish && x.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { x.name = untitled }
        if let i = lists.firstIndex(where: { $0.id == x.id }) { lists[i] = x } else { lists.append(x) }
        return true
    }

    mutating func keepPlan(_ p: Plan) {
        if let i = plans.firstIndex(where: { $0.id == p.id }) { plans[i] = p } else { plans.append(p) }
    }

    @discardableResult
    mutating func keepBook(_ b: PhotoBook, untitled: String = "Untitled") -> Bool {
        var x = b
        let fresh = !books.contains { $0.id == x.id }
        if fresh && x.isEmpty { return false }
        if x.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { x.name = untitled }
        if let i = books.firstIndex(where: { $0.id == x.id }) { books[i] = x } else { books.append(x) }
        return true
    }

    mutating func keepTier(_ t: TierList, untitled: String = "Untitled") {
        var x = t
        if x.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { x.name = untitled }
        if let i = tiers.firstIndex(where: { $0.id == x.id }) { tiers[i] = x } else { tiers.append(x) }
    }

    var shownLists: [MyList] {
        let wish = lists.filter(\.wish)
        return wish + inOrder(lists.filter { !$0.wish && !$0.arch && !$0.hid }, name: \.name)
    }
    var shownPlans: [Plan] { inOrder(plans.filter { !$0.arch && !$0.hid }, name: \.name) }
    var shownTiers: [TierList] { inOrder(tiers.filter { !$0.arch && !$0.hid }, name: \.name) }
    var shownBooks: [PhotoBook] { inOrder(books.filter { !$0.arch && !$0.hid }, name: \.name) }

    struct Hit: Equatable, Sendable {
        let kind: ThingKind
        let id: String
        let name: String
        var via: [String] = []
    }
    func search(_ q: String) -> [Hit] {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func has(_ s: String) -> Bool { t.isEmpty || s.lowercased().contains(t) }
        var out: [Hit] = []
        for l in shownLists where has(l.name) || (!t.isEmpty && l.items.contains { $0.k != .mine && has($0.n) }) {
            let via = has(l.name) ? [] : l.items.filter { $0.k != .mine && has($0.n) }.map(\.n)
            out.append(Hit(kind: .list, id: l.id, name: l.name, via: via))
        }
        for p in shownPlans where has(p.name) { out.append(Hit(kind: .plan, id: p.id, name: p.name)) }
        for x in shownTiers where has(x.name) { out.append(Hit(kind: .tier, id: x.id, name: x.name)) }
        for b in shownBooks where has(b.name) { out.append(Hit(kind: .book, id: b.id, name: b.name)) }
        return out
    }
    var searchNames: [String] {
        shownLists.flatMap { [$0.name] + $0.items.filter { $0.k != .mine }.map(\.n) }
            + shownPlans.map(\.name) + shownTiers.map(\.name) + shownBooks.map(\.name)
    }

    func movable(_ k: ThingKind) -> [String] {
        switch k {
        case .list: return inOrder(lists.filter { !$0.wish && !$0.arch && !$0.hid }, name: \.name).map(\.id)
        case .plan: return shownPlans.map(\.id)
        case .tier: return shownTiers.map(\.id)
        case .book: return shownBooks.map(\.id)
        }
    }
    func archived(_ k: ThingKind) -> [String] {
        switch k {
        case .list: return inOrder(lists.filter { $0.arch && !$0.hid }, name: \.name).map(\.id)
        case .plan: return inOrder(plans.filter { $0.arch && !$0.hid }, name: \.name).map(\.id)
        case .tier: return inOrder(tiers.filter { $0.arch && !$0.hid }, name: \.name).map(\.id)
        case .book: return inOrder(books.filter { $0.arch && !$0.hid }, name: \.name).map(\.id)
        }
    }

    mutating func move(_ k: ThingKind, from: Int, to: Int) {
        var ids = movable(k)
        guard ids.indices.contains(from), ids.indices.contains(to), from != to else { return }
        let m = ids.remove(at: from)
        ids.insert(m, at: to)
        for (i, id) in ids.enumerated() { rank[id] = i }
        order = .own
    }

    @discardableResult
    mutating func copy(_ k: ThingKind, _ id: String) -> String? {
        switch k {
        case .list:
            guard var x = lists.first(where: { $0.id == id }) else { return nil }
            x.id = "l-" + UUID().uuidString; x.wish = false; x.arch = false; x.hid = false
            x.items = x.items.map { var i = $0; i.id = "i-" + UUID().uuidString; return i }
            lists.append(x); return x.id
        case .plan:
            guard var x = plans.first(where: { $0.id == id }) else { return nil }
            x.id = "p-" + UUID().uuidString; x.arch = false; x.hid = false
            plans.append(x); return x.id
        case .tier:
            guard var x = tiers.first(where: { $0.id == id }) else { return nil }
            x.id = "t-" + UUID().uuidString; x.arch = false; x.hid = false
            tiers.append(x); return x.id
        case .book:
            guard var x = books.first(where: { $0.id == id }) else { return nil }
            x.id = "b-" + UUID().uuidString; x.arch = false; x.hid = false
            books.append(x); return x.id
        }
    }

    mutating func setArchived(_ k: ThingKind, _ id: String, _ on: Bool) {
        switch k {
        case .list: if let i = lists.firstIndex(where: { $0.id == id }), !lists[i].wish { lists[i].arch = on }
        case .plan: if let i = plans.firstIndex(where: { $0.id == id }) { plans[i].arch = on }
        case .tier: if let i = tiers.firstIndex(where: { $0.id == id }) { tiers[i].arch = on }
        case .book: if let i = books.firstIndex(where: { $0.id == id }) { books[i].arch = on }
        }
    }

    mutating func delete(_ k: ThingKind, _ id: String) {
        if k == .list && lists.first(where: { $0.id == id })?.wish == true { return }
        switch k {
        case .list: lists.removeAll { $0.id == id }
        case .plan: plans.removeAll { $0.id == id }
        case .tier: tiers.removeAll { $0.id == id }
        case .book: books.removeAll { $0.id == id }
        }
        rank[id] = nil
        for i in lists.indices { lists[i].items.removeAll { $0.k == .mine && $0.t == k && $0.ref == id } }
    }
}

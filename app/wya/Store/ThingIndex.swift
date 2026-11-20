import Foundation

/// SEARCH OVER EVERY THING (Part 1.10 in Places, D12's things part): every thing of D5 (57,754), famous first, read once
/// from the data server (`native/things/things-index-3.wyti`: rows [name, file, Wikidata id, kind, fame, lat, lon,
/// codes, and (3) the names people know it by]) the first time Places is searched. Names starting with what was typed, then (from three letters) names
/// holding it; an airport's code ("JFK") finds it whole; the open country's before everywhere else's.
@MainActor
@Observable
final class ThingIndex {
    static let shared = ThingIndex()
    struct Hit: Hashable {
        let name: String
        let file: String
        let id: String
        let kind: Int
        let fame: Int
        let lat: Double
        let lon: Double
        var key: String { "m:wd:" + id }
    }
    private(set) var ready = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var rows: [(folded: String, codes: [String], hit: Hit, alt: Bool)] = []
    /// the index: 3 (with the names people know) where the server has it, else 2
    nonisolated private static func file() async -> ServerAnswer<Data> {
        let r = await Servers.data.file("native/things/things-index-3.wyti")
        if case .ok(_) = r { return r }
        return await Servers.data.file("native/things/things-index-2.wyti")
    }
    /// the folded names as bytes, one after another, and where each row's starts (one more than rows): the search's
    /// pass over every thing, as strings, took 40 to 90 ms a letter
    @ObservationIgnored private var nameBytes: [UInt8] = []
    @ObservationIgnored private var nameStart: [Int32] = []
    /// whether any row has a code at all (none: the codes' test is skipped)
    @ObservationIgnored private var anyCodes = false
    /// the last two searches (a name and its short words in full are asked one after the other)
    @ObservationIgnored private var last: [(q: String, open: String?, near: Bool, hits: [Hit])] = []

    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            var out: [(String, [String], Hit, Bool)] = []
            if case .ok(let d) = await Self.file(),
               let all = try? JSONSerialization.jsonObject(with: d) as? [[Any]] {
                out.reserveCapacity(all.count)
                for r in all {
                    guard r.count >= 7, let n = r[0] as? String, let f = r[1] as? String, let id = r[2] as? String else { continue }
                    let h = Hit(name: n, file: f, id: id, kind: (r[3] as? NSNumber)?.intValue ?? 11,
                                fame: (r[4] as? NSNumber)?.intValue ?? 0, lat: (r[5] as? NSNumber)?.doubleValue ?? 0, lon: (r[6] as? NSNumber)?.doubleValue ?? 0)
                    let codes = r.count > 7 ? (r[7] as? String ?? "").split(separator: "|").map { $0.lowercased() } : []
                    out.append((n.townFolded, codes, h, false))
                    // ITS NAME AS PEOPLE KNOW IT: English Wikipedia's title, searched as a name is and shown when it
                    // is what was found; straight after its thing, so it keeps the thing's place in the famous-first
                    // order (at the end, Istanbul's Blue Mosque came after two others)
                    if r.count > 8, let alt = r[8] as? String, !alt.isEmpty {
                        for a in alt.split(separator: "|") {
                            out.append((String(a).townFolded, [], Hit(name: String(a), file: h.file, id: h.id, kind: h.kind,
                                                                      fame: h.fame, lat: h.lat, lon: h.lon), true))
                        }
                    }
                }
            }
            var bytes: [UInt8] = [], start: [Int32] = [0]
            start.reserveCapacity(out.count + 1)
            for r in out { bytes.append(contentsOf: r.0.utf8); start.append(Int32(bytes.count)) }
            let coded = out.contains { !$0.1.isEmpty }
            await MainActor.run {
                let me = ThingIndex.shared
                me.rows = out
                (me.nameBytes, me.nameStart, me.anyCodes) = (bytes, start, coded)
                me.loading = false
                me.ready = !out.isEmpty
            }
        }
    }

    /// at most `limit` things for what was typed: a code typed whole first, then names (the open country's first),
    /// the best known first among them (the index is in the data's order: found a lake, a waterfall and two airports
    /// and never the park). A name with a word that starts with what was typed counts as one that starts with it (
    /// finds Lake Baikal before the airport named after it).
    func hits(_ query: String, open: String?, limit: Int = 4, near: Bool = true) -> [Hit] {
        let raw = query.trimmingCharacters(in: .whitespaces)
        let q = raw.townFolded
        guard ready, q.count >= 2 else { return [] }
        if let l = last.first(where: { $0.q == q && $0.open == open && $0.near == near }) { return l.hits }
        let code = raw.lowercased()
        var coded: [Hit] = [], home: [Hit] = [], away: [Hit] = [], homeIn: [Hit] = [], awayIn: [Hit] = []
        var starts = Set<String>()
        guard nameStart.count == rows.count + 1 else { return [] }
        let qb = Array(q.utf8), wb = Array((" " + q).utf8), ql = qb.count, inside = q.count >= 3
        let byCode = anyCodes && code.count >= 3 && code.count <= 4
        nameBytes.withUnsafeBufferPointer { nb in
            qb.withUnsafeBufferPointer { qp in
                wb.withUnsafeBufferPointer { wp in
                    guard let base = nb.baseAddress, let qa = qp.baseAddress, let wa = wp.baseAddress else { return }
                    for i in 0 ..< rows.count {
                        if byCode, rows[i].codes.contains(code) { coded.append(rows[i].hit); continue }
                        let a = Int(nameStart[i]), n = Int(nameStart[i + 1]) - a
                        // (the same tests as the names as strings: its start, a later word's start, anywhere from three
                        // letters)
                        if n >= ql, memcmp(base + a, qa, ql) == 0 {
                            starts.insert(rows[i].hit.id)
                            if rows[i].hit.file == open { home.append(rows[i].hit) } else { away.append(rows[i].hit) }
                        } else if n > ql, memmem(base + a, n, wa, ql + 1) != nil {
                            if rows[i].hit.file == open { home.append(rows[i].hit) } else { away.append(rows[i].hit) }
                        } else if inside, n > ql, memmem(base + a, n, qa, ql) != nil {
                            if rows[i].hit.file == open { if homeIn.count < limit { homeIn.append(rows[i].hit) } } else if awayIn.count < limit { awayIn.append(rows[i].hit) }
                        }
                    }
                }
            }
        }
        // (by fame; at equal fame a name that starts with it first; then the data's order)
        let best = { (a: [Hit]) -> [Hit] in
            a.enumerated().sorted { x, y in
                if x.element.fame != y.element.fame { return x.element.fame > y.element.fame }
                let sx = starts.contains(x.element.id), sy = starts.contains(y.element.id)
                return sx != sy ? sx : x.offset < y.offset
            }.map(\.element)
        }
        // (a thing once: found by its name and by its other name, its name)
        var seen = Set<String>()
        var h = Array((coded + best(home) + homeIn + best(away) + awayIn).filter { seen.insert($0.id).inserted }.prefix(limit))
        // ONE LETTER OFF: with nothing found, a word of a name that starts with what was typed give or take one
        // letter (missed, extra, wrong or two swapped), the best known first
        if h.isEmpty, near, q.count >= 4 {
            let typed = Array(q.utf8)
            var close: [(Hit, Int)] = []
            for (n, r) in rows.enumerated() {
                let f = Array(r.folded.utf8)
                var i = 0
                while i < f.count {
                    var j = i
                    while j < f.count, f[j] != 32 { j += 1 }
                    if Self.nearStart(typed, f[i ..< j]) { close.append((r.hit, n)); break }
                    i = j + 1
                }
            }
            var once = Set<String>()
            h = Array(close.sorted { $0.0.fame != $1.0.fame ? $0.0.fame > $1.0.fame : $0.1 < $1.1 }.map(\.0).filter { once.insert($0.id).inserted }.prefix(limit))
        }
        last = Array(([(q, open, near, h)] + last).prefix(2))
        return h
    }
    /// whether a word starts with `q` give or take one letter: a letter missed, one extra, one wrong, or two swapped
    nonisolated static func nearStart(_ q: [UInt8], _ w: ArraySlice<UInt8>) -> Bool {
        let w = Array(w)
        guard w.count >= q.count - 1, let d = q.indices.first(where: { $0 >= w.count || q[$0] != w[$0] }) else { return false }
        func same(_ a: Int, _ b: Int) -> Bool {   // the rest of q from a matches w from b
            let n = q.count - a
            guard b + n <= w.count else { return false }
            for k in 0 ..< n where q[a + k] != w[b + k] { return false }
            return true
        }
        return same(d, d + 1)                                                   // a letter missed ("eifel": eif-f-el)
            || (d + 1 <= q.count && same(d + 1, d) && d < q.count - 1)          // one extra
            || same(d + 1, d + 1)                                               // one wrong
            || (d + 1 < q.count && d + 1 < w.count && q[d] == w[d + 1] && q[d + 1] == w[d] && same(d + 2, d + 2))   // two swapped
    }
    /// one thing by its key's id, once the index has come
    func hit(_ id: String) -> Hit? {
        let q = id.hasPrefix("wd:") ? String(id.dropFirst(3)) : id
        if byID == nil, ready { byID = Dictionary(rows.enumerated().map { ($1.hit.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        if let byID { return byID[q].map { rows[$0].hit } }
        return rows.first { $0.hit.id == q }?.hit
    }
    /// each thing's row by its id, made once at the first look-up
    @ObservationIgnored private var byID: [String: Int]?
    /// A KIND'S THINGS EVERYWHERE: the best known first (fame, then the index's own order, which is the data's), made
    /// once per kind
    func kind(_ k: Int) -> [Hit] {
        guard ready else { return [] }
        if let c = byKind[k] { return c }
        let out = rows.lazy.filter { !$0.alt }.map(\.hit).filter { $0.kind == k }.enumerated()
            .sorted { $0.element.fame != $1.element.fame ? $0.element.fame > $1.element.fame : $0.offset < $1.offset }
            .map(\.element)
        byKind[k] = out
        return out
    }
    @ObservationIgnored private var byKind: [Int: [Hit]] = [:]
    /// is this hit found by its code (it leads the results)
    func byCode(_ h: Hit, _ query: String) -> Bool {
        let code = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.first { $0.hit == h }?.codes.contains(code) ?? false
    }
}

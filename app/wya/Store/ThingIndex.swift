import Foundation

/// SEARCH OVER EVERY THING (Part 1.10 in Places, D12's things part): every thing of D5 (57,754), famous first, read once
/// from the data server (`native/things/things-index-2.wyti`: rows [name, file, Wikidata id, kind, fame, lat, lon,
/// other names]) the first time Places is searched. Names starting with what was typed, then (from three letters) names
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
    @ObservationIgnored private var rows: [(folded: String, codes: [String], hit: Hit)] = []
    @ObservationIgnored private var last: (q: String, open: String?, hits: [Hit])?

    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            var out: [(String, [String], Hit)] = []
            if case .ok(let d) = await Servers.data.file("native/things/things-index-2.wyti"),
               let all = try? JSONSerialization.jsonObject(with: d) as? [[Any]] {
                out.reserveCapacity(all.count)
                for r in all {
                    guard r.count >= 7, let n = r[0] as? String, let f = r[1] as? String, let id = r[2] as? String else { continue }
                    let h = Hit(name: n, file: f, id: id, kind: (r[3] as? NSNumber)?.intValue ?? 11,
                                fame: (r[4] as? NSNumber)?.intValue ?? 0, lat: (r[5] as? NSNumber)?.doubleValue ?? 0, lon: (r[6] as? NSNumber)?.doubleValue ?? 0)
                    let codes = r.count > 7 ? (r[7] as? String ?? "").split(separator: "|").map { $0.lowercased() } : []
                    out.append((n.townFolded, codes, h))
                }
            }
            await MainActor.run {
                let me = ThingIndex.shared
                me.rows = out
                me.loading = false
                me.ready = !out.isEmpty
            }
        }
    }

    /// at most `limit` things for what was typed: a code typed whole first, then names (the open country's first),
    /// the best known first among them (the index is in the data's order: "yellowst" found a lake, a waterfall and two
    /// airports and never the park). A name with a word that starts with what was typed counts as one that starts
    /// with it ("baikal" finds Lake Baikal before the airport named after it).
    func hits(_ query: String, open: String?, limit: Int = 4) -> [Hit] {
        let raw = query.trimmingCharacters(in: .whitespaces)
        let q = raw.townFolded
        guard ready, q.count >= 2 else { return [] }
        if let l = last, l.q == q, l.open == open { return l.hits }
        let code = raw.lowercased()
        var coded: [Hit] = [], home: [Hit] = [], away: [Hit] = [], homeIn: [Hit] = [], awayIn: [Hit] = []
        var starts = Set<String>()
        let word = " " + q
        for r in rows {
            if code.count >= 3, code.count <= 4, r.codes.contains(code) { coded.append(r.hit); continue }
            let mine = r.hit.file == open
            if r.folded.hasPrefix(q) {
                starts.insert(r.hit.id)
                if mine { home.append(r.hit) } else { away.append(r.hit) }
            } else if r.folded.contains(word) {
                if mine { home.append(r.hit) } else { away.append(r.hit) }
            } else if q.count >= 3, r.folded.contains(q) {
                if mine { if homeIn.count < limit { homeIn.append(r.hit) } } else if awayIn.count < limit { awayIn.append(r.hit) }
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
        var h = Array((coded + best(home) + homeIn + best(away) + awayIn).prefix(limit))
        // ONE LETTER OFF (14 Nov: "eifel" found Ireland and no Eiffel Tower): with nothing found, a word of a name that
        // starts with what was typed give or take one letter (missed, extra, wrong or two swapped), the best known first
        if h.isEmpty, q.count >= 4 {
            let typed = Array(q.utf8)
            var near: [(Hit, Int)] = []
            for (n, r) in rows.enumerated() {
                let f = Array(r.folded.utf8)
                var i = 0
                while i < f.count {
                    var j = i
                    while j < f.count, f[j] != 32 { j += 1 }
                    if Self.nearStart(typed, f[i ..< j]) { near.append((r.hit, n)); break }
                    i = j + 1
                }
            }
            h = Array(near.sorted { $0.0.fame != $1.0.fame ? $0.0.fame > $1.0.fame : $0.1 < $1.1 }.prefix(limit).map(\.0))
        }
        last = (q, open, h)
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
    /// one thing by its key's id ("wd:Q19675"), once the index has come
    func hit(_ id: String) -> Hit? {
        let q = id.hasPrefix("wd:") ? String(id.dropFirst(3)) : id
        if byID == nil, ready { byID = Dictionary(rows.enumerated().map { ($1.hit.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        // (14 Nov: once the table is made, a miss is a miss: the walk through every row on each miss, for each of a big
        // country's listings, held the screen still for seconds)
        if let byID { return byID[q].map { rows[$0].hit } }
        return rows.first { $0.hit.id == q }?.hit
    }
    /// each thing's row by its id, made once at the first look-up
    @ObservationIgnored private var byID: [String: Int]?
    /// A KIND'S THINGS EVERYWHERE (Places' types, 9 Nov): the best known first (fame, then the index's own order, which
    /// is the data's), made once per kind
    func kind(_ k: Int) -> [Hit] {
        guard ready else { return [] }
        if let c = byKind[k] { return c }
        let out = rows.lazy.map(\.hit).filter { $0.kind == k }.enumerated()
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

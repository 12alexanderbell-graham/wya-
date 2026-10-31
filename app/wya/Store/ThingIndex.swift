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
                                lat: (r[5] as? NSNumber)?.doubleValue ?? 0, lon: (r[6] as? NSNumber)?.doubleValue ?? 0)
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

    /// at most `limit` things for what was typed: a code typed whole first, then names (the open country's first)
    func hits(_ query: String, open: String?, limit: Int = 4) -> [Hit] {
        let raw = query.trimmingCharacters(in: .whitespaces)
        let q = raw.townFolded
        guard ready, q.count >= 2 else { return [] }
        if let l = last, l.q == q, l.open == open { return l.hits }
        let code = raw.lowercased()
        var coded: [Hit] = [], home: [Hit] = [], away: [Hit] = [], homeIn: [Hit] = [], awayIn: [Hit] = []
        for r in rows {
            if code.count >= 3, code.count <= 4, r.codes.contains(code) { coded.append(r.hit); continue }
            let mine = r.hit.file == open
            if r.folded.hasPrefix(q) {
                if mine { if home.count < limit { home.append(r.hit) } } else if away.count < limit { away.append(r.hit) }
            } else if q.count >= 3, r.folded.contains(q) {
                if mine { if homeIn.count < limit { homeIn.append(r.hit) } } else if awayIn.count < limit { awayIn.append(r.hit) }
            }
        }
        let h = Array((coded + home + homeIn + away + awayIn).prefix(limit))
        last = (q, open, h)
        return h
    }
    /// is this hit found by its code (it leads the results)
    func byCode(_ h: Hit, _ query: String) -> Bool {
        let code = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.first { $0.hit == h }?.codes.contains(code) ?? false
    }
}

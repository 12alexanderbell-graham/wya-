import Foundation

/// SEARCH OVER EVERY PLACE'S REGIONS (Part 1.10, D12's regions part): the first two region levels of every place
/// (52,725 regions, 54,584 names with their English names), read once from the data server (`native/regions/regions-index-2.wyri`: rows [name, place id, row,
/// region id]) the first time the map is searched. Names starting with what was typed, then (from three letters)
/// names holding it.
@MainActor
@Observable
final class RegionIndex {
    static let shared = RegionIndex()
    struct Hit: Hashable {
        let name: String
        let place: String
        let row: Int
        let id: String
        /// the region it lies in, one level up ( for a Florence County), or "" (regions-index-3)
        var parent: String = ""
        var key: String { "r:\(place)-\(row)|\(id)" }
    }
    private(set) var ready = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var rows: [(folded: String, hit: Hit)] = []
    @ObservationIgnored private var last: (q: String, towns: Bool, hits: [Hit])?
    /// the folded names as bytes, one after another, and where each row's starts (one more than rows): the search's
    /// pass as strings took 15 to 20 ms a letter
    @ObservationIgnored private var nameBytes: [UInt8] = []
    @ObservationIgnored private var nameStart: [Int32] = []

    func load() {
        if ready { buildPeople() }
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            var out: [(String, Hit)] = []
            var data: Data?
            // (-4: and the region each lies in, one level up, for two of one name:; -5: that region found by the
            // shapes where the file names none, 1,655 of 1,808 such pairs told apart)
            for f in ["native/regions/regions-index-5.wyri", "native/regions/regions-index-4.wyri", "native/regions/regions-index-3.wyri", "native/regions/regions-index-2.wyri"] where data == nil {
                if case .ok(let d) = await Servers.data.file(f) { data = d }
            }
            if let d = data, let all = try? JSONSerialization.jsonObject(with: d) as? [[Any]] {
                for r in all {
                    guard r.count >= 4, let n = r[0] as? String, let p = r[1] as? String, let id = r[3] as? String else { continue }
                    let h = Hit(name: n, place: p, row: (r[2] as? NSNumber)?.intValue ?? 1, id: id, parent: r.count > 4 ? (r[4] as? String ?? "") : "")
                    out.append((n.townFolded, h))
                }
            }
            var bytes: [UInt8] = [], start: [Int32] = [0]
            bytes.reserveCapacity(out.reduce(0) { $0 + $1.0.utf8.count })
            start.reserveCapacity(out.count + 1)
            for r in out { bytes.append(contentsOf: r.0.utf8); start.append(Int32(bytes.count)) }
            await MainActor.run {
                let me = RegionIndex.shared
                me.rows = out
                (me.nameBytes, me.nameStart) = (bytes, start)
                me.loading = false
                me.ready = !out.isEmpty
            }
        }
    }

    /// each region's people where the towns' index tells (a first-level region under any of its names, by its id):
    /// made once both indexes have come
    private func people() -> [String: Int] {
        if let p = peopleByID { return p }
        buildPeople()
        return [:]
    }
    @ObservationIgnored private var peopleBuilding = false
    /// the regions' people have come (read by the search, so its list is made again then)
    private(set) var peopleReady = false
    func buildPeople() {
        guard peopleByID == nil, !peopleBuilding, ready, TownIndex.shared.ready else { return }
        peopleBuilding = true
        let towns = TownIndex.shared.peopleRows()
        let regions = rows.map { (folded: $0.folded, place: $0.hit.place, row: $0.hit.row, id: $0.hit.id) }
        Task.detached(priority: .utility) {
            let fold = { (s: String) in s.townFolded }
            // each first-level division's people (the sum of its towns'), and each town's (the biggest of its name)
            var byRegion: [String: Int] = [:], byTown: [String: Int] = [:]
            for t in towns {
                let c = t.file.lowercased()
                if !t.region.isEmpty { byRegion[c + "|" + fold(t.region), default: 0] += t.people }
                let k = c + "|" + fold(t.name)
                if t.people > byTown[k] ?? 0 { byTown[k] = t.people }
            }
            // (a second level by the town of its name there: York in the United Kingdom, 150,000, before York in
            // Western Australia; with no number at all they stood by the alphabet)
            var out: [String: Int] = [:]
            for r in regions {
                let k = r.place + "|\(r.row)|" + r.id
                if let n = (r.row == 1 ? byRegion : byTown)[r.place.lowercased() + "|" + r.folded] { out[k] = max(out[k] ?? 0, n) }
            }
            await MainActor.run {
                let me = RegionIndex.shared
                me.peopleByID = out
                me.peopleBuilding = false
                me.last = nil
                me.peopleReady = true
            }
        }
    }
    @ObservationIgnored private var peopleByID: [String: Int]?
    /// how many people live in a region found, where the towns' index tells (0: not known)
    func people(_ h: Hit) -> Int { people()[h.place + "|\(h.row)|" + h.id] ?? 0 }

    func hits(_ query: String, limit: Int = 4) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).townFolded
        guard ready, q.count >= 2 else { return [] }
        // (read first, so the list is made again when the towns' index comes)
        let townsIn = TownIndex.shared.ready && peopleReady
        if let l = last, l.q == q, l.towns == townsIn { return l.hits }
        let lives = people()
        var starts: [(f: String, h: Hit)] = [], inside: [Hit] = []
        guard nameStart.count == rows.count + 1 else { return [] }
        let qb = Array(q.utf8), ql = qb.count, mid = q.count >= 3
        nameBytes.withUnsafeBufferPointer { nb in
            qb.withUnsafeBufferPointer { qp in
                guard let base = nb.baseAddress, let qa = qp.baseAddress else { return }
                for i in 0 ..< rows.count {
                    let a = Int(nameStart[i]), n = Int(nameStart[i + 1]) - a
                    if n >= ql, memcmp(base + a, qa, ql) == 0 { starts.append((rows[i].folded, rows[i].hit)) }
                    // (a later word starting with it: for "denis"; never the middle of a word; the words looked at
                    // only in a name that holds it at all)
                    else if mid, inside.count < limit, n > ql, memmem(base + a, n, qa, ql) != nil,
                            rows[i].folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) })
                                || rows[i].folded.contains(" " + q) {
                        inside.append(rows[i].hit)
                    }
                }
            }
        }
        let pop = starts.map { lives[$0.h.place + "|\($0.h.row)|" + $0.h.id] ?? 0 }
        let order = starts.indices.sorted { ia, ib in
            let a = starts[ia], b = starts[ib]
            // (a district named Çal led California for "cal": what was typed as a whole name leads within its level,
            // not over the level above)
            let pa = pop[ia], pb = pop[ib]
            let ea = a.f == q, eb = b.f == q
            // a country's first level (states, regions) before its second
            if a.h.row != b.h.row { return a.h.row < b.h.row }
            if ea != eb { return ea }
            // the region more people live in first ("cal" is California, 39 million, before Çal and Caldas: by the
            // shorter name alone California never made the list)
            if pa != pb { return pa > pb }
            if a.f.count != b.f.count { return a.f.count < b.f.count }
            return a.f < b.f
        }
        starts = order.map { starts[$0] }
        // (a region under two of its names, Caldas and Caldas Department, once)
        var seen = Set<String>()
        let h = Array((starts.map(\.h) + inside).filter { seen.insert($0.place + "|" + $0.id).inserted }.prefix(limit))
        last = (q, townsIn, h)
        return h
    }
}

/// A REGION'S ENGLISH NAME: the map's region files name them in their own language, while its page and search say,;
/// the regions' records (regions/<cc>.json) give the English name for the names they were matched by. Read when a
/// country's region map opens
@MainActor
enum RegionNames {
    private static var byCountry: [String: [String: String]] = [:]
    static func load(_ cc: String) async {
        let c = cc.lowercased()
        guard byCountry[c] == nil, case .ok(let d) = await Servers.data.file("regions/\(c).json"),
              let all = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        var m: [String: String] = [:]
        for v in all.values {
            guard let r = v as? [String: Any], let n = r["n"] as? String, !n.isEmpty else { continue }
            for u in (r["u"] as? [String]) ?? [] where u.townFolded != n.townFolded { m[u.townFolded] = n }
        }
        byCountry[c] = m
    }
    /// its English name where its record has one, else the name as given
    static func english(_ cc: String, _ name: String) -> String { byCountry[cc.lowercased()]?[name.townFolded] ?? name }
}


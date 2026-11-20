import Foundation

/// SEARCH OVER EVERY TOWN (Part 1.10 in Places, D12's towns part): every town of every place (228,388, D3), biggest
/// first, read once from the data server (`native/towns/towns-index-2.wyti`: rows [name, file, GeoNames id, people,
/// lat, lon, kind, region]) the first time Places is searched, folded off the main thread. A search lists names starting with what
/// was typed, then (from three letters) names holding it; the open country's towns before everywhere else's. Then a
/// town's other names (`native/towns/towns-alt-1.wyta`, GeoNames' alternate names, CC BY 4.0: Tiflis, Москва, 東京,
/// Shenzen), when its own names gave fewer than asked; the row shows its own name.
@MainActor
@Observable
final class TownIndex {
    static let shared = TownIndex()
    struct Hit: Hashable {
        let name: String
        let file: String
        let id: String
        let people: Int
        let lat: Double
        let lon: Double
        /// its first-level division's name, or ""
        let region: String
        var key: String { "t:" + id }
    }
    private(set) var ready = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var rows: [(folded: String, hit: Hit)] = []
    /// each row's other names folded, ("" for none), read after the index
    @ObservationIgnored private var alt: [String] = []
    @ObservationIgnored private var last: (q: String, open: String?, hits: [Hit])?
    /// THE NAMES AS BYTES, for the search's pass over every town (a pass over the names as strings held the screen a
    /// quarter of a second a letter): each row's folded name, and its other names as, one after another, with where
    /// each row's starts (one more entry than rows, the end)
    @ObservationIgnored private var ownBytes: [UInt8] = []
    @ObservationIgnored private var ownStart: [Int32] = []
    @ObservationIgnored private var altBytes: [UInt8] = []
    @ObservationIgnored private var altStart: [Int32] = []
    nonisolated private static func pack(_ names: [String]) -> ([UInt8], [Int32]) {
        var bytes: [UInt8] = [], start: [Int32] = [0]
        bytes.reserveCapacity(names.reduce(0) { $0 + $1.utf8.count })
        start.reserveCapacity(names.count + 1)
        for n in names { bytes.append(contentsOf: n.utf8); start.append(Int32(bytes.count)) }
        return (bytes, start)
    }

    /// EACH FIRST-LEVEL DIVISION'S PEOPLE, the sum of its towns' (: 39 million), by country and the division's folded
    /// name: how the regions' search tells California from Çal. Made once.
    func regionPeople() -> [String: Int] {
        if let p = peopleByRegion { return p }
        guard ready else { return [:] }
        var out: [String: Int] = [:]
        for r in rows where !r.hit.region.isEmpty {
            out[r.hit.file.lowercased() + "|" + r.hit.region.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil), default: 0] += r.hit.people
        }
        peopleByRegion = out
        return out
    }
    @ObservationIgnored private var peopleByRegion: [String: Int]?
    /// every town's country, folded name, division and people, for the regions' search to make its numbers off the main
    /// thread (an array, handed over without copying)
    func peopleRows() -> [(file: String, name: String, region: String, people: Int)] {
        rows.map { (file: $0.hit.file, name: $0.hit.name, region: $0.hit.region, people: $0.hit.people) }
    }

    /// EACH TOWN'S PEOPLE by country and folded name (: 150,000; the biggest of that name there): what the regions'
    /// search goes by for a second-level division, which is most often its town's name. Made once.
    func townPeople() -> [String: Int] {
        if let p = peopleByTown { return p }
        guard ready else { return [:] }
        var out: [String: Int] = [:]
        for r in rows {
            let k = r.hit.file.lowercased() + "|" + r.hit.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if r.hit.people > out[k] ?? 0 { out[k] = r.hit.people }
        }
        peopleByTown = out
        return out
    }
    @ObservationIgnored private var peopleByTown: [String: Int]?

    /// read the index once (in the background)
    func load() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            var out: [(String, Hit)] = []
            var gids: [Int] = []
            if case .ok(let d) = await Servers.data.file("native/towns/towns-index-2.wyti"),
               let all = try? JSONSerialization.jsonObject(with: d) as? [[Any]] {
                out.reserveCapacity(all.count)
                for r in all {
                    guard r.count >= 6, let n = r[0] as? String, let f = r[1] as? String else { continue }
                    let gid = (r[2] as? NSNumber)?.intValue ?? 0
                    let h = Hit(name: n, file: f, id: gid != 0 ? "\(f)/\(gid)" : "\(f)/\(n)",
                                people: (r[3] as? NSNumber)?.intValue ?? 0,
                                lat: (r[4] as? NSNumber)?.doubleValue ?? 0, lon: (r[5] as? NSNumber)?.doubleValue ?? 0,
                                region: r.count > 7 ? r[7] as? String ?? "" : "")
                    out.append((n.townFolded, h))
                    gids.append(gid)
                }
            }
            var alt = [String](repeating: "", count: out.count)
            if case .ok(let d) = await Servers.data.file("native/towns/towns-alt-1.wyta"),
               let all = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
                for (i, g) in gids.enumerated() where g != 0 {
                    if let a = all[String(g)] { alt[i] = "|" + a.townFolded }
                }
            }
            let own = Self.pack(out.map(\.0))
            let others = Self.pack(alt.map { $0.isEmpty ? "" : $0 + "|" })
            await MainActor.run {
                let me = TownIndex.shared
                me.rows = out
                me.alt = alt
                (me.ownBytes, me.ownStart) = own
                (me.altBytes, me.altStart) = others
                me.loading = false
                me.ready = !out.isEmpty
                #if DEBUG
                NSLog("wya town index: %d towns", out.count)
                #endif
            }
        }
    }

    /// one town by its key's id, if the index has come a town's other names, folded ( for Luzern), for finding its
    /// guide under the name English uses
    func otherNames(_ id: String) -> [String] {
        _ = hit(id)
        guard let i = byID?[id], i < alt.count else { return [] }
        return alt[i].split(separator: "|").map(String.init)
    }
    /// A COUNTRY'S BIGGEST TOWNS (the index is biggest first): what "japan" typed whole also lists (Tokyo, Yokohama,
    /// Osaka), made once per country
    func biggest(in cc: String, count: Int) -> [Hit] {
        let c = cc.lowercased()
        if let b = biggestBy[c] { return Array(b.prefix(count)) }
        guard ready else { return [] }
        var out: [Hit] = []
        for r in rows where r.hit.file.lowercased() == c {
            out.append(r.hit)
            if out.count == 3 { break }
        }
        biggestBy[c] = out
        return Array(out.prefix(count))
    }
    @ObservationIgnored private var biggestBy: [String: [Hit]] = [:]
    func hit(_ id: String) -> Hit? {
        if byID == nil, ready { byID = Dictionary(rows.enumerated().map { ($1.hit.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        if let byID { return byID[id].map { rows[$0].hit } }
        return rows.first { $0.hit.id == id }?.hit
    }
    /// ONE COUNTRY'S TOWN BY ITS NAME as it was typed (case and accents aside; its own name, then its other names), the
    /// most peopled of that name there, or nil: how a town written into a country's Details is found
    func named(_ name: String, in cc: String) -> Hit? {
        let q = name.trimmingCharacters(in: .whitespaces).townFolded
        guard ready, !q.isEmpty else { return nil }
        let c = cc.lowercased()
        if let r = rows.first(where: { $0.folded == q && $0.hit.file.lowercased() == c }) { return r.hit }
        guard alt.count == rows.count else { return nil }
        let bar = "|" + q + "|"
        for (i, a) in alt.enumerated() where !a.isEmpty && rows[i].hit.file.lowercased() == c && (a + "|").contains(bar) {
            return rows[i].hit
        }
        return nil
    }
    /// each town's row by its id, made once at the first look-up (the Stamped list asks for many)
    @ObservationIgnored private var byID: [String: Int]?

    /// DID YOU MEAN (1.10's rule for a typo, D12): nothing found, the biggest of the 40,000 most peopled towns within
    /// two letters' change of what was typed (its whole name or its first word; from four letters; is Frankfurt am
    /// Main), or nil
    @ObservationIgnored private var lastGuess: (q: String, hit: Hit?)?
    func guess(_ query: String) -> Hit? {
        let q = query.trimmingCharacters(in: .whitespaces).townFolded
        // (longer than any town's name give or take two: nothing to guess, and the guess's pass held the screen)
        guard ready, q.count >= 4, q.count <= 60 else { return nil }
        if let g = lastGuess, g.q == q { return g.hit }
        let a = Array(q.unicodeScalars)
        var best: (Hit, Int)?
        for r in rows.prefix(40_000) {
            // its whole name, or its first word when what was typed is one ( for Frankfurt am Main)
            let whole = Array(r.folded.unicodeScalars)
            let first = q.contains(" ") ? whole : Array((r.folded.split(separator: " ").first.map(String.init) ?? r.folded).unicodeScalars)
            let b = abs(a.count - first.count) < abs(a.count - whole.count) ? first : whole
            guard abs(a.count - b.count) <= 2 else { continue }
            let d = Self.distance(a, b, cap: 2)
            if d <= 2, best == nil || d < best!.1 { best = (r.hit, d); if d == 1 { break } }
        }
        lastGuess = (q, best?.0)
        return best?.0
    }
    /// letters to change, insert or drop (stopped past `cap`), with two neighbours swapped counting as one
    private static func distance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar], cap: Int) -> Int {
        let n = a.count, m = b.count
        var pp = [Int](repeating: 0, count: m + 1), p = Array(0 ... m), c = [Int](repeating: 0, count: m + 1)
        for i in 1 ... n {
            c[0] = i
            var low = c[0]
            for j in 1 ... m {
                var v = min(p[j] + 1, c[j - 1] + 1, p[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { v = min(v, pp[j - 2] + 1) }
                c[j] = v; low = min(low, v)
            }
            if low > cap { return cap + 1 }
            pp = p; p = c
        }
        return p[m]
    }

    /// the town nearest a spot within `km`, or nil (a pin's own place, 11.5's); nil until loaded
    func nearest(lat: Double, lon: Double, km: Double = 15) -> Hit? {
        guard ready else { return nil }
        let reach = km / 111.2, k = cos(lat * .pi / 180)
        var best: Hit?, bd = reach * reach
        for r in rows {
            let dy = r.hit.lat - lat
            guard abs(dy) < reach else { continue }
            var dx = r.hit.lon - lon
            if dx > 180 { dx -= 360 } else if dx < -180 { dx += 360 }
            dx *= k
            let d = dx * dx + dy * dy
            if d < bd { bd = d; best = r.hit }
        }
        return best.map(Self.asCity)
    }

    /// THE PLACE A SPOT IS IN, by the name people know: the nearest town, unless a city at least five times its size
    /// has the spot well inside it (within 2 km + √people / 200 of its middle: Barcelona 8.5 km, New York 17 km;
    /// Versailles, 17 km from Paris, stays Versailles)
    func place(lat: Double, lon: Double, km: Double = 15) -> Hit? {
        guard let n = nearest(lat: lat, lon: lon, km: km) else { return nil }
        let k = cos(lat * .pi / 180)
        for r in rows {
            let h = r.hit
            guard h.people >= 300_000 else { break }
            guard h.people >= n.people * 5, h.file == n.file else { continue }
            let reach = (2 + Double(h.people).squareRoot() / 200) / 111.2
            let dy = h.lat - lat, dx = (h.lon - lon) * k
            if dx * dx + dy * dy <= reach * reach { return Self.asCity(h) }
        }
        return n
    }

    /// the `count` towns nearest a point, nearest first (What's here?, A11.4), however far
    func nearest(lat: Double, lon: Double, count: Int) -> [Hit] {
        guard ready, count > 0 else { return [] }
        let k = cos(lat * .pi / 180)
        var best: [(Double, Hit)] = []
        var worst = Double.infinity
        for r in rows {
            let dy = r.hit.lat - lat
            guard best.count < count || dy * dy < worst else { continue }
            var dx = r.hit.lon - lon
            if dx > 180 { dx -= 360 } else if dx < -180 { dx += 360 }
            dx *= k
            let d = dx * dx + dy * dy
            guard best.count < count || d < worst else { continue }
            best.append((d, r.hit))
            best.sort { $0.0 < $1.0 }
            if best.count > count { best.removeLast() }
            if best.count == count { worst = best[count - 1].0 }
        }
        return best.map { Self.asCity($0.1) }
    }

    /// at most `limit` towns for what was typed: the open country's first (`open`, its file), then everywhere a
    /// district by its city's name ( is Paris); any other town as it is
    nonisolated static func asCity(_ h: Hit) -> Hit {
        guard isDistrict(h.name), let d = h.name.range(of: " [0-9]{1,2}( |$)", options: .regularExpression) else { return h }
        return Hit(name: String(h.name[..<d.lowerBound]), file: h.file, id: h.id, people: h.people, lat: h.lat, lon: h.lon, region: h.region)
    }
    /// a city's numbered district (,,)
    nonisolated static func isDistrict(_ n: String) -> Bool {
        n.range(of: "^[^0-9]+ [0-9]{1,2}( .*)?$", options: .regularExpression) != nil
    }
    func hits(_ query: String, open: String?, limit: Int = 6) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).townFolded
        guard ready, !q.isEmpty else { return [] }
        if let l = last, l.q == q, l.open == open { return l.hits }
        // (: a town whose name is exactly what was typed, in its own name or one of its other names, comes first: is
        // Lucerne (Luzern) before Lucerne Valley; the other names are looked at every time, not only when the own
        // names left room)
        var exact: [Hit] = []
        var home: [Hit] = [], away: [Hit] = [], homeIn: [Hit] = [], awayIn: [Hit] = []
        let qb = Array(q.utf8), ql = qb.count, inside = q.count >= 3
        guard ownStart.count == rows.count + 1 else { return [] }
        ownBytes.withUnsafeBufferPointer { nb in
            qb.withUnsafeBufferPointer { qp in
                guard let base = nb.baseAddress, let qa = qp.baseAddress else { return }
                for i in 0 ..< rows.count {
                    let a = Int(ownStart[i]), n = Int(ownStart[i + 1]) - a
                    // (the same tests as the names as strings: all of it, its start, anywhere in it from three letters)
                    let starts = n >= ql && memcmp(base + a, qa, ql) == 0
                    if starts && n == ql {
                        if exact.count < limit { exact.append(rows[i].hit) }
                    } else if starts {
                        if rows[i].hit.file == open { home.append(rows[i].hit) } else if away.count < limit { away.append(rows[i].hit) }
                    } else if inside, n > ql, memmem(base + a, n, qa, ql) != nil {
                        if rows[i].hit.file == open { if homeIn.count < limit { homeIn.append(rows[i].hit) } }
                        else if awayIn.count < limit { awayIn.append(rows[i].hit) }
                    }
                    // enough found: the open country's (or, with none open, everywhere's) names starting with what was typed
                    if home.count >= limit || (open == nil && away.count >= limit && exact.count >= 1) { break }
                }
            }
        }
        var exactAlt: [Hit] = [], homeAlt: [Hit] = [], awayAlt: [Hit] = []
        if q.count >= 2, !q.contains("|"), altStart.count == rows.count + 1 {
            // (each row's other names are: one starting with it holds "|q|q|")
            let bar = Array(("|" + q).utf8), whole = Array(("|" + q + "|").utf8)
            altBytes.withUnsafeBufferPointer { ab in
                bar.withUnsafeBufferPointer { bp in
                    whole.withUnsafeBufferPointer { wp in
                        guard let base = ab.baseAddress, let b = bp.baseAddress, let w = wp.baseAddress else { return }
                        for i in 0 ..< rows.count {
                            let a = Int(altStart[i]), n = Int(altStart[i + 1]) - a
                            guard n > bar.count, memmem(base + a, n, b, bar.count) != nil else { continue }
                            let hit = rows[i].hit
                            if memmem(base + a, n, w, whole.count) != nil {
                                if exactAlt.count < limit { exactAlt.append(hit) }
                            } else if hit.file == open { if homeAlt.count < limit { homeAlt.append(hit) } } else if awayAlt.count < limit { awayAlt.append(hit) }
                            if exactAlt.count >= limit { break }
                        }
                    }
                }
            }
        }
        // exact names, biggest first (the rows are in order of size)
        let exactAll = (exact + exactAlt).sorted { $0.people > $1.people }
        var seen = Set<String>()
        let numbered = !q.contains(where: \.isNumber)
        let h = Array((exactAll + home + homeIn + away + awayIn + homeAlt + awayAlt)
            .filter { seen.insert($0.id).inserted && !(numbered && Self.isDistrict($0.name)) }.prefix(limit))
        last = (q, open, h)
        return h
    }
}

extension String {
    /// a name as search compares it: case and accents gone, and German's written-out umlauts read as the plain vowel
    /// on both sides ( finds Zürich, Münster)
    nonisolated var townFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "þ", with: "th")
            .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "\u{2013}", with: " ").replacingOccurrences(of: "\u{2010}", with: " ")
            // (and an apostrophe is nothing: was only a for Côte d'Ivoire)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "ae", with: "a").replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
            // (one form of every letter, so names and what was typed compare as bytes as they did as strings)
            .precomposedStringWithCanonicalMapping
    }
}

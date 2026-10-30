import Foundation
import SwiftData

/// THE ONE WRITER (Part 0.2.2, 20.1): every write to stamps, wishes, visits and evidence goes through this actor, in
/// order, each one whole (SwiftData saves it in one transaction: killing the app mid-write keeps nothing half done).
/// It returns what changed and how to undo it; `MarkStore` is its face on the main thread.
@ModelActor
actor TravelStore {
    /// the stored values of one place's record, so a change can be undone exactly (nil: there was no record)
    struct Snapshot: Sendable {
        let key: PlaceKey
        let values: Values?
        /// the place's visits as they were, when the write removed them (an unstamp)
        var visits: [Visit]? = nil
        /// visits the write added (an import's found trips): undoing it takes them away again
        var added: [UUID]? = nil
        struct Visit: Sendable {
            var id: UUID
            var arrived, left, rough: String?
            var lived, transit: Bool
            var planId: String?
            var source: String
        }
        struct Values: Sendable {
            var stamped, wished: Bool
            var want: Int
            var wishWhen: String?
            var at: Date
            var source: String
            var times: Int
            var lived: Bool
            var note: String
            var how: String?
            var when: String?
            var details, wishDetails, verification: Data?
            var via: String?
            var came: Date?
            var name, cc: String
            var level: Int
        }
    }

    /// what one write did: the places it changed, before and after, and the snapshots that undo it
    struct Result: Sendable {
        var changed: [PlaceKey: (old: MarkState, new: MarkState)] = [:]
        var undo: [Snapshot] = []
    }

    private func record(_ account: String, _ key: PlaceKey) throws -> StampRecord? {
        let k = key.description
        var d = FetchDescriptor<StampRecord>(predicate: #Predicate { $0.account == account && $0.key == k })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func visitCount(_ account: String, _ key: PlaceKey) throws -> Int {
        let k = key.description
        return try modelContext.fetchCount(FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.account == account && $0.key == k }))
    }

    private func state(_ r: StampRecord?, visits: Int) -> MarkState {
        guard let r else { return .none }
        return MarkState(stamped: r.stamped, visits: max(r.times, visits), transitOnly: false, lived: r.lived,
                         wished: r.wished, want: r.wished ? r.want : 0)
    }

    private func snapshot(_ key: PlaceKey, _ r: StampRecord?) -> Snapshot {
        guard let r else { return Snapshot(key: key, values: nil) }
        return Snapshot(key: key, values: .init(stamped: r.stamped, wished: r.wished, want: r.want, wishWhen: r.wishWhen,
                                                at: r.at, source: r.source, times: r.times, lived: r.lived, note: r.note,
                                                how: r.how, when: r.when, details: r.details, wishDetails: r.wishDetails,
                                                verification: r.verification, via: r.via, came: r.came, name: r.name,
                                                cc: r.cc, level: r.level))
    }

    /// Every mark there is for an account (the map's start).
    func all(account: String) throws -> [PlaceKey: MarkState] {
        var out: [PlaceKey: MarkState] = [:]
        for r in try modelContext.fetch(FetchDescriptor<StampRecord>(predicate: #Predicate { $0.account == account })) {
            if let k = PlaceKey(r.key) { out[k] = state(r, visits: 0) }
        }
        let vs = try modelContext.fetch(FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.account == account }))
        var counts: [String: Int] = [:]
        for v in vs { counts[v.key, default: 0] += 1 }
        for (k, n) in counts { if let pk = PlaceKey(k), var s = out[pk] { s.visits = max(s.visits, n); out[pk] = s } }
        return out
    }

    /// A STAMPED PLACE'S DETAILS (Part 4.4), as one write and one undo step: the details JSON, the times you typed and
    /// the lived flag; nothing is written when nothing changed
    func setDetails(_ key: PlaceKey, account: String, details: Data?, times: Int, lived: Bool) throws -> Result {
        var res = Result()
        guard let r = try record(account, key), r.stamped else { return res }
        guard r.details != details || r.times != times || r.lived != lived else { return res }
        let v = try visitCount(account, key)
        res.undo.append(snapshot(key, r))
        let old = state(r, visits: v)
        r.details = details
        r.times = max(1, max(times, v))
        r.lived = lived
        res.changed[key] = (old, state(r, visits: v))
        try modelContext.save()
        return res
    }

    /// THE STAMPED LIST'S SECOND LINE (4.6.3): each stamped place's latest visit year (its latest dated visit, else
    /// the details' dates, else the month it was stamped for) and whether its stamp is verified
    func listInfo(account: String) throws -> [String: (year: Int?, verified: Bool)] {
        let rs = try modelContext.fetch(FetchDescriptor<StampRecord>(predicate: #Predicate { $0.account == account && $0.stamped }))
        let vs = try modelContext.fetch(FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.account == account }))
        func year(_ s: String?) -> Int? { s.flatMap { Int($0.prefix(4)) } }
        var latest: [String: Int] = [:]
        for v in vs { if let y = year(v.arrived) { latest[v.key] = max(latest[v.key] ?? 0, y) } }
        var out: [String: (year: Int?, verified: Bool)] = [:]
        for r in rs {
            let d = StampDetails(json: r.details)
            let y = latest[r.key] ?? [year(d.to), year(d.from)].compactMap { $0 }.max() ?? year(r.when)
            var verified = false
            if let v = r.verification, let o = try? JSONSerialization.jsonObject(with: v) as? [String: Any] {
                verified = (o["state"] as? String) == "verified"
            }
            out[r.key] = (y, verified)
        }
        return out
    }

    /// A STAMP'S PROOF (Part 4.5): the verification JSON as one write and one undo step (nil: none)
    func setVerification(_ key: PlaceKey, account: String, data: Data?) throws -> Result {
        var res = Result()
        guard let r = try record(account, key), r.stamped, r.verification != data else { return res }
        let v = try visitCount(account, key)
        res.undo.append(snapshot(key, r))
        let old = state(r, visits: v)
        r.verification = data
        res.changed[key] = (old, state(r, visits: v))
        try modelContext.save()
        return res
    }
    func verificationOf(_ key: PlaceKey, account: String) throws -> Data? {
        try record(account, key)?.verification
    }

    /// A WISHED PLACE'S DETAILS (Part 4.4.5), as one write and one undo step: the wish details JSON and how badly
    /// (`want`, 1 to 5); nothing is written when nothing changed
    func setWishDetails(_ key: PlaceKey, account: String, details: Data?, want: Int) throws -> Result {
        var res = Result()
        guard let r = try record(account, key), r.wished else { return res }
        let w = max(1, min(5, want))
        guard r.wishDetails != details || r.want != w else { return res }
        let v = try visitCount(account, key)
        res.undo.append(snapshot(key, r))
        let old = state(r, visits: v)
        r.wishDetails = details
        r.want = w
        res.changed[key] = (old, state(r, visits: v))
        try modelContext.save()
        return res
    }

    /// what a wished place's record holds for Details: its wish details JSON and how badly
    func wishDetailsOf(_ key: PlaceKey, account: String) throws -> (details: Data?, want: Int)? {
        guard let r = try record(account, key), r.wished else { return nil }
        return (r.wishDetails, max(1, r.want))
    }

    /// what a stamped place's record holds for Details: its details JSON, times and lived
    func detailsOf(_ key: PlaceKey, account: String) throws -> (details: Data?, times: Int, lived: Bool)? {
        guard let r = try record(account, key), r.stamped else { return nil }
        return (r.details, r.times, r.lived)
    }

    /// THE PASSPORT'S ORDER (the old StampBook's: by when, then by id): the countries stamped, oldest first; each takes
    /// the next slot of the book
    func passportOrder(account: String) throws -> [String] {
        let rs = try modelContext.fetch(FetchDescriptor<StampRecord>(predicate: #Predicate { $0.account == account && $0.stamped }))
        return rs.filter { $0.key.hasPrefix("c:") }
            .sorted { ($0.when ?? "", $0.at, $0.key) < ($1.when ?? "", $1.at, $1.key) }
            .map { String($0.key.dropFirst(2)) }
    }

    /// When each mark was made (for the Streak: weeks with an act).
    func markDates(account: String) throws -> [Date] {
        try modelContext.fetch(FetchDescriptor<StampRecord>(predicate: #Predicate { $0.account == account })).map(\.at)
    }

    // MARK: the writes (the old StampBook's rules)

    /// STAMP a place. A wished place loses its wish and keeps when it was wished (`came`). A region, town or thing in one
    /// country stamps that country too, on only (unstamping it later leaves the country), the old app's cascade.
    func stamp(_ key: PlaceKey, account: String, source: MarkSource, at: Date = Date(),
               name: String = "", cc: String = "", level: Int = 0) throws -> Result {
        var res = Result()
        try stampOne(key, account: account, source: source, at: at, name: name, cc: cc, level: level, via: nil, into: &res)
        if key.kind != .country, !cc.isEmpty {
            let c = PlaceKey.country(cc.lowercased())
            if try record(account, c)?.stamped != true {
                try stampOne(c, account: account, source: source, at: at, name: "", cc: cc, level: 0, via: key.description, into: &res)
            }
        }
        try modelContext.save()
        return res
    }

    private func stampOne(_ key: PlaceKey, account: String, source: MarkSource, at: Date, name: String, cc: String,
                          level: Int, via: String?, into res: inout Result) throws {
        let r0 = try record(account, key)
        let v = try visitCount(account, key)
        if r0?.stamped == true { return }
        res.undo.append(snapshot(key, r0))
        let old = state(r0, visits: v)
        let r = r0 ?? { let n = StampRecord(account: account, key: key); modelContext.insert(n); return n }()
        if r.wished { r.came = r.at }
        r.wished = false; r.want = 0; r.wishWhen = nil; r.wishDetails = nil
        r.stamped = true
        r.at = at
        r.source = source.rawValue
        r.times = max(1, r.times)
        r.via = via
        if !name.isEmpty { r.name = name }
        if !cc.isEmpty { r.cc = cc }
        if level > 0 { r.level = level }
        res.changed[key] = (old, state(r, visits: v))
    }

    /// UNSTAMP: the record goes, with its details, its proof and when it was wished (the old dropDetails); the places it
    /// stamped through (`via`) go with it only when nothing else holds them (a country stays stamped).
    func unstamp(_ key: PlaceKey, account: String) throws -> Result {
        var res = Result()
        guard let r = try record(account, key), r.stamped else { return res }
        let v = try visitCount(account, key)
        var snap = snapshot(key, r)
        // its visits go with it (Part 0.2.5), its evidence stays
        let k = key.description
        let visits = try modelContext.fetch(FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.account == account && $0.key == k }))
        snap.visits = visits.map { .init(id: $0.id, arrived: $0.arrived, left: $0.left, rough: $0.rough, lived: $0.lived,
                                         transit: $0.transit, planId: $0.planId, source: $0.source) }
        for x in visits { modelContext.delete(x) }
        res.undo.append(snap)
        res.changed[key] = (state(r, visits: v), .none)
        modelContext.delete(r)
        try modelContext.save()
        return res
    }

    /// WISH a place, `want` 1 to 5. A stamped place can't be wished (the old toggleWish refused it).
    func wish(_ key: PlaceKey, account: String, want: Int = 3, source: MarkSource = .hand,
              name: String = "", cc: String = "", level: Int = 0) throws -> Result {
        var res = Result()
        let r0 = try record(account, key)
        if r0?.stamped == true { return res }
        if r0?.wished == true && r0?.want == want { return res }
        res.undo.append(snapshot(key, r0))
        let old = state(r0, visits: 0)
        let r = r0 ?? { let n = StampRecord(account: account, key: key); modelContext.insert(n); return n }()
        r.wished = true
        r.want = min(5, max(1, want))
        r.at = Date()
        r.source = source.rawValue
        if !name.isEmpty { r.name = name }
        if !cc.isEmpty { r.cc = cc }
        if level > 0 { r.level = level }
        res.changed[key] = (old, state(r, visits: 0))
        try modelContext.save()
        return res
    }

    func unwish(_ key: PlaceKey, account: String) throws -> Result {
        var res = Result()
        guard let r = try record(account, key), r.wished else { return res }
        res.undo.append(snapshot(key, r))
        res.changed[key] = (state(r, visits: 0), .none)
        modelContext.delete(r)
        try modelContext.save()
        return res
    }

    /// THE OLD APP'S BOOK, read in (OldStamps.swift) as one write and one undo step. It only adds: a place that
    /// already has a record here keeps it as it is (nothing you did in this app is overwritten).
    func importOld(_ book: OldBook, account: String) throws -> Result {
        var res = Result()
        for row in book.rows {
            guard try record(account, row.key) == nil else { continue }
            res.undo.append(snapshot(row.key, nil))
            let r = StampRecord(account: account, key: row.key)
            modelContext.insert(r)
            r.stamped = row.stamped; r.wished = row.wished; r.want = row.want
            r.at = row.at; r.source = MarkSource.imported.rawValue; r.times = row.times; r.lived = row.lived
            r.note = row.note; r.how = row.how; r.when = row.when; r.via = row.via; r.came = row.came
            r.name = row.name; r.cc = row.cc; r.level = row.level
            r.details = row.details; r.wishDetails = row.wishDetails; r.verification = row.verification
            res.changed[row.key] = (.none, state(r, visits: 0))
        }
        try modelContext.save()
        return res
    }

    /// AN UPLOAD'S FINDS STAMPED (Part 9.5's go), as one write and one undo step: each place stamped (source the
    /// import; a wished one loses its wish) unless it already is, and each found trip added as a dated visit unless
    /// the place has that trip already; times rise to the visits there are. Undo takes the stamps and these visits
    /// away again (and nothing else).
    struct Found: Sendable {
        var key: PlaceKey
        var name: String
        var cc: String
        /// each trip's first and last day ("2024-08-03")
        var trips: [(String, String)]
    }
    func importFinds(_ finds: [Found], account: String, source: MarkSource, at: Date = Date()) throws -> Result {
        var res = Result()
        for f in finds {
            let r0 = try record(account, f.key)
            let k = f.key.description
            let have = try modelContext.fetch(FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.account == account && $0.key == k }))
            let new = f.trips.filter { t in !have.contains { $0.arrived == t.0 && $0.left == t.1 } }
            if r0?.stamped == true && new.isEmpty { continue }
            var snap = snapshot(f.key, r0)
            let old = state(r0, visits: have.count)
            let r = r0 ?? { let n = StampRecord(account: account, key: f.key); modelContext.insert(n); return n }()
            if r.stamped != true {
                if r.wished { r.came = r.at }
                r.wished = false; r.want = 0; r.wishWhen = nil; r.wishDetails = nil
                r.stamped = true; r.at = at; r.source = source.rawValue; r.via = nil
                if !f.name.isEmpty { r.name = f.name }
                if !f.cc.isEmpty { r.cc = f.cc }
            }
            var ids: [UUID] = []
            for t in new {
                let v = VisitRecord(account: account, key: f.key)
                v.arrived = t.0; v.left = t.1; v.source = source.rawValue
                modelContext.insert(v)
                ids.append(v.id)
            }
            snap.added = ids
            r.times = max(1, r.times, have.count + new.count)
            res.undo.append(snap)
            res.changed[f.key] = (old, state(r, visits: have.count + new.count))
        }
        try modelContext.save()
        return res
    }

    /// PUT BACK what a write changed (its snapshots), as one write
    func restore(_ snaps: [Snapshot], account: String) throws -> Result {
        var res = Result()
        for s in snaps.reversed() {
            let r0 = try record(account, s.key)
            // the visits this write added go (kept in the redo's snapshot, so a redo puts them back)
            var gone: [Snapshot.Visit] = []
            for id in s.added ?? [] {
                if let x = try modelContext.fetch(FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.account == account && $0.id == id })).first {
                    gone.append(.init(id: x.id, arrived: x.arrived, left: x.left, rough: x.rough, lived: x.lived,
                                      transit: x.transit, planId: x.planId, source: x.source))
                    modelContext.delete(x)
                }
            }
            let v = try visitCount(account, s.key)
            var redo = snapshot(s.key, r0)
            if !gone.isEmpty { redo.visits = gone }
            if let back = s.visits, !back.isEmpty { redo.added = back.map(\.id) }
            res.undo.append(redo)
            let old = state(r0, visits: v)
            if let vals = s.values {
                let r = r0 ?? { let n = StampRecord(account: account, key: s.key); modelContext.insert(n); return n }()
                r.stamped = vals.stamped; r.wished = vals.wished; r.want = vals.want; r.wishWhen = vals.wishWhen
                r.at = vals.at; r.source = vals.source; r.times = vals.times; r.lived = vals.lived; r.note = vals.note
                r.how = vals.how; r.when = vals.when; r.details = vals.details; r.wishDetails = vals.wishDetails
                r.verification = vals.verification; r.via = vals.via; r.came = vals.came
                r.name = vals.name; r.cc = vals.cc; r.level = vals.level
                res.changed[s.key] = (old, state(r, visits: v))
            } else if let r0 {
                modelContext.delete(r0)
                res.changed[s.key] = (old, .none)
            }
            for x in s.visits ?? [] {
                let n = VisitRecord(account: account, key: s.key)
                n.id = x.id; n.arrived = x.arrived; n.left = x.left; n.rough = x.rough; n.lived = x.lived
                n.transit = x.transit; n.planId = x.planId; n.source = x.source
                modelContext.insert(n)
            }
        }
        try modelContext.save()
        return res
    }

    /// SIGN OUT (Part 19.3, 20.10): everything of an account goes
    func empty(account: String) throws {
        try modelContext.delete(model: StampRecord.self, where: #Predicate { $0.account == account })
        try modelContext.delete(model: VisitRecord.self, where: #Predicate { $0.account == account })
        try modelContext.delete(model: EvidenceRecord.self, where: #Predicate { $0.account == account })
        try modelContext.save()
    }
}

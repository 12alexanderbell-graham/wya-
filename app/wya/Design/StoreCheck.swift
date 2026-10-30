#if DEBUG
import Foundation
import SwiftData
import CoreGraphics

/// THE STORE'S CHECKS (Part 0.2.5's six, the old stamps.json read and a schema reopen), run inside the app by the test
/// driver's `storecheck` command, against a store of their own in memory (the demo account is not touched, except by
/// check 6, which uses the real MarkStore and undoes itself). Results into snaps/storecheck.log, one line each:
/// PASS or FAIL, and what was seen.
@MainActor
enum StoreCheck {
    static func run() async -> [String] {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool, _ seen: String) { out.append("\(ok ? "PASS" : "FAIL") \(name): \(seen)") }

        // 1. a photo taken at 1 am in Tokyo lands on the Tokyo day (the day where it happened, not the phone's)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 11; c.hour = 1; c.minute = 0
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tokyo
        let shot = cal.date(from: c)!
        let day = LocalDay(shot, in: tokyo)
        let utcDay = LocalDay(shot, in: TimeZone(identifier: "UTC")!)
        check("1 Tokyo day", day.description == "2026-03-11", "Tokyo \(day), the same instant in UTC \(utcDay)")

        // a store of its own, in memory
        let schema = Schema(versionedSchema: TravelSchemaV1.self)
        guard let box = try? ModelContainer(for: schema, configurations: ModelConfiguration("Check", schema: schema, isStoredInMemoryOnly: true)) else {
            check("store", false, "no in-memory container"); return out
        }
        let store = TravelStore(modelContainer: box)
        let acc = "check"
        let fr = PlaceKey.country("fr")

        // 2. a wish and a stamp never both exist
        _ = try? await store.wish(fr, account: acc)
        _ = try? await store.stamp(fr, account: acc, source: .hand)
        var all = (try? await store.all(account: acc)) ?? [:]
        let afterStamp = all[fr] ?? .none
        let refused = (try? await store.wish(fr, account: acc))?.changed.isEmpty ?? false
        all = (try? await store.all(account: acc)) ?? [:]
        check("2 never both", afterStamp.stamped && !afterStamp.wished && refused && all[fr]?.wished == false,
              "wish then stamp: stamped \(afterStamp.stamped) wished \(afterStamp.wished); a wish on a stamped place refused \(refused)")

        // 3. unstamping removes the place's visits, not its evidence
        let ctx = ModelContext(box)
        ctx.insert(VisitRecord(account: acc, key: fr))
        ctx.insert(VisitRecord(account: acc, key: fr))
        ctx.insert(EvidenceRecord(account: acc, key: fr, day: LocalDay(y: 2025, m: 5, d: 1)))
        try? ctx.save()
        _ = try? await store.unstamp(fr, account: acc)
        let k = fr.description
        let visits = (try? ModelContext(box).fetchCount(FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.key == k }))) ?? -1
        let evidence = (try? ModelContext(box).fetchCount(FetchDescriptor<EvidenceRecord>(predicate: #Predicate { $0.key == k }))) ?? -1
        check("3 unstamp keeps evidence", visits == 0 && evidence == 1, "visits \(visits) (were 2), evidence \(evidence) (was 1)")

        // 4. a write cut off before its save leaves nothing (each write is one save; what was not saved is gone)
        let cut = ModelContext(box)
        cut.autosaveEnabled = false
        cut.insert(StampRecord(account: acc, key: .country("jp")))
        let jk = "c:jp"
        _ = cut   // the "killed" write: never saved, dropped here
        let half = (try? ModelContext(box).fetchCount(FetchDescriptor<StampRecord>(predicate: #Predicate { $0.key == jk }))) ?? -1
        check("4 nothing half done", half == 0, "records of an unsaved write seen by a new context: \(half)")

        // 5. every write is one undo step: a town stamps its country too, and one undo takes both back
        let town = PlaceKey(.town, "mn/2028462")
        let w = try? await store.stamp(town, account: acc, source: .hand, name: "Ulaanbaatar", cc: "mn")
        let both = (try? await store.all(account: acc)) ?? [:]
        _ = try? await store.restore(w?.undo ?? [], account: acc)
        let after = (try? await store.all(account: acc)) ?? [:]
        check("5 one undo step", (w?.changed.count ?? 0) == 2 && both[.country("mn")]?.stamped == true
              && after[town] == nil && after[.country("mn")] == nil,
              "one write changed \(w?.changed.count ?? 0) places (the town and Mongolia); after one undo: town \(after[town] == nil ? "gone" : "still there"), Mongolia \(after[.country("mn")] == nil ? "gone" : "still there")")

        // 6. marksChanged carries the origin of the touch (the real MarkStore; undone at once)
        let ms = MarkStore.shared
        var seen: CGPoint?
        var who: Who?
        let token = ms.listen { ch in seen = ch.origin; who = ch.who }
        let aq = PlaceKey.country("aq")
        let wasStamped = ms.state(aq).stamped
        if wasStamped { await ms.unstamp(aq, origin: CGPoint(x: 10, y: 20)) } else { await ms.stamp(aq, origin: CGPoint(x: 10, y: 20)) }
        let got = seen
        await ms.undo()
        ms.stopListening(token)
        check("6 origin", got == CGPoint(x: 10, y: 20) && who == .undo && ms.state(aq).stamped == wasStamped,
              "origin \(got.map { "\($0)" } ?? "none"), the undo's change said who \(who.map { $0.rawValue } ?? "none"), Antarctica back as it was \(ms.state(aq).stamped == wasStamped)")

        // 7. the old app's stamps.json, read into an empty store (the fixture in snaps)
        if let d = try? Data(contentsOf: URL(fileURLWithPath: Snap.dir + "/old-stamps-fixture.json")), let book = try? OldBook(json: d) {
            let r = try? await store.importOld(book, account: "old")
            let m = (try? await store.all(account: "old")) ?? [:]
            let moved = m[PlaceKey(.region, "OSM-r1250591")] != nil && m[PlaceKey(.region, "IRN120")] != nil
                && m[PlaceKey(.town, "br/6317631")] != nil && m[PlaceKey(.region, "ALB210")] == nil
            check("7 old stamps.json", (r?.changed.count ?? 0) == 10 && moved && m[.country("mn")]?.stamped == true
                  && m[.country("mn")]?.wished == false && m[.country("pe")]?.want == 5,
                  "\(r?.changed.count ?? 0) places in (10 in the fixture), key moves applied \(moved), Mongolia stamped not wished, Peru wished 5; waiting \(book.waiting)")
        } else {
            check("7 old stamps.json", false, "no fixture at snaps/old-stamps-fixture.json")
        }
        return out
    }
}
#endif

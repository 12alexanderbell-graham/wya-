import ActivityKit
import BackgroundTasks
import UIKit

/// A PLAN ON THE LOCK SCREEN: from seven days before a dated plan starts to its last day, one Live Activity for it, the
/// nearest such plan if there are two. The map in a square, never a rectangle; "3 days to Bangkok" the big words,
/// filling the room beside the map; the dates in numbers; the other places on a line under. On the trip it goes
/// through the plan: the day's place big, "Day 2 of 7", the day's things. Worked out again when the app comes up and
/// when your plans change; gone when no plan is near.
@MainActor
enum PlanLive {
    /// how many days before a plan starts it comes onto the lock screen
    static let ahead = 7

    /// what the lock screen should show now: the plan, how many days to its start (negative: days into it)
    static func pick(_ plans: [Plan], today: String) -> (plan: Plan, toStart: Int)? {
        guard let t = PlanDates.date(today) else { return nil }
        return plans.compactMap { p -> (Plan, Int)? in
            guard !p.arch, !p.hid, !p.ai, !p.start.isEmpty, let s = PlanDates.date(p.start),
                  let e = PlanDates.date(p.end.isEmpty ? p.start : p.end) else { return nil }
            let toStart = PlanDates.cal.dateComponents([.day], from: t, to: s).day ?? 0
            let toEnd = PlanDates.cal.dateComponents([.day], from: t, to: e).day ?? 0
            guard toEnd >= 0, toStart <= ahead else { return nil }
            return (p, toStart)
        }
        .sorted { $0.1 < $1.1 }.first
    }

    /// a plan's places, in its order, each once ("Lisbon, Portugal" is Lisbon)
    static func places(_ items: [PlanItem]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { i -> String? in
            let n = i.place.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            return n.isEmpty || !seen.insert(n.lowercased()).inserted ? nil : n
        }
    }

    /// the dates in numbers: "13–20.10", across a month "28.10–3.11", one day "13.10"
    static func dates(_ p: Plan) -> String {
        guard let s = PlanDates.date(p.start) else { return "" }
        let e = PlanDates.date(p.end.isEmpty ? p.start : p.end) ?? s
        let a = PlanDates.cal.dateComponents([.day, .month], from: s), b = PlanDates.cal.dateComponents([.day, .month], from: e)
        let (ad, am, bd, bm) = (a.day ?? 1, a.month ?? 1, b.day ?? 1, b.month ?? 1)
        if s == e { return "\(ad).\(am)" }
        return am == bm ? "\(ad)–\(bd).\(bm)" : "\(ad).\(am)–\(bd).\(bm)"
    }

    static func state(_ p: Plan, toStart: Int) -> PlanLiveAttributes.ContentState {
        let all = places(p.days.flatMap(\.items))
        // (no places in it yet: the town or country its name says, as its cover; else none: "3 days to Our honeymoon
        // across Southeast Asia" read as a sentence gone wrong, so it is "3 days to go" with the plan's name under)
        let named = all.isEmpty ? (ListsWater.namedTown(p.name)?.name
            ?? ListsWater.namedCountry(p.name).flatMap { cc in AIContext.map?.world.flatMap { w in w.placeIndex[cc].map { w.places[$0].n } } }) : nil
        let first = all.first ?? named
        if toStart > 0 {
            let days = toStart == 1 ? "1 day" : "\(toStart) days"
            guard let first else {
                return .init(big: "\(days) to go", dates: dates(p), line: p.name, short: "\(toStart)d")
            }
            return .init(big: "\(days) to \(first)", dates: dates(p), line: all.dropFirst().joined(separator: ", "), short: "\(toStart)d")
        }
        // on the trip: the day it is, its place and its things
        let i = min(max(0, -toStart), max(0, p.days.count - 1))
        let day = p.days.indices.contains(i) ? p.days[i].items : []
        let place = places(day).first ?? first ?? p.name
        // (the day's things in their order by time, each with its time as the plan has it, "14:00 Grand Palace"; the
        // ones with no time after, as they are in the plan)
        let ordered = day.enumerated().sorted { a, b in
            switch (PlanItem.minutes(a.element.at), PlanItem.minutes(b.element.at)) {
            case let (x?, y?): return x != y ? x < y : a.offset < b.offset
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
        let things = ordered.compactMap { it -> String? in
            guard !it.what.isEmpty else { return nil }
            guard let m = PlanItem.minutes(it.at) else { return it.what }
            return "\(m / 60):" + String(format: "%02d", m % 60) + " " + it.what
        }
        let len = max(p.days.count, PlanDates.length(p.start, p.end.isEmpty ? p.start : p.end))
        return .init(big: place, dates: "Day \(i + 1) of \(len)", line: things.joined(separator: ", "), short: "Day \(i + 1)")
    }

    /// the plan's map square for the lock screen, from the same map its cover is made from
    static func writeMap(_ p: Plan) async {
        guard let u = PlanLiveAttributes.mapURL(p.id) else { return }
        // (the towns and sights read first, a few seconds at most: drawn as the app came up, before them, each place
        // stood at its country's middle and Bangkok, Chiang Mai and Krabi were one dot, 25 Nov)
        TownIndex.shared.load(); ThingIndex.shared.load()
        for _ in 0 ..< 60 where !(TownIndex.shared.ready && ThingIndex.shared.ready) { try? await Task.sleep(for: .milliseconds(100)) }
        // (the world too: its outlines frame the countries)
        for _ in 0 ..< 60 where AIContext.map?.world == nil { try? await Task.sleep(for: .milliseconds(100)) }
        let c = ListsWater.planCover(p)
        // (a plan with no places has no map: the cover maker's whole-world picture is for lists)
        guard !c.ccs.isEmpty, let img = await ListMapCovers.image(c.ccs, spots: c.spots, world: AIContext.map?.world,
                                                  size: CGSize(width: 64, height: 64), scale: 2),
              let png = img.pngData() else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: u, options: .atomic)
    }

    /// the lock screen made right: the plan near now on it, any other taken off
    static func refresh() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let running = Activity<PlanLiveAttributes>.activities
        guard let (p, toStart) = pick(ListsStore.shared.book.plans, today: PlanDates.key(local: Date())) else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            // (a plan further off: woken each midnight until it comes within the days before it)
            let today = PlanDates.key(local: Date())
            if ListsStore.shared.book.plans.contains(where: { !$0.arch && !$0.hid && !$0.ai && !$0.start.isEmpty && $0.start > today }) {
                scheduleNext()
            }
            return
        }
        for a in running where a.attributes.plan != p.id { await a.end(nil, dismissalPolicy: .immediate) }
        await writeMap(p)
        // (stale at the next midnight: a day the app was not opened, the lock screen knows its count is old)
        let content = ActivityContent(state: state(p, toStart: toStart), staleDate: nextMidnight())
        if let a = running.first(where: { $0.attributes.plan == p.id }) {
            await a.update(content)
        } else {
            _ = try? Activity.request(attributes: PlanLiveAttributes(plan: p.id, name: p.name), content: content)
        }
        // (counted again just after midnight, the app not opened: "3 days to Bangkok" becomes 2 by itself)
        scheduleNext()
        // (the towns or sights still being read after the wait: the map square drawn again once they are, its places
        // where they are, not all at the country's middle, 25 Nov; a few times at most)
        if !(TownIndex.shared.ready && ThingIndex.shared.ready), tries < 6 {
            tries += 1
            soon?.cancel()
            soon = Task { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled { await refresh() } }
        } else { tries = 0 }
    }
    private static var tries = 0

    /// THE DAY'S NEW COUNT IN THE BACKGROUND: the app asks iOS to wake it a minute after midnight (wyaApp's
    /// .backgroundTask runs refresh), so a plan on the lock screen counts its days down with the app closed; iOS picks
    /// the moment, so the activity is also marked stale at midnight
    static let task = "com.alexanderbell.wya.planlive"
    static func nextMidnight() -> Date {
        let cal = Calendar.current
        return cal.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86_400)
    }
    static func scheduleNext() {
        let r = BGAppRefreshTaskRequest(identifier: task)
        r.earliestBeginDate = nextMidnight()
        do { try BGTaskScheduler.shared.submit(r) } catch {
            #if DEBUG
            NSLog("wya planlive: the midnight wake-up not booked: %@", String(describing: error))
            #endif
        }
    }
    /// after a change to your plans: once, a moment later (typing a plan's name changes it at every letter)
    private static var soon: Task<Void, Never>?
    static func changed() {
        soon?.cancel()
        soon = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { await refresh() } }
    }
}

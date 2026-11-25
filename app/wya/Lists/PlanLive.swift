import ActivityKit
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
        let first = all.first ?? p.name
        if toStart > 0 {
            let big = toStart == 1 ? "1 day to \(first)" : "\(toStart) days to \(first)"
            return .init(big: big, dates: dates(p), line: all.dropFirst().joined(separator: ", "), short: "\(toStart)d")
        }
        // on the trip: the day it is, its place and its things
        let i = min(max(0, -toStart), max(0, p.days.count - 1))
        let day = p.days.indices.contains(i) ? p.days[i].items : []
        let place = places(day).first ?? first
        let things = day.map(\.what).filter { !$0.isEmpty }
        let len = max(p.days.count, PlanDates.length(p.start, p.end.isEmpty ? p.start : p.end))
        return .init(big: place, dates: "Day \(i + 1) of \(len)", line: things.joined(separator: ", "), short: "Day \(i + 1)")
    }

    /// the plan's map square for the lock screen, from the same map its cover is made from
    static func writeMap(_ p: Plan) async {
        guard let u = PlanLiveAttributes.mapURL(p.id) else { return }
        let c = ListsWater.planCover(p)
        guard let img = await ListMapCovers.image(c.ccs, spots: c.spots, world: AIContext.map?.world,
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
            return
        }
        for a in running where a.attributes.plan != p.id { await a.end(nil, dismissalPolicy: .immediate) }
        await writeMap(p)
        let content = ActivityContent(state: state(p, toStart: toStart), staleDate: nil)
        if let a = running.first(where: { $0.attributes.plan == p.id }) {
            await a.update(content)
        } else {
            _ = try? Activity.request(attributes: PlanLiveAttributes(plan: p.id, name: p.name), content: content)
        }
    }
    /// after a change to your plans: once, a moment later (typing a plan's name changes it at every letter)
    private static var soon: Task<Void, Never>?
    static func changed() {
        soon?.cancel()
        soon = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { await refresh() } }
    }
}

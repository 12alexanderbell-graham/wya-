import SwiftUI

/// A DATED PLAN AS ITS CALENDAR:
/// the plan's months, a week to a row from Monday, each day its number; the plan's days under one black capsule a week,
/// their numbers white, a day with something planned in semibold. A plan day tapped opens that day hour by hour; a day
/// before or after the plan tapped makes the plan reach to it. The month before and after the plan are there by name, a
/// tap opening them, so there is always a day to reach to.
struct PlanMonths: View {
    let plan: Plan
    let open: (Int) -> Void
    let reach: (String) -> Void

    /// the months either side of the plan opened (folded to their names until tapped)
    @State private var opened: Set<String> = []

    var body: some View {
        let months = Self.months(plan)
        VStack(alignment: .leading, spacing: 22) {
            ForEach(months, id: \.self) { m in month(m) }
        }
        .padding(.top, 12)
    }

    /// first-of-month keys from the month before the plan to the month after
    static func months(_ p: Plan) -> [String] {
        guard let a = PlanDates.date(p.start), let b = PlanDates.date(p.end) else { return [] }
        let cal = PlanDates.cal
        var c = cal.dateComponents([.year, .month], from: a)
        c.day = 1
        guard var m = cal.date(from: c), let last0 = cal.date(from: { var x = cal.dateComponents([.year, .month], from: b); x.day = 1; return x }()) else { return [] }
        m = cal.date(byAdding: .month, value: -1, to: m) ?? m
        let last = cal.date(byAdding: .month, value: 1, to: last0) ?? last0
        var out: [String] = []
        while m <= last, out.count < 14 {
            out.append(PlanDates.key(m))
            m = cal.date(byAdding: .month, value: 1, to: m) ?? last.addingTimeInterval(1)
        }
        return out
    }

    // THE PLAN'S DAYS AS ONE BAND: a week at a time, the plan's days in it under one black capsule, as the
    // app's own chosen chips are black capsules; white numbers on it, a day with something planned in semibold (no bar
    // under it). The month before and after the plan are their names only (50% ink) until tapped
    private func month(_ first: String) -> some View {
        let cal = PlanDates.cal
        let d = PlanDates.date(first) ?? Date()
        let n = cal.range(of: .day, in: .month, for: d)?.count ?? 30
        // Monday first
        let lead = (cal.component(.weekday, from: d) + 5) % 7
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "LLLL yyyy"
        let last = PlanDates.key(first, n - 1)
        let outside = last < plan.start || first > plan.end
        let shown = !outside || opened.contains(first)
        // the month's cells, a week to a row (nil before the 1st and after the last)
        let cells: [Int?] = Array(repeating: nil, count: lead) + (0 ..< n).map { Optional($0) }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { i in
            (0 ..< 7).map { j in i + j < cells.count ? cells[i + j] : nil }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                guard outside else { return }
                Feel.tap()
                withAnimation(Motion.quick) { if opened.contains(first) { opened.remove(first) } else { opened.insert(first) } }
            } label: {
                Text(f.string(from: d)).font(.body.weight(.semibold))
                    .foregroundStyle(outside ? Palette.ink.opacity(0.5) : Palette.ink)
                    .frame(minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(outside)
            .accessibilityHint(outside ? (shown ? "Folds the month" : "Opens the month to reach a day in it") : "")
            if shown {
                VStack(spacing: 6) {
                    ForEach(weeks.indices, id: \.self) { w in week(weeks[w], first: first) }
                }
                .transition(.blurReplace)
            }
        }
    }

    /// one week: the plan's run of days in it under one black capsule, every day a tap
    private func week(_ days: [Int?], first: String) -> some View {
        let inPlan = days.map { i in i.map { PlanDates.key(first, $0) }.map { $0 >= plan.start && $0 <= plan.end } ?? false }
        let lo = inPlan.firstIndex(of: true), hi = inPlan.lastIndex(of: true)
        return HStack(spacing: 0) {
            ForEach(0 ..< 7, id: \.self) { j in
                if let i = days[j] { day(PlanDates.key(first, i), number: i + 1) }
                else { Color.clear.frame(maxWidth: .infinity).frame(height: 40) }
            }
        }
        .background(alignment: .leading) {
            if let lo, let hi {
                GeometryReader { g in
                    let cw = g.size.width / 7
                    Capsule().fill(Palette.ink)
                        .frame(width: CGFloat(hi - lo + 1) * cw - 4, height: 38)
                        .offset(x: CGFloat(lo) * cw + 2, y: (g.size.height - 38) / 2)
                }
            }
        }
    }

    private func day(_ k: String, number: Int) -> some View {
        let inPlan = k >= plan.start && k <= plan.end
        let i = inPlan ? PlanDates.length(plan.start, k) - 1 : -1
        let planned = inPlan && plan.days.indices.contains(i) && !plan.days[i].items.isEmpty
        return Button {
            Feel.tap()
            if inPlan { open(i) } else { reach(k) }
        } label: {
            Text("\(number)").font(.body.monospacedDigit().weight(planned ? .semibold : .regular))
                .foregroundStyle(inPlan ? Palette.white : Palette.ink.opacity(0.5))
                .frame(maxWidth: .infinity).frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WhenWords.day(k))
        .accessibilityHint(inPlan ? "Opens the day hour by hour" : "Makes the plan reach to this day")
    }
}

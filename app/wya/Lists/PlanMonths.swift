import SwiftUI

/// A DATED PLAN AS ITS CALENDAR: the plan's months, a week to a row from Monday, each day its number; the plan's days
/// filled black with the number in white (selected = black fill, no ticks), a day with something planned underlined
/// by a short bar of its first thing's colour. A plan day tapped opens that day hour by hour; a day before or after
/// the plan tapped makes the plan reach to it. One month before and after the plan are shown, so there is always a
/// day to reach to.
struct PlanMonths: View {
    let plan: Plan
    let open: (Int) -> Void
    let reach: (String) -> Void

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

    private func month(_ first: String) -> some View {
        let cal = PlanDates.cal
        let d = PlanDates.date(first) ?? Date()
        let n = cal.range(of: .day, in: .month, for: d)?.count ?? 30
        // Monday first
        let lead = (cal.component(.weekday, from: d) + 5) % 7
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "LLLL yyyy"
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(alignment: .leading, spacing: 8) {
            Text(f.string(from: d)).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(-lead ..< 0), id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(0 ..< n, id: \.self) { i in day(PlanDates.key(first, i), number: i + 1) }
            }
        }
    }

    private func day(_ k: String, number: Int) -> some View {
        let inPlan = k >= plan.start && k <= plan.end
        let i = inPlan ? PlanDates.length(plan.start, k) - 1 : -1
        let first = inPlan && plan.days.indices.contains(i) ? plan.days[i].items.first : nil
        return Button {
            Feel.tap()
            if inPlan { open(i) } else { reach(k) }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(inPlan ? Palette.ink : Color.clear)
                Text("\(number)").font(.body.monospacedDigit())
                    .foregroundStyle(inPlan ? Palette.white : Palette.ink.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let it = first {
                    Capsule().fill(it.c.isEmpty ? Palette.white : PlanItemSheet.colour(it.c))
                        .frame(width: 14, height: 3).padding(.bottom, 5)
                }
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WhenWords.day(k))
        .accessibilityHint(inPlan ? "Opens the day hour by hour" : "Makes the plan reach to this day")
    }
}

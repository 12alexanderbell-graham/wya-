import SwiftUI

/// THE NEXT TRIP, ON TOP OF LISTS. One line in one drop of glass under the square, on every kind's shelf: before the
/// trip how long till it, during it the day and today's first thing, for a week after it the book to make. Pressed:
/// the plan opens (during it, on today), or after it its book is started. It floats over the page: the shelf starts
/// under it and scrolls up under its glass. (It is there or not from the plans themselves, never popping in while you
/// look.)
struct NextTripLine: View {
    let trip: NextTrip
    let plan: Plan

    var body: some View {
        Button(action: press) {
            Text(Self.words(trip, plan, today: PlanDates.key(local: Date())))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(PageGlass.head.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(trip.phase == .after ? "Starts its book" : "Opens the plan")
    }

    static func words(_ t: NextTrip, _ p: Plan, today: String) -> String {
        switch t.phase {
        case .before(let n):
            return n <= 1 ? "\(t.place) tomorrow" : "\(n) days till \(t.place)"
        case .during(let d, let all):
            let head = "Day \(d) of \(all)"
            guard d >= 1, d <= p.days.count else { return head + " in \(t.place)" }
            // today's first thing still to come (one with no time counts as the day's)
            let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let mins = (now.hour ?? 0) * 60 + (now.minute ?? 0)
            let items = p.days[d - 1].items.sorted { $0.startMinutes < $1.startMinutes }
            let next = items.first { $0.at == nil || $0.startMinutes >= mins } ?? items.last
            guard let it = next, !it.what.trimmingCharacters(in: .whitespaces).isEmpty else { return head + " in \(t.place)" }
            return head + " · " + it.what
        case .after:
            return "Make the \(t.place) book"
        }
    }

    private func press() {
        Feel.tap()
        let s = ListsState.shared
        if trip.phase == .after {
            // the book, named as the plan is, waits on the Books shelf (its pages come with the book's page)
            let name = plan.name.trimmingCharacters(in: .whitespaces).isEmpty ? trip.place : plan.name
            ListsStore.shared.change { b in
                if !b.books.contains(where: { $0.name == name }) { b.books.append(PhotoBook(name: name)) }
            }
            withAnimation(Motion.quick) { s.kind = 3 }
            return
        }
        if case .during(let d, _) = trip.phase, d >= 1, d <= plan.days.count { s.showDay = d - 1 }
        withAnimation(Motion.quick) { s.kind = 1; s.open = plan.id }
    }

    /// the trip shown, if any: the one going on, else the next, else one just back whose book is not made yet
    @MainActor static func current() -> (NextTrip, Plan)? {
        let b = ListsStore.shared.book
        let booked = Set(b.plans.filter { p in b.books.contains { $0.name == p.name } }.map(\.id))
        let shown = b.plans.filter { !$0.ai }
        guard let t = NextTrip.pick(shown, today: PlanDates.key(local: Date()), booked: booked),
              let p = shown.first(where: { $0.id == t.plan }) else { return nil }
        return (t, p)
    }
}

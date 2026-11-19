import SwiftUI

/// A VISIT'S DAYS ON OUR OWN CALENDAR (Part 4.4.3, the dates that waited for it; never Apple's date picker). One
/// month at a time under the visit's When row: the month's name between back and forward circles, the weekdays, the
/// days. The first tap is the day you arrived, the second the day you left (picked earlier, the two swap); the days
/// between are a lime band, the two ends black circles. A third tap starts again from that day; the same day twice is
/// a one-day visit. Today and later are the look and can't be picked (a stamp is somewhere you have been).
struct VisitCalendar: View {
    @Binding var from: String?
    @Binding var to: String?
    @State private var month: LocalDay
    private let today: LocalDay

    init(from: Binding<String?>, to: Binding<String?>) {
        _from = from; _to = to
        let now = LocalDay(Date(), in: .current)
        today = now
        let start = from.wrappedValue.flatMap(LocalDay.init) ?? now
        _month = State(initialValue: LocalDay(y: start.y, m: start.m, d: 1))
    }

    private var a: LocalDay? { from.flatMap(LocalDay.init) }
    private var b: LocalDay? { to.flatMap(LocalDay.init) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    arrow("back") { month = Self.step(month, -1) }
                    Spacer(minLength: 0)
                    Text(Self.title(month)).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        .contentTransition(.identity)
                    Spacer(minLength: 0)
                    arrow("forward", dim: Self.step(month, 1) > today) { if Self.step(month, 1) <= today { month = Self.step(month, 1) } else { Feel.refuse() } }
                }
                .frame(height: 44)
                WeekLetters().frame(height: 28)
            }
            // (the month and its weekday letters are one row, each week another: Details below full shows whole
            // rows only, EdgeRows)
            .edgeRow()
            let cells = Self.cells(month)
            VStack(spacing: 2) {
                ForEach(0 ..< cells.count / 7, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0 ..< 7, id: \.self) { c in day(cells[r * 7 + c]) }
                    }
                    .background { band(Array(cells[r * 7 ..< r * 7 + 7])) }
                    .edgeRow()
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 24).onEnded { g in
            // a swipe across the days turns the month, as Apple's calendars do
            guard abs(g.translation.width) > abs(g.translation.height) else { return }
            let next = Self.step(month, g.translation.width < 0 ? 1 : -1)
            if next <= today { Feel.tap(); month = next } else { Feel.refuse() }
        })
    }

    @ViewBuilder private func day(_ d: LocalDay?) -> some View {
        if let d {
            let lo = a, hi = b ?? a
            let end = d == lo || d == hi
            let inside = lo != nil && hi != nil && d > lo! && d < hi!
            let later = d > today
            ZStack {
                if end { Circle().fill(Palette.ink).frame(width: 40, height: 40) }
                Text("\(d.d)").font(.body.weight(end ? .semibold : .regular))
                    // (a day still to come at the one grey, 50%, as everything that can't act yet)
                    .foregroundStyle(end ? Palette.white : Palette.ink.opacity(later ? 0.5 : 1))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .contentShape(Rectangle())
            .onTapGesture { pick(d, later: later) }
            .accessibilityElement()
            .accessibilityLabel(Self.spoken(d))
            // (a day still to come can't be picked: not a button, and said so)
            .accessibilityAddTraits(later ? [] : end || inside ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(later ? "Not yet" : "")
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 44)
        }
    }

    /// the lime band of a week's days inside the visit: one rounded piece from the first such day's middle to the
    /// last's (the ends' circles sit on its round ends; a week that only passes through runs edge to edge, round)
    @ViewBuilder private func band(_ week: [LocalDay?]) -> some View {
        if let lo = a, let hi = b, lo != hi {
            let cols = week.indices.filter { i in week[i].map { $0 >= lo && $0 <= hi } ?? false }
            if let f = cols.first, let l = cols.last {
                GeometryReader { g in
                    let w = g.size.width / 7, gx = g.frame(in: .global).minX
                    // a week the visit runs on past (or came in from) runs to the screen's edge, square there, over
                    // the blank cells of a month's first or last week too (the visit goes on in the next month); its
                    // own ends are round under the day's circle
                    let openL = week[..<f].allSatisfy { $0 == nil } && week[f]! > lo
                    let openR = week[(l + 1)...].allSatisfy { $0 == nil } && week[l]! < hi
                    let x0 = openL ? -gx : w * (CGFloat(f) + 0.5) - 20
                    let x1 = openR ? Screen.width - gx : w * (CGFloat(l) + 0.5) + 20
                    UnevenRoundedRectangle(topLeadingRadius: openL ? 0 : 20, bottomLeadingRadius: openL ? 0 : 20,
                                           bottomTrailingRadius: openR ? 0 : 20, topTrailingRadius: openR ? 0 : 20)
                        .fill(Palette.lime)
                        .frame(width: x1 - x0, height: 40)
                        .position(x: (x0 + x1) / 2, y: g.size.height / 2)
                }
            }
        }
    }

    private func pick(_ d: LocalDay, later: Bool) {
        guard !later else { Feel.refuse(); return }
        Feel.tap()
        if let lo = a, b == nil {
            // the second tap: the day you left (earlier than the first: they swap)
            if d < lo { from = d.description; to = lo.description } else { to = d.description }
        } else {
            from = d.description; to = nil
        }
    }

    private func arrow(_ key: String, dim: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: { Feel.tap(); act() }) {
            Icon5Still(key: key, progress: 0, ink: Palette.white, size: 15)
                .frame(width: 36, height: 36).background(Palette.ink.opacity(dim ? 0.5 : 1), in: .circle)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key == "back" ? "Month before" : "Month after")
    }

    // MARK: days

    static func step(_ m: LocalDay, _ n: Int) -> LocalDay {
        var y = m.y, mm = m.m + n
        while mm < 1 { mm += 12; y -= 1 }
        while mm > 12 { mm -= 12; y += 1 }
        return LocalDay(y: y, m: mm, d: 1)
    }
    /// the month's days in Monday-first weeks, nil for the blanks before the first and after the last
    static func cells(_ m: LocalDay) -> [LocalDay?] {
        let last = CalendarEdit.monthEnd(m).d
        let lead = CalendarEdit.weekday(m)   // 0 Monday … 6 Sunday
        var out: [LocalDay?] = Array(repeating: nil, count: lead)
        out += (1 ... last).map { LocalDay(y: m.y, m: m.m, d: $0) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }
    // (made once: the upload's calendar asks for every day's spoken date as it scrolls)
    private static let titles: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = TimeZone(identifier: "UTC"); f.setLocalizedDateFormatFromTemplate("MMMM yyyy"); return f
    }()
    private static let spokenDays: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = TimeZone(identifier: "UTC"); f.dateStyle = .long; return f
    }()
    static func title(_ m: LocalDay) -> String { titles.string(from: m.date) }
    static func spoken(_ d: LocalDay) -> String { spokenDays.string(from: d.date) }
    /// ,,, (one day)
    static func range(_ from: String?, _ to: String?) -> String? {
        guard let a = from.flatMap(LocalDay.init) else { return nil }
        let b = to.flatMap(LocalDay.init) ?? a
        let mon = DateFormatter(); mon.locale = .current; mon.timeZone = TimeZone(identifier: "UTC"); mon.setLocalizedDateFormatFromTemplate("MMM")
        let m = { (d: LocalDay) in mon.string(from: d.date) }
        if a == b { return "\(a.d) \(m(a)) \(a.y)" }
        if a.y != b.y { return "\(a.d) \(m(a)) \(a.y) – \(b.d) \(m(b)) \(b.y)" }
        if a.m != b.m { return "\(a.d) \(m(a)) – \(b.d) \(m(b)) \(b.y)" }
        return "\(a.d) – \(b.d) \(m(b)) \(b.y)"
    }
    /// the days there, both ends counted; nil without both ends
    static func days(_ from: String?, _ to: String?) -> String? {
        guard let a = from.flatMap(LocalDay.init), let b = to.flatMap(LocalDay.init) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let n = cal.dateComponents([.day], from: a.date, to: b.date).day ?? 0
        return n + 1 == 1 ? "1 day" : "\(n + 1) days"
    }
}

/// THE WEEK'S LETTERS, Monday first, as every calendar in the app shows them (a visit's days in Details and the
/// upload's found days are one calendar: the same letters, month names, day numbers and spoken dates)
struct WeekLetters: View {
    var spacing: CGFloat = 0
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, w in
                Text(w).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

extension LocalDay {
    /// midnight of the day in UTC (for formatting and counting only)
    var date: Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d)) ?? .now
    }
}

/// the screen's width, for fills that run edge to edge whatever their row's insets
enum Screen {
    @MainActor static var width: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 440
    }
}
extension View {
    /// a fill behind the row that runs to both edges of the screen (never stopping short with a gap at the sides)
    @MainActor func screenWide(_ fill: Color) -> some View {
        background {
            GeometryReader { g in
                let f = g.frame(in: .global)
                Rectangle().fill(fill).frame(width: Screen.width, height: f.height).offset(x: -f.minX)
            }
        }
    }
}

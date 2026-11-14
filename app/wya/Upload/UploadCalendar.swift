import SwiftUI

/// THE CALENDAR OF WHAT WAS FOUND (Part 9: the upload's second view of the same finds as the map's review). Full screen,
/// a cell per day from the first found day's month to the last's:
/// - a day with a find is that place's flag, cropped square, filling the cell; an empty day is a quiet cell with its
///   number (numbers on empty days only);
/// - a flag tapped is crossed out (you weren't there that day), tapped again it is back;
/// - a flag held and dragged fills every day the finger passes over with that place, across months, over what was
///   there;
/// - a month's name tapped folds the month away, again opens it;
/// - × leaves with nothing changed; Undo and Redo step through the changes, and a hold on Undo puts back the days as
///   they were found (Reset); "Add N" stamps the places that still have a day, with those days as their trips.
@MainActor @Observable
final class CalendarEdit {
    /// the place on each day
    private(set) var days: [LocalDay: String] = [:]
    /// days crossed out
    private(set) var crossed: Set<LocalDay> = []
    /// months folded away (first day of the month)
    var folded: Set<LocalDay> = []
    /// the day the finger is filling from, while a fill is under way
    var filling: String?

    private var found: ([LocalDay: String], Set<LocalDay>) = ([:], [])
    private var past: [([LocalDay: String], Set<LocalDay>)] = []
    private var ahead: [([LocalDay: String], Set<LocalDay>)] = []

    /// the first and last days shown: whole months round what was found
    private(set) var first = LocalDay(y: 2000, m: 1, d: 1)
    private(set) var last = LocalDay(y: 2000, m: 1, d: 31)

    /// the calendar open now (the test driver's taps and fills)
    static weak var current: CalendarEdit?

    init(days: [LocalDay: String], crossed: Set<LocalDay>) {
        self.days = days; self.crossed = crossed
        found = (days, crossed)
        let all = days.keys.sorted()
        if let a = all.first, let b = all.last {
            first = LocalDay(y: a.y, m: a.m, d: 1)
            last = Self.monthEnd(b)
        }
        // months with nothing found start folded (a camera roll of years is mostly empty months)
        let withDays = Set(all.map { LocalDay(y: $0.y, m: $0.m, d: 1) })
        folded = Set(months.filter { !withDays.contains($0) })
        Self.current = self
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !ahead.isEmpty }
    var changed: Bool { days != found.0 || crossed != found.1 }

    /// the places that still have a day, and their days
    var kept: [String: [LocalDay]] {
        var out: [String: [LocalDay]] = [:]
        for (d, p) in days where !crossed.contains(d) { out[p, default: []].append(d) }
        return out.mapValues { $0.sorted() }
    }

    private func mark() { past.append((days, crossed)); ahead = [] }

    func toggle(_ d: LocalDay) {
        guard days[d] != nil else { return }
        mark()
        if crossed.contains(d) { crossed.remove(d) } else { crossed.insert(d) }
    }
    /// a fill starts: one undo step for the whole stroke
    func beginFill(_ place: String) { mark(); filling = place }
    func fill(_ d: LocalDay) {
        guard let p = filling, d >= first, d <= last else { return }
        if days[d] != p { days[d] = p }
        if crossed.contains(d) { crossed.remove(d) }
    }
    func endFill() {
        filling = nil
        // a stroke that changed nothing is no step
        if let top = past.last, top.0 == days, top.1 == crossed { past.removeLast() }
    }
    func undo() { guard let s = past.popLast() else { return }; ahead.append((days, crossed)); (days, crossed) = s }
    func redo() { guard let s = ahead.popLast() else { return }; past.append((days, crossed)); (days, crossed) = s }
    func reset() { guard changed else { return }; mark(); (days, crossed) = found }

    /// every month shown, by its first day
    var months: [LocalDay] {
        var out: [LocalDay] = []
        var m = first
        while m <= last && out.count < 600 {
            out.append(m)
            m = m.m == 12 ? LocalDay(y: m.y + 1, m: 1, d: 1) : LocalDay(y: m.y, m: m.m + 1, d: 1)
        }
        return out
    }

    /// the months as they are shown: a month on its own, or a run of folded months with no day found in them, which
    /// show as one line ("June 2018 to April 2019")
    var runs: [[LocalDay]] {
        let withDays = Set(days.keys.map { LocalDay(y: $0.y, m: $0.m, d: 1) })
        var out: [[LocalDay]] = []
        for m in months {
            let empty = folded.contains(m) && !withDays.contains(m)
            if empty, let last = out.last, let l = last.last, folded.contains(l), !withDays.contains(l) {
                out[out.count - 1].append(m)
            } else {
                out.append([m])
            }
        }
        return out
    }

    static func monthEnd(_ d: LocalDay) -> LocalDay {
        let next = d.m == 12 ? LocalDay(y: d.y + 1, m: 1, d: 1) : LocalDay(y: d.y, m: d.m + 1, d: 1)
        return next.plus(-1)
    }
    /// 0 for Monday … 6 for Sunday
    static func weekday(_ d: LocalDay) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: d.y, month: d.m, day: d.d)) ?? .now
        return (cal.component(.weekday, from: date) + 5) % 7
    }
}

struct UploadCalendar: View {
    @State var edit: CalendarEdit
    let close: () -> Void
    let add: ([String: [LocalDay]]) -> Void
    /// where each day's cell is in the calendar's space (the fill finds the day under the finger)
    @State private var cells: [LocalDay: CGRect] = [:]

    private static let gap: CGFloat = 4
    private static let monthName: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "LLLL yyyy"; return f
    }()

    var body: some View {
        GeometryReader { g in
            let side = floor((g.size.width - 32 - 6 * Self.gap) / 7)
            ZStack(alignment: .top) {
                Palette.white.ignoresSafeArea()
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(edit.runs, id: \.self) { run in
                            if run.count == 1 { month(run[0], side: side) } else { emptyRun(run) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 72)
                    .padding(.bottom, 120)
                }
                .scrollDisabled(edit.filling != nil)
                .coordinateSpace(.named("calendar"))
                bar
                VStack { Spacer(); addButton }
            }
        }
        .onPreferenceChange(CellFrames.self) { cells = $0 }
    }

    // MARK: the top: ×, Undo (hold: Reset), Redo, and the days of the week

    private var bar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                circle("cross", "Cancel", dim: false) { close() }
                Spacer()
                circle("undo", "Undo", dim: !edit.canUndo) { edit.undo() }
                    .contextMenu {
                        Button("Reset") { Feel.tap(); edit.reset() }.disabled(!edit.changed)
                    }
                circle("undo", "Redo", dim: !edit.canRedo, flip: true) { edit.redo() }
            }
            .padding(.horizontal, 16)
            HStack(spacing: Self.gap) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .accessibilityHidden(true)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background { Palette.white.opacity(0.92).ignoresSafeArea(edges: .top) }
    }

    private func circle(_ icon: String, _ label: String, dim: Bool, flip: Bool = false, act: @escaping () -> Void) -> some View {
        Button { Feel.tap(); act() } label: {
            Icon5(key: icon, ink: Palette.ink.opacity(dim ? 0.3 : 1), size: 20)
                .scaleEffect(x: flip ? -1 : 1, y: 1)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(dim)
        .accessibilityLabel(label)
    }

    // MARK: Add N

    private var addButton: some View {
        let n = edit.kept.count
        return Button {
            guard n > 0 else { Feel.refuse(); return }
            Feel.stamp()
            add(edit.kept)
        } label: {
            Text("Add \(n)")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(n == 0 ? 0.5 : 1))
                .contentTransition(.numericText(value: Double(n)))
                .padding(.horizontal, 28)
                .frame(height: 50)
                .glassEffect(.regular.tint(n > 0 ? Palette.lime : .clear).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: n)
        .padding(.bottom, 12)
        .accessibilityLabel("Add \(n) \(n == 1 ? "place" : "places")")
    }

    // MARK: a month

    @ViewBuilder
    private func month(_ m: LocalDay, side: CGFloat) -> some View {
        let folded = edit.folded.contains(m)
        let end = CalendarEdit.monthEnd(m)
        let lead = CalendarEdit.weekday(m)
        let cells = Array(repeating: LocalDay?.none, count: lead) + (1 ... end.d).map { Optional(LocalDay(y: m.y, m: m.m, d: $0)) }
        let found = (1 ... end.d).filter { edit.days[LocalDay(y: m.y, m: m.m, d: $0)] != nil && !edit.crossed.contains(LocalDay(y: m.y, m: m.m, d: $0)) }.count
        Button {
            Feel.tick()
            withAnimation(Motion.chrome) { if folded { edit.folded.remove(m) } else { edit.folded.insert(m) } }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(m)).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                // a folded month says how many of its days have a place
                if folded, found > 0 {
                    Text("\(found) \(found == 1 ? "day" : "days")").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                }
            }
            .frame(height: 52, alignment: .bottom)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(folded ? "Opens the month" : "Folds the month away")
        if !folded {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: Self.gap), count: 7), spacing: Self.gap) {
                ForEach(cells.indices, id: \.self) { i in
                    if let d = cells[i] { cell(d, side: side) } else { Color.clear.frame(width: side, height: side) }
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// folded months with nothing found, as one line; a tap opens them all
    private func emptyRun(_ run: [LocalDay]) -> some View {
        Button {
            Feel.tick()
            withAnimation(Motion.chrome) { edit.folded.subtract(run) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(run[0]) + " to " + Self.title(run[run.count - 1]))
                    .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.35))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
            }
            .frame(height: 52, alignment: .bottom)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Nothing found in these months. Opens them")
    }

    private static func title(_ m: LocalDay) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: m.y, month: m.m, day: 1)) ?? .now
        monthName.timeZone = cal.timeZone
        return monthName.string(from: date)
    }

    // MARK: a day

    @ViewBuilder
    private func cell(_ d: LocalDay, side: CGFloat) -> some View {
        let place = edit.days[d]
        let off = edit.crossed.contains(d)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            if let place {
                Group {
                    if let f = Flags.square(place) { f.resizable().interpolation(.high).scaledToFill() } else { Palette.grey }
                }
                .frame(width: side, height: side)
                .clipShape(shape)
                .opacity(off ? 0.25 : 1)
                if off {
                    // crossed out: one line corner to corner
                    Path { p in p.move(to: CGPoint(x: 8, y: side - 8)); p.addLine(to: CGPoint(x: side - 8, y: 8)) }
                        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: side, height: side)
                }
            } else {
                shape.fill(Palette.grey.opacity(0.35))
                Text("\(d.d)").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.4)).monospacedDigit()
            }
        }
        .frame(width: side, height: side)
        .contentShape(shape)
        .background {
            GeometryReader { c in
                Color.clear.preference(key: CellFrames.self, value: [d: c.frame(in: .named("calendar"))])
            }
        }
        .onTapGesture { if place != nil { Feel.tap(); withAnimation(Motion.quick) { edit.toggle(d) } } }
        .gesture(fillGesture(from: d, place: place ?? ""), including: place == nil ? .none : .all)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(d) + (place.map { ", " + Self.name($0) + (off ? ", crossed out" : "") } ?? ""))
        .accessibilityAddTraits(place == nil ? [] : .isButton)
    }

    /// a flag held (0.3 s) and dragged: every day the finger passes over takes that flag
    private func fillGesture(from d: LocalDay, place: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("calendar")))
            .onChanged { v in
                switch v {
                case .first(true):
                    break
                case .second(true, let drag):
                    if edit.filling == nil { Feel.lift(); edit.beginFill(place); edit.fill(d) }
                    if let drag, let hit = cells.first(where: { $0.value.contains(drag.location) })?.key, edit.days[hit] != place {
                        Feel.tick()
                        edit.fill(hit)
                    }
                default: break
                }
            }
            .onEnded { _ in edit.endFill() }
    }

    private static func spoken(_ d: LocalDay) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: d.y, month: d.m, day: d.d)) ?? .now
        return date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_GB")))
    }
    private static func name(_ id: String) -> String { Pin.countryNames[id] ?? id.uppercased() }
}

private struct CellFrames: PreferenceKey {
    static let defaultValue: [LocalDay: CGRect] = [:]
    static func reduce(value: inout [LocalDay: CGRect], nextValue: () -> [LocalDay: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

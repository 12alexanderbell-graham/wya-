import SwiftUI

/// THE CALENDAR OF WHAT WAS FOUND (Part 9: the upload's second view of the same finds as the map's review). Full screen,
/// a cell per day from the first found day's month to the last's:
/// - a day with a find is that place's flag, cropped square, filling the cell; an empty day is just its number, no
///   square behind it (numbers on empty days only);
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
    /// show as one line
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
    @State private var pos = ScrollPosition(edge: .top)
    @State private var geo = Geo()
    /// the finger while a flag is being dragged, and the edge scrolling that follows it
    @State private var finger: CGPoint?
    @State private var drift: Task<Void, Never>?
    /// a flag held: false again however the hold ends, a cancelled one too (a held day's month scrolled away and
    /// unloaded ends its gesture with no onEnded; the fill then stayed on and the edge scrolling ran on)
    @GestureState private var holding = false

    private static let gap: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            let side = floor((g.size.width - 32 - 6 * Self.gap) / 7)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(edit.runs, id: \.self) { run in
                        if run.count == 1 { month(run[0], side: side) } else { emptyRun(run) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollBlur()
            .scrollDisabled(edit.filling != nil)
            .scrollPosition($pos)
            .onScrollGeometryChange(for: Geo.self) { s in
                Geo(y: s.contentOffset.y + s.contentInsets.top,
                    most: max(0, s.contentSize.height - (s.containerSize.height - s.contentInsets.top - s.contentInsets.bottom)),
                    top: s.contentInsets.top, bottom: s.containerSize.height - s.contentInsets.bottom)
            } action: { _, now in geo = now }
            .coordinateSpace(.named("calendar"))
            // the bars as Apple's bars: the list's own soft edge runs under them, no strip of white (one blur everywhere)
            .safeAreaBar(edge: .top) { bar }
            .safeAreaBar(edge: .bottom) { addButton }
            // the app's own ground (the living field, as Lists has it), not a white sheet: a flag's white reads as part
            // of the flag, and the calendar is the app's (25 Nov)
            .background { LivingField().ignoresSafeArea() }
        }
        .onPreferenceChange(CellFrames.self) { cells = $0 }
        .onChange(of: edit.filling) { _, now in if now == nil { finger = nil; drift?.cancel(); drift = nil } }
        .onChange(of: holding) { _, h in if !h, edit.filling != nil { edit.endFill() } }
        .onDisappear { drift?.cancel(); drift = nil; if edit.filling != nil { edit.endFill() } }
    }

    /// where the list is scrolled: how far down, how far it can go, and where the bars' edges are in its space
    private struct Geo: Equatable { var y: CGFloat = 0; var most: CGFloat = 0; var top: CGFloat = 0; var bottom: CGFloat = 0 }

    /// a fill held near the top or bottom edge scrolls the months under the finger, faster the nearer the edge, so a
    /// stroke can run on into the next month (the list's own scrolling is off while a flag is held)
    private func drifting() {
        guard drift == nil else { return }
        drift = Task { @MainActor in
            while !Task.isCancelled, edit.filling != nil, holding, let f = finger {
                let zone: CGFloat = 64
                let up = (geo.top + zone - f.y) / zone, down = (f.y - (geo.bottom - zone)) / zone
                let speed = up > 0 ? -14 * min(1, up) : down > 0 ? 14 * min(1, down) : 0
                let to = min(max(geo.y + speed, 0), geo.most)
                if speed != 0, to != geo.y {
                    pos.scrollTo(y: to)
                    try? await Task.sleep(for: .milliseconds(16))
                    fillUnder(f)
                } else {
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
            drift = nil
        }
    }

    /// the day under the finger takes the flag being dragged
    private func fillUnder(_ at: CGPoint) {
        guard let p = edit.filling, let hit = cells.first(where: { $0.value.contains(at) })?.key, edit.days[hit] != p || edit.crossed.contains(hit) else { return }
        Feel.tick()
        edit.fill(hit)
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
            WeekLetters(spacing: Self.gap)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func circle(_ icon: String, _ label: String, dim: Bool, flip: Bool = false, act: @escaping () -> Void) -> some View {
        Button { Feel.tap(); act() } label: {
            Icon5(key: icon, ink: Palette.ink.opacity(dim ? 0.5 : 1), size: 20)
                .scaleEffect(x: flip ? -1 : 1, y: 1)
                .frame(width: 44, height: 44)
                .glassEffect(.clear.interactive(), in: .circle)
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
                .frame(height: 44)
                .glassEffect((n > 0 ? Glass.clear.tint(Palette.lime) : .clear).interactive(), in: .capsule)
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
            let gridW = 7 * side + 6 * Self.gap
            let rows = (cells.count + 6) / 7
            let gridH = CGFloat(rows) * (side + Self.gap) - Self.gap
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: Self.gap), count: 7), spacing: Self.gap) {
                ForEach(cells.indices, id: \.self) { i in
                    if let d = cells[i] { cell(d, side: side) } else { Color.clear.frame(width: side, height: side) }
                }
            }
            .frame(width: gridW, alignment: .leading)
            // A TRIP IS ONE SHAPE (25 Nov): the days in a row in one place are one flag, their rows melted together,
            // never a box a day with white between
            .background(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Self.trips(cells, edit), id: \.first) { t in
                        trip(t.place, t.cells, side: side, size: CGSize(width: gridW, height: gridH))
                    }
                }
                .frame(width: gridW, height: gridH, alignment: .topLeading)
                .animation(Motion.quick, value: edit.days)
                .animation(Motion.quick, value: edit.crossed)
            }
            .padding(.bottom, 8)
        }
    }

    /// the month's trips: runs of days one after another in one place and not crossed out (grid cell indices)
    private static func trips(_ cells: [LocalDay?], _ edit: CalendarEdit) -> [(place: String, cells: [Int], first: Int)] {
        var out: [(place: String, cells: [Int], first: Int)] = []
        for (i, d) in cells.enumerated() {
            guard let d, let p = edit.days[d], !edit.crossed.contains(d) else { continue }
            if let last = out.last, last.place == p, last.cells.last == i - 1 { out[out.count - 1].cells.append(i) }
            else { out.append((p, [i], i)) }
        }
        return out
    }

    /// one trip: its flag laid over the box round its days, seen only through their joined shape
    private func trip(_ place: String, _ cells: [Int], side: CGFloat, size: CGSize) -> some View {
        let rects = DayGoo.rows(cells, side: side, gapX: Self.gap, gapY: Self.gap)
        let box = DayGoo.box(rects)
        // (a long trip takes the flag's own shape; a day or a block of rows the square crop, centred on its emblem)
        let flag = box.width > box.height * 1.3 ? (Flags.wide(place) ?? Flags.square(place)) : Flags.square(place)
        return ZStack(alignment: .topLeading) {
            Group {
                if let flag { flag.resizable().interpolation(.high).scaledToFill() } else { Palette.grey }
            }
            .frame(width: box.width, height: box.height)
            .clipped()
            .offset(x: box.minX, y: box.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask { DayGoo(rects: rects, soft: 4, corner: 9) }
    }

    /// folded months with nothing found, as one line; a tap opens them all
    private func emptyRun(_ run: [LocalDay]) -> some View {
        Button {
            Feel.tick()
            withAnimation(Motion.chrome) { edit.folded.subtract(run) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(run[0]) + " to " + Self.title(run[run.count - 1]))
                    .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
                    .lineLimit(1)
                Spacer()
            }
            .frame(height: 52, alignment: .bottom)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Nothing found in these months. Opens them")
    }

    /// (month names and spoken days as Details' calendar has them: one calendar)
    private static func title(_ m: LocalDay) -> String { VisitCalendar.title(m) }

    // MARK: a day

    @ViewBuilder
    private func cell(_ d: LocalDay, side: CGFloat) -> some View {
        let place = edit.days[d]
        let off = edit.crossed.contains(d)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            if let place {
                // (a kept day's flag is its trip's, drawn under the grid as one shape; a crossed-out day keeps its own
                // faint square so the cross has something to lie on)
                if off {
                    Group {
                        if let f = Flags.square(place) { f.resizable().interpolation(.high).scaledToFill() } else { Palette.grey }
                    }
                    .frame(width: side, height: side)
                    .clipShape(shape)
                    .opacity(0.25)
                }
                if off {
                    // crossed out: one line corner to corner
                    Path { p in p.move(to: CGPoint(x: 8, y: side - 8)); p.addLine(to: CGPoint(x: side - 8, y: 8)) }
                        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: side, height: side)
                }
            } else {
                // (an empty day is its number alone, as on Details' calendar: no square behind it)
                // (a fixed square: the number stops growing at the largest ordinary size, never shrinks to fit)
                Text("\(d.d)").font(.body).foregroundStyle(Palette.ink.opacity(0.5)).monospacedDigit()
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
            .updating($holding) { v, held, _ in if case .second(true, _) = v { held = true } }
            .onChanged { v in
                switch v {
                case .first(true):
                    break
                case .second(true, let drag):
                    if edit.filling == nil { Feel.lift(); edit.beginFill(place); edit.fill(d) }
                    if let drag {
                        finger = drag.location
                        fillUnder(drag.location)
                        drifting()
                    }
                default: break
                }
            }
            .onEnded { _ in edit.endFill() }
    }

    private static func spoken(_ d: LocalDay) -> String { VisitCalendar.spoken(d) }
    private static func name(_ id: String) -> String { Pin.countryNames[id] ?? id.uppercased() }
}

private struct CellFrames: PreferenceKey {
    static let defaultValue: [LocalDay: CGRect] = [:]
    static func reduce(value: inout [LocalDay: CGRect], nextValue: () -> [LocalDay: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

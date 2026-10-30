import SwiftUI

/// THE STAMPED LIST (Part 4.6): every country you have stamped, one list sorted by name, in the water at full under
/// the caption (which stays). Opened and closed by the caption's number; a pull down closes it.
/// Rows 56 pt: the square flag 28 pt (detailed), the name 17 pt, under it how often (13 pt black 50%).
/// A row: tap = the card from the place on the map (the water at 25%, the camera framing it first); swipe right =
/// Details; swipe left = Unstamp; hold = Apple's menu. Black and white as Map settings and Details are.
/// A4.19: the rows arrive each in its own place, top down, 0.025 s apart (the first 15; the rest are simply there),
/// once the water is 80% of the way up: the flag grows about its own centre (smooth 0.26 s) and the words roll in once
/// the flag is past 60%; closing is the reverse, bottom row first, while the water goes down.
/// A4.20: an unstamped row's words roll out and its flag shrinks, then the rows below move up.
/// A4.21: Details from a row, the list leaving as one block through its bottom edge. Not here yet (logged): regions /
/// towns / things scopes, Show in passport.
struct StampedList: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    /// where the caption's bottom is (the rows start 12 pt under it)
    let top: CGFloat
    @State private var marks = MarkStore.shared
    /// each place's latest year and verified, from the store
    @State private var info: [String: (year: Int?, verified: Bool)] = [:]
    /// A4.19: the rows whose flag is out, and whose words are
    @State private var flagOut: Set<String> = []
    @State private var wordsOut: Set<String> = []
    /// the rows on screen now (the ones that animate when the list closes)
    @State private var onScreen: Set<String> = []
    /// the water's top when the list appeared (its rise is measured from there)
    @State private var startTop: CGFloat?
    @State private var arrived = false
    @State private var openedAt = Date()
    /// A4.20: the rows as they were last, and the ones gone from the store still leaving
    @State private var last: [Row] = []
    @State private var kept: [Row] = []
    /// A4.21: how far the rows have dropped through the list's bottom edge
    @State private var listDrop: CGFloat = 0
    static let each = 0.26, gap = 0.025, animated = 15

    struct Row: Identifiable {
        let id: String
        let name: String
        let place: Int
        let line: String
    }

    private var rows: [Row] {
        guard let w = map.world else { return [] }
        var index: [String: Int] = [:]
        for (i, p) in w.places.enumerated() { index[p.id] = i }
        return marks.marks.compactMap { k, s -> Row? in
            guard k.kind == .country, s.stamped, let i = index[k.id] else { return nil }
            // "Lived" / "Once" / "Twice" / "<n> times", " · " the latest visit's year, " · Verified" (no tick)
            var line = s.lived ? "Lived" : s.visits <= 1 ? "Once" : s.visits == 2 ? "Twice" : "\(s.visits) times"
            if let x = info[k.description] {
                if let y = x.year { line += " · \(y)" }
                if x.verified { line += " · Verified" }
            }
            return Row(id: k.id, name: w.places[i].n, place: i, line: line)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let L = water.layout
        let y0 = top + 12
        let bottom = L.capsule.minY - 24
        let h = max(60, bottom - y0)
        // whole rows only (0.7: nothing sits cut off at rest): the height ends between two rows, the soft edge lies
        // over their empty margins, and a scroll stops on a row boundary
        let n = max(1, Int((h - 8) / 56))
        let vh = CGFloat(n) * 56 + 8
        List {
            ForEach(listed) { r in
                row(r)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { details(r) } label: { Text("Details") }.tint(Palette.ink)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // not the destructive role: that slides the row away at once; the row leaves by A4.20 (the
                        // same red as the destructive button)
                        Button { unstamp(r) } label: { Text("Unstamp") }.tint(.red)
                    }
                    .contextMenu {
                        Button("Show on the map") { open(r) }
                        Button("Details") { details(r) }
                        Button("Verify") { VerifyState.shared.open(.country(r.id), name: r.name, place: r.place, water: water) }
                        Button("Unstamp", role: .destructive) { unstamp(r) }
                    }
            }
        }
        .listStyle(.plain)
        // A4.21: the rows drop as one block down through the bottom edge (first tried row by row with a stagger:
        // List's own cell layout moved the rows over each other on the way)
        .offset(y: listDrop)
        // the list's bottom soft edge (P3): rows scrolling and leaving go out through it, never cut by a hard line
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().frame(height: vh - 16)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
            }
        }
        // a row going or coming: the rows below move by its height (A4.20; A4.19's own motion does the row itself)
        .animation(Motion.quick, value: listed.map(\.id))
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 56)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .scrollTargetBehavior(RowSnap(row: 56))
        .task(id: marks.changes) { info = await MarkStore.shared.listInfo() }
        .frame(width: L.W - 2 * L.sheetInset, height: vh)
        .position(x: L.W / 2, y: y0 + vh / 2)
        .allowsHitTesting(water.stampedList)
        .onAppear {
            startTop = form.top; openedAt = Date()
            Self.testDetails = { id in if let r = rows.first(where: { $0.id == id }) { details(r) } }
        }
        // the rows come once the water is 80% of the way up (from wherever it was when the list opened)
        .onChange(of: water.stampedList && form.top <= L.top(.full) + 0.2 * max(0, (startTop ?? form.top) - L.top(.full))
                  && !rows.isEmpty, initial: true) { _, go in
            if go && !arrived { arrive() }
        }
        .onChange(of: water.stampedList) { _, open in
            if open { startTop = form.top; openedAt = Date(); arrived = false } else { leave() }
        }
        // a row that comes while the list is up (an undo, a stamp elsewhere) arrives the same way; one that goes
        // (unstamped here or anywhere) leaves by A4.20: it stays on screen while its words roll out and its flag
        // shrinks, then the rows below move up (List's own removal would fade it)
        .onChange(of: rows.map(\.id)) { old, new in
            let gone = last.filter { !new.contains($0.id) }
            last = rows
            guard arrived else { return }
            let added = new.filter { !old.contains($0) }
            // the space opens first (List's insertion fades a row in: it must be blank then), then the row arrives
            for (k, id) in added.enumerated() {
                kept.removeAll { $0.id == id }
                flagOut.remove(id); wordsOut.remove(id)
                show(id, after: Self.each + Self.gap * Double(k))
            }
            for r in gone where flagOut.contains(r.id) || wordsOut.contains(r.id) || onScreen.contains(r.id) {
                kept.append(r)
                withAnimation(Motion.quick) { _ = wordsOut.remove(r.id) }
                withAnimation(.smooth(duration: Self.each)) { _ = flagOut.remove(r.id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.each) { kept.removeAll { $0.id == r.id } }
            }
        }
        .onAppear { last = rows }
    }

    /// the rows as shown: the store's, plus any still leaving
    /// (`last` too: on the first frame after the store drops a row, before onChange has put it in `kept`, it is still
    /// there, so List never removes it and puts it back)
    private var listed: [Row] {
        var ids = Set(rows.map(\.id))
        var out = rows
        for r in last + kept where !ids.contains(r.id) { out.append(r); ids.insert(r.id) }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A4.19: top down, 0.025 s apart, the first 15 animated and the rest simply there; never before the solar
    /// system has gone down out of the water (Motion.chrome, 0.38 s from the list opening): one out, then the other in
    private func arrive() {
        arrived = true
        if Self.backFromDetails { Self.backFromDetails = false; rise(); return }
        let wait = max(0, 0.38 - Date().timeIntervalSince(openedAt))
        for (i, r) in rows.enumerated() {
            if i < Self.animated { show(r.id, after: wait + Self.gap * Double(i)) }
            else { flagOut.insert(r.id); wordsOut.insert(r.id) }
        }
    }
    private func show(_ id: String, after d: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + d) {
            withAnimation(.smooth(duration: Self.each)) { _ = flagOut.insert(id) }
            // the words once the flag is past 60% (about a third of its time on this curve)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.each * 0.3) {
                withAnimation(Motion.quick) { _ = wordsOut.insert(id) }
            }
        }
    }
    /// the reverse, bottom row first: the words roll out and the flags shrink into their own centres
    private func leave() {
        let ids = rows.map(\.id)
        let shown = ids.filter { onScreen.contains($0) }
        for id in ids where !onScreen.contains(id) { flagOut.remove(id); wordsOut.remove(id) }
        for (k, id) in shown.reversed().enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.gap * Double(k)) {
                withAnimation(Motion.quick) { _ = wordsOut.remove(id) }
                withAnimation(.smooth(duration: Self.each)) { _ = flagOut.remove(id) }
            }
        }
        arrived = false
        // the solar system comes back as soon as the last row has gone (Water's own timer is the cap)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.leaving(shown.count)) {
            if !water.stampedList { water.listLeaving = false }
        }
    }
    /// how long the list stays on screen after it is closed, for its rows to leave
    static func leaving(_ rows: Int) -> Double { each + gap * Double(min(rows, animated)) + 0.05 }

    private func row(_ r: Row) -> some View {
        HStack(spacing: 12) {
            Group {
                if let f = Flags.square(r.id.lowercased()) { f.resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: 28, height: 28)
            .scaleEffect(flagOut.contains(r.id) ? 1 : 0)
            // the words by the text roll (never scaled, never faded): a blank of the same length until they come
            let w = wordsOut.contains(r.id)
            VStack(alignment: .leading, spacing: 1) {
                Text(w ? r.name : Caption.blank(r.name, "\u{2002}")).font(.body).foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: w ? 1 : 0))
                Text(w ? r.line : Caption.blank(r.line, "\u{2002}")).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5))
                    .contentTransition(.numericText(value: w ? 1 : 0))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .onAppear { onScreen.insert(r.id) }
        .onDisappear { onScreen.remove(r.id) }
        .contentShape(Rectangle())
        .onTapGesture { open(r) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.name), \(r.line)")
        .accessibilityAddTraits(.isButton)
    }

    /// the card from the place: the water to 25%, the camera frames the place, then the card grows out of it
    private func open(_ r: Row) {
        Feel.tap()
        water.closeList(to: .quarter)
        map.show(place: r.place, sheetTop: water.y(.quarter))
        // the card from the place once the camera has landed (show's flight is 0.8 s) and the water is at 25%, so
        // nothing moves into the card's way while it grows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + 0.1) {
            guard let w = map.world else { return }
            let p = w.places[r.place]
            CardState.shared.open(r.place, at: map.screenPoint(SIMD2(p.c[0], p.c[1])), map: map, water: water)
        }
    }

    /// A4.21: Details over the list, in the same water. The rows go down and out through the list's bottom soft edge
    /// together (quick curve; the book's 0.025 s stagger is not kept, see `listDrop`), and only then Details come;
    /// closing them, the rows come back up through the edge (`rise`). (Details' own rows arriving from the swiped row's centre,
    /// A4.14, are not built: they are there in one frame once the list has gone.)
    private func details(_ r: Row) {
        Feel.tick()
        Self.backFromDetails = true
        withAnimation(Motion.quick) { listDrop = listHeight + 8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.each) {
            DetailsState.shared.open(.country(r.id), name: r.name, water: water)
        }
    }
    /// back from Details: every row in, the ones on screen (the list starts at its top again) coming up through the
    /// bottom edge, nearest it first
    private func rise() {
        let ids = rows.map(\.id)
        flagOut = Set(ids); wordsOut = Set(ids)
        listDrop = listHeight + 8
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(Motion.quick) { listDrop = 0 }
        }
    }
    private var listHeight: CGFloat { max(60, water.layout.capsule.minY - 24 - (top + 12)) }
    /// Details were opened from a row: the list coming back rises instead of arriving (A4.21)
    @MainActor static var backFromDetails = false
    /// the test driver's way to swipe a row right (simulator checks: a synthesized drag does not trigger List swipes)
    @MainActor static var testDetails: ((String) -> Void)?

    /// A4.20: the row's words roll out and its flag shrinks into its own centre (0.26 s), then the stamp lifts and the
    /// rows below move up into its place
    private func unstamp(_ r: Row) {
        Feel.lift()
        Task { await MarkStore.shared.unstamp(.country(r.id), name: r.name) }
    }
}

import SwiftUI

/// WHICH PLACE'S DETAILS ARE OPEN in the water (Part 4.4), and what is being edited; written once when they close
@MainActor
@Observable
final class DetailsState {
    static let shared = DetailsState()
    private(set) var key: PlaceKey?
    private(set) var name = ""
    var d = StampDetails()
    var times = 1
    var lived = false
    /// a wished place's Details (4.4.5) instead of a stamped one's
    private(set) var wish = false
    var wd = WishDetails()
    var want = 1
    @ObservationIgnored private var start: (StampDetails, Int, Bool)?
    @ObservationIgnored private var wishStart: (WishDetails, Int)?
    @ObservationIgnored private var opening = false

    var isOpen: Bool { key != nil }

    func open(_ key: PlaceKey, name: String, water: Water) {
        // one thing in the water at a time: not over Verify
        guard self.key == nil, !opening, !VerifyState.shared.isOpen else { return }
        opening = true
        Task {
            defer { opening = false }
            if let x = await MarkStore.shared.details(key) {
                d = x.details; times = max(1, x.times); lived = x.lived
                start = (d, times, lived)
                wish = false
            } else if let x = await MarkStore.shared.wishDetails(key) {
                wd = x.details; want = x.want
                wishStart = (wd, want)
                wish = true
            } else { Feel.refuse(); return }
            self.name = name
            self.key = key
            Feel.tap()
            water.openDetails()
        }
    }

    /// closed (pulled down, a tap off): kept, written once; nothing changed, nothing written (no undo drop)
    func close(water: Water) {
        guard let key else { return }
        let n = name
        if wish {
            let changed = wishStart.map { $0.0 != wd || $0.1 != want } ?? false
            let (w, k) = (wd, want)
            self.key = nil
            wishStart = nil
            water.closeDetails()
            if changed { Task { await MarkStore.shared.setWishDetails(key, name: n, details: w, want: k) } }
            return
        }
        var dd = d
        dd.lived = lived ? true : nil
        let changed = start.map { $0.0 != d || $0.1 != times || $0.2 != lived } ?? false
        let (t, l) = (times, lived)
        self.key = nil
        start = nil
        water.closeDetails()
        if changed { Task { await MarkStore.shared.setDetails(key, name: n, details: dd, times: t, lived: l) } }
    }
}

/// DETAILS IN THE WATER (Part 4.4): the record of one stamped place, at 50%, pullable to full; no Done, no Save.
/// Laid out as Map settings are: black and
/// white only; rows 52 pt with their name on the left and their value on the right; a choice is its word, the chosen
/// one a black capsule with white words that just appears; section
/// names 17 pt semibold black; every word lines up on one 16 pt edge. Haptics only.
/// Not here yet (logged): a visit's exact dates (they wait for our own calendar), Photos,
/// the Lived block swap and the stars' rows by A4.14, the letters rolling at a limit. (A lived time and a place you
/// went come and go by A4.14 / A4.15 as built: see `arrive`, `removeRow`.)
struct DetailsSheet: View {
    let water: Water
    let form: Water.Form
    @State private var s = DetailsState.shared
    @FocusState private var typing: String?
    @State private var kb: CGFloat = 0
    @State private var kind: String?
    @State private var placeName = ""
    @State private var scrolled = false
    /// A4.14 / A4.15: a lived row's identity (the stays carry none), and the rows whose space is open but whose
    /// words and circle are not in yet (`arriving`), are on their way out (`leaving`), or are drawn as plain words
    /// for the roll (`rolling`: a field cannot roll its words, so it is swapped for a Text that looks the same)
    @State private var livedIDs: [String] = []
    @State private var tripIDs: [String] = []
    @State private var placeIDs: [String] = []
    @State private var arriving: Set<String> = []
    @State private var leaving: Set<String> = []
    @State private var rolling: Set<String> = []

    static let modes = ["visit", "airport", "through", "other"]
    static let purposes = ["holiday", "work", "family", "study", "other"]
    static let whys = ["grew-up", "work", "study", "family", "partner", "other"]
    static let kinds = ["city", "area", "landmark", "mountain", "water", "nature", "spot", "stay", "station", "route", "event", "other"]
    static func word(_ k: String) -> String {
        switch k {
        case "family": return "Family and friends"
        case "grew-up": return "Grew up"
        default: return k.prefix(1).uppercased() + k.dropFirst()
        }
    }

    var body: some View {
        let L = water.layout
        let top = max(form.top + 20, L.headBottom + 8)
        let bottom = kb > 0 ? L.H - kb - 8 : L.capsule.minY - 24
        let h = max(60, bottom - top)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    // the place's name heads the sheet only when no card shows above it (at full the card has gone)
                    if form.page > 0.5 || !CardState.shared.isOpen {
                        Text(s.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if s.wish {
                        wishBlock
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            band("Lived here", on: s.lived) { Feel.notch(); s.lived.toggle() }
                            if s.lived { livedBlock } else { visitsBlock }
                        }
                        placesBlock
                        section("Notes") {
                            field("What you did", id: "did", max: 600, lines: true, \.did)
                            field("Anything else", id: "note", max: 600, lines: true, \.note)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            row("Rating") { stars }
                            row("With") {
                                field("Names", id: "with", max: 120, trailing: true, \.with)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // the water's top blurs only once content scrolls under it (4.4.2); neither edge cuts a word sharply
            .scrollEdgeEffectStyle(.soft, for: .top)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: scrolled ? 20 : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20)
                }
            }
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 1 }) { _, v in scrolled = v }
            .onChange(of: typing) { _, id in
                // typing takes Details to full, card or not (the card goes back as the water rises); the field scrolls above the keyboard; keyboard down, back to 50%
                if let id {
                    if water.stop != .full { water.go(.full) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(Motion.quick) { proxy.scrollTo(id, anchor: .center) } }
                } else if water.details, water.stop == .full {
                    water.go(.half)
                }
            }
        }
        .frame(width: L.W - 2 * L.sheetInset, height: h)
        .position(x: L.W / 2, y: top + h / 2)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            kb = f.minY >= L.H - 1 ? 0 : L.H - f.minY
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in kb = 0 }
        // the rows' identities follow the stored rows (a change from outside, an undo, makes them fresh)
        .onChange(of: livedTimes.count, initial: true) { _, n in livedIDs = Self.synced(livedIDs, n) }
        .onChange(of: 1 + (s.d.trips?.count ?? 0), initial: true) { _, n in tripIDs = Self.synced(tripIDs, n) }
        .onAppear { Self.test = { driver($0) } }
        .onChange(of: s.d.places?.count ?? 0, initial: true) { _, n in placeIDs = Self.synced(placeIDs, n) }
    }

    // MARK: the blocks

    /// A WISHED PLACE (4.4.5): how badly (5 stars, feeding Wishlist+; a wish is at least 1), when (Someday /
    /// Sometime soon / Next trip, or in your own words), what you'd do there, notes
    private var wishBlock: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                row("How badly") { wishStars }
                choiceWords("When", [("someday", "Someday"), ("soon", "Sometime soon"), ("next", "Next trip")],
                            chosen: s.wd.prio) { s.wd.prio = $0 }
                wishField("When, in your words", id: "wishWhen", max: 40, \.when)
            }
            section("Notes") {
                wishField("What you'd do there", id: "why", max: 600, lines: true, \.why)
                wishField("Anything else", id: "wishNote", max: 600, lines: true, \.note)
            }
        }
    }
    /// 1 to 5 stars; a wish never goes below 1 (the first star refuses to clear)
    private var wishStars: some View {
        HStack(spacing: 0) {
            ForEach(1 ... 5, id: \.self) { n in
                Star().fill(n <= s.want ? Palette.ink : Palette.ink.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if n == s.want && n == 1 { Feel.refuse(); return }
                        Feel.tap(); s.want = n == s.want ? 1 : n
                    }
            }
        }
        .padding(.trailing, -8)
        .accessibilityElement()
        .accessibilityLabel("How badly")
        .accessibilityValue("\(s.want) of 5")
        .accessibilityAdjustableAction { dir in s.want = max(1, min(5, s.want + (dir == .increment ? 1 : -1))) }
    }
    private func wishField(_ empty: String, id: String, max: Int, lines: Bool = false,
                           _ k: WritableKeyPath<WishDetails, String?>) -> some View {
        TextField(empty, text: Binding(get: { s.wd[keyPath: k] ?? "" }, set: { v in
            if v.count > max { Feel.refuse() }
            let c = String(v.prefix(max))
            s.wd[keyPath: k] = c.isEmpty ? nil : c
        }), axis: lines ? .vertical : .horizontal)
        .font(.body)
        .foregroundStyle(Palette.ink)
        .lineLimit(lines ? 1 ... 12 : 1 ... 1)
        .frame(minHeight: lines ? 52 : 44)
        .focused($typing, equals: id)
        .id(id)
    }

    private var visitsBlock: some View {
        let n = 1 + (s.d.trips?.count ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            row("Times") { stepper }
            // one row per trip (4.4.3): each visit its time in words (until our own calendar
            // exists), how and why; the × only when there is more than one
            ForEach(0 ..< n, id: \.self) { i in
                visitRows(i, key: Self.key(tripIDs, i, "trip"), count: n)
                    .padding(.top, i == 0 ? 0 : 12)   // a little air between one trip and the next
            }
            row("Add a visit") { EmptyView() }
                .contentShape(Rectangle())
                .onTapGesture { addTrip() }
                .accessibilityAddTraits(.isButton)
        }
    }

    /// visit i's key paths: the first visit is the record's own fields, the others its `trips`
    private func tk(_ i: Int, _ field: WritableKeyPath<StampDetails.Trip, String?>) -> WritableKeyPath<StampDetails, String?> {
        let visit: WritableKeyPath<StampDetails, StampDetails.Trip> = \StampDetails.[trip: i]
        return visit.appending(path: field)
    }
    @ViewBuilder
    private func visitRows(_ i: Int, key k: String, count n: Int) -> some View {
        let gone = arriving.contains(k) || leaving.contains(k)
        let plain = rolling.contains(k)
        let rough = tk(i, \.whenRough), mode = tk(i, \.mode), purpose = tk(i, \.purpose)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(gone ? Caption.blank("When", "\u{2002}") : "When").font(.body).foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: gone ? 0 : 1))
                Spacer(minLength: 8)
                if plain {
                    let v = s.d[keyPath: rough] ?? ""
                    let w = v.isEmpty ? "Summer 2019" : v
                    Text(gone ? Caption.blank(w, "\u{2002}") : w).font(.body)
                        .foregroundStyle(v.isEmpty ? Color(uiColor: .placeholderText) : Palette.ink)
                        .contentTransition(.numericText(value: gone ? 0 : 1))
                        .frame(minHeight: 44)
                } else {
                    // a visit's time in words until our own calendar exists ("Summer 2019", 40 characters)
                    field("Summer 2019", id: "rough\(i)", max: 40, trailing: true, rough)
                }
                if n > 1 {
                    xCircle { removeTrip(k) }
                        .scaleEffect(gone ? 0 : 1)
                        .transition(.scale)
                }
            }
            .frame(minHeight: 52)
            choice("How", Self.modes, chosen: s.d[keyPath: mode], blank: gone) { s.d[keyPath: mode] = $0 }
            if s.d[keyPath: mode] == "other" { field("How, in your words", id: "modeOther\(i)", max: 60, tk(i, \.modeOther)) }
            choice("Trip", Self.purposes, chosen: s.d[keyPath: purpose], blank: gone) { s.d[keyPath: purpose] = $0 }
            if s.d[keyPath: purpose] == "other" { field("Trip, in your words", id: "purposeOther\(i)", max: 60, tk(i, \.purposeOther)) }
        }
    }
    /// A4.14: the space opens, then the visit's words roll in; Times goes up to the visits there are when it was lower
    private func addTrip() {
        Feel.tap()
        let k = UUID().uuidString
        let n = 1 + (s.d.trips?.count ?? 0)
        tripIDs = Self.synced(tripIDs, n)
        arriving.insert(k); rolling.insert(k)
        withAnimation(Motion.quick) {
            tripIDs.append(k)
            s.d.trips = (s.d.trips ?? []) + [StampDetails.Trip()]
        }
        if s.times < n + 1 { s.times = n + 1 }
        arrive(k)
    }
    /// A4.15: its words roll out and its × shrinks, then the rows below move up; the first visit going takes the
    /// second's place in the record's own fields
    private func removeTrip(_ k: String) {
        let n = 1 + (s.d.trips?.count ?? 0)
        tripIDs = Self.synced(tripIDs, n)
        guard n > 1, tripIDs.contains(k) else { return }
        removeRow(k, index: { tripIDs.firstIndex(of: k) }) { j in
            var all = [s.d[trip: 0]] + (s.d.trips ?? [])
            guard j < all.count else { return }
            all.remove(at: j)
            s.d[trip: 0] = all.first ?? StampDetails.Trip()
            let rest = Array(all.dropFirst())
            s.d.trips = rest.isEmpty ? nil : rest
            tripIDs.remove(at: j)
        }
    }

    /// every time you lived there, in order: the record's own from/to first, then `stays` (the old app's layout)
    private var livedTimes: [StampDetails.Stay] {
        [StampDetails.Stay(from: s.d.from ?? "", to: s.d.to ?? "")] + (s.d.stays ?? [])
    }
    private func setLived(_ t: [StampDetails.Stay]) {
        let first = t.first ?? StampDetails.Stay(from: "", to: "")
        s.d.from = first.from.isEmpty ? nil : first.from
        s.d.to = first.to.isEmpty ? nil : first.to
        let rest = Array(t.dropFirst())
        s.d.stays = rest.isEmpty ? nil : rest
    }

    private var livedBlock: some View {
        let t = livedTimes.enumerated().map { (Self.key(livedIDs, $0.offset, "lived"), $0.element) }
        let now = s.d.livesNow == true
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(t.enumerated()), id: \.element.0) { i, row in
                let stay = row.1
                let k = row.0
                let last = i == t.count - 1
                let gone = arriving.contains(k) || leaving.contains(k)
                let plain = rolling.contains(k)
                HStack(spacing: 12) {
                    if plain {
                        monthWords(stay.from, empty: "Moved in", gone: gone)
                    } else {
                        MonthField(empty: "Moved in", value: stay.from, focus: $typing, id: "in\(i)") { v in
                            var x = livedTimes; guard i < x.count else { return }; x[i].from = v; setLived(x)
                        }
                    }
                    if now && last {
                        Text("Now").font(.body).foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    } else if plain {
                        monthWords(stay.to, empty: "Moved out", gone: gone)
                    } else {
                        MonthField(empty: "Moved out", value: stay.to, focus: $typing, id: "out\(i)") { v in
                            var x = livedTimes; guard i < x.count else { return }; x[i].to = v; setLived(x)
                        }
                    }
                    if let len = Self.length(stay.from, now && last ? nil : stay.to, toNow: now && last) {
                        Text(gone ? Caption.blank(len, "\u{2002}") : len).font(.body).foregroundStyle(Palette.ink).fixedSize()
                            .contentTransition(.numericText(value: gone ? 0 : 1))
                    }
                    if t.count > 1 {
                        xCircle { removeLived(i) }
                            .scaleEffect(gone ? 0 : 1)
                            // the first row's × comes and goes with the second row: about its own centre, never a fade
                            .transition(.scale)
                    }
                }
            }
            band("I still live here", on: now) {
                Feel.tap()
                s.d.livesNow = now ? nil : true
                if !now { var x = livedTimes; x[x.count - 1].to = ""; setLived(x) }
            }
            if !now {
                row("Add time") { EmptyView() }
                    .contentShape(Rectangle())
                    .onTapGesture { addLived() }
                    .accessibilityAddTraits(.isButton)
            }
            // (here "family" is Family, not the trip's "Family and friends")
            choiceWords("Why", Self.whys.map { ($0, $0 == "family" ? "Family" : Self.word($0)) }, chosen: s.d.livedWhy) {
                s.d.livedWhy = $0
            }
            if s.d.livedWhy == "other" { field("Why, in your words", id: "whyOther", max: 60, \.livedWhyOther) }
        }
    }

    private var placesBlock: some View {
        section("Places") {
            ForEach(Array((s.d.places ?? []).enumerated()).map { (Self.key(placeIDs, $0.offset, "place"), $0.element) }, id: \.0) { k, p in
                let gone = arriving.contains(k) || leaving.contains(k)
                HStack(spacing: 12) {
                    Text(gone ? Caption.blank(p.n, "\u{2002}") : p.n).font(.body).foregroundStyle(Palette.ink).lineLimit(2)
                        .contentTransition(.numericText(value: gone ? 0 : 1))
                    Spacer(minLength: 8)
                    let w = Self.word(p.k)
                    Text(gone ? Caption.blank(w, "\u{2002}") : w).font(.body).foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: gone ? 0 : 1))
                    xCircle { removePlace(Int(placeIDs.firstIndex(of: k) ?? 0)) }
                    .scaleEffect(gone ? 0 : 1)
                }
                .frame(minHeight: 52)
            }
            HStack(spacing: 12) {
                TextField("Add a place", text: Binding(get: { placeName }, set: { v in
                    if v.count > 60 { Feel.refuse() }
                    placeName = String(v.prefix(60))
                }))
                .font(.body).foregroundStyle(Palette.ink)
                .focused($typing, equals: "place").id("place")
                .submitLabel(.done)
                .onSubmit { addPlace() }
                // Add only once there is something to add (a name and its kind); no greyed-out button
                if canAdd {
                    Text("Add").font(.body.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36).background(Palette.ink, in: .capsule)
                        .frame(minHeight: 44).contentShape(Rectangle())
                        .onTapGesture { addPlace() }
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(minHeight: 52)
            // its kind, asked once a name is being typed
            if !placeName.trimmingCharacters(in: .whitespaces).isEmpty {
                chips(Self.kinds.map { ($0, Self.word($0)) }, chosen: kind) { kind = kind == $0 ? nil : $0 }
            }
        }
    }
    private var canAdd: Bool { kind != nil && !placeName.trimmingCharacters(in: .whitespaces).isEmpty }
    private func addPlace() {
        guard canAdd, let k = kind else { Feel.refuse(); return }
        Feel.tap()
        let id = UUID().uuidString
        placeIDs = Self.synced(placeIDs, s.d.places?.count ?? 0)
        arriving.insert(id)
        let went = StampDetails.Went(n: placeName.trimmingCharacters(in: .whitespaces), k: k)
        withAnimation(Motion.quick) { placeIDs.append(id); s.d.places = (s.d.places ?? []) + [went] }
        arrive(id)
        placeName = ""
        kind = nil
    }

    // MARK: A4.14 / A4.15 a row comes and goes
    // A row comes: its space opens first (the rows below move down, quick curve), then its words roll in and its
    // circle grows about its own centre (0.26 s). A row goes: its words roll out and its circle shrinks into its centre
    // (0.26 s), then the rows below move up. One after the other, never both at once (the book has them together and
    // the shapes travelling from the Add control: not kept, so nothing crosses anything).
    static func key(_ ids: [String], _ i: Int, _ p: String) -> String { i < ids.count ? ids[i] : "\(p)\(i)" }
    /// identities lined up with the rows (the stored rows carry none: made fresh when the counts differ)
    static func synced(_ ids: [String], _ n: Int) -> [String] { ids.count == n ? ids : (0 ..< n).map { _ in UUID().uuidString } }
    private func arrive(_ k: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.smooth(duration: 0.26)) { _ = arriving.remove(k) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { _ = rolling.remove(k) }
        }
    }
    private func addLived() {
        Feel.tap()
        let k = UUID().uuidString
        livedIDs = Self.synced(livedIDs, livedTimes.count)
        arriving.insert(k); rolling.insert(k)
        withAnimation(Motion.quick) { livedIDs.append(k); setLived(livedTimes + [StampDetails.Stay(from: "", to: "")]) }
        arrive(k)
    }
    private func removeLived(_ i: Int) {
        livedIDs = Self.synced(livedIDs, livedTimes.count)
        guard i < livedIDs.count, livedTimes.count > 1 else { return }
        let k = livedIDs[i]
        removeRow(k, index: { livedIDs.firstIndex(of: k) }) { j in
            var x = livedTimes; x.remove(at: j); setLived(x); livedIDs.remove(at: j)
        }
    }
    private func removePlace(_ i: Int) {
        placeIDs = Self.synced(placeIDs, s.d.places?.count ?? 0)
        guard i < placeIDs.count else { return }
        let k = placeIDs[i]
        removeRow(k, index: { placeIDs.firstIndex(of: k) }) { j in
            var x = s.d.places ?? []; x.remove(at: j); s.d.places = x.isEmpty ? nil : x; placeIDs.remove(at: j)
        }
    }
    /// the test driver's hands on the rows (simulator checks): lived, addtime, removelived N, addplace <kind> <name>, removeplace N
    @MainActor static var test: (([String]) -> Void)?
    private func driver(_ p: [String]) {
        switch p.first {
        case "lived": s.lived.toggle()
        case "addvisit": addTrip()
        case "removevisit": tripIDs = Self.synced(tripIDs, 1 + (s.d.trips?.count ?? 0)); if let i = Int(p.count > 1 ? p[1] : "1"), i < tripIDs.count { removeTrip(tripIDs[i]) }
        case "addtime": addLived()
        case "removelived": removeLived(Int(p.count > 1 ? p[1] : "0") ?? 0)
        case "addplace": kind = p.count > 1 ? p[1] : "city"; placeName = p.dropFirst(2).joined(separator: " "); addPlace()
        case "removeplace": removePlace(Int(p.count > 1 ? p[1] : "0") ?? 0)
        default: break
        }
    }

    private func removeRow(_ k: String, index: @escaping () -> Int?, drop: @escaping (Int) -> Void) {
        Feel.lift()
        rolling.insert(k)
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.26)) { _ = leaving.insert(k) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                if let j = index() { withAnimation(Motion.quick) { drop(j) } }
                leaving.remove(k); rolling.remove(k)
            }
        }
    }
    /// a month field drawn as plain words for the roll, looking as the field does (its value, or its placeholder)
    private func monthWords(_ v: String, empty: String, gone: Bool) -> some View {
        let p = v.split(separator: "-")
        let shown: String? = p.count >= 2 ? "\(p[1]) / \(p[0])" : (p.count == 1 && p[0].count == 4 ? "00 / \(p[0])" : nil)
        let w = shown ?? empty
        return Text(gone ? Caption.blank(w, "\u{2002}") : w).font(.body)
            .foregroundStyle(shown == nil ? Color(uiColor: .placeholderText) : Palette.ink)
            .contentTransition(.numericText(value: gone ? 0 : 1))
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    // MARK: the parts

    /// a section: its name (17 pt semibold, black), then its rows
    private func section<C: View>(_ name: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.headline).foregroundStyle(Palette.ink)
                .frame(minHeight: 32, alignment: .bottom)
                .accessibilityAddTraits(.isHeader)
            c()
        }
    }

    /// a row: its name on the left, its value on the right, 52 pt
    private func row<V: View>(_ name: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(name).font(.body).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            value()
        }
        .frame(minHeight: 52)
    }

    /// a two-state row as Map settings' current choice: on = a black band the water's width with white words,
    /// appearing in one frame
    private func band(_ name: String, on: Bool, tap: @escaping () -> Void) -> some View {
        Text(name)
            .font(.body)
            .foregroundStyle(on ? .white : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
            .background(on ? Palette.ink : .clear, in: .capsule)
            .padding(.horizontal, -16)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// a row of choices under its name: the words wrap; the chosen one sits on a black capsule with white words; the
    /// chosen one tapped again clears
    private func choice(_ name: String, _ ids: [String], chosen: String?, blank: Bool = false, set: @escaping (String?) -> Void) -> some View {
        choiceWords(name, ids.map { ($0, Self.word($0)) }, chosen: chosen, blank: blank, set: set)
    }
    /// `blank`: the words as blanks of their length, for a row coming or going (they roll, never fade)
    private func choiceWords(_ name: String, _ items: [(String, String)], chosen: String?, blank: Bool = false,
                             set: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(blank ? Caption.blank(name, "\u{2002}") : name).font(.body).foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: blank ? 0 : 1))
                .frame(minHeight: 44, alignment: .leading)
            chips(items, chosen: chosen, blank: blank) { set(chosen == $0 ? nil : $0) }
                .padding(.bottom, 8)
        }
    }
    /// 17 pt words, 36 pt capsules with 44 pt touch areas, 8 pt apart; the first word lines up with the names above
    private func chips(_ items: [(String, String)], chosen: String?, blank: Bool = false, tap: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(items, id: \.0) { id, word in
                Text(blank ? Caption.blank(word, "\u{2002}") : word)
                    .contentTransition(.numericText(value: blank ? 0 : 1))
                    .font(.body)
                    .foregroundStyle(chosen == id ? .white : Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(chosen == id ? Palette.ink : .clear, in: .capsule)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); tap(id) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(chosen == id ? .isSelected : [])
            }
        }
        .padding(.leading, -12)
    }

    /// Times: an exact number from 1; drag on the number or its − / + circles (36 pt drawn, 44 pt touch, solid black,
    /// white glyphs); the number rolls; refuse at the floor
    @State private var dragFrom: Int?
    @State private var atFloor = false
    private var stepper: some View {
        HStack(spacing: 4) {
            // the floor is the number of visit rows
            circle("minus") { if s.times > timesFloor { s.times -= 1; Feel.tap() } else { Feel.refuse() } }
            Text("\(s.times)").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(s.times)))
                .animation(Motion.quick, value: s.times)
                .frame(minWidth: 36, minHeight: 44)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { g in
                    let base = dragFrom ?? s.times
                    dragFrom = base
                    let v = base + Int((-g.translation.height / 16).rounded())
                    // no haptic while it runs; one refuse when it hits the floor
                    if v < timesFloor { if !atFloor { atFloor = true; Feel.refuse() }; if s.times != timesFloor { s.times = timesFloor }; return }
                    atFloor = false
                    if v != s.times { s.times = v }
                }.onEnded { _ in
                    dragFrom = nil
                    atFloor = false
                })
            circle("plus") { s.times += 1; Feel.tap() }
        }
        .padding(.trailing, -4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Times")
        .accessibilityValue("\(s.times)")
        .accessibilityAdjustableAction { dir in
            if dir == .increment { s.times += 1 } else if s.times > timesFloor { s.times -= 1 }
        }
    }
    /// Times never goes below the visit rows there are
    private var timesFloor: Int { 1 + (s.d.trips?.count ?? 0) }
    private func circle(_ g: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: g).font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Palette.ink, in: .circle)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
    /// × on a row (only where there is more than one): solid black, white ×, 24 pt drawn, 44 pt touch
    private func xCircle(_ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Palette.ink, in: .circle)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }

    /// 5 stars, a normal five-pointed star, 28 pt; filled black up to the rating, the rest black at 15%; the same star
    /// again clears
    private var stars: some View {
        HStack(spacing: 0) {
            ForEach(1 ... 5, id: \.self) { n in
                Star().fill(n <= (s.d.stars ?? 0) ? Palette.ink : Palette.ink.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); s.d.stars = s.d.stars == n ? nil : n }
            }
        }
        .padding(.trailing, -8)
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue("\(s.d.stars ?? 0) of 5")
        .accessibilityAdjustableAction { dir in
            let v = (s.d.stars ?? 0) + (dir == .increment ? 1 : -1)
            s.d.stars = v <= 0 ? nil : min(5, v)
        }
    }

    /// a field: text on the water, its empty word in black 50% (the system's own placeholder), no box, no line;
    /// past the limit the text stops and refuse plays
    private func field(_ empty: String, id: String, max: Int, lines: Bool = false, trailing: Bool = false,
                       _ k: WritableKeyPath<StampDetails, String?>) -> some View {
        TextField(empty, text: Binding(get: { s.d[keyPath: k] ?? "" }, set: { v in
            if v.count > max { Feel.refuse() }
            let c = String(v.prefix(max))
            s.d[keyPath: k] = c.isEmpty ? nil : c
        }), axis: lines ? .vertical : .horizontal)
        .font(.body)
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(trailing ? .trailing : .leading)
        .lineLimit(lines ? 1 ... 12 : 1 ... 1)
        .frame(minHeight: lines ? 52 : 44)
        .focused($typing, equals: id)
        .id(id)
    }

    /// "2 years, 3 months" between two "YYYY-MM" (or to now)
    static func length(_ a: String, _ b: String?, toNow: Bool) -> String? {
        func months(_ s: String) -> Int? {
            let p = s.split(separator: "-")
            guard let y = p.first.flatMap({ Int($0) }) else { return nil }
            let m = p.count > 1 ? Int(p[1]) ?? 1 : 1
            return y * 12 + (m - 1)
        }
        guard let x = months(a) else { return nil }
        let end: Int
        if toNow {
            let c = Calendar.current.dateComponents([.year, .month], from: Date())
            end = (c.year ?? 0) * 12 + (c.month ?? 1) - 1
        } else {
            guard let b, let e = months(b) else { return nil }
            end = e
        }
        let n = end - x
        guard n >= 0 else { return nil }
        let y = n / 12, m = n % 12
        var parts: [String] = []
        if y > 0 { parts.append(y == 1 ? "1 year" : "\(y) years") }
        if m > 0 { parts.append(m == 1 ? "1 month" : "\(m) months") }
        return parts.isEmpty ? "Under a month" : parts.joined(separator: ", ")
    }
}

/// MM / YYYY typed on the number pad; a bad month turns red (d94f3d) and only the year is kept ("YYYY-MM" or "YYYY")
struct MonthField: View {
    let empty: String
    let value: String
    var focus: FocusState<String?>.Binding
    let id: String
    let set: (String) -> Void
    @State private var digits = ""
    @State private var bad = false

    var body: some View {
        TextField(empty, text: Binding(get: { Self.show(digits) }, set: { v in
            let d = String(v.filter(\.isNumber).prefix(6))
            digits = d
            guard d.count == 6, let m = Int(d.prefix(2)) else { bad = false; if d.isEmpty { set("") }; return }
            let y = String(d.suffix(4))
            bad = !(1 ... 12).contains(m)
            set(bad ? y : "\(y)-\(d.prefix(2))")
            if bad { Feel.refuse() }
        }))
        .keyboardType(.numberPad)
        .font(.body)
        .foregroundStyle(bad ? Color(hex: 0xd94f3d) : Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .focused(focus, equals: id)
        .id(id)
        .onAppear {
            let p = value.split(separator: "-")
            if p.count >= 2, p[0].count == 4 { digits = String(p[1].prefix(2)) + p[0] }
            else if p.count == 1, p[0].count == 4 { digits = "00" + p[0]; bad = true }
        }
    }
    static func show(_ d: String) -> String {
        d.count <= 2 ? d : d.prefix(2) + " / " + d.dropFirst(2)
    }
}

/// a normal five-pointed star
struct Star: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2, q = R * 0.382
        for i in 0 ..< 10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let rr = i % 2 == 0 ? R : q
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// chips that wrap to the next line
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { y += row; x = 0; row = 0 }
            x += s.width + spacing; row = max(row, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(w, widest), height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX, x + s.width > b.maxX { y += row; x = b.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

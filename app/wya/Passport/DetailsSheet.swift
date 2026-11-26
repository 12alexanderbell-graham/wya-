import PhotosUI
import SwiftUI

/// WHICH PLACE'S DETAILS ARE OPEN in the water (Part 4.4), and what is being edited; written once when they close
@MainActor
@Observable
final class DetailsState {
    static let shared = DetailsState()
    /// each text field's limit, as its row was drawn: typing past it is never cut off, and what is kept is what fits,
    /// when Details closes
    @ObservationIgnored var limits: [WritableKeyPath<StampDetails, String?>: Int] = [:]
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
    @ObservationIgnored private(set) var opening = false

    var isOpen: Bool { key != nil }
    /// closing back to the Stamped list (A4.21 reversed): the sheet's words roll out for 0.26 s before it closes
    private(set) var rollingOut = false

    /// `lived`: opened with Lived here on (a hold menu's Lived here, 11.5)
    func open(_ key: PlaceKey, name: String, water: Water, lived livedOn: Bool = false) {
        // one thing in the water at a time: not over Verify
        guard self.key == nil, !opening, !VerifyState.shared.isOpen, !VerifyState.shared.opening else { return }
        opening = true
        #if DEBUG
        let t0 = CACurrentMediaTime()
        #endif
        Task {
            defer { opening = false }
            #if DEBUG
            defer { NSLog("wya details open %.0f ms", (CACurrentMediaTime() - t0) * 1000) }
            #endif
            if let x = await MarkStore.shared.details(key) {
                d = x.details; times = max(1, x.times); lived = x.lived
                start = (d, times, lived)
                if livedOn { lived = true }
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
    /// rows whose × was tapped and that are still rolling out: taken out of the details now if Details closes first
    /// (the copy written on close kept them, and the row came back)
    @ObservationIgnored var pendingDrops: [String: () -> Void] = [:]
    func close(water: Water, now: Bool = false) {
        guard let key else { return }
        let drops = pendingDrops; pendingDrops = [:]
        drops.values.forEach { $0() }
        let rolled = rollingOut
        if !now {
            guard !rollingOut else { return }
            if StampedList.backFromDetails && water.stampedList {
                withAnimation(.smooth(duration: 0.26)) { rollingOut = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                    self?.close(water: water, now: true)
                    self?.rollingOut = false
                }
                return
            }
        }
        let n = name
        if wish {
            let changed = wishStart.map { $0.0 != wd || $0.1 != want } ?? false
            let (w, k) = (wd, want)
            self.key = nil
            wishStart = nil
            water.closeDetails(rolled: rolled)
            if changed { Task { await MarkStore.shared.setWishDetails(key, name: n, details: w, want: k) } }
            return
        }
        var dd = d
        for (k, m) in limits {
            guard let v = dd[keyPath: k], v.count > m else { continue }
            var cut = String(v.prefix(m))
            // links keep their whole lines: an address cut in half is no link
            if k == \StampDetails.links, let nl = cut.lastIndex(of: "\n") { cut = String(cut[..<nl]) }
            dd[keyPath: k] = cut
        }
        dd.lived = lived ? true : nil
        let changed = start.map { $0.0 != d || $0.1 != times || $0.2 != lived } ?? false
        let (t, l) = (times, lived)
        self.key = nil
        start = nil
        water.closeDetails(rolled: rolled)
        if changed { Task { await MarkStore.shared.setDetails(key, name: n, details: dd, times: t, lived: l) } }
    }
}

/// DETAILS IN THE WATER (Part 4.4): the record of one stamped place, at 50%, pullable to full; no Done, no Save.
/// Laid out as Map settings are: black and
/// white only; rows 52 pt with their name on the left and their value on the right; a choice is its word, the chosen
/// one a black capsule with white words that just appears; section
/// names 17 pt semibold black; every word lines up on one 16 pt edge. Haptics only.
/// Not here yet (logged): a visit's exact dates (they wait for our own calendar), Photos,
/// the letters rolling at a limit. (A lived time and a place you
/// went come and go by A4.14 / A4.15 as built: see `arrive`, `removeRow`.)
struct DetailsSheet: View {
    let water: Water
    let form: Water.Form
    /// the map, for the regions a town stamped from here stamps with it
    var map: MapController?
    @State private var s = DetailsState.shared
    @State private var marks = MarkStore.shared
    @FocusState private var typing: String?
    @State private var kb: CGFloat = 0
    @State private var kind: String?
    @State private var placeName = ""
    @State private var scrolled = false
    /// the gaps between rows (content coordinates) a list may end in (0.7)
    @State private var cuts: [CGFloat] = []
    /// A4.14 / A4.15: a lived row's identity (the stays carry none), and the rows whose space is open but whose
    /// words and circle are not in yet (`arriving`), are on their way out (`leaving`), or are drawn as plain words
    /// for the roll (`rolling`: a field cannot roll its words, so it is swapped for a Text that looks the same)
    @State private var livedIDs: [String] = []
    @State private var tripIDs: [String] = []
    /// the block on screen while a Lived swap runs (nil: the one Lived says); `blockGone`: its words blank, its shapes 0
    @State private var shownLived: Bool?
    @State private var blockGone = false
    /// A4.21's Details end: opened from a Stamped list row, the sheet's words start as blanks and roll in (its shapes
    /// grow); closing back to the list they roll out first (`DetailsState.rollingOut`), then the list rises
    @State private var sheetGone = StampedList.backFromDetails
    /// how far below its place the sheet still is, coming up from the list (0 in place)
    @State private var rise: CGFloat = StampedList.backFromDetails ? 900 : 0
    /// every word blank and every shape at 0: the Lived block swapping, or the whole sheet coming from / going to the list
    private var out: Bool { blockGone || sheetGone || s.rollingOut }
    @State private var swapJob = 0
    @State private var placeIDs: [String] = []
    @State private var arriving: Set<String> = []
    @State private var leaving: Set<String> = []
    @State private var rolling: Set<String> = []

    static let modes = ["visit", "airport", "through", "other"]
    static let purposes = ["holiday", "work", "family", "study", "other"]
    /// HOW LONG a visit was when its days aren't known: a number of days, never a range or a word; kept as the number
    /// ("12"). A length picked before in words reads as its days until it is changed.
    static let wordDays: [String: Int] = ["day": 1, "days": 3, "week": 7, "weeks": 14, "month": 30, "longer": 60]
    static func lengthDays(_ v: String?) -> Int? { v.flatMap { Int($0) ?? wordDays[$0] } }
    static let whys = ["grew-up", "work", "study", "family", "partner", "other"]
    static let kinds = ["city", "area", "landmark", "mountain", "water", "nature", "spot", "stay", "station", "route", "event", "other"]
    static func word(_ k: String) -> String {
        switch k {
        case "family": return "Family and friends"
        case "grew-up": return "Grew up"
        default: return k.prefix(1).uppercased() + k.dropFirst()
        }
    }

    /// A PLACE THAT IS NOT SOMEWHERE YOU STAY (a mountain, a museum, a park, a sea, a place of your own): nobody
    /// lives on Mount Everest or is there. Its Details are when you were there, how often, your notes, your rating
    /// and who with: no Lived here, no How, no Trip, no places inside it. A country, a region and a town keep them
    /// all.
    private var aThing: Bool { s.key?.kind == .thing || s.key?.kind == .yours }

    var body: some View {
        let L = water.layout
        let top = max(form.top + 20, L.headBottom + 8)
        let bottom = kb > 0 ? L.H - kb - 8 : L.capsule.minY - 24
        let room = max(60, bottom - top)
        // whole rows only at rest (0.7): the visible height ends in the gap between two rows, the soft edge over that
        // gap, and a scroll stops where the bottom lands in a gap (the top passes under the water's soft edge, 4.4.2)
        let h = EdgeRows.fit(room, cuts: cuts)
        let wide = water.stop == .full
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    // the place's name heads the sheet only when no card shows above it (at full the card has gone)
                    if form.page > 0.5 || !CardState.shared.isOpen {
                        Text(sheetGone || s.rollingOut ? Caption.blank(s.name, "\u{2002}") : s.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                            .contentTransition(.identity)
                            .edgeRow()
                            .accessibilityAddTraits(.isHeader)
                    }
                    if s.wish {
                        wishBlock
                    } else {
                        // YOUR VISITS ALWAYS, AND LIVED HERE AS ITS OWN PART UNDER THEM: Lived here was a black band
                        // that swapped the visits out for the moved in / moved out rows, so saying you lived
                        // somewhere hid every trip there, and the sheet opened on that band. Now the visits stay;
                        // Lived here is a row with its plus (as Add a visit) that opens its own part, which its ×
                        // closes (the dates are kept) (closed, Lived here is the row after Add a visit, no gap; open,
                        // its own part a section away)
                        VStack(alignment: .leading, spacing: 0) {
                            visitsBlock
                            if !aThing { livedSection.padding(.top, s.lived ? 28 : 0) }
                        }
                        if !aThing, !regionUnits.isEmpty { regionsBlock }
                        if !aThing { placesBlock }
                        section("Notes", blank: out) {
                            if out || shownLived != nil {
                                fieldWords("What you did", s.d.did, gone: out)
                                fieldWords("Anything else", s.d.note, gone: out)
                                fieldWords("Links", s.d.links, gone: out)
                            } else {
                                field("What you did", id: "did", max: 600, lines: true, \.did)
                                field("Anything else", id: "note", max: 600, lines: true, \.note)
                                field("Links", id: "links", max: 600, lines: true, web: true, \.links)
                            }
                        }
                        row("Rating", blank: out) { stars.opacity(out ? 0 : 1).transaction { $0.disablesAnimations = true; $0.animation = nil } }
                        photosBlock
                        VStack(alignment: .leading, spacing: 0) {
                            row("With", blank: out) {
                                if out { fieldWords("Names", s.d.with, gone: out, trailing: true) }
                                else { field("Names", id: "with", max: 120, trailing: true, \.with) }
                            }
                        }
                    }
                }
                // (a pull down from the list's top at full brings the water down, Water/WaterHandoff)
                .background(WaterHandoff())
                .padding(.horizontal, 16 + (wide ? L.sheetInset : 0))
                .padding(.top, 4)
                .padding(.bottom, 24)
                .coordinateSpace(name: EdgeRows.space)
                .onPreferenceChange(EdgeRows.self) { cuts = EdgeRows.cuts($0) }
            }
            .scrollBlur()
            .scrollIndicators(.hidden)
            // from the Stamped list: the sheet comes up through its bottom soft edge as one block, its words in
            // place, as the list went down through it
            .offset(y: rise)
            // below full a drag on the rows is the water's (it rises to full, or comes down), as in Apple's sheets
            // and the Places shelf; at full they scroll
            .scrollDisabled(water.stop != .full)
            .scrollDismissesKeyboard(.interactively)
            // the water's top blurs only once content scrolls under it (4.4.2); neither edge cuts a word sharply
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: scrolled ? 20 : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
                }
            }
            .scrollTargetBehavior(GapSnap(cuts: cuts))
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 1 }) { _, v in scrolled = v }
            .onChange(of: scrollAsk) { _, id in
                guard let id else { return }
                withAnimation(Motion.quick) { proxy.scrollTo(id, anchor: .top) }
                scrollAsk = nil
            }
            .onChange(of: typing) { _, id in
                // typing takes Details to full, card or not; the field scrolls above the keyboard; keyboard down,
                // back to 50%
                if let id {
                    if water.stop != .full { water.go(.full) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(Motion.quick) { proxy.scrollTo(id, anchor: .center) } }
                } else if water.details, water.stop == .full, !water.stampedList, calOpen == nil {
                    // (not with a calendar open: below full it could not be scrolled to)
                    // (opened from the Stamped list it stays at full, the list's height: lower was the list's pull down)
                    water.go(.half)
                }
            }
        }
        // at full the water meets the screen's edges, so the rows' area does too (a band or a calendar week runs
        // edge to edge); below full it stops at the water's rounded sides
        .frame(width: wide ? L.W : L.W - 2 * L.sheetInset, height: h)
        .position(x: L.W / 2, y: top + h / 2)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            kb = f.minY >= L.H - 1 ? 0 : L.H - f.minY
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in kb = 0 }
        // the rows' identities follow the stored rows (a change from outside, an undo, makes them fresh)
        .onChange(of: livedTimes.count, initial: true) { _, n in livedIDs = Self.synced(livedIDs, n) }
        // the place no longer stamped (or no longer wished) under it: undone by a shake or a three-finger swipe, or
        // taken off another way. Details closes rather than stand open for a record that is gone (what was typed could
        // no longer be kept)
        .onChange(of: s.key.map { k in s.wish ? marks.state(k).wished : marks.state(k).stamped } ?? true) { _, still in
            if !still { s.close(water: water, now: true) }
        }
        .onAppear {
            // (a country whose Provinces were read already, as its card opened: there from the first frame)
            if regionUnits.isEmpty, let k = s.key, k.kind == .country, !s.wish, let e = DetailsRegions.cache[k.id.lowercased()] {
                applyRegions(e, k.id.lowercased())
            }
            // from the list: the words roll in once the list has gone (they start as blanks, see `sheetGone`)
            guard sheetGone else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { sheetGone = false; rise = water.layout.capsule.minY - 24 - max(form.top + 20, water.layout.headBottom + 8) }
                DispatchQueue.main.async { withAnimation(Motion.quick) { rise = 0 } }
            }
        }
        .onChange(of: 1 + (s.d.trips?.count ?? 0), initial: true) { _, n in tripIDs = Self.synced(tripIDs, n) }
        .task(id: s.key) { await loadRegions() }
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
                wishField("When", id: "wishWhen", max: 40, \.when)
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
                RatingStar(on: n <= s.want)
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
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
        }), prompt: Text(empty).foregroundStyle(Palette.ink.opacity(0.5)), axis: lines ? .vertical : .horizontal)
        .font(.body)
        .foregroundStyle(Palette.ink)
        .lineLimit(lines ? 1 ... 12 : 1 ... 1)
        .frame(minHeight: lines ? 52 : 44).edgeRow()
        .focused($typing, equals: id)
        .id(id)
    }

    /// the visit whose calendar is open under its When row
    @State private var calOpen: Int?
    private var visitsBlock: some View {
        let n = 1 + (s.d.trips?.count ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            row("Times", blank: out) { stepper }
            // one row per trip (4.4.3): each visit its time in words (until our own calendar
            // exists), how and why; the × only when there is more than one
            ForEach(0 ..< n, id: \.self) { i in
                visitRows(i, key: Self.key(tripIDs, i, "trip"), count: n)
                    .padding(.top, i == 0 ? 0 : 12)   // a little air between one trip and the next
            }
            row("Add a visit", blank: out) { Icon5(key: "plus", ink: Palette.ink, size: 17).frame(width: 28, height: 28).opacity(out ? 0 : 1) }
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
        let gone = out || arriving.contains(k) || leaving.contains(k)
        let plain = out || shownLived != nil || rolling.contains(k)
        let rough = tk(i, \.whenRough), mode = tk(i, \.mode), purpose = tk(i, \.purpose)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(gone ? Caption.blank("When", "\u{2002}") : "When").font(.body).foregroundStyle(Palette.ink)
                    .contentTransition(.identity)
                    .frame(minHeight: 44).contentShape(Rectangle())
                    // A VISIT HELD by its first word (11.5; never over its text field, whose own hold moves the
                    // cursor): Duplicate (a new visit with its how, why and time in words) · Delete (only with more
                    // than one, as its ×). Copy the dates waits for our own calendar.
                    .contextMenu {
                        Section(n > 1 ? "Visit \(i + 1)" : "Visit") {
                            Button("Duplicate") { addTrip(copy: i) }
                            if n > 1 { Button("Delete", role: .destructive) { removeTrip(k) } }
                        }
                    }
                Spacer(minLength: 8)
                // the visit's days (our own calendar, under this row), else its time in words, else "Add"; a tap opens
                // or closes the calendar
                let days = VisitCalendar.range(s.d[keyPath: tk(i, \.from)], s.d[keyPath: tk(i, \.to)])
                let v = days ?? s.d[keyPath: rough] ?? ""
                let w = v.isEmpty ? "Add" : v
                HStack(spacing: 8) {
                    Text(gone ? Caption.blank(w, "\u{2002}") : w).font(.body)
                        .foregroundStyle(v.isEmpty ? Palette.ink.opacity(0.5) : Palette.ink)
                        .contentTransition(.identity)
                    if let n = VisitCalendar.days(s.d[keyPath: tk(i, \.from)], s.d[keyPath: tk(i, \.to)]), !gone {
                        Text(n).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }
                .lineLimit(2)
                .frame(minHeight: 44).edgeRow()
                .contentShape(Rectangle())
                .onTapGesture { guard !plain else { return }; Feel.tap(); typing = nil; toggleCal(i) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("When")
                .accessibilityValue(v.isEmpty ? "Not set" : v)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the calendar")
                if n > 1 {
                    xCircle("visit \(i + 1)") { removeTrip(k) }
                        .opacity(gone ? 0 : 1).transaction { $0.disablesAnimations = true; $0.animation = nil }
                        .transition(.identity)
                }
            }
            .frame(minHeight: 52).edgeRow()
            // THE CALENDAR OPENS AS A DRAWER: it stood whole at once over How long, How and Why while they slid down
            // under it. Now its own lasting holder grows to it and is cut to its height, so the month is uncovered
            // from the top as the rows below move; shutting, it slides up under the edge
            VStack(alignment: .leading, spacing: 0) {
                if calOpen == i, !plain {
                    VStack(alignment: .leading, spacing: 0) {
                        VisitCalendar(from: Binding(get: { s.d[keyPath: tk(i, \.from)] }, set: { s.d[keyPath: tk(i, \.from)] = $0 }),
                                      to: Binding(get: { s.d[keyPath: tk(i, \.to)] }, set: { s.d[keyPath: tk(i, \.to)] = $0 }))
                        HStack(spacing: 12) {
                            Text("In words").font(.body).foregroundStyle(Palette.ink).frame(minHeight: 44)
                            Spacer(minLength: 8)
                            // when the days aren't known: the time in words (40 characters); the empty field says only "Add"
                            field("Add", id: "rough\(i)", max: 40, trailing: true, rough)
                        }
                        .frame(minHeight: 52).edgeRow()
                        if s.d[keyPath: tk(i, \.from)] != nil {
                            row("Clear the days", blank: false) { EmptyView() }
                                .contentShape(Rectangle())
                                .onTapGesture { Feel.tap(); s.d[keyPath: tk(i, \.from)] = nil; s.d[keyPath: tk(i, \.to)] = nil }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.bottom, 8)
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .modifier(active: DrawerSlide(y: -24), identity: DrawerSlide(y: 0))))
                }
            }
            // the water's width always (empty, the holder had none, so its cut grew sideways too and the month came
            // in from the left, "N",, one column at a time): only its foot moves
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipShape(SideOpenRect())
            // how long: the days counted when they're known (on the When row), else picked in words
            if VisitCalendar.days(s.d[keyPath: tk(i, \.from)], s.d[keyPath: tk(i, \.to)]) == nil {
                row("How long", blank: gone) { longStepper(i, blank: gone) }
            }
            if !aThing {
            choice("How", Self.modes, chosen: s.d[keyPath: mode], blank: gone) { s.d[keyPath: mode] = $0 }
            drawer(s.d[keyPath: mode] == "other") {
                if plain { fieldWords("How", s.d[keyPath: tk(i, \.modeOther)], gone: gone) }
                else { field("How", id: "modeOther\(i)", max: 60, tk(i, \.modeOther)) }
            }
            choice("Why", Self.purposes, chosen: s.d[keyPath: purpose], blank: gone) { s.d[keyPath: purpose] = $0 }
            }
            if !aThing {
            drawer(s.d[keyPath: purpose] == "other") {
                if plain { fieldWords("Why", s.d[keyPath: tk(i, \.purposeOther)], gone: gone) }
                else { field("Why", id: "purposeOther\(i)", max: 60, tk(i, \.purposeOther)) }
            }
            }
        }
    }
    /// A PART THAT OPENS UNDER A ROW AS A DRAWER: a lasting holder the water's width, cut to its own height, so what
    /// comes in is uncovered from the top as the rows below move, and what goes slides up under the edge (inserted
    /// bare, it stood whole over the rows sliding down under it)
    private func drawer<V: View>(_ open: Bool, @ViewBuilder _ c: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if open {
                c().transition(.asymmetric(insertion: .identity,
                                           removal: .modifier(active: DrawerSlide(y: -16), identity: DrawerSlide(y: 0))))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipShape(SideOpenRect())
    }
    /// visit i's calendar opened or closed; opening it below full takes the water to full, as typing does (below
    /// full the rows don't scroll, and a month is taller than the room there)
    private func toggleCal(_ i: Int) {
        let opening = calOpen != i
        withAnimation(Motion.quick) { calOpen = opening ? i : nil }
        if opening, water.stop != .full { water.go(.full) }
    }
    /// Lived here tapped: Lived changes now (the band in one frame); the blocks swap in three steps of 0.26 s
    private func swapBlock() {
        typing = nil
        let was = shownLived ?? s.lived
        s.lived.toggle()
        swapJob += 1
        let job = swapJob
        shownLived = was
        withAnimation(.smooth(duration: 0.26)) { blockGone = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            guard job == swapJob else { return }
            withAnimation(Motion.quick) { shownLived = s.lived }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                guard job == swapJob else { return }
                withAnimation(.smooth(duration: 0.26)) { blockGone = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if job == swapJob { shownLived = nil }
                }
            }
        }
    }
    /// a text field drawn as plain words while its row rolls (a field can't): its value, or its placeholder
    private func fieldWords(_ empty: String, _ v: String?, gone: Bool, trailing: Bool = false) -> some View {
        let t = (v ?? "").isEmpty ? empty : v!
        return Text(gone ? Caption.blank(t, "\u{2002}") : t).font(.body)
            .foregroundStyle((v ?? "").isEmpty ? Palette.ink.opacity(0.5) : Palette.ink)
            .contentTransition(.identity)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: trailing ? .trailing : .leading).edgeRow()
    }

    /// A4.14: the space opens, then the visit's words roll in; Times goes up to the visits there are when it was lower
    /// `copy`: a visit to duplicate (its row's hold menu, 11.5): the new one takes its how, why and time in words
    private func addTrip(copy: Int? = nil) {
        Feel.tap()
        let k = UUID().uuidString
        let n = 1 + (s.d.trips?.count ?? 0)
        tripIDs = Self.synced(tripIDs, n)
        arriving.insert(k); rolling.insert(k)
        withAnimation(Motion.quick) {
            tripIDs.append(k)
            s.d.trips = (s.d.trips ?? []) + [copy.map { var t = s.d[trip: $0]; t.from = nil; t.to = nil; return t } ?? StampDetails.Trip()]
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
        // an open calendar closes: the visits after the removed one move up a place
        calOpen = nil
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

    /// one lasting part, never a swap: closed it was a row and open a header, swapped in one frame, so the × cut the
    /// whole part away. Now the words stay where they are (only their weight turns), the plus and the × change about
    /// their own middle, and the part under them opens and shuts as a drawer: its rows are there at once, shown as
    /// the part's edge moves down, and on the × they stay, sliding up under the edge as it closes
    @ViewBuilder private var livedSection: some View {
        let on = s.lived
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(out ? Caption.blank("Lived here", "\u{2002}") : "Lived here")
                    .font(.body.weight(on ? .semibold : .regular)).foregroundStyle(Palette.ink)
                    .contentTransition(out ? .identity : .interpolate)
                    .accessibilityAddTraits(on ? .isHeader : [])
                Spacer(minLength: 8)
                // one mark, not two swapped: the plus turns an eighth into the × while its black circle grows
                // under it from the middle, the plus white where the circle is (two marks swapped sat apart while
                // the row moved, the leaving one where the row had been)
                let disc = Circle().frame(width: 24, height: 24).scaleEffect(on ? 1 : 0.01)
                ZStack {
                    disc.foregroundStyle(Palette.ink)
                    Icon5Still(key: "plus", progress: 0, ink: Palette.ink, size: 17)
                    Icon5Still(key: "plus", progress: 0, ink: Palette.white, size: 17).mask(disc)
                }
                .scaleEffect(on ? 13 / 17 * 1.25 : 1)
                .rotationEffect(.degrees(on ? 45 : 0))
                .frame(width: 44, height: 44)
                .opacity(out ? 0 : 1)
                // (the ×'s middle under the plus of Add a visit above: the 44 pt touch reaches 8 pt past)
                .padding(.trailing, -8)
            }
            .frame(minHeight: on ? 44 : 52).edgeRow()
            .contentShape(Rectangle())
            .onTapGesture {
                if s.lived { Feel.lift(); typing = nil } else { Feel.notch() }
                withAnimation(Motion.quick) { s.lived.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(on ? "Closes Lived here" : "Opens Lived here")
            if on {
                livedBlock
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .modifier(active: DrawerSlide(y: -16), identity: DrawerSlide(y: 0))))
            }
        }
        .clipShape(SideOpenRect())
    }

    private var livedBlock: some View {
        let t = livedTimes.enumerated().map { (Self.key(livedIDs, $0.offset, "lived"), $0.element) }
        let now = s.d.livesNow == true
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(t.enumerated()), id: \.element.0) { i, row in
                let stay = row.1
                let k = row.0
                let last = i == t.count - 1
                let gone = out || arriving.contains(k) || leaving.contains(k)
                let plain = out || shownLived != nil || rolling.contains(k)
                HStack(spacing: 12) {
                    if plain {
                        monthWords(stay.from, empty: "Moved in", gone: gone)
                    } else {
                        MonthField(empty: "Moved in", value: stay.from, focus: $typing, id: "in\(i)") { v in
                            var x = livedTimes; guard i < x.count else { return }; x[i].from = v; setLived(x)
                        }
                    }
                    if now && last {
                        Text(gone ? Caption.blank("Now", "\u{2002}") : "Now").font(.body).foregroundStyle(Palette.ink)
                            .contentTransition(.identity)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).edgeRow()
                    } else if plain {
                        monthWords(stay.to, empty: "Moved out", gone: gone)
                    } else {
                        MonthField(empty: "Moved out", value: stay.to, focus: $typing, id: "out\(i)") { v in
                            var x = livedTimes; guard i < x.count else { return }; x[i].to = v; setLived(x)
                        }
                    }
                    if let len = Self.length(stay.from, now && last ? nil : stay.to, toNow: now && last) {
                        Text(gone ? Caption.blank(len, "\u{2002}") : len).font(.body).foregroundStyle(Palette.ink).fixedSize()
                            .contentTransition(.identity)
                    }
                    if t.count > 1 {
                        xCircle("lived time \(i + 1)") { removeLived(i) }
                            .opacity(gone ? 0 : 1).transaction { $0.disablesAnimations = true; $0.animation = nil }
                            // the first row's × comes and goes with the second row: about its own centre, never a fade
                            .transition(.identity)
                    }
                }
            }
            band("I still live here", on: now, blank: out) {
                Feel.tap()
                s.d.livesNow = now ? nil : true
                if !now { var x = livedTimes; x[x.count - 1].to = ""; setLived(x) }
            }
            if !now {
                row("Add time", blank: out) { EmptyView() }
                    .contentShape(Rectangle())
                    .onTapGesture { addLived() }
                    .accessibilityAddTraits(.isButton)
            }
            // (here is Family, not the trip's)
            choiceWords("Why", Self.whys.map { ($0, $0 == "family" ? "Family" : Self.word($0)) }, chosen: s.d.livedWhy,
                        blank: out) {
                s.d.livedWhy = $0
            }
            drawer(s.d.livedWhy == "other") {
                if out || shownLived != nil { fieldWords("Why", s.d.livedWhyOther, gone: out) }
                else { field("Why", id: "whyOther", max: 60, \.livedWhyOther) }
            }
        }
    }

    /// REGIONS YOU WENT TO (the web's): the country's first level of regions as choices, one tap stamping or
    /// unstamping it as the Regions map does (its parents too), so the chips and the map always agree
    struct RegionChoice: Sendable {
 let id: String; let name: String; let parent: String? }
    @State private var regionUnits: [RegionChoice] = []
    /// the test driver's: a row brought to the top
    @State private var scrollAsk: String?
    @State private var regionLevel: (row: Int, name: String)?
    @State private var regionCC: String?
    private var regionsBlock: some View {
        let on = Set(regionUnits.map(\.id).filter { marks.state(PlaceKey(.region, $0)).stamped })
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(out ? Caption.blank(regionLevel?.name ?? "", "\u{2002}") : regionLevel?.name ?? "")
                    .font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    .contentTransition(.identity)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                let n = "\(on.count) of \(regionUnits.count)"
                Text(out ? Caption.blank(n, "\u{2002}") : n).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                    .contentTransition(.numericText(value: Double(on.count)))
            }
            .frame(minHeight: 32, alignment: .bottom).edgeRow()
            .id("regions")
            chips(regionUnits.map { ($0.id, $0.name) }, chosen: nil, on: on, blank: out) { toggleRegion($0) }
                .padding(.top, 4)
        }
    }
    private func toggleRegion(_ id: String) {
        guard let u = regionUnits.first(where: { $0.id == id }), let lv = regionLevel, let cc = regionCC,
              cc == s.key?.id.lowercased() else { return }
        Task {
            if marks.state(PlaceKey(.region, id)).stamped {
                await RegionStamps.unstamp(id: u.id, name: u.name, parent: u.parent, cc: cc, row: lv.row)
            } else {
                await RegionStamps.stamp(id: u.id, name: u.name, parent: u.parent, cc: cc, row: lv.row, source: .hand)
            }
        }
    }
    /// the country's bundled first level, read off the main thread (the biggest is 1 MB), names in order
    private func loadRegions() async {
        guard let k = s.key, k.kind == .country, !s.wish else { regionUnits = []; regionLevel = nil; regionCC = nil; return }
        let cc = k.id.lowercased()
        if let e = DetailsRegions.cache[cc] { applyRegions(e, cc); return }
        regionUnits = []; regionLevel = nil; regionCC = nil
        let e = await DetailsRegions.read(cc)
        // (another place opened while this one was read: its own read decides)
        guard !Task.isCancelled, s.key == k, let e else { return }
        applyRegions(e, cc)
    }
    /// what was read, kept read (one region is the country itself: nothing to choose)
    private func applyRegions(_ e: DetailsRegions.Entry, _ cc: String) {
        regionUnits = e.units.count > 1 ? e.units : []
        regionLevel = (e.row, e.name)
        regionCC = cc
    }

    /// PHOTOS (4.4.3): the plus circle (44 pt, solid black, white plus) opens Apple's picker (no permission asked);
    /// each photo a 72 pt postage stamp after it; hold one for Remove. (The camera, and in the hold menu, are not
    /// built yet.)
    @State private var photoPicking = false
    @State private var picked: [PhotosPickerItem] = []
    private var photosBlock: some View {
        section("Photos", blank: out) {
            FlowLayout(spacing: 8) {
                Button { Feel.tap(); typing = nil; photoPicking = true } label: {
                    Icon5Still(key: "plus", progress: 0, ink: Palette.white, size: 17)
                        .frame(width: 44, height: 44).background(Palette.ink, in: .circle)
                        .opacity(out ? 0 : 1).transaction { $0.disablesAnimations = true; $0.animation = nil }
                        // its left edge under the group's name, its middle on the tiles' middle
                        .frame(width: 44, height: 72)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photos")
                ForEach(Array((s.d.photos ?? []).enumerated()), id: \.element.file) { i, ph in
                    PhotoStampTile(file: ph.file)
                        .opacity(out ? 0 : 1)
                        .contextMenu {
                            Button("Remove", role: .destructive) { removePhoto(ph.file) }
                        }
                        .accessibilityLabel("Photo \(i + 1)")
                        // (a photo added comes in from 93%, never from a point, 25 Nov)
                        .transition(detailsPhotoIn)
                }
            }
            .padding(.vertical, 4)
            .edgeRow()
        }
        .id("photos")
        .photosPicker(isPresented: $photoPicking, selection: $picked, maxSelectionCount: 20, matching: .images,
                      photoLibrary: .shared())
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            // the place they were picked for: Details closed or opened on another place meanwhile, they are not added
            // (to the wrong place, or to a record already written)
            let forKey = s.key
            Task {
                var add: [StampDetails.Photo] = []
                for it in items {
                    guard let d = try? await it.loadTransferable(type: Data.self) else { continue }
                    // (decoded, shrunk and written off the main thread: twenty photos made the sheet stutter)
                    if let f = await Task.detached(priority: .userInitiated, operation: { DetailPhotos.keep(d) }).value {
                        add.append(StampDetails.Photo(file: f, asset: it.itemIdentifier))
                    }
                }
                picked = []
                guard s.key == forKey, s.key != nil else { return }
                guard !add.isEmpty else { Feel.refuse(); return }
                addPhotos(add)
            }
        }
    }
    private func addPhotos(_ add: [StampDetails.Photo]) {
        Feel.tap()
        withAnimation(Motion.quick) { s.d.photos = (s.d.photos ?? []) + add }
    }
    private func removePhoto(_ file: String) {
        Feel.lift()
        withAnimation(Motion.quick) {
            let rest = (s.d.photos ?? []).filter { $0.file != file }
            s.d.photos = rest.isEmpty ? nil : rest
        }
    }

    private var placesBlock: some View {
        section("Places", blank: out) {
            ForEach(Array((s.d.places ?? []).enumerated()).map { (Self.key(placeIDs, $0.offset, "place"), $0.element) }, id: \.0) { k, p in
                let gone = out || arriving.contains(k) || leaving.contains(k)
                HStack(spacing: 12) {
                    Text(gone ? Caption.blank(p.n, "\u{2002}") : p.n).font(.body).foregroundStyle(Palette.ink).lineLimit(2)
                        .contentTransition(.identity)
                    Spacer(minLength: 8)
                    let w = Self.word(p.k)
                    Text(gone ? Caption.blank(w, "\u{2002}") : w).font(.body).foregroundStyle(Palette.ink)
                        .contentTransition(.identity)
                    xCircle(p.n) { if let j = placeIDs.firstIndex(of: k) { removePlace(j) } }
                    .opacity(gone ? 0 : 1).transaction { $0.disablesAnimations = true; $0.animation = nil }
                }
                .frame(minHeight: 52).edgeRow()
            }
            HStack(spacing: 12) {
                if out { fieldWords("Add a place", placeName, gone: true) } else {
                TextField("", text: Binding(get: { placeName }, set: { v in
                    placeName = v
                }), prompt: Text("Add a place").foregroundStyle(Palette.ink.opacity(0.5)))
                .font(.body).foregroundStyle(Palette.ink)
                .focused($typing, equals: "place").id("place")
                .submitLabel(.done)
                .onAppear { if s.key?.kind == .country { TownIndex.shared.load() } }
                .onSubmit { addPlace() }
                if placeName.count > 60 {
                    Text("\(placeName.count)/60").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.red)
                }
                }
                // Add only once there is something to add (a name and its kind); no greyed-out button
                if canAdd {
                    Text("Add").font(.body.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36).background(Palette.ink, in: .capsule)
                        .frame(minHeight: 44).contentShape(Rectangle()).edgeRow()
                        .onTapGesture { addPlace() }
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(minHeight: 52).edgeRow()
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
        let went = StampDetails.Went(n: String(placeName.trimmingCharacters(in: .whitespaces).prefix(60)), k: k)
        withAnimation(Motion.quick) { placeIDs.append(id); s.d.places = (s.d.places ?? []) + [went] }
        arrive(id)
        placeName = ""
        kind = nil
        if k == "city", let c = s.key, c.kind == .country { stampTown(went.n, cc: c.id) }
    }
    /// A TOWN WRITTEN INTO A COUNTRY'S PLACES is a town you went to: stamped too, with its regions (as the town's own
    /// Stamp does), one shake taking it back; a name the towns don't know, or a town already stamped, is just the row
    private func stampTown(_ n: String, cc: String) {
        let ix = TownIndex.shared
        ix.load()
        let place = map?.world?.placeIndex[cc]
        Task {
            for _ in 0 ..< 40 where !ix.ready { try? await Task.sleep(for: .milliseconds(100)) }
            guard let h = ix.named(n, in: cc) else { return }
            let key = PlaceKey(.town, h.id)
            guard !MarkStore.shared.state(key).stamped else { return }
            Feel.stamp()
            await TownStamps.stamp(key, name: h.name, cc: cc, source: .hand, place: place,
                                   at: EqualEarth.project(lon: h.lon, lat: h.lat))
        }
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
            var x = livedTimes; x.remove(at: j)
            if s.d.livesNow == true, j == x.count, !x.isEmpty { x[x.count - 1].to = "" }
            setLived(x); livedIDs.remove(at: j)
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
    /// the test driver's hands on the rows (simulator checks): lived, addtime, removelived N, addplace <kind> <name>, removeplace N|last,
    /// places (logs the place rows)
    @MainActor static var test: (([String]) -> Void)?
    private func driver(_ p: [String]) {
        switch p.first {
        case "lived": swapBlock()
        case "addvisit": addTrip()
        // cal [i]: visit i's calendar opened or closed (its When value tapped); calday i yyyy-mm-dd: that day tapped on it;
        // calback / calnext: the month arrows
        case "cal": toggleCal(Int(p.count > 1 ? p[1] : "0") ?? 0)
        case "calday":
            if p.count > 2, let i = Int(p[1]), let d = LocalDay(p[2]) {
                let f = tk(i, \.from), t = tk(i, \.to)
                if let lo = s.d[keyPath: f].flatMap(LocalDay.init), s.d[keyPath: t] == nil {
                    if d < lo { s.d[keyPath: f] = d.description; s.d[keyPath: t] = lo.description } else { s.d[keyPath: t] = d.description }
                } else { s.d[keyPath: f] = d.description; s.d[keyPath: t] = nil }
            }
        // calclear i: visit i's dates taken away again (a test's own dates)
        case "calclear":
            if let i = Int(p.count > 1 ? p[1] : "0") { s.d[keyPath: tk(i, \.from)] = nil; s.d[keyPath: tk(i, \.to)] = nil }
        case "removevisit": tripIDs = Self.synced(tripIDs, 1 + (s.d.trips?.count ?? 0)); if let i = Int(p.count > 1 ? p[1] : "1"), i < tripIDs.count { removeTrip(tripIDs[i]) }
        // photo test: a made-up picture added as if picked (the picker can't be driven); photo remove N
        case "photo":
            if p.count > 1, p[1] == "remove", let i = Int(p.count > 2 ? p[2] : "0"), let all = s.d.photos, i < all.count { removePhoto(all[i].file) }
            else if p.count > 1, p[1] == "test" {
                let img = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).image { c in
                    UIColor(red: 0.35, green: 0.6, blue: 0.85, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
                    UIColor(red: 0.85, green: 0.9, blue: 0.4, alpha: 1).setFill(); c.cgContext.fillEllipse(in: CGRect(x: 300, y: 150, width: 300, height: 300))
                }
                if let d = img.jpegData(compressionQuality: 0.9), let f = DetailPhotos.keep(d) { addPhotos([StampDetails.Photo(file: f, asset: nil)]) }
            }
        // scroll <id>: that row to the top (regions, place, did, with)
        case "scroll": scrollAsk = p.count > 1 ? p[1] : nil
        // region <name>: that region's chip tapped
        case "region": if let u = regionUnits.first(where: { $0.name == p.dropFirst().joined(separator: " ") }) { toggleRegion(u.id) }
        case "addtime": addLived()
        case "removelived": removeLived(Int(p.count > 1 ? p[1] : "0") ?? 0)
        case "addplace": kind = p.count > 1 ? p[1] : "city"; placeName = p.dropFirst(2).joined(separator: " "); addPlace()
        case "removeplace": removePlace(p.count > 1 && p[1] == "last" ? (s.d.places?.count ?? 1) - 1 : Int(p.count > 1 ? p[1] : "0") ?? 0)
        case "places": NSLog("wya details places: %@", (s.d.places ?? []).map { "\($0.n) (\($0.k))" }.joined(separator: ", "))
        default: break
        }
    }

    private func removeRow(_ k: String, index: @escaping () -> Int?, drop: @escaping (Int) -> Void) {
        Feel.lift()
        rolling.insert(k)
        s.pendingDrops[k] = { if let j = index() { drop(j) } }
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.26)) { _ = leaving.insert(k) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                // (not if Details closed meanwhile and took it out already)
                if s.pendingDrops.removeValue(forKey: k) != nil, let j = index() { withAnimation(Motion.quick) { drop(j) } }
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
            .foregroundStyle(shown == nil ? Palette.ink.opacity(0.5) : Palette.ink)
            .contentTransition(.identity)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).edgeRow()
    }

    // MARK: the parts

    /// a section: its name (17 pt semibold, black), then its rows
    private func section<C: View>(_ name: String, blank: Bool = false, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(blank ? Caption.blank(name, "\u{2002}") : name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .contentTransition(.identity)
                .frame(minHeight: 32, alignment: .bottom).edgeRow()
                .accessibilityAddTraits(.isHeader)
            c()
        }
    }

    /// a row: its name on the left, its value on the right, 52 pt
    private func row<V: View>(_ name: String, blank: Bool = false, @ViewBuilder _ value: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(blank ? Caption.blank(name, "\u{2002}") : name).font(.body).foregroundStyle(Palette.ink)
                .contentTransition(.identity)
            Spacer(minLength: 8)
            value()
        }
        .frame(minHeight: 52).edgeRow()
    }

    /// a two-state row as Map settings' current choice: on = a black band the water's width with white words,
    /// appearing in one frame
    private func band(_ name: String, sub: String? = nil, on: Bool, blank: Bool = false, tap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(blank ? Caption.blank(name, "\u{2002}") : name)
                .contentTransition(.identity)
                .font(.body)
            // what it does, under it (the old app said what Lived here does)
            if let sub {
                Text(blank ? Caption.blank(sub, "\u{2002}") : sub).font(.subheadline)
                    .contentTransition(.identity)
                    .opacity(0.5)
            }
        }
            .foregroundStyle(on ? .white : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: sub == nil ? 52 : 60, alignment: .leading).edgeRow()
            .padding(.horizontal, 16)
            // on: a plain black band edge to edge, square-ended, as Map settings' current choice (no oval); it shrinks
            // about its centre while the band's block goes (and grows as it comes)
            .padding(.horizontal, -16)
            // edge to edge of the screen, no gap at the sides
            .screenWide(on && !blank ? Palette.ink : .clear)
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
                .contentTransition(.identity)
                .frame(minHeight: 44, alignment: .leading)
            chips(items, chosen: chosen, blank: blank) { id in withAnimation(Motion.quick) { set(chosen == id ? nil : id) } }
                .padding(.bottom, 8)
        }
        // the name and its choices are one row: the sheet's edge never stops under a name with its choices cut off
        // ("Trip" stood alone at the bottom of Details at 50%)
        .edgeRow()
    }
    /// 17 pt words, 36 pt capsules with 44 pt touch areas, 8 pt apart; the first word lines up with the names above
    /// `on`: more than one chosen (the regions)
    private func chips(_ items: [(String, String)], chosen: String?, on: Set<String> = [], blank: Bool = false,
                       tap: @escaping (String) -> Void) -> some View {
        // four or fewer: equal capsules across the water's width (nothing sized by its words; How's four left ~90 pt
        // bare at the right); where the words don't fit a quarter (the largest type), they wrap as before
        ViewThatFits(in: .horizontal) {
            if items.count <= 4 {
                HStack(spacing: 8) {
                    ForEach(items, id: \.0) { id, word in
                        chip(id, word, picked: chosen == id || on.contains(id), blank: blank, fill: true, tap: tap)
                    }
                }
            }
            FlowLayout(spacing: 4) {
                ForEach(items, id: \.0) { id, word in
                    chip(id, word, picked: chosen == id || on.contains(id), blank: blank, fill: false, tap: tap)
                }
            }
        }
        // (no pull to the left: with every choice a visible capsule, the capsules' edge lines up with the names above)
    }
    private func chip(_ id: String, _ word: String, picked: Bool, blank: Bool, fill: Bool, tap: @escaping (String) -> Void) -> some View {
        Text(blank ? Caption.blank(word, "\u{2002}") : word)
            .contentTransition(.identity)
            .font(.body)
            .lineLimit(fill ? 1 : nil)
            // (across: one line each, or the row is not taken; wrapping: a long name wraps inside its capsule, never
            // past the screen's edge)
            .fixedSize(horizontal: fill, vertical: true)
            .foregroundStyle(picked ? .white : Palette.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(minHeight: 36)
            // the black of the chosen one comes and goes in one frame, never a fade, but moves with its capsule
            // (the whole fill kept from animating stood still while its row moved)
            .animation(nil) { $0.background { Capsule().fill(picked ? Palette.ink : .clear).opacity(blank ? 0 : 1) } }
            // the others are clear glass capsules, so every choice reads as a control (F46, F54)
            .glassEffect(picked || blank ? .identity : .clear, in: .capsule)
            .padding(.vertical, 4)
            .edgeRow()
            .contentShape(Rectangle())
            .onTapGesture { Feel.tap(); tap(id) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// Times: an exact number from 1; drag on the number or its − / + circles (36 pt drawn, 44 pt touch, solid black,
    /// white glyphs); the number rolls; refuse at the floor
    @State private var dragFrom: Int?
    static let valueSlot: CGFloat = 72
    @State private var atFloor = false
    /// the visit's length in days: minus, the number, plus; minus at one day clears it (nothing picked)
    private func longStepper(_ i: Int, blank: Bool) -> some View {
        let k = tk(i, \.long)
        let n = Self.lengthDays(s.d[keyPath: k])
        return HStack(spacing: 4) {
            circle("minus", blank: blank, dim: n == nil) {
                guard let n else { Feel.refuse(); return }
                Feel.tap(); s.d[keyPath: k] = n > 1 ? String(n - 1) : nil
            }
            // (no length yet: at 50%, as the stepper it is, not "Add" between its circles)
            Text(blank ? Caption.blank("0 days", "\u{2002}") : n.map { $0 == 1 ? "1 day" : "\($0) days" } ?? "0 days")
                .font(.body.weight(n == nil ? .regular : .semibold))
                .foregroundStyle(Palette.ink.opacity(n == nil ? 0.5 : 1))
                .contentTransition(.numericText(value: Double(n ?? 0)))
                .animation(Motion.quick, value: n)
                // (one 72 pt slot for the value in both steppers, so Times' and How long's circles share their
                // columns: "1" and "0 days" put the minuses 28 pt apart, 25 Nov)
                .frame(minWidth: Self.valueSlot, minHeight: 44)
            circle("plus", blank: blank) { Feel.tap(); s.d[keyPath: k] = String((n ?? 0) + 1) }
        }
        .padding(.trailing, -4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("How long")
        .accessibilityValue(n.map { "\($0) days" } ?? "Not set")
        .accessibilityAdjustableAction { dir in
            if dir == .increment { s.d[keyPath: k] = String((n ?? 0) + 1) } else if let n { s.d[keyPath: k] = n > 1 ? String(n - 1) : nil }
        }
    }

    private var stepper: some View {
        HStack(spacing: 4) {
            // the floor is the number of visit rows
            circle("minus", blank: out, dim: s.times <= timesFloor) { if s.times > timesFloor { s.times -= 1; Feel.tap() } else { Feel.refuse() } }
            Text(out ? Caption.blank("\(s.times)", "\u{2002}") : "\(s.times)").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: out ? -1 : Double(s.times)))
                .animation(Motion.quick, value: s.times)
                .frame(minWidth: Self.valueSlot, minHeight: 44).edgeRow()
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
            circle("plus", blank: out) { s.times += 1; Feel.tap() }
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
    /// `dim`: it can do nothing now (the minus at the floor): 50%, as the zoom column's minus is at home
    private func circle(_ g: String, blank: Bool = false, dim: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            // the app's own icons only, never SF Symbols (0.8.7): "plus" and "minus" from Icons5
            Icon5Still(key: g, progress: 0, ink: Palette.white, size: 17)
                .frame(width: 36, height: 36)
                // its fill and its going away change in one frame, never a fade; only those: the whole circle without
                // animation also stopped it moving with its row, so when a calendar opened or shut above it the
                // circles stood at the row's new place over the month while the words glided there
                .animation(nil) { $0.background(Palette.ink.opacity(dim ? 0.5 : 1), in: .circle).opacity(blank ? 0 : 1) }
                .frame(width: 44, height: 44)
                // the whole 44 pt touches (only the drawn circle did)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    /// × on a row (only where there is more than one): solid black, white ×, 24 pt drawn, 44 pt touch `what`: what it
    /// takes away, as VoiceOver says it
    private func xCircle(_ what: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Icon5Still(key: "cross", progress: 0, ink: Palette.white, size: 13)
                .frame(width: 24, height: 24).background(Palette.ink, in: .circle)
                .frame(width: 44, height: 44)
                // the whole 44 pt touches (only the 24 pt circle did)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(what)")
    }

    /// 5 stars, a normal five-pointed star, 24 pt; yellow up to the rating, the rest clear glass; the same star again
    /// clears
    private var stars: some View {
        HStack(spacing: 0) {
            ForEach(1 ... 5, id: \.self) { n in
                RatingStar(on: n <= (s.d.stars ?? 0))
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
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
    /// past the limit the words go on, the count under them in red; what fits is kept when Details closes
    private func field(_ empty: String, id: String, max: Int, lines: Bool = false, trailing: Bool = false,
                       web: Bool = false, _ k: WritableKeyPath<StampDetails, String?>) -> some View {
        s.limits[k] = max
        let n = (s.d[keyPath: k] ?? "").count
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            TextField("", text: Binding(get: { s.d[keyPath: k] ?? "" }, set: { v in
                if v.count > max, (s.d[keyPath: k] ?? "").count <= max { Feel.refuse() }
                s.d[keyPath: k] = v.isEmpty ? nil : v
            }), prompt: Text(empty).foregroundStyle(Palette.ink.opacity(0.5)), axis: lines ? .vertical : .horizontal)
            .font(.body)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(trailing ? .trailing : .leading)
            .lineLimit(lines ? 1 ... 12 : 1 ... 1)
            .keyboardType(web ? .URL : .default)
            .textInputAutocapitalization(web ? .never : .sentences)
            .autocorrectionDisabled(web)
            .frame(minHeight: lines ? 52 : 44)
            if n > max {
                Text("\(n)/\(max)").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.red).padding(.bottom, 6)
            }
        }
        .edgeRow()
        .focused($typing, equals: id)
        .id(id)
    }

    /// between two (or to now)
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

/// MM / YYYY typed on the number pad; a bad month turns red (d94f3d) and only the year is kept ( or "YYYY")
struct MonthField: View {
    let empty: String
    let value: String
    var focus: FocusState<String?>.Binding
    let id: String
    let set: (String) -> Void
    @State private var digits = ""
    @State private var bad = false

    var body: some View {
        // (the empty words in the one soft ink, 50% black: the system's placeholder grey was paler than any we use)
        TextField("", text: Binding(get: { Self.show(digits) }, set: { v in
            let d = String(v.filter(\.isNumber).prefix(6))
            digits = d
            guard d.count == 6, let m = Int(d.prefix(2)) else { bad = false; if d.isEmpty { set("") }; return }
            let y = String(d.suffix(4))
            bad = !(1 ... 12).contains(m)
            set(bad ? y : "\(y)-\(d.prefix(2))")
            if bad { Feel.refuse() }
        }), prompt: Text(empty).foregroundStyle(Palette.ink.opacity(0.5)))
        .keyboardType(.numberPad)
        .font(.body)
        .foregroundStyle(bad ? Palette.red : Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).edgeRow()
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

/// A RATING STAR: a full star always, never an outline; clear Liquid Glass until it is picked, then yellow
struct RatingStar: View {
    var on: Bool
    var body: some View {
        ZStack {
            Color.clear.glassEffect(.clear, in: Star()).opacity(on ? 0 : 1)
            Star().fill(Palette.yellow).opacity(on ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: on)
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
    /// the gap between lines, the same as between things unless asked (wrapped lines sat touching, 25 Nov)
    var lineSpacing: CGFloat? = nil
    private var lineGap: CGFloat { lineSpacing ?? spacing }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { y += row + lineGap; x = 0; row = 0 }
            x += s.width + spacing; row = max(row, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(w, widest), height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX, x + s.width > b.maxX { y += row + lineGap; x = b.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

/// WHOLE ROWS ONLY (0.7: nothing sits cut off at rest), for content whose rows differ in height: each row reports its
/// frame; the gaps between them are where a list's visible height may end
struct EdgeRows: PreferenceKey {
    static let space = "edgeRows"
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
    /// the middle of every gap between rows (rows inside rows merge into one)
    static func cuts(_ rects: [CGRect]) -> [CGFloat] {
        let r = rects.filter { $0.height > 0 }.sorted { $0.minY < $1.minY }
        var spans: [(CGFloat, CGFloat)] = []
        for x in r {
            if let last = spans.last, x.minY < last.1 - 0.5 { spans[spans.count - 1].1 = max(last.1, x.maxY) }
            else { spans.append((x.minY, x.maxY)) }
        }
        var out: [CGFloat] = []
        for k in 1 ..< max(1, spans.count) { out.append((spans[k - 1].1 + spans[k].0) / 2) }
        if let end = spans.last?.1 { out.append(end + 8) }
        return out
    }
    /// the tallest visible height that fits the room and ends 8 pt past a gap (the 16 pt soft edge centred on it);
    /// the whole room when everything fits or nothing has been measured yet
    static func fit(_ room: CGFloat, cuts: [CGFloat]) -> CGFloat {
        guard let end = cuts.last, end + 8 > room else { return room }
        guard let c = cuts.last(where: { $0 + 8 <= room }), c > 60 else { return room }
        return c + 8
    }
}
extension View {
    /// a row whose frame a list keeps whole at rest (EdgeRows)
    func edgeRow() -> some View {
        background(GeometryReader { g in Color.clear.preference(key: EdgeRows.self, value: [g.frame(in: .named(EdgeRows.space))]) })
    }
}
/// a scroll stops where the visible height's end lands in a gap between rows
struct GapSnap: ScrollTargetBehavior {
    var cuts: [CGFloat]
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let H = context.containerSize.height
        let top = max(0, context.contentSize.height - H)
        let want = target.rect.minY + H - 8
        let ends = cuts + [context.contentSize.height + 8]
        guard let c = ends.min(by: { abs($0 - want) < abs($1 - want) }) else { return }
        target.rect.origin.y = min(max(0, c - H + 8), top)
    }
}


/// A COUNTRY'S FIRST-LEVEL REGIONS FOR DETAILS, read once and kept, begun as its card opens
@MainActor
enum DetailsRegions {
    struct Entry: Sendable { let units: [DetailsSheet.RegionChoice]; let row: Int; let name: String }
    static private(set) var cache: [String: Entry] = [:]
    private static var reading: [String: Task<Entry?, Never>] = [:]
    static func read(_ cc: String) async -> Entry? {
        if let e = cache[cc] { return e }
        if let t = reading[cc] { return await t.value }
        guard let first = RegionCatalog.shared.first(cc) else { return nil }
        let row = first.row, name = first.level.many
        let t = Task.detached(priority: .userInitiated) { () -> Entry? in
            guard let f = RegionCatalog.shared.file(cc, row: row) else { return nil }
            var seen = Set<String>(), out: [DetailsSheet.RegionChoice] = []
            for u in f.units where seen.insert(u.id).inserted { out.append(DetailsSheet.RegionChoice(id: u.id, name: u.name, parent: u.parent)) }
            return Entry(units: out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, row: row, name: name)
        }
        reading[cc] = t
        let e = await t.value
        reading[cc] = nil
        if let e { cache[cc] = e }
        return e
    }
    static func prefetch(_ cc: String) { Task { _ = await read(cc) } }
}

/// a drawer's rows leaving: kept while it shuts, sliding up under its edge
struct DrawerSlide: ViewModifier {
    var y: CGFloat
    func body(content: Content) -> some View { content.offset(y: y) }
}

/// a photo added in Details comes in from 93% at its left, blurred in, never from a point (25 Nov)
@MainActor let detailsPhotoIn: AnyTransition = AnyTransition.scale(scale: 0.93, anchor: .leading).combined(with: AnyTransition(.blurReplace))

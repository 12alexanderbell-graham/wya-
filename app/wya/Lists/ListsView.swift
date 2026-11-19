import SwiftUI
import MapKit
import UniformTypeIdentifiers

/// THE LISTS TAB (the square): the living gradient, with its own top row: search on the left, the four kinds (Lists,
/// Plans, Tier lists, Books) as one square in the middle, turned like the Map's wheel, the plus on the right. Lists first: your wishlist always first (the map's own wishlist: what you wished there is
/// what is in it), then your lists, each a row (its first country's flag, its name, how many things are in it). A row
/// opens the list (its things, a note shown only when the row is opened); the plus makes a new list, its name typed at
/// once (a list left without a name is not kept).
@MainActor
@Observable
final class ListsState {
    static let shared = ListsState()
    /// 0 Lists, 1 Plans, 2 Tier lists, 3 Books: the kind the wheel is on, the one the shelf shows
    var kind = 0
    /// a test's hold on the wheel mid-turn (nil: let go)
    var testDial: CGFloat?
    /// the list open, by id ("wish" is the map's wishlist)
    var open: String?
    /// the open list's name being typed
    var naming = false
    var searching = false
    var query = ""
    /// the thing whose note is shown
    var noted: String?
    /// the plan the AI is making right now (PlanAI)
    var planning: String?
    /// a day of the plan being opened to show, hour by hour (the next trip's line during the trip: today)
    var showDay: Int?

    static let kinds = ["lists-lists", "lists-plans", "lists-tiers", "lists-books"]
    static let words = ["Lists", "Plans", "Tier lists", "Books"]

    /// a new list, its name typed at once
    func newList() {
        let l = MyList(name: "")
        ListsStore.shared.change { $0.lists.append(l) }
        open = l.id
        naming = true
    }
    /// a new plan: (no days yet set), its name typed at once
    func newPlan() {
        let pl = Plan(name: "", start: "", days: [PlanDay()])
        ListsStore.shared.change { $0.plans.append(pl) }
        open = pl.id
        naming = true
    }
    /// a new tier list: S to D, nothing ranked yet, its name typed at once
    func newTier() {
        let t = TierList.blank()
        ListsStore.shared.change { $0.tiers.append(t) }
        open = t.id
        naming = true
    }
    /// leaving a list: one left with no name and nothing in it is not kept
    func close() {
        if let id = open, let t = ListsStore.shared.book.tiers.first(where: { $0.id == id }),
           t.name.trimmingCharacters(in: .whitespaces).isEmpty, t.has.isEmpty {
            ListsStore.shared.change { $0.tiers.removeAll { $0.id == id } }
        }
        if let id = open, let pl = ListsStore.shared.book.plans.first(where: { $0.id == id }),
           pl.name.trimmingCharacters(in: .whitespaces).isEmpty, pl.count == 0, pl.start.isEmpty {
            ListsStore.shared.change { $0.plans.removeAll { $0.id == id } }
        }
        if let id = open, id != "wish",
           let l = ListsStore.shared.book.lists.first(where: { $0.id == id }),
           l.name.trimmingCharacters(in: .whitespaces).isEmpty, l.items.isEmpty {
            ListsStore.shared.change { $0.lists.removeAll { $0.id == id } }
        }
        open = nil
        naming = false
        noted = nil
    }
}

/// a row's thing: what it is called, its country (for the flag), what a tap shows
struct ListsThing: Identifiable {
    let id: String
    let name: String
    let cc: String?
    let note: String
}

struct ListsWater: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    @State private var s = ListsState.shared
    @State private var store = ListsStore.shared
    @State private var marks = MarkStore.shared
    @FocusState private var typing: Bool
    @FocusState private var naming: Bool
    /// a calendar file being picked for the open plan
    @State private var importingICS = false
    /// the thing whose sheet is up (PlanItemSheet)
    @State private var editingItem: PlanItemRef?
    /// the days open hour by hour
    @State private var hourDays: Set<String> = []
    /// what the last calendar file did
    @State private var icsWords: String?

    var body: some View {
        let L = water.layout
        let w = L.W - 2 * L.sheetInset - 32
        let top = max(form.top + 12, L.safeTop)
        // the next trip's line, under the square on the shelves (NextTripLine)
        let trip = s.open == nil && !s.searching ? NextTripLine.current() : nil
        let room = max(56, L.capsule.minY - 8 - (top + 56))
        ZStack(alignment: .topLeading) {
            // THE GROUND: the living gradient, the app's own (never the map: the Lists tab is not the map)
            LivingField()
                .frame(width: L.W, height: L.H)
                .allowsHitTesting(false)
            VStack(spacing: 8) {
                topRow(w)
                Group {
                    if let id = s.open { listPage(id, w: w) } else { rows(w) }
                }
                .contentMargins(.top, trip == nil ? 0 : 48, for: .scrollContent)
                .frame(width: w, height: room, alignment: .top)
            }
            .offset(x: L.sheetInset + 16, y: top)
            // THE NEXT TRIP'S LINE, OVER THE PAGE, out of the square (NextTripLine)
            if let (t, p) = trip {
                NextTripLine(trip: t, plan: p)
                    .frame(width: w, height: 40)
                    .offset(x: L.sheetInset + 16, y: top + 52)
            }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
    }

    // MARK: the top row

    private func topRow(_ w: CGFloat) -> some View {
        HStack(spacing: 0) {
            if s.open != nil {
                // a list open: its way back where search was, in the same glass circle as search
                circle("back") { Feel.tap(); withAnimation(Motion.quick) { s.close() } }
                .accessibilityLabel("Back")
                Spacer(minLength: 0)
            } else {
                circle("search") {
                    Feel.tap()
                    s.searching.toggle()
                    if !s.searching { s.query = "" }
                }
                .accessibilityLabel(s.searching ? "Close search" : "Search")
                Spacer(minLength: 8)
                if s.searching {
                    TextField("", text: $s.query, prompt: Text("Search").foregroundStyle(Palette.ink.opacity(0.5)))
                        .font(.body).foregroundStyle(Palette.ink)
                        .autocorrectionDisabled()
                        .focused($typing)
                        .submitLabel(.done)
                        .onAppear { typing = true }
                        .frame(height: 44)
                } else {
                    ListsWheel(s: s)
                }
                Spacer(minLength: 8)
                // the plus makes one of the kind the wheel is on (books' making comes with their page)
                circle("plus", dim: s.kind > 2) {
                    guard s.kind <= 2 else { Feel.refuse(); return }
                    Feel.tap()
                    withAnimation(Motion.quick) { [s.newList, s.newPlan, s.newTier][s.kind]() }
                }
                .accessibilityLabel(["New list", "New plan", "New tier list", "New book"][s.kind])
            }
        }
        .frame(width: w, height: 44)
        // (the wishlist's things and the towns named by the indexes, read once)
        .onAppear { ThingIndex.shared.load(); TownIndex.shared.load() }
    }

    private func circle(_ key: String, dim: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Icon5(key: key, ink: dim ? Palette.ink.opacity(0.5) : Palette.ink, size: 22)
                .frame(width: 44, height: 44)
                .glassEffect(PageGlass.head.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }

    // MARK: your lists

    /// the map's wishlist, as things: every place you wished, countries by the map's names
    private var wishThings: [ListsThing] {
        // (read so the rows are named again once the indexes have come)
        _ = ThingIndex.shared.ready; _ = TownIndex.shared.ready
        let w = map.world
        return marks.marks.filter(\.value.wished).keys.sorted { $0.description < $1.description }.map { k in
            switch k.kind {
            case .country:
                let n = w.flatMap { w in w.placeIndex[k.id].map { w.places[$0].n } } ?? k.id.uppercased()
                return ListsThing(id: k.description, name: n, cc: k.id, note: "")
            case .thing:
                // (a thing, else a collection's stop that is not among the things: a sea, a range, a circuit)
                let h = ThingIndex.shared.hit(k.id)
                let t = ThingStore.shared.thing(k.id)
                let c = CollectionStore.shared.item(k)
                return ListsThing(id: k.description, name: t?.thing.name ?? h?.name ?? c?.name ?? k.id,
                                  cc: t?.cc ?? h?.file ?? c.map { $0.cc.isEmpty ? nil : $0.cc } ?? nil, note: "")
            case .town:
                let h = TownIndex.shared.hit(k.id)
                return ListsThing(id: k.description, name: h?.name ?? k.id, cc: String(k.id.prefix { $0 != "/" }), note: "")
            default:
                return ListsThing(id: k.description, name: k.id, cc: nil, note: "")
            }
        }
        .sorted { $0.name < $1.name }
    }
    private func things(_ l: MyList) -> [ListsThing] {
        l.items.filter { $0.k != .section }.map { ListsThing(id: $0.id, name: $0.n, cc: $0.cc, note: $0.note) }
    }

    @ViewBuilder private func rows(_ w: CGFloat) -> some View {
        let q = s.query.trimmingCharacters(in: .whitespaces).lowercased()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                shelf(q)
            }
            .frame(width: w, alignment: .leading)
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
    }

    /// THE SHELF OF THE KIND THE WHEEL IS ON, each kind as what it is (never one card for all): Lists, the wishlist
    /// first and then the lists as tiles two across; Plans with their days; Tier lists with their tiers; Books. A kind
    /// with nothing in it says so, quietly, in the middle.
    @ViewBuilder private func shelf(_ q: String) -> some View {
        let match = { (n: String) in q.isEmpty || n.lowercased().contains(q) }
        switch s.kind {
        case 0:
            let lists = store.book.lists.filter { l in
                !l.arch && !l.hid && (match(l.name) || (!q.isEmpty && (l.wish ? wishThings.map(\.name) : things(l).map(\.name)).contains { match($0) }))
            }
            if !q.isEmpty, lists.isEmpty { noResults }
            // ONE TILE FOR EVERY LIST, the wishlist first among them: two across, each its square map cover, its name
            // and how many under it, never on it
            let ordered = lists.filter(\.wish) + lists.filter { !$0.wish }
            if !ordered.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 20) {
                    ForEach(ordered) { l in l.wish ? AnyView(wishTile(l)) : AnyView(listTile(l)) }
                }
                .padding(.top, 4)
            }
        case 1:
            let plans = store.book.plans.filter { !$0.arch && !$0.hid && match($0.name) }
            if plans.isEmpty { if q.isEmpty { none("No plans yet") } else { noResults } }
            ForEach(plans) { p in
                row(nil, p.name.isEmpty ? "New plan" : p.name, Self.when(p), dim: p.name.isEmpty) {
                    Feel.tap(); withAnimation(Motion.quick) { s.open = p.id }
                }
            }
        case 2:
            let tiers = store.book.tiers.filter { !$0.arch && !$0.hid && match($0.name) }
            if tiers.isEmpty { if q.isEmpty { none("No tier lists yet") } else { noResults } }
            ForEach(tiers) { t in
                row(nil, t.name.isEmpty ? "New tier list" : t.name, t.count == 0 ? "" : "\(t.count) ranked", dim: t.name.isEmpty,
                    mark: nil) {
                    Feel.tap(); withAnimation(Motion.quick) { s.open = t.id }
                }
            }
        default:
            let books = store.book.books.filter { match($0.name) }
            if books.isEmpty { if q.isEmpty { none("No books yet") } else { noResults } }
            ForEach(books) { b in row(nil, b.name, "") { Feel.refuse() } }
        }
    }
    /// a search that found nothing says so, as the map's search does
    private var noResults: some View {
        Text("No results").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 120)
    }
    /// a kind with nothing in it: its words, quiet, in the middle of the shelf (: no words (R01): an empty kind is
    /// simply empty, its "+" is how to start)
    private func none(_ t: String) -> some View {
        Color.clear.frame(maxWidth: .infinity, minHeight: 240).accessibilityLabel(t)
    }

    /// A LIST ON THE SHELF: a tile, its cover (until covers come: the flags of its first four countries, side by side;
    /// none, the glass), its name at the bottom left and how many things at the right
    private func listTile(_ l: MyList) -> some View {
        tile(l.id, name: l.name.isEmpty ? "New list" : l.name, dim: l.name.isEmpty, count: things(l).count,
             ccs: Array(l.countries.prefix(4)))
    }
    /// THE WISHLIST (LS01): a tile the shelf's full width, first, its cover made from the places you wished
    private func wishTile(_ l: MyList) -> some View {
        let ccs = Array(NSOrderedSet(array: wishThings.compactMap(\.cc)).array.compactMap { $0 as? String }.prefix(4))
        return tile(l.id, name: l.name, dim: false, count: wishThings.count, ccs: ccs)
    }
    /// A LIST'S TILE: its cover a square, Apple's own map of where its places are; a list with no places yet, plain
    /// glass. Its name under it, one line, and how many things in 50%, as Apple's albums.
    private func tile(_ id: String, name: String, dim: Bool, count n: Int, ccs: [String]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { ListCover(ccs: ccs, world: map.world) }
                .clipShape(shape)
                // (glass only for a list with no places yet: over the map it washed Apple's colours out)
                .glassEffect(ccs.isEmpty ? PageGlass.on : .clear, in: shape)
                .padding(.bottom, 6)
            Text(name).font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(dim ? 0.5 : 1)).lineLimit(1)
            Text(n == 0 ? "Nothing yet" : "\(n) \(n == 1 ? "place" : "places")").font(.subheadline)
                .foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { Feel.tap(); withAnimation(Motion.quick) { s.open = id } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + (n > 0 ? ", \(n) \(n == 1 ? "place" : "places")" : ""))
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ cc: String?, _ name: String, _ sub: String, dim: Bool = false, mark: AnyView? = nil, _ tap: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            if mark != nil || cc != nil {
                Group {
                    if let mark { mark }
                    else if let cc, let f = Flags.row(cc.lowercased()) { f.resizable().interpolation(.high).frame(width: 28, height: 21) } else { Color.clear }
                }
                .frame(width: mark == nil ? 28 : 46, height: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink.opacity(dim ? 0.5 : 1)).lineLimit(2)
                if !sub.isEmpty {
                    Text(sub).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: one list

    @ViewBuilder private func listPage(_ id: String, w: CGFloat) -> some View {
        if let pl = store.book.plans.first(where: { $0.id == id }) {
            planPage(pl, w: w)
        } else if let t = store.book.tiers.first(where: { $0.id == id }) {
            TierPage(t: t, w: w, naming: $naming)
        } else if id == "wish" {
            page(title: "Wishlist", editable: false, things: wishThings, note: "", w: w)
        } else if let l = store.book.lists.first(where: { $0.id == id }) {
            page(title: l.name, editable: true, things: things(l), note: l.note, w: w)
        }
    }

    /// A LIST (LS03): its cover at the top, wide, square corners, the list's name large on it at the bottom left (a
    /// list of no countries yet: the name alone, no cover); then its things, each its square flag at 44, its name.
    /// A note shows when its row is tapped. Taking a thing out is in the row's hold menu, never a button on every row.
    private func page(title: String, editable: Bool, things: [ListsThing], note: String, w: CGFloat) -> some View {
        let ccs = Array(NSOrderedSet(array: things.compactMap(\.cc)).array.compactMap { $0 as? String }.prefix(4))
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if editable, s.naming || title.isEmpty {
                        TextField("", text: Binding(get: { store.book.lists.first { $0.id == s.open }?.name ?? "" }, set: { v in
                            let n = String(v.prefix(60))
                            ListsStore.shared.change { b in if let i = b.lists.firstIndex(where: { $0.id == s.open }) { b.lists[i].name = n } }
                        }), prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                        .font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                        .focused($naming)
                        .submitLabel(.done)
                        .onSubmit { s.naming = false }
                        .onAppear { naming = true }
                        .onChange(of: naming) { _, f in if !f { s.naming = false } }
                    } else {
                        Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .onTapGesture { if editable { Feel.tap(); s.naming = true } }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .bottomLeading)
                .padding(.top, ccs.isEmpty ? 0 : 192)
                .background(alignment: .top) {
                    if !ccs.isEmpty {
                        ListCover(ccs: ccs, world: map.world)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(.bottom, 8)
                ForEach(things) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Group {
                                if let cc = t.cc, let f = Flags.row(cc.lowercased()) { f.resizable().interpolation(.high) } else { Color.clear }
                            }
                            .frame(width: 44, height: 33)
                            .frame(width: 44, height: 44)
                            Text(t.name).font(.body).foregroundStyle(Palette.ink).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        // a note: not shown until its row is opened
                        if s.noted == t.id, !t.note.isEmpty {
                            Text(t.note).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                                .padding(.leading, 56)
                        }
                    }
                    .frame(minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !t.note.isEmpty else { return }
                        Feel.tap()
                        withAnimation(Motion.quick) { s.noted = s.noted == t.id ? nil : t.id }
                    }
                    // out of the list (yours only: the wishlist is the map's own, changed on the map)
                    .contextMenu {
                        if editable {
                            Button("Take out", role: .destructive) {
                                withAnimation(Motion.quick) {
                                    ListsStore.shared.change { b in
                                        if let i = b.lists.firstIndex(where: { $0.id == s.open }) { b.lists[i].items.removeAll { $0.id == t.id } }
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                // Suggestions for one of your own lists (AI on; PlanIdeas)
                if editable, MapSettingsStore.shared.value.ai, !things.isEmpty, let id = s.open {
                    ListSuggestions(listID: id, name: title, things: things)
                }
            }
            .frame(width: w, alignment: .leading)
            .padding(.bottom, 16)
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
    }

    // MARK: one plan

    /// a plan's dates as you'd say them:, or
    static func when(_ p: Plan) -> String {
        p.start.isEmpty ? "Someday" : WhenWords.exact(from: p.start, to: p.end) ?? ""
    }
    private func changePlan(_ id: String, _ f: (inout Plan) -> Void) {
        ListsStore.shared.change { b in if let i = b.plans.firstIndex(where: { $0.id == id }) { f(&b.plans[i]) } }
    }
    /// a day's name: its date, or its number while the plan has no dates
    private func dayName(_ p: Plan, _ i: Int) -> String {
        guard !p.start.isEmpty, let d = PlanDates.date(PlanDates.key(p.start, i)) else { return "Day \(i + 1)" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    private func planPage(_ p: Plan, w: CGFloat) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if s.naming || p.name.isEmpty {
                    TextField("", text: Binding(get: { p.name }, set: { v in changePlan(p.id) { $0.name = String(v.prefix(60)) } }),
                              prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    .focused($naming)
                    .submitLabel(.done)
                    .onSubmit { s.naming = false }
                    .onAppear { naming = true }
                    .onChange(of: naming) { _, f in if !f { s.naming = false } }
                    .frame(minHeight: 44)
                } else {
                    Text(p.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .onTapGesture { Feel.tap(); s.naming = true }
                }
                // its first and last day (none yet: someday)
                HStack(spacing: 12) {
                    dateBox(p.start, label: "First day") { v in var e = false; changePlan(p.id) { $0.pickFirst(v, endFirst: &e) } }
                    dateBox(p.end, label: "Last day") { v in var e = false; changePlan(p.id) { _ = $0.pickLast(v, endFirst: &e, force: true) } }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                // ITS CALENDAR: a dated plan goes out as a calendar file (Apple's Calendar and Google Calendar both
                // take it); a calendar file comes in as things on the plan's days (an undated plan takes the file's
                // days)
                HStack(spacing: 12) {
                    if !p.start.isEmpty, p.count > 0, let url = Self.icsFile(p) {
                        ShareLink(item: url) {
                            Text("Add to Calendar").font(.body).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 16).frame(height: 44)
                                .glassEffect(PageGlass.control, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { Feel.tap(); importingICS = true } label: {
                        Text("Import").font(.body).foregroundStyle(Palette.ink)
                            .padding(.horizontal, 16).frame(height: 44)
                            .glassEffect(PageGlass.control, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds a calendar file's events to this plan")
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                if let w = icsWords {
                    Text(w).font(.body).foregroundStyle(Palette.ink.opacity(0.5)).frame(minHeight: 28)
                }
                // A DATED PLAN AS ITS CALENDAR: a plan day tapped opens it hour by hour (and the page goes to it); a day
                // just outside makes the plan reach to it
                if !p.start.isEmpty, !p.end.isEmpty {
                    PlanMonths(plan: p, open: { i in
                        withAnimation(Motion.chrome) { hourDays.insert("\(p.id)|\(i)") }
                        withAnimation(Motion.chrome) { reader.scrollTo("\(p.id)|day\(i)", anchor: .top) }
                    }, reach: { k in
                        withAnimation(Motion.chrome) { changePlan(p.id) { $0.reach(k) } }
                    })
                }
                // the AI making it: its needle turning
                if s.planning == p.id {
                    HStack(spacing: 12) {
                        TimelineView(.animation) { tl in
                            ZStack {
                                NeedleHalf(black: false).fill(Palette.white)
                                NeedleHalf(black: true).fill(Palette.ink)
                            }
                            .frame(width: 30, height: 30)
                            .background(Palette.lime, in: .circle)
                            .rotationEffect(.degrees(tl.date.timeIntervalSinceReferenceDate * 300))
                        }
                        Text("Planning").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                    }
                    .frame(minHeight: 52)
                    .accessibilityElement(children: .combine)
                }
                ForEach(Array(p.days.enumerated()), id: \.offset) { i, d in
                    // (a time column only on a day with a time in it)
                    let timed = d.items.contains { $0.at != nil }
                    let hourly = hourDays.contains("\(p.id)|\(i)")
                    // the day's name: a tap opens the day hour by hour, again closes it
                    Text(dayName(p, i)).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        .padding(.top, 20).padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("\(p.id)|day\(i)")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Feel.tap()
                            withAnimation(Motion.chrome) {
                                let k = "\(p.id)|\(i)"
                                if hourDays.contains(k) { hourDays.remove(k) } else { hourDays.insert(k) }
                            }
                        }
                        .accessibilityHint(hourly ? "Shows the day as a list" : "Shows the day hour by hour")
                    if hourly {
                        // (the things with no time stay above the hours, as a list)
                        ForEach(d.items.filter { $0.at == nil }) { it in
                            Text(it.what).font(.body).foregroundStyle(Palette.ink).frame(minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { Feel.tap(); editingItem = PlanItemRef(plan: p.id, day: i, item: it.id) }
                        }
                        PlanDayHours(items: d.items, ai: p.ai,
                                     open: { it in editingItem = PlanItemRef(plan: p.id, day: i, item: it.id) },
                                     add: { m in
                                         let item = PlanItem(at: String(format: "%02d:%02d", m / 60, m % 60), what: "", place: "")
                                         changePlan(p.id) { $0.days[i].items.append(item); $0.sortDay(i) }
                                         editingItem = PlanItemRef(plan: p.id, day: i, item: item.id)
                                     })
                    }
                    ForEach(hourly ? [] : d.items) { it in
                        HStack(spacing: 12) {
                            // its colour, a short bar at its start
                            if !it.c.isEmpty {
                                Capsule().fill(PlanItemSheet.colour(it.c)).frame(width: 4, height: 24)
                            }
                            if timed {
                                // (a thing with no time on a day with times says so, as Apple's calendar does, never a gap)
                                Text(it.at ?? "All day").font(it.at == nil ? .subheadline : .body.monospacedDigit())
                                    .foregroundStyle(Palette.ink.opacity(0.5))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(width: 58, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(it.what).font(.body).foregroundStyle(Palette.ink).lineLimit(2)
                                // its place, at 50%: a tap opens it on the Map (PlanPlaces)
                                if !it.place.isEmpty, it.place.lowercased() != it.what.lowercased() {
                                    Text(it.place).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                                        .contentShape(Rectangle())
                                        .onTapGesture { PlanPlaces.open(it.place, cc: it.cc) }
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityHint("Opens it on the map")
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                Feel.lift()
                                withAnimation(Motion.quick) { changePlan(p.id) { $0.days[i].items.removeAll { $0.id == it.id } } }
                            } label: {
                                Icon5Still(key: "cross", progress: 0, ink: Palette.white, size: 13)
                                    .frame(width: 24, height: 24).background(Palette.ink, in: .circle)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Take out")
                        }
                        .frame(minHeight: 44)
                        // a tap on the thing opens its sheet (all day or a time, where, link, note, colour)
                        .contentShape(Rectangle())
                        .onTapGesture { Feel.tap(); editingItem = PlanItemRef(plan: p.id, day: i, item: it.id) }
                        // MADE BY THE AI, NOT KEPT YET: each thing on lime glass until Keep
                        .padding(.leading, p.ai ? 14 : 0)
                        .glassEffect(p.ai ? .regular.tint(Palette.lime.opacity(0.55)) : .identity,
                                     in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.vertical, p.ai ? 3 : 0)
                    }
                    if !hourly { PlanAddRow(day: i) { at, what in
                        changePlan(p.id) { $0.days[i].items.append(PlanItem(at: at, what: what, place: "")); $0.sortDay(i) }
                    } }
                }
                // its Ideas (on no day yet) and Suggestions (PlanIdeas), once it is yours
                if !p.ai, s.planning != p.id, !p.name.isEmpty {
                    PlanIdeasSection(p: p, dayName: { dayName(p, $0) }, change: { f in changePlan(p.id, f) })
                }
                // MADE BY THE AI: why it is shaped this way, and Keep (only then is it among your plans)
                if p.ai, s.planning != p.id, !p.days.isEmpty || !p.note.isEmpty {
                    if !p.note.isEmpty {
                        Text(p.note).font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 24)
                    }
                    if !p.days.isEmpty {
                        Button {
                            Feel.notch()
                            withAnimation(Motion.chrome) { changePlan(p.id) { $0.ai = false } }
                        } label: {
                            Text("Keep").font(.body.weight(.semibold)).foregroundStyle(Palette.white)
                                .padding(.horizontal, 28).frame(height: 48)
                                .background(Palette.ink, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 20)
                        .accessibilityHint("Adds it to your plans")
                    }
                }
            }
            .frame(width: w, alignment: .leading)
            .padding(.bottom, 16)
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
        // opened on a day (the next trip's line, during the trip): that day hour by hour, scrolled to
        .task(id: p.id) {
            guard let i = s.showDay else { return }
            s.showDay = nil
            hourDays.insert("\(p.id)|\(i)")
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Motion.chrome) { reader.scrollTo("\(p.id)|day\(i)", anchor: .top) }
        }
        }
        .fileImporter(isPresented: $importingICS, allowedContentTypes: [.init(filenameExtension: "ics") ?? .data, .data]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url), let t = String(data: d, encoding: .utf8) else { icsWords = "That file couldn't be read."; return }
            let evs = PlanICS.read(t)
            var res = (added: 0, outside: 0)
            withAnimation(Motion.chrome) { changePlan(p.id) { res = $0.merge(evs) } }
            Feel.notch()
            icsWords = res.added == 0 && res.outside == 0 ? "No events in that file."
                : "\(res.added) added" + (res.outside > 0 ? ", \(res.outside) outside the plan's days" : "")
        }
        .onChange(of: p.id) { _, _ in icsWords = nil }
        // (a thing made by tapping an hour and left without words is not kept)
        .sheet(item: $editingItem, onDismiss: {
            changePlan(p.id) { pl in for k in pl.days.indices { pl.days[k].items.removeAll { $0.what.trimmingCharacters(in: .whitespaces).isEmpty } } }
        }) { r in
            PlanItemSheet(planID: r.plan, day: r.day, itemID: r.item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }

    /// the plan as a calendar file, written where the share sheet can hand it on
    static func icsFile(_ p: Plan) -> URL? {
        let name = p.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Plan" : p.name
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: " ")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safe).ics")
        guard (try? PlanICS.write(p, now: Date()).data(using: .utf8)?.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// a day picked on Apple's own calendar, its words the day, or the label at 50% when not set
    private func dateBox(_ v: String, label: String, set: @escaping (String) -> Void) -> some View {
        let shown = v.isEmpty ? Date() : PlanDates.date(v) ?? Date()
        return Text(v.isEmpty ? label : WhenWords.day(v)).font(.body)
            .foregroundStyle(v.isEmpty ? Palette.ink.opacity(0.5) : Palette.ink)
            .padding(.horizontal, 16).frame(height: 44)
            .glassEffect(PageGlass.control, in: .capsule)
            .overlay {
                DatePicker("", selection: Binding(get: { shown }, set: { d in Feel.tap(); set(PlanDates.key(local: d)) }), displayedComponents: .date)
                    .labelsHidden()
                    .colorMultiply(.clear)
                    .accessibilityLabel(label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(Capsule())
            }
            .fixedSize()
    }

}

extension ListsState {
    /// ADD TO LIST (the hold menus of a country, a town and a thing): your lists that don't hold the place yet; then
    /// New list, which makes one holding the place and opens it in the Lists tab with its name being typed; then each
    /// list that holds it (no ticks: a tick is only for approving)
    static func menu(name: String, cc: String?) -> UIMenu {
        let item = ListItem(n: name, cc: cc?.lowercased())
        let lists = ListsStore.shared.book.lists.filter { !$0.wish && !$0.arch && !$0.name.isEmpty }
        let holding = lists.filter { l in l.items.contains { $0.same(item) } }
        var children: [UIMenuElement] = lists.filter { l in !holding.contains { $0.id == l.id } }.map { l in
            UIAction(title: l.name) { _ in
                Feel.tap()
                ListsStore.shared.change { b in
                    guard let i = b.lists.firstIndex(where: { $0.id == l.id }) else { return }
                    b.lists[i].items.append(ListItem(n: name, cc: cc?.lowercased()))
                }
            }
        }
        children.append(UIAction(title: "New list") { _ in
            Feel.tap()
            var l = MyList(name: "")
            l.items = [item]
            ListsStore.shared.change { $0.lists.append(l) }
            let s = ListsState.shared
            s.kind = 0; s.open = l.id; s.naming = true
            NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: 1)
        })
        if !holding.isEmpty {
            children.append(UIMenu(options: .displayInline, children: holding.map { l in
                UIAction(title: "Take out of \(l.name)", attributes: .destructive) { _ in
                    Feel.lift()
                    ListsStore.shared.change { b in
                        guard let i = b.lists.firstIndex(where: { $0.id == l.id }) else { return }
                        b.lists[i].items.removeAll { $0.same(item) }
                    }
                }
            }))
        }
        return UIMenu(title: "Add to list", children: children)
    }
}

/// which thing's sheet is up
struct PlanItemRef: Identifiable, Hashable {
    let plan: String
    let day: Int
    let item: String
    var id: String { plan + "|" + item }
}

/// A DAY'S ADD ROW: what you'll do (and, written first, its time:), kept on Return
struct PlanAddRow: View {
    let day: Int
    let add: (String?, String) -> Void
    @State private var text = ""
    var body: some View {
        TextField("", text: $text, prompt: Text("Add").foregroundStyle(Palette.ink.opacity(0.5)))
            .font(.body).foregroundStyle(Palette.ink)
            .submitLabel(.done)
            .onSubmit {
                let t = text.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                // a time at its start  is the time
                var at: String?, what = t
                if let r = t.range(of: #"^\d{1,2}[:.]\d{2}\s+"#, options: .regularExpression) {
                    let raw = t[r].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ":")
                    at = raw.count == 4 ? "0" + raw : raw
                    what = String(t[r.upperBound...])
                }
                Feel.tap()
                add(at, what)
                text = ""
            }
            .frame(minHeight: 44)
    }
}


/// A TIER LIST: its name, then its tiers edge to edge (square ends, the tier's letter on its own full colour), then the
/// things not ranked yet, and a field to add more. A thing is dragged onto a tier or back under; its hold menu takes it
/// out of the tier list.
struct TierPage: View {
    let t: TierList
    let w: CGFloat
    var naming: FocusState<Bool>.Binding
    @State private var s = ListsState.shared
    @State private var adding = ""

    private func change(_ f: (inout TierList) -> Void) {
        ListsStore.shared.change { b in if let i = b.tiers.firstIndex(where: { $0.id == t.id }) { f(&b.tiers[i]) } }
    }
    private static func colour(_ n: String) -> Color {
        let v = Palette.named[n] ?? SIMD3(0.5, 0.5, 0.5)
        return Color(red: v.x, green: v.y, blue: v.z)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if s.naming || t.name.isEmpty {
                    TextField("", text: Binding(get: { t.name }, set: { v in change { $0.name = String(v.prefix(60)) } }),
                              prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    .focused(naming)
                    .submitLabel(.done)
                    .onSubmit { s.naming = false }
                    .onAppear { naming.wrappedValue = true }
                    .frame(minHeight: 44)
                } else {
                    Text(t.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .onTapGesture { Feel.tap(); s.naming = true }
                }
                VStack(spacing: 2) {
                    ForEach(Array(t.rows.enumerated()), id: \.offset) { i, r in
                        HStack(alignment: .top, spacing: 0) {
                            Text(r.t).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                                .frame(width: 52, height: 52)
                                .background(Self.colour(t.colour(i)))
                            ScrollView(.horizontal) {
                                HStack(spacing: 6) { ForEach(r.items, id: \.self) { chip($0) } }
                                    .padding(.horizontal, 6).frame(minHeight: 52)
                            }
                            .scrollIndicators(.hidden)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        }
                        .dropDestination(for: String.self) { names, _ in
                            guard let n = names.first else { return false }
                            Feel.tap()
                            withAnimation(Motion.quick) { change { _ = $0.move(n, to: .row(i)) } }
                            return true
                        }
                    }
                }
                .padding(.top, 8)
                // the things not ranked yet
                FlowRow(items: t.pool) { chip($0) }
                    .frame(minHeight: 52, alignment: .topLeading)
                    .padding(.top, 16)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { names, _ in
                        guard let n = names.first else { return false }
                        withAnimation(Motion.quick) { change { _ = $0.move(n, to: .pool) } }
                        return true
                    }
                TextField("", text: $adding, prompt: Text("Add").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.body).foregroundStyle(Palette.ink)
                    .submitLabel(.done)
                    .onSubmit {
                        let n = adding.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        Feel.tap()
                        change { $0.add([n]) }
                        adding = ""
                    }
                    .frame(minHeight: 44)
            }
            .frame(width: w, alignment: .leading)
            .padding(.bottom, 16)
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
        // (the tiers run past the page's margins to the water's edges)
        .scrollClipDisabled()
    }

    private func chip(_ n: String) -> some View {
        Text(n).font(.subheadline).foregroundStyle(Palette.ink).lineLimit(1)
            .padding(.horizontal, 10).frame(height: 36)
            .background(Palette.cream, in: .rect(cornerRadius: 6))
            .draggable(n)
            .contextMenu {
                Button("Take out", role: .destructive) { Feel.lift(); withAnimation(Motion.quick) { change { _ = $0.move(n, to: nil) } } }
            }
    }
}

/// things laid out in rows that wrap, left to right
struct FlowRow<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    var body: some View {
        FlowLayout(spacing: 6) { ForEach(items, id: \.self) { content($0) } }
    }
}

/// A PLAN'S DAYS on the shelf: a cell for each of its days (up to three weeks, seven across), filled where something is
/// planned that day; a plan of no days yet (someday) one empty week
struct PlanDays: View {
    let plan: Plan
    var body: some View {
        let days = Array(plan.days.prefix(21))
        let cols = 7, side: CGFloat = 5, gap: CGFloat = 1.5
        // (always at least a week, so a plan of no days or one day still reads as days and not as a speck)
        let shown = max(cols, days.count)
        let rows = max(1, Int(ceil(Double(shown) / Double(cols))))
        VStack(alignment: .leading, spacing: gap) {
            ForEach(0 ..< rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0 ..< cols, id: \.self) { c in
                        let i = r * cols + c
                        if i < shown {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(Palette.ink.opacity(i < days.count && !days[i].items.isEmpty ? 1 : 0.15))
                                .frame(width: side, height: side)
                        } else { Color.clear.frame(width: side, height: side) }
                    }
                }
            }
        }
        .frame(width: 46, height: 28, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// A TIER LIST on the shelf: its tiers' colours as thin bands, top tier first
struct TierStrip: View {
    let tiers: TierList
    var body: some View {
        VStack(spacing: 1.5) {
            ForEach(0 ..< min(tiers.rows.count, 6), id: \.self) { i in
                let v = Palette.named[tiers.colour(i)] ?? SIMD3(0.5, 0.5, 0.5)
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Color(red: v.x, green: v.y, blue: v.z))
            }
        }
        .frame(width: 46, height: 28)
        .accessibilityHidden(true)
    }
}

/// THE KINDS' WHEEL (the Map's mode wheel, the Lists tab's four kinds): one black square in the middle of the top row,
/// whichever kind you are on, as the Map's is one black circle. Turned, never tapped: while you turn it the kinds ride
/// the rim in their own shapes, the one coming to the top fills in as far as it has come, a tick at each kind it
/// passes, a click when it lands, the kind's name under it while you hold it.
struct ListsWheel: View {
    @Bindable var s: ListsState
    @State private var at: CGFloat = 0
    @State private var dragging = false
    @State private var startAt: CGFloat = 0
    @State private var lastTick = 0
    @State private var reveal: CGFloat = 0
    private let step: CGFloat = 35

    var body: some View {
        ZStack {
            WheelFace(at: at, reveal: reveal, ink: Palette.ink, keys: ListsState.kinds)
                .allowsHitTesting(false)
            let i = Int(at.rounded()).clamped(0, 3)
            let name = ListsState.words[i]
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 100 + 28)
                Text(dragging ? name : String(repeating: "\u{2002}", count: name.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize()
                    .contentTransition(.numericText(value: dragging ? Double(i + 1) : 0))
                    .animation(Motion.quick, value: dragging ? i + 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(width: 200, height: 200, alignment: .top)
            .allowsHitTesting(false)
        }
        .frame(width: 88, height: 44)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { g in turn(g.translation.width) }
                .onEnded { g in letGo(g.predictedEndTranslation.width - g.translation.width) }
        )
        .onAppear { at = CGFloat(s.kind); lastTick = s.kind }
        .onChange(of: s.kind) { _, k in
            if Int(at.rounded()) != k && !dragging {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { at = CGFloat(k) }
            }
        }
        .onChange(of: s.testDial) { _, v in
            withAnimation(Motion.chrome) {
                if let v { dragging = true; reveal = 1; at = v } else { dragging = false; reveal = 0; at = CGFloat(s.kind) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Kind")
        .accessibilityValue(ListsState.words[s.kind])
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: choose(min(3, s.kind + 1))
            case .decrement: choose(max(0, s.kind - 1))
            @unknown default: break
            }
        }
    }

    private func turn(_ dx: CGFloat) {
        if !dragging {
            withAnimation(Motion.quick) { dragging = true; reveal = 1 }
            startAt = at
        }
        var v = startAt - dx / step
        if v < 0 { v = -Flow.rubber(-v, 0.5) }
        if v > 3 { v = 3 + Flow.rubber(v - 3, 0.5) }
        at = v
        let i = Int(v.rounded()).clamped(0, 3)
        if i != lastTick { lastTick = i; Feel.tick() }
    }
    private func letGo(_ fling: CGFloat) {
        guard dragging else { return }
        let projected = at - fling / step * 0.3
        choose(Int(projected.rounded()).clamped(0, 3))
        withAnimation(Motion.quick) { dragging = false }
        withAnimation(Motion.chrome.delay(0.12)) { reveal = 0 }
    }
    private func choose(_ i: Int) {
        let changed = i != s.kind
        withAnimation(Motion.quick) { s.kind = i; s.query = "" }
        lastTick = i
        withAnimation(Motion.chrome) { at = CGFloat(i) }
        if changed { Feel.notch() }
    }
}

/// A LIST'S COVER until covers come: the flags of its first four countries side by side, each cropped to its share,
/// a soft white rising from the foot so words sit on it. It fills whatever it is given and never sets its own size.
struct ListCover: View {
    let ccs: [String]
    var world: World? = nil
    @State private var img: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { g in
            ZStack {
                if let img { Image(uiImage: img).resizable().scaledToFill() } else { Color.clear }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            .task(id: ccs.joined(separator: ",") + "|\(Int(g.size.width))x\(Int(g.size.height))") {
                img = ListMapCovers.cached(ccs, size: g.size)
                if img == nil { img = await ListMapCovers.image(ccs, world: world, size: g.size, scale: scale) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// THE LISTS' MAP COVERS: Apple's own map, its realistic land and its relief, framed on the countries a list holds,
/// made once a size and kept; no names, no places of interest, nothing drawn over it
@MainActor
enum ListMapCovers {
    private static var cache: [String: UIImage] = [:]
    private static func key(_ ccs: [String], _ size: CGSize) -> String { ccs.sorted().joined(separator: ",") + "|\(Int(size.width))x\(Int(size.height))" }
    static func cached(_ ccs: [String], size: CGSize) -> UIImage? { cache[key(ccs, size)] }

    static func image(_ ccs: [String], world: World?, size: CGSize, scale: CGFloat) async -> UIImage? {
        let k = key(ccs, size)
        if let c = cache[k] { return c }
        guard let world, !ccs.isEmpty, size.width > 4, size.height > 4 else { return nil }
        // the countries' frames, as Apple's map points (the frames are in our own map's units: Equal Earth)
        var rect = MKMapRect.null
        var mids: [CLLocationCoordinate2D] = []
        for cc in ccs {
            guard let i = world.placeIndex[cc.lowercased()] ?? world.placeIndex[cc], let f = world.frame(of: i) else { continue }
            let m = EqualEarth.unproject(SIMD2(Double(f.x + f.z) / 2, Double(f.y + f.w) / 2))
            mids.append(CLLocationCoordinate2D(latitude: max(-80, min(80, m.lat)), longitude: m.lon))
            for q in [SIMD2(f.x, f.y), SIMD2(f.z, f.w)] {
                let ll = EqualEarth.unproject(SIMD2(Double(q.x), Double(q.y)))
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: max(-80, min(80, ll.lat)), longitude: ll.lon))
                rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
            }
        }
        guard !rect.isNull else { return nil }
        // room round them, and the cover's own shape (never stretched)
        let aspect = size.width / size.height
        var w = max(rect.size.width, MKMapSize.world.width / 60) * 1.4, h = max(rect.size.height, MKMapSize.world.height / 60) * 1.4
        if w / h < aspect { w = h * aspect } else { h = w / aspect }
        w = min(w, MKMapSize.world.width); h = min(h, MKMapSize.world.height)
        let o = MKMapPoint(x: rect.midX - w / 2, y: max(0, rect.midY - h / 2))
        let opt = MKMapSnapshotter.Options()
        opt.mapRect = MKMapRect(origin: o, size: MKMapSize(width: w, height: h))
        opt.size = size
        opt.scale = scale
        let conf = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        conf.pointOfInterestFilter = .excludingAll
        conf.showsTraffic = false
        opt.preferredConfiguration = conf
        guard let snap = try? await MKMapSnapshotter(options: opt).start() else { return nil }
        // A DOT ON EACH OF ITS PLACES (black, a pale halo, as the journey's stops): what makes one list's map its own
        let out = UIGraphicsImageRenderer(size: snap.image.size, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = snap.image.scale; return f
        }()).image { ctx in
            snap.image.draw(at: .zero)
            let c = ctx.cgContext
            for m in mids {
                let p = snap.point(for: m)
                c.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
                c.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                c.setFillColor(UIColor(Palette.ink).cgColor)
                c.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            }
        }
        cache[k] = out
        return out
    }
}

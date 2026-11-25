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
    var kind = 0 { didSet { if kind != oldValue { kindForward = kind > oldValue } } }
    /// the wheel last turned on to a later kind (the shelf slides in from the right) or an earlier one (from the left)
    var kindForward = true
    /// a test's hold on the wheel mid-turn (nil: let go)
    var testDial: CGFloat?
    /// the list open, by id ("wish" is the map's wishlist)
    var open: String?
    /// the lists this one was opened from, inside one another (a list inside a list goes back to the list it is in)
    var parents: [String] = []
    /// open a list that sits inside the open one: back returns to this one
    func openInner(_ id: String) {
        if let o = open { parents.append(o) }
        open = id; noted = nil
    }
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
    /// a new book: no pages yet, its name typed at once (25 Nov)
    func newBook() {
        let b = PhotoBook(name: "")
        ListsStore.shared.change { $0.books.append(b) }
        open = b.id
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
        // (a book never named and with no pages is not kept)
        if let id = open, let bk = ListsStore.shared.book.books.first(where: { $0.id == id }),
           bk.name.trimmingCharacters(in: .whitespaces).isEmpty, bk.pages.isEmpty {
            ListsStore.shared.change { $0.books.removeAll { $0.id == id } }
        }
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
        // (back from a list opened inside another: to that one, not the shelf)
        open = parents.popLast()
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
    /// a list inside this list: the inner list's id (it sits like a country and opens as a list, any depth)
    var ref: String? = nil
}

struct ListsWater: View {
    let water: Water
    let map: MapController
    @Environment(\.displayScale) private var scale
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
    /// a row being swiped out (its id, how far), and the last thing taken out, for Undo
    @State private var swiping: (id: String, x: CGFloat)?
    @State private var removed: (list: String, item: ListItem, at: Int)?
    /// the list whose own sheet is up (name, cover, who can see it, archive, hide, delete)
    @State private var infoFor: String?
    /// the archive sheet is up (archived and hidden lists)
    @State private var archiveOpen = false

    var body: some View {
        let L = water.layout
        let w = L.W - 2 * L.sheetInset - 32
        let top = max(form.top + 12, L.safeTop)
        // the next trip's line, under the square on the shelves (NextTripLine)
        let trip = s.open == nil && !s.searching ? NextTripLine.current() : nil
        // (24 pt under the row of circles, as a place page's words start 24 under the head; it was 8, the shelf's tiles
        // and a list's map pressed up against the circles, 25 Nov)
        let gap: CGFloat = 24
        let room = max(56, L.capsule.minY - 8 - (top + 44 + gap))
        ZStack(alignment: .topLeading) {
            // THE GROUND: the living gradient, the app's own (never the map: the Lists tab is not the map)
            LivingField()
                .frame(width: L.W, height: L.H)
                .allowsHitTesting(false)
            VStack(spacing: gap) {
                topRow(w)
                // A LIST OPENS AS A PAGE PUSHED IN: the list comes in from the right while the shelf goes out to the
                // left, and back the other way
                ZStack(alignment: .top) {
                    // A LIST'S OWN PAGE AND THE ARCHIVE PUSHED IN THE SAME WAY (25 Nov: never Apple's pop-up sheet with
                    // its grabber line): over the list or the shelf, from the right, the back circle taking it away
                    // (a thing of a plan, its page, 25 Nov: it was Apple's pop-up sheet)
                    if let r = editingItem {
                        PlanItemSheet(planID: r.plan, day: r.day, itemID: r.item) { closeItem() }
                            .frame(width: w)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else if let id = infoFor {
                        ListInfoSheet(id: id) { withAnimation(Motion.quick) { infoFor = nil } }
                            .frame(width: w)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else if archiveOpen {
                        ListArchiveSheet(open: { id in s.parents = []; withAnimation(Motion.quick) { archiveOpen = false; s.open = id } })
                            .frame(width: w)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else if let id = s.open {
                        listPage(id, w: w)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else {
                        rows(w)
                            .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    }
                }
                .contentMargins(.top, trip == nil ? 0 : 48, for: .scrollContent)
                .frame(width: w, height: room, alignment: .top)
            }
            .offset(x: L.sheetInset + 16, y: top)
            // THE NEXT TRIP'S LINE, OVER THE PAGE, out of the square (NextTripLine)
            if let (t, p) = trip {
                NextTripLine(trip: t, plan: p)
                    .frame(width: w, height: 40)
                    .offset(x: L.sheetInset + 16, y: top + 44 + gap)
            }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
    }

    /// a thing's note in the open list, typed in place under it
    private func itemNote(_ t: ListsThing) -> some View {
        TextField("", text: Binding(get: { t.note }, set: { v in
            let n = String(v.prefix(500))
            ListsStore.shared.change { b in
                guard let li = b.lists.firstIndex(where: { $0.id == s.open }),
                      let ii = b.lists[li].items.firstIndex(where: { $0.id == t.id }) else { return }
                b.lists[li].items[ii].note = n
            }
        }), prompt: Text("Note").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
            .font(.subheadline).foregroundStyle(Palette.ink)
            .lineLimit(1 ... 5)
            .frame(minHeight: 36)
            .padding(.leading, 56)
    }
    /// A LIST INSIDE A LIST: its own cover, small, rounded as its tile
    private func innerThumb(_ r: String) -> some View {
        let inner = store.book.lists.first { $0.id == r }
        return Color.clear.frame(width: 44, height: 44)
            .overlay { if let inner { listCoverOrGlass(inner) } }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    /// its name, and "List" with how many things are in it
    private func innerLabel(_ r: String, name: String) -> some View {
        let n = store.book.lists.first { $0.id == r }.map { things($0).count } ?? 0
        return VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
            Text("List · \(n) " + (n == 1 ? "thing" : "things")).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
        }
    }
    /// a plan's thing put away: back to the plan, and a thing left with no words taken out
    private func closeItem() {
        guard let r = editingItem else { return }
        withAnimation(Motion.quick) { editingItem = nil }
        changePlan(r.plan) { pl in for k in pl.days.indices { pl.days[k].items.removeAll { $0.what.trimmingCharacters(in: .whitespaces).isEmpty } } }
    }

    // MARK: the top row

    private func topRow(_ w: CGFloat) -> some View {
        // ONE CIRCLE IN EACH CORNER THAT STAYS: the circle stays where it is and its mark changes; the wheel in the
        // middle shrinks away while a list is open and grows back
        let open = s.open
        let viewL = open.flatMap { viewable($0) }
        // (a list open: nothing in the right corner, 25 Nov; it was View on map, the Map tab's circle in a glass circle;
        // the list's own cover at its top is now what you tap to see it on the map)
        // (a list's own page or the archive pushed in: back, as for a list)
        let inner = infoFor != nil || archiveOpen || editingItem != nil
        let rightKey: String? = open == nil && !inner ? "plus" : nil
        return HStack(spacing: 0) {
            circle(open != nil || inner ? "back" : "search") {
                Feel.tap()
                if editingItem != nil { closeItem() }
                else if infoFor != nil { withAnimation(Motion.quick) { infoFor = nil } }
                else if archiveOpen { withAnimation(Motion.quick) { archiveOpen = false } }
                else if open != nil { withAnimation(Motion.quick) { s.close() } }
                else { s.searching.toggle(); if !s.searching { s.query = "" } }
            }
            .accessibilityLabel(open != nil || inner ? "Back" : s.searching ? "Close search" : "Search")
            Spacer(minLength: 8)
            if open == nil && !inner {
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
                        // (never from a point: it shrank to 1% and grew back from it; now Apple's blur
                        // replace, from 93%, as Pins' choices come and go, 25 Nov)
                        .transition(.blurReplace)
                }
            }
            Spacer(minLength: 8)
            // the plus makes one of the kind the wheel is on (books' making comes with their page); a list open with
            // places: SEE IT ON THE MAP, on the Map tab's own mark
            if let key = rightKey {
                circle(key) {
                    if let l = viewL { viewOnMap(l); return }
                    Feel.tap()
                    withAnimation(Motion.quick) { [s.newList, s.newPlan, s.newTier, s.newBook][min(s.kind, 3)]() }
                    // A NEW LIST STARTS ON ITS OWN PAGE OF INFORMATION (you can always just continue): its sheet,
                    // name first, over the empty list
                    if s.kind == 0, let id = s.open { s.naming = false; withAnimation(Motion.quick) { infoFor = id } }
                }
                .accessibilityLabel(open != nil ? "View on map" : ["New list", "New plan", "New tier list", "New book"][s.kind])
                .transition(.blurReplace)
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
        l.items.filter { $0.k != .section }.compactMap { it in
            if it.k == .mine, it.t == .list, let r = it.ref {
                // (a list inside: its own name, as it is now; gone if that list was deleted)
                guard let inner = store.book.lists.first(where: { $0.id == r }) else { return nil }
                return ListsThing(id: it.id, name: inner.name.isEmpty ? "New list" : inner.name, cc: nil, note: it.note, ref: r)
            }
            return ListsThing(id: it.id, name: it.n, cc: it.cc, note: it.note)
        }
    }

    @ViewBuilder private func rows(_ w: CGFloat) -> some View {
        let q = s.query.trimmingCharacters(in: .whitespaces).lowercased()
        ScrollView {
            // THE SHELF SLIDES WITH THE WHEEL: the kind turned to comes in from the side the wheel turned toward, the
            // one left goes out the other side (in a box that stays, so the change is inside it: the scroll view's
            // own content took no transition)
            ZStack(alignment: .topLeading) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    shelf(q)
                }
                .frame(width: w, alignment: .leading)
                .id(s.kind)
                // (the side read while it moves: a shelf leaving kept the side of the turn that brought it, and went out
                // the same way the next one came in)
                .transition(.asymmetric(insertion: .modifier(active: ShelfSlide(on: true, leaving: false, w: w + 24),
                                                             identity: ShelfSlide(on: false, leaving: false, w: w + 24)),
                                        removal: .modifier(active: ShelfSlide(on: true, leaving: true, w: w + 24),
                                                           identity: ShelfSlide(on: false, leaving: true, w: w + 24))))
            }
            .frame(width: w, alignment: .topLeading)
        }
        .scrollBlur()
        .scrollIndicators(.hidden)
        // THE OTHER KINDS' COVERS MADE AHEAD: the plans' map covers at the tiles' own size, so they are there when
        // the wheel turns to them (once the towns' and sights' indexes are in: a cover's key and its dots wait for
        // them, and a plan with no places yet finds its town by them)
        .task(id: "\(Int(w))|\(TownIndex.shared.ready && ThingIndex.shared.ready)") {
            TownIndex.shared.load(); ThingIndex.shared.load()
            guard TownIndex.shared.ready && ThingIndex.shared.ready else { return }
            let side = (w - 12) / 2
            for p in store.book.plans where !p.arch && !p.hid && !p.ai {
                let (ccs, spots) = Self.planCover(p)
                guard !ccs.isEmpty else { continue }
                _ = await ListMapCovers.image(ccs, spots: spots, world: map.world, size: CGSize(width: side, height: side), scale: scale)
                _ = await ListMapCovers.image(ccs, spots: spots, world: map.world, size: CGSize(width: w, height: 180), scale: scale)
            }
            let pages = [("Wishlist", wishThings)] + store.book.lists.filter { !$0.arch && !$0.hid && !$0.wish }.map { ($0.name, things($0)) }
            for (title, th) in pages {
                let (ccs, spots) = Self.pageCover(title: title, things: th)
                guard !ccs.isEmpty else { continue }
                _ = await ListMapCovers.image(ccs, spots: spots, world: map.world, size: CGSize(width: w, height: 180), scale: scale)
            }
        }
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
                    ForEach(ordered) { l in (l.wish ? AnyView(wishTile(l)) : AnyView(listTile(l))).settlesIn() }
                }
                .padding(.top, 4)
            }
            // THE ARCHIVE (25 Nov): archived or hidden lists left the shelf and could never be seen again; one quiet line
            // at the shelf's foot when there are any
            let away = store.book.lists.filter { $0.arch || $0.hid }.count
            if q.isEmpty, away > 0 {
                Button { Feel.tap(); withAnimation(Motion.quick) { archiveOpen = true } } label: {
                    Text("Archived and hidden · \(away)").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        // PLANS AND TIER LISTS AS TILES, the same shape as Lists': a plan's cover the map of where it goes, or its
        // days as a little calendar while it has no places; a tier list's its tiers in full colour
        case 1:
            let plans = store.book.plans.filter { !$0.arch && !$0.hid && !$0.ai && match($0.name) }
            if plans.isEmpty { if q.isEmpty { none("No plans yet") } else { noResults } }
            if !plans.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 20) {
                    ForEach(plans) { p in
                        let (ccs2, spots2) = Self.planCover(p)
                        tile(p.id, name: p.name.isEmpty ? "New plan" : p.name, dim: p.name.isEmpty, count: p.count, ccs: ccs2,
                             cover: ccs2.isEmpty ? AnyView(PlanCalendarCover(plan: p)) : nil, words: Self.shortWhen(p), spots: spots2)
                            .settlesIn()
                    }
                }
                .padding(.top, 4)
            }
        case 2:
            let tiers = store.book.tiers.filter { !$0.arch && !$0.hid && match($0.name) }
            if tiers.isEmpty { if q.isEmpty { none("No tier lists yet") } else { noResults } }
            if !tiers.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 20) {
                    ForEach(tiers) { t in
                        tile(t.id, name: t.name.isEmpty ? "New tier list" : t.name, dim: t.name.isEmpty, count: t.count, ccs: [],
                             cover: AnyView(TierBandsCover(tiers: t)),
                             words: t.count == 0 ? "Nothing ranked yet" : "\(t.count) ranked")
                            .settlesIn()
                    }
                }
                .padding(.top, 4)
            }
        default:
            // BOOKS AS TILES, as every kind: its cover (its first photo), its name, how many pages
            let books = store.book.books.filter { !$0.arch && !$0.hid && match($0.name) }
            // YOUR PASSPORT, FIRST AMONG BOOKS: its
            // first page as its cover; tapped, the map with the passport open on it
            let passportShown = q.isEmpty || match("Passport")
            if books.isEmpty && !passportShown { noResults }
            if !books.isEmpty || passportShown {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 20) {
                    if passportShown {
                        tile("passport", name: "Passport", dim: false, count: map.stamped.count, ccs: [],
                             cover: AnyView(PassportCover()),
                             words: "\(map.stamped.count) " + (map.stamped.count == 1 ? "stamp" : "stamps"),
                             tap: {
                                 // (on Countries, where the passport is at home)
                                 if let h = AIContext.head, h.mode != .countries { h.mode = .countries }
                                 NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: 0)
                                 Task { try? await Task.sleep(for: .milliseconds(450)); BookState.shared.open() }
                             })
                            .settlesIn()
                    }
                    ForEach(books) { b in
                        tile(b.id, name: b.name.isEmpty ? "New book" : b.name, dim: b.name.isEmpty, count: b.pages.count, ccs: [],
                             cover: AnyView(BookCover(book: b)),
                             words: b.pages.isEmpty ? "No pages yet" : "\(b.pages.count) " + (b.pages.count == 1 ? "page" : "pages"))
                            .settlesIn()
                    }
                }
                .padding(.top, 4)
            }
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
        let spots = things(l).compactMap { t in t.cc.map { t.name + "|" + $0 } }
        let named = spots.isEmpty ? Self.namedTown(l.name) : nil
        let land = spots.isEmpty && named == nil ? Self.namedCountry(l.name) : nil
        let ccs = named.map { [$0.file.lowercased()] } ?? land.map { [$0] } ?? Array(l.countries.prefix(4))
        return tile(l.id, name: l.name.isEmpty ? "New list" : l.name, dim: l.name.isEmpty, count: things(l).count,
             ccs: ccs, ticks: ListTicks.count(l.items.filter { $0.k != .section }), cover: listOwnCover(l),
             spots: named.map { [$0.name + "|" + $0.file.lowercased()] } ?? spots,
             places: l.items.filter { $0.k != .section }.allSatisfy { $0.k == .place })
    }
    /// a town of 100,000 people or more that a plan's name says, one word or two (: Lisbon), or nil A LIST PAGE'S
    /// COVER'S PLACES: its first four countries and its things where they are; with no places yet, the town or
    /// country its name says, as its tile shows; never while it is being named
    static func pageCover(title: String, things: [ListsThing], naming: Bool = false) -> (ccs: [String], spots: [String]) {
        let ccs0 = Array(NSOrderedSet(array: things.compactMap(\.cc)).array.compactMap { $0 as? String }.prefix(4))
        let named = ccs0.isEmpty && !naming ? namedTown(title) : nil
        let land = ccs0.isEmpty && !naming && named == nil ? namedCountry(title) : nil
        let spots0 = things.compactMap { t in t.cc.map { t.name + "|" + $0 } }
        return (named.map { [$0.file.lowercased()] } ?? land.map { [$0] } ?? ccs0,
                named.map { [$0.name + "|" + $0.file.lowercased()] } ?? spots0)
    }

    /// A PLAN'S COVER'S PLACES: its countries (the first four) and its things where they are; with no places yet, the
    /// town its name says  or the country; none, its little calendar
    static func planCover(_ p: Plan) -> (ccs: [String], spots: [String]) {
        let ccs = Array(NSOrderedSet(array: (p.days.flatMap(\.items) + p.ideas).compactMap { $0.cc?.lowercased() })
            .array.compactMap { $0 as? String }.prefix(4))
        // (each thing's own place, as a list's:, where they are, not Georgia's middle)
        let spots = (p.days.flatMap(\.items) + p.ideas).compactMap { i -> String? in
            guard let cc = i.cc, !cc.isEmpty else { return nil }
            let n = i.place.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            return n.isEmpty ? nil : n + "|" + cc.lowercased()
        }
        let named = ccs.isEmpty ? namedTown(p.name) : nil
        // (or the country it says,: its map)
        let land = ccs.isEmpty && named == nil ? namedCountry(p.name) : nil
        return (named.map { [$0.file.lowercased()] } ?? land.map { [$0] } ?? ccs,
                named.map { [$0.name + "|" + $0.file.lowercased()] } ?? spots)
    }

    static func namedTown(_ name: String) -> TownIndex.Hit? {
        TownIndex.shared.load()
        guard TownIndex.shared.ready else { return nil }
        let w = name.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }).map(String.init)
        let tries = (w.indices.dropLast().map { w[$0] + " " + w[$0 + 1] }) + w.filter { $0.count >= 4 }
        for t in tries {
            if let h = TownIndex.shared.hits(t, open: nil, limit: 3).first(where: { $0.name.townFolded == t.townFolded && $0.people >= 100_000 }) { return h }
        }
        return nil
    }
    /// a country a plan's name says by the map's name for it (: jp), or nil
    @MainActor static func namedCountry(_ name: String) -> String? {
        guard let w = AIContext.map?.world else { return nil }
        let f = " " + name.townFolded + " "
        return w.places.first { pl in pl.n.count >= 4 && f.contains(" " + pl.n.townFolded + " ") }?.id.lowercased()
    }
    /// THE WISHLIST (LS01): a tile the shelf's full width, first, its cover made from the places you wished
    private func wishTile(_ l: MyList) -> some View {
        let ccs = Array(NSOrderedSet(array: wishThings.compactMap(\.cc)).array.compactMap { $0 as? String }.prefix(4))
        return tile(l.id, name: l.name, dim: false, count: wishThings.count, ccs: ccs, cover: listOwnCover(l),
                    spots: wishThings.compactMap { t in t.cc.map { t.name + "|" + $0 } })
    }
    /// A LIST'S TILE: its cover a square, Apple's own map of where its places are; a list with no places yet, plain
    /// glass. Its name under it, one line, and how many things in 50%, as Apple's albums.
    private func tile(_ id: String, name: String, dim: Bool, count n: Int, ccs: [String], ticks: (been: Int, of: Int)? = nil,
                      cover: AnyView? = nil, words: String? = nil, spots: [String] = [], places: Bool = true,
                      tap: (() -> Void)? = nil) -> some View {
        let unit = places ? (n == 1 ? "place" : "places") : (n == 1 ? "thing" : "things")
        let sub = words ?? (n == 0 ? "Nothing yet" : ticks.map { $0.of == n ? "\($0.been) of \($0.of) been" : nil }
            .flatMap { $0 } ?? "\(n) \(unit)")
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { if let cover { cover } else { ListCover(ccs: ccs, world: map.world, spots: spots) } }
                .clipShape(shape)
                // (glass only for a tile with nothing of its own to show: over the map it washed Apple's colours out)
                .glassEffect(ccs.isEmpty && cover == nil ? PageGlass.on : .clear, in: shape)
                .padding(.bottom, 6)
            Text(name).font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink.opacity(dim ? 0.5 : 1)).lineLimit(1)
            Text(sub).font(.subheadline)
                .foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { Feel.tap(); if let tap { tap(); return }; s.parents = []; withAnimation(Motion.quick) { s.open = id } }
        // A LIST'S HOLD MENU (25 Nov): its own sheet, and archive / hide straight from the shelf
        .contextMenu {
            if let l = store.book.lists.first(where: { $0.id == id }) {
                Button("Edit") { withAnimation(Motion.quick) { infoFor = id } }
                Button(l.arch ? "Take out of the archive" : "Archive") {
                    ListsStore.shared.change { b in if let i = b.lists.firstIndex(where: { $0.id == id }) { b.lists[i].arch.toggle() } }
                }
                Button(l.hid ? "Show again" : "Hide") {
                    ListsStore.shared.change { b in if let i = b.lists.firstIndex(where: { $0.id == id }) { b.lists[i].hid.toggle() } }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + (n > 0 ? ", " + sub : ""))
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
        } else if store.book.books.contains(where: { $0.id == id }) {
            BookOpenView(id: id, w: w, naming: $naming, water: water)
        } else if id == "wish" {
            page(title: "Wishlist", editable: false, things: wishThings, note: "", w: w,
                 list: store.book.lists.first { $0.wish })
        } else if let l = store.book.lists.first(where: { $0.id == id }) {
            page(title: l.name, editable: true, things: things(l), note: l.note, w: w, list: l)
        }
    }

    /// A LIST (LS03): its cover at the top, wide, square corners, the list's name large on it at the bottom left (a
    /// list of no countries yet: the name alone, no cover); then its things, each its square flag at 44, its name.
    /// A note shows when its row is tapped. Taking a thing out is in the row's hold menu, never a button on every row.
    private func page(title: String, editable: Bool, things: [ListsThing], note: String, w: CGFloat, list: MyList? = nil) -> some View {
        let (ccs, spots) = Self.pageCover(title: title, things: things, naming: s.naming)
        let own = list.flatMap { listOwnCover($0) }
        let hasCover = own != nil || !ccs.isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    // (named in place only when asked; a new list is named in its own sheet, 25 Nov)
                    if editable, s.naming {
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
                        Text(title.isEmpty ? "New list" : title).font(.largeTitle.weight(.bold))
                            .foregroundStyle(Palette.ink.opacity(title.isEmpty ? 0.5 : 1))
                            .lineLimit(2)
                            // (its name tapped: the list's own sheet, everything that makes it yours, 25 Nov)
                            .onTapGesture { if let list { Feel.tap(); withAnimation(Motion.quick) { infoFor = list.id } } }
                            .accessibilityHint(list == nil ? "" : "Name, cover, who can see it")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .bottomLeading)
                .padding(.top, hasCover ? 192 : 0)
                .background(alignment: .top) {
                    if hasCover {
                        Group {
                            if let own { own } else { ListCover(ccs: ccs, world: map.world, spots: spots) }
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        // (its cover tapped: the list on the map, where the corner circle was, 25 Nov)
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .onTapGesture { if let l = s.open.flatMap({ viewable($0) }) { viewOnMap(l) } else { Feel.refuse() } }
                        .accessibilityLabel("See it on the map")
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.bottom, 8)
                // HOW MANY OF ITS PLACES YOU'VE BEEN TO: under its name, "All 20 been" once every one is stamped
                // (only a list of places: as its tile, every thing in it a place counted; a list of dishes said "0 of 2
                // been" for Seoul and a town called Pasta, 25 Nov)
                if let list, !list.wish, case let tk = ListTicks.count(list.items), tk.of > 0,
                   tk.of == list.items.filter({ $0.k != .section }).count {
                    Text(tk.been == tk.of ? "All \(tk.of) been" : "\(tk.been) of \(tk.of) been")
                        .font(tk.been == tk.of ? .body.weight(.semibold) : .body)
                        .foregroundStyle(Palette.ink.opacity(tk.been == tk.of ? 1 : 0.5))
                        .contentTransition(.numericText(value: Double(tk.been)))
                        .padding(.bottom, 12)
                }
                // WHAT IT'S FOR AND ITS NOTE, under its name, when it has them (both set in its page, 25 Nov)
                if let list, !list.what.isEmpty || !list.note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !list.what.isEmpty { Text(list.what).font(.body).foregroundStyle(Palette.ink.opacity(0.5)) }
                        if !list.note.isEmpty { Text(list.note).font(.body).foregroundStyle(Palette.ink) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); withAnimation(Motion.quick) { infoFor = list.id } }
                }
                ForEach(things) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            let key = PlaceKey(t.id).flatMap { $0.kind == .thing ? $0 : nil }
                            let set = key == nil ? t.cc.flatMap { ListSuggestions.setPlace(t.name, $0) } : nil
                            let own = key.flatMap { CollectionStore.shared.item($0)?.photo } ?? set?.item.photo ?? ""
                            let wd = key.map { $0.id.hasPrefix("wd:") ? String($0.id.dropFirst(3)) : $0.id }
                                ?? t.cc.flatMap { ListSuggestions.sight(t.name, $0) } ?? set?.item.id
                            if let r = t.ref {
                                innerThumb(r)
                            } else if let cc = t.cc, (wd != nil || !own.isEmpty), SetPlaceThumb.file(own: own, thing: wd ?? "") != nil {
                                SetPlaceThumb(own: own, thing: wd ?? "", cc: cc)
                            } else {
                                Group {
                                    if let cc = t.cc, let f = Flags.row(cc.lowercased()) { f.resizable().interpolation(.high) } else { Color.clear }
                                }
                                .frame(width: 44, height: 33)
                                .frame(width: 44, height: 44)
                                .onAppear { if let cc = t.cc, !cc.isEmpty { ThingStore.shared.load(cc.lowercased()); ThingIndex.shared.load() } }
                            }
                            if let r = t.ref {
                                innerLabel(r, name: t.name)
                            } else {
                                Text(t.name).font(.body).foregroundStyle(Palette.ink).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            // (a place you have been to: ticked)
                            if t.ref == nil, ListTicks.been(name: t.name, cc: t.cc) == true {
                                Icon5(key: "tick", ink: Palette.ink, size: 18).frame(width: 44, height: 44)
                                    .accessibilityLabel("Been")
                            }
                        }
                        // OPENED: its note, and for a place, Open, which takes it to the map (morning Q12)
                        if s.noted == t.id {
                            // ITS NOTE, written here in your own lists; read
                            // only in the wishlist
                            if editable {
                                itemNote(t)
                            } else if !t.note.isEmpty {
                                Text(t.note).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                                    .padding(.leading, 56)
                            }
                            if let cc = t.cc, !cc.isEmpty {
                                Button { PlanPlaces.open(t.name, cc: cc) } label: {
                                    Text("Open").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                                        .padding(.horizontal, 16).frame(height: 36)
                                        .glassEffect(PageGlass.control.interactive(), in: .capsule)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 56).padding(.bottom, 8)
                                .accessibilityHint("Opens it on the map")
                            }
                        }
                    }
                    .frame(minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // (a list inside opens, pushed in as any list)
                        if let r = t.ref { Feel.tap(); withAnimation(Motion.quick) { s.openInner(r) }; return }
                        guard editable || !t.note.isEmpty || !(t.cc ?? "").isEmpty else { return }
                        Feel.tap()
                        withAnimation(Motion.quick) { s.noted = s.noted == t.id ? nil : t.id }
                    }
                    // out of the list (yours only: the wishlist is the map's own, changed on the map) SWIPED LEFT, it
                    // comes out (Undo brings it back); the words show behind it as it goes
                    .offset(x: swiping?.id == t.id ? min(0, swiping!.x) : 0)
                    .background(alignment: .trailing) {
                        if editable, swiping?.id == t.id, (swiping?.x ?? 0) < -12 {
                            Text("Remove").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.white)
                                .padding(.horizontal, 16).frame(maxHeight: .infinity)
                                .background(Palette.ink, in: .capsule)
                        }
                    }
                    .simultaneousGesture(editable ? DragGesture(minimumDistance: 18)
                        .onChanged { g in
                            guard abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
                            swiping = (t.id, g.translation.width)
                        }
                        .onEnded { g in
                            if g.translation.width < -110 { removeThing(t.id) }
                            withAnimation(Motion.quick) { swiping = nil }
                        } : nil)
                    // HELD, it lifts and moves: dropped on another row, it goes in that row's place
                    .draggable(t.id) {
                        Text(t.name).font(.body).foregroundStyle(Palette.ink)
                            .padding(.horizontal, 16).frame(height: 44)
                            .glassEffect(PageGlass.surface, in: .capsule)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard editable, let id = ids.first, id != t.id else { return false }
                        moveThing(id, to: t.id)
                        return true
                    }
                    // (no hold menu: holding lifts the row to move it; taking out is the swipe, with Undo)
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Take out") { if editable { removeThing(t.id) } }
                }
                // adding, in the list (ListEdit)
                if editable, let id = s.open { ListAddRow(listID: id) }
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
        // UNDO, for a few seconds after something is taken out
        .overlay(alignment: .bottom) {
            if let r = removed, r.list == s.open {
                Button {
                    Feel.tap()
                    withAnimation(Motion.quick) {
                        ListsStore.shared.change { b in
                            if let i = b.lists.firstIndex(where: { $0.id == r.list }) {
                                b.lists[i].items.insert(r.item, at: min(r.at, b.lists[i].items.count))
                            }
                        }
                        removed = nil
                    }
                } label: {
                    Text("Undo").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 24).frame(height: 44)
                        .glassEffect(PageGlass.surface.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
                .transition(.identity)
            }
        }
    }

    /// the open list, when it has places that are on the map (the wishlist is the map's own already)
    private func viewable(_ id: String) -> MyList? {
        guard id != "wish", let l = store.book.lists.first(where: { $0.id == id }) else { return nil }
        return l.items.contains { $0.k == .place && !($0.cc ?? "").isEmpty } ? l : nil
    }
    /// the list's countries coloured on the Map tab, under them (P06 §3)
    private func viewOnMap(_ l: MyList) {
        guard let w = map.world else { return }
        Feel.tap()
        let ccs = Set(l.items.filter { $0.k == .place }.compactMap { $0.cc?.lowercased() }.filter { !$0.isEmpty })
        let places = Set(ccs.compactMap { w.placeIndex[$0] })
        guard !places.isEmpty else { Feel.refuse(); return }
        // (the caption's count: of the list's countries, the ones you have stamped)
        map.viewing = MapController.Viewing(name: l.name.isEmpty ? "New list" : l.name, places: places,
                                            been: places.filter { map.stamped.contains($0) }.count,
                                            tint: ListColours.vector(l.mapc))
        // (on Countries: Pins and Places draw no countries' colours)
        if let h = AIContext.head, h.mode != .countries { h.mode = .countries }
        NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: 0)
    }

    /// a thing taken out of the open list, kept for Undo for 8 s
    private func removeThing(_ id: String) {
        guard let lid = s.open, let l = ListsStore.shared.book.lists.first(where: { $0.id == lid }),
              let at = l.items.firstIndex(where: { $0.id == id }) else { return }
        Feel.lift()
        let item = l.items[at]
        withAnimation(Motion.quick) {
            ListsStore.shared.change { b in
                if let i = b.lists.firstIndex(where: { $0.id == lid }) { b.lists[i].items.removeAll { $0.id == id } }
            }
            removed = (lid, item, at)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if removed?.item.id == id { withAnimation(Motion.quick) { removed = nil } }
        }
    }
    /// a thing moved into another's place in the open list
    private func moveThing(_ id: String, to target: String) {
        guard let lid = s.open else { return }
        Feel.notch()
        withAnimation(Motion.quick) {
            ListsStore.shared.change { b in
                guard let i = b.lists.firstIndex(where: { $0.id == lid }),
                      let from = b.lists[i].items.firstIndex(where: { $0.id == id }),
                      let to = b.lists[i].items.firstIndex(where: { $0.id == target }) else { return }
                let it = b.lists[i].items.remove(at: from)
                b.lists[i].items.insert(it, at: to)
            }
        }
    }

    // MARK: one plan

    /// a plan's dates short enough for its tile:,, the year only when it is not this one, or
    static func shortWhen(_ p: Plan) -> String {
        guard !p.start.isEmpty, let a = PlanDates.date(p.start), let b = PlanDates.date(p.end.isEmpty ? p.start : p.end) else { return "Someday" }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC")
        let ya = cal.component(.year, from: a), yb = cal.component(.year, from: b)
        let thisYear = Calendar.current.component(.year, from: Date())
        func day(_ d: Date) -> String { "\(cal.component(.day, from: d))" }
        f.dateFormat = "MMM"
        if ya != yb {
            f.dateFormat = "d MMM yyyy"; let x = f.string(from: a), y = f.string(from: b); return "\(x) to \(y)"
        }
        let yr = ya == thisYear ? "" : " \(ya)"
        if p.start == p.end || p.end.isEmpty { f.dateFormat = "d MMM"; return f.string(from: a) + yr }
        if cal.component(.month, from: a) == cal.component(.month, from: b) { return "\(day(a)) to \(day(b)) \(f.string(from: b))" + yr }
        f.dateFormat = "d MMM"
        return "\(f.string(from: a)) to \(f.string(from: b))" + yr
    }
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

    @ViewBuilder private func datePills(_ p: Plan) -> some View {
        dateBox(p.start, label: "First day") { v in var e = false; changePlan(p.id) { $0.pickFirst(v, endFirst: &e) } }
        dateBox(p.end, label: "Last day") { v in var e = false; changePlan(p.id) { _ = $0.pickLast(v, endFirst: &e, force: true) } }
    }
    @ViewBuilder private func calendarPills(_ p: Plan) -> some View {
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
    }
    private func planPage(_ p: Plan, w: CGFloat) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ITS MAP ON TOP, as a list's page has it: where it goes, or the town its name says; a plan with no
                // places yet keeps its calendar on the shelf
                let cover = Self.planCover(p)
                if !cover.ccs.isEmpty {
                    ListCover(ccs: cover.ccs, world: map.world, spots: cover.spots)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.bottom, 12)
                }
                if s.naming || p.name.isEmpty {
                    TextField("", text: Binding(get: { p.name }, set: { v in changePlan(p.id) { $0.name = String(v.prefix(60)) } }),
                              prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                    .focused($naming)
                    .submitLabel(.done)
                    .onSubmit { s.naming = false }
                    .onAppear { naming = true }
                    .onChange(of: naming) { _, f in if !f { s.naming = false } }
                    .frame(minHeight: 44)
                } else {
                    Text(p.name).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .onTapGesture { Feel.tap(); s.naming = true }
                }
                // its first and last day (none yet: someday), then ITS CALENDAR: a dated plan goes out as a calendar
                // file (Apple's Calendar and Google Calendar both take it); a calendar file comes in as things on the
                // plan's days (an undated plan takes the file's days). One line when they all fit, else the calendar on
                // a second line (25 Nov: an undated plan had Import alone under First day and Last day)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { datePills(p); calendarPills(p); Spacer(minLength: 0) }
                        .frame(minHeight: 52)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) { datePills(p); Spacer(minLength: 0) }.frame(minHeight: 52)
                        HStack(spacing: 12) { calendarPills(p); Spacer(minLength: 0) }.frame(minHeight: 52)
                    }
                }
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
                                .onTapGesture { Feel.tap(); withAnimation(Motion.quick) { editingItem = PlanItemRef(plan: p.id, day: i, item: it.id) } }
                        }
                        PlanDayHours(items: d.items, ai: p.ai,
                                     open: { it in withAnimation(Motion.quick) { editingItem = PlanItemRef(plan: p.id, day: i, item: it.id) } },
                                     add: { m in
                                         let item = PlanItem(at: String(format: "%02d:%02d", m / 60, m % 60), what: "", place: "")
                                         changePlan(p.id) { $0.days[i].items.append(item); $0.sortDay(i) }
                                         withAnimation(Motion.quick) { editingItem = PlanItemRef(plan: p.id, day: i, item: item.id) }
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
                        }
                        .frame(minHeight: 44)
                        // a tap on the thing opens its page (all day or a time, where, link, note, colour, Take out)
                        .contentShape(Rectangle())
                        .onTapGesture { Feel.tap(); withAnimation(Motion.quick) { editingItem = PlanItemRef(plan: p.id, day: i, item: it.id) } }
                        // TAKING IT OUT IS IN ITS HOLD MENU (and its page), never a black cross on every row (25 Nov; as a
                        // list's rows)
                        .contextMenu {
                            Button("Take out", role: .destructive) {
                                Feel.lift()
                                withAnimation(Motion.quick) { changePlan(p.id) { $0.days[i].items.removeAll { $0.id == it.id } } }
                            }
                        }
                        .accessibilityAction(named: "Take out") {
                            withAnimation(Motion.quick) { changePlan(p.id) { $0.days[i].items.removeAll { $0.id == it.id } } }
                        }
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
    /// the tier whose own strip is open under it (its name, its colour, Remove)
    @State private var tierOpen: Int?
    /// a thing is being dragged over the bin
    @State private var overBin = false

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
                    .font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                    .focused(naming)
                    .submitLabel(.done)
                    .onSubmit { s.naming = false }
                    .onAppear { naming.wrappedValue = true }
                    .frame(minHeight: 44)
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        Text(t.name).font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                            .frame(minHeight: 44)
                            .onTapGesture { Feel.tap(); s.naming = true }
                        Spacer(minLength: 0)
                        // THE BIN, by the name: a thing dragged from anywhere and dropped on it is taken out; red while
                        // one is over it
                        Icon5(key: "bin", ink: overBin ? Palette.white : Palette.ink, size: 22)
                            .frame(width: 44, height: 44)
                            .background { Circle().fill(overBin ? Palette.red : .clear) }
                            .animation(Motion.quick, value: overBin)
                            .dropDestination(for: String.self) { names, _ in
                                guard let n = names.first else { return false }
                                Feel.lift()
                                withAnimation(Motion.quick) { change { _ = $0.move(n, to: nil) } }
                                return true
                            } isTargeted: { on in if on != overBin { overBin = on; if on { Feel.tick() } } }
                            .accessibilityLabel("Bin: drop a thing here to take it out")
                    }
                }
                // EDGE TO EDGE, FULL COLOUR: each tier's whole row is its colour, from one side of the screen to the
                // other; its letter in line with the title
                let m = max(0, (UIScreen.main.bounds.width - w) / 2)
                // (bands flush: 2 pt gaps showed the gradient through as muddy lines between them)
                VStack(spacing: 0) {
                    ForEach(Array(t.rows.enumerated()), id: \.offset) { i, r in
                        HStack(alignment: .top, spacing: 0) {
                            Text(r.t).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                                .frame(width: 52, height: 52)
                                .contentShape(Rectangle())
                                // (its letter tapped: its own strip opens under it)
                                .onTapGesture { Feel.tap(); withAnimation(Motion.quick) { tierOpen = tierOpen == i ? nil : i } }
                                .accessibilityLabel("Tier \(r.t)")
                                .accessibilityHint("Its name and colour")
                            ScrollView(.horizontal) {
                                HStack(spacing: 6) { ForEach(r.items, id: \.self) { chip($0) } }
                                    .padding(.horizontal, 6).frame(minHeight: 52)
                            }
                            .scrollIndicators(.hidden)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        }
                        .padding(.horizontal, m)
                        .background(Self.colour(t.colour(i)))
                        .padding(.horizontal, -m)
                        .dropDestination(for: String.self) { names, _ in
                            guard let n = names.first else { return false }
                            Feel.tap()
                            withAnimation(Motion.quick) { change { _ = $0.move(n, to: .row(i)) } }
                            return true
                        }
                        if tierOpen == i { tierStrip(i, r) }
                    }
                }
                // ADD A TIER (two at least, as many as wanted)
                Button {
                    Feel.tap()
                    withAnimation(Motion.quick) {
                        change { tl in
                            let letters = ["S", "A", "B", "C", "D", "E", "F", "G", "H"]
                            let next = letters.first { l in !tl.rows.contains { $0.t == l } } ?? "\(tl.rows.count + 1)"
                            tl.rows.append(TierRow(t: next, items: []))
                        }
                    }
                } label: {
                    Text("Add a tier").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                // A TIER LIST ON THE MAP: its places, each in its
                // tier's colour, everything else plain, "Viewing" its name
                if !mapPlaces().isEmpty {
                    Button { seeOnMap() } label: {
                        Text("See on the map").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
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

    /// its ranked things that are countries, with their tier's colour: a thing's own country where it has one, else a
    /// country of exactly its name
    private func mapPlaces() -> [Int: SIMD4<Float>] {
        guard let w = AIContext.map?.world else { return [:] }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        var out: [Int: SIMD4<Float>] = [:]
        for (i, r) in t.rows.enumerated() {
            let v = Palette.named[t.colour(i)] ?? SIMD3(0.5, 0.5, 0.5)
            let c = SIMD4<Float>(Float(v.x), Float(v.y), Float(v.z), 1)
            for n in r.items {
                let cc = t.cc[n]?.lowercased() ?? CountryEntity.all.first { fold($0.name) == fold(n) }?.id.lowercased()
                if let cc, let pi = w.placeIndex[cc], out[pi] == nil { out[pi] = c }
            }
        }
        return out
    }
    private func seeOnMap() {
        guard let map = AIContext.map else { return }
        let tints = mapPlaces()
        guard !tints.isEmpty else { Feel.refuse(); return }
        Feel.tap()
        let places = Set(tints.keys)
        map.viewing = MapController.Viewing(name: t.name.isEmpty ? "Tier list" : t.name, places: places,
                                            been: places.filter { map.stamped.contains($0) }.count, tints: tints)
        if let h = AIContext.head, h.mode != .countries { h.mode = .countries }
        NotificationCenter.default.post(name: Notification.Name("wyaTestTab"), object: 0)
    }

    /// A TIER'S OWN STRIP, under it: its name, its colour from the app's, and Remove (two tiers at least stay)
    @ViewBuilder private func tierStrip(_ i: Int, _ r: TierRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: Binding(get: { r.t }, set: { v in change { tl in if tl.rows.indices.contains(i) { tl.rows[i].t = String(v.prefix(24)) } } }),
                      prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                .font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                .submitLabel(.done)
                .frame(minHeight: 44)
            HStack(spacing: 6) {
                ForEach(TierList.colours, id: \.self) { c in
                    let on = t.colour(i) == c
                    Circle().fill(Self.colour(c))
                        .overlay { Circle().strokeBorder(Palette.ink.opacity(0.12), lineWidth: 0.5) }
                        .frame(width: 30, height: 30)
                        .overlay { if on { Circle().strokeBorder(Palette.ink, lineWidth: 2).frame(width: 38, height: 38) } }
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                        .onTapGesture { Feel.tap(); change { tl in if tl.rows.indices.contains(i) { tl.rows[i].c = c } } }
                        .accessibilityLabel(c)
                }
                Spacer(minLength: 0)
            }
            if t.rows.count > 2 {
                Button {
                    Feel.lift()
                    withAnimation(Motion.quick) {
                        tierOpen = nil
                        change { tl in
                            guard tl.rows.indices.contains(i) else { return }
                            // (its things go back to the ones not ranked yet, never lost)
                            tl.pool.append(contentsOf: tl.rows[i].items)
                            tl.rows.remove(at: i)
                        }
                    }
                } label: {
                    Text("Remove tier").font(.body).foregroundStyle(Palette.red)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .transition(.blurReplace)
    }

    private func chip(_ n: String) -> some View {
        HStack(spacing: 6) {
            // (a place keeps its flag in the tier list)
            if let cc = t.cc[n], let f = Flags.row(cc.lowercased()) {
                f.resizable().interpolation(.high).frame(width: 20, height: 15)
            }
            Text(n).font(.subheadline).foregroundStyle(Palette.ink).lineLimit(1)
        }
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

/// A TIER LIST'S COVER: its tiers in full colour, flush, top tier first, the tile's whole square (as its page shows them)
struct TierBandsCover: View {
    let tiers: TierList
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< max(1, min(tiers.rows.count, 8)), id: \.self) { i in
                let v = Palette.named[tiers.colour(i)] ?? SIMD3(0.5, 0.5, 0.5)
                Rectangle().fill(Color(red: v.x, green: v.y, blue: v.z))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A PLAN'S COVER while it has no places: its days as a little calendar, seven across, a day with something planned
/// filled black, the rest faint (a someday plan, one empty week)
struct PlanCalendarCover: View {
    let plan: Plan
    var body: some View {
        let days = Array(plan.days.prefix(28))
        let shown = max(7, days.count)
        let rows = Int(ceil(Double(shown) / 7))
        GeometryReader { g in
            let gap: CGFloat = 4
            let side = min((g.size.width - 32 - gap * 6) / 7, (g.size.height - 32 - gap * CGFloat(rows - 1)) / CGFloat(rows))
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0 ..< rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0 ..< 7, id: \.self) { c in
                            let i = r * 7 + c
                            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                                .fill(Palette.ink.opacity(i >= shown ? 0 : i < days.count && !days[i].items.isEmpty ? 1 : 0.12))
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
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
    /// its places,: each dot at its own town or sight where one is found, else its country's middle
    var spots: [String] = []
    @State private var img: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { g in
            ZStack {
                if let shown = img ?? ListMapCovers.cached(ccs, spots: spots, size: g.size) {
                    Image(uiImage: shown).resizable().scaledToFill()
                } else { Color.clear }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            // (made again once the towns' and sights' indexes have come: their dots move to their own places)
            .task(id: ccs.joined(separator: ",") + "|" + spots.joined(separator: ",") + "|\(Int(g.size.width))x\(Int(g.size.height))"
                  + (TownIndex.shared.ready && ThingIndex.shared.ready ? "|r" : "")) {
                img = ListMapCovers.cached(ccs, spots: spots, size: g.size)
                if img == nil { img = await ListMapCovers.image(ccs, spots: spots, world: world, size: g.size, scale: scale) }
            }
        }
        .accessibilityHidden(true)
        .onAppear { if !spots.isEmpty { TownIndex.shared.load(); ThingIndex.shared.load() } }
    }
}

/// THE LISTS' MAP COVERS: Apple's own map, its realistic land and its relief, framed on the countries a list holds,
/// made once a size and kept; no names, no places of interest, nothing drawn over it
@MainActor
enum ListMapCovers {
    private static var cache: [String: UIImage] = [:]
    private static func key(_ ccs: [String], _ spots: [String], _ size: CGSize) -> String {
        ccs.sorted().joined(separator: ",") + "|" + spots.joined(separator: ",") + "|\(Int(size.width))x\(Int(size.height))"
            + (TownIndex.shared.ready && ThingIndex.shared.ready ? "|r" : "")
    }
    static func cached(_ ccs: [String], spots: [String] = [], size: CGSize) -> UIImage? { cache[key(ccs, spots, size)] }

    /// A PLACE OF A LIST, WHERE IT IS: a town of that name in that country, else a sight of exactly that name there,
    /// else nil (its country's middle)
    static func spot(_ name: String, _ cc: String) -> CLLocationCoordinate2D? {
        // (a town of some size: "Pasta" in a list of dishes is not the hamlet of Pasta near Turin)
        if let t = TownIndex.shared.named(name, in: cc), t.people >= 1_000 { return CLLocationCoordinate2D(latitude: t.lat, longitude: t.lon) }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        if ThingIndex.shared.ready, let h = ThingIndex.shared.hits(name, open: cc, limit: 6, near: false)
            .first(where: { $0.file.lowercased() == cc.lowercased() && fold($0.name) == fold(name) }) {
            return CLLocationCoordinate2D(latitude: h.lat, longitude: h.lon)
        }
        return nil
    }

    static func image(_ ccs: [String], spots: [String] = [], world: World?, size: CGSize, scale: CGFloat) async -> UIImage? {
        let k = key(ccs, spots, size)
        if let c = cache[k] { return c }
        guard let world, !ccs.isEmpty, size.width > 4, size.height > 4 else { return nil }
        // the countries' frames, as Apple's map points (the frames are in our own map's units: Equal Earth)
        var rect = MKMapRect.null
        var mids: [CLLocationCoordinate2D] = []
        var frames: [String: MKMapRect] = [:], midOf: [String: CLLocationCoordinate2D] = [:]
        // (the countries of all its places, not only the first four: the Wishlist's Madagascar and Namibia had no dot)
        var all = ccs.map { $0.lowercased() }
        for s in spots { if let c = s.split(separator: "|").last.map({ String($0).lowercased() }), !all.contains(c) { all.append(c) } }
        for cc in all {
            guard let i = world.placeIndex[cc.lowercased()] ?? world.placeIndex[cc], let f = world.frame(of: i) else { continue }
            let m = EqualEarth.unproject(SIMD2(Double(f.x + f.z) / 2, Double(f.y + f.w) / 2))
            let mid = CLLocationCoordinate2D(latitude: max(-80, min(80, m.lat)), longitude: m.lon)
            mids.append(mid); midOf[cc.lowercased()] = mid
            var r = MKMapRect.null
            for q in [SIMD2(f.x, f.y), SIMD2(f.z, f.w)] {
                let ll = EqualEarth.unproject(SIMD2(Double(q.x), Double(q.y)))
                // (framed between 60 S and 78 N, where people are: Chile's frame down to its Antarctic claim made a list
                // of Portugal, Peru and Chile so tall the cover was capped at the world's width and cut Portugal off its
                // top, 25 Nov)
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: max(-60, min(78, ll.lat)), longitude: ll.lon))
                r = r.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
            }
            frames[cc.lowercased()] = r
            rect = rect.union(r)
        }
        guard !rect.isNull else { return nil }
        // (each place at its own town or sight where found; a country of none of them keeps its middle)
        if !spots.isEmpty {
            var placed: [CLLocationCoordinate2D] = [], placedCC = Set<String>(), seen = Set<String>()
            for s in spots.prefix(40) {
                let parts = s.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, seen.insert(s.lowercased()).inserted else { continue }
                if let c = spot(parts[0], parts[1]) { placed.append(c); placedCC.insert(parts[1].lowercased()) }
            }
            let rest = all.filter { !placedCC.contains($0) }
            mids = placed + rest.compactMap { midOf[$0] }
            // (framed on the places themselves, and on the whole of a country only where nothing in it is placed: a
            // list of Vladivostok framed on all of Russia ended in the north, Vladivostok under its edge)
            if !placed.isEmpty {
                rect = .null
                for m in placed { rect = rect.union(MKMapRect(origin: MKMapPoint(m), size: MKMapSize(width: 0, height: 0))) }
                for cc in rest { if let r = frames[cc] { rect = rect.union(r) } }
            }
        }
        // room round them, and the cover's own shape (never stretched)
        let aspect = size.width / size.height
        var w = max(rect.size.width, MKMapSize.world.width / 60) * 1.4, h = max(rect.size.height, MKMapSize.world.height / 60) * 1.4
        if w / h < aspect { w = h * aspect } else { h = w / aspect }
        if w > MKMapSize.world.width { w = MKMapSize.world.width; h = w / aspect }
        if h > MKMapSize.world.height { h = MKMapSize.world.height; w = h * aspect }
        // (kept inside the world across too: a wide cover nearly the world's width began west of its edge, and Apple's map
        // then shifted the view and cut Portugal off a list of Portugal, Peru and Chile, 25 Nov)
        // (centred on its places, not on its countries' whole outlines: Apple's map goes only so far out, showing the
        // middle of what was asked, and Chile's outline down to Tierra del Fuego pulled that middle south of Portugal)
        let pts = mids.map { MKMapPoint($0) }
        var cx = pts.isEmpty ? rect.midX : (pts.map(\.x).min()! + pts.map(\.x).max()!) / 2
        var cy = pts.isEmpty ? rect.midY : (pts.map(\.y).min()! + pts.map(\.y).max()!) / 2
        // A LIST ROUND THE WORLD: wider than Apple's map shows at a cover's size (about two fifths of the world), the
        // cover is where most of its places are, not the middle of them all (a list from Peru to Japan to New Zealand
        // was framed on the mid-Atlantic, nearly every dot off its edges, 25 Nov)
        let reach = MKMapSize.world.width * 0.4
        if pts.count > 2, pts.map(\.x).max()! - pts.map(\.x).min()! > reach {
            var best = (n: 0, from: cx - reach / 2)
            for p in pts {
                let n = pts.filter { $0.x >= p.x && $0.x <= p.x + reach }.count
                if n > best.n { best = (n, p.x) }
            }
            let inside = pts.filter { $0.x >= best.from && $0.x <= best.from + reach }
            if !inside.isEmpty {
                let x0 = inside.map(\.x).min()!, x1 = inside.map(\.x).max()!
                let y0 = inside.map(\.y).min()!, y1 = inside.map(\.y).max()!
                cx = (x0 + x1) / 2; cy = (y0 + y1) / 2
                // (and only as wide as those places: a frame the world's width can only sit at the world's middle)
                w = max(x1 - x0, MKMapSize.world.width / 60) * 1.4; h = max(y1 - y0, MKMapSize.world.height / 60) * 1.4
                if w / h < aspect { w = h * aspect } else { h = w / aspect }
                if h > MKMapSize.world.height { h = MKMapSize.world.height; w = h * aspect }
            }
        }
        let o = MKMapPoint(x: min(max(0, cx - w / 2), MKMapSize.world.width - w), y: max(0, cy - h / 2))
        let opt = MKMapSnapshotter.Options()
        opt.mapRect = MKMapRect(origin: o, size: MKMapSize(width: w, height: h))
        opt.size = size
        opt.scale = scale
        let conf = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        conf.pointOfInterestFilter = .excludingAll
        conf.showsTraffic = false
        opt.preferredConfiguration = conf
        guard let snap = try? await MKMapSnapshotter(options: opt).start() else { return nil }
        // A DOT ON EACH OF ITS PLACES: what makes one list's map its own. Small and plain black, no halo (25 Nov: they
        // were 8 pt on a 12 pt white ring, too big and loud)
        let out = UIGraphicsImageRenderer(size: snap.image.size, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = snap.image.scale; return f
        }()).image { ctx in
            snap.image.draw(at: .zero)
            let c = ctx.cgContext
            for m in mids {
                let p = snap.point(for: m)
                c.setFillColor(UIColor(Palette.ink).cgColor)
                c.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            }
        }
        cache[k] = out
        return out
    }
}

/// a shelf moving in or out with the kinds' wheel: the side is the wheel's last turn, read while it moves
struct ShelfSlide: ViewModifier {
    let on: Bool
    let leaving: Bool
    let w: CGFloat
    func body(content: Content) -> some View {
        let fwd = ListsState.shared.kindForward
        content.offset(x: on ? (leaving ? (fwd ? -w : w) : (fwd ? w : -w)) : 0)
    }
}

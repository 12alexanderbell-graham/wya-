import SwiftUI

/// THE LISTS TAB (the square): the whole screen is the water, clear glass over the real map (as Regions' list is), with
/// its own top row: search on the left, the four kinds (Lists, Plans, Tier lists, Books) as their icons in the middle,
/// the plus on the right. Lists first: your wishlist always first (the map's own wishlist: what you wished there is
/// what is in it), then your lists, each a row (its first country's flag, its name, how many things are in it). A row
/// opens the list (its things, a note shown only when the row is opened); the plus makes a new list, its name typed at
/// once (a list left without a name is not kept).
@MainActor
@Observable
final class ListsState {
    static let shared = ListsState()
    /// 0 Lists, 1 Plans, 2 Tier lists, 3 Books
    var kind = 0
    /// the list open, by id ("wish" is the map's wishlist)
    var open: String?
    /// the open list's name being typed
    var naming = false
    var searching = false
    var query = ""
    /// the thing whose note is shown
    var noted: String?

    static let kinds = ["lists-lists", "lists-plans", "lists-tiers", "lists-books"]
    static let words = ["Lists", "Plans", "Tier lists", "Books"]

    /// a new list, its name typed at once
    func newList() {
        let l = MyList(name: "")
        ListsStore.shared.change { $0.lists.append(l) }
        open = l.id
        naming = true
    }
    /// leaving a list: one left with no name and nothing in it is not kept
    func close() {
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

    var body: some View {
        let L = water.layout
        let w = L.W - 2 * L.sheetInset - 32
        let top = max(form.top + 12, L.safeTop)
        let room = max(56, L.capsule.minY - 8 - (top + 56))
        ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                topRow(w)
                Group {
                    if let id = s.open { listPage(id, w: w) } else { rows(w) }
                }
                .frame(width: w, height: room, alignment: .top)
            }
            .offset(x: L.sheetInset + 16, y: top)
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
    }

    // MARK: the top row

    private func topRow(_ w: CGFloat) -> some View {
        HStack(spacing: 0) {
            if s.open != nil {
                // a list open: its way back where search was
                Button { Feel.tap(); withAnimation(Motion.quick) { s.close() } } label: {
                    Icon5(key: "back", ink: Palette.ink, size: 22).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                    HStack(spacing: 20) {
                        ForEach(0 ..< 4, id: \.self) { k in
                            Button {
                                guard k != s.kind else { return }
                                Feel.tap()
                                s.kind = k
                            } label: {
                                Icon5(key: ListsState.kinds[k], on: k == s.kind,
                                      ink: k == s.kind ? Palette.ink : Palette.ink.opacity(0.5), size: 24)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ListsState.words[k])
                            .accessibilityAddTraits(k == s.kind ? .isSelected : [])
                        }
                    }
                }
                Spacer(minLength: 8)
                // the plus: a new list (the other kinds' making comes with their pages)
                circle("plus", dim: s.kind != 0) {
                    guard s.kind == 0 else { Feel.refuse(); return }
                    Feel.tap()
                    withAnimation(Motion.quick) { s.newList() }
                }
                .accessibilityLabel("New list")
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
                switch s.kind {
                case 0:
                    let lists = store.book.lists.filter { !$0.arch && !$0.hid }
                    ForEach(lists.filter { q.isEmpty || $0.name.lowercased().contains(q) }) { l in
                        let n = l.wish ? wishThings.count : things(l).count
                        let first = l.wish ? wishThings.first?.cc : l.countries.first
                        row(first, l.name.isEmpty ? "New list" : l.name, n == 0 ? "" : "\(n) \(n == 1 ? "place" : "places")",
                            dim: l.name.isEmpty) {
                            Feel.tap()
                            withAnimation(Motion.quick) { s.open = l.id }
                        }
                    }
                case 1:
                    ForEach(store.book.plans.filter { !$0.arch && !$0.hid && (q.isEmpty || $0.name.lowercased().contains(q)) }) { p in
                        row(nil, p.name, p.count == 0 ? "" : "\(p.count) \(p.count == 1 ? "stop" : "stops")") { Feel.refuse() }
                    }
                case 2:
                    ForEach(store.book.tiers.filter { !$0.arch && !$0.hid && (q.isEmpty || $0.name.lowercased().contains(q)) }) { t in
                        row(nil, t.name, t.count == 0 ? "" : "\(t.count) ranked") { Feel.refuse() }
                    }
                default:
                    ForEach(store.book.books.filter { q.isEmpty || $0.name.lowercased().contains(q) }) { b in
                        row(nil, b.name, "") { Feel.refuse() }
                    }
                }
            }
            .frame(width: w, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                Color.black
            }
        }
    }

    private func row(_ cc: String?, _ name: String, _ sub: String, dim: Bool = false, _ tap: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Group {
                if let cc, let f = Flags.square(cc.lowercased()) { f.resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.headline).foregroundStyle(Palette.ink.opacity(dim ? 0.5 : 1)).lineLimit(1).minimumScaleFactor(0.7)
                if !sub.isEmpty {
                    Text(sub).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
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
        if id == "wish" {
            page(title: "Wishlist", editable: false, things: wishThings, note: "", w: w)
        } else if let l = store.book.lists.first(where: { $0.id == id }) {
            page(title: l.name, editable: true, things: things(l), note: l.note, w: w)
        }
    }

    private func page(title: String, editable: Bool, things: [ListsThing], note: String, w: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if editable, s.naming || title.isEmpty {
                    TextField("", text: Binding(get: { store.book.lists.first { $0.id == s.open }?.name ?? "" }, set: { v in
                        let n = String(v.prefix(60))
                        ListsStore.shared.change { b in if let i = b.lists.firstIndex(where: { $0.id == s.open }) { b.lists[i].name = n } }
                    }), prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    .focused($naming)
                    .submitLabel(.done)
                    .onSubmit { s.naming = false }
                    .onAppear { naming = true }
                    .onChange(of: naming) { _, f in if !f { s.naming = false } }
                    .frame(minHeight: 44)
                } else {
                    Text(title).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .onTapGesture { if editable { Feel.tap(); s.naming = true } }
                }
                ForEach(things) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Group {
                                if let cc = t.cc, let f = Flags.square(cc.lowercased()) { f.resizable().interpolation(.high) } else { Color.clear }
                            }
                            .frame(width: 28, height: 28)
                            Text(t.name).font(.body).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                        }
                        // a note: not shown until its row is opened
                        if s.noted == t.id, !t.note.isEmpty {
                            Text(t.note).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
                                .padding(.leading, 40)
                        }
                    }
                    .frame(minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !t.note.isEmpty else { return }
                        Feel.tap()
                        withAnimation(Motion.quick) { s.noted = s.noted == t.id ? nil : t.id }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(width: w, alignment: .leading)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }
}

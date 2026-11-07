import SwiftUI
import simd

/// PLACES' WATER (7.5, 7.6; redesigned 7 Nov 16:37: the solar system means nothing in Places, no tiles).
/// What Places is about is your towns, things and own places, and the maps you look at them on, so that is what the
/// water holds. At 25% the caption: the map you are on and your number on it (its number opens your stamped places,
/// as before). At 50% and full: your maps, as rows on the water, the same rows as the Stamped list (a 28 pt mark, the
/// name in body, one grey line under it, 56 pt a row): All my places; the countries you have places in, most first;
/// the collections. The map you are on has its name in semibold. A tap shows that map and the water goes to 25%, so it
/// is framed where it is seen. Any other country is found with the head's search (no second search here, no section
/// words). The rows scroll only at full; below full a drag moves the water.
/// Not here yet (they need Lists): your own maps and New map, a row's hold menu (11.5's map card menu).
struct PlacesShelf: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    /// the caption's centre
    let captionY: CGFloat

    var body: some View {
        let L = water.layout
        // (the caption's foot is 65 pt under its centre; the rows start 8 pt under it)
        let foot = captionY + 65
        let fade = L.capsule.minY - 44
        let top = foot + 8
        PlacesMaps(water: water, map: map, bottom: L.H - fade + 24)
            .frame(width: L.W - 2 * L.sheetInset, height: max(0, L.H - top))
            .padding(.top, top)
            .frame(width: L.W, height: L.H, alignment: .top)
            // under the caption's soft edge at the top and the soft edge above the tabs at the bottom
            .mask { Self.band(top: foot - 8, bottom: fade, H: L.H) }
            .allowsHitTesting(water.stop != .quarter && water.stop != .closed)
            .onAppear { TownIndex.shared.load(); CollectionStore.shared.load() }
    }

    /// the band the rows show in: from under the caption's foot (a 16 pt soft edge) to the soft edge above the tabs
    /// (24 pt); nothing at all when the caption's foot is below that edge (the water at 25%)
    @ViewBuilder static func band(top: CGFloat, bottom: CGFloat, H: CGFloat) -> some View {
        let t1 = top + 16, t2 = max(t1, bottom - 24)
        if bottom <= t1 || H <= 0 {
            Color.clear
        } else {
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: max(0, top / H)),
                .init(color: .black, location: t1 / H),
                .init(color: .black, location: t2 / H),
                .init(color: .black.opacity(0), location: min(1, bottom / H)),
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// YOUR MAPS, one row each
struct PlacesMaps: View {
    let water: Water
    let map: MapController
    /// the room under the rows (the tabs' place)
    let bottom: CGFloat

    var body: some View {
        let L = water.layout
        let _ = map.townsVersion
        let _ = MarkStore.shared.changes
        let counts = Self.counts()
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(picks(counts), id: \.self) { p in row(p, counts) }
                Color.clear.frame(height: bottom)
            }
        }
        .contentMargins(.horizontal, 16 - L.sheetInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        // below full a drag is the water's, not the rows'
        .scrollDisabled(water.stop != .full)
    }

    /// your stamped towns, things and own places by country, in one pass over the marks
    static func counts() -> [String: Int] {
        // a thing's country: its country's things when they are loaded, else the collection it is a stop of (a
        // Formula 1 circuit stamped from its collection, its country's things never opened)
        var stopCC: [String: String] = [:]
        for c in CollectionStore.shared.all { for it in c.items { stopCC[it.key.id] = it.cc.lowercased() } }
        var n: [String: Int] = [:]
        for (k, s) in MarkStore.shared.marks where s.stamped && (k.kind == .town || k.kind == .yours || k.kind == .thing) {
            let cc = k.kind == .town ? String(k.id.prefix { $0 != "/" })
                : k.kind == .thing ? (ThingStore.shared.thing(k.id)?.cc ?? stopCC[k.id] ?? "") : OwnPlaces.shared.place(k.id)?.cc ?? ""
            if !cc.isEmpty { n[cc.lowercased(), default: 0] += 1 }
        }
        return n
    }

    /// All my places; the countries you have places in (most first, then A to Z); the collections
    private func picks(_ counts: [String: Int]) -> [MapController.PlacesPick] {
        guard let w = map.world else { return [.everywhere] }
        let n = { (i: Int) in counts[w.places[i].id.lowercased()] ?? 0 }
        let mine = w.places.indices.filter { w.places[$0].id != "aq" && n($0) > 0 }
            .sorted { n($0) != n($1) ? n($0) > n($1) : w.places[$0].n.localizedStandardCompare(w.places[$1].n) == .orderedAscending }
        return [.everywhere] + mine.map { .country($0) } + CollectionStore.shared.all.map { .collection($0.id) }
    }

    private func row(_ p: MapController.PlacesPick, _ counts: [String: Int]) -> some View {
        let current = map.placesPick == p
        let (name, line) = words(p, counts)
        return HStack(spacing: 12) {
            mark(p).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(current ? .body.weight(.semibold) : .body).foregroundStyle(Palette.ink).lineLimit(1)
                Text(line).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            water.go(.quarter)
            map.showPlacesMap(p)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(line)")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    /// a country's square flag (as the Stamped list's); All my places the Places mark; a collection the list mark, or
    /// its country's flag when it is all in one country
    @ViewBuilder private func mark(_ p: MapController.PlacesPick) -> some View {
        switch p {
        case .country(let i):
            if let f = Flags.square(map.world?.places[i].id.lowercased() ?? "") { f.resizable().interpolation(.high) } else { Color.clear }
        case .collection(let id):
            if let c = CollectionStore.shared.collection(id), c.scope != "world", let f = Flags.square(c.scope.lowercased()) {
                f.resizable().interpolation(.high)
            } else {
                Icon5(key: "lists-lists", ink: Palette.ink, size: 22)
            }
        default:
            Icon5(key: "map-places", ink: Palette.ink, size: 22)
        }
    }

    private func words(_ p: MapController.PlacesPick, _ counts: [String: Int]) -> (String, String) {
        let places = { (k: Int) in k == 1 ? "1 place" : "\(k.formatted()) places" }
        switch p {
        case .country(let i):
            let w = map.world
            return (w?.places[i].n ?? "", places(counts[w?.places[i].id.lowercased() ?? ""] ?? 0))
        case .collection(let id):
            let c = CollectionStore.shared.collection(id)
            return (c?.title ?? "", "\(map.stampedTowns(on: p).formatted()) of \((c?.items.count ?? 0).formatted())")
        default:
            return (p.title, places(map.stampedTowns(on: .everywhere)))
        }
    }
}

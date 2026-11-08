import SwiftUI
import simd

/// PLACES' WATER (7.5, 7.6): what Places is about is your towns, things and own places, and the maps you look at them
/// on. At 25% the caption: the map you are on and your number on it (its number opens your places on it). From 50% the
/// shelf of maps (PlacesMaps): each map as its own shape on the water, a sideways row per kind.
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

/// THE SHELF (7.5): the maps Places looks at, each drawn as its own shape in ink
/// straight on the
/// water (a country's outline, a continent's, the world's for Everywhere, a collection's stops as points), its name under
/// it; no box, no tile, no list. One sideways row per kind: your maps (Everywhere, the countries you have places in,
/// the collections you have places in), the continents, then every collection. The map you are on is the darker shape
/// with its name in semibold. A tap shows that map (the water to 25%, so it is framed where it is seen). The rows go
/// sideways at every stop; the shelf scrolls down only at full, where the rest of it is.
struct PlacesMaps: View {
    let water: Water
    let map: MapController
    /// the room under the rows (the tabs' place)
    let bottom: CGFloat

    static let continents = ["Africa", "Antarctica", "Asia", "Europe", "North America", "Oceania", "South America"]

    var body: some View {
        let L = water.layout
        let _ = map.townsVersion
        let _ = MarkStore.shared.changes
        let counts = Self.counts()
        let pick = map.placesPick
        // below full only whole shelves, none cut by the soft edge over the tabs
        let cut: CGFloat? = water.stop == .full ? nil : L.capsule.minY - 44 - 14
        let mine = yours(counts)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                shelf("Your maps", mine, pick).whole(cut)
                shelf("Continents", Self.continents.map { .continent($0) }, pick).whole(cut)
                shelf("Collections", CollectionStore.shared.all.map { .collection($0.id) }, pick).whole(cut)
                Color.clear.frame(height: bottom)
            }
        }
        .scrollIndicators(.hidden)
        // below full a drag up or down is the water's, not the shelf's
        .scrollDisabled(water.stop != .full)
    }

    /// one kind of map: its name, then its maps sideways (the one you are on brought into view)
    private func shelf(_ name: String, _ picks: [MapController.PlacesPick], _ current: MapController.PlacesPick) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(picks, id: \.self) { p in item(p, current: p == current).id(p) }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .onAppear { if picks.contains(current) { proxy.scrollTo(current, anchor: .center) } }
            }
        }
        .padding(.top, 6)
        // (two kinds fit at 50%: the continents under your maps, 9 Nov; at 112 pt the second was left under the edge)
        .frame(height: 100, alignment: .top)
    }

    /// a map: its shape 44 pt high in a 76 pt column, its name under it
    private func item(_ p: MapController.PlacesPick, current: Bool) -> some View {
        VStack(spacing: 6) {
            shape(p)
                .foregroundStyle(Palette.ink.opacity(current ? 1 : 0.45))
                .frame(width: 64, height: 44)
            Text(title(p)).font(current ? .footnote.weight(.semibold) : .footnote)
                .foregroundStyle(Palette.ink.opacity(current ? 1 : 0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 76)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !current else { Feel.refuse(); return }
            Feel.tap()
            water.go(.quarter)
            map.showPlacesMap(p)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title(p))
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    /// what the shape of a map is: its land, or a collection's stops
    @ViewBuilder private func shape(_ p: MapController.PlacesPick) -> some View {
        if let w = map.world {
            switch p {
            case .collection(let id):
                if let c = CollectionStore.shared.collection(id), let d = MapShapes.points("c:" + id, c.items.map(\.at)) {
                    StopsShape(points: d.pts, aspect: d.aspect)
                }
            default:
                let key: String = { switch p {
                    case .everywhere: return "world"
                    case .country(let i): return "p:" + w.places[i].id
                    case .continent(let k), .region(let k): return "k:" + k
                    case .collection(let id): return "c:" + id
                } }()
                if let s = MapShapes.land(key, places: map.members(of: p), world: w) {
                    FittedShape(path: s.path, aspect: s.aspect).fill(style: FillStyle(eoFill: false))
                }
            }
        }
    }

    private func title(_ p: MapController.PlacesPick) -> String {
        if case .country(let i) = p { return map.world?.places[i].n ?? "" }
        return p.title
    }

    /// Everywhere; the countries you have places in (most first, then A to Z); the collections you have places in
    private func yours(_ counts: [String: Int]) -> [MapController.PlacesPick] {
        guard let w = map.world else { return [.everywhere] }
        let n = { (i: Int) in counts[w.places[i].id.lowercased()] ?? 0 }
        let mine = w.places.indices.filter { w.places[$0].id != "aq" && n($0) > 0 }
            .sorted { n($0) != n($1) ? n($0) > n($1) : w.places[$0].n.localizedStandardCompare(w.places[$1].n) == .orderedAscending }
        let cols = CollectionStore.shared.all.filter { map.stampedTowns(on: .collection($0.id)) > 0 }.map { MapController.PlacesPick.collection($0.id) }
        // the country you are looking at is on it even with nothing of yours in it yet
        var out: [MapController.PlacesPick] = [.everywhere] + mine.map { .country($0) } + cols
        if !out.contains(map.placesPick), case .country = map.placesPick { out.insert(map.placesPick, at: 1) }
        return out
    }

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

}

/// a collection's stops: one 4 pt dot each, in their own box
struct StopsShape: View {
    let points: [CGPoint]
    let aspect: CGFloat
    var body: some View {
        GeometryReader { g in
            let r = g.size
            let w = min(r.width - 8, (r.height - 8) * aspect), h = w / max(aspect, 0.001)
            let k = max(w, h), x0 = (r.width - w) / 2, y0 = (r.height - h) / 2
            Path { p in
                for q in points { p.addEllipse(in: CGRect(x: x0 + q.x * k - 2, y: y0 + q.y * k - 2, width: 4, height: 4)) }
            }
            .fill()
        }
    }
}


extension View {
    /// WHOLE ROWS ONLY (a sheet below full, where its rows do not scroll): hidden when its bottom (plus `need`, the room
    /// for what must come with it) is past `cut`, in the screen's points (nil: always shown)
    func whole(_ cut: CGFloat?, need: CGFloat = 0) -> some View {
        visualEffect { content, proxy in
            content.opacity(cut.map { proxy.frame(in: .global).maxY + need > $0 ? 0 : 1 } ?? 1)
        }
    }
}

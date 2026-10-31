import SwiftUI
import simd

/// THE SHELF (7.5) AND THE ATLAS (7.6), Places' water above 25%.
/// The shelf: at 50%, the maps that fit where you are looking, one sideways row of cards snapping card by card, 12 pt
/// under the caption's foot, riding the water's edge with it and passing under the soft edge above the tabs as a
/// scrolled row does (A7.4). Worked out when the sheet rises to 50%, never while you look at it. A card: its picture
/// (corners 20: the map's land on our sea, your towns on it lime), its title and your number under it on the water;
/// the current map's card 4 pt higher. A tap makes it the current map (A7.2), the water going to 25% so the map is
/// framed where it is seen (author's call).
/// The atlas: at full, every map in sections, three columns (`(W - 56) / 3`), from 12 pt under the caption's foot
/// (the caption stays under the head at full). From 50% to full the shelf rides up and passes under the soft edge at
/// the caption's foot while the atlas rises into view (A7.5); down is the exact reverse.
/// Not here yet: Around you (location), your maps (lists), collections (D7), the AI's maps, New map, Collections by
/// country, search over maps.
struct PlacesShelf: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    /// the caption's centre
    let captionY: CGFloat
    @State private var cards: [MapController.PlacesPick] = []
    private static let side: CGFloat = 132
    private static let rowH: CGFloat = side + 64

    var body: some View {
        let L = water.layout
        // 0 at 50% (or lower), 1 at full
        let f = min(1, max(0, (L.top(.half) - form.top) / max(1, L.top(.half) - L.top(.full))))
        // (the caption's foot is 65 pt under its centre and a row is placed 14 pt under where it is asked for, both
        // measured on the Pro Max; the 4 pt the current card rises by is inside the row)
        let foot = captionY + 65
        let shelfTop = foot + 12 - 4 - 14 - f * (Self.rowH + 40)
        let atlasFrom = foot + 12 - 4 - 14 + Self.rowH + 24
        let atlasTop = atlasFrom + (foot + 12 - 14 - atlasFrom) * f
        // (the row's last visible line is 44 pt above the tabs' top, so at 25% none of it shows, with room: 31 Oct 02:07,
        // the cards' tops were peeking behind the tabs; at 50% the whole row is still clear of it)
        let fade = L.capsule.minY - 44
        ZStack(alignment: .top) {
            shelf(L)
                .padding(.top, shelfTop)
                .frame(width: L.W, height: L.H, alignment: .top)
                .allowsHitTesting(f < 0.02 && shelfTop + Self.side < fade - 24)
            if f > 0.01 {
                PlacesAtlas(water: water, map: map, here: Array(cards.dropFirst()), bottom: L.H - fade + 24)
                    .frame(width: L.W - 2 * L.sheetInset, height: max(0, L.H - atlasTop))
                    .padding(.top, atlasTop)
                    .frame(width: L.W, height: L.H, alignment: .top)
                    .allowsHitTesting(f > 0.98)
            }
        }
        // under the caption's soft edge at the top (P3) and the soft edge above the tabs at the bottom
        .mask { band(top: foot - 20, bottom: fade, H: L.H) }
        .onAppear { TownIndex.shared.load(); work() }
        .onChange(of: water.stop) { _, s in if s == .half { work() } }
    }

    /// the band the shelf and atlas show in: from under the caption's foot (a 16 pt soft edge) to the soft edge above
    /// the tabs (24 pt); nothing at all when the caption's foot is below that edge (the water at 25%)
    @ViewBuilder private func band(top: CGFloat, bottom: CGFloat, H: CGFloat) -> some View {
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

    private func shelf(_ L: Layout) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(cards, id: \.self) { c in MapCard(water: water, map: map, pick: c, side: Self.side) }
            }
            .scrollTargetLayout()
            .padding(.top, 4)
            .frame(height: Self.rowH, alignment: .top)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .frame(width: L.W - 2 * L.sheetInset, height: Self.rowH)
        .clipped()
    }

    /// THE CARDS, in order (7.5): Everywhere; Here (the country under the room's middle, its world region, its
    /// continent); the current map kept on the shelf even when it is not one of these
    private func work() {
        guard let w = map.world else { return }
        let L = water.layout
        let room = L.room(sheetTop: L.top(.quarter))
        let mid = map.mapPoint(CGPoint(x: L.W / 2, y: (room.lowerBound + room.upperBound) / 2))
        var out: [MapController.PlacesPick] = [.everywhere]
        if let i = w.place(at: SIMD2(Float(mid.x), Float(mid.y))) ?? map.placeOpen {
            out.append(.country(i))
            if let r = WorldRegions.of(w.places[i].id) { out.append(.region(r)) }
            if let k = w.places[i].cont { out.append(.continent(k)) }
        }
        let now = map.placesPick
        if !out.contains(now) { out.insert(now, at: 1) }
        cards = out
    }
}

/// THE ATLAS (7.6): every map, in sections (the sections 7.6 lists that exist now: Here, Continents, World regions,
/// Countries A to Z), three columns 12 pt apart, 16 pt margins, rows 20 pt apart; a section's name 15 pt semibold black
/// 50%, 24 pt above its cards
struct PlacesAtlas: View {
    let water: Water
    let map: MapController
    /// Here's cards (the shelf's, without Everywhere)
    let here: [MapController.PlacesPick]
    /// the room under the content (the tabs' place)
    let bottom: CGFloat

    var body: some View {
        let L = water.layout
        let cw = ((L.W - 56) / 3).rounded(.down)
        let cols = Array(repeating: GridItem(.fixed(cw), spacing: 12, alignment: .top), count: 3)
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                grid([.everywhere], cols, cw)
                if !here.isEmpty { section("Here", here, cols, cw) }
                section("Continents", MapController.continents.map { .continent($0) }, cols, cw)
                section("World regions", Self.regions.map { .region($0) }, cols, cw)
                section("Countries", countries, cols, cw)
                Color.clear.frame(height: bottom)
            }
            .padding(.top, 4)
        }
        .contentMargins(.horizontal, 16 - L.sheetInset, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    private static let regions = Array(Set(WorldRegions.table.values)).sorted()
    private var countries: [MapController.PlacesPick] {
        guard let w = map.world else { return [] }
        return w.places.indices.filter { w.places[$0].id != "aq" }
            .sorted { w.places[$0].n.localizedStandardCompare(w.places[$1].n) == .orderedAscending }
            .map { .country($0) }
    }

    private func section(_ name: String, _ picks: [MapController.PlacesPick], _ cols: [GridItem], _ cw: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
                .padding(.top, 24).padding(.bottom, 12)
            grid(picks, cols, cw)
        }
    }
    private func grid(_ picks: [MapController.PlacesPick], _ cols: [GridItem], _ cw: CGFloat) -> some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 20) {
            ForEach(picks, id: \.self) { p in MapCard(water: water, map: map, pick: p, side: cw) }
        }
    }
}

/// A MAP'S CARD (7.5, 7.6): its picture, its title (15 pt semibold, two lines at most) and your number (12 pt black
/// 50%) under it; the current map's 4 pt higher. A tap: the current map, the water at 25%
struct MapCard: View {
    let water: Water
    let map: MapController
    let pick: MapController.PlacesPick
    let side: CGFloat

    var body: some View {
        let current = map.placesPick == pick
        _ = map.townsVersion
        let n = map.stampedTowns(on: pick)
        var number = "\(n)"
        if case .country(let i) = pick, let cc = map.world?.places[i].id.lowercased(), let all = map.townScenes[cc]?.towns.count {
            number += " of \(all.formatted())"
        }
        return VStack(alignment: .leading, spacing: 0) {
            ShelfPicture(map: map, pick: pick, side: side, ready: TownIndex.shared.ready, version: map.townsVersion)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text(number).font(.caption).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .frame(width: side, alignment: .leading)
        .offset(y: current ? -4 : 0)
        .animation(Motion.quick, value: current)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            water.go(.quarter)
            map.showPlacesMap(pick)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var title: String {
        if case .country(let i) = pick { return map.world?.places[i].n ?? "" }
        return pick.title
    }
}

/// A CARD'S PICTURE: our map's piece (MapPicture, drawn off the main thread once per map, size and marks, kept);
/// until it has come, the sea's blue
struct ShelfPicture: View {
    let map: MapController
    let pick: MapController.PlacesPick
    let side: CGFloat
    let ready: Bool
    let version: Int
    @State private var image: CGImage?
    private static var kept: [String: CGImage] = [:]
    @Environment(\.displayScale) private var scale

    var body: some View {
        let key = "\(pick)|\(side)|\(version)|\(ready)"
        Group {
            if let i = Self.kept[key] ?? image {
                Image(decorative: i, scale: scale).resizable()
            } else {
                Palette.blue
            }
        }
        .task(id: key) {
            guard Self.kept[key] == nil, let w = map.world, let box = map.box(of: pick) else { return }
            let own: Set<Int>? = map.members(of: pick).map(Set.init)
            let ids: Set<String>? = own.map { Set($0.map { w.places[$0].id.lowercased() }) }
            // your marks on it
            var dots: [SIMD2<Float>] = []
            for (k, st) in MarkStore.shared.marks where st.stamped {
                if k.kind == .town, let h = TownIndex.shared.hit(k.id), ids?.contains(h.file) ?? true {
                    dots.append(EqualEarth.project(lon: h.lon, lat: h.lat))
                } else if k.kind == .yours, let o = OwnPlaces.shared.place(k.id), ids?.contains(o.cc) ?? true {
                    dots.append(o.point)
                }
            }
            let relief = map.relief, every = pick == .everywhere, px = Int(side * scale)
            let made = await Task.detached(priority: .utility) {
                MapPicture.draw(world: w, relief: relief, box: box, own: own, everywhere: every, dots: dots, px: px)
            }.value
            guard let made else { return }
            Self.kept[key] = made
            image = made
        }
    }
}

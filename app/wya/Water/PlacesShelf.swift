import SwiftUI
import simd

/// PLACES' WATER (7.5, 7.6; redesigned 7 Nov 16:37: the solar system means nothing in Places, no tiles).
/// What Places is about is your towns, things and own places, and the maps you look at them on, so that is what the
/// water holds. At 25% the caption: the map you are on and your number on it (its number opens your stamped places,
/// as before). At 50% and full: your maps, as rows on the water, the same rows as the Stamped list (a 28 pt mark, the
/// name in body, one grey line under it, 56 pt a row): Everywhere; the countries you have places in, most first;
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
        let pick = map.placesPick
        // below full the rows do not scroll: only whole rows show, none cut by the soft edge above the tabs (a heading
        // only with a row under it)
        let cut: CGFloat? = water.stop == .full ? nil : L.capsule.minY - 44 - 14
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if pick == .everywhere {
                    // EVERYWHERE: your countries, then your collections, each under its own heading (the map you are on is
                    // the caption's; it is not a row of itself, 8 Nov)
                    let all = picks(counts)
                    let countries = all.filter { if case .country = $0 { return true } else { return false } }
                    let collections = all.filter { if case .collection = $0 { return true } else { return false } }
                    if !countries.isEmpty { heading("Countries").whole(cut, need: 56); ForEach(countries, id: \.self) { p in row(p, counts).whole(cut) } }
                    if !collections.isEmpty { heading("Collections").whole(cut, need: 56); ForEach(collections, id: \.self) { p in row(p, counts).whole(cut) } }
                } else {
                    // INSIDE A COUNTRY, A COLLECTION OR A CONTINENT: the way back up first, then your places on this map
                    backRow.whole(cut)
                    let rows = placeRows(pick)
                    heading("Your places").whole(cut, need: 44)
                    if rows.isEmpty {
                        Text("None stamped yet").font(.body).foregroundStyle(Palette.ink.opacity(0.5))
                            .frame(minHeight: 44, alignment: .leading)
                            .whole(cut)
                    }
                    ForEach(rows, id: \.key) { r in placeRow(r).whole(cut) }
                }
                Color.clear.frame(height: bottom)
            }
        }
        // 16 pt inside the water, as the Stamped list's rows (the box already starts at the water's edge)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        // below full a drag is the water's, not the rows'
        .scrollDisabled(water.stop != .full)
    }

    /// a section's heading, as the Stamped list's ("Countries", "Collections", "Your places")
    private func heading(_ w: String) -> some View {
        Text(w).font(.headline).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .bottomLeading)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// back up to Everywhere (the map's own path: Everywhere, then a country, a collection or a continent)
    private var backRow: some View {
        HStack(spacing: 12) {
            Icon5(key: "back", ink: Palette.ink, size: 20).frame(width: 28, height: 28)
            Text("Everywhere").font(.body).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { Feel.tap(); water.go(.quarter); map.showPlacesMap(.everywhere) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Back to Everywhere")
        .accessibilityAddTraits(.isButton)
    }

    struct PlaceRow { let key: PlaceKey; let name: String; let line: String; let cc: String }

    /// your stamped towns, things, own places (and a collection's stops) on this map, A to Z
    private func placeRows(_ pick: MapController.PlacesPick) -> [PlaceRow] {
        guard let w = map.world else { return [] }
        let marks = MarkStore.shared
        if case .collection(let id) = pick, let c = CollectionStore.shared.collection(id) {
            return c.items.filter { marks.state($0.key).stamped }
                .map { PlaceRow(key: $0.key, name: $0.name, line: CollectionStore.line($0), cc: $0.cc.lowercased()) }
        }
        let ids: Set<String>? = map.members(of: pick).map { Set($0.map { w.places[$0].id.lowercased() }) }
        func country(_ cc: String) -> String { w.placeIndex[cc].map { w.places[$0].n } ?? "" }
        var out: [PlaceRow] = []
        for (k, st) in marks.marks where st.stamped {
            switch k.kind {
            case .town:
                let cc = String(k.id.prefix { $0 != "/" })
                guard ids?.contains(cc) ?? true else { continue }
                let name = map.townScenes[cc].flatMap { sc in sc.index[k.id].map { sc.towns[$0].name } } ?? TownIndex.shared.hit(k.id)?.name
                if let name { out.append(PlaceRow(key: k, name: name, line: "Town · \(country(cc))", cc: cc)) }
            case .thing:
                // (a collection's stop that isn't among the things, a circuit, is found in its collection)
                let found = ThingStore.shared.thing(k.id).map { ($0.0, $0.1.name) } ?? ThingIndex.shared.hit(k.id).map { ($0.file, $0.name) }
                    ?? CollectionStore.shared.item(k).map { ($0.cc, $0.name) }
                guard let (cc, name) = found, ids?.contains(cc.lowercased()) ?? true else { continue }
                out.append(PlaceRow(key: k, name: name, line: country(cc.lowercased()), cc: cc.lowercased()))
            case .yours:
                guard let o = OwnPlaces.shared.place(k.id), ids?.contains(o.cc.lowercased()) ?? true else { continue }
                out.append(PlaceRow(key: k, name: o.name, line: "Your place · \(country(o.cc.lowercased()))", cc: o.cc.lowercased()))
            default: continue
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func placeRow(_ r: PlaceRow) -> some View {
        HStack(spacing: 12) {
            Group {
                if let f = Flags.square(r.cc) { f.resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                Text(r.line).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            water.go(.quarter)
            switch r.key.kind {
            case .town: map.showTown(file: r.cc, id: r.key.id)
            case .thing:
                // a collection's stop with no thing behind it (a circuit): the camera comes to its own point
                if ThingStore.shared.thing(r.key.id) == nil, let it = CollectionStore.shared.item(r.key), let i = map.world?.placeIndex[r.cc] {
                    let d: Float = 2
                    map.showBox(SIMD4(it.at.x - d, it.at.y - d, it.at.x + d, it.at.y + d), place: i)
                } else {
                    map.showThing(file: r.cc, id: String(r.key.id.dropFirst(3)))
                }
            case .yours: map.showOwn(r.key.id)
            default: break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.name), \(r.line)")
        .accessibilityAddTraits(.isButton)
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

    /// Everywhere; the countries you have places in (most first, then A to Z); the collections
    private func picks(_ counts: [String: Int]) -> [MapController.PlacesPick] {
        guard let w = map.world else { return [.everywhere] }
        let n = { (i: Int) in counts[w.places[i].id.lowercased()] ?? 0 }
        let mine = w.places.indices.filter { w.places[$0].id != "aq" && n($0) > 0 }
            .sorted { n($0) != n($1) ? n($0) > n($1) : w.places[$0].n.localizedStandardCompare(w.places[$1].n) == .orderedAscending }
        return mine.map { .country($0) } + CollectionStore.shared.all.map { .collection($0.id) }
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

    /// a country's square flag (as the Stamped list's); Everywhere the Places mark; a collection the list mark, or
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


extension View {
    /// WHOLE ROWS ONLY (a sheet below full, where its rows do not scroll): hidden when its bottom (plus `need`, the room
    /// for what must come with it) is past `cut`, in the screen's points (nil: always shown)
    func whole(_ cut: CGFloat?, need: CGFloat = 0) -> some View {
        visualEffect { content, proxy in
            content.opacity(cut.map { proxy.frame(in: .global).maxY + need > $0 ? 0 : 1 } ?? 1)
        }
    }
}

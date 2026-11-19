import SwiftUI

/// PLACES' WATER. Laid out as Pins' water is, so the two read as one app: - THE MENU: on the name line, where Pins
/// says its map's name; under it the sets as rows, one under the other: the set's name, and at its right yours of it 
/// once you have one, and the arrow that says it opens. No icons, no tiles, no capsules, no count of every place
/// there is. - A SET (a row tapped): the caption says the set, yours of it and of how many; the back arrow at the
/// sheet's top left brings the menu back. Under the caption the set's own kinds as rows (Seas and oceans: Oceans,
/// Seas, Gulfs and bays, Straits), the one picked a black band edge to edge with white words, as the map shown in
/// Pins; a second tap shows all of the set again. Our twelve kinds are never a row: they file things. Where is the
/// map's job: a country tapped narrows the set to it.
struct PlacesSheet: View {
    let water: Water
    let map: MapController
    /// the caption's centre
    let captionY: CGFloat
    /// the water's top edge
    let top: CGFloat
    /// the caption's words are up (the back arrow is there with them, never alone)
    let captionUp: Bool

    static let rowH: CGFloat = 52
    /// the gaps between the rows, measured (EdgeRows): the list's visible height ends in one
    @State private var cuts: [CGFloat] = []

    var body: some View {
        let L = water.layout
        let picked = map.placesPicked
        let store = CollectionStore.shared
        // (the name line as Pins has it: the water's top, never under the head)
        let lineTop = max(top, L.headBottom + 8)
        // (the menu's rows under; a set's kinds under its caption's count)
        let from = picked ? captionY + 62 : lineTop + 20
        let to = L.capsule.minY - 12
        let rows = PlacesRows.rows(map: map, water: water)
        ZStack(alignment: .topLeading) {
            // (the rows are there once the sets have been read, and only with room for one whole row at least; the
            // rest scroll, going out softly at the foot)
            let places = picked ? Self.places(map: map) : []
            if store.ready, !rows.isEmpty || !places.isEmpty, to - from >= 44 {
                ScrollView(.vertical) {
                  VStack(spacing: 8) {
                    if !rows.isEmpty {
                    let w = L.W - 2 * L.sheetInset - 24
                    setGrid(rows, columns: rows.contains { Self.wide($0.title, small: picked, part: w / 2) } ? 1 : 2, width: w, small: picked)
                    .padding(.vertical, 4)
                    .edgeRow()
                    }
                    // A SET'S PLACES: the best known first, each its name and its country; a tap shows it on the map,
                    // the water at 25% (12 pt between rows: a gap for the list's end to fall in, so it ends on a
                    // whole row, PL7)
                    LazyVStack(spacing: 12) {
                        ForEach(places, id: \.id) { it in
                            Button {
                                Feel.tick()
                                water.go(.quarter)
                                map.showSetPlace(map.placesKind == CollectionStore.capitals ? CollectionStore.capitals : map.placesSet, id: it.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.short).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                                    let land = Self.country(it, map: map)
                                    if !land.isEmpty { Text(land).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1) }
                                }
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity, minHeight: Self.rowH, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .edgeRow()
                        }
                    }
                  }
                  .coordinateSpace(name: EdgeRows.space)
                  .onPreferenceChange(EdgeRows.self) { cuts = EdgeRows.cuts($0) }
                }
                // WHOLE ROWS ONLY: the visible height ends in the gap between two rows, as Details' does, its 16 pt
                // soft foot over that gap, and a scroll stops on a gap (it ended part way through under a long fade)
                .scrollBlur()
                .scrollIndicators(.hidden)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
                    }
                }
                .scrollTargetBehavior(GapSnap(cuts: cuts))
                .frame(width: L.W - 2 * L.sheetInset, height: EdgeRows.fit(to - from, cuts: cuts))
                .position(x: L.W / 2, y: from + EdgeRows.fit(to - from, cuts: cuts) / 2)
                .allowsHitTesting(water.stop == .half)
            }
            if picked, captionUp {
                // the back arrow, as on Map settings' pages: 22 pt in a 44 pt square, on the caption's name's line
                // (the menu's rows need the water at 50%: a set that sent it down to 25% brings it back up with them)
                Button { Feel.tap(); map.clearPlacesSet(); if water.stop == .quarter { water.go(.half) } } label: {
                    Icon5(key: "back", ink: Palette.ink, size: 22).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .position(x: L.sheetInset + 8 + 22, y: captionY - 41)
            }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        .transaction { $0.animation = nil }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear { ThingIndex.shared.load(); CollectionStore.shared.load() }
    }

    /// the sets (or a set's kinds) in rows of `columns` equal parts, each word whole in the middle of its part
    @ViewBuilder private func setGrid(_ rows: [PlacesRows.Row], columns: Int, width: CGFloat, small: Bool) -> some View {
        let lines = stride(from: 0, to: rows.count, by: columns).map { Array(rows[$0 ..< min($0 + columns, rows.count)]) }
        VStack(spacing: 0) {
            ForEach(lines.indices, id: \.self) { k in
                HStack(spacing: 0) {
                    ForEach(lines[k]) { r in
                        Button { Feel.tick(); r.act() } label: {
                            Text(r.title)
                                .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                                .foregroundStyle(r.on ? Palette.white : Palette.ink)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 12).frame(height: 34)
                                .background { if r.on { Capsule().fill(Palette.ink) } }
                                .frame(width: width / CGFloat(columns), height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(r.count.isEmpty ? r.title : r.title + ", " + r.count)
                        .accessibilityAddTraits(r.on ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
        .frame(width: width)
    }
    private static func wide(_ t: String, small: Bool, part: CGFloat) -> Bool {
        // (measured at the size the sheet draws: its type stops at xxxLarge)
        let cat = UIApplication.shared.preferredContentSizeCategory
        let f = UIFont.preferredFont(forTextStyle: small ? .subheadline : .body,
                                     compatibleWith: UITraitCollection(preferredContentSizeCategory: cat > .extraExtraExtraLarge ? .extraExtraExtraLarge : cat))
        let bold = UIFont.systemFont(ofSize: f.pointSize, weight: .semibold)
        return (t as NSString).size(withAttributes: [.font: bold]).width + 24 > part
    }

    /// the picked set's places (its kind's, when one is picked), in the set's own order (best known first); 300 at most
    static func places(map: MapController) -> [CollectionStore.Item] {
        // (the capitals are their own list, each keyed as its town)
        let kind = map.placesKind, capitals = kind == CollectionStore.capitals
        guard let c = CollectionStore.shared.collection(capitals ? CollectionStore.capitals : map.placesSet) else { return [] }
        return Array(c.items.lazy.filter { capitals || kind == nil || $0.type == kind }.prefix(300))
    }
    /// its country, or the two it lies between; a sea or a range says none
    static func country(_ it: CollectionStore.Item, map: MapController) -> String {
        let named = { (cc: String) -> String? in map.world.flatMap { w in (w.placeIndex[cc] ?? w.placeIndex[cc.uppercased()]).map { w.places[$0].n } } }
        let ccs = (it.ccs.isEmpty ? [it.cc] : it.ccs).compactMap(named)
        return ccs.count <= 2 ? ccs.sorted().joined(separator: ", ") : ""
    }
}

/// the rows: the sets, or the picked set's kinds
struct PlacesRows: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        /// yours of it, (empty until you have one)
        let count: String
        /// a set (opens) or a kind (narrows)
        let opens: Bool
        let on: Bool
        let act: () -> Void
    }
    let rows: [Row]
    let height: CGFloat

    @MainActor static func rows(map: MapController, water: Water) -> [Row] {
        let store = CollectionStore.shared
        guard map.placesPicked else {
            return store.menu.map { id in
                Row(id: "set:" + id, title: store.title(id), count: Self.yours(id, map: map), opens: true, on: false) {
                    map.showPlacesSet(id)
                }
            }
        }
        let set = map.placesSet, kind = map.placesKind
        return store.types(set).compactMap { t in
            guard t.count == 2 else { return nil }
            return Row(id: "kind:" + set + ":" + t[0], title: t[1], count: "", opens: false, on: kind == t[0]) {
                map.showPlacesType(kind == t[0] ? nil : t[0])
            }
        }
    }

    /// yours of a set and of how many it lists; the towns, yours only (no one holds a list of the world's towns);
    /// nothing while you have none of it. Worked out once per change of your stamps
    @MainActor private static func yours(_ id: String, map: MapController) -> String {
        let changes = MarkStore.shared.changes
        if seen != changes { counts = [:]; seen = changes }
        if let s = counts[id] { return s }
        let s: String
        if id == CollectionStore.towns {
            let n = map.stampedTowns(on: .everywhere)
            s = n > 0 ? SheetContent.number(n) : ""
        } else if let c = CollectionStore.shared.collection(id) {
            let n = c.items.filter { MarkStore.shared.state($0.key).stamped }.count
            s = n > 0 ? SheetContent.number(n) + " of " + SheetContent.number(c.total) : ""
        } else {
            s = ""
        }
        counts[id] = s
        return s
    }
    @MainActor private static var counts: [String: String] = [:]
    @MainActor private static var seen = -1

    var body: some View {
        let more = CGFloat(rows.count) * PlacesSheet.rowH > height + 0.5
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row($0) }
            }
            .scrollTargetLayout()
        }
        .scrollBlur()
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollDisabled(!more)
    }

    private func row(_ r: Row) -> some View {
        let ink = r.on ? Color.white : Palette.ink
        return Button {
            Feel.tick()
            r.act()
        } label: {
            HStack(spacing: 10) {
                Text(r.title).font(.body).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 8)
                if !r.count.isEmpty {
                    Text(r.count).font(.body).foregroundStyle(ink.opacity(0.5)).lineLimit(1).monospacedDigit()
                }
                if r.opens {
                    Icon5(key: "forward", ink: ink.opacity(0.5), size: 15)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: PlacesSheet.rowH)
            .background { Rectangle().fill(r.on ? Palette.ink : .clear) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.count.isEmpty ? r.title : r.title + ", " + r.count)
        .accessibilityAddTraits(r.on ? [.isButton, .isSelected] : .isButton)
    }
}

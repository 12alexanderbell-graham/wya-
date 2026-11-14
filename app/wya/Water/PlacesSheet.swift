import SwiftUI

/// PLACES' WATER: a menu of the types of place to look at; one picked, the map shows those places and the sheet
/// becomes that set's. Never full screen.
///
/// Laid out as Pins' water is, so the two read as one app (13 Nov: Places and Pins replaced, never kept as they were):
/// - THE MENU: "Places" on the name line, where Pins says its map's name; under it the sets as rows, one under the
///   other: the set's name, and at its right yours of it ("12 of 59") once you have one, and the arrow that says it
///   opens. No icons, no tiles, no capsules, no count of every place there is.
/// - A SET (a row tapped): the caption says the set, yours of it and of how many; the back arrow at the sheet's top
///   left brings the menu back. Under the caption the set's own kinds as rows (Seas and oceans: Oceans, Seas, Gulfs and
///   bays, Straits), the one picked a black band edge to edge with white words, as the map shown in Pins; a second tap
///   shows all of the set again.
/// Our twelve kinds are never a row: they file things. Where is the map's job: a country tapped narrows the set to it.
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

    var body: some View {
        let L = water.layout
        let picked = map.placesPicked
        let store = CollectionStore.shared
        // (the name line as Pins has it: the water's top, never under the head)
        let lineTop = max(top, L.headBottom + 8)
        // (the menu's rows under "Places"; a set's kinds under its caption's count)
        let from = picked ? captionY + 62 : lineTop + 58
        let to = L.capsule.minY - 12
        let rows = PlacesRows.rows(map: map, water: water)
        ZStack(alignment: .topLeading) {
            if !picked, store.ready {
                Text("Places")
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .position(x: L.W / 2, y: lineTop + 31)
                    // (14 Nov: closing, the word rode down into the capsule and stayed over the tab buttons) gone
                    // before it reaches the capsule
                    .opacity(Double(min(1, max(0, (L.capsule.minY - (lineTop + 31) - 24) / 40))))
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isHeader)
            }
            // (the rows are there once the sets have been read, and only with room for one whole row at least; the
            // rest scroll, going out softly at the foot)
            if store.ready, !rows.isEmpty, to - from >= Self.rowH {
                PlacesRows(rows: rows, height: to - from)
                    .frame(width: L.W - 2 * L.sheetInset, height: to - from)
                    .position(x: L.W / 2, y: (from + to) / 2)
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
}

/// the rows: the sets, or the picked set's kinds
struct PlacesRows: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        /// yours of it, "12 of 59" (empty until you have one)
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
            // (a set with kinds keeps the water at 50% for them; one with none has nothing more to pick here, so the
            // water goes down to 25% and the map of its places has the screen)
            return store.menu.map { id in
                Row(id: "set:" + id, title: store.title(id), count: Self.yours(id, map: map), opens: true, on: false) {
                    map.showPlacesSet(id)
                    if store.types(id).isEmpty { water.go(.quarter) }
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

    /// yours of a set and of how many it lists ("12 of 59"); the towns, yours only (no one holds a list of the
    /// world's towns); nothing while you have none of it. Worked out once per change of your stamps
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
        // (the soft foot only when there is more under it)
        let more = CGFloat(rows.count) * PlacesSheet.rowH > height + 0.5
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row($0) }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollDisabled(!more)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: more ? max(0, 1 - 28 / height) : 1),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
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
                    Icon5(key: "forward", ink: ink.opacity(0.35), size: 15)
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

import SwiftUI

/// PLACES' WATER: simple, a few buttons: a menu of the types of place to look at; one pressed, the map shows those
/// places and the sheet becomes that set's. Never full screen.
///
/// Two states, and one simply takes the other's place (7 Nov: a change of what is shown needs no animation):
/// - THE MENU: the sets by the names people say, each a button (a capsule on a quiet ground, two side by side), all
///   of them on screen. Nothing else: no caption, no count of "places"
///   as a whole (a count of every place there is says nothing).
/// - A SET (a button tapped): the caption says the set, yours of it and of how many, as the
///   map's caption does for the world; the back arrow stands at the sheet's top left, where Map settings' pages have
///   it, and brings the menu back (the way back must be plain to see);
///   under the caption the set's own kinds (Seas and oceans: Oceans, Seas, Gulfs and bays, Straits), the one picked
///   its whole bar in lime glass (12 Oct), a second tap showing all of the set again.
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

    static let rowH: CGFloat = 44

    var body: some View {
        let L = water.layout
        let picked = map.placesPicked
        // (the menu has the whole water above the tabs; a set's kinds the room under its caption's count)
        let from = picked ? captionY + 70 : top + 20
        let to = L.capsule.minY - 12
        let store = CollectionStore.shared
        let count = picked ? store.types(map.placesSet).count : store.menu.count
        // (the buttons' lines: 44 pt each, 8 pt between)
        let lines = Int(ceil(Double(count) / Double(PlacesMenu.columns(count))))
        let height = CGFloat(lines) * Self.rowH + CGFloat(max(0, lines - 1)) * PlacesMenu.gap
        // (the buttons are there when every one of them fits in the water as it stands, so the water's edge and the
        // tabs never cut one and none stands alone on the way up)
        // (and only once the sets have been read: for a moment before that the menu was Cities alone)
        let shown = count > 0 && store.ready && height <= to - from + 0.5
        // (the menu in the middle of its room; a set's kinds from the room's top, right under the caption)
        ZStack(alignment: .topLeading) {
            if shown {
                PlacesMenu(water: water, map: map)
                    .frame(width: L.W - 2 * L.sheetInset - 32, height: height, alignment: .top)
                    .padding(.top, picked ? from : from + max(0, to - from - height) / 2)
                    .frame(width: L.W, alignment: .top)
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
        .onAppear { ThingIndex.shared.load(); CollectionStore.shared.load() }
    }
}

/// the buttons: the sets, or the picked set's kinds. Four or more stand two side by side (eight sets are four lines,
/// a set's four kinds two); up to three share one line
struct PlacesMenu: View {
    let water: Water
    let map: MapController

    static let gap: CGFloat = 8
    static func columns(_ count: Int) -> Int { count >= 4 ? 2 : max(1, count) }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let on: Bool
        /// a set's own mark (drawn in the icons' grid), nil for a set's kinds
        var icon: String? = nil
        /// how many of the set are yours (shown from one)
        var count = 0
        let act: () -> Void
    }
    /// A SET'S MARK by what it holds: cities, landmarks, World Heritage, national parks, peaks, ranges, lakes,
    /// islands, seas; any other set (a season of races, a tour) the flag
    static func icon(_ id: String, title: String) -> String {
        if id == CollectionStore.towns { return "set-cities" }
        let t = title.lowercased()
        let marks: [(String, String)] = [("heritage", "set-heritage"), ("park", "set-parks"), ("range", "set-ranges"),
                                         ("peak", "set-peaks"), ("mountain", "set-peaks"), ("lake", "set-lakes"),
                                         ("island", "set-islands"), ("sea", "set-seas"), ("ocean", "set-seas"),
                                         ("landmark", "set-landmarks"), ("cit", "set-cities"), ("capital", "set-cities")]
        return marks.first { t.contains($0.0) }?.1 ?? "set-collection"
    }
    private var list: [Row] {
        let store = CollectionStore.shared
        guard map.placesPicked else {
            // (a set with kinds keeps the water at 50% for them; one with none has nothing more to pick here, so the
            // water goes down to 25% and the map of its places has the screen)
            // (each set with its mark and how many of it are yours, so the menu reads as what you collect)
            _ = MarkStore.shared.changes; _ = map.townsVersion
            return store.menu.map { id in
                let title = store.title(id)
                let mine = id == CollectionStore.towns ? map.stampedTowns(on: .everywhere)
                    : store.collection(id).map { $0.items.filter { MarkStore.shared.state($0.key).stamped }.count } ?? 0
                return Row(id: "set:" + id, title: title, on: false, icon: Self.icon(id, title: title), count: mine) {
                    map.showPlacesSet(id)
                    if store.types(id).isEmpty { water.go(.quarter) }
                }
            }
        }
        let set = map.placesSet, kind = map.placesKind
        return store.types(set).compactMap { t in
            guard t.count == 2 else { return nil }
            return Row(id: "kind:" + set + ":" + t[0], title: t[1], on: kind == t[0]) { map.showPlacesType(kind == t[0] ? nil : t[0]) }
        }
    }

    var body: some View {
        let _ = CollectionStore.shared.ready
        let list = self.list
        let cols = Self.columns(list.count)
        let lines = stride(from: 0, to: list.count, by: cols).map { Array(list[$0 ..< min($0 + cols, list.count)]) }
        VStack(spacing: Self.gap) {
            ForEach(lines.indices, id: \.self) { i in
                if lines[i].count < cols, let last = lines[i].first {
                    // (an odd one out, the ninth of nine: a button as wide as the others, in the middle, not one
                    // stretched across the whole water)
                    // (at least as wide as the others, wider if its name and count need it: never cut short)
                    Color.clear.frame(height: PlacesSheet.rowH).overlay {
                        GeometryReader { g in
                            row(last, least: (g.size.width - Self.gap) / 2).fixedSize(horizontal: true, vertical: false)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    HStack(spacing: Self.gap) { ForEach(lines[i]) { row($0) } }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// `least`: the odd one out's least width (it grows to fit its name and count)
    private func row(_ r: Row, least: CGFloat? = nil) -> some View {
        Button {
            Feel.tick()
            r.act()
        } label: {
            // (a set: its mark, its name, and yours of it in grey at the end, from one; a set's kind: its name in
            // the middle, as before)
            HStack(spacing: 8) {
                if let icon = r.icon { Icon5(key: icon, ink: Palette.ink, size: 17).accessibilityHidden(true) }
                Text(r.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if r.icon != nil { Spacer(minLength: 4) }
                if r.count > 0 {
                    Text("\(r.count)").font(.body).monospacedDigit().foregroundStyle(Palette.ink.opacity(0.5))
                }
            }
                .padding(.horizontal, r.icon == nil ? 8 : 14)
                .frame(minWidth: least, maxWidth: least == nil ? .infinity : nil)
                .frame(height: PlacesSheet.rowH)
                // (a button is its own glass capsule, as the head's circles and the water's tools: never a see-through
                // ground: frosted, so the map under the water does not show through, 12 Nov; the one picked in lime glass)
                .contentShape(Capsule())
                .glassEffect(r.on ? PageGlass.surface.tint(Palette.lime) : PageGlass.surface, in: .capsule)
        }
        .buttonStyle(.plain)
        .transition(.identity)
        .accessibilityAddTraits(r.on ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(r.count > 0 ? "\(r.count) yours" : "")
    }
}

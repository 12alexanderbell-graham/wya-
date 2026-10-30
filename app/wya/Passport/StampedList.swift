import SwiftUI

/// THE STAMPED LIST (Part 4.6): every country you have stamped, one list sorted by name, in the water at full under
/// the caption (which stays). Opened and closed by the caption's number; a pull down closes it.
/// Rows 56 pt: the square flag 28 pt (detailed), the name 17 pt, under it how often (13 pt black 50%).
/// A row: tap = the card from the place on the map (the water at 25%, the camera framing it first); swipe right =
/// Details; swipe left = Unstamp; hold = Apple's menu. Black and white as Map settings and Details are.
/// Not here yet (logged): the latest visit's year and "Verified" in the second line, A4.19 / A4.20 / A4.21 motion
/// (rows just appear), regions / towns / things scopes, Show in passport.
struct StampedList: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    /// where the caption's bottom is (the rows start 12 pt under it)
    let top: CGFloat
    @State private var marks = MarkStore.shared

    struct Row: Identifiable {
        let id: String
        let name: String
        let place: Int
        let line: String
    }

    private var rows: [Row] {
        guard let w = map.world else { return [] }
        var index: [String: Int] = [:]
        for (i, p) in w.places.enumerated() { index[p.id] = i }
        return marks.marks.compactMap { k, s -> Row? in
            guard k.kind == .country, s.stamped, let i = index[k.id] else { return nil }
            let line = s.lived ? "Lived" : s.visits <= 1 ? "Once" : s.visits == 2 ? "Twice" : "\(s.visits) times"
            return Row(id: k.id, name: w.places[i].n, place: i, line: line)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let L = water.layout
        let y0 = top + 12
        let bottom = L.capsule.minY - 24
        let h = max(60, bottom - y0)
        List {
            ForEach(rows) { r in
                row(r)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { details(r) } label: { Text("Details") }.tint(Palette.ink)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { unstamp(r) } label: { Text("Unstamp") }
                    }
                    .contextMenu {
                        Button("Show on the map") { open(r) }
                        Button("Details") { details(r) }
                        Button("Unstamp", role: .destructive) { unstamp(r) }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 56)
        .frame(width: L.W - 2 * L.sheetInset, height: h)
        .position(x: L.W / 2, y: y0 + h / 2)
    }

    private func row(_ r: Row) -> some View {
        HStack(spacing: 12) {
            Group {
                if let f = Flags.square(r.id.lowercased()) { f.resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.body).foregroundStyle(Palette.ink)
                Text(r.line).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture { open(r) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// the card from the place: the water to 25%, the camera frames the place, then the card grows out of it
    private func open(_ r: Row) {
        Feel.tap()
        water.closeList(to: .quarter)
        map.show(place: r.place, sheetTop: water.y(.quarter))
        // the card from the place once the camera has landed (show's flight is 0.8 s) and the water is at 25%, so
        // nothing moves into the card's way while it grows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + 0.1) {
            guard let w = map.world else { return }
            let p = w.places[r.place]
            CardState.shared.open(r.place, at: map.screenPoint(SIMD2(p.c[0], p.c[1])), map: map, water: water)
        }
    }

    /// Details over the list, in the same water; closing them comes back to the list
    private func details(_ r: Row) {
        DetailsState.shared.open(.country(r.id), name: r.name, water: water)
    }

    private func unstamp(_ r: Row) {
        Feel.lift()
        Task { await MarkStore.shared.unstamp(.country(r.id), name: r.name) }
    }
}

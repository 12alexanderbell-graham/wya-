import SwiftUI

/// WHAT'S HERE? (A11.4; 11.5's empty-land and pin menus): the nearest three names from our own data (towns and things,
/// nearest first, one a line, the subheadline style: 15 pt, larger with larger text) in a glass panel over the map, its
/// bottom 12 pt above the held point; each name is a tap to its card.
/// THE ANSWER FITS HOW FAR OUT THE MAP IS (12 Nov): only names within a finger of the held point on the screen count
/// (44 pt, and only while that is under about 30 km of ground), and the country is always the last line. Held on a world map over Cameroon it named three villages, one of
/// them across the border in Nigeria; now it says "Cameroon", and names towns once the map is close enough for a
/// finger to mean a town. A name from another country than the point's carries its country. Rows are 44 pt. The panel (frosted, as every surface) is simply
/// there, and a touch anywhere else on the map simply takes it away (A11.4's grow and roll dropped: no grow,
/// no roll). At sea: "Open sea".
@MainActor
@Observable
final class WhatsHere {
    static let shared = WhatsHere()
    struct Item: Identifiable {
        let id: String
        let name: String
        /// its card, or nil (the open sea)
        let open: (() -> Void)?
    }
    /// the held point on screen
    private(set) var point: CGPoint = .zero
    private(set) var items: [Item] = []
    /// up on the map
    private(set) var present = false
    private(set) var namesIn = false
    @ObservationIgnored private var job = 0
    /// each country's first level, read once for What's here
    @ObservationIgnored private static var scenes: [String: RegionScene] = [:]

    var isOpen: Bool { present }

    /// on our own map: the point held on screen
    func show(at p: CGPoint, map: MapController) {
        let mp = map.mapPoint(p)
        let ll = EqualEarth.unproject(mp)
        let land = map.world?.place(at: SIMD2(Float(mp.x), Float(mp.y)))
        // a finger's reach on the screen, in degrees there (the point 44 pt below the held one)
        let down = EqualEarth.unproject(map.mapPoint(CGPoint(x: p.x, y: p.y + 44)))
        show(at: p, lat: ll.lat, lon: ll.lon, land: land, reach: abs(down.lat - ll.lat), map: map)
    }

    /// `land`: the country under the point on our map (nil: the sea); `reach`: a finger's reach on the screen (44 pt)
    /// in degrees of latitude at the point
    func show(at p: CGPoint, lat: Double, lon: Double, land: Int?, reach: Double, map: MapController) {
        items = Self.nearest(lat: lat, lon: lon, land: land, reach: reach, map: map)
        job += 1
        // THE REGION IT IS IN on the country's line ("Kigoma, Tanzania"): the first level's file is on the phone; read
        // and looked in off the main thread, the line changed once it is known (held on Tanzania it said three villages,
        // then the country alone, never which part of it)
        if let land, let w = map.world, land >= 0, land < w.places.count {
            let cc = w.places[land].id.lowercased(), country = w.places[land].n, me = job
            let at = EqualEarth.project(lon: lon, lat: lat)
            let kept = Self.scenes[cc]
            Task { @MainActor [weak self] in
                let found: (RegionScene?, String?) = await Task.detached(priority: .userInitiated) {
                    var sc = kept
                    if sc == nil, let first = RegionCatalog.shared.first(cc), let f = RegionCatalog.shared.file(cc, row: first.row) {
                        sc = RegionScene(place: land, id: cc, row: first.row, file: f)
                    }
                    return (sc, sc.flatMap { s in s.unit(at: at).map { s.unitNames[$0] } })
                }.value
                if let sc = found.0 { Self.scenes[cc] = sc }
                guard let self, self.job == me, let name = found.1, !name.isEmpty, name != country,
                      let i = self.items.lastIndex(where: { $0.id == "land" }) else { return }
                self.items[i] = Item(id: "land", name: "\(name), \(country)", open: nil)
            }
        }
        point = p
        // simply there, and simply gone (no grow, no circle)
        Feel.tap()
        namesIn = true; present = true
        UIAccessibility.post(notification: .announcement, argument: items.map(\.name).joined(separator: ", "))
    }

    func close() {
        guard present else { return }
        job += 1
        namesIn = false; present = false
    }

    /// the three nearest of the towns (the index of every town) and the things of the country under the point
    private static func nearest(lat: Double, lon: Double, land: Int?, reach: Double, map: MapController) -> [Item] {
        guard let land, let w = map.world, land >= 0, land < w.places.count else {
            return [Item(id: "sea", name: "Open sea", open: nil)]
        }
        let country = w.places[land].n
        let k = cos(lat * .pi / 180)
        func d2(_ la: Double, _ lo: Double) -> Double {
            var dx = lo - lon
            if dx > 180 { dx -= 360 } else if dx < -180 { dx += 360 }
            dx *= k
            let dy = la - lat
            return dx * dx + dy * dy
        }
        var found: [(Double, Item)] = []
        // (towns and things are an answer only when a finger is under about 30 km of ground: farther out a finger
        // covers a region or a country, and the three "nearest" are three villages somewhere under it)
        let far = reach <= 0.28 ? reach * reach : -1
        for h in TownIndex.shared.nearest(lat: lat, lon: lon, count: 3) where d2(h.lat, h.lon) <= far {
            let place = w.placeIndex[h.file] ?? w.placeIndex[h.file.uppercased()] ?? land
            let parents = [h.region, w.places[place].n].filter { !$0.isEmpty }.joined(separator: ", ")
            found.append((d2(h.lat, h.lon), Item(id: h.key, name: place == land ? h.name : "\(h.name), \(w.places[place].n)") {
                RegionCardState.shared.open(PlaceKey(.town, h.id), name: h.name, parents: parents, place: place, map: map)
            }))
        }
        let cc = w.places[land].id.lowercased()
        for t in ThingStore.shared.things(cc) ?? [] {
            let ll = EqualEarth.unproject(SIMD2(Double(t.at.x), Double(t.at.y)))
            let d = d2(ll.lat, ll.lon)
            // only those within reach that could be among the three
            guard d <= far, found.count < 3 || d < found.map(\.0).max()! else { continue }
            let line = t.line.isEmpty ? country : t.line.prefix(1).uppercased() + t.line.dropFirst()
            found.append((d, Item(id: "wd:" + t.id, name: t.name) {
                RegionCardState.shared.open(t.key, name: t.name, parents: line, place: land, map: map)
            }))
            if found.count > 6 { found.sort { $0.0 < $1.0 }; found.removeLast(found.count - 3) }
        }
        found.sort { $0.0 < $1.0 }
        // the names within reach, then the country itself (its name only), always
        return found.prefix(3).map(\.1) + [Item(id: "land", name: country, open: nil)]
    }
}

/// the panel itself, over the map and under the water and the head
struct WhatsHereView: View {
    let layout: Layout
    @State private var here = WhatsHere.shared

    var body: some View {
        let open = here.present
        let widest = layout.W - 32
        let width = open ? min(widest, panelWidth + 32) : 44
        let height = open ? CGFloat(here.items.count) * lineHeight + 12 : 44
        // its bottom 12 pt above the point, kept on the screen
        let x = min(max(here.point.x, width / 2 + 16), layout.W - width / 2 - 16)
        let y = max(here.point.y - 12 - height / 2, layout.headBottom + 8 + height / 2)
        if here.present {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(here.items) { item in
                    if let o = item.open {
                        Button {
                            Feel.tap()
                            here.close()
                            o()
                        } label: { name(item) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.name)
                    } else {
                        name(item).accessibilityLabel(item.name)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            // a surface over the map: the system's frosted glass, as search's results box
            .glassEffect(PageGlass.surface, in: RoundedRectangle(cornerRadius: open ? 18 : 22, style: .continuous))
            .position(x: x, y: y)
            .allowsHitTesting(here.present)
            .transition(.identity)
        }
    }

    /// one name, rolled in and out by the text roll (never scaled, never faded)
    private func name(_ item: WhatsHere.Item) -> some View {
        Text(here.namesIn ? item.name : Caption.blank(item.name, "\u{2002}"))
            .font(.subheadline)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.identity)
            .frame(height: lineHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// one name's line: 44 pt, a finger's (they were 22 with 8 between: a miss pressed the map under the panel)
    private var lineHeight: CGFloat { max(44, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight.rounded(.up) + 2) }

    /// the longest name's width in that style
    private var panelWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        return here.items.map { ($0.name as NSString).size(withAttributes: [.font: font]).width.rounded(.up) }.max() ?? 0
    }
}

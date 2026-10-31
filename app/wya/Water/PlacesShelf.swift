import SwiftUI
import simd

/// THE SHELF (7.5): at 50% in Places, the maps that fit where you are looking, one sideways row of cards snapping card
/// by card, 12 pt under the caption's foot, riding the water's edge with it and passing under the soft edge above the
/// tabs as a scrolled row does (A7.4). Worked out when the sheet rises to 50%, never while you look at it. A card: its
/// picture (132 pt, corners 20: the map's land on our sea, your towns on it lime), its title and your number under it
/// on the water; the current map's card 4 pt higher. A tap makes it the current map (A7.2), the water going to 25% so
/// the map is framed where it is seen (author's call).
/// Not on it yet: Around you (location), your lists, collections (D7), the AI's maps, New map and All maps (the atlas).
struct PlacesShelf: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    /// the caption's centre
    let captionY: CGFloat
    @State private var cards: [MapController.PlacesPick] = []
    private static let side: CGFloat = 132

    var body: some View {
        let L = water.layout
        // (the caption's foot is 65 pt under its centre and the row's place 14 pt under where it is asked for, both
        // measured on the Pro Max; the 4 pt the current card rises by is inside the row)
        let top = captionY + 65 + 12 - 4 - 14
        // the row's foot under the soft edge above the tabs (P3): seen only once the water has lifted it clear
        let fade = L.capsule.minY - 2
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(cards, id: \.self) { c in card(c) }
            }
            .scrollTargetLayout()
            .padding(.top, 4)
            .frame(height: Self.side + 64, alignment: .top)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .frame(width: L.W - 2 * L.sheetInset, height: Self.side + 64)
        .clipped()
        .padding(.top, top)
        .frame(width: L.W, height: L.H, alignment: .top)
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().frame(height: max(0, fade - 24))
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 24)
                Spacer(minLength: 0)
            }
        }
        // touchable only once the cards are clear of the edge (a masked row would still take touches)
        .allowsHitTesting(top + Self.side < fade - 24)
        .onAppear { TownIndex.shared.load(); work() }
        .onChange(of: water.stop) { _, s in if s == .half { work() } }
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

    private func card(_ c: MapController.PlacesPick) -> some View {
        let current = map.placesPick == c
        _ = map.townsVersion
        let n = map.stampedTowns(on: c)
        var number = "\(n)"
        if case .country(let i) = c, let cc = map.world?.places[i].id.lowercased(), let all = map.townScenes[cc]?.towns.count {
            number += " of \(all.formatted())"
        }
        return VStack(alignment: .leading, spacing: 0) {
            ShelfPicture(map: map, pick: c, ready: TownIndex.shared.ready, version: map.townsVersion)
                .frame(width: Self.side, height: Self.side)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title(c)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
                .padding(.top, 6)
            Text(number).font(.caption).foregroundStyle(Palette.ink.opacity(0.5))
        }
        .frame(width: Self.side, alignment: .leading)
        .offset(y: current ? -4 : 0)
        .animation(Motion.quick, value: current)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            water.go(.quarter)
            map.showPlacesMap(c)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func title(_ c: MapController.PlacesPick) -> String {
        if case .country(let i) = c { return map.world?.places[i].n ?? "" }
        return c.title
    }
}

/// A CARD'S PICTURE: the map's land white on our sea (the land round it lighter), your stamped towns and own places
/// on it as lime points; drawn once per map and marks, kept
struct ShelfPicture: View {
    let map: MapController
    let pick: MapController.PlacesPick
    let ready: Bool
    let version: Int
    private static var kept: [String: UIImage] = [:]

    var body: some View {
        let key = "\(pick)|\(version)|\(ready)"
        if let i = Self.kept[key] ?? draw(key) {
            Image(uiImage: i).resizable()
        } else {
            Palette.blue
        }
    }

    private func draw(_ key: String) -> UIImage? {
        guard let w = map.world, let b0 = map.box(of: pick) else { return nil }
        let size: CGFloat = 132
        // the box with room round it, made square
        var x0 = Double(b0.x), y0 = Double(b0.y), x1 = Double(b0.z), y1 = Double(b0.w)
        let pad = pick == .everywhere ? 0 : max(x1 - x0, y1 - y0) * 0.12
        x0 -= pad; x1 += pad; y0 -= pad; y1 += pad
        if x1 - x0 > y1 - y0 { let c = (y0 + y1) / 2, h = (x1 - x0) / 2; y0 = c - h; y1 = c + h }
        else { let c = (x0 + x1) / 2, h = (y1 - y0) / 2; x0 = c - h; x1 = c + h }
        let s = Double(size) / (x1 - x0)
        func pt(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: (Double(p.x) - x0) * s, y: (Double(p.y) - y0) * s) }
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
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = r.image { ctx in
            let g = ctx.cgContext
            g.setFillColor(UIColor(Palette.blue).cgColor)
            g.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let mine = CGMutablePath(), rest = CGMutablePath(), lakes = CGMutablePath()
            for ring in w.rings {
                guard Double(ring.box.z) >= x0, Double(ring.box.x) <= x1, Double(ring.box.w) >= y0, Double(ring.box.y) <= y1 else { continue }
                let p = CGMutablePath()
                p.move(to: pt(w.points[ring.start]))
                for i in 1 ..< ring.count { p.addLine(to: pt(w.points[ring.start + i])) }
                p.closeSubpath()
                if ring.unit < 0 { lakes.addPath(p) }
                else if own == nil || own!.contains(w.unitOwner[ring.unit]) { mine.addPath(p) } else { rest.addPath(p) }
            }
            g.addPath(rest); g.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor); g.fillPath(using: .evenOdd)
            g.addPath(mine); g.setFillColor(UIColor.white.cgColor); g.fillPath(using: .evenOdd)
            g.addPath(lakes); g.setFillColor(UIColor(Palette.blue).cgColor); g.fillPath()
            g.setFillColor(UIColor(Palette.lime).cgColor)
            let d: CGFloat = pick == .everywhere ? 3 : 5
            for p in dots {
                let c = pt(p)
                g.fillEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
            }
        }
        DispatchQueue.main.async { Self.kept[key] = image }
        return image
    }
}

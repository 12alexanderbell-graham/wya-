import Foundation
import CoreGraphics
import simd

/// PLACES ON OUR MAP (7.4), the old native app's system (30 Oct 23:38: the old native app's system, followed;
/// old MapPlaces.openPlaceCountry): the world plain in Places; a country tapped is opened, framed as
/// a region map is (the rest of the world into its continent's blue) and its towns come in as their built-up shapes,
/// every shape at once, solid in our grey (old encodeTownShapes: "solid, so neighbours are one colour"), yours lime,
/// wished blue, the one under the finger the darker grey. No circles for towns with no shape (30 Oct 23:38: no circles
/// on the towns map); dots only with Map settings' Town dots on.
extension MapController {
    /// the open country's towns shown now (all of them: the old app showed every shape of the country at once)
    func townsShown(_ s: TownScene) -> Int { s.cc == placeOpenID ? s.towns.count : 0 }
    /// the open country's id, lowercased ("de")
    var placeOpenID: String? { placeOpen.flatMap { world?.places[$0].id.lowercased() } }

    /// A COUNTRY OPENED IN PLACES: framed as a region map (6.5's room), the rest of the world fading into its
    /// continent's blue, its towns read (from the data server, kept for the session)
    func openPlace(_ i: Int) {
        guard placesMode, let w = world, i >= 0, i < w.places.count, placeOpen != i else { return }
        townPressed = nil
        placesCollection = nil
        placeOpen = i
        frameRegion(i)
        loadTowns(w.places[i].id.lowercased())
        ThingStore.shared.load(w.places[i].id.lowercased())
    }
    /// REGIONS' TOWNS LEVEL (6.6, the level line's last word "towns"): the level that was up kept, drawn as borders
    /// only (the book's finest level was tried on 31 Oct: France's 35,000 communes' borders buried the towns), and the
    /// country's towns as Places draws them (their names too); a tap is a town's
    func showRegionTowns() {
        guard let sc = regionScene, let w = world else { return }
        regionTowns = true
        regionPressed = nil
        placeOpen = sc.place
        loadTowns(w.places[sc.place].id.lowercased())
        needsFrame = true
    }
    /// out of the towns level (another level picked, or the region map closed)
    func leaveRegionTowns() {
        guard regionTowns else { return }
        regionTowns = false
        townPressed = nil
        if !placesMode { placeOpen = nil }
        needsFrame = true
    }
    /// a place's towns read (from the data server, kept for the session)
    func loadTowns(_ cc: String) {
        if retryShapes.contains(cc) { townScenes[cc] = nil }
        guard townScenes[cc] == nil, !townLoading.contains(cc) else { takeTownMarks(); return }
        townLoading.insert(cc)
        Task.detached(priority: .userInitiated) { [weak self] in
            let towns = await TownStore.shared.towns(cc)
            let shapes = await TownStore.shared.shapes(cc)
            let scene = towns.map { TownScene(cc: cc, towns: $0, shapes: shapes ?? []) }
            await MainActor.run {
                guard let self else { return }
                self.townLoading.remove(cc)
                // shapes that could not be had now: shown without them this time, asked for again next time
                guard let scene, !scene.towns.isEmpty, shapes != nil else {
                    if let scene, !scene.towns.isEmpty, shapes == nil { self.townScenes[cc] = scene; self.retryShapes.insert(cc) }
                    return
                }
                self.retryShapes.remove(cc)
                self.townScenes[cc] = scene
                self.takeTownMarks()
                self.needsFrame = true
                #if DEBUG
                NSLog("wya towns %@: %d towns, %d shaped", cc, scene.towns.count, scene.runs.filter { $0 != nil }.count)
                #endif
            }
        }
    }
    /// A TOWN FOUND BY SEARCH: its country opened (if it isn't), then, once its towns have come, the town framed and
    /// darkened (as a region found on a region map is)
    func showTown(file cc: String, id: String) {
        guard let w = world, let i = w.placeIndex[cc] else { return }
        if placeOpen != i { openPlace(i) }
        Task { @MainActor [weak self] in
            for _ in 0 ..< 150 {
                if self?.townScenes[cc] != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, self.placeOpen == i, let sc = self.townScenes[cc], let t = sc.index[id] else { return }
            self.townPressed = (cc, t)
            self.showBox(sc.box(t), place: i)
        }
    }

    /// A THING FOUND BY SEARCH: its country opened (if it isn't), then, once its things have come, the thing framed and
    /// darkened for two seconds
    func showThing(file cc: String, id: String) {
        guard let w = world, let i = w.placeIndex[cc] else { return }
        if placeOpen != i { openPlace(i) }
        Task { @MainActor [weak self] in
            for _ in 0 ..< 150 {
                if ThingStore.shared.things(cc) != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, self.placeOpen == i, let t = ThingStore.shared.things(cc)?.first(where: { $0.id == id }) else { return }
            self.thingPressed = id
            // close enough that its band shows it (the rest of its fame's band: 16x the framing zoom covers every thing)
            let r: Float = 0.004
            self.showBox(SIMD4(t.at.x - r, t.at.y - r, t.at.x + r, t.at.y + r), place: i)
            try? await Task.sleep(for: .milliseconds(2600))
            if self.thingPressed == id { self.thingPressed = nil; self.needsFrame = true }
        }
    }

    /// your own place whose mark is under a screen point (within 22 pt of its point)
    func ownHit(at p: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for o in OwnPlaces.shared.all {
            let q = screenPoint(SIMD2(Double(o.point.x), Double(o.point.y)))
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= 22, best == nil || d < best!.1 { best = (o.id, d) }
        }
        return best?.0
    }
    /// A7.11 YOUR OWN PLACE MADE BY QUICK ADD: at the tapped point of the open country, named after the nearest town
    /// ("Near Kyoto"), stamped as it is made (with its region chain and country)
    func makeOwnPlace(at p: CGPoint) {
        guard let open = placeOpen, let cc = placeOpenID else { return }
        let m = mapPoint(p)
        let ll = EqualEarth.unproject(m)
        let mp = SIMD2(Float(m.x), Float(m.y))
        var near: String?
        if let sc = townScenes[cc] {
            var bd = Float.infinity
            for (i, a) in sc.at.enumerated() { let d = simd_distance_squared(a, mp); if d < bd { bd = d; near = sc.towns[i].name } }
        }
        let name = near.map { "Near \($0)" } ?? "Your place"
        let place = OwnPlaces.shared.make(name: name, lat: ll.lat, lon: ll.lon, cc: cc)
        Feel.tap()
        needsFrame = true
        Task { await TownStamps.stamp(place.key, name: place.name, cc: cc, source: .quick, place: open, at: mp) }
    }

    /// a map box's frame on screen now (where a page grows from, A16.1)
    func screenRect(_ b: SIMD4<Float>) -> CGRect {
        let a = screenPoint(SIMD2(Double(b.x), Double(b.y))), c = screenPoint(SIMD2(Double(b.z), Double(b.w)))
        let r = CGRect(x: min(a.x, c.x), y: min(a.y, c.y), width: abs(c.x - a.x), height: abs(c.y - a.y))
        return r.width < 24 || r.height < 24 ? CGRect(x: r.midX - 22, y: r.midY - 22, width: 44, height: 44) : r
    }
    /// a place's frame on screen now
    func screenRect(of i: Int) -> CGRect {
        guard let f = world?.frame(of: i) else { return CGRect(x: view.width / 2 - 22, y: view.height / 2 - 22, width: 44, height: 44) }
        return screenRect(f)
    }

    /// A PLACES MAP PICKED (7.5's cards): Everywhere (the world), a country (opened with its towns), a continent (its own
    /// framing, the rest of the world into the blue, as Countries' continent) or a world region (its countries framed)
    enum PlacesPick: Hashable {
        case everywhere, country(Int), continent(String), region(String), collection(String)
        @MainActor var title: String {
            switch self {
            case .everywhere: "Everywhere"
            case .continent(let k), .region(let k): k
            case .country: ""
            case .collection(let id): CollectionStore.shared.collection(id)?.title ?? ""
            }
        }
    }
    var placesPick: PlacesPick {
        if let c = placesCollection { return .collection(c) }
        if let i = placeOpen { return .country(i) }
        if let a = placesArea { return Self.continents.contains(a) ? .continent(a) : .region(a) }
        return .everywhere
    }
    static let continents = ["Africa", "Antarctica", "Asia", "Europe", "North America", "Oceania", "South America"]
    func showPlacesMap(_ pick: PlacesPick) {
        guard placesMode, world != nil else { return }
        // a card left up from the last map goes back into the water (a town's card stood over the world after Everywhere)
        CardState.shared.close(map: self); RegionCardState.shared.close(map: self)
        if case .collection = pick {} else { placesCollection = nil }
        switch pick {
        case .everywhere:
            placesArea = nil
            closePlace()
            goHome()
        case .country(let i):
            placesArea = nil
            if placeOpen == i { frameRegion(i) } else { openPlace(i) }
        case .continent(let k):
            closePlace()
            placesArea = k
            show(continent: k)
        case .collection(let id):
            // A COLLECTION (7.2): its places marked wherever they are, framed together (the world for one spread over it)
            closePlace()
            placesArea = nil
            placesCollection = id
            guard let f = box(of: pick) else { return }
            if f.z - f.x > (world?.width ?? 1000) * 0.45 { goHome() }
            else { frameArea(SIMD4(Double(f.x), Double(f.y), Double(f.z), Double(f.w))) }
        case .region(let name):
            closePlace()
            placesArea = name
            guard let f = box(of: pick) else { return }
            frameArea(SIMD4(Double(f.x), Double(f.y), Double(f.z), Double(f.w)))
        }
    }
    /// a pick's box on the map: the world, a country's, a continent's own view, a world region's countries together (a
    /// far-off island of one of them left out when it would make the frame a hemisphere wide)
    func box(of pick: PlacesPick) -> SIMD4<Float>? {
        guard let w = world else { return nil }
        switch pick {
        case .everywhere: return SIMD4(0, 0, w.width, w.height)
        case .country(let i): return w.frame(of: i)
        case .collection(let id):
            guard let items = CollectionStore.shared.collection(id)?.items, !items.isEmpty else { return nil }
            var f = SIMD4<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            for i in items { f = SIMD4(min(f.x, i.at.x), min(f.y, i.at.y), max(f.z, i.at.x), max(f.w, i.at.y)) }
            let pad = max(f.z - f.x, f.w - f.y) * 0.08 + 2
            return SIMD4(f.x - pad, f.y - pad, f.z + pad, f.w + pad)
        case .continent(let k):
            if let v = w.contViews[k] { return SIMD4(Float(v.x), Float(v.y), Float(v.z), Float(v.w)) }
            fallthrough
        default:
            let boxes = (members(of: pick) ?? []).compactMap { w.frame(of: $0) }
            guard !boxes.isEmpty else { return nil }
            let big = boxes.max { ($0.z - $0.x) * ($0.w - $0.y) < ($1.z - $1.x) * ($1.w - $1.y) }!
            let mid = SIMD2((big.x + big.z) / 2, (big.y + big.w) / 2)
            let reach = w.width * 0.18
            var f = big
            for b in boxes where abs((b.x + b.z) / 2 - mid.x) < reach && abs((b.y + b.w) / 2 - mid.y) < reach {
                f = SIMD4(min(f.x, b.x), min(f.y, b.y), max(f.z, b.z), max(f.w, b.w))
            }
            return f
        }
    }
    /// the places of a pick (the world's place indices), for counting and pictures
    func members(of pick: PlacesPick) -> [Int]? {
        guard let w = world else { return nil }
        switch pick {
        case .everywhere: return nil
        case .country(let i): return [i]
        case .continent(let k): return w.places.indices.filter { w.places[$0].cont == k }
        case .region(let n): return WorldRegions.members(n).compactMap { w.placeIndex[$0] }
        case .collection(let id):
            let ccs = Set(CollectionStore.shared.collection(id)?.items.map(\.cc) ?? [])
            return ccs.compactMap { w.placeIndex[$0] }
        }
    }
    /// your stamped towns (and own places, and things) on a pick; a collection's: its places you stamped
    func stampedTowns(on pick: PlacesPick) -> Int {
        if case .collection(let id) = pick {
            return CollectionStore.shared.collection(id)?.items.filter { MarkStore.shared.state($0.key).stamped }.count ?? 0
        }
        let ids: Set<String>? = members(of: pick).map { Set($0.compactMap { world?.places[$0].id.lowercased() }) }
        var n = 0
        for (k, s) in MarkStore.shared.marks where s.stamped && (k.kind == .town || k.kind == .yours || k.kind == .thing) {
            guard let ids else { n += 1; continue }
            let cc = k.kind == .town ? String(k.id.prefix { $0 != "/" })
                : k.kind == .thing ? (ThingStore.shared.thing(k.id)?.cc ?? "") : OwnPlaces.shared.place(k.id)?.cc ?? ""
            if ids.contains(cc) { n += 1 }
        }
        return n
    }

    /// back to the world: the towns go, the world comes back (the camera stays where it is)
    func closePlace() {
        guard placeOpen != nil else { return }
        placeOpen = nil
        townPressed = nil
        closeRegions()
    }

    /// a collection's place whose mark is under a screen point (the collection's map up)
    func collectionHit(at p: CGPoint) -> CollectionStore.Item? {
        guard placesMode, let id = placesCollection, let items = CollectionStore.shared.collection(id)?.items else { return nil }
        var best: (CollectionStore.Item, CGFloat)?
        for (q, f) in thingFrames {
            guard f.insetBy(dx: -8, dy: -8).contains(p), let it = items.first(where: { $0.id == q }) else { continue }
            let d = hypot(f.minX + 5 - p.x, f.midY - p.y)
            if best == nil || d < best!.1 { best = (it, d) }
        }
        return best?.0
    }

    /// the thing whose mark is under a screen point (only marks showing now: TownNamesView keeps their frames)
    func thingHit(at p: CGPoint) -> ThingStore.Thing? {
        guard placesMode, placesCollection == nil else { return nil }
        let all = townCountries.flatMap { ThingStore.shared.things($0) ?? [] }
        var best: (ThingStore.Thing, CGFloat)?
        for (id, f) in thingFrames {
            // within the mark and its name, with a fingertip's room round them
            guard f.insetBy(dx: -8, dy: -8).contains(p) else { continue }
            let d = hypot(f.minX + 5 - p.x, f.midY - p.y)
            guard best == nil || d < best!.1, let t = all.first(where: { $0.id == id }) else { continue }
            best = (t, d)
        }
        return best?.0
    }

    /// the town under a screen point (only towns showing now)
    func townHit(at p: CGPoint) -> (cc: String, i: Int)? {
        guard placesMode || regionTowns else { return nil }
        let m = mapPoint(p)
        let mp = SIMD2(Float(m.x), Float(m.y)), reach = Float(12 / k)
        let dots = MapSettingsStore.shared.value.townDots
        for cc in townCountries {
            guard let s = townScenes[cc], let i = s.town(at: mp, reach: reach, upTo: s.towns.count, dots: dots) else { continue }
            return (cc, i)
        }
        return nil
    }

    // MARK: TOWNS EVERYWHERE (7.4: "Everywhere zoomed out: only the visible size classes are drawn ... more come in as
    // you zoom in"): with no country open, once the map is close (about 1,000 km across the screen) the towns and things
    // of the countries in view are read and drawn as an open country's are, the nearest six at most
    /// the zoom from which they come
    var townsK: Double { Double(view.width) / 25 }
    /// the countries whose towns are drawn now: the open one's, else the ones in view close in
    var townCountries: [String] {
        if let cc = placeOpenID { return [cc] }
        guard placesMode, regionScene == nil, placesCollection == nil else { return [] }
        return nearbyTowns
    }
    /// worked out again when the camera has moved a fifth of a screen or zoomed by a fifth (called by the renderer)
    func updateNearbyTowns() {
        guard placesMode, placeOpen == nil, placesCollection == nil, regionScene == nil, let w = world, k >= townsK else {
            if !nearbyTowns.isEmpty { nearbyTowns = []; nearbyAt = .zero }
            return
        }
        // (not on the way: a flight to Belgium over the Alps loads no Swiss towns; worked out where it lands)
        guard flight == nil else { return }
        let span = Double(view.width) / k
        let now = SIMD3(c.x, c.y, k)
        guard abs(now.x - nearbyAt.x) > span / 5 || abs(now.y - nearbyAt.y) > span / 5 || abs(now.z / max(1, nearbyAt.z) - 1) > 0.2 else { return }
        nearbyAt = now
        if placeBoxes == nil { placeBoxes = w.places.indices.map { w.frame(of: $0) } }
        let a = mapPoint(.zero), b = mapPoint(CGPoint(x: view.width, y: view.height))
        let x0 = Float(min(a.x, b.x)), y0 = Float(min(a.y, b.y)), x1 = Float(max(a.x, b.x)), y1 = Float(max(a.y, b.y))
        var found: [(String, Float)] = []
        for (i, f) in (placeBoxes ?? []).enumerated() {
            guard let f, f.z >= x0, f.x <= x1, f.w >= y0, f.y <= y1, w.places[i].id != "aq" else { continue }
            let mid = SIMD2((f.x + f.z) / 2, (f.y + f.w) / 2)
            found.append((w.places[i].id.lowercased(), simd_distance(mid, SIMD2(Float(c.x), Float(c.y)))))
        }
        let list = found.sorted { $0.1 < $1.1 }.prefix(6).map(\.0)
        nearbyTowns = list
        for cc in list { loadTowns(cc); ThingStore.shared.load(cc) }
        needsFrame = true
    }

    /// which towns of the loaded places are yours, from the store (`t:` keys)
    func takeTownMarks() {
        var st: [String: Set<Int>] = [:], wi: [String: Set<Int>] = [:]
        var count = 0
        for (k, s) in MarkStore.shared.marks where k.kind == .town {
            if s.stamped { count += 1 }
            let cc = String(k.id.prefix { $0 != "/" })
            guard let sc = townScenes[cc], let i = sc.index[k.id] else { continue }
            if s.stamped { st[cc, default: []].insert(i) } else if s.wished { wi[cc, default: []].insert(i) }
        }
        townStamped = st; townWished = wi
        if townCount != count { townCount = count }
        townsVersion += 1
        needsFrame = true
    }
}

/// STAMPING A TOWN STAMPS ITS COUNTRY (7.4's quick add: "stamped (with its region chain and country)"): the country is
/// stamped too unless it already is, and remembered as stamped only through a town; unstamping the town takes the
/// country back only when it was stamped through a town and no other stamped town of it holds it. THE REGION CHAIN
/// (Part 6.7's rule, A6.12): the finest region level the country has, the region holding the town's point, stamped with
/// every parent above it (regions already stamped left as they are). Unstamping a town leaves its regions stamped.
enum TownStamps {
    @MainActor
    static func stamp(_ key: PlaceKey, name: String, cc: String, source: MarkSource, place: Int? = nil,
                      at point: SIMD2<Float>? = nil, day: String? = nil) async {
        await MarkStore.shared.stamp(key, name: name, cc: cc, source: source, day: day)
        let country = PlaceKey.country(cc)
        if !MarkStore.shared.state(country).stamped {
            await MarkStore.shared.stamp(country, source: source)
            through.insert(cc)
        }
        if let place, let point { await stampRegions(cc: cc, place: place, at: point, source: source) }
    }

    /// each country's finest region level, made into a scene once (to find the region holding a point)
    @MainActor private static var finest: [String: RegionScene] = [:]
    @MainActor
    static func stampRegions(cc: String, place: Int, at p: SIMD2<Float>, source: MarkSource) async {
        guard let row = RegionCatalog.shared.used(cc).last?.row else { return }
        var scene = finest[cc].flatMap { $0.row == row ? $0 : nil }
        if scene == nil {
            guard let f = await RegionCatalog.shared.fetch(cc, row: row) else { return }
            // built off the main thread (France's finest level is 35,000 communes), as the region map's are
            scene = await Task.detached(priority: .userInitiated) { RegionScene(place: place, id: cc, row: row, file: f) }.value
            finest = [cc: scene].compactMapValues { $0 }
        }
        guard let scene, let u = scene.unit(at: p) else { return }
        guard !MarkStore.shared.state(PlaceKey(.region, scene.unitIDs[u])).stamped else { return }
        await RegionStamps.stamp(u, in: scene, source: source)
    }

    @MainActor
    static func unstamp(_ key: PlaceKey, name: String, cc: String) async {
        await MarkStore.shared.unstamp(key, name: name)
        guard through.contains(cc) else { return }
        let held = MarkStore.shared.marks.contains { $0.key.kind == .town && $0.value.stamped && $0.key.id.hasPrefix(cc + "/") }
        guard !held else { return }
        through.remove(cc)
        let country = PlaceKey.country(cc)
        if MarkStore.shared.state(country).stamped { await MarkStore.shared.unstamp(country) }
    }

    /// a country no longer held only through a town
    @MainActor static func forget(_ cc: String) { through.remove(cc.lowercased()) }

    /// the countries stamped only through a town
    private static let throughKey = "wya.towns.through"
    @MainActor private static var through: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: throughKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: throughKey) }
    }
}

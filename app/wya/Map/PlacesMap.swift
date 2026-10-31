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
        placeOpen = i
        frameRegion(i)
        loadTowns(w.places[i].id.lowercased())
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

    /// back to the world: the towns go, the world comes back (the camera stays where it is)
    func closePlace() {
        guard placeOpen != nil else { return }
        placeOpen = nil
        townPressed = nil
        closeRegions()
    }

    /// the town under a screen point (only towns showing now)
    func townHit(at p: CGPoint) -> (cc: String, i: Int)? {
        guard placesMode || regionTowns else { return nil }
        let m = mapPoint(p)
        let mp = SIMD2(Float(m.x), Float(m.y)), reach = Float(12 / k)
        let dots = MapSettingsStore.shared.value.townDots
        guard let cc = placeOpenID, let s = townScenes[cc] else { return nil }
        return s.town(at: mp, reach: reach, upTo: s.towns.count, dots: dots).map { (cc, $0) }
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
                      at point: SIMD2<Float>? = nil) async {
        await MarkStore.shared.stamp(key, name: name, cc: cc, source: source)
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

    /// the countries stamped only through a town
    private static let throughKey = "wya.towns.through"
    @MainActor private static var through: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: throughKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: throughKey) }
    }
}

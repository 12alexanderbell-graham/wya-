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
        // (the set looked at stays: the country narrows it, national parks in one country)
        placeOpen = i
        frameRegion(i)
        loadTowns(w.places[i].id.lowercased())
        ThingStore.shared.load(w.places[i].id.lowercased(), opened: true)
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
        ShowJob.n += 1
        let me = ShowJob.n
        // (a town is the towns' set's)
        placesCollection = nil; placesType = nil; placesPicked = true
        // the country open already but its towns never came (offline then): they are asked again
        if placeOpen != i { openPlace(i) } else { loadTowns(cc) }
        Task { @MainActor [weak self] in
            for _ in 0 ..< 150 {
                if self?.townScenes[cc] != nil || me != ShowJob.n { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // a newer pick wins; a town that can't be shown says so
            guard me == ShowJob.n else { return }
            guard let self, self.placeOpen == i, let sc = self.townScenes[cc], let t = sc.index[id] else { Feel.refuse(); return }
            self.townPressed = (cc, t)
            self.showBox(sc.box(t), place: i)
        }
    }

    /// YOUR OWN PLACE from the Stamped list: its country opened (if it isn't), the camera close to it, its mark pressed
    func showOwn(_ id: String) {
        guard let w = world, let o = OwnPlaces.shared.place(id), let i = w.placeIndex[o.cc] else { return }
        ShowJob.n += 1
        placesCollection = nil; placesType = nil; placesPicked = true
        if placeOpen != i { openPlace(i) }
        let d: Float = 2, at = o.point
        ownPressed = id
        showBox(SIMD4(at.x - d, at.y - d, at.x + d, at.y + d), place: i)
    }

    /// A THING FOUND BY SEARCH: its country opened (if it isn't), then, once its things have come, the thing framed with
    /// its mark and name, then its card, as a tap on its mark gives (the towns' map shows only the things that are
    /// yours: one found was marked for two seconds and then gone, the map left on a spot with nothing on it)
    func showThing(file cc: String, id: String) {
        guard let w = world, let i = w.placeIndex[cc] else { return }
        ShowJob.n += 1
        let me = ShowJob.n
        // (one of the set looked at stays on its set's map; any other thing shows on the towns')
        if let c = placesCollection, CollectionStore.shared.collection(c)?.items.contains(where: { $0.id == id }) != true { placesCollection = nil; placesType = nil }
        placesPicked = true
        if placeOpen != i { openPlace(i) }
        Task { @MainActor [weak self] in
            for _ in 0 ..< 150 {
                if ThingStore.shared.things(cc) != nil || me != ShowJob.n { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard me == ShowJob.n else { return }
            guard let self, self.placeOpen == i, let t = ThingStore.shared.things(cc)?.first(where: { $0.id == id }) else { Feel.refuse(); return }
            self.thingPressed = id
            // (a tenth of a degree round it, as a set's landmark; its card will stand on the 25% water, 240 pt of the
            // map's room, so the box runs on under it by that share and the thing is framed in the room above the card)
            var b = SIMD4(t.at.x - 0.1, t.at.y - 0.1, t.at.x + 0.1, t.at.y + 0.1)
            let room = self.layout.room(sheetTop: self.layout.top(.quarter))
            let free = max(120, room.upperBound - room.lowerBound - 240)
            b.w += (b.w - b.y) * Float((room.upperBound - room.lowerBound) / free - 1)
            self.showBox(b, place: i)
            try? await Task.sleep(for: .milliseconds(1100))
            guard me == ShowJob.n, self.placeOpen == i, self.thingPressed == id else { return }
            self.needsFrame = true
            self.onThingFound?(id)
        }
    }

    /// A SET'S PLACE FOUND BY SEARCH: its set on the map, all of it (a kind picked could be another's); its country
    /// opened when it is one country's (the set narrowed to it, as a tap on the country does), the map over the place
    /// itself otherwise (a sea, a range, a peak two countries share); then its card, as a tap on its mark gives
    func showSetPlace(_ set: String, id: String) {
        guard placesMode, let w = world, let it = CollectionStore.shared.collection(set)?.items.first(where: { $0.id == id }) else { return }
        ShowJob.n += 1
        let me = ShowJob.n
        // (a kind picked stays when the place is of it: a lake picked from the lakes' own list keeps the lakes)
        if placesCollection != set || (placesType != nil && placesType != it.type) || !placesPicked { showPlacesSet(set) }
        let home = it.ccs.count == 1 ? (w.placeIndex[it.cc] ?? w.placeIndex[it.cc.uppercased()]) : nil
        if let home { if placeOpen != home { closePlace(); openPlace(home) } } else { closePlace() }
        let shaped = CollectionStore.shared.collection(set)?.shapes != nil
        Task { @MainActor [weak self] in
            // (a set of shapes just picked: its shapes are still coming, and without its own box a sea was framed as a
            // point, the screen all water)
            for _ in 0 ..< 40 {
                guard let self, me == ShowJob.n else { return }
                if !shaped || self.setScenes[set] != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, me == ShowJob.n, self.placesCollection == set else { return }
            // (the map goes to the place itself, with room round it: its shape and a third of it again on every side,
            // or a degree round its point; the whole of the United States with 70 marks said nothing of where
            // Yellowstone is)
            // (a landmark is a point in a town: a tenth of a degree round it, where its neighbours stand apart; at a
            // degree the Eiffel Tower was one of a blot of marks over Paris)
            let near = set == "landmarks"
            let half: Float = near ? 0.1 : 1
            var b = self.setScenes[set]?.box(it.id) ?? SIMD4(it.at.x - half, it.at.y - half, it.at.x + half, it.at.y + half)
            let least: Float = near ? 0.05 : 0.3
            let pad = SIMD2(max(least, (b.z - b.x) * 0.35), max(least, (b.w - b.y) * 0.35))
            b = SIMD4(b.x - pad.x, b.y - pad.y, b.z + pad.x, b.w + pad.y)
            // (its card will stand on the 25% water, 240 pt of the map's room: the box runs on under it by that share,
            // so the place itself is framed in the room above the card)
            let room = self.layout.room(sheetTop: self.layout.top(.quarter))
            let free = max(120, room.upperBound - room.lowerBound - 240)
            b.w += (b.w - b.y) * Float((room.upperBound - room.lowerBound) / free - 1)
            if let home { self.showBox(b, place: home) } else { self.showFree(b) }
            try? await Task.sleep(for: .milliseconds(1100))
            guard me == ShowJob.n, self.placesCollection == set else { return }
            self.thingPressed = id
            self.needsFrame = true
            self.onSeaTap?()
        }
    }

    /// your own place whose mark is under a screen point (within 22 pt of its point), or whose drawn outline it is inside
    func ownHit(at p: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for o in OwnPlaces.shared.all {
            let q = screenPoint(SIMD2(Double(o.point.x), Double(o.point.y)))
            if let r = o.ring, r.count > 2 {
                let path = CGMutablePath()
                for (i, c) in r.enumerated() {
                    let m = EqualEarth.project(lon: c[1], lat: c[0])
                    let s = screenPoint(SIMD2(Double(m.x), Double(m.y)))
                    if i == 0 { path.move(to: s) } else { path.addLine(to: s) }
                }
                path.closeSubpath()
                // (inside: as near as its middle; a smaller one inside a bigger one wins by being nearer)
                if path.contains(p) { let d = hypot(q.x - p.x, q.y - p.y); if best == nil || d < best!.1 { best = (o.id, d) }; continue }
            }
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= 22, best == nil || d < best!.1 { best = (o.id, d) }
        }
        return best?.0
    }
    /// A7.11 YOUR OWN PLACE MADE BY QUICK ADD: at the tapped point of the open country, named after the nearest town
    /// ("Near Kyoto"), stamped as it is made (with its region chain and country). From the land's hold menu (Add a
    /// place here) it is made unstamped, its card to follow.
    @discardableResult
    func makeOwnPlace(at p: CGPoint, stamp: Bool = true, ring: [DrawTool.Geo]? = nil) -> OwnPlaces.Place? {
        guard let open = placeOpen, let cc = placeOpenID else { return nil }
        // (a drawn place: its point is its outline's middle, the mean of its corners weighted by the edges round them)
        var m = mapPoint(p)
        if let r = ring, r.count > 2 {
            var sx = 0.0, sy = 0.0, sw = 0.0
            let q = r.map { EqualEarth.project(lon: $0.lon, lat: $0.lat) }
            for i in 0 ..< q.count {
                let a = q[i], b = q[(i + 1) % q.count]
                let w = Double(simd_distance(a, b))
                sx += Double(a.x + b.x) / 2 * w; sy += Double(a.y + b.y) / 2 * w; sw += w
            }
            if sw > 0 { m = SIMD2(sx / sw, sy / sw) }
        }
        let ll = EqualEarth.unproject(m)
        let mp = SIMD2(Float(m.x), Float(m.y))
        var near: String?
        if let sc = townScenes[cc] {
            var bd = Float.infinity
            for (i, a) in sc.at.enumerated() { let d = simd_distance_squared(a, mp); if d < bd { bd = d; near = sc.towns[i].name } }
        }
        let name = near.map { "Near \($0)" } ?? "Your place"
        let place = OwnPlaces.shared.make(name: name, lat: ll.lat, lon: ll.lon, cc: cc, ring: ring?.map { [$0.lat, $0.lon] })
        Feel.tap()
        needsFrame = true
        if stamp { Task { await TownStamps.stamp(place.key, name: place.name, cc: cc, source: .quick, place: open, at: mp) } }
        return place
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
            case .everywhere: ""
            case .continent(let k), .region(let k): k
            case .country: ""
            case .collection(let id): CollectionStore.shared.collection(id)?.title ?? ""
            }
        }
    }
    var placesPick: PlacesPick {
        if let i = placeOpen { return .country(i) }
        if let c = placesCollection { return .collection(c) }
        if let a = placesArea { return Self.continents.contains(a) ? .continent(a) : .region(a) }
        return .everywhere
    }
    static let continents = ["Africa", "Antarctica", "Asia", "Europe", "North America", "Oceania", "South America"]
    func showPlacesMap(_ pick: PlacesPick) {
        guard placesMode, world != nil else { return }
        // a card left up from the last map goes back into the water (a town's card stood over the world after Everywhere)
        CardState.shared.close(map: self); RegionCardState.shared.close(map: self)
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
    /// YOUR PLACES OF THE SET LOOKED AT, on the map up: a collection's places you stamped (in the open country, when
    /// one narrows it); the towns' set: your towns (of the open country, a continent, or everywhere)
    func stampedTowns(on pick: PlacesPick) -> Int {
        if let c = setCollection { return c.items.filter { MarkStore.shared.state($0.key).stamped }.count }
        if case .collection(let id) = pick {
            return CollectionStore.shared.collection(id)?.items.filter { MarkStore.shared.state($0.key).stamped }.count ?? 0
        }
        let ids: Set<String>? = members(of: pick).map { Set($0.compactMap { world?.places[$0].id.lowercased() }) }
        return MarkStore.shared.marks.filter { m in
            m.value.stamped && m.key.kind == .town && (ids?.contains(String(m.key.id.prefix { $0 != "/" })) ?? true)
        }.count
    }

    /// back to the world: the towns go, the world comes back (the camera stays where it is)
    func closePlace() {
        ownPressed = nil
        guard placeOpen != nil else { return }
        placeOpen = nil
        townPressed = nil
        closeRegions()
    }

    /// the collection whose places are the map's marks now: the set looked at; or, for Cities far out (the whole
    /// world or a continent on screen, where a town's own shape is nothing yet), the cities people know. Nearer, and
    /// in an open country, Cities is the towns' own shapes and this is nil
    var markCollection: CollectionStore.Collection? {
        if let c = setCollection {
            // (a long list with the whole world on screen: its best known and yours; a continent picked, the map
            // nearer, or a country opened: all of them)
            // (on the way somewhere, by where the map is going: flying out to the world, every park of the land
            // passed over came up for a moment and went again)
            let zoom = flight.map { exp($0.to.z) } ?? k
            return placeOpen == nil && continent == nil && zoom < longListK && c.items.count > CollectionStore.longList ? CollectionStore.shared.known(c) : c
        }
        guard placesMode, placesPicked, placesCollection == nil, placeOpen == nil, placesArea == nil, regionScene == nil,
              k < townsK else { return nil }
        return CollectionStore.shared.collection(CollectionStore.famousCities).map(onContinent)
    }
    /// a list cut down to the continent picked (its places in the flat blue beside it are not on this map)
    private func onContinent(_ c: CollectionStore.Collection) -> CollectionStore.Collection {
        guard let k = continent, let w = world else { return c }
        return CollectionStore.shared.within(c, continent: k) { cc in
            (w.placeIndex[cc] ?? w.placeIndex[cc.uppercased()]).map { w.inCont($0, k) } ?? false
        } ?? c
    }
    /// the set looked at (picked from the menu), narrowed to its kind and to the open country or the picked continent;
    /// nil for Cities
    var setCollection: CollectionStore.Collection? {
        guard placesMode, let id = placesCollection else { return nil }
        if let cc = placeOpenID, let i = placeOpen, let w = world {
            return CollectionStore.shared.narrowed(id, type: placesType, cc: cc) { w.place(at: $0) == i }
        }
        return CollectionStore.shared.typed(id, placesType).map(onContinent)
    }
    /// the area set's shapes that are up (the set looked at, once its shapes have come)
    var setScene: SetScene? { placesMode ? placesCollection.flatMap { setScenes[$0] } : nil }
    /// an area set's shapes read (from the data server, kept for the session)
    func loadSetShapes(_ id: String) {
        guard setScenes[id] == nil, !setLoading.contains(id), let path = CollectionStore.shared.collection(id)?.shapes else { return }
        setLoading.insert(id)
        Task.detached(priority: .userInitiated) { [weak self] in
            var scene: SetScene?
            if case .ok(let d) = await Servers.data.file(path), let s = UrbanFile.parse(d) { scene = SetScene(id: id, shapes: s) }
            await MainActor.run {
                guard let self else { return }
                self.setLoading.remove(id)
                if let scene { self.setScenes[id] = scene; self.needsFrame = true }
            }
        }
    }
    /// the shaped places of a scene that are yours: stamped, wished
    func setMarks(_ sc: SetScene) -> (stamped: [String], wished: [String]) {
        var st: [String] = [], wi: [String] = []
        // (only the places of the list that is up: a set cut down to its seas has no ocean filled)
        let up = markCollection.map { CollectionStore.shared.ids($0) }
        for (k, s) in MarkStore.shared.marks where k.kind == .thing && (s.stamped || s.wished) {
            let id = String(k.id.dropFirst(3))
            guard sc.runs[id] != nil, up?.contains(id) ?? true else { continue }
            if s.stamped { st.append(id) } else { wi.append(id) }
        }
        return (st, wi)
    }
    /// A SET'S PLACE IS ITS MARK (11 Nov: its own shape where it has one to see; otherwise the map's diamond, the same
    /// for every place): no shape of its own, or one still under 8 pt across
    func setMarkShown(_ it: CollectionStore.Item, _ scene: SetScene?) -> Bool {
        guard let scene, let a = scene.across(it.id) else { return true }
        // (every park has the mark, its boundary or not: half the parks as shapes and half as marks read as two kinds
        // of thing; the boundary is drawn as well where there is one)
        if scene.outlined { return true }
        // (a sea has no tint and no line: until it is wide enough for its name, about 6.5 pt a letter, its mark stands for it)
        return Double(a) * k < (scene.untinted ? Double(it.short.count) * 6.5 + 12 : 8)
    }
    /// the set looked at ("towns", or a collection's id)
    var placesSet: String { placesCollection == CollectionStore.capitals ? CollectionStore.towns : placesCollection ?? CollectionStore.towns }
    /// the kind it is cut down to (the menu's second lime bar), or nil
    var placesKind: String? { placesCollection == CollectionStore.capitals ? CollectionStore.capitals : placesType }

    /// A KIND PICKED under the set: the same set cut down to it; nil: all of it again
    func showPlacesType(_ t: String?) {
        guard placesMode else { return }
        CardState.shared.close(map: self); RegionCardState.shared.close(map: self)
        townPressed = nil; thingPressed = nil
        needsFrame = true
        if placesSet == CollectionStore.towns {
            placesType = nil
            placesCollection = t == nil ? nil : CollectionStore.capitals
            if t == nil, let cc = placeOpenID { loadTowns(cc) }
        } else { placesType = t }
        // (a kind of a few places spread over the world, the five oceans: the world, so they are in sight)
        if placeOpen == nil, placesArea == nil, let c = markCollection, c.items.count <= 12, let w = world {
            let xs = c.items.map(\.at.x)
            if let lo = xs.min(), let hi = xs.max(), hi - lo > w.width * 0.45 { goHome() }
        }
    }
    /// THE MENU AGAIN (a tap on the lime bar): no set picked, the map the cities' as it is when Places opens
    func clearPlacesSet() {
        guard placesMode else { return }
        CardState.shared.close(map: self); RegionCardState.shared.close(map: self)
        townPressed = nil; thingPressed = nil
        placesPicked = false; placesType = nil; placesCollection = nil
        needsFrame = true
    }

    /// A SET PICKED from Places' menu (9 Nov): its places on the map. The country open stays open (the set narrowed to
    /// it); a short list with no country open is framed whole (a season's circuits); a long one comes onto the map where
    /// it is.
    func showPlacesSet(_ id: String) {
        guard placesMode else { return }
        CardState.shared.close(map: self); RegionCardState.shared.close(map: self)
        townPressed = nil; thingPressed = nil
        needsFrame = true
        placesPicked = true; placesType = nil
        if id == CollectionStore.towns {
            placesCollection = nil
            if let cc = placeOpenID { loadTowns(cc) }
            return
        }
        placesCollection = id
        loadSetShapes(id)
        // (every set frames its places, a big one too: one spread over the world shows the world)
        guard placeOpen == nil, placesArea == nil, CollectionStore.shared.collection(id) != nil,
              let f = box(of: .collection(id)) else { return }
        if f.z - f.x > (world?.width ?? 1000) * 0.45 { goHome() }
        else { frameArea(SIMD4(Double(f.x), Double(f.y), Double(f.z), Double(f.w))) }
    }

    /// a collection's place whose mark is under a screen point (the collection's map up)
    func collectionHit(at p: CGPoint) -> CollectionStore.Item? {
        guard let items = markCollection?.items else { return nil }
        // a name up (TownNamesView keeps their frames), else the nearest mark within a fingertip (14 pt)
        for (q, f) in thingFrames where f.insetBy(dx: -4, dy: -6).contains(p) {
            if let it = items.first(where: { $0.id == q }) { return it }
        }
        let scene = setScene
        var best: (CollectionStore.Item, CGFloat)?
        for it in items where setMarkShown(it, scene) {
            let q = screenPoint(SIMD2(Double(it.at.x), Double(it.at.y)))
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= 14, best == nil || d < best!.1 { best = (it, d) }
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

    // MARK: TOWNS EVERYWHERE (7.4): with no country open, once the map is close (about 1,000 km across the screen)
    // the towns and things
    // of the countries in view are read and drawn as an open country's are, the nearest six at most
    /// the zoom from which they come
    var townsK: Double { Double(view.width) / 25 }
    /// the zoom from which a long list shows all of its places: half as near again as the whole world (Europe as a
    /// continent on screen is twice as near: its 600 parks stand apart there, where at the world's size they are a blot)
    var longListK: Double { worldKMin * 1.5 }
    /// the countries whose towns are drawn now: the open one's, else the ones in view close in
    var townCountries: [String] {
        // (Regions' towns level: the country's towns whatever Places looks at)
        if regionTowns, let cc = placeOpenID { return [cc] }
        // (a collection's map shows its own places only: no towns under them; and with no set picked the map shows
        // none: the menu is up and the map is its borders, 11 Nov)
        guard placesCollection == nil, placesPicked || !placesMode else { return [] }
        if let cc = placeOpenID { return [cc] }
        guard placesMode, regionScene == nil else { return [] }
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
        // one undo step for the town, its country and its regions, named by the town
        await MarkStore.shared.grouped { await stampChain(key, name: name, cc: cc, source: source, place: place, at: point, day: day) }
    }
    @MainActor
    private static func stampChain(_ key: PlaceKey, name: String, cc: String, source: MarkSource, place: Int?,
                                   at point: SIMD2<Float>?, day: String?) async {
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
        await MarkStore.shared.grouped { await unstampChain(key, name: name, cc: cc) }
    }
    @MainActor
    private static func unstampChain(_ key: PlaceKey, name: String, cc: String) async {
        await MarkStore.shared.unstamp(key, name: name)
        guard through.contains(cc) else { return }
        // still held by another stamped town or thing of it
        let held = MarkStore.shared.marks.contains { k, s in
            guard s.stamped else { return false }
            if k.kind == .town { return k.id.hasPrefix(cc + "/") }
            if k.kind == .thing { return (ThingStore.shared.thing(k.id)?.cc ?? ThingIndex.shared.hit(k.id)?.file) == cc }
            return false
        }
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

/// the latest town, thing or own place asked to be shown (a quicker second pick wins over the first one still waiting
/// for its country's towns)
@MainActor enum ShowJob { static var n = 0 }

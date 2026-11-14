import SwiftUI
import MapKit
import PhotosUI

// PINS (Part 8; 7 Nov: Apple's map,; one plain black pin until its
// colour is changed, the 16:37). First slice: Apple's map under the head and the water whenever Pins is the mode, the
// camera taken over from our map; hold the map 0.4 s and a pin drops there, named after the finest place it is in;
// tap a pin and the water shows its name and place; hold a pin for its menu. Pins are kept on the phone (pins.json).
// Still to come (8.5 to 8.8): the dock's tools (they need the icons first), the pin's sheet at 50%, routes, drawing.

/// ONE PIN
struct Pin: Codable, Identifiable, Hashable {
    var id = UUID()
    var lat: Double
    var lon: Double
    /// the name you gave it; empty: it reads its place
    var name = ""
    /// the finest place it is in ("Kreuzberg, Berlin"), filled once the phone has named it
    var place = ""
    /// the colour you gave it (the picker's own value); nil: the plain black
    var pick: ColourPick? = nil
    /// up to 600 characters
    var note: String? = nil
    var made = Date()
    /// the country our own map has under it (its id), when it is on land
    var cc: String? = nil
    /// its category, one of the twelve kinds a place of your own is filed under; nil: none given
    var kind: String? = nil
    /// its photo's file in Application Support/pin-photos, or nil
    var photo: String? = nil
    /// the map of yours it is in (Map/PinMaps.swift); nil: none (All pins only)
    var map: UUID? = nil
    /// gamma-encoded P3, or nil for the plain black
    var colour: [Double]? { pick.map { let v = $0.p3; return [v.x, v.y, v.z] } }

    /// A PIN HAS NO NAME UNLESS YOU GIVE IT ONE (12 Nov):
    /// your name; else where it is, its region and country ("Bavaria, Germany"); else its coordinates
    var title: String { !name.isEmpty ? name : !region.isEmpty ? region : coordinates }
    /// its region and country from its place (a pin read before 12 Nov held its finest spot first, "Kreuzberg, Berlin,
    /// Germany": that first word is left out; the pin itself is never rewritten)
    var region: String {
        var parts = place.components(separatedBy: ", ").filter { !$0.isEmpty }
        if parts.count >= 3 { parts = Array(parts.suffix(2)) }
        // (its country as our map names it: Apple's "Türkiye" beside the map's "Turkey"; shown so, never rewritten)
        if let cc, let ours = Self.countryNames[cc], let last = parts.last, last != ours, Self.appleNames[cc]?.contains(last) == true {
            parts[parts.count - 1] = ours
        }
        return parts.joined(separator: ", ")
    }
    /// our map's name for each country (its id to its name), set once the map is there
    nonisolated(unsafe) static var countryNames: [String: String] = [:]
    /// the country it is in, by our map's name for it (nil off land, or before the map has named countries)
    var countryName: String? { cc.flatMap { Self.countryNames[$0] } }
    /// the names Apple's naming may have given each country (in English and in the phone's language): only those are
    /// swapped, so a place's last part that is a city ("Kreuzberg, Berlin") stays
    nonisolated(unsafe) static var appleNames: [String: Set<String>] = [:]
    /// "48.8566° N, 2.3522° E"
    var coordinates: String {
        String(format: "%.4f° %@, %.4f° %@", abs(lat), lat >= 0 ? "N" : "S", abs(lon), lon >= 0 ? "E" : "W")
    }
    /// the pins just dropped whose place is still being asked for (a second or so)
    nonisolated(unsafe) static var naming: Set<UUID> = []
    /// the title as it is drawn (its coordinates while its place is asked for: never a made-up name)
    var shownTitle: String { title }
    /// under its title: where it is, when it has your name; its day
    var line: String {
        let day = made.formatted(.dateTime.day().month(.abbreviated).year())
        let rest = name.isEmpty ? "" : region
        return rest.isEmpty ? day : "\(rest) · \(day)"
    }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// YOUR PINS, kept in Application Support/pins.json (written on every change; no Save, 22 Oct 18:30)
@MainActor
@Observable
final class PinStore {
    static let shared = PinStore()
    private(set) var pins: [Pin] = []
    /// the pin whose sheet is up (its name and place in the water)
    var selected: UUID?
    /// a pin just dropped: its view falls into place once it is on the map
    @ObservationIgnored var dropping: UUID?
    /// the hold menu's Colour: the chosen pin's sheet opens with the picker out
    var colourAsked = false
    /// a name or a note is being typed (the one time Pins' water goes to full: the keyboard needs the room)
    var typing = false
    /// a test's ask: the chosen pin's sheet scrolled to its end (its last rows filmed)
    var endAsked = 0

    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("pins.json")
    }
    init() {
        guard let u = url, let d = try? Data(contentsOf: u) else { return }
        if let p = try? JSONDecoder().decode([Pin].self, from: d) { pins = p } else { PinRoutes.putAside(u) }
    }
    private func save() {
        guard let u = url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(pins) { try? d.write(to: u, options: .atomic) }
    }
    func pin(_ id: UUID?) -> Pin? { id.flatMap { i in pins.first { $0.id == i } } }

    /// a pin dropped at `c`: kept at once, named once the phone knows the place; the undo drop takes it back.
    /// `country`: the country our own map has there, for when Apple's naming gives none (open desert, small islands)
    /// `known`: the place's own name when the pin is dropped on a place found in search (Apple's nearest name for
    /// a town's middle can be a hamlet's)
    func drop(at c: CLLocationCoordinate2D, country: (id: String, name: String)? = nil, known: String? = nil) {
        var p = Pin(lat: c.latitude, lon: c.longitude)
        p.cc = country?.id
        p.map = PinMaps.shared.shown
        dropping = p.id
        Pin.naming.insert(p.id)
        pins.append(p)
        selected = p.id
        save()
        undoableDrop(p.id)
        Task { await name(p.id, country: country?.name, known: known) }
        if MapSettingsStore.shared.value.pinMarksPlace, let cc = country?.id.lowercased() { markNear(c, cc: cc) }
    }
    /// TRACKING (Map/PinTracker.swift): a pin where you were, in the tracked map, named as any other; never chosen,
    /// never an undo step (nothing was done by hand)
    func track(at c: CLLocationCoordinate2D, map: UUID, when: Date) {
        var p = Pin(lat: c.latitude, lon: c.longitude)
        p.map = map
        p.kind = "tracked"
        p.made = when
        // (its country from our own map when the map is there; else the map names it when it next loads)
        if let m = PinsMapState.shared.map { p.cc = PinsMapView.Coordinator.country(m, c)?.id }
        Pin.naming.insert(p.id)
        pins.append(p)
        save()
        Task { await name(p.id, country: nil) }
    }
    /// A PIN NEAR A PLACE MARKS IT (Map settings, Off by default): a pin dropped within 200 m of a thing of the
    /// country (a museum, a lake's point, a station) stamps that thing, the nearest one, as "a pin near a place"; the
    /// pin itself is never stamped. One undo step of its own.
    private func markNear(_ c: CLLocationCoordinate2D, cc: String) {
        let things = ThingStore.shared
        things.load(cc)
        Task {
            for _ in 0 ..< 50 where things.things(cc) == nil { try? await Task.sleep(for: .milliseconds(100)) }
            let k = cos(c.latitude * .pi / 180)
            var best: (Double, ThingStore.Thing)?
            for t in things.things(cc) ?? [] {
                let ll = EqualEarth.unproject(SIMD2(Double(t.at.x), Double(t.at.y)))
                var dx = ll.lon - c.longitude
                if dx > 180 { dx -= 360 } else if dx < -180 { dx += 360 }
                // metres, near enough for 200 m
                let d = ((dx * k) * (dx * k) + (ll.lat - c.latitude) * (ll.lat - c.latitude)).squareRoot() * 111_195
                if d <= 200, d < best?.0 ?? .infinity { best = (d, t) }
            }
            guard let t = best?.1, !MarkStore.shared.state(t.key).stamped else { return }
            Feel.stamp()
            await MarkStore.shared.stamp(t.key, name: t.name, cc: cc, source: .pinNear)
        }
    }
    /// DROP A PIN HERE (11.5's town or thing menu): a pin at a place's point, named after it; not chosen, and nothing
    /// else changes until Pins is opened; the undo drop takes it back
    func drop(at c: CLLocationCoordinate2D, named: String, country: (id: String, name: String)?) {
        var p = Pin(lat: c.latitude, lon: c.longitude)
        p.cc = country?.id
        p.map = PinMaps.shared.shown
        p.place = [named, country?.name ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        pins.append(p)
        save()
        undoableDrop(p.id)
    }
    /// a dropped pin's undo takes it away; its redo puts it back as it was then (named, coloured, routes with it)
    private func undoableDrop(_ id: UUID) {
        let box = UndoBox<(Pin, Int, [PinRoute])>()
        MarkStore.shared.did("Pin dropped", back: { [weak self] in
            guard let self, let k = self.pins.firstIndex(where: { $0.id == id }) else { return }
            let p = self.pins[k]
            box.value = (p, k, self.remove(id, undoable: false))
        }, forth: { [weak self] in
            guard let self, let (p, k, routes) = box.value, self.pin(id) == nil else { return }
            self.pins.insert(p, at: min(k, self.pins.count)); self.save()
            PinRoutes.shared.restore(routes)
        })
    }
    /// gives back the routes that went with it
    @discardableResult func remove(_ id: UUID, undoable: Bool = true) -> [PinRoute] {
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return [] }
        let gone = pins.remove(at: k)
        if selected == id { selected = nil }
        let routes = PinRoutes.shared.pinGone(id)
        save()
        if undoable {
            MarkStore.shared.did("\(gone.title) deleted", back: { [weak self] in
                guard let self, self.pin(id) == nil else { return }
                self.pins.insert(gone, at: min(k, self.pins.count)); self.save()
                PinRoutes.shared.restore(routes)
            }, forth: { [weak self] in self?.remove(id, undoable: false) })
        }
        return routes
    }
    /// MOVE A PIN (8.4): set down somewhere else by a drag; its place is read again there (a name you gave it stays);
    /// the undo puts it back where it was, with its old place
    func move(_ id: UUID, to c: CLLocationCoordinate2D, country: (id: String, name: String)?) {
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return }
        let was = pins[k]
        pins[k].lat = c.latitude
        pins[k].lon = c.longitude
        pins[k].cc = country?.id
        save()
        let box = UndoBox<Pin>()
        MarkStore.shared.did("\(was.title) moved", back: { [weak self] in
            guard let self, let j = self.pins.firstIndex(where: { $0.id == id }) else { return }
            box.value = self.pins[j]
            self.pins[j].lat = was.lat; self.pins[j].lon = was.lon; self.pins[j].cc = was.cc; self.pins[j].place = was.place
            self.save()
            PinRoutes.shared.pinMoved(id)
        }, forth: { [weak self] in
            guard let self, let now = box.value, let j = self.pins.firstIndex(where: { $0.id == id }) else { return }
            self.pins[j].lat = now.lat; self.pins[j].lon = now.lon; self.pins[j].cc = now.cc; self.pins[j].place = now.place
            self.save()
            PinRoutes.shared.pinMoved(id)
        })
        PinRoutes.shared.pinMoved(id)
        Task { await name(id, country: country?.name) }
    }
    func rename(_ id: UUID, _ name: String) {
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[k].name = String(name.prefix(60))
        save()
    }
    /// live while the finger moves in the picker; kept as it changes (no Save)
    func colour(_ id: UUID, _ c: ColourPick?) {
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[k].pick = c
        save()
    }
    /// the picker out for a pin: the colour it had then, so the picker going away makes one undo of all its moves
    @ObservationIgnored private var colourWas: (id: UUID, pick: ColourPick?)?
    func colourStart(_ id: UUID) {
        if colourWas?.id == id { return }
        colourEnd()
        colourWas = (id, pin(id)?.pick)
    }
    func colourEnd() {
        guard let was = colourWas else { return }
        colourWas = nil
        guard let p = pin(was.id), p.pick != was.pick else { return }
        let now = p.pick, id = was.id
        MarkStore.shared.did("\(p.title) colour changed", back: { [weak self] in self?.colour(id, was.pick) },
                             forth: { [weak self] in self?.colour(id, now) })
    }
    func note(_ id: UUID, _ n: String) {
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[k].note = n.isEmpty ? nil : String(n.prefix(600))
        save()
    }
    /// PINS NAMED BEFORE THE COUNTRY WAS KEPT (the first days' pins: "Bordj Omar Driss" alone, where a new pin there is
    /// "Bordj Omar Driss, Algeria"): a pin on land whose place is one name gets the country our map has under it, so
    /// every row of the list says where it is. A pin at sea, or one named as its country, stays as it is.
    func nameCountries(_ country: (CLLocationCoordinate2D) -> (id: String, name: String)?) {
        var changed = false
        // (a pin with no country yet, a tracked one say, gets the one our map has under it)
        for k in pins.indices where pins[k].cc == nil {
            guard let c = country(pins[k].coordinate) else { continue }
            pins[k].cc = c.id
            changed = true
        }
        for k in pins.indices where !pins[k].place.isEmpty && !pins[k].place.contains(", ") {
            guard let c = country(pins[k].coordinate), c.name != pins[k].place else { continue }
            pins[k].place += ", " + c.name
            if pins[k].cc == nil { pins[k].cc = c.id }
            changed = true
        }
        if changed { save() }
    }
    /// its category (3 Oct: a pin is filed under one of the twelve kinds, as a place of your own is); nil: none
    func kind(_ id: UUID, _ kind: String?) {
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[k].kind = kind
        save()
    }
    /// its photo (3 Oct): the picture kept beside pins.json, no bigger than 1,600 px on its longer side; nil takes it
    /// away. A pin deleted keeps its file (its undo brings the pin back with it)
    func photo(_ id: UUID, _ data: Data?) {
        guard let k = pins.firstIndex(where: { $0.id == id }), let dir = Self.photos else { return }
        if let old = pins[k].photo {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(old))
            Self.shown.removeObject(forKey: old as NSString)
        }
        pins[k].photo = nil
        if let data, let full = UIImage(data: data) {
            let longer = max(full.size.width, full.size.height)
            let scale = min(1, 1600 / max(1, longer))
            let small = scale < 1 ? full.preparingThumbnail(of: CGSize(width: full.size.width * scale, height: full.size.height * scale)) ?? full : full
            let name = UUID().uuidString + ".jpg"
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let jpeg = small.jpegData(compressionQuality: 0.85), (try? jpeg.write(to: dir.appendingPathComponent(name), options: .atomic)) != nil {
                pins[k].photo = name
            }
        }
        save()
    }
    private static var photos: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("pin-photos")
    }
    private static let shown = NSCache<NSString, UIImage>()
    /// a pin's photo, read once
    static func image(_ p: Pin) -> UIImage? {
        guard let name = p.photo, let dir = photos else { return nil }
        if let i = shown.object(forKey: name as NSString) { return i }
        guard let i = UIImage(contentsOfFile: dir.appendingPathComponent(name).path) else { return nil }
        shown.setObject(i, forKey: name as NSString)
        return i
    }

    /// Share (the hold menu's and the sheet's): Apple Maps' link to the spot, under its name
    static func share(_ p: Pin) {
        guard let u = URL(string: "https://maps.apple.com/?ll=\(p.lat),\(p.lon)&q=\(p.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Pin")")
        else { return }
        var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        while let next = top?.presentedViewController { top = next }
        top?.present(UIActivityViewController(activityItems: [u], applicationActivities: nil), animated: true)
    }
    /// Directions: Apple Maps to the pin
    static func directions(_ p: Pin) {
        let item = MKMapItem(location: CLLocation(latitude: p.lat, longitude: p.lon), address: nil)
        item.name = p.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
    /// the page of the finest place a pin is in that has one (11.5): the town within 15 km of it, else its country;
    /// nil at sea
    static func page(_ p: Pin, world: World?) -> (() -> Void)? {
        guard let cc = p.cc else { return nil }
        let country = world?.placeIndex[cc].map { world!.places[$0].n } ?? ""
        if let t = TownIndex.shared.nearest(lat: p.lat, lon: p.lon), t.file.lowercased() == cc.lowercased() {
            let parents = [t.region, country].filter { !$0.isEmpty }.joined(separator: ", ")
            return { PlacePageState.shared.open(PlaceKey(.town, t.id), name: t.name, what: "Town in \(parents)", country: t.file, from: Self.from) }
        }
        return { PlacePageState.shared.open(.country(cc), name: country, country: cc, from: Self.from) }
    }
    /// where a page opened from a pin grows from (the pin's box on screen, set as its menu opens)
    static var from = CGRect(x: 0, y: 0, width: 44, height: 44)

    /// the finest place a pin is in, from Apple's reverse geocoding: "Kreuzberg, Berlin"; a town alone; a region and
    /// its country; the sea's name at sea
    private func name(_ id: UUID, country ours: String?, known: String? = nil) async {
        // (asked or not, answered or not: the pin has its name from here, "Pin" if nothing came)
        defer {
            Pin.naming.remove(id)
            if let k = pins.firstIndex(where: { $0.id == id }) { pins[k] = pins[k] }
        }
        guard let p = pin(id), let req = MKReverseGeocodingRequest(location: CLLocation(latitude: p.lat, longitude: p.lon)) else { return }
        let item = try? await req.mapItems.first
        let a = item?.addressRepresentations
        // (its region: the city it is in, else the state or province; never the nearest landmark or street, which
        // read as a name the pin never had, 12 Nov)
        let region = a?.cityName ?? ""
        // (the country as our map names it, where our map has one there; Apple's own name only at sea or past our map)
        let country = ours ?? a?.regionName.flatMap { $0.isEmpty ? nil : $0 } ?? ""
        _ = known
        var parts: [String] = []
        for x in [region, country] where !x.isEmpty && !parts.contains(x) { parts.append(x) }
        let place = parts.joined(separator: ", ")
        // the pin still where it was read (a move, or its undo, while Apple was answering, reads it again)
        guard let k = pins.firstIndex(where: { $0.id == id }), pins[k].lat == p.lat, pins[k].lon == p.lon else { return }
        pins[k].place = place
        save()
    }
}

/// what the zoom column and the camera hand-over need from Apple's map
@MainActor
final class PinsMapState {
    static let shared = PinsMapState()
    weak var view: MKMapView?
    weak var water: Water?
    weak var map: MapController?
    /// the place last found in search and shown (its name and point): Add pin on it drops the pin at that point, named
    /// after it
    var found: (name: String, lat: Double, lon: Double)?
    /// a pin being moved (8.4): the pin's spot from the finger, and the pin's drawn middle from its spot, as it was
    /// picked up (so it is set down tip first where the finger lets go, and lands where it is drawn)
    /// (one per pin: two fingers can move two pins at once). `middle` is the view's own centre, without its transform,
    /// which is kept to land with (a chosen pin lands still chosen)
    var held: [UUID: (spot: CGPoint, middle: CGPoint, transform: CGAffineTransform)] = [:]
    /// where each pin being moved was set down (Apple's map points)
    var landing: [UUID: CGPoint] = [:]
    func zoom(by f: Double) {
        guard let v = view else { return }
        let cam = v.camera.copy() as! MKMapCamera
        let was = cam.centerCoordinateDistance
        cam.centerCoordinateDistance = max(Self.closest, min(Self.farthest, was / f))
        held(cam, v, cam.centerCoordinateDistance > 0 ? was / cam.centerCoordinateDistance : 1)
        v.setCamera(cam, animated: true)
    }
    /// the camera's middle moved so the middle of what you see (between the head and the water) stays where it is
    /// on the screen while the zoom changes by `f` (as our own map's + and −)
    private func held(_ cam: MKMapCamera, _ v: MKMapView, _ f: Double) {
        guard let m = map, f.isFinite, f > 0, abs(f - 1) > 1e-6 else { return }
        let y = m.roomMiddle
        guard y > 0, y < v.bounds.height else { return }
        let p = MKMapPoint(v.convert(CGPoint(x: v.bounds.midX, y: y), toCoordinateFrom: v))
        let c = MKMapPoint(cam.centerCoordinate)
        let n = MKMapPoint(x: p.x + (c.x - p.x) / f, y: p.y + (c.y - p.y) / f)
        let ll = n.coordinate
        guard CLLocationCoordinate2DIsValid(ll), abs(ll.latitude) < 85 else { return }
        cam.centerCoordinate = ll
    }
    /// one frame of a held + or − (no animation of its own: the hold moves it frame by frame); false once at a limit
    func zoomStep(_ f: Double) -> Bool {
        guard let v = view else { return false }
        let cam = v.camera.copy() as! MKMapCamera
        let was = cam.centerCoordinateDistance
        cam.centerCoordinateDistance = max(Self.closest, min(Self.farthest, was / f))
        held(cam, v, cam.centerCoordinateDistance > 0 ? was / cam.centerCoordinateDistance : 1)
        v.setCamera(cam, animated: false)
        limits()
        return abs(v.camera.centerCoordinateDistance - was) > 0.5
    }
    /// as close and as far as + and − take Apple's map
    static let closest = 150.0, farthest = 4.0e7
    /// the zoom column's dimmed + and − from Apple's camera: out as far as it goes (the whole world across), or in
    func limits() {
        guard let v = view, let m = map else { return }
        let out = v.visibleMapRect.width >= MKMapSize.world.width * 0.98 || v.camera.centerCoordinateDistance >= Self.farthest * 0.98
        m.pinsLimits(out: out, close: v.camera.centerCoordinateDistance <= Self.closest * 1.05)
    }
    /// our map's view of the world, on Apple's map: the same middle, the same span of latitude
    /// HISTORY IN PINS (Part 13's table: your pins by their date): one line through them from the oldest to the newest,
    /// as the journey on our own map: straight legs (a leg over 180 degrees goes the short way, across the date line),
    /// 2.5 pt, round ends, no edge, one black (12 Nov 17:57; it was black at the first pin to blue at the last).
    /// With fewer than two pins there is nothing to join and the tool refuses.
    private(set) var historyOn = false
    private var journey: MKPolyline?
    /// the pins' order and places the line was drawn for (a pin moved, re-dated, made or deleted redraws it)
    private var journeyKey = ""
    /// where the map was before history framed the journey (put back when history goes off; 9 Nov audit: the map
    /// stayed on the journey's frame, the open Atlantic, after history closed)
    private var beforeHistory: MKMapCamera?
    @discardableResult func history(_ on: Bool) -> Bool {
        let was = historyOn
        historyOn = on && PinStore.shared.pins.count > 1
        if !historyOn { stopPlay() }
        // turned off: the line draws itself back to the first pin (0.35 s) as the map goes back, then goes (at once,
        // it vanished in one frame, 17:50)
        if was, !historyOn, let v = view, let j = journey, !UIAccessibility.isReduceMotionEnabled {
            journey = nil
            retract(j, on: v)
        } else {
            redrawHistory()
        }
        if was, !historyOn, let v = view, let back = beforeHistory { v.setCamera(back, animated: true) }
        if !historyOn { beforeHistory = nil }
        if !was, historyOn, let v = view { beforeHistory = v.camera.copy() as? MKMapCamera }
        // HISTORY ALONE (when history is shown, all else is clear): routes and drawings step off the map
        // while it is on, and come back when it goes
        // (turned off with the journey drawing itself back: they come back once it has gone, never over it)
        if was != historyOn, retracting == nil { redrawRoutes(); PinDrawings.shared.changed?() }
        // turned on: the journey played, stop to stop, then framed whole; given again (on while on): framed at once
        if historyOn, !was, view != nil, journey != nil, !UIAccessibility.isReduceMotionEnabled { play() } else if historyOn { frameJourney() }
        updateCaps()
        return historyOn || !on
    }
    /// the whole journey framed between the head and the water at its stop (as on our own map, 13.4); the top clears
    /// a pin's own height under the head
    private func frameJourney() {
        guard let v = view, let j = journey else { return }
        // (the map's margins are the head and the water already: only the gaps are padding. Given again, the journey
        // was framed in a third of its room)
        // (Apple's flat map goes no further out than about 85 degrees across on this phone: a journey wider than
        // that is framed on its middle, as far out as the map goes)
        v.setVisibleMapRect(j.boundingMapRect, edgePadding: Self.journeyPad, animated: true)
    }
    private static let journeyPad = UIEdgeInsets(top: 30 + 16, left: 32, bottom: 32, right: 60)

    // THE JOURNEY PLAYED (every time history is
    // switched on): the line draws itself from the oldest pin to the newest, the map following its end, easing into
    // each pin and out of it again (one equal step of time per leg, about 3 s in all), then the whole journey framed.
    // Any touch on the map ends it there: the line whole, the journey framed. Reduce Motion: framed at once.
    private var playLink: CADisplayLink?
    private var playFrom: CFTimeInterval = 0
    private var playLength: CFTimeInterval = 3
    private var playStops: [MKMapPoint] = []
    /// how far along the line each stop is (0 to 1)
    private var playAt: [Double] = []
    private var playCentre = MKMapPoint()
    private var playWidth = 0.0
    private var playSkip: UILongPressGestureRecognizer?
    private let playSkipDelegate = SimultaneousTouch()
    /// (this state is not an Objective-C object: the link and the touch watcher call it through these)
    private lazy var playTick = Fire { [weak self] in self?.playStep() }
    private lazy var playTouch = Fire { [weak self] in
        guard let self, self.playSkip?.state == .began, self.playLink != nil else { return }
        self.stopPlay()
        self.frameJourney()
    }

    private func play() {
        guard let v = view, let j = journey, j.pointCount > 1 else { frameJourney(); return }
        stopPlay()
        let pts = UnsafeBufferPointer(start: j.points(), count: j.pointCount).map { $0 }
        var at: [Double] = [0]
        var total = 0.0
        for k in 1 ..< pts.count { total += hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y); at.append(total) }
        playStops = pts
        playAt = total > 0 ? at.map { $0 / total } : at
        let legs = pts.count - 1
        playLength = min(3.6, max(2.4, 0.35 * Double(legs)))
        playCentre = MKMapPoint(x: v.visibleMapRect.midX, y: v.visibleMapRect.midY)
        playWidth = v.visibleMapRect.width
        (v.renderer(for: j) as? JourneyRenderer).map { $0.progress = 0; $0.setNeedsDisplay() }
        if playSkip == nil {
            let g = UILongPressGestureRecognizer(target: playTouch, action: #selector(Fire.fire))
            g.minimumPressDuration = 0
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
            g.delegate = playSkipDelegate
            v.addGestureRecognizer(g)
            playSkip = g
        }
        playSkip?.isEnabled = true
        playFrom = CACurrentMediaTime()
        let link = CADisplayLink(target: playTick, selector: #selector(Fire.fire))
        link.add(to: .main, forMode: .common)
        playLink = link
    }
    private func playStep() {
        guard let v = view, let j = journey, playStops.count > 1 else { stopPlay(); return }
        let legs = playStops.count - 1
        let t = min(1, (CACurrentMediaTime() - playFrom) / playLength)
        let k = min(legs - 1, Int(t * Double(legs)))
        let u = t * Double(legs) - Double(k)
        // eased into each pin and out of it (smoothstep), so it reads as going place to place
        let e = u * u * (3 - 2 * u)
        let a = playStops[k], b = playStops[k + 1]
        let tip = MKMapPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
        (v.renderer(for: j) as? JourneyRenderer).map { $0.progress = playAt[k] + (playAt[k + 1] - playAt[k]) * e; $0.setNeedsDisplay() }
        // the map follows the line's end, wide enough for the leg it is on (a little room round it), never closer
        // than about 60 km across
        let leg = max(abs(b.x - a.x), abs(b.y - a.y) * Double(v.bounds.width / max(1, v.bounds.height)))
        let want = max(leg * 1.8, MKMapPointsPerMeterAtLatitude(tip.coordinate.latitude) * 60_000)
        playCentre = MKMapPoint(x: playCentre.x + (tip.x - playCentre.x) * 0.12, y: playCentre.y + (tip.y - playCentre.y) * 0.12)
        playWidth += (want - playWidth) * 0.08
        let h = playWidth * Double(v.bounds.height / max(1, v.bounds.width))
        v.setVisibleMapRect(MKMapRect(x: playCentre.x - playWidth / 2, y: playCentre.y - h / 2, width: playWidth, height: h),
                            edgePadding: Self.journeyPad, animated: false)
        if t >= 1 { stopPlay(); frameJourney() }
        updateCaps()
    }
    /// the play ended (or never ran): the line whole, the touch watcher off
    private var retractLink: CADisplayLink?
    private lazy var retractTick = Fire { [weak self] in self?.retractStep() }
    private var retracting: (line: MKPolyline, from: CFTimeInterval)?
    private func retract(_ j: MKPolyline, on v: MKMapView) {
        retractLink?.invalidate()
        if let old = retracting { v.removeOverlay(old.line) }
        retracting = (j, CACurrentMediaTime())
        let link = CADisplayLink(target: retractTick, selector: #selector(Fire.fire))
        link.add(to: .main, forMode: .common)
        retractLink = link
    }
    private func retractStep() {
        guard let v = view, let r = retracting else { retractLink?.invalidate(); retractLink = nil; return }
        let t = min(1, (CACurrentMediaTime() - r.from) / 0.35)
        // (ease in: it leaves slowly, then quickly)
        let e = t * t
        (v.renderer(for: r.line) as? JourneyRenderer).map { $0.progress = 1 - e; $0.setNeedsDisplay() }
        if t >= 1 {
            v.removeOverlay(r.line)
            retracting = nil
            retractLink?.invalidate()
            retractLink = nil
            // the routes and drawings back, now the journey has gone (History alone)
            if !historyOn { redrawRoutes(); PinDrawings.shared.changed?() }
        }
    }

    private func stopPlay() {
        playLink?.invalidate()
        playLink = nil
        playSkip?.isEnabled = false
        if let v = view, let j = journey { (v.renderer(for: j) as? JourneyRenderer).map { $0.progress = 1; $0.setNeedsDisplay() } }
        updateCaps()
    }
    /// the line as the pins now are (the new one is on the map before the old one goes, so it never blinks)
    func redrawHistory() {
        guard let v = view else { return }
        let old = journey
        journey = nil
        let pins = PinStore.shared.pins.sorted { $0.made < $1.made }
        journeyKey = historyOn ? pins.map { "\($0.id)\($0.lat),\($0.lon)" }.joined(separator: "|") : ""
        if historyOn, pins.count > 1 {
            let W = MKMapSize.world.width
            var pts: [MKMapPoint] = []
            for p in pins {
                var m = MKMapPoint(p.coordinate)
                if let last = pts.last {
                    while m.x - last.x > W / 2 { m.x -= W }
                    while last.x - m.x > W / 2 { m.x += W }
                }
                pts.append(m)
            }
            let j = MKPolyline(points: pts, count: pts.count)
            journey = j
            v.addOverlay(j, level: .aboveRoads)
        }
        if let old { v.removeOverlay(old) }
    }
    /// THE JOURNEY'S START AND END CAPSULES (12 Nov: the two histories the same, as on our map): the oldest pin's
    /// "name · month year" from the first moment, the newest's once the line has arrived
    private let caps = JourneyCaps()
    func updateCaps() {
        guard historyOn, let v = view, let j = journey, let w = water else { caps.hide(); return }
        let pins = PinStore.shared.pins.sorted { $0.made < $1.made }
        guard let a = pins.first, let b = pins.last else { caps.hide(); return }
        let pts = UnsafeBufferPointer(start: j.points(), count: j.pointCount).map { $0 }
        let progress = (v.renderer(for: j) as? JourneyRenderer)?.progress ?? 1
        caps.update(v, line: pts, words: (Self.capWords(a), Self.capWords(b)), progress: progress, L: w.layout, sheetTop: w.form().top)
    }
    private static func capWords(_ p: Pin) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "MMM yyyy"
        return "\(p.shownTitle) · \(f.string(from: p.made))"
    }
    /// the line again when the pins changed under it
    func historyNeedsRedraw(_ pins: [Pin]) -> Bool {
        historyOn && pins.sorted { $0.made < $1.made }.map { "\($0.id)\($0.lat),\($0.lon)" }.joined(separator: "|") != journeyKey
    }
    // ROUTES (8.3): the kept routes' lines and labels on Apple's map, and while the Route row is open Apple's other ways
    @ObservationIgnored private var routeOverlays: [MKOverlay] = []
    @ObservationIgnored private var routeLabels: [RouteLabel] = []
    /// THE CAMERA ON THE MAP PICKED: all its pins, routes and drawings in sight above the water (nothing in it: left
    /// where it is)
    func frameShownMap() {
        guard let v = view else { return }
        let maps = PinMaps.shared
        var c: [CLLocationCoordinate2D] = PinStore.shared.pins.filter { maps.shows(pin: $0.map) }.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        for r in PinRoutes.shared.routes where maps.shows(extra: r.map) { c += r.points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } }
        for d in PinDrawings.shared.all where maps.shows(extra: d.map) { c += d.points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) } }
        guard !c.isEmpty else { return }
        var r = MKMapRect.null
        for p in c { let q = MKMapPoint(p); r = r.union(MKMapRect(x: q.x, y: q.y, width: 0, height: 0)) }
        // a lone pin (or pins close together): never closer than a town's width
        let least = 20_000.0
        if r.width < least { r = r.insetBy(dx: -(least - r.width) / 2, dy: 0) }
        if r.height < least { r = r.insetBy(dx: 0, dy: -(least - r.height) / 2) }
        r = r.insetBy(dx: -r.width * 0.08, dy: -r.height * 0.08)
        let L = water?.layout
        // the map seen above the water where it is now (at full, as at half: framed for when it comes down)
        let bottom = water.map { w in w.layout.H - w.y(w.stop == .full ? .half : w.stop) + 16 } ?? 240
        let top = L.map { $0.headBottom + 16 } ?? 120
        let left = 24.0, right = 64.0
        // worked out here, not by Apple's edge padding (with the water at 50% it left half the pins out): the scale
        // that fits the pins in the seen part, and the whole view's rect around it, the pins in the seen part's middle
        let b = v.bounds
        guard b.width > left + right + 40, b.height > top + bottom + 40 else { return }
        let seenW = Double(b.width - left - right), seenH = Double(b.height - top - bottom)
        // Apple's flat map goes no further out than about 62 million map points across (a quarter of the world; read
        // on the iPhone 18 Pro Max, 13 Nov): pins from Brazil to Iran asked for more, and Apple put the map on the
        // open Atlantic. Pins that don't fit get that width, centred on their middle
        let per = min(max(r.width / seenW, r.height / seenH), 6.2e7 / Double(b.width))
        let midX = Double(left) + seenW / 2, midY = Double(top) + seenH / 2
        let whole = MKMapRect(x: r.midX - midX * per, y: r.midY - midY * per,
                              width: Double(b.width) * per, height: Double(b.height) * per)
        v.setVisibleMapRect(whole, animated: true)
    }

    func redrawRoutes() {
        guard let v = view else { return }
        let r = PinRoutes.shared
        var lines: [MKOverlay] = [], labels: [RouteLabel] = []
        // the other ways first, under the chosen one
        for (n, (pl, d, t)) in r.otherWays.enumerated() {
            var c = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pl.pointCount)
            pl.getCoordinates(&c, range: NSRange(location: 0, length: pl.pointCount))
            let l = PinRouteLine(coordinates: c, count: c.count)
            l.other = true; l.index = n; l.distance = d; l.time = t
            lines.append(l)
        }
        for route in r.routes where route.points.count > 1 && !historyOn && PinMaps.shared.shows(extra: route.map) {
            let c = route.points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            let l = PinRouteLine(coordinates: c, count: c.count)
            l.routeID = route.id
            lines.append(l)
            labels.append(RouteLabel(id: route.id, at: c[c.count / 2], words: route.words))
        }
        // the new ones on before the old ones go (never a blink)
        v.addOverlays(lines, level: .aboveRoads)
        v.addAnnotations(labels)
        v.removeOverlays(routeOverlays)
        v.removeAnnotations(routeLabels)
        routeOverlays = lines; routeLabels = labels
        // the ends tapped on land of the route being made (kept while they stay, so they grow in once)
        let ends = historyOn ? [] : r.spotEnds
        let gone = routeEnds.filter { e in !ends.contains { $0.id == e.id } }
        v.removeAnnotations(gone)
        routeEnds.removeAll { e in gone.contains { $0 === e } }
        for e in ends where !routeEnds.contains(where: { $0.id == e.id }) {
            let a = RouteEnd(id: e.id, at: CLLocationCoordinate2D(latitude: e.lat, longitude: e.lon))
            routeEnds.append(a)
            v.addAnnotation(a)
        }
    }
    @ObservationIgnored private var routeEnds: [RouteEnd] = []
    /// a route's line takes its colour at once (live while the picker moves; no redraw of the line)
    func recolour(_ id: UUID) {
        guard let v = view, let l = routeOverlays.first(where: { ($0 as? PinRouteLine)?.routeID == id }),
              let r = v.renderer(for: l) as? MKPolylineRenderer,
              let ink = PinRoutes.shared.routes.first(where: { $0.id == id })?.ink else { return }
        r.strokeColor = ink
        r.setNeedsDisplay()
    }
    /// a kept route's capsule on the map, if it is drawn
    func labelView(_ id: UUID) -> RouteLabelView? {
        guard let v = view, let l = routeLabels.first(where: { $0.id == id }) else { return nil }
        return v.view(for: l) as? RouteLabelView
    }
    /// a word in a route's capsule for 2 s ("No walking route"), then its distance and time again
    func note(_ id: UUID, _ words: String) {
        guard let v = view, let l = routeLabels.first(where: { $0.id == id }), let lv = v.view(for: l) as? RouteLabelView else { return }
        lv.show(words)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak lv] in
            guard let lv, (lv.annotation as? RouteLabel) === l else { return }
            lv.show(l.words)
        }
    }
    /// a route just made: Apple's map frames it between the head and the water if it is not all in view
    func frame(route id: UUID?, always: Bool = false) {
        guard let v = view, let id, let l = routeOverlays.first(where: { ($0 as? PinRouteLine)?.routeID == id }) else { return }
        // (the line's box ends at the pins' tips: room above for their heads, and at the sides for their names; the
        // head and the water are the map's own margins already, and given again here they left a route a third of
        // its room)
        let pad = UIEdgeInsets(top: 56, left: 68, bottom: 40, right: 76)
        let seen = v.visibleMapRect
        if always || !seen.contains(l.boundingMapRect) { v.setVisibleMapRect(l.boundingMapRect, edgePadding: pad, animated: true) }
    }

    /// Reset on Apple's map: the whole world, as Apple's own map shows it
    func world() { view?.setVisibleMapRect(.world, animated: true) }
    /// Reset's Around you on Apple's map: some 1,700 km across over the spot
    func around(_ c: CLLocationCoordinate2D) {
        guard let v = view else { return }
        v.setCamera(MKMapCamera(lookingAtCenter: c, fromDistance: 3_000_000, pitch: 0, heading: 0), animated: true)
    }
    /// Apple's map over a country picked in search: the country framed between the head and the water
    func show(place i: Int, world: World?) {
        guard let w = world, let f = w.frame(of: i) else { return }
        show(box: SIMD4(Double(f.x), Double(f.y), Double(f.z), Double(f.w)))
    }
    /// a box of our map (x0 y0 x1 y1, map units: a country's frame, a continent's view) framed on Apple's map
    func show(box f: SIMD4<Double>) {
        guard let v = view else { return }
        let a = EqualEarth.unproject(SIMD2(f.x, f.y)), b = EqualEarth.unproject(SIMD2(f.z, f.w))
        // (a box's corners can lie off the round edge of our map, past 180 degrees)
        let p1 = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, a.lat)), longitude: max(-180, min(180, a.lon))))
        let p2 = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, b.lat)), longitude: max(-180, min(180, b.lon))))
        let r = MKMapRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
        // (the map's own margins already are the head and the water where it stands, and a rect is fitted inside them:
        // the head and the water given again as padding left France a third of the room, up in its top half. The
        // padding is only the gap, and the zoom column's side)
        v.setVisibleMapRect(r, edgePadding: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 60), animated: true)
    }

    /// Apple's map over a place found in search (a town, a sight): the spot in the middle of the map's room, between
    /// the head and the 25% water (where Add pin drops its pin), the map `metres` across
    func show(lat: Double, lon: Double, metres: Double) {
        guard let v = view else { return }
        var centre = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        // (the map's own margins are the head and the water (its credit's place), and Apple's map calls the middle of
        // what is left its middle: a region about the spot stands in the map's room by itself. A padded rect on top of
        // that put the spot 49 pt above Add pin's point and the map twice as far out as asked.) The room is the one
        // above the 25% water, where the water is going; its middle is 4 pt right of the screen's (the credit's room on
        // the left), so the map's middle is set that much east of the spot.
        if let L = water?.layout {
            v.layoutMargins = UIEdgeInsets(top: L.headBottom, left: L.sheetInset + 8, bottom: L.H - L.top(.quarter), right: L.sheetInset)
            let room = Double(L.W - 2 * L.sheetInset - 8)
            centre.longitude += 4 * metres / max(1, room) / (111_320 * max(0.2, cos(lat * .pi / 180)))
        }
        v.setRegion(MKCoordinateRegion(center: centre, latitudinalMeters: metres, longitudinalMeters: metres), animated: true)
    }

    /// Apple's map over a pin picked from the list: the pin in the middle, no farther out than 400 km
    func go(to p: Pin) {
        guard let v = view else { return }
        let cam = MKMapCamera(lookingAtCenter: p.coordinate, fromDistance: min(v.camera.centerCoordinateDistance, 400_000), pitch: 0, heading: 0)
        v.setCamera(cam, animated: true)
    }
    /// a move asked of our map while Apple's is up (a search pick, the Stamped list, a card's place): our camera's
    /// middle and zoom, `size` the screen, framed on Apple's map instead
    func fly(centre: SIMD2<Double>, k: Double, size: CGSize) {
        guard let v = view, k.isFinite, k > 0 else { return }
        let hw = Double(size.width) / 2 / k, hh = Double(size.height) / 2 / k
        let mid = EqualEarth.unproject(centre)
        let top = EqualEarth.unproject(centre - SIMD2(0, hh)), bottom = EqualEarth.unproject(centre + SIMD2(0, hh))
        let left = EqualEarth.unproject(centre - SIMD2(hw, 0)), right = EqualEarth.unproject(centre + SIMD2(hw, 0))
        let dLat = max(0.01, min(150, abs(top.lat - bottom.lat)))
        let dLon = max(0.01, min(359, abs(right.lon - left.lon)))
        v.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: max(-80, min(80, mid.lat)), longitude: mid.lon),
                                       span: MKCoordinateSpan(latitudeDelta: dLat, longitudeDelta: dLon)), animated: true)
    }
    static func region(from m: MapController) -> MKCoordinateRegion {
        let W = m.view.width, H = m.view.height
        let mid = EqualEarth.unproject(m.c)
        let top = EqualEarth.unproject(m.mapPoint(CGPoint(x: W / 2, y: 0)))
        let bottom = EqualEarth.unproject(m.mapPoint(CGPoint(x: W / 2, y: H)))
        let left = EqualEarth.unproject(m.mapPoint(CGPoint(x: 0, y: H / 2)))
        let right = EqualEarth.unproject(m.mapPoint(CGPoint(x: W, y: H / 2)))
        let lat = max(-80, min(80, mid.lat))
        let dLat = max(0.01, min(150, abs(top.lat - bottom.lat)))
        let dLon = max(0.01, min(359, abs(right.lon - left.lon)))
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: mid.lon),
                                  span: MKCoordinateSpan(latitudeDelta: dLat, longitudeDelta: dLon))
    }
}

/// a pin on Apple's map
final class PinAnnotation: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ p: Pin) { id = p.id; coordinate = p.coordinate }
}

/// APPLE'S MAP IN PINS
struct PinsMapView: UIViewRepresentable {
    /// every tap recognizer on Apple's map and the views inside it
    static func taps(in v: UIView) -> [UITapGestureRecognizer] {
        (v.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer } + v.subviews.flatMap { taps(in: $0) }
    }
    let map: MapController
    let water: Water
    var store = PinStore.shared

    func makeCoordinator() -> Coordinator { Coordinator(water: water, map: map) }

    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView()
        v.delegate = context.coordinator
        // Apple's map as Apple draws it (8.2), flat; the head and the zoom column are ours, so none of Apple's own
        v.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        v.showsCompass = false
        v.showsScale = false
        v.showsUserLocation = false
        v.isPitchEnabled = false
        // (the margins set below are the whole inset: Apple's map added the home bar's safe area under them, so its
        // credit stood some 40 pt above the water, 12 Nov)
        v.insetsLayoutMarginsFromSafeArea = false
        v.register(PinAnnotationView.self, forAnnotationViewWithReuseIdentifier: PinAnnotationView.id)
        v.setRegion(PinsMapState.region(from: map), animated: false)
        v.insertOverlay(PinsDeepen.world, at: 0, level: .aboveRoads)
        if let w = map.world {
            Pin.countryNames = Dictionary(w.places.map { ($0.id, $0.n) }, uniquingKeysWith: { a, _ in a })
            Pin.appleNames = Dictionary(w.places.map { p in
                (p.id, Set([Locale(identifier: "en_GB"), Locale(identifier: "en_US"), Locale.current].compactMap { $0.localizedString(forRegionCode: p.id.uppercased()) }))
            }, uniquingKeysWith: { a, _ in a })
        }
        PinStore.shared.nameCountries { [map] c in Coordinator.country(map, c) }
        // HOLD THE MAP ANYWHERE (8.4), the system's half second, and let go: a pin drops there. A finger that moves
        // (before the half second or after it) is a pan, not a drop: a hold that turned into a drag of the map left
        // a pin behind at every start, pins nobody meant
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.5
        hold.allowableMovement = 8
        hold.delegate = context.coordinator
        v.addGestureRecognizer(hold)
        // the finger's first contact: the app's map touch (search, settings, the book put away)
        let down = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.down(_:)))
        down.minimumPressDuration = 0
        down.cancelsTouchesInView = false
        down.delaysTouchesBegan = false
        down.delaysTouchesEnded = false
        down.delegate = context.coordinator
        v.addGestureRecognizer(down)
        // any tap on Apple's map takes What's here? away (the tap goes on)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        // a double tap is Apple's zoom, never two single taps (its first tap must not fill a chip or pick a way)
        DispatchQueue.main.async {
            let doubles = Self.taps(in: v).filter { $0 !== tap && $0.numberOfTapsRequired == 2 }
            for d in doubles { tap.require(toFail: d) }
        }
        // DRAWING (Map/DrawTool.swift): while the tool is on, one finger draws (a drag a stroke, a tap a corner) and
        // Apple's own one-finger scroll is off; two fingers still zoom
        let drawPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drawPanned(_:)))
        drawPan.maximumNumberOfTouches = 1
        drawPan.delegate = context.coordinator
        v.addGestureRecognizer(drawPan)
        let drawTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drawTapped(_:)))
        drawTap.delegate = context.coordinator
        v.addGestureRecognizer(drawTap)
        context.coordinator.drawGestures = [drawPan, drawTap]
        PinDrawings.shared.changed = { [weak v, weak c = context.coordinator] in
            guard let v, let c else { return }
            c.syncDrawings(v, PinDrawings.shared.all.filter { PinMaps.shared.shows(extra: $0.map) })
        }
        // a pin moved by a drag is set down on the map (8.4)
        v.addInteraction(UIDropInteraction(delegate: context.coordinator))
        // a hold on a route's line or its capsule: the route's own menu (11.5)
        v.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        PinsMapState.shared.view = v
        PinsMapState.shared.water = water
        PinsMapState.shared.map = map
        // OUR MAP STAYS UNTIL APPLE'S FIRST VIEW IS DRAWN (12.5): Apple's map is there but unseen until its first
        // picture is whole, then it is there at once (30 Oct: the two maps switch with no animation); never empty
        // squares while its tiles come in. Three seconds at most (offline, or very slow), then it shows as it is.
        v.alpha = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak v] in v?.alpha = 1 }
        // its town found for "Open its place's page" (the index is read once, in the background)
        TownIndex.shared.load()
        context.coordinator.sync(v, store.pins.filter { PinMaps.shared.shows(pin: $0.map) })
        // the journey asked for before this map was made (history turned on as Pins opened), and the kept routes
        PinsMapState.shared.redrawHistory()
        PinsMapState.shared.redrawRoutes()
        DispatchQueue.main.async { PinsMapState.shared.limits() }
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) {
        // Apple's look from Settings in Pins (Standard, Satellite, Hybrid; 8 Nov: Pins' settings are its own rows)
        let look = MapSettingsStore.shared.value.pinsMap
        if context.coordinator.look != look {
            context.coordinator.look = look
            switch look {
            case "apple-satellite": v.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
            case "apple-hybrid": v.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
            default: v.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            }
            // the deepening is for Apple's drawn map only; a photo of the earth keeps its own colours
            let on = v.overlays.contains { $0 === PinsDeepen.world }
            if look.contains("satellite") || look.contains("hybrid") { if on { v.removeOverlay(PinsDeepen.world) } }
            else if !on { v.insertOverlay(PinsDeepen.world, at: 0, level: .aboveRoads) }
        }
        // (the map you picked: only what it holds; All pins: every pin)
        let maps = PinMaps.shared
        context.coordinator.sync(v, store.pins.filter { maps.shows(pin: $0.map) })
        context.coordinator.select(v, store.selected)
        context.coordinator.syncDrawings(v, PinDrawings.shared.all.filter { maps.shows(extra: $0.map) })
        if context.coordinator.mapShown != maps.shown || !context.coordinator.mapSeen {
            let first = !context.coordinator.mapSeen
            context.coordinator.mapShown = maps.shown; context.coordinator.mapSeen = true
            // (another map picked: its routes, and the camera on what it holds)
            if !first { DispatchQueue.main.async { PinsMapState.shared.redrawRoutes(); PinsMapState.shared.frameShownMap() } }
        }
        // (while drawing, a finger draws: Apple's one-finger scroll waits)
        let drawing = DrawTool.shared.on
        if v.isScrollEnabled == drawing { v.isScrollEnabled = !drawing }
        let L = water.layout
        // Apple's credit (Legal) on the map just above the water, at the sheet's inner left (Apple asks for it to be
        // seen); at full nothing of the map is seen
        let top = water.y(water.stop == .full ? .half : water.stop)
        // the credit follows the water's edge as it moves (read every frame the water moves), never above 50%
        let edge = max(water.form().top, water.y(.half))
        let margins = UIEdgeInsets(top: L.headBottom, left: L.sheetInset + 8, bottom: max(0, L.H - edge), right: L.sheetInset)
        if v.layoutMargins != margins { v.layoutMargins = margins }
        context.coordinator.reveal(v, store.selected, top: top, L: L, stop: water.stop)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate, UIDropInteractionDelegate, UIContextMenuInteractionDelegate {
        /// Apple's look shown now (Settings in Pins)
        var look = ""
        /// the map of yours shown when last drawn (a change redraws its routes and frames it)
        var mapShown: UUID? = nil
        var mapSeen = false
        let water: Water
        let map: MapController
        init(water: Water, map: MapController) { self.water = water; self.map = map }

        func sync(_ v: MKMapView, _ pins: [Pin]) {
            let have = v.annotations.compactMap { $0 as? PinAnnotation }
            let ids = Set(pins.map(\.id))
            let gone = have.filter { !ids.contains($0.id) }
            if !gone.isEmpty { v.removeAnnotations(gone) }
            let shown = Set(have.map(\.id))
            let new = pins.filter { !shown.contains($0.id) }.map(PinAnnotation.init)
            if !new.isEmpty { v.addAnnotations(new) }
            // a pin made, moved, re-dated or gone while the journey is up: its line as the pins now are
            if PinsMapState.shared.historyNeedsRedraw(pins) { PinsMapState.shared.redrawHistory() }
            for a in have where ids.contains(a.id) {
                let p = PinStore.shared.pin(a.id)
                // a move undone: the pin back on its old spot
                if let p, a.coordinate.latitude != p.lat || a.coordinate.longitude != p.lon { a.coordinate = p.coordinate }
                (v.view(for: a) as? PinAnnotationView)?.show(p)
            }
        }

        /// THE CHOSEN PIN KEPT IN SIGHT: when the water rises over it (its sheet, the picker), Apple's map moves it to the
        /// middle of what is left between the head and the water (as Apple Maps does over its own card); once per stop
        private var revealed: (UUID?, Water.Stop)?
        func reveal(_ v: MKMapView, _ id: UUID?, top: CGFloat, L: Layout, stop: Water.Stop) {
            guard revealed?.0 != id || revealed?.1 != stop else { return }
            revealed = (id, stop)
            guard let id, stop != .full, v.bounds.height > 0, let p = PinStore.shared.pin(id) else { return }
            let at = v.convert(p.coordinate, toPointTo: v)
            guard at.y > top - 60 || at.y < L.headBottom + 30 || at.x < 0 || at.x > L.W else { return }
            // the new middle worked out from the pin itself (in Apple's map points, the scale kept), not from where the
            // pin is on screen, which is still moving while an earlier move plays
            let perPoint = v.visibleMapRect.size.height / Double(v.bounds.height)
            let pin = MKMapPoint(p.coordinate)
            let mid = MKMapPoint(x: pin.x, y: pin.y + (Double(v.bounds.midY) - Double((L.headBottom + top) / 2)) * perPoint)
            v.setCenter(mid.coordinate, animated: true)
        }

        func select(_ v: MKMapView, _ id: UUID?) {
            for a in v.selectedAnnotations where (a as? PinAnnotation)?.id != id { v.deselectAnnotation(a, animated: false) }
            for a in v.annotations.compactMap({ $0 as? PinAnnotation }) {
                (v.view(for: a) as? PinAnnotationView)?.setChosen(a.id == id)
            }
            arrange(v)
        }

        /// the camera is moving (a fling still gliding, a flight): a tap then only stops it
        private var moving = false
        /// THE MAP TOUCHED (as our own map's touch-down does, 8 Nov: Apple's map took every touch, so search, settings
        /// and the book stayed open under a pan or a tap, and the tap still acted): the app's map.onTouch runs at the
        /// finger's first contact; if it closed something, this touch does nothing else
        private(set) var closedThisTouch = false
        @objc func down(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            let before = map.touchClosedAt
            map.onTouch?()
            closedThisTouch = map.touchClosedAt != before
        }
        @objc func tapped(_ g: UITapGestureRecognizer) {
            // a tap that takes What's here? away, or stops the map, does only that
            if WhatsHere.shared.isOpen { WhatsHere.shared.close(); return }
            if closedThisTouch { return }
            if moving { return }
            // a tap on the map off every pin lets the chosen pin go, however it was chosen (dropped, from the list, from
            // search: MapKit had not selected it, so its own deselect never came and the pin stayed chosen, 8 Nov)
            if !PinRoutes.shared.open, PinStore.shared.selected != nil, let v = g.view as? MKMapView {
                var hit = v.hitTest(g.location(in: v), with: nil)
                var onPin = false
                while let h = hit, !(h is MKMapView) { if h is PinAnnotationView || h is RouteLabelView { onPin = true; break }; hit = h.superview }
                if !onPin { PinStore.shared.selected = nil; return }
            }
            // a tap on one of Apple's other ways makes it the route (8.6): only off the pins, and only when that way is
            // nearer the finger (within 12 pt) than the route itself, so a tap on a shared road or an end changes nothing
            guard PinRoutes.shared.open, let v = g.view as? MKMapView else { return }
            let p = g.location(in: v)
            var hit = v.hitTest(p, with: nil)
            while let h = hit, !(h is MKMapView) { if h is PinAnnotationView || h is RouteLabelView { return }; hit = h.superview }
            var best: (PinRouteLine, CGFloat)?
            var chosen = CGFloat.infinity
            for case let l as PinRouteLine in v.overlays where l.other || l.routeID == PinRoutes.shared.currentID {
                let d = Self.near(p, l, in: v)
                if l.other { if d < 12, best == nil || d < best!.1 { best = (l, d) } } else { chosen = min(chosen, d) }
            }
            if let (l, d) = best, d < chosen { PinRoutes.shared.choose(other: l); return }
            // a chip waiting: a tap on land fills it with that spot (8.6); at sea there is nothing to route to
            if PinRoutes.shared.waiting != nil {
                let c = v.convert(p, toCoordinateFrom: v)
                if let land = Self.country(map, c) { _ = PinRoutes.shared.landTapped(c, country: land.name) } else { Feel.refuse() }
            }
        }
        /// a point's distance to a line on the map, in points (worked in Apple's map points, a line whose box is farther
        /// than `within` skipped at once, so a hold or a tap never converts every point of every route)
        static func near(_ p: CGPoint, _ l: MKPolyline, in v: MKMapView, within: CGFloat = 40) -> CGFloat {
            guard v.bounds.width > 0 else { return .infinity }
            let per = v.visibleMapRect.size.width / Double(v.bounds.width)
            let m = MKMapPoint(v.convert(p, toCoordinateFrom: v))
            let reach = Double(within) * per
            guard l.boundingMapRect.insetBy(dx: -reach, dy: -reach).contains(m) else { return .infinity }
            let pts = l.points()
            var d = Double.infinity
            let q = CGPoint(x: m.x, y: m.y)
            for i in 0 ..< max(0, l.pointCount - 1) {
                let a = CGPoint(x: pts[i].x, y: pts[i].y), b = CGPoint(x: pts[i + 1].x, y: pts[i + 1].y)
                d = min(d, Double(distance(q, a, b)))
            }
            return CGFloat(d / per)
        }
        /// the kept route under a point: its capsule, else its line within 12 pt (the nearest); never under a pin
        func route(at p: CGPoint, in v: MKMapView) -> PinRouteLine? {
            var hit = v.hitTest(p, with: nil)
            while let h = hit, !(h is MKMapView) {
                if h is PinAnnotationView { return nil }
                if let lv = h as? RouteLabelView, let id = lv.routeID {
                    return v.overlays.lazy.compactMap { $0 as? PinRouteLine }.first { $0.routeID == id }
                }
                hit = h.superview
            }
            var best: (PinRouteLine, CGFloat)?
            for case let l as PinRouteLine in v.overlays where !l.other && l.routeID != nil {
                let d = Self.near(p, l, in: v)
                if d < 12, best == nil || d < best!.1 { best = (l, d) }
            }
            return best?.0
        }
        // THE ROUTE'S HOLD MENU (11.5): what lifts is its distance and time capsule, where the finger is
        private var routeHeld: (id: UUID, at: CGPoint)?
        /// the capsule stepped out while its lifted copy is up (put back exactly, even if MapKit has moved it on)
        private weak var routeHeldView: RouteLabelView?
        /// the drawing under a point: within 12 pt of its line (the nearest), or inside a shape; never under a pin or a route
        func drawing(at p: CGPoint, in v: MKMapView) -> PinDrawing? {
            var hit = v.hitTest(p, with: nil)
            while let h = hit, !(h is MKMapView) { if h is PinAnnotationView || h is RouteLabelView { return nil }; hit = h.superview }
            var best: (PinDrawing, CGFloat)?
            for d in PinDrawings.shared.all.reversed() {
                let s = d.points.map { v.convert(CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]), toPointTo: v) }
                guard s.count > 1 else { continue }
                var e = CGFloat.infinity
                for k in 1 ..< s.count { e = min(e, Self.distance(p, s[k - 1], s[k])) }
                if d.isShape {
                    e = min(e, Self.distance(p, s[s.count - 1], s[0]))
                    let path = CGMutablePath(); path.addLines(between: s); path.closeSubpath()
                    if path.contains(p) { e = 0 }
                }
                if e < 12, best == nil || e < best!.1 { best = (d, e) }
            }
            return best?.0
        }
        /// a drawing held: what lifts is a capsule with its name and length (or area), where the finger is
        private var drawingHeld: (id: UUID, at: CGPoint)?
        func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
            guard !DrawTool.shared.on, let v = i.view as? MKMapView else { return nil }
            drawingHeld = nil
            if route(at: l, in: v) == nil, let d = drawing(at: l, in: v) {
                routeHeld = nil
                drawingHeld = (d.id, l)
                guard let water = PinsMapState.shared.water else { return nil }
                return UIContextMenuConfiguration(identifier: d.id.uuidString as NSString, previewProvider: nil) { _ in
                    MainActor.assumeIsolated { PinDrawings.shared.menu(d.id, on: v, water: water) }
                }
            }
            guard let line = route(at: l, in: v), let id = line.routeID else { return nil }
            // on the capsule: it lifts from its own place
            // (a capsule not seen: at the finger)
            let label = PinsMapState.shared.labelView(id).flatMap { $0.isHidden ? nil : $0 }
            routeHeld = (id, label.map { v.convert($0.center, from: $0.superview) } ?? l)
            return UIContextMenuConfiguration(identifier: id.uuidString as NSString, previewProvider: nil) { _ in
                MainActor.assumeIsolated { PinRoutes.shared.menu(id) }
            }
        }
        func contextMenuInteraction(_ i: UIContextMenuInteraction, configuration c: UIContextMenuConfiguration,
                                    highlightPreviewForItemWithIdentifier _: any NSCopying) -> UITargetedPreview? {
            preview(i)
        }
        func contextMenuInteraction(_ i: UIContextMenuInteraction, configuration c: UIContextMenuConfiguration,
                                    dismissalPreviewForItemWithIdentifier _: any NSCopying) -> UITargetedPreview? {
            preview(i)
        }
        private func preview(_ i: UIContextMenuInteraction) -> UITargetedPreview? {
            if let v = i.view, let h = drawingHeld, let d = PinDrawings.shared.drawing(h.id) {
                let lv = RouteLabelView(annotation: nil, reuseIdentifier: nil)
                lv.show(d.name.isEmpty ? d.measure : "\(d.name) · \(d.measure)")
                let p = UIPreviewParameters()
                p.backgroundColor = .clear
                p.visiblePath = UIBezierPath(roundedRect: lv.bounds, cornerRadius: 14)
                return UITargetedPreview(view: lv, parameters: p, target: UIPreviewTarget(container: v, center: h.at))
            }
            guard let v = i.view, let h = routeHeld, let r = PinRoutes.shared.routes.first(where: { $0.id == h.id }) else { return nil }
            let lv = RouteLabelView(annotation: nil, reuseIdentifier: nil)
            lv.show(r.words)
            let p = UIPreviewParameters()
            p.backgroundColor = .clear
            p.visiblePath = UIBezierPath(roundedRect: lv.bounds, cornerRadius: 14)
            return UITargetedPreview(view: lv, parameters: p, target: UIPreviewTarget(container: v, center: h.at))
        }
        // the capsule on the map steps out while its lifted copy is up (never two of it)
        func contextMenuInteraction(_ i: UIContextMenuInteraction, willDisplayMenuFor c: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
            if let id = routeHeld?.id, let lv = PinsMapState.shared.labelView(id), !lv.isHidden { lv.alpha = 0; routeHeldView = lv }
        }
        func contextMenuInteraction(_ i: UIContextMenuInteraction, willEndFor c: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
            let lv = routeHeldView
            routeHeldView = nil
            let back: () -> Void = { if let lv { lv.alpha = 1 } }
            if let animator { animator.addCompletion(back) } else { back() }
        }

        /// a point's distance to a segment
        static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
            let t = l2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)) : 0
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }
        func mapView(_ v: MKMapView, regionWillChangeAnimated animated: Bool) { WhatsHere.shared.close(); moving = true }
        func mapView(_ v: MKMapView, regionDidChangeAnimated animated: Bool) { moving = false; PinsMapState.shared.limits() }
        /// the stacks and names follow the camera as it moves (a pinch in spreads a stack, 8.3)
        func mapViewDidChangeVisibleRegion(_ v: MKMapView) { arrange(v); PinsMapState.shared.updateCaps() }

        /// which pins step back behind another and which have room for their name: the chosen pin first, then the
        /// newest; a pin within 18 by 24 pt of one already placed is behind it, and neither shows a name
        func arrange(_ v: MKMapView) {
            let sel = PinStore.shared.selected
            var items: [(Pin, PinAnnotationView, CGPoint)] = []
            for a in v.annotations.compactMap({ $0 as? PinAnnotation }) {
                guard let p = PinStore.shared.pin(a.id), let pv = v.view(for: a) as? PinAnnotationView else { continue }
                items.append((p, pv, v.convert(a.coordinate, toPointTo: v)))
            }
            items.sort { x, y in x.0.id == sel ? true : y.0.id == sel ? false : x.0.made > y.0.made }
            var fronts: [(CGPoint, Int)] = []
            var behindOf: [Int?] = []
            for (_, _, pt) in items {
                if let f = fronts.firstIndex(where: { abs($0.0.x - pt.x) < 18 && abs($0.0.y - pt.y) < 24 }) {
                    behindOf.append(f); fronts[f].1 += 1
                } else { behindOf.append(nil); fronts.append((pt, 0)) }
            }
            var taken: [CGRect] = items.map { CGRect(x: $0.2.x - 12, y: $0.2.y - 30, width: 24, height: 30) }
            var frontIndex = 0
            for (k, (p, pv, pt)) in items.enumerated() {
                let back = behindOf[k] != nil
                var name: String?
                if !back {
                    let stacked = fronts[frontIndex].1 > 0
                    frontIndex += 1
                    if !stacked {
                        // (only a name you gave it is written on the map: a pin's place is not its name, 12 Nov)
                        let t = p.name
                        let s = PinAnnotationView.nameSize(t)
                        let r = CGRect(x: pt.x - s.width / 2, y: pt.y + 2, width: s.width, height: s.height)
                        if !t.isEmpty, !taken.contains(where: { $0.intersects(r.insetBy(dx: -4, dy: -2)) }) { name = t; taken.append(r) }
                    }
                }
                pv.arrange(behind: back && p.id != sel, name: name)
            }
            // THE ROUTES' CAPSULES (8.3): each on its own line where the line is seen, clear of the pins, their names,
            // the head, the water and each other; one stays where it is while its spot is still clear (no hopping)
            // (from our own layout: the map's layout margins also hold the safe area, which would count it twice)
            let L = water.layout
            let room = CGRect(x: L.sheetInset + 8, y: L.headBottom + 8, width: L.W - 2 * L.sheetInset - 8 - 52,
                              height: max(0, L.top(water.stop == .full ? .half : water.stop) - L.headBottom - 16))
            var lines: [UUID: PinRouteLine] = [:]
            for case let l as PinRouteLine in v.overlays where !l.other { if let id = l.routeID { lines[id] = l } }
            for case let lab as RouteLabel in v.annotations {
                guard let line = lines[lab.id] else { continue }
                let size = (v.view(for: lab) as? RouteLabelView)?.bounds.size ?? CGSize(width: 140, height: 28)
                func box(_ c: CGPoint) -> CGRect { CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height) }
                func clear(_ c: CGPoint) -> Bool {
                    let b = box(c)
                    return room.contains(b) && !taken.contains { $0.intersects(b.insetBy(dx: -4, dy: -4)) }
                }
                let view = v.view(for: lab)
                let now = v.convert(lab.coordinate, toPointTo: v)
                // kept while clear and still by its line (a spot beside it drifts off as the map zooms in)
                if clear(now), view?.isHidden != true, Self.near(now, line, in: v, within: 30) <= 26 { taken.append(box(now)); continue }
                // the line's points in view (its seen stretch, every point of it up to about 200), tried from the middle
                // of what is seen outwards; between points far apart on screen, points along the way too
                let c0 = MKMapPoint(v.convert(CGPoint(x: room.minX, y: room.minY), toCoordinateFrom: v))
                let c1 = MKMapPoint(v.convert(CGPoint(x: room.maxX, y: room.maxY), toCoordinateFrom: v))
                let rect = MKMapRect(x: min(c0.x, c1.x), y: min(c0.y, c1.y), width: abs(c1.x - c0.x), height: abs(c1.y - c0.y))
                let mp = line.points(), n = line.pointCount
                var inView: [Int] = []
                for i in 0 ..< n where rect.contains(mp[i]) || (i + 1 < n && rect.intersects(MKMapRect(x: min(mp[i].x, mp[i + 1].x), y: min(mp[i].y, mp[i + 1].y), width: abs(mp[i + 1].x - mp[i].x), height: abs(mp[i + 1].y - mp[i].y)))) { inView.append(i) }
                let step = max(1, inView.count / 200)
                var seen: [CGPoint] = []
                for k in stride(from: 0, to: inView.count, by: step) {
                    let i = inView[k]
                    let a = v.convert(mp[i].coordinate, toPointTo: v)
                    if room.contains(a) { seen.append(a) }
                    if i + 1 < n {
                        let b = v.convert(mp[i + 1].coordinate, toPointTo: v)
                        let gap = hypot(b.x - a.x, b.y - a.y)
                        if gap > 40 { for t in stride(from: 40.0, to: Double(gap), by: 40) { let f = CGFloat(t) / gap; let c = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f); if room.contains(c) { seen.append(c) } } }
                    }
                }
                let mid = seen.count / 2
                let order = seen.indices.sorted { abs($0 - mid) < abs($1 - mid) }.map { seen[$0] }
                // on the line, else just beside it (above, then below); with no clear spot it waits unseen until there
                // is one (a capsule over a pin or a name is worse than none: the distance is in the route's menu)
                let tries = order + order.map { CGPoint(x: $0.x, y: $0.y - 22) } + order.map { CGPoint(x: $0.x, y: $0.y + 22) }
                guard let pick = tries.first(where: clear) else { view?.isHidden = true; continue }
                view?.isHidden = false
                lab.coordinate = v.convert(pick, toCoordinateFrom: v)
                taken.append(box(pick))
            }
        }

        /// where a hold began, until the finger moves away or lifts
        private var heldAt: CGPoint?
        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard let v = g.view as? MKMapView else { return }
            let p = g.location(in: v)
            switch g.state {
            case .began:
                heldAt = nil
                WhatsHere.shared.close()
                if closedThisTouch { return }
                // on a pin: its own menu, not a new pin; on a route: the route's menu (the lock keeps menus: it only
                // refuses a new pin)
                if v.hitTest(p, with: nil) is PinAnnotationView || route(at: p, in: v) != nil { return }
                // the lock stops dropping, never looking (as on every map)
                if map.locked { Feel.refuse(); return }
                // (the tick says the hold has taken; the pin falls when the finger lifts)
                Feel.tick()
                heldAt = p
            case .changed:
                if let a = heldAt, hypot(p.x - a.x, p.y - a.y) > 10 { heldAt = nil }
            case .ended:
                if let a = heldAt { heldAt = nil; drop(at: a, in: v) }
            default:
                heldAt = nil
            }
        }
        private func drop(at p: CGPoint, in v: MKMapView) {
            let c = v.convert(p, toCoordinateFrom: v)
            // (a new pin is chosen: the Route row goes first, its sheet hidden behind it otherwise)
            if PinRoutes.shared.open { PinRoutes.shared.close() }
            PinStore.shared.drop(at: c, country: Self.country(map, c))
            if water.stop != .quarter { water.go(.quarter) }
        }
        /// the country our own map has under a spot
        static func country(_ map: MapController, _ c: CLLocationCoordinate2D) -> (id: String, name: String)? {
            guard let w = map.world, let i = w.place(at: EqualEarth.project(lon: c.longitude, lat: c.latitude)) else { return nil }
            return (w.places[i].id, w.places[i].n)
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
        /// the draw tool's own pan and tap only while it is on; the pin's hold never while it is
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if drawGestures.contains(where: { $0 === g }) { return DrawTool.shared.on }
            if g is UILongPressGestureRecognizer, (g as? UILongPressGestureRecognizer)?.minimumPressDuration ?? 0 > 0 { return !DrawTool.shared.on }
            return true
        }
        var drawGestures: [UIGestureRecognizer] = []
        @objc func drawPanned(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began: DrawTool.shared.touchBegan(p); DrawTool.shared.touchMoved(p)
            case .changed: DrawTool.shared.touchMoved(p)
            case .ended: DrawTool.shared.touchEnded(p)
            default: DrawTool.shared.touchCancelled()
            }
        }
        @objc func drawTapped(_ g: UITapGestureRecognizer) {
            let p = g.location(in: g.view)
            DrawTool.shared.touchBegan(p); DrawTool.shared.touchEnded(p)
        }
        /// the drawings on Apple's map, as kept (added, taken away, or changed: redrawn whole)
        func syncDrawings(_ v: MKMapView, _ every: [PinDrawing]) {
            // (none while history is on: the journey alone)
            let all = PinsMapState.shared.historyOn ? [] : every
            let shown = v.overlays.compactMap { o -> (UUID, MKOverlay)? in
                if let l = o as? PinDrawingLine, let id = l.drawingID { return (id, l) }
                if let s = o as? PinDrawingShape, let id = s.drawingID { return (id, s) }
                return nil
            }
            let want = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, o) in shown {
                guard let d = want[id] else { v.removeOverlay(o); drawn[id] = nil; continue }
                guard let was = drawn[id], was != d else { continue }
                // only its colour changed (the picker moving): the line takes it where it is, never drawn again
                if was.points == d.points, was.kind == d.kind {
                    if let r = v.renderer(for: o) as? MKPolylineRenderer { r.strokeColor = d.ink; r.setNeedsDisplay() }
                    if let r = v.renderer(for: o) as? MKPolygonRenderer { r.strokeColor = d.ink; r.fillColor = d.ink.withAlphaComponent(0.25); r.setNeedsDisplay() }
                    drawn[id] = d
                } else { v.removeOverlay(o); drawn[id] = nil }
            }
            let have = Set(v.overlays.compactMap { ($0 as? PinDrawingLine)?.drawingID ?? ($0 as? PinDrawingShape)?.drawingID })
            for d in all where !have.contains(d.id) {
                let cs = d.points.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                let o: MKOverlay
                if d.isShape {
                    let s = PinDrawingShape(coordinates: cs, count: cs.count); s.drawingID = d.id; o = s
                } else {
                    let l = PinDrawingLine(coordinates: cs, count: cs.count); l.drawingID = d.id; o = l
                }
                v.addOverlay(o, level: .aboveRoads)
                // (drawn now: a new overlay on a map that is not moving waited for the next move to be drawn)
                v.renderer(for: o)?.setNeedsDisplay()
                drawn[d.id] = d
            }
        }
        /// what each drawing on the map was drawn from (a change draws it again)
        private var drawn: [UUID: PinDrawing] = [:]

        // A PIN SET DOWN (8.4, A8.5): only our own pins are taken; its tip lands where the finger lets go, the
        // drag's own picture settling onto the pin in its new place, a notch as it lands
        func dropInteraction(_ i: UIDropInteraction, canHandle s: UIDropSession) -> Bool {
            s.localDragSession?.items.first?.localObject is UUID
        }
        func dropInteraction(_ i: UIDropInteraction, sessionDidUpdate s: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: s.localDragSession == nil ? .cancel : .move)
        }
        func dropInteraction(_ i: UIDropInteraction, performDrop s: UIDropSession) {
            guard let v = i.view as? MKMapView, let id = s.localDragSession?.items.first?.localObject as? UUID,
                  let held = PinsMapState.shared.held[id] else { return }
            let f = s.location(in: v)
            let spot = CGPoint(x: f.x + held.spot.x, y: f.y + held.spot.y)
            PinsMapState.shared.landing[id] = spot
            let c = v.convert(spot, toCoordinateFrom: v)
            // the pin on the map moves at once, under the picture that lands on it
            if let a = v.annotations.lazy.compactMap({ $0 as? PinAnnotation }).first(where: { $0.id == id }) { a.coordinate = c }
            PinStore.shared.move(id, to: c, country: Self.country(map, c))
        }
        func dropInteraction(_ i: UIDropInteraction, previewForDropping item: UIDragItem, withDefault d: UITargetedDragPreview) -> UITargetedDragPreview? {
            guard let v = i.view, let id = item.localObject as? UUID, let spot = PinsMapState.shared.landing[id],
                  let held = PinsMapState.shared.held[id] else { return nil }
            return d.retargetedPreview(with: UIDragPreviewTarget(container: v, center: CGPoint(x: spot.x + held.middle.x, y: spot.y + held.middle.y),
                                                                 transform: held.transform))
        }
        func dropInteraction(_ i: UIDropInteraction, item: UIDragItem, willAnimateDropWith a: UIDragAnimating) {
            a.addCompletion { _ in Feel.notch() }
        }
        func dropInteraction(_ i: UIDropInteraction, concludeDrop s: UIDropSession) {
            if let id = s.localDragSession?.items.first?.localObject as? UUID { PinsMapState.shared.landing[id] = nil }
        }

        func mapViewDidFinishRenderingMap(_ v: MKMapView, fullyRendered: Bool) {
            if fullyRendered, v.alpha < 1 { v.alpha = 1 }
        }

        /// the journey's line (history on): black at its start to blue at its end
        func mapView(_ v: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            if o === PinsDeepen.world {
                let r = MKPolygonRenderer(polygon: PinsDeepen.world)
                r.fillColor = UIColor(white: PinsDeepen.white, alpha: 1)
                r.blendMode = .multiply
                return r
            }
            // A DRAWING: its colour (black unless given one), 3 pt as a route; a shape filled with it at 25%
            if let l = o as? PinDrawingLine {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = l.drawingID.flatMap { PinDrawings.shared.drawing($0)?.ink } ?? UIColor(Palette.ink)
                r.lineWidth = 3; r.lineCap = .round; r.lineJoin = .round
                return r
            }
            if let s = o as? PinDrawingShape {
                let r = MKPolygonRenderer(polygon: s)
                let ink = s.drawingID.flatMap { PinDrawings.shared.drawing($0)?.ink } ?? UIColor(Palette.ink)
                r.strokeColor = ink; r.fillColor = ink.withAlphaComponent(0.25)
                r.lineWidth = 2.5; r.lineJoin = .round
                return r
            }
            // a route: 3 pt black, round ends and joins, no casing; another way 2 pt black 50% (8.3)
            if let l = o as? PinRouteLine {
                let r = MKPolylineRenderer(polyline: l)
                // a kept route in its own colour (black unless you gave it one); another way always black 50%
                let ink = l.routeID.flatMap { id in PinRoutes.shared.routes.first { $0.id == id }?.ink } ?? UIColor(Palette.ink)
                r.strokeColor = l.other ? UIColor(Palette.ink).withAlphaComponent(0.5) : ink
                r.lineWidth = l.other ? 2 : 3
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            guard let p = o as? MKPolyline else { return MKOverlayRenderer(overlay: o) }
            // (our own: Apple's gradient line was drawn thick and blurred zoomed far out)
            return JourneyRenderer(p)
        }

        func mapView(_ v: MKMapView, viewFor a: MKAnnotation) -> MKAnnotationView? {
            if let e = a as? RouteEnd {
                let view = RouteEndView(annotation: e, reuseIdentifier: nil)
                view.appear()
                return view
            }
            if let l = a as? RouteLabel {
                let view = (v.dequeueReusableAnnotationView(withIdentifier: RouteLabelView.id) as? RouteLabelView)
                    ?? RouteLabelView(annotation: l, reuseIdentifier: RouteLabelView.id)
                view.annotation = l
                view.routeID = l.id
                view.show(l.words)
                return view
            }
            guard let a = a as? PinAnnotation else { return nil }
            let view = v.dequeueReusableAnnotationView(withIdentifier: PinAnnotationView.id, for: a) as! PinAnnotationView
            view.show(PinStore.shared.pin(a.id))
            view.setChosen(PinStore.shared.selected == a.id, animated: false)
            return view
        }
        /// A8.2: a pin just dropped falls onto its spot from 57 pt above, at its own size (it never grows; 31 Oct: no
        /// growing circles), on the settle, no overshoot; a notch as it lands
        func mapView(_ v: MKMapView, didAdd views: [MKAnnotationView]) {
            arrange(v)
            for view in views {
                guard let a = view.annotation as? PinAnnotation, a.id == PinStore.shared.dropping, let pv = view as? PinAnnotationView else { continue }
                PinStore.shared.dropping = nil
                pv.fall()
            }
        }
        func mapView(_ v: MKMapView, didSelect a: MKAnnotation) {
            if a is RouteLabel { v.deselectAnnotation(a, animated: false); return }
            guard let a = a as? PinAnnotation else { return }
            // the touch that closed search, settings or the book does only that (one press, one job)
            if closedThisTouch { v.deselectAnnotation(a, animated: false); return }
            // the Route row waiting for an end: the pin fills it, nothing else happens
            if PinRoutes.shared.pinTapped(a.id) { v.deselectAnnotation(a, animated: false); return }
            // no end waiting: the row goes and the pin is chosen (its sheet had stood hidden behind the row)
            if PinRoutes.shared.open { PinRoutes.shared.close() }
            Feel.tap()
            PinStore.shared.selected = a.id
            if water.stop != .quarter { water.go(.quarter) }
        }
        func mapView(_ v: MKMapView, didDeselect a: MKAnnotation) {
            guard let a = a as? PinAnnotation, PinStore.shared.selected == a.id else { return }
            PinStore.shared.selected = nil
        }
    }
}

/// a pin's view on Apple's map: our pin (PinLook), its tip on the spot; chosen, 1.2x about its tip and 4 pt up (A8.4)
final class PinAnnotationView: MKAnnotationView, UIContextMenuInteractionDelegate, UIDragInteractionDelegate {
    static let id = "pin"
    private static var images: [String: UIImage] = [:]
    private var chosen = false

    /// touched over 44 pt round the pin's head (the marker is drawn 24 x 30, smaller behind another pin, 8 Nov)
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let head = CGPoint(x: bounds.midX, y: bounds.minY + min(bounds.height, 30) * 0.4)
        return abs(point.x - head.x) <= 22 && abs(point.y - head.y) <= 22
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        // Apple's own selection would grow it again: ours is the one change (setChosen)
        collisionMode = .rectangle
        addInteraction(UIContextMenuInteraction(delegate: self))
        // MOVE A PIN (8.4): held, its menu opens with it lifted; moving the finger before letting go closes the menu
        // and the pin follows the finger (iOS's context menu with a drag, as Home Screen icons do)
        drag = UIDragInteraction(delegate: self)
        drag.isEnabled = true
        addInteraction(drag)
    }
    private var drag: UIDragInteraction!

    func dragInteraction(_ i: UIDragInteraction, itemsForBeginning s: UIDragSession) -> [UIDragItem] {
        // (the lock turns the drag off as the press starts: contextMenuInteraction)
        guard let a = annotation as? PinAnnotation, let v = PinsMapState.shared.view, let sv = superview else { return [] }
        let spot = v.convert(a.coordinate, toPointTo: v)
        let f = s.location(in: v)
        let mid = sv.convert(center, to: v)
        PinsMapState.shared.held[a.id] = (CGPoint(x: spot.x - f.x, y: spot.y - f.y), CGPoint(x: mid.x - spot.x, y: mid.y - spot.y), transform)
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = a.id
        return [item]
    }
    /// the pin alone, no plate and no shadow under it (8.3: no outline, no shadow)
    func dragInteraction(_ i: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        let p = UIDragPreviewParameters()
        p.backgroundColor = .clear
        p.shadowPath = UIBezierPath()
        return UITargetedDragPreview(view: self, parameters: p)
    }
    /// let go anywhere but the map: the picture goes back onto the pin where it was (nil, the system's own, when the
    /// pin has left the screen's views)
    func dragInteraction(_ i: UIDragInteraction, previewForCancelling item: UIDragItem, withDefault d: UITargetedDragPreview) -> UITargetedDragPreview? {
        guard window != nil, let sv = superview, (annotation as? PinAnnotation)?.id == item.localObject as? UUID else { return nil }
        return d.retargetedPreview(with: UIDragPreviewTarget(container: sv, center: center, transform: transform))
    }
    func dragInteraction(_ i: UIDragInteraction, item: UIDragItem, willAnimateCancelWith a: UIDragAnimating) {
        a.addCompletion { [weak self] _ in self?.alpha = 1 }
    }
    // the one under the finger is the pin: its place on the map stays empty until it lands
    func dragInteraction(_ i: UIDragInteraction, sessionWillBegin s: UIDragSession) {
        Feel.tick()
        alpha = 0
    }
    func dragInteraction(_ i: UIDragInteraction, session s: UIDragSession, didEndWith o: UIDropOperation) {
        alpha = 1
        if let id = s.items.first?.localObject as? UUID { PinsMapState.shared.held[id] = nil }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1
        arrange(behind: false, name: nil)
    }

    @MainActor func show(_ p: Pin?) {
        let c = p?.colour.map { SIMD3($0[0], $0[1], $0[2]) } ?? PinColours.standard
        let key = "\(c.x),\(c.y),\(c.z)"
        if Self.images[key] == nil {
            let r = ImageRenderer(content: PinMarker(colour: c, p3: p?.colour != nil))
            r.scale = 3
            Self.images[key] = r.uiImage
        }
        image = Self.images[key]
        // the image's bottom middle is the spot (the pin is 30 pt tall)
        centerOffset = CGPoint(x: 0, y: -(image?.size.height ?? 30) / 2)
        accessibilityLabel = p.map { "\($0.title), pin" }
    }

    func setChosen(_ on: Bool, animated: Bool = true) {
        guard on != chosen else { return }
        chosen = on
        look(animated: animated)
    }
    /// chosen: 1.2x about its tip and 4 pt up (A8.4); behind a stack: 0.8x and 4 pt down (8.3); else as drawn
    private func look(animated: Bool) {
        let h = bounds.height
        let s: CGFloat = chosen ? 1.2 : behind ? 0.8 : 1
        let lift: CGFloat = chosen ? 4 : behind ? -4 : 0
        let t = CGAffineTransform(translationX: 0, y: h / 2 * (1 - s) - lift).scaledBy(x: s, y: s)
        if animated {
            UIView.animate(withDuration: Motion.reduce ? 0.2 : 0.26, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) { self.transform = t }
        } else { transform = t }
    }

    // MANY PINS CLOSE TOGETHER (8.3): the ones behind step back; NAMES under the point (8.3), only where they don't
    // collide and never on a stack. No number bubbles.
    private var behind = false
    private lazy var nameLabel: UILabel = {
        let l = UILabel()
        // (the map's own names' type: 12 pt medium, as a thing's name on our map)
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.textColor = UIColor(Palette.ink)
        l.isHidden = true
        TownNamesView.glow(l)
        addSubview(l)
        return l
    }()
    /// the name's size at 12 pt (to test for room before it shows)
    static func nameSize(_ s: String) -> CGSize {
        (s as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .medium)])
    }
    func arrange(behind b: Bool, name: String?) {
        if b != behind {
            behind = b
            zPriority = b ? .min : .defaultUnselected
            look(animated: false)
        }
        if let name {
            if nameLabel.text != name { nameLabel.text = name; nameLabel.sizeToFit() }
            // centred under the tip (the view's bottom middle), 2 pt below it
            nameLabel.center = CGPoint(x: bounds.midX, y: bounds.maxY + 2 + nameLabel.bounds.height / 2)
            nameLabel.isHidden = false
        } else if nameLabel.superview != nil {
            nameLabel.isHidden = true
        }
    }

    /// a pin dropped is simply there (no fall any more, 8 Nov answer), with the notch of setting it down
    func fall() {
        transform = .identity
        Feel.notch()
    }

    // THE PIN'S HOLD MENU (11.5), its name over the rows built so far, in the book's groups:
    // Edit | Colour | Directions | What's here? · Open its place's page · Copy coordinates | Share | Delete
    // (Icon, routes, Measure, lists and plans come with their parts)
    func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
        guard let a = annotation as? PinAnnotation else { return nil }
        let id = a.id
        // the lock: the menu, but no moving (8.4)
        drag.isEnabled = PinsMapState.shared.map?.locked != true
        PinStore.from = convert(bounds, to: nil)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            MainActor.assumeIsolated { Self.menu(id) }
        }
    }

    @MainActor static func menu(_ id: UUID) -> UIMenu? {
        guard let p = PinStore.shared.pin(id) else { return nil }
        // each runs once the menu has gone (as every hold menu's rows)
        let after = { (f: @escaping @MainActor () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
        let state = PinsMapState.shared
        // (the Route row goes first: the pin's sheet stood hidden behind it, and came up unasked later, 8 Nov)
        let edit = UIAction(title: "Edit") { _ in
            after { PinRoutes.shared.close(); PinStore.shared.selected = id; state.water?.go(.half) }
        }
        let colour = UIAction(title: "Colour") { _ in
            after { PinRoutes.shared.close(); PinStore.shared.selected = id; PinStore.shared.colourAsked = true; state.water?.go(.full) }
        }
        let directions = UIAction(title: "Directions") { _ in PinStore.directions(p) }
        // Route from here / Route to here (11.5): the Route row opens with that end set (8.6)
        let routeFrom = UIAction(title: "Route from here") { _ in after { PinStore.shared.selected = nil; PinRoutes.shared.start(.from, at: id) } }
        let routeTo = UIAction(title: "Route to here") { _ in after { PinStore.shared.selected = nil; PinRoutes.shared.start(.to, at: id) } }
        let open = PinStore.page(p, world: state.map?.world)
        let page = UIAction(title: "Open its place's page", attributes: open == nil ? .disabled : []) { _ in
            after { open?() }
        }
        let copy = UIAction(title: "Copy coordinates") { _ in
            UIPasteboard.general.string = String(format: "%.5f, %.5f", p.lat, p.lon)
        }
        // What's here? (A11.4): the nearest three names from our data, over Apple's map at the pin's tip
        let here = UIAction(title: "What's here?") { _ in
            after {
                guard let v = state.view, let m = state.map, let now = PinStore.shared.pin(id) else { return }
                let at = v.convert(now.coordinate, toPointTo: nil)
                let land = PinsMapView.Coordinator.country(m, now.coordinate).flatMap { m.world?.placeIndex[$0.id] }
                // (a finger's reach on Apple's map: 44 pt of its height in degrees)
                let reach = v.region.span.latitudeDelta * 44 / max(1, Double(v.bounds.height))
                WhatsHere.shared.show(at: at, lat: now.lat, lon: now.lon, land: land, reach: reach, map: m)
            }
        }
        let share = UIAction(title: "Share") { _ in after { PinStore.share(p) } }
        let delete = UIAction(title: "Delete", attributes: .destructive) { _ in after { Feel.lift(); PinStore.shared.remove(id) } }
        return UIMenu(title: p.title, children: [
            UIMenu(options: .displayInline, children: [edit]),
            UIMenu(options: .displayInline, children: [colour]),
            UIMenu(options: .displayInline, children: [routeFrom, routeTo, directions]),
            UIMenu(options: .displayInline, children: [here, page, copy]),
            UIMenu(options: .displayInline, children: [share]),
            UIMenu(options: .displayInline, children: [delete]),
        ])
    }
}

/// PINS' WATER'S CAPTION (8.5, 8.8's first line; the dock's tools come with their icons): your pins' count, or the
/// chosen pin's name over its place and day; with no pins yet, how to drop one
struct PinsWater: View {
    let water: Water
    let form: Water.Form
    let captionY: CGFloat
    var store = PinStore.shared

    var body: some View {
        let L = water.layout
        VStack(spacing: 4) {
            // (the words change at once: only a count rolls, never a name being typed)
            if let p = store.pin(store.selected) {
                // its name on the caption's own name line (a caption laid out unseen under it gives the place), so the
                // title sits where every map's name sits at each stop
                ZStack(alignment: .top) {
                    Caption(name: " ", count: 0, tail: " ", night: false).hidden()
                    VStack(spacing: 4) {
                        // while the phone names a new pin, the nearest town we know at once (never an empty line,
                        // 19:18), the real name blurring in over it when it comes
                        let name = p.shownTitle
                        ZStack {
                            Text(name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                                .id(name).transition(.blurReplace)
                        }
                        .animation(Motion.quick, value: name)
                        Text(p.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                    }
                }
                // (capped where the caption is, so the name stays on its line at the largest sizes)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                // none chosen: the caption every map has (Places' "Everywhere 4"), how to drop one under a 0
                Text(PinMaps.shared.map(PinMaps.shared.shown)?.name ?? "All pins")
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
            }
        }
        // (no fade between "Pins" and a pin's name: the words are simply there, 8 Nov; it crossfaded on every pin tap)
        // (clear of the Share circle on each side while the sheet is up, so the name stays centred)
        .frame(width: L.W - 2 * L.sheetInset - 32 - (store.selected != nil && water.stop != .quarter && water.stop != .closed ? 96 : 0))
        .position(x: L.W / 2, y: captionY)
        .allowsHitTesting(false)
    }
}


/// YOUR PINS (8.8's list) at 50% when none is chosen: newest first, the same rows as your maps in Places
/// (the pin in its colour, its name in body, its place and day in a grey line, 56 pt a row). A tap chooses the pin:
/// Apple's map goes to it and the water to 25%, under its name. The list is there once the water rests at 50% (no
/// row comes up alone on the way), holds whole rows, and scrolls there row by row: the list never takes the screen.
struct PinsList: View {
    let water: Water
    /// the caption's centre
    let captionY: CGFloat
    /// where the rows start (under the dock), else under the caption's foot
    var top: CGFloat? = nil
    /// the water is standing at 50%
    var rest = true
    var store = PinStore.shared
    /// (the test driver's "pins end": the drawings brought up to the top of the list)
    @State private var pos = ScrollPosition(idType: UUID.self)
    /// the map whose name is being typed, and the words so far
    @State private var naming: UUID?
    @State private var name = ""
    @FocusState private var typing: Bool

    static let rowH: CGFloat = 72

    var body: some View {
        let L = water.layout
        // (under the dock, or under the caption's foot as Places' rows)
        let foot = self.top.map { $0 - 8 } ?? captionY + 65
        let rowsTop = foot + 8
        // (as many whole rows as stand clear of the tabs with the water at 50%; the soft edge sits right under the last
        // of them, so at rest no row is cut and a row scrolled past it goes out softly)
        let restTop = self.top == nil ? rowsTop : PinsDock.bottom(max(L.top(.half), L.headBottom + 8))
        let n = max(0, Int(floor((L.capsule.minY - 16 - restTop) / Self.rowH)))
        let fade = restTop + CGFloat(n) * Self.rowH + 12
        // THE WATER MOVING (the 25% to 50% change): the rows are always there and ride
        // with the water's top, shown only in the band between the tools and the soft edge above the tabs, so they
        // rise out of it with the water and sink back into it (as Places' maps do), never popping in at the end
        if n > 0 {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let maps = PinMaps.shared
                    if !maps.inside {
                        // YOUR MAPS (Google Earth's projects): All pins, then each map you made, then a new one. A tap
                        // shows that map (the water down to 25%); the one shown, tapped again, opens what it holds
                        mapRow(nil)
                        ForEach(maps.all.reversed()) { m in mapRow(m) }
                        newMapRow
                    } else {
                    // with routes kept, a Routes section under the pins (8.6's Saved), its name 15 pt semibold black 50%
                    let routes = PinRoutes.shared.routes.filter { maps.shows(extra: $0.map) }
                    ForEach(store.pins.filter { maps.shows(pin: $0.map) }.reversed()) { p in row(p) }
                    if !routes.isEmpty {
                        header("Routes").padding(.top, 12)
                        ForEach(routes.reversed()) { r in routeRow(r) }
                    }
                    // the lines and shapes drawn (Map/PinDrawings.swift)
                    let drawings = PinDrawings.shared.all.filter { maps.shows(extra: $0.map) }
                    if !drawings.isEmpty {
                        header("Drawings").padding(.top, 12)
                        ForEach(drawings.reversed()) { d in drawingRow(d) }
                    }
                    }
                    Color.clear.frame(height: max(0, L.H - fade))
                }
                .scrollTargetLayout()
            }
            // (row by row, so whole rows are what it comes to rest on)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($pos)
            .onChange(of: store.endAsked) { _, _ in
                if let d = PinDrawings.shared.all.last { pos.scrollTo(id: d.id, anchor: .top) }
            }
            // 16 pt inside the water, as the Stamped list's rows (the box already starts at the water's edge)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            // (the first row clear of the soft top edge: the shown map's black band was faded at its top)
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollIndicators(.hidden)
            .frame(width: L.W - 2 * L.sheetInset, height: max(0, L.H - rowsTop))
            .padding(.top, rowsTop)
            .frame(width: L.W, height: L.H, alignment: .top)
            // (the soft top edge inside the list's own frame: the list cuts its rows at its top, so a fade above it never
            // showed and a row scrolled up was cut by a hard line under the count; 8 pt, so a row at rest, its words
            // 10 pt in, stays whole)
            .mask {
                if fade > rowsTop + 32, L.H > 0 {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0), location: rowsTop / L.H),
                        .init(color: .black, location: (rowsTop + 8) / L.H),
                        .init(color: .black, location: (fade - 24) / L.H),
                        .init(color: .black.opacity(0), location: min(1, fade / L.H)),
                    ], startPoint: .top, endPoint: .bottom)
                } else { Color.clear }
            }
            .scrollDisabled(!rest)
            .allowsHitTesting(rest)
            .transaction { $0.animation = nil }
        }
    }

    /// A MAP OF YOURS AS A ROW: a small picture of where its pins are (each a dot, placed as on the map), its name,
    /// and the countries it is in; the one shown is a black band edge to edge with white words, as a chosen row in
    /// Map settings. A hold: Rename, Delete map
    private func mapRow(_ m: PinMap?) -> some View {
        let maps = PinMaps.shared
        let on = maps.shown == m?.id
        let pins = store.pins.filter { m == nil || $0.map == m?.id }
        // its countries, the one with most pins first; past three, how many more
        let counts = Dictionary(pins.compactMap(\.countryName).map { ($0, 1) }, uniquingKeysWith: +)
        let names = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let places = names.isEmpty ? (pins.isEmpty ? "No pins yet" : "")
            : names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " and \(names.count - 3) more" : "")
        // YOUR MAPS as Google Earth's projects and Apple Maps' guides: the map itself small (where its pins are, on
        // Apple's map), its name, its countries; the one shown has a tick, nothing else changes
        return HStack(spacing: 14) {
            PinMapThumb(pins: pins.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if naming == m?.id, let m {
                    TextField("", text: $name)
                        .font(.body.weight(.semibold)).foregroundStyle(Palette.ink).focused($typing)
                        .submitLabel(.done)
                        .onSubmit { maps.rename(m.id, to: name); naming = nil }
                } else {
                    Text(m?.name ?? "All pins").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                }
                if !places.isEmpty {
                    Text(places).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if on { Icon5(key: "tick", ink: Palette.ink, size: 17).frame(width: 28, height: 28).transition(.blurReplace) }
        }
        .animation(Motion.quick, value: on)
        .frame(minHeight: Self.rowH)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            store.selected = nil
            if on { maps.inside = true; return }
            maps.shown = m?.id
            water.go(.quarter)
        }
        .contextMenu {
            if let m {
                Button("Rename") { name = m.name; naming = m.id; typing = true }
                Button("Delete map", role: .destructive) { Feel.lift(); maps.remove(m.id) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m?.name ?? "All pins")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
    /// NEW MAP: made at once and shown, its name typed in place on its own row
    private var newMapRow: some View {
        HStack(spacing: 14) {
            Icon5(key: "plus", ink: Palette.ink, size: 20)
                .frame(width: 56, height: 56)
                .glassEffect(PageGlass.head, in: .rect(cornerRadius: 12, style: .continuous))
            Text("New map").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Self.rowH)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            let n = PinMaps.shared.all.count + 1
            let m = PinMaps.shared.make("Map \(n)")
            name = m.name; naming = m.id; typing = true
        }
        .accessibilityAddTraits(.isButton)
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.5))
            .frame(minHeight: 32, alignment: .bottom)
            .accessibilityAddTraits(.isHeader)
    }
    /// a kept route: its own line drawn small (the route icon is still to draw), "From to To", its distance and time;
    /// a tap shows it on the map with the water at 25%; a hold, the route's menu (11.5)
    private func routeRow(_ r: PinRoute) -> some View {
        let ends = PinRoutes.shared
        let name = "\(ends.end(r.from, r)?.title ?? "Pin") to \(ends.end(r.to, r)?.title ?? "Pin")"
        return HStack(spacing: 12) {
            RouteShape(points: r.points)
                .stroke(r.pick?.color ?? Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 24)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                    .minimumScaleFactor(0.85).allowsTightening(true)
                Text(PinRoutes.shared.notes[r.id] ?? r.words).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            store.selected = nil
            water.go(.quarter)
            PinsMapState.shared.frame(route: r.id, always: true)
        }
        .contextMenu {
            Section {
                Button("Reverse") { PinRoutes.shared.reask(r.id, reverse: true) }
                Button("Walk") { PinRoutes.shared.reask(r.id, walk: true) }.disabled(r.walk == true)
                Button("Drive") { PinRoutes.shared.reask(r.id, walk: false) }.disabled(r.walk != true)
                Button("Colour") {
                    store.selected = nil; PinRoutes.shared.colouring = r.id
                    if water.stop == .quarter || water.stop == .closed { water.go(.half) }
                }
            }
            Section {
                Button("Directions in Apple Maps") { PinRoutes.shared.directions(r.id) }
                Button("Share") { PinRoutes.shared.share(r.id) }
            }
            Button("Delete", role: .destructive) { Feel.lift(); PinRoutes.shared.remove(r.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(r.words)")
        .accessibilityAddTraits(.isButton)
    }

    /// a drawing: its own outline small, its name ("Line" or "Shape" until it has one), its length or area; a tap
    /// frames it with the water at 25%; a hold, its menu
    private func drawingRow(_ d: PinDrawing) -> some View {
        let name = d.name.isEmpty ? (d.isShape ? "Shape" : "Line") : d.name
        // Apple's own plane (as the map above draws it), so the small one matches the big one
        let pts = d.points.map { c -> SIMD2<Float> in
            let m = MKMapPoint(CLLocationCoordinate2D(latitude: c[0], longitude: c[1])); return SIMD2(Float(m.x), Float(m.y))
        }
        return HStack(spacing: 12) {
            DrawingShape(points: pts, closed: d.isShape)
                .stroke(d.pick?.color ?? Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 24)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                Text(d.measure).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            store.selected = nil
            water.go(.quarter)
            PinDrawings.shared.frame(d.id)
        }
        .contextMenu {
            Button("Rename") { PinDrawings.shared.rename(d.id) }
            Button("Redraw") { if let v = PinsMapState.shared.view { PinDrawings.shared.redraw(d.id, on: v, water: water) } }
            Button("Colour") {
                store.selected = nil; PinRoutes.shared.close(); PinDrawings.shared.colouring = d.id
                if water.stop == .quarter || water.stop == .closed { water.go(.half) }
            }
            Button("Delete", role: .destructive) { Feel.lift(); PinDrawings.shared.remove(d.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(d.measure)")
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ p: Pin) -> some View {
        HStack(spacing: 12) {
            PinMarker(colour: p.colour.map { SIMD3($0[0], $0[1], $0[2]) } ?? PinColours.standard, p3: p.colour != nil)
                .scaleEffect(0.8)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.shownTitle.isEmpty ? " " : p.shownTitle).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
                Text(p.line).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            Feel.tap()
            store.selected = p.id
            water.go(.quarter)
            PinsMapState.shared.go(to: p)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.title), \(p.line)")
        .accessibilityAddTraits(.isButton)
    }
}

/// SHARE, a clear circle at the right of the chosen pin's name while its sheet is up (as Apple's own marked place)
struct PinShare: View {
    let water: Water
    let captionY: CGFloat
    var store = PinStore.shared
    var body: some View {
        let L = water.layout
        if let p = store.pin(store.selected) {
            Button { Feel.tap(); PinStore.share(p) } label: {
                Icon5(key: "share", ink: Palette.ink, size: 20).frame(width: 44, height: 44)
                    // the whole circle touches (only the glyph's strokes did)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(PageGlass.control, in: .circle)
            .accessibilityLabel("Share")
            .position(x: L.W - L.sheetInset - 16 - 22, y: captionY)
        }
    }
}

/// THE PIN'S SHEET (8.8) at 50% and full, under its name and place: the same sections and rows as Details (Part 4.4),
/// on the water: Name, Colour (the circle opens the colour picker under it, the pin following live), Note, Coordinates
/// (a tap copies them); then Delete pin in red words. Share is the clear circle by its name (PinShare). Every change is
/// kept as it happens (no Save). Scrolls at full.
struct PinSheet: View {
    let water: Water
    let top: CGFloat
    var store = PinStore.shared
    @State private var picking = false
    @State private var pick = PinSheet.nearBlack
    /// where the picker opens for a black pin: its deepest row, the field in full colour (at no strength the whole
    /// field would be grey); nothing is picked until the finger moves
    static let nearBlack = ColourPick(hue: 0, light: ColourPick.lightBottom, strength: 0.8)
    @FocusState private var typing: Bool
    @State private var choosingPhoto = false
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var rows = ScrollPosition()

    var body: some View {
        let L = water.layout
        let fade = L.capsule.minY - 24
        let whole = water.stop == .full
        if let p = store.pin(store.selected) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                  if picking {
                    // CHOOSING ITS COLOUR: the sheet is the picker alone, at the height it is at (50% holds it): the colour's
                    // name, Reset to black and Done on one line, the picker under it; nothing else is up meanwhile (the
                    // pin's other rows, a full screen for one colour, a Share circle in the head's corner all went, 8 Nov)
                    HStack(spacing: 16) {
                        Circle().fill(p.pick?.color ?? Palette.ink).frame(width: 28, height: 28)
                        Text(p.pick.map { ColourNames.name($0).capitalizedFirst } ?? "Black").font(.headline).foregroundStyle(Palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        if p.pick != nil {
                            Button { Feel.tap(); store.colour(p.id, nil); pick = Self.nearBlack } label: {
                                Text("Reset").font(.body).foregroundStyle(Palette.ink).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Button { Feel.tap(); picking = false } label: {
                            Text("Done").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    ColourPicker(colour: Binding(get: { pick }, set: { c in pick = c; store.colour(p.id, c) }),
                                 suggested: nil, width: L.W - 2 * L.sheetInset - 32) { c in ColourStore.shared.add(c) }
                  } else {
                    // THE PIN'S SHEET (23 Oct, 3 Oct): what it does as glass circles in one even row (its colour, a
                    // photo, share, delete in red); under it its name, its kind, its photo and its note, each only
                    // the thing itself, no labels and no explaining
                    actions(p, width: L.W - 2 * L.sheetInset - 32)
                    TextField("", text: Binding(get: { p.name }, set: { v in
                        if v.count > 60 { Feel.refuse() }
                        store.rename(p.id, v)
                    }), prompt: Text("Name").foregroundStyle(Palette.ink.opacity(0.5)))
                    .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    .focused($typing)
                    .submitLabel(.done)
                    .frame(minHeight: 44)
                    kinds(p)
                    if let img = PinStore.image(p) {
                        Menu {
                            Button("Choose another") { Feel.tap(); choosingPhoto = true }
                            Button("Remove", role: .destructive) { Feel.lift(); store.photo(p.id, nil) }
                        } label: {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 200)
                                .overlay { Image(uiImage: img).resizable().scaledToFill() }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Photo")
                    }
                    TextField("", text: Binding(get: { p.note ?? "" }, set: { v in
                        if v.count > 600 { Feel.refuse() }
                        store.note(p.id, v)
                    }), prompt: Text("Note").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
                    .font(.body).foregroundStyle(Palette.ink)
                    .lineLimit(whole ? 1 ... 12 : 1 ... 3)
                    .focused($typing)
                    .frame(minHeight: 44)
                    fullRows(p, cut: whole ? nil : fade - 8)
                  }
                    Color.clear.frame(height: L.H - fade + 24)
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($rows)
            .onChange(of: store.endAsked) { _, _ in rows.scrollTo(edge: .bottom) }
            // (at 50% as at full: every row of the pin is reached where the sheet stands, never by a full screen)
            .scrollDisabled(water.stop == .quarter || water.stop == .closed)
            .scrollDismissesKeyboard(.immediately)
            .frame(width: L.W - 2 * L.sheetInset, height: max(0, L.H - top))
            // the rows go out through a soft edge above the tabs, never cut by a hard line (P3)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().frame(height: max(0, fade - top - 24))
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    Spacer(minLength: 0)
                }
                .frame(height: max(0, L.H - top))
            }
            .position(x: L.W / 2, y: top + max(0, L.H - top) / 2)
            // typing: the water goes to full (Part 4.4's rule), the keyboard under it
            // (and back to 50% when the keyboard goes)
            .onChange(of: typing) { _, t in
                store.typing = t
                if t { water.go(.full) } else if water.stop == .full { water.go(.half) }
            }
            .onChange(of: store.selected) { _, _ in picking = false; colourIfAsked() }
            .onChange(of: store.colourAsked) { _, _ in colourIfAsked() }
            // pulled down below full, the picker goes back into its row
            .onChange(of: water.stop) { _, s in if s == .quarter || s == .closed { picking = false } }
            .onAppear { colourIfAsked() }
            // its photo: Apple's picker (no permission asked), one picture
            .photosPicker(isPresented: $choosingPhoto, selection: $chosenPhoto, matching: .images)
            .onChange(of: chosenPhoto) { _, item in
                guard let item, let id = store.selected else { return }
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self) { store.photo(id, d) }
                    chosenPhoto = nil
                }
            }
            // the picker going away (closed, Reset, another pin, the water down): its moves are one undo
            .onChange(of: picking) { _, on in if on, let id = store.selected { store.colourStart(id) } else if !on { store.colourEnd() } }
            .onDisappear { store.colourEnd(); store.typing = false }
        }
    }

    /// the rows seen at full: Coordinates (Apple's marked place has them; a tap copies them), then Delete pin, the last
    /// row, in red words (as Apple's own Remove; at once, the undo drop brings it back)
    /// (`cut`: below full, a row is there once it is whole above the soft edge over the tabs, never cut by it)
    @ViewBuilder private func fullRows(_ p: Pin, cut: CGFloat?) -> some View {
        // where it is, copied with a tap
        Button {
            Feel.tap()
            UIPasteboard.general.string = String(format: "%.5f, %.5f", p.lat, p.lon)
        } label: {
            Text(Self.coordinates(p)).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.ink.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Copies the coordinates")
        .whole(cut)
    }

    /// the pin's four circles, sharing the row evenly: its colour (the circle is the colour), a photo, share, delete
    private func actions(_ p: Pin, width: CGFloat) -> some View {
        let part = width / 4
        return GlassEffectContainer(spacing: 14) {
            HStack(spacing: 0) {
                Button {
                    Feel.tap()
                    pick = p.pick ?? Self.nearBlack
                    picking = true
                    if water.stop == .quarter || water.stop == .closed { water.go(.half) }
                } label: {
                    Circle().fill(p.pick?.color ?? Palette.ink).frame(width: 24, height: 24)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain).glassEffect(PageGlass.head, in: .circle)
                .accessibilityLabel("Colour, \(p.pick.map { ColourNames.name($0) } ?? "black")")
                .frame(width: part)
                circle("photo", "Photo", Palette.ink) { choosingPhoto = true }.frame(width: part)
                circle("share", "Share", Palette.ink) { PinStore.share(p) }.frame(width: part)
                circle("bin", "Delete pin", Palette.red) { Feel.lift(); store.remove(p.id); water.go(.quarter) }.frame(width: part)
            }
        }
        .frame(width: width)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func circle(_ icon: String, _ label: String, _ ink: Color, _ act: @escaping () -> Void) -> some View {
        Button { Feel.tap(); act() } label: {
            Icon5(key: icon, ink: ink, size: 20).frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(PageGlass.head, in: .circle)
        .accessibilityLabel(label)
    }

    /// its kind, one of the twelve (7.3), in a row to slide through; the one chosen filled black, chosen again it
    /// goes back to none
    private func kinds(_ p: Pin) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(OwnPlaces.kinds, id: \.self) { k in
                    let on = p.kind == k
                    Button { Feel.tap(); store.kind(p.id, on ? nil : k) } label: {
                        Text(k.capitalizedFirst).font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Palette.white : Palette.ink)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background { if on { Capsule().fill(Palette.ink) } }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .identity : PageGlass.head, in: .capsule)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .animation(Motion.quick, value: p.kind)
    }

    private func section<C: View>(_ name: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.headline).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            c()
        }
    }

    /// "29.12345° N, 6.54321° E"
    static func coordinates(_ p: Pin) -> String {
        String(format: "%.5f° %@, %.5f° %@", abs(p.lat), p.lat >= 0 ? "N" : "S", abs(p.lon), p.lon >= 0 ? "E" : "W")
    }

    /// the hold menu's Colour: the picker out under the Colour row
    private func colourIfAsked() {
        guard store.colourAsked, let p = store.pin(store.selected) else { return }
        store.colourAsked = false
        pick = p.pick ?? Self.nearBlack
        picking = true
        // (said here too: another pin's Colour while the picker is out changes no `picking`)
        store.colourStart(p.id)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// a route's own line, fitted into its frame (north up, its longer side filling it)
struct RouteShape: Shape {
    let points: [[Double]]
    func path(in rect: CGRect) -> Path {
        let pts = points.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1])) }
        guard pts.count > 1, let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(),
              let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return Path() }
        let k = min(rect.width, rect.height) / max(x1 - x0, y1 - y0, 1)
        let ox = rect.midX - (x0 + x1) / 2 * k, oy = rect.midY - (y0 + y1) / 2 * k
        let step = max(1, pts.count / 120)
        var p = Path()
        p.move(to: CGPoint(x: pts[0].x * k + ox, y: pts[0].y * k + oy))
        for i in stride(from: step, to: pts.count, by: step) { p.addLine(to: CGPoint(x: pts[i].x * k + ox, y: pts[i].y * k + oy)) }
        p.addLine(to: CGPoint(x: pts[pts.count - 1].x * k + ox, y: pts[pts.count - 1].y * k + oy))
        return p
    }
}

/// THE JOURNEY'S LINE on Apple's map: one black line (not black to blue), 2.5 pt at every zoom, round ends
/// and joins; `progress` (0 to 1, of its length) is how much of it is drawn, for the play
final class JourneyRenderer: MKOverlayRenderer {
    let line: MKPolyline
    var progress = 1.0
    init(_ l: MKPolyline) { line = l; super.init(overlay: l) }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        let n = line.pointCount
        guard n > 1 else { return }
        let pts = line.points()
        var total = 0.0
        for k in 1 ..< n { total += hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y) }
        var left = total * min(1, max(0, progress))
        guard left > 0 else { return }
        let path = CGMutablePath()
        path.move(to: point(for: pts[0]))
        for k in 1 ..< n where left > 0 {
            let a = pts[k - 1], b = pts[k]
            let d = hypot(b.x - a.x, b.y - a.y)
            let f = min(1, left / max(d, 1e-9))
            path.addLine(to: point(for: MKMapPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)))
            left -= d
        }
        // (screen points: a map point is zoomScale points on screen)
        ctx.setLineWidth(CGFloat(2.5 / Double(zoomScale)))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(UIColor(Palette.ink).cgColor)
        ctx.addPath(path)
        ctx.strokePath()
    }
}

/// a closure for an Objective-C target (a display link, a gesture)
final class Fire: NSObject {
    let f: @MainActor () -> Void
    init(_ f: @escaping @MainActor () -> Void) { self.f = f }
    @MainActor @objc func fire() { f() }
}

/// a touch watcher that lets every other gesture on the map go on as it would (the journey's play ends on any touch)
final class SimultaneousTouch: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}

/// A MAP'S SMALL PICTURE: its pins as dots where they are, fitted to the square (one pin: one dot in the middle; none:
/// an empty square's room)
struct PinMapPicture: View {
    let points: [SIMD2<Double>]
    let ink: Color
    var body: some View {
        Canvas { ctx, size in
            guard !points.isEmpty else { return }
            let xs = points.map(\.x), ys = points.map(\.y)
            let w = max(xs.max()! - xs.min()!, 1e-6), h = max(ys.max()! - ys.min()!, 1e-6)
            let side = max(w, h), r: CGFloat = 2.5, room = size.width - 2 * r - 2
            for p in points.prefix(200) {
                let x = points.count == 1 ? size.width / 2 : r + 1 + CGFloat((p.x - xs.min()! + (side - w) / 2) / side) * room
                let y = points.count == 1 ? size.height / 2 : r + 1 + CGFloat((ys.max()! - p.y + (side - h) / 2) / side) * room
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(ink))
            }
        }
        .accessibilityHidden(true)
    }
}

/// APPLE'S MAP, DEEPER (12 Nov 21:27: its green and blue were far too light): the whole earth under the roads' labels
/// multiplied by a light grey, so land and sea come out a step deeper and the labels, pins and routes stay as they are
enum PinsDeepen {
    /// how much of each colour is kept (1 is Apple's own)
    static let white: CGFloat = 0.84
    static let world: MKPolygon = {
        let r = MKMapRect.world
        var pts = [MKMapPoint(x: r.minX, y: r.minY), MKMapPoint(x: r.maxX, y: r.minY),
                   MKMapPoint(x: r.maxX, y: r.maxY), MKMapPoint(x: r.minX, y: r.maxY)]
        return MKPolygon(points: &pts, count: pts.count)
    }()
}


/// A MAP OF YOURS DRAWN SMALL: Apple's map (its standard look, no labels) round where its pins are, each pin a small
/// black dot; no pins, the whole world. Made once per set of pins and kept.
struct PinMapThumb: View {
    let pins: [CLLocationCoordinate2D]
    @State private var image: UIImage?
    private static let kept = NSCache<NSString, UIImage>()

    private var key: String {
        pins.map { String(format: "%.3f,%.3f", $0.latitude, $0.longitude) }.joined(separator: ";")
    }

    var body: some View {
        ZStack {
            if let i = image ?? Self.kept.object(forKey: key as NSString) {
                Image(uiImage: i).resizable().scaledToFill()
            } else {
                Palette.cream
            }
        }
        .task(id: key) { await make() }
    }

    private func region() -> MKCoordinateRegion {
        guard !pins.isEmpty else { return MKCoordinateRegion(center: .init(latitude: 20, longitude: 10), span: .init(latitudeDelta: 140, longitudeDelta: 300)) }
        let la = pins.map(\.latitude), lo = pins.map(\.longitude)
        let c = CLLocationCoordinate2D(latitude: (la.min()! + la.max()!) / 2, longitude: (lo.min()! + lo.max()!) / 2)
        let s = MKCoordinateSpan(latitudeDelta: min(150, max(0.05, (la.max()! - la.min()!) * 1.6)),
                                 longitudeDelta: min(340, max(0.05, (lo.max()! - lo.min()!) * 1.6)))
        return MKCoordinateRegion(center: c, span: s)
    }

    private func make() async {
        let k = key as NSString
        if Self.kept.object(forKey: k) != nil { return }
        let o = MKMapSnapshotter.Options()
        o.region = region()
        o.size = CGSize(width: 112, height: 112)
        o.scale = 3
        o.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        o.pointOfInterestFilter = .excludingAll
        guard let shot = try? await MKMapSnapshotter(options: o).start() else { return }
        let r = UIGraphicsImageRenderer(size: o.size)
        let out = r.image { _ in
            shot.image.draw(at: .zero)
            UIColor(Palette.ink).setFill()
            for p in pins {
                let q = shot.point(for: p)
                UIBezierPath(ovalIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)).fill()
            }
        }
        Self.kept.setObject(out, forKey: k)
        image = out
    }
}

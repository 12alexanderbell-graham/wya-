import SwiftUI
import MapKit

// PINS (Part 8; 7 Nov: Apple's map, decided 31 Oct 11:19; one plain black pin until its
// colour is changed, 7 Nov 16:37). First slice: Apple's map under the head and the water whenever Pins is the mode, the
// camera taken over from our map; hold the map 0.4 s and a pin drops there, named after the finest place it is in;
// tap a pin and the water shows its name and place; hold a pin for its menu. Pins are kept on the phone (pins.json).
// Still to come (8.5 to 8.8): the dock's tools (they need their icons first), the pin's sheet at 50%, routes, drawing.

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
    /// gamma-encoded P3, or nil for the plain black
    var colour: [Double]? { pick.map { let v = $0.p3; return [v.x, v.y, v.z] } }

    var title: String { !name.isEmpty ? name : place.components(separatedBy: ", ").first.flatMap { $0.isEmpty ? nil : $0 } ?? "Pin" }
    /// its place and day; under the place's own name (no name given) the rest of the place, never the name twice
    var line: String {
        let day = made.formatted(.dateTime.day().month(.abbreviated).year())
        let rest = name.isEmpty ? place.components(separatedBy: ", ").dropFirst().joined(separator: ", ") : place
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
    func drop(at c: CLLocationCoordinate2D, country: (id: String, name: String)? = nil) {
        var p = Pin(lat: c.latitude, lon: c.longitude)
        p.cc = country?.id
        dropping = p.id
        pins.append(p)
        selected = p.id
        save()
        undoableDrop(p.id)
        Task { await name(p.id, country: country?.name) }
    }
    /// DROP A PIN HERE (11.5's town or thing menu): a pin at a place's point, named after it; not chosen, and nothing
    /// else changes until Pins is opened; the undo drop takes it back
    func drop(at c: CLLocationCoordinate2D, named: String, country: (id: String, name: String)?) {
        var p = Pin(lat: c.latitude, lon: c.longitude)
        p.cc = country?.id
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
    private func name(_ id: UUID, country ours: String?) async {
        guard let p = pin(id), let req = MKReverseGeocodingRequest(location: CLLocation(latitude: p.lat, longitude: p.lon)) else { return }
        let item = try? await req.mapItems.first
        let a = item?.addressRepresentations
        let city = a?.cityName ?? ""
        let near = item?.name ?? ""
        let country = a?.regionName.flatMap { $0.isEmpty ? nil : $0 } ?? ours ?? ""
        // the finest place, its town, its country, each once: "Kreuzberg, Berlin, Germany"; "Mayo-Belwa, Nigeria"
        var parts: [String] = []
        for x in [near.contains(where: \.isNumber) ? "" : near, city, country] where !x.isEmpty && !parts.contains(x) { parts.append(x) }
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
        cam.centerCoordinateDistance = max(150, min(4.0e7, cam.centerCoordinateDistance / f))
        v.setCamera(cam, animated: true)
    }
    /// our map's view of the world, on Apple's map: the same middle, the same span of latitude
    /// HISTORY IN PINS (Part 13's table: your pins by their date): one line through them from the oldest to the newest,
    /// as the journey on our own map: straight legs (a leg over 180 degrees goes the short way, across the date line),
    /// 2.5 pt, round ends, no edge, black at the first pin to blue at the last, each pin one equal step of the colour.
    /// With fewer than two pins there is nothing to join and the tool refuses.
    private(set) var historyOn = false
    private var journey: MKPolyline?
    /// the pins' order and places the line was drawn for (a pin moved, re-dated, made or deleted redraws it)
    private var journeyKey = ""
    /// each stop's colour and place along the line, for the renderer
    private(set) var journeyColours: ([UIColor], [CGFloat]) = ([], [])
    @discardableResult func history(_ on: Bool) -> Bool {
        historyOn = on && PinStore.shared.pins.count > 1
        redrawHistory()
        // turned on: the whole journey framed between the head and the water at its stop (as on our own map, 13.4);
        // the top clears a pin's own height under the head
        if historyOn, let v = view, let j = journey, let w = water {
            let L = w.layout
            let pad = UIEdgeInsets(top: L.headBottom + 30 + 16, left: 40,
                                   bottom: L.H - w.y(w.stop == .full ? .half : w.stop) + 32, right: 72)
            v.setVisibleMapRect(j.boundingMapRect, edgePadding: pad, animated: true)
        }
        return historyOn || !on
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
            let n = pins.count
            let a = UIColor(Palette.ink), b = UIColor(Palette.blue)
            journeyColours = ((0 ..< n).map { Self.mix(a, b, CGFloat($0) / CGFloat(n - 1)) },
                              (0 ..< n).map { j.location(atPointIndex: $0) })
            journey = j
            v.addOverlay(j, level: .aboveRoads)
        }
        if let old { v.removeOverlay(old) }
    }
    /// the line again when the pins changed under it
    func historyNeedsRedraw(_ pins: [Pin]) -> Bool {
        historyOn && pins.sorted { $0.made < $1.made }.map { "\($0.id)\($0.lat),\($0.lon)" }.joined(separator: "|") != journeyKey
    }
    private static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
    // ROUTES (8.3): the kept routes' lines and labels on Apple's map, and while the Route row is open Apple's other ways
    @ObservationIgnored private var routeOverlays: [MKOverlay] = []
    @ObservationIgnored private var routeLabels: [RouteLabel] = []
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
        for route in r.routes where route.points.count > 1 {
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
    }
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
        let L = water?.layout
        // (the line's box ends at the pins' tips: room above for their heads, and at the sides for their names)
        let pad = UIEdgeInsets(top: (L?.headBottom ?? 120) + 56, left: 76, bottom: (L.map { $0.H - $0.top(.quarter) } ?? 220) + 40, right: 84)
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
        guard let v = view, let w = world, let f = w.frame(of: i) else { return }
        let a = EqualEarth.unproject(SIMD2(Double(f.x), Double(f.y))), b = EqualEarth.unproject(SIMD2(Double(f.z), Double(f.w)))
        let p1 = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, a.lat)), longitude: a.lon))
        let p2 = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, b.lat)), longitude: b.lon))
        let r = MKMapRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
        let L = water?.layout
        let pad = UIEdgeInsets(top: (L?.headBottom ?? 120) + 16, left: 24,
                               bottom: (L.map { $0.H - $0.top(.quarter) } ?? 220) + 16, right: 72)
        v.setVisibleMapRect(r, edgePadding: pad, animated: true)
    }

    /// Apple's map over a pin picked from the list: the pin in the middle, no farther out than 400 km
    func go(to p: Pin) {
        guard let v = view else { return }
        let cam = MKMapCamera(lookingAtCenter: p.coordinate, fromDistance: min(v.camera.centerCoordinateDistance, 400_000), pitch: 0, heading: 0)
        v.setCamera(cam, animated: true)
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
        v.register(PinAnnotationView.self, forAnnotationViewWithReuseIdentifier: PinAnnotationView.id)
        v.setRegion(PinsMapState.region(from: map), animated: false)
        // HOLD THE MAP 0.4 s ANYWHERE (8.4): a pin drops there; a finger moving more than 8 pt is a pan, not a drop
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.4
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
        context.coordinator.sync(v, store.pins)
        // the journey asked for before this map was made (history turned on as Pins opened), and the kept routes
        PinsMapState.shared.redrawHistory()
        PinsMapState.shared.redrawRoutes()
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) {
        context.coordinator.sync(v, store.pins)
        context.coordinator.select(v, store.selected)
        let L = water.layout
        // Apple's credit (Legal) on the map just above the water, at the sheet's inner left (Apple asks for it to be
        // seen; asked 30 Oct 03:00); at full nothing of the map is seen
        let top = water.y(water.stop == .full ? .half : water.stop)
        // the credit follows the water's edge as it moves (read every frame the water moves), never above 50%
        let edge = max(water.form().top, water.y(.half))
        let margins = UIEdgeInsets(top: L.headBottom, left: L.sheetInset + 8, bottom: max(0, L.H - edge), right: L.sheetInset)
        if v.layoutMargins != margins { v.layoutMargins = margins }
        context.coordinator.reveal(v, store.selected, top: top, L: L, stop: water.stop)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate, UIDropInteractionDelegate, UIContextMenuInteractionDelegate {
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
        func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
            guard let v = i.view as? MKMapView, let line = route(at: l, in: v), let id = line.routeID else { return nil }
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
        func mapView(_ v: MKMapView, regionDidChangeAnimated animated: Bool) { moving = false }
        /// the stacks and names follow the camera as it moves (a pinch in spreads a stack, 8.3)
        func mapViewDidChangeVisibleRegion(_ v: MKMapView) { arrange(v) }

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
                        let s = PinAnnotationView.nameSize(p.title)
                        let r = CGRect(x: pt.x - s.width / 2, y: pt.y + 2, width: s.width, height: s.height)
                        if !taken.contains(where: { $0.intersects(r.insetBy(dx: -4, dy: -2)) }) { name = p.title; taken.append(r) }
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

        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let v = g.view as? MKMapView else { return }
            WhatsHere.shared.close()
            if closedThisTouch { return }
            let p = g.location(in: v)
            // on a pin: its own menu, not a new pin; on a route: the route's menu (the lock keeps menus: it only refuses
            // a new pin)
            if v.hitTest(p, with: nil) is PinAnnotationView || route(at: p, in: v) != nil { return }
            // the lock stops dropping, never looking (as on every map)
            if map.locked { Feel.refuse(); return }
            Feel.tick()
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
            let r = MKGradientPolylineRenderer(polyline: p)
            let (c, at) = PinsMapState.shared.journeyColours
            if c.count == p.pointCount { r.setColors(c, locations: at) } else { r.setColors([UIColor(Palette.ink), UIColor(Palette.blue)], locations: [0, 1]) }
            r.lineWidth = 2.5
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }

        func mapView(_ v: MKMapView, viewFor a: MKAnnotation) -> MKAnnotationView? {
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
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = UIColor(Palette.ink)
        l.isHidden = true
        TownNamesView.glow(l)
        addSubview(l)
        return l
    }()
    /// the name's size at 12 pt (to test for room before it shows)
    static func nameSize(_ s: String) -> CGSize {
        (s as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)])
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

    func fall() {
        transform = CGAffineTransform(translationX: 0, y: -57)
        // (Reduce Motion: the same fall on the tight spring, 0.2 s, 0.4)
        UIView.animate(withDuration: Motion.reduce ? 0.2 : 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: []) {
            self.transform = .identity
        } completion: { _ in Feel.notch() }
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
                WhatsHere.shared.show(at: at, lat: now.lat, lon: now.lon, land: land, map: m)
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
            if PinRoutes.shared.open {
                // the Route row is in this place (RouteRow, over the water)
                Color.clear.frame(height: 1)
            } else if let p = store.pin(store.selected) {
                // its name on the caption's own name line (a caption laid out unseen under it gives the place), so the
                // title sits where every map's name sits at each stop
                ZStack(alignment: .top) {
                    Caption(name: " ", count: 0, tail: " ", night: false).hidden()
                    VStack(spacing: 4) {
                        Text(p.title).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                        Text(p.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                    }
                }
                // (capped where the caption is, so the name stays on its line at the largest sizes)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                // none chosen: the caption every map has (Places' "Everywhere 4"), how to drop one under a 0
                Caption(name: "Pins", count: store.pins.count, tail: store.pins.isEmpty ? "Hold the map to drop a pin" : "",
                        night: FullView.night(form.page))
            }
        }
        // (no fade between "Pins" and a pin's name: the words are simply there, 8 Nov; it crossfaded on every pin tap)
        // (clear of the Share circle on each side while the sheet is up, so the name stays centred)
        .frame(width: L.W - 2 * L.sheetInset - 32 - (store.selected != nil && water.stop != .quarter && water.stop != .closed ? 96 : 0))
        .position(x: L.W / 2, y: captionY)
        .allowsHitTesting(false)
    }
}


/// YOUR PINS (8.8's list) at 50% and full when none is chosen: newest first, the same rows as your maps in Places
/// (the pin in its colour, its name in body, its place and day in a grey line, 56 pt a row). A tap chooses the pin:
/// Apple's map goes to it and the water to 25%, under its name. The rows scroll only at full.
struct PinsList: View {
    let water: Water
    /// the caption's centre
    let captionY: CGFloat
    var store = PinStore.shared

    var body: some View {
        let L = water.layout
        // (under the caption's foot, as Places' rows)
        let foot = captionY + 65
        let fade = L.capsule.minY - 44
        let top = foot + 8
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // with routes kept, a Routes section under the pins (8.6's Saved), its name 15 pt semibold black 50%;
                // the pins need no name of their own: the caption over them already says Pins
                let routes = PinRoutes.shared.routes
                ForEach(store.pins.reversed()) { p in row(p) }
                if !routes.isEmpty {
                    header("Routes").padding(.top, 12)
                    ForEach(routes.reversed()) { r in routeRow(r) }
                }
                Color.clear.frame(height: L.H - fade + 24)
            }
        }
        // 16 pt inside the water, as the Stamped list's rows (the box already starts at the water's edge)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollDisabled(water.stop != .full)
        .frame(width: L.W - 2 * L.sheetInset, height: max(0, L.H - top))
        .padding(.top, top)
        .frame(width: L.W, height: L.H, alignment: .top)
        .mask { PlacesShelf.band(top: foot - 8, bottom: fade, H: L.H) }
        .allowsHitTesting(water.stop != .quarter && water.stop != .closed)
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
                Button("Colour") { store.selected = nil; PinRoutes.shared.colouring = r.id; water.go(.full) }
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

    private func row(_ p: Pin) -> some View {
        HStack(spacing: 12) {
            PinMarker(colour: p.colour.map { SIMD3($0[0], $0[1], $0[2]) } ?? PinColours.standard, p3: p.colour != nil)
                .scaleEffect(0.8)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.title).font(.body).foregroundStyle(Palette.ink).lineLimit(1)
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

    var body: some View {
        let L = water.layout
        let fade = L.capsule.minY - 24
        let whole = water.stop == .full
        if let p = store.pin(store.selected) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    section("Name") {
                        TextField("", text: Binding(get: { p.name }, set: { v in
                            if v.count > 60 { Feel.refuse() }
                            store.rename(p.id, v)
                        }), prompt: Text("Add a name").foregroundStyle(Palette.ink.opacity(0.5)))
                        .font(.body).foregroundStyle(Palette.ink)
                        .focused($typing)
                        .submitLabel(.done)
                        .frame(minHeight: 44)
                    }
                    section("Colour") {
                        Button {
                            Feel.tap()
                            pick = p.pick ?? Self.nearBlack
                            picking.toggle()
                            // the picker is taller than the room at 50%: it opens with the water at full
                            if picking, water.stop != .full { water.go(.full) }
                        } label: {
                            HStack {
                                // the colour's own name ("deep red"), as the picker names it
                                Text(p.pick.map { ColourNames.name($0).capitalizedFirst } ?? "Black").font(.body).foregroundStyle(Palette.ink)
                                Spacer(minLength: 8)
                                Circle().fill(p.pick?.color ?? Palette.ink).frame(width: 28, height: 28)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if picking {
                            ColourPicker(colour: Binding(get: { pick }, set: { c in pick = c; store.colour(p.id, c) }),
                                         suggested: nil, width: L.W - 2 * L.sheetInset - 32) { c in ColourStore.shared.add(c) }
                            if p.pick != nil {
                                Button {
                                    Feel.tap(); store.colour(p.id, nil); picking = false
                                } label: {
                                    Text("Reset to black").font(.body).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    // NOTHING CUT AT REST: below full the sheet holds what fits whole (Name, Colour, Note);
                    // Coordinates and Delete pin are at full, where it scrolls (as the picker, which needs full)
                    section("Note") {
                        TextField("", text: Binding(get: { p.note ?? "" }, set: { v in
                            if v.count > 600 { Feel.refuse() }
                            store.note(p.id, v)
                        }), prompt: Text("Add a note").foregroundStyle(Palette.ink.opacity(0.5)), axis: .vertical)
                        .font(.body).foregroundStyle(Palette.ink)
                        .lineLimit(whole ? 1 ... 12 : 1 ... 2)
                        .focused($typing)
                        .frame(minHeight: 44)
                    }
                    if whole { fullRows(p) }
                    Color.clear.frame(height: L.H - fade + 24)
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(water.stop != .full)
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
            .onChange(of: typing) { _, t in if t { water.go(.full) } }
            .onChange(of: store.selected) { _, _ in picking = false; colourIfAsked() }
            .onChange(of: store.colourAsked) { _, _ in colourIfAsked() }
            // pulled down below full, the picker goes back into its row
            .onChange(of: water.stop) { _, s in if s != .full { picking = false } }
            .onAppear { colourIfAsked() }
            // the picker going away (closed, Reset, another pin, the water down): its moves are one undo
            .onChange(of: picking) { _, on in if on, let id = store.selected { store.colourStart(id) } else if !on { store.colourEnd() } }
            .onDisappear { store.colourEnd() }
        }
    }

    /// the rows seen at full: Coordinates (Apple's marked place has them; a tap copies them), then Delete pin, the last
    /// row, in red words (as Apple's own Remove; at once, the undo drop brings it back)
    @ViewBuilder private func fullRows(_ p: Pin) -> some View {
        section("Coordinates") {
            Button {
                Feel.tap()
                UIPasteboard.general.string = String(format: "%.5f, %.5f", p.lat, p.lon)
            } label: {
                Text(Self.coordinates(p)).font(.body.monospacedDigit()).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Copies the coordinates")
        }
        Button { Feel.lift(); store.remove(p.id); water.go(.quarter) } label: {
            Text("Delete pin").font(.body).foregroundStyle(Palette.red)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

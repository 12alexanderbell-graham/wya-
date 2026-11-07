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
        if let u = url, let d = try? Data(contentsOf: u), let p = try? JSONDecoder().decode([Pin].self, from: d) { pins = p }
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
        MarkStore.shared.did("Pin dropped") { [weak self] in self?.remove(p.id, undoable: false) }
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
        MarkStore.shared.did("Pin dropped") { [weak self] in self?.remove(p.id, undoable: false) }
    }
    func remove(_ id: UUID, undoable: Bool = true) {
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return }
        let gone = pins.remove(at: k)
        if selected == id { selected = nil }
        save()
        if undoable {
            MarkStore.shared.did("\(gone.title) deleted") { [weak self] in
                guard let self else { return }
                self.pins.insert(gone, at: min(k, self.pins.count)); self.save()
            }
        }
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
        guard let k = pins.firstIndex(where: { $0.id == id }) else { return }
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
    func zoom(by f: Double) {
        guard let v = view else { return }
        let cam = v.camera.copy() as! MKMapCamera
        cam.centerCoordinateDistance = max(150, min(4.0e7, cam.centerCoordinateDistance / f))
        v.setCamera(cam, animated: true)
    }
    /// our map's view of the world, on Apple's map: the same middle, the same span of latitude
    /// HISTORY IN PINS (Part 13's table: your pins by their date): one line through them from the oldest to the newest,
    /// black to blue as the journey on our own map (2.5 pt, round ends, the short way round the globe); with fewer than
    /// two pins there is nothing to join and the tool refuses
    private(set) var historyOn = false
    private var journey: MKPolyline?
    @discardableResult func history(_ on: Bool) -> Bool {
        historyOn = on && PinStore.shared.pins.count > 1
        redrawHistory()
        // turned on: the whole journey framed between the head and the water (as on our own map, 13.4)
        if historyOn, let v = view, let j = journey, let w = water {
            let L = w.layout
            let pad = UIEdgeInsets(top: L.headBottom + 40, left: 40, bottom: L.H - w.y(w.stop == .full ? .half : w.stop) + 40, right: 72)
            v.setVisibleMapRect(j.boundingMapRect, edgePadding: pad, animated: true)
        }
        return historyOn || !on
    }
    func redrawHistory() {
        guard let v = view else { return }
        if let j = journey { v.removeOverlay(j); journey = nil }
        guard historyOn else { return }
        let c = PinStore.shared.pins.sorted { $0.made < $1.made }.map(\.coordinate)
        guard c.count > 1 else { return }
        let j = MKGeodesicPolyline(coordinates: c, count: c.count)
        journey = j
        v.addOverlay(j, level: .aboveRoads)
    }
    /// Reset on Apple's map: the whole world, as Apple's own map shows it
    func world() { view?.setVisibleMapRect(.world, animated: true) }
    /// Reset's Around you on Apple's map: some 1,700 km across over the spot
    func around(_ c: CLLocationCoordinate2D) {
        guard let v = view else { return }
        v.setCamera(MKMapCamera(lookingAtCenter: c, fromDistance: 3_000_000, pitch: 0, heading: 0), animated: true)
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
        PinsMapState.shared.view = v
        PinsMapState.shared.water = water
        PinsMapState.shared.map = map
        // its town found for "Open its place's page" (the index is read once, in the background)
        TownIndex.shared.load()
        context.coordinator.sync(v, store.pins)
        // the journey asked for before this map was made (history turned on as Pins opened)
        PinsMapState.shared.redrawHistory()
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) {
        context.coordinator.sync(v, store.pins)
        context.coordinator.select(v, store.selected)
        let L = water.layout
        // Apple's credit (Legal) on the map just above the water, at the sheet's inner left (Apple asks for it to be
        // seen; asked 30 Oct 03:00); at full nothing of the map is seen
        let top = water.y(water.stop == .full ? .half : water.stop)
        let margins = UIEdgeInsets(top: L.headBottom, left: L.sheetInset + 8, bottom: max(0, L.H - top), right: L.sheetInset)
        if v.layoutMargins != margins { v.layoutMargins = margins }
        context.coordinator.reveal(v, store.selected, top: top, L: L, stop: water.stop)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
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
            // a pin made or gone while the journey is up joins or leaves its line
            if (!gone.isEmpty || !new.isEmpty), PinsMapState.shared.historyOn { PinsMapState.shared.redrawHistory() }
            for a in have where ids.contains(a.id) {
                (v.view(for: a) as? PinAnnotationView)?.show(PinStore.shared.pin(a.id))
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
            for a in v.annotations.compactMap({ $0 as? PinAnnotation }) {
                (v.view(for: a) as? PinAnnotationView)?.setChosen(a.id == id)
            }
        }

        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let v = g.view as? MKMapView else { return }
            // the lock stops dropping, never looking (as on every map)
            if map.locked { Feel.refuse(); return }
            let p = g.location(in: v)
            // on a pin: its own menu, not a new pin
            if v.hitTest(p, with: nil) is PinAnnotationView { return }
            Feel.tick()
            let c = v.convert(p, toCoordinateFrom: v)
            PinStore.shared.drop(at: c, country: Self.country(map, c))
            if water.stop != .quarter { water.go(.quarter) }
        }
        /// the country our own map has under a spot
        static func country(_ map: MapController, _ c: CLLocationCoordinate2D) -> (id: String, name: String)? {
            guard let w = map.world, let i = w.place(at: EqualEarth.project(lon: c.longitude, lat: c.latitude)) else { return nil }
            return (w.places[i].id, w.places[i].n)
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

        /// the journey's line (history on): black at its start to blue at its end
        func mapView(_ v: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            guard let p = o as? MKPolyline else { return MKOverlayRenderer(overlay: o) }
            let r = MKGradientPolylineRenderer(polyline: p)
            r.setColors([UIColor(Palette.ink), UIColor(Palette.blue)], locations: [0, 1])
            r.lineWidth = 2.5
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }

        func mapView(_ v: MKMapView, viewFor a: MKAnnotation) -> MKAnnotationView? {
            guard let a = a as? PinAnnotation else { return nil }
            let view = v.dequeueReusableAnnotationView(withIdentifier: PinAnnotationView.id, for: a) as! PinAnnotationView
            view.show(PinStore.shared.pin(a.id))
            view.setChosen(PinStore.shared.selected == a.id, animated: false)
            return view
        }
        /// A8.2: a pin just dropped falls onto its spot from 57 pt above, at its own size (it never grows; 31 Oct: no
        /// growing circles), on the settle, no overshoot; a notch as it lands
        func mapView(_ v: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views {
                guard let a = view.annotation as? PinAnnotation, a.id == PinStore.shared.dropping, let pv = view as? PinAnnotationView else { continue }
                PinStore.shared.dropping = nil
                pv.fall()
            }
        }
        func mapView(_ v: MKMapView, didSelect a: MKAnnotation) {
            guard let a = a as? PinAnnotation else { return }
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
final class PinAnnotationView: MKAnnotationView, UIContextMenuInteractionDelegate {
    static let id = "pin"
    private static var images: [String: UIImage] = [:]
    private var chosen = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        // Apple's own selection would grow it again: ours is the one change (setChosen)
        collisionMode = .rectangle
        addInteraction(UIContextMenuInteraction(delegate: self))
    }
    required init?(coder: NSCoder) { fatalError() }

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
        let h = bounds.height
        let s: CGFloat = on ? 1.2 : 1
        let t = CGAffineTransform(translationX: 0, y: h / 2 * (1 - s) - (on ? 4 : 0)).scaledBy(x: s, y: s)
        if animated {
            UIView.animate(withDuration: 0.26, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) { self.transform = t }
        } else { transform = t }
    }

    func fall() {
        transform = CGAffineTransform(translationX: 0, y: -57)
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: []) {
            self.transform = .identity
        } completion: { _ in Feel.notch() }
    }

    // THE PIN'S HOLD MENU (11.5), its name over the rows built so far, in the book's groups:
    // Edit | Colour | Directions | Open its place's page · Copy coordinates | Share | Delete
    // (Icon, routes, Measure, What's here?, lists and plans come with their parts)
    func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
        guard let a = annotation as? PinAnnotation else { return nil }
        let id = a.id
        PinStore.from = convert(bounds, to: nil)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            MainActor.assumeIsolated { Self.menu(id) }
        }
    }

    @MainActor static func menu(_ id: UUID) -> UIMenu? {
        guard let p = PinStore.shared.pin(id) else { return nil }
        // each runs once the menu has gone (as every hold menu's rows)
        let after = { (f: @escaping () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
        let state = PinsMapState.shared
        let edit = UIAction(title: "Edit") { _ in
            after { PinStore.shared.selected = id; state.water?.go(.half) }
        }
        let colour = UIAction(title: "Colour") { _ in
            after { PinStore.shared.selected = id; PinStore.shared.colourAsked = true; state.water?.go(.full) }
        }
        let directions = UIAction(title: "Directions") { _ in PinStore.directions(p) }
        let open = PinStore.page(p, world: state.map?.world)
        let page = UIAction(title: "Open its place's page", attributes: open == nil ? .disabled : []) { _ in
            after { open?() }
        }
        let copy = UIAction(title: "Copy coordinates") { _ in
            UIPasteboard.general.string = String(format: "%.5f, %.5f", p.lat, p.lon)
        }
        let share = UIAction(title: "Share") { _ in after { PinStore.share(p) } }
        let delete = UIAction(title: "Delete", attributes: .destructive) { _ in after { Feel.lift(); PinStore.shared.remove(id) } }
        return UIMenu(title: p.title, children: [
            UIMenu(options: .displayInline, children: [edit]),
            UIMenu(options: .displayInline, children: [colour]),
            UIMenu(options: .displayInline, children: [directions]),
            UIMenu(options: .displayInline, children: [page, copy]),
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
                Text(p.title).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(p.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            } else {
                // none chosen: the caption every map has (Places'), how to drop one under a 0
                Caption(name: "All my pins", count: store.pins.count, tail: store.pins.isEmpty ? "Hold the map to drop a pin" : "",
                        night: FullView.night(form.page))
            }
        }
        .animation(Motion.quick, value: store.selected)
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
                ForEach(store.pins.reversed()) { p in row(p) }
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
                                    Text("Back to black").font(.body).foregroundStyle(Palette.ink).frame(minHeight: 44)
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
            .accessibilityHint("Copies them")
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
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

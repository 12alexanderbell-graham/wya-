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
    /// gamma-encoded P3 once you have given it a colour; nil: the plain black
    var colour: [Double]? = nil
    var made = Date()

    var title: String { !name.isEmpty ? name : place.components(separatedBy: ", ").first.flatMap { $0.isEmpty ? nil : $0 } ?? "Pin" }
    var line: String {
        let day = made.formatted(.dateTime.day().month(.abbreviated).year())
        return place.isEmpty ? day : "\(place) · \(day)"
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

    /// a pin dropped at `c`: kept at once, named once the phone knows the place; the undo drop takes it back
    func drop(at c: CLLocationCoordinate2D) {
        let p = Pin(lat: c.latitude, lon: c.longitude)
        dropping = p.id
        pins.append(p)
        selected = p.id
        save()
        MarkStore.shared.did("Pin dropped") { [weak self] in self?.remove(p.id, undoable: false) }
        Task { await name(p.id) }
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

    /// the finest place a pin is in, from Apple's reverse geocoding: "Kreuzberg, Berlin"; a town alone; a region and
    /// its country; the sea's name at sea
    private func name(_ id: UUID) async {
        guard let p = pin(id), let req = MKReverseGeocodingRequest(location: CLLocation(latitude: p.lat, longitude: p.lon)) else { return }
        guard let item = try? await req.mapItems.first else { return }
        let a = item.addressRepresentations
        let city = a?.cityName ?? ""
        let near = item.name ?? ""
        let country = a?.regionName ?? ""
        // the finest place, its town, its country, each once: "Kreuzberg, Berlin, Germany"; "Bordj Omar Driss, Algeria"
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
    func zoom(by f: Double) {
        guard let v = view else { return }
        let cam = v.camera.copy() as! MKMapCamera
        cam.centerCoordinateDistance = max(150, min(4.0e7, cam.centerCoordinateDistance / f))
        v.setCamera(cam, animated: true)
    }
    /// our map's view of the world, on Apple's map: the same middle, the same span of latitude
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
        context.coordinator.sync(v, store.pins)
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) {
        context.coordinator.sync(v, store.pins)
        context.coordinator.select(v, store.selected)
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
            for a in have where ids.contains(a.id) {
                (v.view(for: a) as? PinAnnotationView)?.show(PinStore.shared.pin(a.id))
            }
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
            PinStore.shared.drop(at: v.convert(p, toCoordinateFrom: v))
            if water.stop != .quarter { water.go(.quarter) }
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

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

    // THE PIN'S HOLD MENU (11.5, the rows built so far): its name over Copy coordinates · Share · Delete
    func contextMenuInteraction(_ i: UIContextMenuInteraction, configurationForMenuAtLocation l: CGPoint) -> UIContextMenuConfiguration? {
        guard let a = annotation as? PinAnnotation else { return nil }
        let id = a.id
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            MainActor.assumeIsolated {
                guard let p = PinStore.shared.pin(id) else { return nil }
                let after = { (f: @escaping () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: f) }
                let copy = UIAction(title: "Copy coordinates") { _ in
                    UIPasteboard.general.string = String(format: "%.5f, %.5f", p.lat, p.lon)
                }
                let share = UIAction(title: "Share") { _ in
                    after {
                        guard let u = URL(string: "https://maps.apple.com/?ll=\(p.lat),\(p.lon)&q=\(p.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Pin")"),
                              let top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController
                        else { return }
                        top.present(UIActivityViewController(activityItems: [u], applicationActivities: nil), animated: true)
                    }
                }
                let delete = UIAction(title: "Delete", attributes: .destructive) { _ in after { Feel.lift(); PinStore.shared.remove(id) } }
                return UIMenu(title: p.title, children: [UIMenu(options: .displayInline, children: [copy, share]),
                                                        UIMenu(options: .displayInline, children: [delete])])
            }
        }
    }
}

/// PINS' WATER AT 25% (8.5, 8.8's first line; the dock's tools come with their icons): your pins' count, or the chosen
/// pin's name over its place and day; with no pins yet, how to drop one
struct PinsWater: View {
    let water: Water
    let form: Water.Form
    let captionY: CGFloat
    var store = PinStore.shared

    var body: some View {
        let L = water.layout
        VStack(spacing: 4) {
            if let p = store.pin(store.selected) {
                Text(p.title).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    .contentTransition(.numericText())
                Text(p.line).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                    .contentTransition(.numericText())
            } else if store.pins.isEmpty {
                Text("Hold the map to drop a pin").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5))
            } else {
                Text(store.pins.count == 1 ? "1 pin" : "\(store.pins.count) pins").font(.subheadline)
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .contentTransition(.numericText(value: Double(store.pins.count)))
            }
        }
        .animation(Motion.quick, value: store.selected)
        .frame(width: L.W - 2 * L.sheetInset - 32)
        .position(x: L.W / 2, y: captionY)
        .allowsHitTesting(false)
    }
}

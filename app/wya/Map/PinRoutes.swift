import SwiftUI
import MapKit

/// ROUTES BETWEEN PINS (8.3, 8.6's Route): from one pin to another along the roads, Apple's directions (MapKit).
/// Opened from a pin's hold menu (Route from here, Route to here: 11.5), the Route row takes the caption's place in the
/// water: the cross, From and To. A chip waiting for its end is lime; a tap on a pin fills it. Once both ends are set
/// the route is asked for: one solid 3 pt black line with round ends (the two pins are its ends), Apple's other ways
/// behind it as 2 pt black 50%, and its distance and time in a small frosted capsule over its middle. A tap on another
/// way makes it the route. The cross closes the row; the route stays, kept with the pins (routes.json; no Save). It
/// simply appears (no drawing along: 7 Nov, not everything needs an animation). Waiting on the dock's icons: the row's
/// transport choice (driving until then) and the Route tool in the dock.
struct PinRoute: Codable, Identifiable, Hashable {
    var id = UUID()
    var from: UUID
    var to: UUID
    /// the line, as [latitude, longitude] pairs
    var points: [[Double]]
    /// metres and seconds, as Apple gave them
    var distance: Double
    var time: Double
    var made = Date()

    var words: String { Self.words(distance: distance, time: time) }
    static func words(distance: Double, time: Double) -> String {
        let km = Measurement(value: distance, unit: UnitLength.meters).converted(to: .kilometers)
        let d = km.value < 10 ? km.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1))))
            : km.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        let f = DateComponentsFormatter()
        f.allowedUnits = time >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return "\(d) · \(f.string(from: time) ?? "")"
    }
}

/// a route's line on Apple's map (the chosen one, or one of Apple's other ways)
final class PinRouteLine: MKPolyline {
    var routeID: UUID?
    var other = false
    /// for another way: its own distance and time, kept to make it the route when tapped
    var distance: Double = 0
    var time: Double = 0
}

/// a route's distance and time, over its middle
final class RouteLabel: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let words: String
    init(id: UUID, at c: CLLocationCoordinate2D, words: String) { self.id = id; coordinate = c; self.words = words }
}

/// its view: 13 pt semibold words in a 28 pt frosted capsule (a surface over the map, 7 Nov's glass)
final class RouteLabelView: MKAnnotationView {
    static let id = "route"
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let label = UILabel()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        collisionMode = .rectangle
        displayPriority = .required
        glass.layer.cornerRadius = 14
        glass.clipsToBounds = true
        addSubview(glass)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor(Palette.ink)
        glass.contentView.addSubview(label)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ words: String) {
        label.text = words
        label.sizeToFit()
        let w = label.bounds.width + 20
        frame.size = CGSize(width: w, height: 28)
        glass.frame = bounds
        label.center = CGPoint(x: w / 2, y: 14)
        accessibilityLabel = words
    }
}

@MainActor
@Observable
final class PinRoutes {
    static let shared = PinRoutes()
    enum End { case from, to }
    private(set) var routes: [PinRoute] = []
    /// the Route row is up in the water
    private(set) var open = false
    private(set) var from: UUID?
    private(set) var to: UUID?
    /// the chip a pin tap fills next
    private(set) var waiting: End?
    /// "No route" in the To chip for a moment (Apple found none)
    private(set) var noRoute = false
    /// the route the row is making (replaced when an end changes)
    @ObservationIgnored private var current: UUID?
    /// Apple's other ways for the current route (not kept: they are asked again)
    @ObservationIgnored private var others: [MKRoute] = []
    @ObservationIgnored private var asking = 0

    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("routes.json")
    }
    init() {
        if let u = url, let d = try? Data(contentsOf: u), let r = try? JSONDecoder().decode([PinRoute].self, from: d) { routes = r }
    }
    private func save() {
        guard let u = url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(routes) { try? d.write(to: u, options: .atomic) }
    }

    /// Route from here / Route to here (the pin's menu): the row opens with that end set, the other waiting
    func start(_ end: End, at pin: UUID) {
        if !open { open = true; from = nil; to = nil; current = nil; others = [] }
        set(end, pin)
    }
    /// a pin tapped while the row waits for an end: it fills that end (true: the tap was the row's)
    func pinTapped(_ pin: UUID) -> Bool {
        guard open, let w = waiting else { return false }
        Feel.tap()
        set(w, pin)
        return true
    }
    /// a chip tapped: it waits for a pin
    func choose(_ end: End) {
        guard open else { return }
        Feel.tap()
        waiting = end
    }
    /// the cross: the row closes; the route stays (no Save)
    func close() {
        guard open else { return }
        open = false; waiting = nil; noRoute = false
        from = nil; to = nil; current = nil; others = []
        PinsMapState.shared.redrawRoutes()
    }

    private func set(_ end: End, _ pin: UUID) {
        switch end {
        case .from: from = pin
        case .to: to = pin
        }
        // the same pin at both ends is no route: the other end waits again
        if from == to { if end == .from { to = nil } else { from = nil } }
        waiting = from == nil ? .from : to == nil ? .to : nil
        if from != nil, to != nil { ask() }
    }

    /// Apple's directions between the two pins (driving until the transport choice comes with its icons)
    private func ask() {
        guard let f = from.flatMap({ PinStore.shared.pin($0) }), let t = to.flatMap({ PinStore.shared.pin($0) }) else { return }
        asking += 1
        let me = asking
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: f.lat, longitude: f.lon), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: t.lat, longitude: t.lon), address: nil)
        req.transportType = .automobile
        req.requestsAlternateRoutes = true
        Task {
            let answer = try? await MKDirections(request: req).calculate()
            guard me == asking, open else { return }
            guard let routes = answer?.routes, let best = routes.first else {
                // across an ocean by car: the To chip says so for 2 s
                Feel.refuse()
                noRoute = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in if me == asking { noRoute = false } }
                return
            }
            keep(best, from: f.id, to: t.id)
            others = Array(routes.dropFirst())
            PinsMapState.shared.redrawRoutes()
            PinsMapState.shared.frame(route: current)
        }
    }

    /// the route made or changed by the row: one undo takes it back
    private func keep(_ r: MKRoute, from f: UUID, to t: UUID) {
        let line = Self.points(r.polyline)
        if let id = current, let k = routes.firstIndex(where: { $0.id == id }) {
            let was = routes[k]
            routes[k].from = f; routes[k].to = t; routes[k].points = line; routes[k].distance = r.distance; routes[k].time = r.expectedTravelTime
            save()
            MarkStore.shared.did("Route changed") { [weak self] in
                guard let self, let j = self.routes.firstIndex(where: { $0.id == id }) else { return }
                self.routes[j] = was; self.save(); PinsMapState.shared.redrawRoutes()
            }
        } else {
            let new = PinRoute(from: f, to: t, points: line, distance: r.distance, time: r.expectedTravelTime)
            current = new.id
            routes.append(new)
            save()
            MarkStore.shared.did("Route added") { [weak self] in self?.remove(new.id, undoable: false) }
        }
    }
    /// another way tapped: it becomes the route (the old one is let go: Apple's ways are asked for again next time)
    func choose(other line: PinRouteLine) {
        guard let id = current, let k = routes.firstIndex(where: { $0.id == id }),
              let i = others.firstIndex(where: { Self.points($0.polyline) == Self.points(line) }) else { return }
        Feel.tap()
        let was = routes[k]
        let picked = others.remove(at: i)
        routes[k].points = Self.points(picked.polyline); routes[k].distance = picked.distance; routes[k].time = picked.expectedTravelTime
        save()
        MarkStore.shared.did("Route changed") { [weak self] in
            guard let self, let j = self.routes.firstIndex(where: { $0.id == id }) else { return }
            self.routes[j] = was; self.save(); PinsMapState.shared.redrawRoutes()
        }
        PinsMapState.shared.redrawRoutes()
    }
    /// Apple's other ways for the route being made, as lines with their distance and time
    var otherWays: [(MKPolyline, Double, Double)] {
        open ? others.map { ($0.polyline, $0.distance, $0.expectedTravelTime) } : []
    }
    var currentID: UUID? { current }

    func remove(_ id: UUID, undoable: Bool = true) {
        guard let k = routes.firstIndex(where: { $0.id == id }) else { return }
        let gone = routes.remove(at: k)
        if current == id { current = nil }
        save()
        PinsMapState.shared.redrawRoutes()
        if undoable {
            MarkStore.shared.did("Route deleted") { [weak self] in
                guard let self else { return }
                self.routes.insert(gone, at: min(k, self.routes.count)); self.save(); PinsMapState.shared.redrawRoutes()
            }
        }
    }
    /// a pin deleted: its routes go with it (and come back with its undo, which restores the pin only)
    func pinGone(_ pin: UUID) {
        let before = routes.count
        routes.removeAll { $0.from == pin || $0.to == pin }
        if from == pin { from = nil }
        if to == pin { to = nil }
        if routes.count != before { save(); PinsMapState.shared.redrawRoutes() }
    }

    static func points(_ l: MKPolyline) -> [[Double]] {
        var c = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: l.pointCount)
        l.getCoordinates(&c, range: NSRange(location: 0, length: l.pointCount))
        return c.map { [$0.latitude, $0.longitude] }
    }
}

/// THE ROUTE ROW, in the caption's place while it is open: the cross, From, To (8.6)
struct RouteRow: View {
    let water: Water
    let captionY: CGFloat
    @State private var r = PinRoutes.shared

    var body: some View {
        let L = water.layout
        let chipW = min(138, (L.W - 2 * L.sheetInset - 32 - 44 - 24) / 2)
        HStack(spacing: 12) {
            Button {
                Feel.tap()
                r.close()
            } label: {
                Icon5(key: "cross", ink: Palette.ink, size: 22)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close route")
            chip(.from, r.from, word: "From", width: chipW)
            chip(.to, r.to, word: r.noRoute ? "No route" : "To", width: chipW)
        }
        .position(x: L.W / 2, y: captionY)
    }

    private func chip(_ end: PinRoutes.End, _ pin: UUID?, word: String, width: CGFloat) -> some View {
        let p = pin.flatMap { PinStore.shared.pin($0) }
        let waiting = r.waiting == end
        return Button { r.choose(end) } label: {
            HStack(spacing: 6) {
                if let p, !(end == .to && r.noRoute) {
                    Circle().fill(PinRows.colour(p)).frame(width: 12, height: 12)
                    Text(p.title).font(.subheadline).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                } else {
                    Text(word).font(.body).foregroundStyle(waiting ? Palette.ink : Palette.ink.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: 36)
            // the one waiting for a pin: filled lime, ink words; the others a quiet ground on the water (no glass, no edge)
            .background(Capsule().fill(waiting ? Palette.lime : Palette.ink.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(end == .from ? "From" : "To"), \(p?.title ?? (waiting ? "waiting for a pin" : "not set"))")
    }
}

/// a pin's colour as a SwiftUI colour (the plain black, or the picker's)
enum PinRows {
    static func colour(_ p: Pin) -> Color {
        guard let c = p.colour else { return Palette.ink }
        return Color(.displayP3, red: c[0], green: c[1], blue: c[2])
    }
}

import SwiftUI
import MapKit

/// ROUTES BETWEEN PINS (8.3, 8.6's Route): from one pin to another along the roads, Apple's directions (MapKit).
/// Opened from a pin's hold menu (Route from here, Route to here: 11.5), the Route row takes the caption's place in the
/// water: the cross, From and To. A chip waiting for its end is lime; a tap on a pin fills it. Once both ends are set
/// the route is asked for: one solid 3 pt black line with round ends (the two pins are its ends), Apple's other ways
/// behind it as 2 pt black 50%, and its distance and time in a small frosted capsule over its middle. A tap on another
/// way makes it the route. The cross closes the row; the route stays, kept with the pins (routes.json; no Save). It
/// simply appears (no drawing along). Waiting on the dock's icons: the row's
/// transport choice (driving until then) and the Route tool in the dock.
struct PinRoute: Codable, Identifiable, Hashable {
    var id = UUID()
    /// the map of yours it is in (Map/PinMaps.swift); nil: none
    var map: UUID? = nil
    var from: UUID
    var to: UUID
    /// the line, as [latitude, longitude] pairs
    var points: [[Double]]
    /// metres and seconds, as Apple gave them
    var distance: Double
    var time: Double
    var made = Date()
    /// on foot (nil: by car, the first way)
    var walk: Bool? = nil
    /// its ends that are not pins: spots on land, each named when it was tapped (8.6)
    var spots: [RouteSpot]? = nil
    /// the colour you gave it (the picker's own value); nil: black (8.3)
    var pick: ColourPick? = nil
    /// a straight line between its ends (how a route starts, 14 Nov); nil: Apple's way by road or on foot
    var straight: Bool? = nil
    /// its way as directions gave it, with the ends and travel asked for (its name and colour are not part of it)
    struct Way: Equatable { var from: UUID; var to: UUID; var walk: Bool?; var spots: [RouteSpot]?; var points: [[Double]]; var distance: Double; var time: Double }
    var way: Way {
        get { Way(from: from, to: to, walk: walk, spots: spots, points: points, distance: distance, time: time) }
        set { from = newValue.from; to = newValue.to; walk = newValue.walk; spots = newValue.spots; points = newValue.points; distance = newValue.distance; time = newValue.time }
    }
    /// its line's colour on the map
    var ink: UIColor { pick.map { UIColor($0.color) } ?? UIColor(Palette.ink) }

    var words: String { straight == true ? Self.words(distance: distance) : Self.words(distance: distance, time: time) }
    /// a straight line's words: only how far
    static func words(distance: Double) -> String {
        let km = Measurement(value: distance, unit: UnitLength.meters).converted(to: .kilometers)
        return km.formatted(.measurement(width: .abbreviated, usage: .road,
                                         numberFormatStyle: .number.precision(.fractionLength(km.value < 10 ? 1 : 0))))
    }
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

/// a route's end that is not a pin: a spot on land, kept with its route (no pin is made for it)
struct RouteSpot: Codable, Hashable {
    var id = UUID()
    var lat: Double
    var lon: Double
    var name: String
}

/// a route's line on Apple's map (the chosen one, or one of Apple's other ways)
final class PinRouteLine: MKPolyline {
    var routeID: UUID?
    var other = false
    /// for another way: which of Apple's other ways it is
    var index = 0
    /// for another way: its own distance and time, kept to make it the route when tapped
    var distance: Double = 0
    var time: Double = 0
}

/// a route's distance and time, over its middle
/// an end of the route being made that is a spot on land: a small black dot where the tap was
final class RouteEnd: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(id: UUID, at c: CLLocationCoordinate2D) { self.id = id; coordinate = c }
}
final class RouteEndView: MKAnnotationView {
    static let id = "routeEnd"
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        backgroundColor = UIColor(Palette.ink)
        layer.cornerRadius = 5
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }
    /// it is simply there where the finger was, as a dropped pin is (no growing circle, no bounce)
    func appear() {
        transform = .identity
        alpha = 1
    }
}

final class RouteLabel: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let words: String
    init(id: UUID, at c: CLLocationCoordinate2D, words: String) { self.id = id; coordinate = c; self.words = words }
}

/// its view: 13 pt semibold words in a 28 pt frosted capsule (a surface over the map)
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
    /// a view MapKit hands on to another route comes back seen (a menu or a full map may have hidden it)
    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1
        isHidden = false
    }
    func show(_ words: String) {
        label.text = words
        label.sizeToFit()
        let w = label.bounds.width + 20
        frame.size = CGSize(width: w, height: 28)
        glass.frame = bounds
        label.center = CGPoint(x: w / 2, y: 14)
        accessibilityLabel = words
    }
    /// the route's hold menu, for VoiceOver as actions (the same rows)
    var routeID: UUID?
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            guard let id = routeID else { return nil }
            let r = PinRoutes.shared
            // the route being made: Apple's other ways can be chosen here too (a tap on a line is the only other way)
            let ways = id == r.currentID ? r.otherWays.enumerated().map { n, w in
                UIAccessibilityCustomAction(name: "Other way: \(PinRoute.words(distance: w.1, time: w.2))") { _ in r.choose(other: n); return true }
            } : []
            return ways + (r.menu(id).map { MapMTKView.actions($0) } ?? [])
        }
        set {}
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
    /// the row's spots on land not yet in a kept route
    private var temp: [UUID: RouteSpot] = [:]
    /// the route whose colour is being picked in the water (its hold menu's Colour)
    var colouring: UUID? {
        // the colour sheet going away (or to another route): its moves are one undo
        didSet { if oldValue != colouring { colourEnd(oldValue); colourWas = colouring.map { c in (c, routes.first { $0.id == c }?.pick) } } }
    }
    @ObservationIgnored private var colourWas: (id: UUID, pick: ColourPick?)?
    private func colourEnd(_ id: UUID?) {
        guard let was = colourWas, was.id == id else { return }
        colourWas = nil
        guard let r = routes.first(where: { $0.id == was.id }), r.pick != was.pick else { return }
        let now = r.pick, id = was.id
        MarkStore.shared.did("Route colour changed", back: { [weak self] in self?.colour(id, was.pick) },
                             forth: { [weak self] in self?.colour(id, now) })
    }
    /// words a route shows for 2 s in place of its distance ("No walking route"), on the map and in the list
    private(set) var notes: [UUID: String] = [:]
    /// the newest re-ask of each route, and the way it was asked for (a second one starts from the first's ends)
    @ObservationIgnored private var asked: [UUID: (Int, PinRoute)] = [:]
    @ObservationIgnored private var askedCount = 0
    func note(_ id: UUID, _ words: String) {
        notes[id] = words
        PinsMapState.shared.note(id, words)
        UIAccessibility.post(notification: .announcement, argument: words)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in if self?.notes[id] == words { self?.notes[id] = nil } }
    }

    /// an end as a route sees it: a pin (where it is now) or a spot
    struct Place { let lat: Double; let lon: Double; let title: String; let pin: Pin? }
    func end(_ id: UUID?, _ r: PinRoute? = nil) -> Place? {
        guard let id else { return nil }
        if let p = PinStore.shared.pin(id) { return Place(lat: p.lat, lon: p.lon, title: p.title, pin: p) }
        let s = r?.spots?.first(where: { $0.id == id }) ?? temp[id] ?? routes.lazy.compactMap { $0.spots?.first { $0.id == id } }.first
        return s.map { Place(lat: $0.lat, lon: $0.lon, title: $0.name, pin: nil) }
    }

    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("routes.json")
    }
    init() {
        guard let u = url, let d = try? Data(contentsOf: u) else { return }
        if let r = try? JSONDecoder().decode([PinRoute].self, from: d) { routes = r } else { Self.putAside(u) }
    }
    /// a file that can't be read is moved beside itself ("routes.json.unreadable-<time>"), never written over
    nonisolated static func putAside(_ u: URL) {
        let to = u.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: u, to: to)
    }
    private func save() {
        guard let u = url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(routes) { try? d.write(to: u, options: .atomic) }
    }

    /// the dock's Route tool: the row opens with both ends empty, From waiting for a pin or a tap on the map
    func openEmpty() {
        if !open { open = true; from = nil; to = nil; current = nil; others = []; noRoute = false; temp = [:]; asking += 1 }
        waiting = .from
    }
    /// Route from here / Route to here (the pin's menu): the row opens with that end set, the other waiting
    func start(_ end: End, at pin: UUID) {
        if !open { open = true; from = nil; to = nil; current = nil; others = []; noRoute = false; temp = [:]; asking += 1 }
        set(end, pin)
    }
    /// a pin tapped while the row waits for an end: it fills that end (true: the tap was the row's)
    func pinTapped(_ pin: UUID) -> Bool {
        guard open else { return false }
        freshIfMade()
        guard let w = waiting else { return false }
        Feel.tap()
        set(w, pin)
        return true
    }
    /// a tap on land while the row waits for an end: a spot there fills it, named after the nearest town within 15 km
    /// ("Kreuzberg" in it, "Near Kreuzberg" outside it), else the country; no pin is made (true: the tap was the row's)
    func landTapped(_ c: CLLocationCoordinate2D, country: String) -> Bool {
        guard open else { return false }
        freshIfMade()
        guard let w = waiting else { return false }
        Feel.tap()
        // in a town (within 3 km of its point) the town; anywhere else its country (12 Nov: no made-up names, no
        // "Near ...")
        let name = TownIndex.shared.nearest(lat: c.latitude, lon: c.longitude).flatMap { t in
            CLLocation(latitude: t.lat, longitude: t.lon).distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 3000
                ? t.name : nil
        } ?? country
        let spot = RouteSpot(lat: c.latitude, lon: c.longitude, name: name)
        temp[spot.id] = spot
        set(w, spot.id)
        return true
    }
    /// TAP TWO PINS (12 Nov 17:08): with a route made (both ends set), the next tap starts another, from there
    private func freshIfMade() {
        guard waiting == nil, from != nil, to != nil else { return }
        from = nil; to = nil; current = nil; others = []; noRoute = false; temp = [:]; asking += 1
        waiting = .from
        PinsMapState.shared.redrawRoutes()
    }
    /// the route being made: its ends that are spots on land (an end on a pin is the pin), for the map to mark
    /// (while Apple finds the way, 2 to 6 s, nothing showed where the taps were)
    var spotEnds: [(id: UUID, lat: Double, lon: Double)] {
        guard open else { return [] }
        return [from, to].compactMap { id in
            guard let id, let e = end(id), e.pin == nil else { return nil }
            return (id, e.lat, e.lon)
        }
    }
    /// the cross: the row closes; the route stays (no Save)
    func close() {
        colouring = nil
        guard open else { return }
        open = false; waiting = nil; noRoute = false
        from = nil; to = nil; current = nil; others = []; temp = [:]
        // an answer still on its way is for nothing now
        asking += 1
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
        // the ends changed: an answer on its way is for the old ones
        asking += 1
        if from != nil, to != nil { ask() }
        PinsMapState.shared.redrawRoutes()
    }

    /// Apple's directions between the two pins (driving until the transport choice comes with its icons)
    private func ask() {
        guard let fid = from, let tid = to, let f = end(fid), let t = end(tid) else { return }
        asking += 1
        let me = asking
        noRoute = false
        // A ROUTE STARTS STRAIGHT (14 Nov): a line from one end to the other; its menu turns it to roads or paths
        if current == nil, PinsDockState.shared.routeWay == "straight" { keepStraight(f, t, from: fid, to: tid); return }
        // a straight route whose end was moved stays straight: its line between the new ends
        if let id = current, let k = routes.firstIndex(where: { $0.id == id }), routes[k].straight == true {
            let was = routes[k].way
            routes[k].from = fid; routes[k].to = tid
            routes[k].points = [[f.lat, f.lon], [t.lat, t.lon]]
            routes[k].distance = CLLocation(latitude: f.lat, longitude: f.lon).distance(from: CLLocation(latitude: t.lat, longitude: t.lon))
            save()
            PinsMapState.shared.redrawRoutes()
            if was.from != fid || was.to != tid { changed(id, was: was) }
            return
        }
        let req = Self.request(f, t, walk: PinsDockState.shared.routeWay == "walk")
        req.requestsAlternateRoutes = true
        Task {
            let answer = try? await MKDirections(request: req).calculate()
            // still the row's question: open, the same two ends, both still there
            // (and the ends still where they were asked from: an end pin dragged during the wait asks again, 8 Nov)
            guard me == asking, open, from == fid, to == tid, let f2 = end(fid), let t2 = end(tid) else { return }
            if Self.moved(f, f2) || Self.moved(t, t2) { ask(); return }
            guard let routes = answer?.routes, let best = routes.first else {
                // across an ocean by car: the To chip says so for 2 s
                Feel.refuse()
                noRoute = true
                // (then the end waits again: another tap is where it ends)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                    if me == asking { noRoute = false; to = nil; waiting = .to; PinsMapState.shared.redrawRoutes() }
                }
                return
            }
            // the same two ends already kept (by car): that route is the one changed, never a second copy
            if current == nil, let same = self.routes.first(where: { $0.from == fid && $0.to == tid && $0.walk != true }) { current = same.id }
            keep(best, from: fid, to: tid)
            others = Array(routes.dropFirst())
            PinsMapState.shared.redrawRoutes()
            PinsMapState.shared.frame(route: current)
        }
    }

    /// a straight route between two ends: kept at once (one undo takes it back), drawn in from its start
    private func keepStraight(_ a: Place, _ b: Place, from f: UUID, to t: UUID) {
        let d = CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
        let spots = [f, t].compactMap { id in temp[id] ?? routes.lazy.compactMap { r in r.spots?.first { $0.id == id } }.first }
        var new = PinRoute(from: f, to: t, points: [[a.lat, a.lon], [b.lat, b.lon]], distance: d, time: 0)
        new.straight = true
        new.map = PinMaps.shared.shown
        new.spots = spots.isEmpty ? nil : spots
        current = new.id
        routes.append(new)
        save()
        let id = new.id
        let box = UndoBox<(PinRoute, Int)>()
        MarkStore.shared.did("Route added", back: { [weak self] in
            guard let self, let k = self.routes.firstIndex(where: { $0.id == id }) else { return }
            box.value = (self.routes[k], k)
            self.remove(id, undoable: false)
        }, forth: { [weak self] in
            guard let self, let (r, k) = box.value, !self.routes.contains(where: { $0.id == id }) else { return }
            self.routes.insert(r, at: min(k, self.routes.count)); self.save(); self.undone(id)
        })
        PinsMapState.shared.redrawRoutes()
        PinsMapState.shared.frame(route: current)
    }

    /// the route made or changed by the row: one undo takes it back
    private func keep(_ r: MKRoute, from f: UUID, to t: UUID) {
        let line = Self.points(r.polyline)
        // the ends that are spots go with the route
        let spots = [f, t].compactMap { id in temp[id] ?? routes.lazy.compactMap { r in r.spots?.first { $0.id == id } }.first }
        let kept: [RouteSpot]? = spots.isEmpty ? nil : spots
        if let id = current, let k = routes.firstIndex(where: { $0.id == id }) {
            let was = routes[k].way
            // the same way again (the route asked once more): nothing changed, so no undo and no word about it
            if was.from == f, was.to == t, was.distance == r.distance, was.time == r.expectedTravelTime { return }
            // the same ends asked again and Apple's way only a little different (its time moves with traffic): the
            // line is kept up to date quietly, with no undo step and no "Route changed" (it said so with nothing done)
            if was.from == f, was.to == t, abs(was.distance - r.distance) <= max(50, was.distance * 0.01) {
                routes[k].points = line; routes[k].distance = r.distance; routes[k].time = r.expectedTravelTime
                save()
                PinsMapState.shared.redrawRoutes()
                return
            }
            routes[k].from = f; routes[k].to = t; routes[k].spots = kept; routes[k].points = line; routes[k].distance = r.distance; routes[k].time = r.expectedTravelTime
            save()
            changed(id, was: was)
        } else {
            var new = PinRoute(from: f, to: t, points: line, distance: r.distance, time: r.expectedTravelTime)
            new.map = PinMaps.shared.shown
            if PinsDockState.shared.routeWay == "walk" { new.walk = true }
            new.spots = kept
            current = new.id
            routes.append(new)
            save()
            let id = new.id
            let box = UndoBox<(PinRoute, Int)>()
            MarkStore.shared.did("Route added", back: { [weak self] in
                guard let self, let k = self.routes.firstIndex(where: { $0.id == id }) else { return }
                box.value = (self.routes[k], k)
                self.remove(id, undoable: false)
            }, forth: { [weak self] in
                guard let self, let (r, k) = box.value, !self.routes.contains(where: { $0.id == id }) else { return }
                self.routes.insert(r, at: min(k, self.routes.count)); self.save(); self.undone(id)
            })
        }
    }
    /// another way tapped: it becomes the route (the old one is let go: Apple's ways are asked for again next time)
    func choose(other line: PinRouteLine) { choose(other: line.index) }
    func choose(other i: Int) {
        guard let id = current, let k = routes.firstIndex(where: { $0.id == id }), others.indices.contains(i) else { return }
        Feel.tap()
        let was = routes[k].way
        let picked = others.remove(at: i)
        routes[k].points = Self.points(picked.polyline); routes[k].distance = picked.distance; routes[k].time = picked.expectedTravelTime
        save()
        changed(id, was: was)
        PinsMapState.shared.redrawRoutes()
    }
    /// a route's way changed: one undo takes it back to `was`, its redo makes it as it is now again
    private func changed(_ id: UUID, was: PinRoute.Way) {
        guard let now = routes.first(where: { $0.id == id })?.way else { return }
        MarkStore.shared.did("Route changed", back: { [weak self] in
            guard let self, let j = self.routes.firstIndex(where: { $0.id == id }) else { return }
            self.routes[j].way = was; self.save(); self.undone(id)
        }, forth: { [weak self] in
            guard let self, let j = self.routes.firstIndex(where: { $0.id == id }) else { return }
            self.routes[j].way = now; self.save(); self.undone(id)
        })
    }
    /// an undo touched the route the row is making: Apple's other ways no longer belong to it; the row shows what is
    /// kept now (or, for a route taken back, its ends with nothing made)
    private func undone(_ id: UUID) {
        if open, current == id {
            others = []
            if let r = routes.first(where: { $0.id == id }) { from = r.from; to = r.to } else { current = nil }
            asking += 1
        }
        PinsMapState.shared.redrawRoutes()
    }
    /// Apple's other ways for the route being made, as lines with their distance and time
    var otherWays: [(MKPolyline, Double, Double)] {
        open ? others.map { ($0.polyline, $0.distance, $0.expectedTravelTime) } : []
    }
    var currentID: UUID? { current }

    /// live while the finger moves in the picker; kept as it changes (no Save, as a pin's colour)
    /// (written to the file when the finger lifts, on Reset and when the sheet goes, not on every move)
    func colour(_ id: UUID, _ c: ColourPick?, keep: Bool = true) {
        guard let k = routes.firstIndex(where: { $0.id == id }) else { return }
        routes[k].pick = c
        if keep { save() }
        PinsMapState.shared.recolour(id)
    }
    func keepColours() { save() }

    func remove(_ id: UUID, undoable: Bool = true) {
        guard let k = routes.firstIndex(where: { $0.id == id }) else { return }
        let gone = routes.remove(at: k)
        if colouring == id { colouring = nil }
        // the route the row was making: its other ways go with it
        if current == id { current = nil; others = []; asking += 1 }
        save()
        PinsMapState.shared.redrawRoutes()
        if undoable {
            MarkStore.shared.did("Route deleted", back: { [weak self] in
                guard let self, !self.routes.contains(where: { $0.id == id }) else { return }
                self.routes.insert(gone, at: min(k, self.routes.count)); self.save(); PinsMapState.shared.redrawRoutes()
            }, forth: { [weak self] in self?.remove(id, undoable: false) })
        }
    }
    /// a pin deleted: its routes go with it (given back to the pin's undo, which brings them back with it)
    @discardableResult func pinGone(_ pin: UUID) -> [PinRoute] {
        let gone = routes.filter { $0.from == pin || $0.to == pin }
        routes.removeAll { $0.from == pin || $0.to == pin }
        if gone.contains(where: { $0.id == colouring }) { colouring = nil }
        if open, from == pin || to == pin || gone.contains(where: { $0.id == current }) {
            if from == pin { from = nil }
            if to == pin { to = nil }
            if gone.contains(where: { $0.id == current }) { current = nil }
            others = []; noRoute = false; asking += 1
            waiting = from == nil ? .from : to == nil ? .to : nil
        }
        if !gone.isEmpty { save() }
        PinsMapState.shared.redrawRoutes()
        return gone
    }
    /// the pin's undo: its routes come back as they were
    func restore(_ back: [PinRoute]) {
        let have = Set(routes.map(\.id))
        routes += back.filter { !have.contains($0.id) }
        if !back.isEmpty { save(); PinsMapState.shared.redrawRoutes() }
    }
    /// a pin moved (or moved back): its routes are asked again from where it is now
    func pinMoved(_ pin: UUID) {
        for r in routes where r.from == pin || r.to == pin { reask(r.id, quiet: true) }
    }

    /// an end moved since its route was asked for (a pin dragged during the wait)
    static func moved(_ a: Place, _ b: Place) -> Bool { abs(a.lat - b.lat) > 1e-6 || abs(a.lon - b.lon) > 1e-6 }

    static func request(_ f: Place, _ t: Place, walk: Bool) -> MKDirections.Request {
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: f.lat, longitude: f.lon), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: t.lat, longitude: t.lon), address: nil)
        req.transportType = walk ? .walking : .automobile
        return req
    }

    /// a kept route asked again from its menu (Reverse, Walk, Drive): the same route, its line and numbers replaced,
    /// one undo; Apple finding no such way leaves it as it was and its capsule says so for 2 s
    func reask(_ id: UUID, reverse: Bool = false, walk: Bool? = nil, quiet: Bool = false) {
        guard let k = routes.firstIndex(where: { $0.id == id }) else { return }
        // from the newest way asked for (a Walk right after a Reverse walks the reversed route), else as it is now
        var r = asked[id]?.1 ?? routes[k]
        if reverse { swap(&r.from, &r.to) }
        // a straight route reversed, or an end of it moved, stays straight: its line drawn again between its ends, no
        // question to Apple
        if routes[k].straight == true, walk == nil {
            guard let f = end(r.from, r), let t = end(r.to, r) else { return }
            let was = routes[k].way
            routes[k].from = r.from; routes[k].to = r.to
            routes[k].points = [[f.lat, f.lon], [t.lat, t.lon]]
            routes[k].distance = CLLocation(latitude: f.lat, longitude: f.lon).distance(from: CLLocation(latitude: t.lat, longitude: t.lon))
            save()
            PinsMapState.shared.redrawRoutes()
            if !quiet { changed(id, was: was) }
            return
        }
        if let walk { r.walk = walk ? true : nil }
        guard let f = end(r.from, r), let t = end(r.to, r) else { return }
        askedCount += 1
        let me = askedCount
        asked[id] = (me, r)
        let req = Self.request(f, t, walk: r.walk == true)
        Task {
            let answer = try? await MKDirections(request: req).calculate()
            // only the newest question about this route is answered (an older answer is for a way no longer asked)
            guard asked[id]?.0 == me else { return }
            asked[id] = nil
            guard let j = routes.firstIndex(where: { $0.id == id }) else { return }
            guard let best = answer?.routes.first else {
                if !quiet { Feel.refuse() }
                note(id, r.walk == true ? "No walking route" : "No route")
                return
            }
            let was = routes[j].way
            var way = r.way
            way.points = Self.points(best.polyline); way.distance = best.distance; way.time = best.expectedTravelTime
            // only its way changes (a colour picked meanwhile stays); it goes by road or path from now on
            routes[j].way = way
            routes[j].straight = nil
            // the row making this route follows it (Apple's other ways were for the old ends)
            if current == id, open { from = way.from; to = way.to; others = [] }
            save()
            PinsMapState.shared.redrawRoutes()
            // a pin's move carries its own undo (which asks again); a menu row's change is one undo of its own
            guard !quiet else { return }
            changed(id, was: was)
        }
    }

    /// a route by road or path back to a straight line between its ends (one undo)
    func straighten(_ id: UUID) {
        guard let k = routes.firstIndex(where: { $0.id == id }), let f = end(routes[k].from, routes[k]), let t = end(routes[k].to, routes[k]) else { return }
        let was = routes[k].way
        routes[k].points = [[f.lat, f.lon], [t.lat, t.lon]]
        routes[k].distance = CLLocation(latitude: f.lat, longitude: f.lon).distance(from: CLLocation(latitude: t.lat, longitude: t.lon))
        routes[k].time = 0
        routes[k].walk = nil
        routes[k].straight = true
        save()
        PinsMapState.shared.redrawRoutes()
        changed(id, was: was)
    }

    /// THE ROUTE'S HOLD MENU (11.5), in the book's groups: Reverse · Walk · Drive · Colour | Directions in Apple Maps · Share |
    /// Delete. The way it goes now is shown but can't be chosen (never a tick). Not yet: Transit (Apple's directions
    /// give no transit lines to draw), lists and plans (with their parts).
    func menu(_ id: UUID) -> UIMenu? {
        guard let r = routes.first(where: { $0.id == id }), let f = end(r.from, r), let t = end(r.to, r) else { return nil }
        // each runs once the menu has gone (as every hold menu's rows)
        let after = { (g: @escaping @MainActor () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: g) }
        let walking = r.walk == true, straight = r.straight == true
        let reverse = UIAction(title: "Reverse") { [weak self] _ in after { self?.reask(id, reverse: true) } }
        let line = UIAction(title: "Straight", attributes: straight ? .disabled : []) { [weak self] _ in after { self?.straighten(id) } }
        let walk = UIAction(title: "Walk", attributes: walking && !straight ? .disabled : []) { [weak self] _ in after { self?.reask(id, walk: true) } }
        let drive = UIAction(title: "Drive", attributes: !walking && !straight ? .disabled : []) { [weak self] _ in after { self?.reask(id, walk: false) } }
        // Colour: the picker in the water at 50%, as a pin's, the line taking each colour as the finger moves (8.3)
        let colour = UIAction(title: "Colour") { [weak self] _ in
            after {
                PinStore.shared.selected = nil
                // (the Route row keeps the water at 25%: it goes first)
                self?.close()
                self?.colouring = id
                if let w = PinsMapState.shared.water, w.stop == .quarter || w.stop == .closed { w.go(.half) }
            }
        }
        let directions = UIAction(title: "Directions in Apple Maps") { [weak self] _ in self?.directions(id) }
        let share = UIAction(title: "Share") { [weak self] _ in after { self?.share(id) } }
        let delete = UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in after { Feel.lift(); self?.remove(id) } }
        return UIMenu(title: "\(f.title) to \(t.title)", children: [
            UIMenu(options: .displayInline, children: [reverse, line, walk, drive, colour]),
            UIMenu(options: .displayInline, children: [directions, share]),
            UIMenu(options: .displayInline, children: [delete]),
        ])
    }

    /// Directions in Apple Maps: Apple Maps from one end to the other, on foot or by car as the route goes
    func directions(_ id: UUID) {
        guard let r = routes.first(where: { $0.id == id }), let f = end(r.from, r), let t = end(r.to, r) else { return }
        let a = MKMapItem(location: CLLocation(latitude: f.lat, longitude: f.lon), address: nil); a.name = f.title
        let b = MKMapItem(location: CLLocation(latitude: t.lat, longitude: t.lon), address: nil); b.name = t.title
        MKMapItem.openMaps(with: [a, b], launchOptions: [MKLaunchOptionsDirectionsModeKey: r.walk == true ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving])
    }
    /// Share: Apple Maps' link to the same directions
    func share(_ id: UUID) {
        guard let r = routes.first(where: { $0.id == id }), let f = end(r.from, r), let t = end(r.to, r),
              let u = URL(string: "https://maps.apple.com/?saddr=\(f.lat),\(f.lon)&daddr=\(t.lat),\(t.lon)&dirflg=\(r.walk == true ? "w" : "d")") else { return }
        var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        while let next = top?.presentedViewController { top = next }
        top?.present(UIActivityViewController(activityItems: [u], applicationActivities: nil), animated: true)
    }

    static func points(_ l: MKPolyline) -> [[Double]] {
        var c = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: l.pointCount)
        l.getCoordinates(&c, range: NSRange(location: 0, length: l.pointCount))
        return c.map { [$0.latitude, $0.longitude] }
    }
}


/// A ROUTE'S OR A DRAWING'S COLOUR in the water at full (its hold menu's Colour, 8.3): its name and distance (a
/// drawing's length or area) where a pin's name sits, the colour picker under them, the line taking each colour live;
/// Reset to black once it has one. The water going below full puts it away (the colour is kept as it was last picked)
private extension String {
    var firstUp: String { prefix(1).uppercased() + dropFirst() }
}

struct RouteColourSheet: View {
    let water: Water
    let captionY: CGFloat
    @State private var r = PinRoutes.shared
    @State private var dr = PinDrawings.shared
    @State private var pick = PinSheet.nearBlack

    var body: some View {
        if let id = r.colouring, let route = r.routes.first(where: { $0.id == id }) {
            sheet(title: "\(r.end(route.from, route)?.title ?? "Pin") to \(r.end(route.to, route)?.title ?? "Pin")",
                  words: route.words, now: route.pick,
                  set: { c, keep in r.colour(id, c, keep: keep) }, kept: { r.keepColours() }, off: { r.colouring = nil })
        } else if let id = dr.colouring, let d = dr.drawing(id) {
            sheet(title: d.name.isEmpty ? (d.isShape ? "Shape" : "Line") : d.name, words: d.measure, now: d.pick,
                  set: { c, keep in dr.colour(id, c, keep: keep) }, kept: { dr.keepColours() }, off: { dr.colouring = nil })
        } else if r.colouring != nil || dr.colouring != nil {
            // its route or drawing gone: the water is the pins' again
            Color.clear.onAppear { r.colouring = nil; dr.colouring = nil }
        }
    }

    private func sheet(title: String, words: String, now: ColourPick?, set: @escaping (ColourPick?, Bool) -> Void,
                       kept: @escaping () -> Void, off: @escaping () -> Void) -> some View {
        let L = water.layout
        return VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                    // (a route's two places a little smaller rather than cut through a word)
                    .minimumScaleFactor(0.75).allowsTightening(true)
                Text(words).font(.subheadline).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            // ONE COLOUR PICKER (12 Nov): as a pin's, at 50%: the colour and its name, Reset and Done on one line, the
            // picker under it
            HStack(spacing: 16) {
                Circle().fill(now?.color ?? Palette.ink).frame(width: 28, height: 28)
                Text(now.map { ColourNames.name($0).firstUp } ?? "Black").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if now != nil {
                    Button {
                        // (the picker back where a black line starts, so a nudge never brings the old colour back)
                        Feel.tap(); set(nil, true); pick = PinSheet.nearBlack
                    } label: {
                        Text("Reset").font(.body).foregroundStyle(Palette.ink).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { Feel.tap(); off() } label: {
                    Text("Done").font(.body.weight(.semibold)).foregroundStyle(Palette.ink).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            ColourPicker(colour: Binding(get: { pick }, set: { c in pick = c; set(c, false) }),
                         suggested: nil, width: L.W - 2 * L.sheetInset - 32) { c in ColourStore.shared.add(c); kept() }
        }
        .padding(.horizontal, 16)
        .frame(width: L.W - 2 * L.sheetInset)
        // its name on the line a pin's name takes at full (about 42 pt over the caption's middle)
        .padding(.top, captionY - 58)
        .frame(width: L.W, height: L.H, alignment: .top)
        .onAppear { pick = now ?? PinSheet.nearBlack }
        .onDisappear { kept() }
        // pulled down below 50%, it goes back into the route's menu (as a pin's)
        .onChange(of: water.stop) { _, s in if s == .quarter || s == .closed { off() } }
    }
}

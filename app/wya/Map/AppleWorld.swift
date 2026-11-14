import SwiftUI
import MapKit
import simd

// THE MAP: APPLE (Map settings' first row: Apple's map instead of ours, on every map, the stamps still colouring the
// countries on it). Apple's map lies under the map instead of ours;
// your countries' colour is laid into it with no outline of ours (the old app's green outline stood out):
// the colour at 75% (60% on the photos) under Apple's names, so its names and its coasts show and every edge is
// Apple's. A tap on a country is a tap on ours. Pins keeps its
// own Apple map (Map/PinsMap.swift); the zoom column, Reset and full screen move whichever Apple map is up, through
// PinsMapState.

/// your countries in one colour: every piece of every one of them, as rings in Apple's map points
final class FillOverlay: NSObject, MKOverlay {
    let colour: UIColor
    /// each place's rings (its pieces, their holes, the enclaves in it), filled by the even-odd rule
    let places: [[[MKMapPoint]]]
    let boundingMapRect: MKMapRect
    /// even-odd (a country's enclaves are holes), or every ring filled (a set's shapes: a sea's parts can overlap, and
    /// even-odd would leave the overlap empty)
    let evenOdd: Bool
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate }
    init(colour: UIColor, places: [[[MKMapPoint]]], evenOdd: Bool = true) {
        self.colour = colour
        self.places = places
        self.evenOdd = evenOdd
        var r = MKMapRect.null
        for p in places { for ring in p { for q in ring { r = r.union(MKMapRect(origin: q, size: MKMapSize(width: 0, height: 0))) } } }
        boundingMapRect = r.isNull ? MKMapRect(x: 0, y: 0, width: 1, height: 1) : r
    }
}

final class FillRenderer: MKOverlayRenderer {
    private let fill: FillOverlay
    /// each place's path in this renderer's points, and its box in map points (made once)
    private let paths: [(path: CGPath, box: MKMapRect)]
    /// satellite or hybrid: screened onto the photos (multiplied there, a colour all but vanished)
    let photo: Bool
    init(_ o: FillOverlay, photo: Bool) {
        fill = o
        self.photo = photo
        let origin = o.boundingMapRect.origin
        paths = o.places.map { rings in
            let p = CGMutablePath()
            var box = MKMapRect.null
            for ring in rings where ring.count > 2 {
                p.addLines(between: ring.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) })
                p.closeSubpath()
                for q in ring { box = box.union(MKMapRect(origin: q, size: MKMapSize(width: 0, height: 0))) }
            }
            return (p, box)
        }
        super.init(overlay: o)
    }
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        // (the colour itself at 75%, not
        // multiplied into Apple's green land, where it all but vanished; 60% on the photos. Apple's names stay over it)
        ctx.setBlendMode(.normal)
        ctx.setFillColor(fill.colour.withAlphaComponent(photo ? 0.6 : 0.75).cgColor)
        for (path, box) in paths where box.intersects(mapRect) {
            ctx.addPath(path)
            ctx.fillPath(using: fill.evenOdd ? .evenOdd : .winding)
        }
    }
}

/// THE JOURNEY'S START AND END CAPSULES ON APPLE'S MAP (Part 13, as on ours; 12 Nov: the two histories the same): the
/// start's from the first moment, the end's once the line has arrived; kept in the room between the head and the water,
/// left of the zoom column, and away while their stop is off the screen
@MainActor
final class JourneyCaps {
    private let start = HistoryCapsule(), end = HistoryCapsule()
    private weak var host: MKMapView?
    /// `line`: the journey's points in order (Apple's map points); `words`: the start's and the end's
    func update(_ v: MKMapView, line: [MKMapPoint], words: (String, String), progress: Double, L: Layout, sheetTop: CGFloat) {
        if host !== v { host = v; v.addSubview(start); v.addSubview(end) }
        guard line.count > 1 else { hide(); return }
        let pt = { (m: MKMapPoint) in v.convert(m.coordinate, toPointTo: v) }
        let rr = L.room(sheetTop: sheetTop)
        let room = CGRect(x: 0, y: rr.lowerBound, width: v.bounds.width - L.side - 44, height: rr.upperBound - rr.lowerBound)
        let seen = room.insetBy(dx: -24, dy: -24)
        let p0 = pt(line[0]), p1 = pt(line[1]), pn = pt(line[line.count - 1]), pm = pt(line[line.count - 2])
        start.set(words.0, near: p0, awayFrom: p1, in: room, visible: progress > 0.001 && seen.contains(p0))
        end.set(words.1, near: pn, awayFrom: pm, in: room, visible: progress > 0.999 && seen.contains(pn))
    }
    func hide() { start.hide(); end.hide() }
}

/// the lines between a country's regions (its region map on Apple's map): Apple draws a country's own edge, not these
final class BorderOverlay: NSObject, MKOverlay {
    /// each line's two ends, in Apple's map points
    let lines: [(MKMapPoint, MKMapPoint)]
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate }
    init(lines: [(MKMapPoint, MKMapPoint)]) {
        self.lines = lines
        var r = MKMapRect.null
        for (a, b) in lines { r = r.union(MKMapRect(origin: a, size: MKMapSize(width: 0, height: 0))).union(MKMapRect(origin: b, size: MKMapSize(width: 0, height: 0))) }
        boundingMapRect = r.isNull ? MKMapRect(x: 0, y: 0, width: 1, height: 1) : r
    }
}

final class BorderRenderer: MKOverlayRenderer {
    private let path: CGPath
    init(_ o: BorderOverlay) {
        let origin = o.boundingMapRect.origin
        let p = CGMutablePath()
        for (a, b) in o.lines {
            p.move(to: CGPoint(x: a.x - origin.x, y: a.y - origin.y))
            p.addLine(to: CGPoint(x: b.x - origin.x, y: b.y - origin.y))
        }
        path = p
        super.init(overlay: o)
    }
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        // one point wide on the screen at every zoom, 50% black as our region lines
        ctx.setLineWidth(1 / zoomScale)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(UIColor(Palette.ink).withAlphaComponent(0.5).cgColor)
        ctx.addPath(path)
        ctx.strokePath()
    }
}

struct AppleWorldView: UIViewRepresentable {
    let map: MapController
    let water: Water

    func makeCoordinator() -> Coordinator { Coordinator(map: map) }

    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView()
        // where our map was looking, through our own camera (before Apple's projection is hooked in below)
        map.apple = nil
        v.setRegion(PinsMapState.region(from: map), animated: false)
        context.coordinator.placed = map.ready
        map.appleOwner = ObjectIdentifier(context.coordinator)
        // the journey (history on) drawn along on Apple's map, frame by frame with ours; the Places names and marks too
        map.onFrame = { [weak v, weak c = context.coordinator] in if let v, let c { c.journey(v); c.names(v) } }
        // our map's points on Apple's screen and back, through Apple's projection
        map.apple = (toScreen: { [weak v] m in
            guard let v else { return .zero }
            let ll = EqualEarth.unproject(m)
            return v.convert(CLLocationCoordinate2D(latitude: max(-85, min(85, ll.lat)), longitude: ll.lon), toPointTo: v)
        }, toMap: { [weak v] s in
            guard let v else { return .zero }
            let c = v.convert(s, toCoordinateFrom: v)
            let q = EqualEarth.project(lon: c.longitude, lat: c.latitude)
            return SIMD2(Double(q.x), Double(q.y))
        })
        // the Places names and marks, over Apple's map (they take no touch)
        let names = TownNamesView(frame: v.bounds)
        names.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        names.marksHere = true
        v.addSubview(names)
        context.coordinator.namesView = names
        v.delegate = context.coordinator
        v.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        v.showsCompass = false
        v.showsScale = false
        v.showsUserLocation = false
        v.isPitchEnabled = false
        v.isRotateEnabled = false
        // (the margins set below are the whole inset, never the home bar's safe area added under them)
        v.insetsLayoutMarginsFromSafeArea = false
        // the finger's first contact: the app's map touch (search, settings, the book put away), as on ours
        let down = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.down(_:)))
        down.minimumPressDuration = 0
        down.cancelsTouchesInView = false
        down.delaysTouchesBegan = false
        down.delaysTouchesEnded = false
        down.delegate = context.coordinator
        v.addGestureRecognizer(down)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        // a double tap is Apple's zoom, never a tap on a country first
        DispatchQueue.main.async {
            for d in PinsMapView.taps(in: v) where d !== tap && d.numberOfTapsRequired == 2 { tap.require(toFail: d) }
        }
        PinsMapState.shared.view = v
        PinsMapState.shared.water = water
        PinsMapState.shared.map = map
        // unseen until its first picture is whole (never empty squares while its tiles come in), three seconds at most
        v.alpha = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak v] in v?.alpha = 1 }
        DispatchQueue.main.async { PinsMapState.shared.limits() }
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) {
        let c = context.coordinator
        // (made before our map's camera was there, at a launch: it takes our map's view once it is)
        if !c.placed, map.ready {
            c.placed = true
            let a = map.apple
            map.apple = nil
            v.setRegion(PinsMapState.region(from: map), animated: false)
            map.apple = a
        }
        // Style's Apple looks (Standard, Satellite, Hybrid)
        let look = MapSettingsStore.shared.value.style
        if c.look != look {
            c.look = look
            switch look {
            case "satellite": v.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
            case "hybrid": v.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
            default: v.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            }
            c.fillsKey = ""
        }
        // (Places: no stamps on its map, borders only, as on ours; the country opened framed on Apple's map)
        if map.placesMode {
            c.leaveRegions(v)
            c.setShapes(v)
            c.placeOpened(map.placeOpen)
        } else if let sc = map.regionScene {
            c.regions(v, sc, stamped: map.showsStamped ? map.regionStamped : [],
                      wished: map.showsWished ? map.regionWished.subtracting(map.regionStamped) : [])
        } else {
            c.leaveRegions(v)
            c.fills(v, stamped: map.showsStamped ? map.stamped : [], wished: map.showsWished ? map.wished.subtracting(map.stamped) : [])
        }
        // Apple's credit (Legal) just above the water, as in Pins
        let L = water.layout
        let edge = max(water.form().top, water.y(.half))
        let margins = UIEdgeInsets(top: L.headBottom, left: L.sheetInset + 8, bottom: max(0, L.H - edge), right: L.sheetInset)
        if v.layoutMargins != margins { v.layoutMargins = margins }
    }

    static func dismantleUIView(_ v: MKMapView, coordinator: Coordinator) {
        // (only this view's own: a view taken down after its replacement was made leaves the new one's alone)
        if coordinator.map.appleOwner == ObjectIdentifier(coordinator) {
            coordinator.map.onFrame = nil
            coordinator.map.apple = nil
            coordinator.map.appleOwner = nil
        }
        // (Pins' own map may already have taken its place)
        if PinsMapState.shared.view === v { PinsMapState.shared.view = nil }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let map: MapController
        var look = ""
        var fillsKey = ""
        private var overlays: [FillOverlay] = []
        /// each place's rings in Apple's map points, worked out once
        private var rings: [Int: [[MKMapPoint]]] = [:]
        init(map: MapController) {
            self.map = map
            // (a country already open when Apple's map comes (close up, 14 Nov) is where the camera already is: framing it
            // again flew back out to the whole country, and ours came back)
            opened = map.placeOpen
            super.init()
            Self.current = self
        }
        /// Apple's map has taken our map's view
        var placed = false
        /// the Places names and marks laid over Apple's map (Map/TownNames.swift)
        weak var namesView: TownNamesView?
        func names(_ v: MKMapView) {
            // (a set's shapes come in off the main thread and are no state SwiftUI watches: looked at each frame)
            if map.placesMode { setShapes(v) }
            guard let n = namesView else { return }
            // (Apple's map adds its own layers as its tiles come: the names stay on top of them)
            if v.subviews.last !== n { v.bringSubviewToFront(n) }
            n.update(map, moving: moving)
        }
        /// Places: a country opened is framed on Apple's map (ours flies to it, under)
        private var opened: Int?
        func placeOpened(_ i: Int?) {
            guard i != opened else { return }
            opened = i
            if let i { PinsMapState.shared.show(place: i, world: map.world) }
        }
        /// our camera kept where Apple's is
        func follow(_ v: MKMapView) {
            guard v.bounds.width > 0 else { return }
            let mid = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
            let a = map.mapPoint(CGPoint(x: mid.x - 50, y: mid.y)), b = map.mapPoint(CGPoint(x: mid.x + 50, y: mid.y))
            let d = simd_length(b - a)
            guard d > 0 else { return }
            map.followApple(centre: map.mapPoint(mid), k: 100 / d)
        }
        /// the one on screen (the test driver's `appletap`)
        static weak var current: Coordinator?

        // A REGION MAP ON APPLE'S MAP: the country framed, its regions' lines over Apple's map, yours laid in as countries are
        private weak var scene: RegionScene?
        private var borders: BorderOverlay?
        func regions(_ v: MKMapView, _ sc: RegionScene, stamped: Set<Int>, wished: Set<Int>) {
            if scene !== sc {
                scene = sc
                if let b = borders { v.removeOverlay(b) }
                var lines: [(MKMapPoint, MKMapPoint)] = []
                lines.reserveCapacity(sc.segs.count / 10)
                var k = 0
                while k + 3 < sc.segs.count {
                    lines.append((Self.apple(SIMD2(sc.segs[k], sc.segs[k + 1])), Self.apple(SIMD2(sc.segs[k + 2], sc.segs[k + 3]))))
                    k += 10
                }
                let b = BorderOverlay(lines: lines)
                borders = b
                v.addOverlay(b, level: .aboveLabels)
                fillsKey = ""
                // the country framed between the head and the water (its main land)
                PinsMapState.shared.show(place: sc.place, world: map.world)
            }
            let key = "r\(sc.id)|\(sc.row)|" + stamped.sorted().map(String.init).joined(separator: ",") + "|"
                + wished.sorted().map(String.init).joined(separator: ",") + "|" + look
            guard key != fillsKey else { return }
            fillsKey = key
            let old = overlays
            overlays = [(stamped, Palette.lime), (wished, Palette.blue)].compactMap { set, colour in
                let ps = set.sorted().map { u in sc.unitRings(u).map { $0.map(Self.apple) } }.filter { !$0.isEmpty }
                return ps.isEmpty ? nil : FillOverlay(colour: UIColor(colour), places: ps)
            }
            v.addOverlays(overlays, level: .aboveRoads)
            v.removeOverlays(old)
        }
        /// back on the world: the region map's lines go
        func leaveRegions(_ v: MKMapView) {
            guard scene != nil || borders != nil else { return }
            scene = nil
            if let b = borders { v.removeOverlay(b) }
            borders = nil
            fillsKey = ""
        }
        // HISTORY ON APPLE'S MAP (Part 13): the journey of the map it was asked on (our map's track), one black line
        // through its stops in order, 2.5 pt, drawn along as ours is; the whole journey framed when it comes
        private var journeyLine: MKPolyline?
        private var journeyKey = ""
        private var journeyPoints: [MKMapPoint] = []
        /// how far along the line each stop is (0 to 1)
        private var journeyAt: [Double] = []
        /// the journey being played: the camera's middle and width followed (Apple's map points)
        private var follow: (centre: MKMapPoint, width: Double)?
        private var journeyRect = MKMapRect.null
        private let caps = JourneyCaps()
        func journey(_ v: MKMapView) {
            let t = map.historyTrack
            let key = t.map { t in "\(t.stops.count)|" + t.stops.map { "\($0.at.x),\($0.at.y)" }.joined(separator: ";") } ?? ""
            if key != journeyKey {
                journeyKey = key
                if let old = journeyLine { v.removeOverlay(old) }
                journeyLine = nil
                if let t, t.stops.count > 1 {
                    // (a leg over 180 degrees goes the short way, across the date line, as in Pins)
                    let W = MKMapSize.world.width
                    var pts: [MKMapPoint] = []
                    for s in t.stops {
                        var m = Self.apple(SIMD2(Float(s.at.x), Float(s.at.y)))
                        if let last = pts.last {
                            while m.x - last.x > W / 2 { m.x -= W }
                            while last.x - m.x > W / 2 { m.x += W }
                        }
                        pts.append(m)
                    }
                    let l = MKPolyline(points: pts, count: pts.count)
                    journeyLine = l
                    journeyPoints = pts
                    v.addOverlay(l, level: .aboveLabels)
                    // (wider than Apple's flat map goes out, about a third of the world across: framed where most of the
                    // stops are, their middle one across, never the empty middle of the span, as on ours)
                    var r = l.boundingMapRect
                    let most = MKMapSize.world.width / 3
                    if r.width > most {
                        let mid = pts.map(\.x).sorted()[pts.count / 2]
                        r = MKMapRect(x: mid - most / 2, y: r.minY, width: most, height: r.height)
                    }
                    journeyRect = r
                    var at: [Double] = [0], total = 0.0
                    for k in 1 ..< pts.count { total += hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y); at.append(total) }
                    journeyAt = total > 0 ? at.map { $0 / total } : at
                    // played (as ours): followed from where the map is; else framed whole at once
                    if map.historyLeg != nil {
                        let seen = v.visibleMapRect
                        follow = (MKMapPoint(x: seen.midX, y: seen.midY), seen.width)
                    } else { frameJourney(v) }
                } else { journeyPoints = []; follow = nil }
            }
            // THE PLAY FOLLOWED: the line's end, the camera easing after it, wide enough for the leg it is on
            if let (j, e) = map.historyLeg, var f = follow, j + 1 < journeyPoints.count, let l = journeyLine {
                let a = journeyPoints[j], b = journeyPoints[j + 1]
                let tip = MKMapPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
                let leg = max(abs(b.x - a.x), abs(b.y - a.y) * Double(v.bounds.width / max(1, v.bounds.height)))
                let want = max(leg * 1.8, MKMapPointsPerMeterAtLatitude(tip.coordinate.latitude) * 60_000)
                f.centre = MKMapPoint(x: f.centre.x + (tip.x - f.centre.x) * 0.12, y: f.centre.y + (tip.y - f.centre.y) * 0.12)
                f.width += (want - f.width) * 0.08
                follow = f
                let h = f.width * Double(v.bounds.height / max(1, v.bounds.width))
                v.setVisibleMapRect(MKMapRect(x: f.centre.x - f.width / 2, y: f.centre.y - h / 2, width: f.width, height: h),
                                    edgePadding: UIEdgeInsets(top: 46, left: 32, bottom: 32, right: 60), animated: false)
                if let r = v.renderer(for: l) as? JourneyRenderer {
                    r.progress = journeyAt[j] + (journeyAt[j + 1] - journeyAt[j]) * e
                    r.setNeedsDisplay()
                }
                caps.update(v, line: journeyPoints, words: words(), progress: drawn(v, l), L: layoutNow(), sheetTop: sheetNow())
                return
            }
            // the play over: the whole journey framed
            if follow != nil, map.historyLeg == nil { follow = nil; frameJourney(v) }
            if let t, journeyLine != nil, let a = t.stops.first, let b = t.stops.last, let water = PinsMapState.shared.water {
                caps.update(v, line: journeyPoints, words: (HistoryLineView.words(a), HistoryLineView.words(b)),
                            progress: Double(map.historyShown), L: water.layout, sheetTop: water.form().top)
            } else { caps.hide() }
            if let l = journeyLine, let r = v.renderer(for: l) as? JourneyRenderer, abs(r.progress - Double(map.historyShown)) > 0.001 {
                r.progress = Double(map.historyShown)
                r.setNeedsDisplay()
            }
        }

        private func frameJourney(_ v: MKMapView) {
            guard !journeyRect.isNull else { return }
            v.setVisibleMapRect(journeyRect, edgePadding: UIEdgeInsets(top: 46, left: 32, bottom: 32, right: 60), animated: true)
        }
        private func words() -> (String, String) {
            guard let t = map.historyTrack, let a = t.stops.first, let b = t.stops.last else { return ("", "") }
            return (HistoryLineView.words(a), HistoryLineView.words(b))
        }
        private func drawn(_ v: MKMapView, _ l: MKPolyline) -> Double { (v.renderer(for: l) as? JourneyRenderer)?.progress ?? 1 }
        private func layoutNow() -> Layout { PinsMapState.shared.water?.layout ?? map.layout }
        private func sheetNow() -> CGFloat { PinsMapState.shared.water?.form().top ?? map.layout.top(.quarter) }

        /// a point of our map in Apple's map points
        static func apple(_ q: SIMD2<Float>) -> MKMapPoint {
            let ll = EqualEarth.unproject(SIMD2(Double(q.x), Double(q.y)))
            return MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, ll.lat)), longitude: ll.lon))
        }

        /// PLACES: a set's places that are yours as their shapes (a sea, a range, a park, an island), lime or blue, as on
        /// ours; the others are Apple's own map with their names over it (a park is already Apple's green)
        func setShapes(_ v: MKMapView) {
            guard let sc = map.setScene else { townShapes(v); return }
            let mk = map.setMarks(sc)
            let st = map.showsStamped ? mk.stamped.sorted() : [], wi = map.showsWished ? mk.wished.sorted() : []
            let key = "s\(sc.id)|" + st.joined(separator: ",") + "|" + wi.joined(separator: ",") + "|" + look
            guard key != fillsKey else { return }
            fillsKey = key
            let old = overlays
            overlays = [(st, Palette.lime), (wi, Palette.blue)].compactMap { ids, colour in
                let ps = ids.map { sc.shapeRings($0).map { $0.map(Self.apple) } }.filter { !$0.isEmpty }
                return ps.isEmpty ? nil : FillOverlay(colour: UIColor(colour), places: ps, evenOdd: false)
            }
            v.addOverlays(overlays, level: .aboveRoads)
            v.removeOverlays(old)
        }

        /// PLACES' TOWNS: the towns of the countries in play that are yours, their built-up shapes lime or blue, as on
        /// ours (Apple's map draws and names every town itself)
        private func townShapes(_ v: MKMapView) {
            let ccs = map.townCountries.filter { map.townScenes[$0] != nil }
            let pick = { (sets: [String: Set<Int>]) in ccs.flatMap { cc in (sets[cc] ?? []).sorted().map { (cc, $0) } } }
            let st = map.showsStamped ? pick(map.townStamped) : [], wi = map.showsWished ? pick(map.townWished) : []
            let key = "t|" + st.map { "\($0.0)\($0.1)" }.joined(separator: ",") + "|" + wi.map { "\($0.0)\($0.1)" }.joined(separator: ",") + "|" + look
            guard key != fillsKey else { return }
            fillsKey = key
            let old = overlays
            overlays = [(st, Palette.lime), (wi, Palette.blue)].compactMap { towns, colour in
                let ps = towns.compactMap { cc, i in map.townScenes[cc]?.townRings(i).map { $0.map(Self.apple) } }.filter { !$0.isEmpty }
                return ps.isEmpty ? nil : FillOverlay(colour: UIColor(colour), places: ps)
            }
            v.addOverlays(overlays, level: .aboveRoads)
            v.removeOverlays(old)
        }

        func fills(_ v: MKMapView, stamped: Set<Int>, wished: Set<Int>) {
            let key = stamped.sorted().map(String.init).joined(separator: ",") + "|" + wished.sorted().map(String.init).joined(separator: ",") + "|" + look
            guard key != fillsKey, let w = map.world else { return }
            fillsKey = key
            let old = overlays
            overlays = [(stamped, Palette.lime), (wished, Palette.blue)].compactMap { set, colour in
                let ps = set.sorted().map { shape(of: $0, in: w) }.filter { !$0.isEmpty }
                return ps.isEmpty ? nil : FillOverlay(colour: UIColor(colour), places: ps)
            }
            v.addOverlays(overlays, level: .aboveRoads)
            v.removeOverlays(old)
        }

        /// a place's rings from our map's outlines (its units in the borders view the world was loaded in), back to
        /// longitude and latitude
        private func shape(of i: Int, in w: World) -> [[MKMapPoint]] {
            if let r = rings[i] { return r }
            var out: [[MKMapPoint]] = []
            for u in w.unitOwner.indices where w.unitOwner[u] == i && u < w.unitRings.count {
                for ri in w.unitRings[u] {
                    let r = w.rings[ri]
                    var ring: [MKMapPoint] = []
                    ring.reserveCapacity(r.count)
                    for k in r.start ..< r.start + r.count {
                        let q = w.points[k]
                        let ll = EqualEarth.unproject(SIMD2(Double(q.x), Double(q.y)))
                        ring.append(MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, ll.lat)), longitude: ll.lon)))
                    }
                    out.append(ring)
                }
            }
            rings[i] = out
            return out
        }

        private var closedThisTouch = false
        private var moving = false
        @objc func down(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            // (a touch ends the journey's play there, the whole journey framed)
            if map.historyLeg != nil { map.endHistoryPlay() }
            let before = map.touchClosedAt
            map.onTouch?()
            closedThisTouch = map.touchClosedAt != before
        }
        /// a tap on a country: the country under it, pressed as on ours (its card); at sea, a tap off every country
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view as? MKMapView else { return }
            if WhatsHere.shared.isOpen { WhatsHere.shared.close(); return }
            if closedThisTouch || moving { return }
            tap(at: g.location(in: v), in: v)
        }
        /// (the test driver's `appletap x y` comes here too)
        /// a tap as on ours (MapMTKView's touch): what our map's own press finds there (a country, a region, a town, a
        /// thing, one of your places; its points through Apple's projection), a name's page first
        func tap(at p: CGPoint, in v: MKMapView) {
            if map.locked { Feel.refuse(); map.lockedPress(); map.dropSetPress(); return }
            let hit = map.hit(at: p)
            map.pressed = hit
            defer { map.pressed = nil }
            if let name = namesView?.nameHit(p) {
                guard map.namePageAllowed?() ?? true else { return }
                if namesView?.openPage(name, map) == true { return }
            }
            if let hit { map.onPlaceTap?(hit, p) } else { map.onSeaTap?() }
        }

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
        func mapView(_ v: MKMapView, regionWillChangeAnimated animated: Bool) { moving = true }
        func mapView(_ v: MKMapView, regionDidChangeAnimated animated: Bool) { moving = false; follow(v); PinsMapState.shared.limits(); map.appleSettled() }
        func mapViewDidChangeVisibleRegion(_ v: MKMapView) { follow(v) }
        func mapViewDidFinishRenderingMap(_ v: MKMapView, fullyRendered: Bool) { if fullyRendered, v.alpha < 1 { v.alpha = 1 } }
        func mapView(_ v: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            if let f = o as? FillOverlay { return FillRenderer(f, photo: look == "satellite" || look == "hybrid") }
            if let b = o as? BorderOverlay { return BorderRenderer(b) }
            if let l = o as? MKPolyline {
                let r = JourneyRenderer(l)
                r.progress = Double(map.historyShown)
                return r
            }
            return MKOverlayRenderer(overlay: o)
        }
    }
}

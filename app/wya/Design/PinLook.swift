import SwiftUI
import MapKit

// HOW PINS, ROUTES AND DRAWINGS LOOK (Part 8.3), drawn once here and used by Pins and by the review sheet that comes
// before anything else in Pins is built (8.3: "Shown ... on a review sheet ... before anything else in Pins").

/// THE PIN: the classic map marker, a round head tapering to a point, the point exactly on the spot (3 Oct: "why is it
/// a pin inside of a circle? It should just be a pin"). 30 pt tall, the head 24 pt across, in a 24 x 30 box whose
/// bottom centre is the spot.
struct PinShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, rad = w / 2
        let c = CGPoint(x: r.midX, y: r.minY + rad), tip = CGPoint(x: r.midX, y: r.maxY)
        // the two lines from the tip touch the head's circle: the angle of the touch points from the centre
        let d = tip.y - c.y
        let a = asin(min(1, rad / d))
        let touch = Double.pi / 2 - a
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: c.x + rad * cos(touch), y: c.y + rad * sin(touch)))
        p.addArc(center: c, radius: rad, startAngle: .radians(touch), endAngle: .radians(.pi - touch), clockwise: true)
        p.closeSubpath()
        _ = h
        return p
    }
}

/// a colour's own lighter top and deeper bottom (lit by the one light like every object; no outline, no shadow)
enum PinLight {
    /// (a palette colour is sRGB; a colour from the picker is Display P3)
    static func mix(_ c: SIMD3<Double>, _ to: SIMD3<Double>, _ t: Double, p3: Bool = false) -> Color {
        let v = c + (to - c) * t
        return Color(p3 ? .displayP3 : .sRGB, red: v.x, green: v.y, blue: v.z)
    }
    static func top(_ c: SIMD3<Double>, p3: Bool = false) -> Color { mix(c, SIMD3(1, 1, 1), 0.14, p3: p3) }
    static func bottom(_ c: SIMD3<Double>, p3: Bool = false) -> Color { mix(c, SIMD3(0, 0, 0), 0.12, p3: p3) }
    static func v3(_ v: SIMD4<Float>) -> SIMD3<Double> { SIMD3(Double(v.x), Double(v.y), Double(v.z)) }
    /// white or ink, whichever reads on this colour (relative luminance against the two)
    static func onInk(_ c: SIMD3<Double>) -> Bool {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let L = 0.2126 * lin(c.x) + 0.7152 * lin(c.y) + 0.0722 * lin(c.z)
        return (L + 0.05) / 0.05 > 1.05 / (L + 0.05)
    }
}

/// THE DEFAULT PIN SEQUENCE (15.7, Q15.3): a new pin takes the next of these (the order the author's call, from the
/// palette); a pin you colour keeps yours
enum PinSequence {
    static let colours: [(String, SIMD3<Double>)] = [("red", Palette.redV), ("blue", Palette.blueV), ("yellow", Palette.yellowV),
                                                     ("lime", Palette.limeV), ("teal", Palette.tealV), ("brown", Palette.brownV),
                                                     ("ink", Palette.inkV)].map { ($0.0, PinLight.v3($0.1)) }
}

struct PinMarker: View {
    /// gamma-encoded P3 (or sRGB palette) colour
    let colour: SIMD3<Double>
    /// the colour is Display P3 (from the picker), not a palette sRGB one
    var p3 = false
    var icon: String? = nil
    var name: String? = nil
    var selected = false
    var tracked = false
    /// stepped back behind a nearer pin of a stack
    var behind = false

    var body: some View {
        let h: CGFloat = tracked ? 18 : 30, w: CGFloat = tracked ? 14.4 : 24
        let c = tracked ? PinLight.v3(Palette.blueV) : colour
        let wide = p3 && !tracked
        VStack(spacing: 2) {
            ZStack {
                PinShape()
                    .fill(LinearGradient(colors: [PinLight.top(c, p3: wide), PinLight.bottom(c, p3: wide)], startPoint: .top, endPoint: .bottom))
                if let icon, !tracked {
                    Icon5(key: icon, ink: PinLight.onInk(c) ? Palette.ink : .white, size: 13)
                        .frame(width: w, height: w)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: w, height: h)
            // selected: 1.2x about its tip and lifted 4 pt (A8.4); behind a stack: 0.8x and 4 pt lower
            .scaleEffect(selected ? 1.2 : behind ? 0.8 : 1, anchor: .bottom)
            .offset(y: selected ? -4 : behind ? 4 : 0)
            if let name, !behind {
                HaloText(name)
            }
        }
    }
}

/// map words: 12 pt semibold ink with a 2 pt cream halo (the halo only for words on the map, 7.4, 8.3)
struct HaloText: View {
    let s: String
    init(_ s: String) { self.s = s }
    var body: some View {
        ZStack {
            ForEach(0 ..< 8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.cream)
                    .offset(x: 2 * cos(a), y: 2 * sin(a))
            }
            Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
        }
        .fixedSize()
    }
}

/// a route's line: 3 pt black (or your colour), round ends and joins, no casing; the options behind 2 pt black 50%
struct RouteLine: View {
    let points: [CGPoint]
    var colour: Color = Palette.ink
    var other = false
    var body: some View {
        Path { p in
            guard let f = points.first else { return }
            p.move(to: f)
            for q in points.dropFirst() { p.addLine(to: q) }
        }
        .stroke(other ? Palette.ink.opacity(0.5) : colour,
                style: StrokeStyle(lineWidth: other ? 2 : 3, lineCap: .round, lineJoin: .round))
    }
}

/// the distance and time, or a size, in a 13 pt glass capsule
struct MapCapsule: View {
    let s: String
    var body: some View {
        Text(s).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
            .padding(.horizontal, 10).frame(height: 26)
            .glassEffect(.regular, in: .capsule)
            .fixedSize()
    }
}

/// a drawn line smoothed as drawn (Catmull-Rom through the points)
func catmullRom(_ pts: [CGPoint]) -> Path {
    var p = Path()
    guard pts.count > 1 else { return p }
    p.move(to: pts[0])
    for i in 0 ..< pts.count - 1 {
        let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        p.addCurve(to: p2, control1: c1, control2: c2)
    }
    return p
}

#if DEBUG
/// THE PINS REVIEW (8.3, before Pins is built): the pins, routes and drawings drawn by the code above over what is
/// behind them: our live map (at the zoom the driver set), or Apple's Standard or Satellite map of the same place (a
/// MapKit snapshot). The driver's `pinreview <map|apple|satellite|off> [scene]` puts it up; a snapshot records it.
@MainActor
@Observable
final class PinReview {
    static let shared = PinReview()
    var on = false
    /// "map" (our map behind, live), "apple", "satellite"
    var ground = "map"
    /// "spread", "stacked", "lines"
    var scene = "spread"
    var apple: UIImage?
    /// the place the Apple snapshots show
    var centre = CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417)
    var span = 0.06

    func snapshot(size: CGSize) {
        apple = nil
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: centre, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span * size.width / size.height))
        o.size = size
        o.preferredConfiguration = ground == "satellite" ? MKImageryMapConfiguration() : MKStandardMapConfiguration()
        MKMapSnapshotter(options: o).start { [weak self] s, _ in
            Task { @MainActor in self?.apple = s?.image }
        }
    }
}

struct PinReviewHost: View {
    let L: Layout
    @State private var r = PinReview.shared
    var body: some View {
        if r.on {
            ZStack(alignment: .topLeading) {
                if r.ground != "map" {
                    if let a = r.apple { Image(uiImage: a).resizable().frame(width: L.W, height: L.H) } else { Palette.cream }
                }
                scene
            }
            .frame(width: L.W, height: L.H)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private var scene: some View {
        let W = L.W
        let seq = PinSequence.colours
        switch r.scene {
        case "stacked":
            // three stacks: the back ones step back, no names while stacked, no number bubbles
            ForEach(0 ..< 3, id: \.self) { k in
                let x = W * (0.25 + 0.25 * CGFloat(k)), y: CGFloat = 330
                ForEach((0 ..< 3).reversed(), id: \.self) { j in
                    PinMarker(colour: seq[(k * 3 + j) % seq.count].1, behind: j > 0)
                        .position(x: x + CGFloat(j) * 7, y: y - CGFloat(j) * 3 - 15)
                }
            }
            // a selected pin and a tracked one
            PinMarker(colour: seq[1].1, name: "Selected", selected: true).position(x: W * 0.3, y: 470)
            PinMarker(colour: seq[0].1, tracked: true).position(x: W * 0.55, y: 470)
            PinMarker(colour: seq[0].1, tracked: true).position(x: W * 0.62, y: 485)
            PinMarker(colour: seq[0].1, tracked: true).position(x: W * 0.7, y: 465)
            PinMarker(colour: seq[3].1, name: "Not selected").position(x: W * 0.8, y: 560)
        case "lines":
            // a route (3 pt black) with an option behind (2 pt black 50%), its two pins the ends, the capsule on its middle
            let a = CGPoint(x: W * 0.18, y: 250), b = CGPoint(x: W * 0.8, y: 420)
            let route = [a, CGPoint(x: W * 0.3, y: 270), CGPoint(x: W * 0.42, y: 320), CGPoint(x: W * 0.58, y: 330),
                         CGPoint(x: W * 0.66, y: 380), b]
            let other = [a, CGPoint(x: W * 0.22, y: 330), CGPoint(x: W * 0.45, y: 400), CGPoint(x: W * 0.7, y: 440), b]
            RouteLine(points: other, other: true)
            RouteLine(points: route)
            MapCapsule(s: "4.2 km · 12 min").position(x: W * 0.5, y: 322)
            PinMarker(colour: seq[0].1, name: "Home").position(x: a.x, y: a.y - 15 + 8)
            PinMarker(colour: seq[1].1, name: "Office").position(x: b.x, y: b.y - 15 + 8)
            // a drawn line (3 pt, smoothed) and an area (filled in its colour multiplied into the land, no edge), the size
            // in a capsule; a measure (2 pt ink, the distance on its middle)
            catmullRom([CGPoint(x: W * 0.1, y: 520), CGPoint(x: W * 0.25, y: 500), CGPoint(x: W * 0.35, y: 560),
                        CGPoint(x: W * 0.5, y: 540), CGPoint(x: W * 0.6, y: 590)])
                .stroke(PinLight.mix(seq[4].1, seq[4].1, 0), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            let area = catmullRom([CGPoint(x: W * 0.62, y: 500), CGPoint(x: W * 0.85, y: 490), CGPoint(x: W * 0.9, y: 580),
                                   CGPoint(x: W * 0.7, y: 610), CGPoint(x: W * 0.6, y: 560), CGPoint(x: W * 0.62, y: 500)])
            area.fill(PinLight.mix(seq[2].1, seq[2].1, 0)).blendMode(.multiply)
            MapCapsule(s: "3.1 km²").position(x: W * 0.75, y: 550)
            Path { p in p.move(to: CGPoint(x: W * 0.15, y: 660)); p.addLine(to: CGPoint(x: W * 0.55, y: 640)) }
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            MapCapsule(s: "1.8 km").position(x: W * 0.35, y: 650)
        default:
            // every colour of the sequence, spread, with names
            ForEach(Array(seq.enumerated()), id: \.offset) { i, c in
                let col = i % 4, row = i / 4
                PinMarker(colour: c.1, name: c.0.prefix(1).uppercased() + c.0.dropFirst())
                    .position(x: W * (0.16 + 0.22 * CGFloat(col)), y: 280 + CGFloat(row) * 110)
            }
        }
    }
}
#endif

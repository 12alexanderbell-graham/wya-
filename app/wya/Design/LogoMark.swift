import SwiftUI

/// THE LOGO. A planet lit by one light, the day lime and the night blue, with the straight route drawn through it: four
/// dashes a side shrinking by the golden ratio out of the dot at the centre, and off the planet a line tapering to a
/// round tip. Drawn here from his construction, number for number, with his glass recipe, so it is sharp at every size.
/// `phase` is where the light stands round the line (the line is the axis the light turns about): `rest` is his drawing
/// (the day/night curve an ellipse 1/phi^2 as wide as the planet); a turn of 2 pi is his animation, the day sweeping
/// round to night and back.
struct LogoMark: View, Animatable {
    var phase: Double = LogoMark.rest
    /// his glass (the light below, the rims, the sheen); off draws the flat mark
    var glass = true
    /// the route through it; off for the planet alone
    var line = true

    nonisolated var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    // HIS CONSTRUCTION, on a 1024 square, the centre at 512 (build_wya_logo.py)
    static let phi = (1 + 5.0.squareRoot()) / 2
    static let R: CGFloat = 350
    static let k: CGFloat = 1 / CGFloat(phi * phi)
    static let W: CGFloat = 22
    static let dotR: CGFloat = 34
    static let gap: CGFloat = 20
    static let reach: CGFloat = 2.0.squareRoot() * 350
    static let tip: CGFloat = 22.0 / 3
    /// his drawing: sin(rest) = k
    static let rest = asin(Double(1 / (phi * phi)))

    // HIS GLASS COLOURS (build_glass_svg.py COL, GLOW): body, light, deep
    static let lime = (body: hex(0xd6eb38), light: hex(0xf0ff8c), deep: hex(0xb3cc14), glow: hex(0xebfb7b))
    static let blue = (body: hex(0x66a6ff), light: hex(0x9ee6ff), deep: hex(0x407af2), glow: hex(0x93d9ff))
    static let ink = (body: hex(0x0d0d0f), light: hex(0x525257))
    // the flat mark's colours are the app's own

    /// the four dashes' spans from the centre outward
    static let spans: [(CGFloat, CGFloat)] = {
        let v0 = (R - dotR - 4 * gap) / CGFloat((0..<4).map { pow(phi, -Double($0)) }.reduce(0, +))
        var out: [(CGFloat, CGFloat)] = [], a = dotR
        for i in 0..<4 {
            let v = v0 * CGFloat(pow(phi, -Double(i)))
            out.append((a, a + v)); a += v + gap
        }
        return out
    }()

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 1024
            let g = Geo(c: CGPoint(x: size.width / 2, y: size.height / 2), s: s)
            let night = g.circle(Self.R)
            let day = g.day(phase)
            let dashes = g.dashes()
            let dot = g.circle(Self.dotR)
            let ends = g.ends()
            let disk = night.boundingRect

            guard glass else {
                ctx.fill(night, with: .color(Palette.blue))
                ctx.fill(day, with: .color(Palette.lime))
                if line {
                    ctx.fill(dashes, with: .color(Palette.ink)); ctx.fill(dot, with: .color(Palette.ink))
                    ctx.fill(ends, with: .color(Palette.ink))
                }
                return
            }
            // the coloured light thrown below each half
            Self.blurred(ctx, night, Self.blue.glow, 0.85, dy: 22 * s, sd: 30 * s)
            Self.blurred(ctx, day, Self.lime.glow, 0.75, dy: 22 * s, sd: 30 * s)
            // the night, then the day's own light near it, then the day
            Self.piece(ctx, night, Self.blue.body, Self.blue.light, Self.blue.deep, box: disk, s: s)
            Self.blurred(ctx, day, Self.lime.light, 0.35, dy: 14 * s, sd: 16 * s)
            Self.piece(ctx, day, Self.lime.body, Self.lime.light, Self.lime.deep, box: disk, s: s)
            // the line's shadow, then the line
            guard line else { return }
            let all = dashes.union(ends).union(dot)
            Self.blurred(ctx, all, .black, 0.25, dy: 6 * s, sd: 6 * s)
            for p in [dashes, dot, ends] {
                ctx.fill(p, with: .linearGradient(Gradient(colors: [Self.mix(Self.ink.body, Self.ink.light, 0.16), Self.ink.body]),
                                                  startPoint: CGPoint(x: 0, y: p.boundingRect.minY),
                                                  endPoint: CGPoint(x: 0, y: p.boundingRect.maxY)))
                Self.band(ctx, p, Self.ink.light, 0.35, dy: -5 * s, sd: 1.6 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "wya?!"))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: his glass, piece by piece (build_glass_svg.py piece/band/glow)

    /// a planet half: its body (a little lighter at the top), the rim a touch lighter, the top edge a touch deeper, a
    /// broad soft lift where it faces the light, and light leaving through its bottom edge
    private static func piece(_ ctx: GraphicsContext, _ p: Path, _ body: Color, _ light: Color, _ deep: Color, box: CGRect, s: CGFloat) {
        ctx.fill(p, with: .linearGradient(Gradient(colors: [mix(body, light, 0.16), body]),
                                          startPoint: CGPoint(x: 0, y: box.minY), endPoint: CGPoint(x: 0, y: box.maxY)))
        rim(ctx, p, light, 0.14, inset: 26 * s, sd: 12 * s)
        band(ctx, p, deep, 0.18, dy: 10 * s, sd: 4 * s)
        band(ctx, p, light, 0.20, dy: 46 * s, sd: 18 * s)
        band(ctx, p, light, 0.85, dy: -16 * s, sd: 5 * s)
    }

    /// the shape's colour thrown `dy` down and blurred, under what comes next
    private static func blurred(_ ctx: GraphicsContext, _ p: Path, _ c: Color, _ o: Double, dy: CGFloat, sd: CGFloat) {
        ctx.drawLayer { l in
            l.opacity = o
            l.addFilter(.blur(radius: sd))
            l.translateBy(x: 0, y: dy)
            l.fill(p, with: .color(c))
        }
    }

    /// a band inside one edge: the shape minus itself moved `dy`, blurred, kept inside the shape
    private static func band(_ ctx: GraphicsContext, _ p: Path, _ c: Color, _ o: Double, dy: CGFloat, sd: CGFloat) {
        ctx.drawLayer { outer in
            outer.clip(to: p)
            outer.drawLayer { l in
                l.opacity = o
                l.addFilter(.blur(radius: sd))
                l.fill(p, with: .color(c))
                l.blendMode = .destinationOut
                l.fill(p.offsetBy(dx: 0, dy: dy), with: .color(.black))
            }
        }
    }

    /// a band all round inside the edge: the shape's own edge, stroked twice as wide as the inset, blurred, kept inside
    private static func rim(_ ctx: GraphicsContext, _ p: Path, _ c: Color, _ o: Double, inset: CGFloat, sd: CGFloat) {
        ctx.drawLayer { outer in
            outer.clip(to: p)
            outer.drawLayer { l in
                l.opacity = o
                l.addFilter(.blur(radius: sd))
                l.stroke(p, with: .color(c), lineWidth: 2 * inset)
            }
        }
    }

    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let x = a.resolve(in: EnvironmentValues()), y = b.resolve(in: EnvironmentValues())
        return Color(red: Double(x.red + (y.red - x.red) * Float(t)), green: Double(x.green + (y.green - x.green) * Float(t)),
                     blue: Double(x.blue + (y.blue - x.blue) * Float(t)))
    }

    // MARK: his geometry

    /// points `along` the line and `across` it, towards the night (lower right), at scale `s`
    struct Geo {
        let c: CGPoint
        let s: CGFloat
        private let u = CGVector(dx: 1 / 2.0.squareRoot(), dy: -1 / 2.0.squareRoot())
        private let n = CGVector(dx: 1 / 2.0.squareRoot(), dy: 1 / 2.0.squareRoot())

        init(c: CGPoint, s: CGFloat) { self.c = c; self.s = s }

        func P(_ along: CGFloat, _ across: CGFloat = 0) -> CGPoint {
            CGPoint(x: c.x + s * (along * u.dx + across * n.dx), y: c.y + s * (along * u.dy + across * n.dy))
        }

        func circle(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s))
        }

        /// THE DAY for the light at `phase`: the planet's edge on the lit side from one end of the line to the other,
        /// back along the day/night curve, half an ellipse R * |sin(phase)| wide
        func day(_ phase: Double) -> Path {
            let side: CGFloat = cos(phase) >= 0 ? -1 : 1           // -1: the day on the top-left side (his)
            let bulge = CGFloat(sin(phase)) * -side                // + towards the night side at rest
            let R = LogoMark.R, steps = 96
            var p = Path()
            for i in 0...steps {
                let t = Double.pi * Double(i) / Double(steps)
                let q = P(R * CGFloat(cos(t)), side * R * CGFloat(sin(t)))
                i == 0 ? p.move(to: q) : p.addLine(to: q)
            }
            for i in 0...steps {
                let t = Double.pi * Double(i) / Double(steps)
                p.addLine(to: P(-R * CGFloat(cos(t)), bulge * R * CGFloat(sin(t))))
            }
            p.closeSubpath()
            return p
        }

        /// the four dashes a side as round-ended capsules, round caps centred at both ends of each: the first grows out
        /// of the dot
        func dashes() -> Path {
            var out = Path()
            let r = LogoMark.W / 2
            for sign in [CGFloat(1), -1] {
                for (i, sp) in LogoMark.spans.enumerated() {
                    let a = sign * (i == 0 ? sp.0 : sp.0 + r), b = sign * (sp.1 - r)
                    var l = Path(); l.move(to: P(a)); l.addLine(to: P(b))
                    out = out.union(l.strokedPath(StrokeStyle(lineWidth: LogoMark.W * s, lineCap: .round)))
                }
            }
            return out
        }

        /// off the planet: from its edge to sqrt2 * R, tapering from the line's width to a round tip: the straight
        /// sides run from the base corners, on the planet's edge, to their tangents on the tip's circle
        func ends() -> Path {
            var out = Path()
            let W = LogoMark.W, tip = LogoMark.tip
            let s0 = (LogoMark.R * LogoMark.R - (W / 2) * (W / 2)).squareRoot()
            let sc = LogoMark.reach - tip
            var tan: [CGFloat: (CGFloat, CGFloat)] = [:]
            for side in [CGFloat(1), -1] {
                let dx = s0 - sc, dy = side * W / 2
                let D = (dx * dx + dy * dy).squareRoot(), beta = atan2(dy, dx), alpha = acos(tip / D)
                let cands = [CGFloat(1), -1].map { e in (sc + tip * cos(beta + e * alpha), tip * sin(beta + e * alpha)) }
                tan[side] = cands.max { $0.1 * side < $1.1 * side }!
            }
            for sign in [CGFloat(1), -1] {
                let loc = { (a: CGFloat, b: CGFloat) in P(sign * a, sign * b) }
                let t1 = tan[-1]!, t2 = tan[1]!
                var side = Path()
                side.move(to: loc(s0, -W / 2)); side.addLine(to: loc(t1.0, t1.1))
                side.addLine(to: loc(t2.0, t2.1)); side.addLine(to: loc(s0, W / 2)); side.closeSubpath()
                let cc = loc(sc, 0)
                let round = Path(ellipseIn: CGRect(x: cc.x - tip * s, y: cc.y - tip * s, width: 2 * tip * s, height: 2 * tip * s))
                out = out.union(side.union(round))
            }
            return out
        }
    }
}

/// THE LOGO OPENING: the light goes once round the planet in about 2.7 seconds and comes to rest as his drawing; still
/// with Reduce Motion
struct LogoMarkOpening: View {
    let still: Bool
    var delay: Double = 0.1
    @State private var phase = LogoMark.rest

    var body: some View {
        LogoMark(phase: phase)
            .onAppear {
                guard !still else { return }
                withAnimation(.easeInOut(duration: 2.7).delay(delay)) { phase = LogoMark.rest + 2 * .pi }
            }
    }
}

/// WHERE THE LOGO'S LIGHT FALLS ON A PAGE (SLICE 175): about the planet's centre, so large it fills the page; brightest
/// in `glow` (round the logo and its name), as light is near where it comes from, so the name's lime and blue never lie
/// on their own colours
struct LogoLightSpot: Equatable {
    var centre: CGPoint
    var radius: CGFloat
    var glow: CGRect
    var strength: CGFloat
    static let none = LogoLightSpot(centre: .zero, radius: 1, glow: .zero, strength: 0)
}

/// one clock for the logo's light
enum LogoLightClock { static let start = Date() }

/// THE LOGO'S LIGHT ON THE PAGE. LogoGlassSurface.swift: lime where a planet far bigger than the screen has its day,
/// blue where it has its night, turning with the logo's light, over the whole page; the glass buttons refract it.
struct LogoLight: View, Animatable {
    var phase: Double
    let spot: LogoLightSpot
    /// not on screen: it keeps its last frame and stops drifting
    var hidden = false
    @Environment(\.accessibilityReduceMotion) private var still

    nonisolated var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    var body: some View {
        LogoGlassSurface(phase: phase, spot: spot, still: still || hidden)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

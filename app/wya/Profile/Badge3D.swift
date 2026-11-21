import SwiftUI
import RealityKit
import Vision
import CoreImage

#if DEBUG
/// BADGES IN 3D, FOR A LOOK (P07 §6; debug builds only for now): every badge a real solid, as Apple's Fitness awards
/// are. The shape is cut out of the level's material with a bevelled edge, lit by a studio around it (image-based
/// light: the shine is the room reflected in the metal, never a line drawn on it). It stands still; a finger turns it
/// and it settles back when let go. Europe and the swirled sun, each in the five levels: lime and blue as coloured
/// anodised metal, silver and gold as metal, diamond as clear glass with crystal cuts (the sun's middle a cut stone).
/// The test driver's `action review.badges3d` shows it and hides it.
@MainActor @Observable
final class Badge3D {
    static let shared = Badge3D()
    var on = false
}
#endif

/// the badges' shapes as outlines in their own space: about one unit across, y up, centred
enum BadgeOutline {
    /// a sun: `rays` curved rays round a disc; each ray's sides leave the disc `w` either side of its angle and meet at
    /// the tip, bending by `bend(t)` along the way (t: 0 at the disc, 1 at the tip)
    nonisolated static func sun(rays: Int, inner: CGFloat, outer: (Int) -> CGFloat, w: CGFloat, bend: @escaping (CGFloat) -> CGFloat,
                    narrow: @escaping (CGFloat) -> CGFloat = { 1 - $0 }) -> Path {
        var p = Path()
        let step = 2 * CGFloat.pi / CGFloat(rays)
        func pt(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: r * cos(a), y: r * sin(a)) }
        for i in 0 ..< rays {
            let a = CGFloat(i) * step, r1 = outer(i)
            // up the leading side to the tip
            for k in 0 ... 16 {
                let t = CGFloat(k) / 16
                let q = pt(inner + (r1 - inner) * t, a - w * narrow(t) + bend(t))
                if i == 0 && k == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            // down the trailing side
            for k in stride(from: 15, through: 0, by: -1) {
                let t = CGFloat(k) / 16
                p.addLine(to: pt(inner + (r1 - inner) * t, a + w * narrow(t) + bend(t)))
            }
            // along the disc to the next ray
            let from = a + w + bend(0), to = a + step - w + bend(0)
            for k in 1 ..< 6 { p.addLine(to: pt(inner, from + (to - from) * CGFloat(k) / 6)) }
        }
        p.closeSubpath()
        return p
    }

    /// twelve rays swept round like a pinwheel, each a curved blade
    nonisolated static var swirl: Path {
        sun(rays: 12, inner: 0.30, outer: { _ in 0.5 }, w: 0.17, bend: { 0.42 * pow($0, 1.7) })
    }
    static func disc(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)) }
    /// a ring: the outer circle one way round, the inner the other, so the middle is open
    static func ring(outer: CGFloat, inner: CGFloat, steps: Int = 128) -> Path {
        var p = Path()
        for (r, dir) in [(outer, CGFloat(1)), (inner, CGFloat(-1))] {
            for k in 0 ... steps {
                let a = dir * 2 * .pi * CGFloat(k) / CGFloat(steps)
                let q = CGPoint(x: r * cos(a), y: r * sin(a))
                if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        }
        return p
    }

    static func europe(_ world: World?) -> Path? { continent(world, "Europe") }

    /// a continent's land as one outline per landmass (borders inside it gone): the map's own units of it drawn into a
    /// picture, then Vision's contour finder traces the land's edge; specks left out
    static func continent(_ world: World?, _ name: String) -> Path? { traced(BadgeRings.continent(world, name)) }

    /// dark land on white: shrunk by 3 pixels, then grown by 3 (an opening), so strands under 6 pixels go
    static func opened(_ img: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: img)
        guard let shrink = CIFilter(name: "CIMorphologyMaximum", parameters: [kCIInputImageKey: ci, kCIInputRadiusKey: 3])?.outputImage,
              let grow = CIFilter(name: "CIMorphologyMinimum", parameters: [kCIInputImageKey: shrink, kCIInputRadiusKey: 3])?.outputImage
        else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(grow, from: ci.extent)
    }

    /// rings in a 0...1 box traced into one outline per landmass, the longer side 1.2 units
    static func traced(_ e: (rings: [[CGPoint]], aspect: CGFloat)) -> Path? {
        guard !e.rings.isEmpty, e.aspect > 0 else { return nil }
        // (the longer side 1,400 pixels: a tall country, Chile, as fine as a wide one)
        let W = e.aspect >= 1 ? 1400 : max(40, Int(1400 * e.aspect)), H = e.aspect >= 1 ? max(40, Int(1400 / e.aspect)) : 1400
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(gray: 0, alpha: 1)
        // (the rings run top down; the picture bottom up; 3% clear round the edge, so land at the edge is traced too)
        let m: CGFloat = 0.03, fw = CGFloat(W) * (1 - 2 * m), fh = CGFloat(H) * (1 - 2 * m), ox = CGFloat(W) * m, oy = CGFloat(H) * m
        for ring in e.rings where ring.count > 2 {
            ctx.move(to: CGPoint(x: ox + ring[0].x * fw, y: oy + (1 - ring[0].y) * fh))
            for q in ring.dropFirst() { ctx.addLine(to: CGPoint(x: ox + q.x * fw, y: oy + (1 - q.y) * fh)) }
            ctx.closePath()
        }
        ctx.fillPath()
        guard let drawn = ctx.makeImage() else { return nil }
        // (land thinner than about 6 pixels taken off and the rest grown back: the Aleutians and the like traced as
        // hairlines that stood out of the solid as spikes)
        let img = Self.opened(drawn) ?? drawn
        let req = VNDetectContoursRequest()
        req.detectsDarkOnLight = true
        req.contrastAdjustment = 1
        req.maximumImageDimension = 1400
        try? VNImageRequestHandler(cgImage: img).perform([req])
        guard let obs = req.results?.first else { return nil }
        // the longer side 1.2 units, centred
        let sx: CGFloat = e.aspect >= 1 ? 1.2 : 1.2 * e.aspect, sy = sx / e.aspect
        var p = Path()
        for c in obs.topLevelContours where c.pointCount > 40 {
            guard let a = try? c.polygonApproximation(epsilon: 0.003), a.pointCount > 3 else { continue }
            let pts = a.normalizedPoints
            p.move(to: CGPoint(x: (CGFloat(pts[0].x) - 0.5) * sx, y: (CGFloat(pts[0].y) - 0.5) * sy))
            for q in pts.dropFirst() { p.addLine(to: CGPoint(x: (CGFloat(q.x) - 0.5) * sx, y: (CGFloat(q.y) - 0.5) * sy)) }
            p.closeSubpath()
        }
        return p.isEmpty ? nil : p
    }
}

/// the five levels' materials, physically based: the light comes from the studio round them
@MainActor
enum BadgeMaterial {
    /// `opaque`: the glass drawn solid (a live view over the page draws see-through glass as nothing at all)
    static func of(_ level: BadgeLevel, opaque: Bool = false) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        switch level {
        case .lime, .blue:
            // coloured anodised metal under a clear coat: the colour stays, the room shows in the coat
            m.baseColor = .init(tint: level == .lime ? UIColor(red: 0.90, green: 1.0, blue: 0.30, alpha: 1)
                                                     : UIColor(red: 0.42, green: 0.66, blue: 1.0, alpha: 1))
            // (coloured metal: anodised aluminium is metal under its colour, so the room shows through tinted; at
            // a fifth metal it read as plastic)
            m.metallic = 0.6
            m.roughness = 0.24
            m.clearcoat = 1.0
            m.clearcoatRoughness = 0.04
        case .silver:
            // (a touch below white: at full white the softbox's bright end burns it out)
            m.baseColor = .init(tint: UIColor(red: 0.80, green: 0.81, blue: 0.83, alpha: 1))
            m.metallic = 1.0
            m.roughness = 0.14
        case .gold:
            m.baseColor = .init(tint: UIColor(red: 1.0, green: 0.80, blue: 0.38, alpha: 1))
            m.metallic = 1.0
            m.roughness = 0.13
        case .diamond:
            // clear glass: almost no body, all coat; the cuts catch the room
            // (a cut stone reads by its facets catching light and dark from the room in turn: mirror-clear, a cool
            // white, only partly see-through; fully clear over the light ground it showed as a pale smear)
            m.baseColor = .init(tint: UIColor(red: 0.90, green: 0.95, blue: 1.0, alpha: 1))
            m.metallic = 1.0
            m.roughness = 0.03
            m.specular = 1.0
            m.clearcoat = 1.0
            m.clearcoatRoughness = 0.0
            if !opaque { m.blending = .transparent(opacity: .init(floatLiteral: 0.72)) }
        }
        return m
    }
}

/// the studio the badges stand in, as a picture all round them (equirectangular): a dark room with soft white panels
/// above and to the sides and a warm one behind; its reflection is the badges' shine
@MainActor
enum BadgeStudio {
    static func image() -> CGImage? {
        let W = 1024, H = 512
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // the room: lighter overhead, dark at the floor (the picture is bottom up: y = H is overhead)
        let space = CGColorSpaceCreateDeviceRGB()
        // (a darker room than at first: in a pale one the gold read as pale yellow plastic and the silver as white)
        let room = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0.04, alpha: 1), CGColor(gray: 0.14, alpha: 1),
                                                           CGColor(gray: 0.40, alpha: 1)] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(room, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        func panel(_ r: CGRect, _ c: CGColor, soft: CGFloat) {
            // a panel with soft edges: the same rectangle drawn wider and fainter, then sharp in the middle
            for k in stride(from: 6, through: 0, by: -1) {
                let g = CGFloat(k) * soft
                ctx.setFillColor(c.copy(alpha: 0.14)!)
                ctx.fill(r.insetBy(dx: -g, dy: -g))
            }
            ctx.setFillColor(c); ctx.fill(r)
        }
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        // (u runs from behind the badge round to behind again: u = 0 and 1 are in front of it, where the camera is)
        // a big soft panel in front and above, split across the picture's two ends: the faces' main light
        panel(CGRect(x: 0, y: 330, width: 46, height: 70), white, soft: 8)
        panel(CGRect(x: 978, y: 330, width: 46, height: 70), white, soft: 8)
        // straight ahead, where the flat faces look: a tall softbox, bright at its top, fading down (the faces read as
        // metal, light to deep, rather than as a flat colour)
        let box = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0.15, alpha: 1), CGColor(gray: 1.0, alpha: 1)] as CFArray,
                             locations: [0, 1])!
        for x in [CGFloat(0), 954] {
            ctx.saveGState(); ctx.clip(to: CGRect(x: x, y: 150, width: 70, height: 160))
            ctx.drawLinearGradient(box, start: CGPoint(x: 0, y: 150), end: CGPoint(x: 0, y: 310), options: [])
            ctx.restoreGState()
        }
        // tall strips either side (u = 0.25 and 0.75): the bevels catch them as it turns
        panel(CGRect(x: 236, y: 190, width: 40, height: 200), white, soft: 6)
        panel(CGRect(x: 748, y: 190, width: 40, height: 200), CGColor(red: 1, green: 0.95, blue: 0.88, alpha: 1), soft: 6)
        // a band of sky overhead and a warm glow behind
        panel(CGRect(x: 0, y: 482, width: 1024, height: 30), CGColor(gray: 0.6, alpha: 1), soft: 6)
        panel(CGRect(x: 420, y: 250, width: 180, height: 80), CGColor(red: 1, green: 0.8, blue: 0.55, alpha: 1), soft: 12)
        return ctx.makeImage()
    }
}

/// a cut stone for the sun's middle (the diamond's crystal cuts): a flat table on top, a ring of triangular facets
/// sloping down to the girdle, every facet flat so each one catches the room on its own
@MainActor
enum BadgeGem {
    static func mesh(radius R: Float, table: Float = 0.56, height h: Float = 0.11, facets n: Int = 16) -> MeshResource? {
        var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], idx: [UInt32] = []
        func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            var (p, q, r) = (a, b, c)
            var nm = simd_normalize(simd_cross(q - p, r - p))
            // every facet faces out and up (towards the camera)
            if nm.z < 0 { swap(&q, &r); nm = -nm }
            for v in [p, q, r] { idx.append(UInt32(pos.count)); pos.append(v); nor.append(nm) }
        }
        let step = 2 * Float.pi / Float(n), top = SIMD3<Float>(0, 0, h)
        func g(_ i: Int) -> SIMD3<Float> { let a = Float(i) * step; return [R * cos(a), R * sin(a), 0] }
        func t(_ i: Int) -> SIMD3<Float> { let a = (Float(i) + 0.5) * step; return [R * table * cos(a), R * table * sin(a), h] }
        for i in 0 ..< n {
            tri(top, t(i), t(i + 1))           // the table
            tri(g(i), g(i + 1), t(i))          // a crown facet down to the girdle
            tri(t(i), g(i + 1), t(i + 1))      // a star facet between
        }
        var d = MeshDescriptor(name: "gem")
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nor)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}

#if DEBUG
struct Badge3DView: View {
    let world: World?
    let L: Layout
    private static let forms = ["Europe", "Streak"]

    var body: some View {
        if Badge3D.shared.on {
            ZStack {
                LivingField().ignoresSafeArea()
                RealityView { content in
                    await build(&content)
                }
                // a finger turns them; let go and they settle back facing you
                // (the scene let go when the review closes)
                .onDisappear { Badge3DTurn.shared.holders = [] }
                .gesture(DragGesture()
                    .onChanged { g in Badge3DTurn.shared.turn(Float(g.translation.width / 110), Float(g.translation.height / 160)) }
                    .onEnded { _ in Badge3DTurn.shared.settle() })
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Self.forms, id: \.self) { f in
                            Text(f).font(.headline).foregroundStyle(Palette.ink).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, L.headBottom + 8)
                    Spacer()
                }
            }
            .frame(width: L.W, height: L.H)
        }
    }

    /// two columns (Europe and the sun), five rows (the levels), one camera far back with a narrow lens so nothing is
    /// distorted
    private func build(_ content: inout RealityViewCameraContent) async {
        content.camera = .virtual
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 22
        let rows = 5, cols = 2, gap: Float = 1.32
        let aspect = Float(L.W / L.H)
        // the grid's height fits the lens: tall enough for the rows, wide enough for the columns
        let needH = max(Float(rows) * gap + 1.6, (Float(cols) * gap + 1.0) / aspect)
        cam.position = [0, 0.55, needH / 2 / tan(11 * .pi / 180)]
        content.add(cam)

        let lightEntity = Entity(), glassLight = Entity()
        content.add(lightEntity)
        content.add(glassLight)
        let europe = BadgeOutline.europe(world)
        let shapes: [Path?] = [europe, BadgeOutline.swirl]
        var holders: [Entity] = []
        for (r, level) in BadgeLevel.allCases.enumerated() {
            for c in 0 ..< cols {
                guard let shape = shapes[c] else { continue }
                let holder = Entity()
                holder.position = [(Float(c) - Float(cols - 1) / 2) * gap * 1.25, (Float(rows - 1) / 2 - Float(r)) * gap, 0]
                let mat = BadgeMaterial.of(level)
                let diamond = level == .diamond
                // (Europe's thin coasts take only a small bevel: a big one folds over itself at the narrow points)
                let bevel: Float = c == 0 ? 0.012 : (diamond ? 0.03 : 0.022)
                if let body = Self.solid(shape, depth: 0.09, chamfer: bevel, mat: mat) { holder.addChild(body) }
                if c == 1 {
                    if diamond, let gem = BadgeGem.mesh(radius: 0.3, height: 0.16, facets: 24) {
                        // the diamond's middle: a cut stone sitting on the rays
                        let stone = ModelEntity(mesh: gem, materials: [mat])
                        stone.position.z = 0.03
                        holder.addChild(stone)
                    } else if let core = Self.solid(BadgeOutline.disc(0.26), depth: 0.15, chamfer: 0.04, mat: mat, smooth: true) {
                        // the metals' middle: a disc standing proud of the rays
                        holder.addChild(core)
                    }
                }
                // (the glass takes the same room, dimmer: at full strength it shows only white)
                for child in holder.children {
                    child.components.set(ImageBasedLightReceiverComponent(imageBasedLight: diamond ? glassLight : lightEntity))
                }
                holder.orientation = Badge3DTurn.rest
                content.add(holder)
                holders.append(holder)
            }
        }
        Badge3DTurn.shared.holders = holders
        // the studio's light (it takes a moment to build; the badges are already up)
        if let img = BadgeStudio.image() {
            do {
                let cube = try await TextureResource(cubeFromEquirectangular: img, quality: .normal,
                                                     options: .init(semantic: .hdrColor))
                let env = try await EnvironmentResource(cube: cube, options: .init())
                lightEntity.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 1.2))
                glassLight.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.9))
            } catch {
                print("wya badges: the studio light failed: \(error)")
            }
        }
    }

    private static func solid(_ path: Path, depth: Float, chamfer: Float, mat: PhysicallyBasedMaterial,
                              smooth: Bool = false) -> ModelEntity? {
        var o = MeshResource.ShapeExtrusionOptions()
        o.extrusionMethod = .linear(depth: depth)
        o.chamferRadius = chamfer
        o.chamferMode = .both
        o.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: smooth ? 16 : 2)
        guard let mesh = try? MeshResource(extruding: path, extrusionOptions: o) else { return nil }
        return ModelEntity(mesh: mesh, materials: [mat])
    }
}

/// the finger's turn: every badge turns with it (round its upright and leaning back), and settles back facing you,
/// eased, when it lets go; nothing moves on its own
@MainActor final class Badge3DTurn {
    static let shared = Badge3DTurn()
    var holders: [Entity] = []
    /// at rest each badge is turned a little and leans back, as a medal held in the hand: its face takes the softbox's
    /// fade from light to deep and its bevels the strips beside it (straight on, a face shows one flat tone)
    static let rest = simd_quatf(angle: 0.22, axis: [0, 1, 0]) * simd_quatf(angle: -0.28, axis: [1, 0, 0])
    func turn(_ yaw: Float, _ pitch: Float) {
        let q = simd_quatf(angle: yaw, axis: [0, 1, 0]) * Self.rest * simd_quatf(angle: max(-0.6, min(0.6, pitch)), axis: [1, 0, 0])
        for h in holders { h.stopAllAnimations(); h.orientation = q }
    }
    func settle() {
        for h in holders {
            var t = h.transform
            t.rotation = Self.rest
            h.move(to: t, relativeTo: h.parent, duration: 0.7, timingFunction: .easeOut)
        }
    }
}
#endif

import SwiftUI
import RealityKit
import Metal

/// A BADGE'S LEVEL: lime, blue, silver, gold, diamond (P07 §6), each its own material (BadgeMaterial)
nonisolated enum BadgeLevel: Int, CaseIterable {
    case lime = 1, blue, silver, gold, diamond
    var name: String { ["", "Lime", "Blue", "Silver", "Gold", "Diamond"][rawValue] }
    /// the material drawn flat: light at the top left, deep at the bottom right (the logo's own lime and blue; metals
    /// as metals)
    var stops: (light: Color, body: Color, deep: Color) {
        switch self {
        case .lime: (Color(hex: 0xf0ff8c), Color(hex: 0xd6eb38), Color(hex: 0xb3cc14))
        case .blue: (Color(hex: 0x9ee6ff), Color(hex: 0x66a6ff), Color(hex: 0x407af2))
        case .silver: (Color(hex: 0xf2f3f5), Color(hex: 0xc9ccd1), Color(hex: 0x9298a1))
        case .gold: (Color(hex: 0xf6e3a1), Color(hex: 0xdcb64c), Color(hex: 0xb08a22))
        case .diamond: (Color.white, Color.white, Color.white)
        }
    }
    /// a badge's level as one of the five (a badge not yet earned shows as lime)
    static func of(_ b: Badge) -> BadgeLevel { BadgeLevel(rawValue: min(5, max(1, b.level))) ?? .lime }
}

/// A BADGE'S FORM, the solid it is cut as: a continent's badge is the continent's own land (the map's own units of it,
/// its own projection, the coasts traced once); the streak's is the swirled sun; every other badge, until its own form is
/// drawn, a medal (a disc with a raised rim; the diamond's with a cut stone in the middle)
enum BadgeForm: Hashable {
    case continent(String)
    /// the land of these places together (a country's own badges, a part of the world, a group of countries); `in`:
    /// only their pieces on that continent (Eastern Europe is Russia to the Urals, not to the Pacific)
    case places([String], in: String? = nil)
    case swirl
    case medal
    /// A MEDAL STRUCK WITH ITS NUMBER: the step its level stands for ("20" for Languages at gold, the first step for
    /// one not yet earned) raised on its face, as a real medal is struck with what it was won for
    case struck(String)
    /// A NATURAL REGION AS ITSELF: a range's or a sea's own outline from the Places sets' shapes, its relief inside
    /// it
    case natural(file: String, key: String, sea: Bool)
    /// the Arctic seen from above the Pole
    case arctic

    /// the group badges that are a natural region, not their countries
    static let regions: [String: BadgeForm] = {
        let ranges = "native/collections/shapes-ranges-1.wyau", seas = "native/collections/shapes-allseas-2.wyau"
        return ["The Alps": .natural(file: ranges, key: "Q1286", sea: false),
                "The Himalayas": .natural(file: ranges, key: "Q5451", sea: false),
                "The Andes": .natural(file: ranges, key: "Q5456", sea: false),
                "The Caucasus": .natural(file: ranges, key: "Q5477", sea: false),
                "The Mediterranean": .natural(file: seas, key: "Q4918", sea: true),
                "The Arctic": .arctic]
    }()

    @MainActor static func of(_ b: Badge) -> BadgeForm {
        switch b.id {
        case "europe": return .continent("Europe")
        case "asia": return .continent("Asia")
        case "africa": return .continent("Africa")
        case "namerica": return .continent("North America")
        case "samerica": return .continent("South America")
        case "oceania": return .continent("Oceania")
        case "streak": return .swirl
        default: break
        }
        if b.family == "groups", let n = regions[b.name] { return n }
        // a continent's capitals: the continent
        if let p = b.place, BadgeArt.shared.world?.contViews[p] != nil { return .continent(p) }
        if let m = members(b), !m.isEmpty {
            let cont = b.family == "world" && b.name.hasSuffix("Europe") ? "Europe" : nil
            return .places(m.sorted(), in: cont)
        }
        guard !b.steps.isEmpty else { return .medal }
        let n = b.steps[min(b.steps.count - 1, max(0, b.level - 1))]
        // (the number only, no unit: would not fit a face; a share keeps its %)
        let t = b.unit == .percent ? "\(n)%" : b.unit == .tenthDegrees ? String(format: "%.0f°", Double(n) / 10) : n.formatted()
        return .struck(t)
    }

    /// the places a badge is about, where it is about a set of them on the map
    @MainActor private static func members(_ b: Badge) -> [String]? {
        // a country's own regions or towns
        if let p = b.place, p.count == 2 { return [p] }
        if b.family == "groups", let g = Badges.groups.first(where: { Badges.slug($0.0) == b.id }) { return g.1 }
        if b.id == "islandnations" { return Array(Badges.islandCountries) }
        guard let w = BadgeArt.shared.world, let bw = BadgeStore.shared.book(w)?.world else { return nil }
        if b.family == "world", let r = Badges.unRegions.first(where: { Badges.slug($0) == b.id }) {
            return bw.countries.filter { $0.sub == r }.map(\.id)
        }
        if b.family == "languages", let l = Badges.languageAreas.first(where: { Badges.slug($0) + "-speaking" == b.id }) {
            return bw.countries.filter { $0.lang.contains(l) }.map(\.id)
        }
        if b.family == "currencies", let c = Badges.currencies.first(where: { Badges.slug($0.0) == b.id }) {
            return bw.countries.filter { $0.cur.contains(c.1) }.map(\.id)
        }
        return nil
    }

    var key: String {
        switch self {
        case .continent(let n): "c:" + n
        case .places(let ids, let c): "p:" + (c.map { $0 + ":" } ?? "") + ids.joined(separator: ",")
        case .swirl: "swirl"
        case .medal: "medal"
        case .struck(let t): "struck:" + t
        case .natural(_, let k, _): "n:" + k
        case .arctic: "arctic"
        }
    }
}

/// the badges' outlines as rings of points in a 0...1 box (its own width to height kept)
@MainActor
enum BadgeRings {
    /// a continent's land: every unit the map counts in it, rings as the map has them, inside the continent's own view;
    /// specks too small to see at a badge's size left out
    static func continent(_ w: World?, _ name: String) -> (rings: [[CGPoint]], aspect: CGFloat) {
        let r = continentBoxed(w, name); return (r.rings, r.aspect)
    }
    /// the same, with its box in the map's own units (x0, y0, x1, y1): the flat badges' relief is read through it
    static func continentBoxed(_ w: World?, _ name: String) -> (rings: [[CGPoint]], aspect: CGFloat, box: SIMD4<Float>) {
        guard let w, let view = w.contViews[name] else { return ([], 1, .zero) }
        var raw: [[SIMD2<Float>]] = []
        for u in 0 ..< w.unitConts.count where w.unitConts[u].contains(name) && u < w.unitRings.count {
            for ri in w.unitRings[u] {
                let r = w.rings[ri]
                let cx = Double(r.box.x + r.box.z) / 2, cy = Double(r.box.y + r.box.w) / 2
                guard cx >= view.x, cx <= view.z, cy >= view.y, cy <= view.w else { continue }
                // (a speck: under 0.4% of the view across)
                guard Double(max(r.box.z - r.box.x, r.box.w - r.box.y)) > (view.z - view.x) * 0.004 else { continue }
                raw.append(Array(w.points[r.start ..< r.start + r.count]))
            }
        }
        let all = raw.flatMap { $0 }
        guard let x0 = all.map(\.x).min(), let x1 = all.map(\.x).max(), let y0 = all.map(\.y).min(), let y1 = all.map(\.y).max(),
              x1 > x0, y1 > y0 else { return ([], 1, .zero) }
        let rings = raw.map { r in r.map { CGPoint(x: CGFloat(($0.x - x0) / (x1 - x0)), y: CGFloat(($0.y - y0) / (y1 - y0))) } }
        return (rings, CGFloat((x1 - x0) / (y1 - y0)), SIMD4(x0, y0, x1, y1))
    }

    /// the land of these places together, as the map draws them: pieces far from the biggest one's side of the world
    /// left out (Alaska's tail over the date line, an island a world away), specks too; none when what is left still
    /// spans much of the world (a language's countries round the globe: no outline would read as anything there)
    static func places(_ w: World?, _ ids: Set<String>, in cont: String? = nil) -> (rings: [[CGPoint]], aspect: CGFloat) {
        let r = placesBoxed(w, ids, in: cont); return (r.rings, r.aspect)
    }
    /// the same, with its box in the map's own units (x0, y0, x1, y1)
    static func placesBoxed(_ w: World?, _ ids: Set<String>, in cont: String? = nil) -> (rings: [[CGPoint]], aspect: CGFloat, box: SIMD4<Float>) {
        guard let w, !ids.isEmpty else { return ([], 1, .zero) }
        var owners = Set<Int>()
        for (i, p) in w.places.enumerated() where ids.contains(p.id) { owners.insert(i) }
        var pieces: [World.Ring] = []
        for (u, o) in w.unitOwner.enumerated() where owners.contains(o) && u < w.unitRings.count {
            if let cont, u < w.unitConts.count, !w.unitConts[u].contains(cont) { continue }
            for ri in w.unitRings[u] { pieces.append(w.rings[ri]) }
        }
        func across(_ r: World.Ring) -> Float { max(r.box.z - r.box.x, r.box.w - r.box.y) }
        func area(_ r: World.Ring) -> Float { (r.box.z - r.box.x) * (r.box.w - r.box.y) }
        guard let big = pieces.max(by: { area($0) < area($1) }) else { return ([], 1, .zero) }
        // the land that holds together: from the biggest piece, every piece within 12% of the whole's size of it,
        // again and again (neighbours touch; Sicily and Corsica come in, the Canaries and the Azores do not)
        var near = [big], box = big.box
        var rest = pieces.filter { $0.start != big.start }
        var grew = true
        while grew {
            grew = false
            let d = max(box.z - box.x, box.w - box.y) * 0.12
            rest.removeAll { r in
                guard r.box.x <= box.z + d, r.box.z >= box.x - d, r.box.y <= box.w + d, r.box.w >= box.y - d else { return false }
                near.append(r)
                box = SIMD4(min(box.x, r.box.x), min(box.y, r.box.y), max(box.z, r.box.z), max(box.w, r.box.w))
                grew = true
                return true
            }
        }
        // (much of the land left out: the set is spread round the world, Portuguese-speaking, and has no one shape)
        let inArea = near.reduce(Float(0)) { $0 + area($1) }, outArea = rest.reduce(Float(0)) { $0 + area($1) }
        guard outArea <= (inArea + outArea) * 0.15 else { return ([], 1, .zero) }
        // (and most of the places in it: Brazil alone is not Portuguese-speaking)
        func owner(_ r: World.Ring) -> Int { r.unit >= 0 && r.unit < w.unitOwner.count ? w.unitOwner[r.unit] : -1 }
        let all = Set(pieces.map(owner)), held = Set(near.map(owner))
        guard Double(held.count) >= Double(all.count) * 0.6 else { return ([], 1, .zero) }
        let x0 = box.x, x1 = box.z, y0 = box.y, y1 = box.w
        // (too small to read as its own shape at a badge's size: Monaco)
        guard x1 > x0, y1 > y0, max(x1 - x0, y1 - y0) > w.width * 0.0015 else { return ([], 1, .zero) }
        let ext = max(x1 - x0, y1 - y0)
        let raw = near.filter { across($0) > ext * 0.006 }.map { Array(w.points[$0.start ..< $0.start + $0.count]) }
        let rings = raw.map { r in r.map { CGPoint(x: CGFloat(($0.x - x0) / (x1 - x0)), y: CGFloat(($0.y - y0) / (y1 - y0))) } }
        return (rings, CGFloat((x1 - x0) / (y1 - y0)), SIMD4(x0, y0, x1, y1))
    }
}

/// the badges as solids: the form cut out of the level's material with a bevelled edge, centred on its own middle
@MainActor
enum BadgeSolid {
    /// the form's outline in its own space (about one unit across, y up), worked out once per world
    private static var outlines: [String: Path?] = [:]

    static func outline(_ form: BadgeForm, world: World?) -> Path? {
        if let p = outlines[form.key] { return p }
        let p: Path?
        switch form {
        case .continent(let n): p = BadgeOutline.continent(world, n)
        case .places(let ids, let c): p = BadgeOutline.traced(BadgeRings.places(world, Set(ids), in: c))
        case .swirl: p = BadgeOutline.swirl
        case .medal, .struck, .natural, .arctic: p = BadgeOutline.disc(0.5)
        }
        // (none is kept too, once the world is here: a set too spread is not traced again)
        if p != nil || world != nil { outlines[form.key] = .some(p) }
        return p
    }

    static func make(_ form: BadgeForm, _ level: BadgeLevel, world: World?, live: Bool = false) -> Entity? {
        let mat = BadgeMaterial.of(level, opaque: live)
        let diamond = level == .diamond
        let body = Entity()
        switch form {
        case .continent, .places:
            // (thin coasts take only a small bevel: a big one folds over itself at the narrow points)
            guard let p = outline(form, world: world), let m = solid(p, depth: 0.09, chamfer: 0.012, mat: mat) else { return nil }
            body.addChild(m)
        case .swirl:
            guard let p = outline(form, world: world), let m = solid(p, depth: 0.09, chamfer: diamond ? 0.03 : 0.022, mat: mat) else { return nil }
            body.addChild(m)
            if diamond, let gem = BadgeGem.mesh(radius: 0.3, table: 0.36, height: 0.16, facets: 24) {
                // the diamond's middle: a cut stone sitting on the rays
                let stone = ModelEntity(mesh: gem, materials: [mat])
                stone.position.z = 0.03
                body.addChild(stone)
            } else if let core = solid(BadgeOutline.disc(0.26), depth: 0.15, chamfer: 0.04, mat: mat, smooth: true) {
                // the metals' middle: a disc standing proud of the rays
                body.addChild(core)
            }
        case .medal, .struck, .natural, .arctic:
            // a disc, and a rim standing proud of it on both faces
            guard let face = solid(BadgeOutline.disc(0.43), depth: 0.07, chamfer: 0.015, mat: mat, smooth: true),
                  let rim = solid(BadgeOutline.ring(outer: 0.5, inner: 0.41), depth: 0.13, chamfer: 0.025, mat: mat, smooth: true)
            else { return nil }
            body.addChild(face)
            body.addChild(rim)
            if case .struck(let t) = form, let num = struck(t, mat: diamond ? BadgeMaterial.of(.silver, opaque: live) : mat) {
                // its number raised on the face's front, as high as the rim stands
                let fb = face.visualBounds(relativeTo: body), nb = num.visualBounds(relativeTo: num)
                num.position = [-nb.center.x * num.scale.x, -nb.center.y * num.scale.y, fb.max.z - nb.min.z - 0.004]
                body.addChild(num)
            } else if diamond, let gem = BadgeGem.mesh(radius: 0.3, table: 0.36, height: 0.14, facets: 24) {
                let stone = ModelEntity(mesh: gem, materials: [mat])
                stone.position.z = 0.03
                body.addChild(stone)
            }
        }
        // centred on its own middle, so it turns round it and the camera frames it
        let b = body.visualBounds(relativeTo: body)
        for c in body.children { c.position -= b.center }
        return body
    }

    /// a medal's number as a solid: rounded bold, scaled so it sits inside the rim with room round it
    static func struck(_ t: String, mat: PhysicallyBasedMaterial) -> ModelEntity? {
        let base = UIFont.systemFont(ofSize: 0.3, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 0.3) } ?? base
        let mesh = MeshResource.generateText(t, extrusionDepth: 0.05, font: font, containerFrame: .zero,
                                             alignment: .center, lineBreakMode: .byClipping)
        let e = ModelEntity(mesh: mesh, materials: [mat])
        let b = e.visualBounds(relativeTo: e)
        // (inside a 0.41 rim: at most 0.6 across and 0.34 high; a lone digit, with the face's room round it, 0.44
        // high: at 0.34 a "520" and "50%")
        let k = min(0.6 / max(0.001, b.extents.x), (t.count == 1 ? 0.44 : 0.34) / max(0.001, b.extents.y))
        e.scale = [k, k, 1]
        return e
    }

    static func solid(_ path: Path, depth: Float, chamfer: Float, mat: PhysicallyBasedMaterial, smooth: Bool = false) -> ModelEntity? {
        var o = MeshResource.ShapeExtrusionOptions()
        o.extrusionMethod = .linear(depth: depth)
        o.chamferRadius = chamfer
        o.chamferMode = .both
        o.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: smooth ? 16 : 2)
        guard let mesh = try? MeshResource(extruding: path, extrusionOptions: o) else { return nil }
        return ModelEntity(mesh: mesh, materials: [mat])
    }

    /// at rest a badge is turned a little and leans back, as a medal held in the hand: its face takes the studio's
    /// softbox from light to deep and its bevels the strips beside it (straight on, a face shows one flat tone)
    static let rest = simd_quatf(angle: 0.22, axis: [0, 1, 0]) * simd_quatf(angle: -0.28, axis: [1, 0, 0])
    /// the lens: narrow, from far back, so nothing is distorted
    static let fov: Float = 22
    /// the camera's distance for a solid of this size to fill the frame, with a little room round it
    static func distance(_ bounds: BoundingBox) -> Float {
        let ext = max(bounds.extents.x, bounds.extents.y)
        return ext / 2 * 1.1 / tan(fov / 2 * .pi / 180) + bounds.extents.z / 2
    }
}

/// THE BADGES' PICTURES: each badge's solid drawn once, off screen, by RealityKit's own renderer in the studio's light,
/// and kept; the grid shows these pictures, so a page of badges costs no live 3D at all (only the one badge opened
/// alone is live, to be turned by a finger)
@MainActor
final class BadgeArt {
    static let shared = BadgeArt()
    /// the map's world, for the continents' outlines (set when the Profile's numbers are counted)
    weak var world: World?
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 48 << 20
        return c
    }()
    /// each badge's form, worked out once the world is here
    private var forms: [String: BadgeForm] = [:]
    func form(_ b: Badge) -> BadgeForm {
        // (by its level too: a medal's number is its level's step)
        let k = b.id + "|\(b.level)"
        if let f = forms[k] { return f }
        let f = BadgeForm.of(b)
        if world != nil, b.id != "islandnations" || BadgeStore.shared.ready { forms[k] = f }
        return f
    }
    private var env: EnvironmentResource?
    private var envTask: Task<EnvironmentResource?, Never>?
    private var renderer: RealityRenderer?
    private let camera = PerspectiveCamera()
    private let root = Entity()
    private let device = MTLCreateSystemDefaultDevice()
    /// one picture at a time (they share the renderer)
    private var last: Task<Void, Never>?

    func cached(_ form: BadgeForm, _ level: BadgeLevel, px: Int) -> UIImage? { cache.object(forKey: "\(form.key)|\(level.rawValue)|\(px)" as NSString) }

    func image(_ form: BadgeForm, _ level: BadgeLevel, px: Int, scale: CGFloat = 3) async -> UIImage? {
        let k = "\(form.key)|\(level.rawValue)|\(px)"
        if let c = cache.object(forKey: k as NSString) { return c }
        let before = last
        let job = Task { @MainActor () -> UIImage? in
            await before?.value
            if let c = self.cache.object(forKey: k as NSString) { return c }
            let img = await self.render(form, level, px: px, scale: scale)
            if let img { self.cache.setObject(img, forKey: k as NSString, cost: px * px * 4) }
            return img
        }
        last = Task { _ = await job.value }
        return await job.value
    }

    /// the studio's light (the picture round the badges, BadgeStudio), made once for the pictures
    func environment() async -> EnvironmentResource? {
        if let env { return env }
        if let envTask { return await envTask.value }
        let t = Task { @MainActor () -> EnvironmentResource? in await Self.studio() }
        envTask = t
        env = await t.value
        return env
    }

    /// the same light made again for a live view (one made for the pictures' renderer and handed to a live view left
    /// that view empty)
    static func studio() async -> EnvironmentResource? {
        guard let img = BadgeStudio.image() else { return nil }
        do {
            let cube = try await TextureResource(cubeFromEquirectangular: img, quality: .normal, options: .init(semantic: .hdrColor))
            return try await EnvironmentResource(cube: cube, options: .init())
        } catch {
            print("wya badges: the studio light failed: \(error)")
            return nil
        }
    }

    /// the studio light's strength: the glass takes the same room, dimmer (at full strength it shows only white)
    /// (the coloured metals in more light than the plain ones: in the same, lime read olive)
    static func exponent(_ level: BadgeLevel) -> Float {
        switch level {
        case .diamond: 2.1
        case .lime, .blue: 1.9
        default: 1.5
        }
    }

    /// THE FLAT PICTURE: a region's relief cut to its shape, a number on a flat disc, drawn off the main thread
    /// (BadgeFlat); the 3D solid below is no longer drawn
    private func render(_ form: BadgeForm, _ level: BadgeLevel, px: Int, scale: CGFloat) async -> UIImage? {
        var plan: BadgeFlat.Plan?, number: String?, swirl = false
        func boxed(_ r: (rings: [[CGPoint]], aspect: CGFloat, box: SIMD4<Float>)) -> BadgeFlat.Plan? {
            r.rings.isEmpty ? nil : BadgeFlat.Plan(plane: .equalEarth(box: SIMD4<Double>(r.box)), rings: r.rings, aspect: r.aspect)
        }
        switch form {
        case .continent(let n): plan = boxed(BadgeRings.continentBoxed(world, n))
        case .places(let ids, let c): plan = boxed(BadgeRings.placesBoxed(world, Set(ids), in: c))
        case .natural(let file, let key, let sea): plan = await BadgeNatural.plan(file: file, key: key, sea: sea)
        case .arctic: plan = BadgeFlat.Plan(plane: .pole(edge: 62), sea: true)
        case .swirl: swirl = true
        case .medal: break
        case .struck(let t): number = t
        }
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer { NSLog("wya badgeflat %@ %d px %.0f ms", form.key, px, (CACurrentMediaTime() - t0) * 1000) }
        #endif
        let p = plan, n = number, sw = swirl
        return await Task.detached(priority: .userInitiated) { BadgeFlat.render(p, number: n, swirl: sw, level: level, px: px, scale: scale) }.value
    }

    private func render3D(_ form: BadgeForm, _ level: BadgeLevel, px: Int, scale: CGFloat) async -> UIImage? {
        // (a set of places too spread to read as one shape is a medal)
        #if DEBUG
        let t0 = CACurrentMediaTime()
        #endif
        guard let device, px > 0,
              let body = BadgeSolid.make(form, level, world: world) ?? BadgeSolid.make(.medal, level, world: world) else { return nil }
        #if DEBUG
        let t1 = CACurrentMediaTime()
        #endif
        let light = await environment()
        #if DEBUG
        let t2 = CACurrentMediaTime()
        defer { NSLog("wya badgeart %@ make %.0f light %.0f render %.0f ms", form.key, (t1 - t0) * 1000, (t2 - t1) * 1000, (CACurrentMediaTime() - t2) * 1000) }
        #endif
        do {
            let r: RealityRenderer
            if let have = renderer { r = have } else {
                r = try RealityRenderer()
                r.cameraSettings.colorBackground = .color(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
                camera.camera.fieldOfViewInDegrees = BadgeSolid.fov
                r.entities.append(camera)
                r.entities.append(root)
                r.activeCamera = camera
                renderer = r
            }
            r.lighting.resource = light
            r.lighting.intensityExponent = Self.exponent(level)
            root.children.removeAll()
            body.orientation = BadgeSolid.rest
            root.addChild(body)
            let b = body.visualBounds(relativeTo: nil)
            camera.position = [b.center.x, b.center.y, b.center.z + BadgeSolid.distance(b)]
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: px, height: px, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .shared
            guard let tex = device.makeTexture(descriptor: d) else { return nil }
            let out = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: tex))
            // (resumed once: by the GPU's finish, or after 5 s if it never comes, so one lost picture never holds up
            // the rest)
            let once = ResumeOnce()
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                do {
                    try r.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: out, onComplete: { _ in
                        if once.take() { c.resume() }
                    })
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if once.take() { c.resume(throwing: CancellationError()) } }
                } catch { if once.take() { c.resume(throwing: error) } }
            }
            root.children.removeAll()
            return Self.picture(tex, scale: scale)
        } catch {
            print("wya badges: a badge's picture failed: \(error)")
            return nil
        }
    }

    private nonisolated final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    private static func picture(_ tex: MTLTexture, scale: CGFloat) -> UIImage? {
        let w = tex.width, h = tex.height, row = w * 4
        var bytes = [UInt8](repeating: 0, count: row * h)
        tex.getBytes(&bytes, bytesPerRow: row, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}

/// a badge as its picture (nothing while the picture is being made: never a stand-in drawn in its place)
struct BadgeArtView: View {
    let badge: Badge
    let size: CGFloat
    @State private var img: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let form = BadgeArt.shared.form(badge), level = BadgeLevel.of(badge)
        let px = Int((size * scale).rounded())
        ZStack {
            if let shown = img ?? BadgeArt.shared.cached(form, level, px: px) {
                Image(uiImage: shown).resizable().interpolation(.high).scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(form.key)|\(level.rawValue)|\(px)") {
            img = await BadgeArt.shared.image(form, level, px: px, scale: scale)
        }
    }
}

/// ONE BADGE, LIVE: the same solid in the same light, turned by a finger (round its upright and leaning), settling
/// back to rest when let go; it never moves on its own. Its picture stands under it until the solid is up.
struct BadgeLiveView: View {
    let badge: Badge
    let size: CGFloat
    /// the moment it is earned (it comes with its page; flat now, nothing turns)
    var intro = false

    var body: some View {
        BadgeArtView(badge: badge, size: size)
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(badge.name), \(Badges.levelName[min(badge.level, 5)])")
    }
}

/// the finger's turn of the one live badge
@MainActor @Observable
final class BadgeTurn {
    @ObservationIgnored var pivot: Entity?
    var live = false
    func turn(_ yaw: Float, _ pitch: Float) {
        guard let pivot else { return }
        pivot.stopAllAnimations()
        pivot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: max(-0.7, min(0.7, pitch)), axis: [1, 0, 0])
    }
    func settle() {
        guard let pivot else { return }
        var t = pivot.transform
        t.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        pivot.move(to: t, relativeTo: pivot.parent, duration: 0.7, timingFunction: .easeOut)
    }
}

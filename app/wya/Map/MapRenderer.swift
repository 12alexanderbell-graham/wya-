import MetalKit
import SwiftUI
import simd

/// Draws the world each frame:
/// 1. the sea, by depth, on a one-degree grid in Equal Earth
/// 2. every country's rings into the stencil (even-odd fans), then the land by height inside them
/// 3. each coloured group (stamped lime, wished blue, pressed grey) the same way, on top
/// 4. the lakes
/// 5. borders and coasts, 0.5 pt at every zoom; disputed lines dashed
/// 6. the polar lights
@MainActor
final class MapRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let controller: MapController

    private var fanPipe: MTLRenderPipelineState!
    private var reliefPipe: MTLRenderPipelineState!
    private var linePipe: MTLRenderPipelineState!
    private var auroraPipe: MTLRenderPipelineState!
    private var diamondPipe: MTLRenderPipelineState!
    private var townDotPipe: MTLRenderPipelineState?
    /// the lines' coverage, drawn first into `coverage` (max at each pixel), then laid over the map once
    private var coveragePipe: MTLRenderPipelineState?
    /// a country's own map (Regions, Places): its shape as a mask, and the lines composited through it
    private var compositeFocusPipe: MTLRenderPipelineState?
    private var maskPipe: MTLRenderPipelineState?
    private var focusMask: MTLTexture?
    /// the borders between regions, drawn in and out along their length (A6.9)
    private var regionCoveragePipe: MTLRenderPipelineState?
    private var compositePipe: MTLRenderPipelineState?
    private var coverage: MTLTexture?
    /// the relief laid over what is drawn at a strength (the land round a continent coming over its borders)
    private var sampler: MTLSamplerState!

    private var noStencil: MTLDepthStencilState!
    private var markLand: MTLDepthStencilState!      // invert bit 1
    private var insideLand: MTLDepthStencilState!    // test bit 1
    private var markGroup: MTLDepthStencilState!     // invert bit 2
    private var insideGroup: MTLDepthStencilState!   // test bit 2, clear it

    private var points: MTLBuffer?
    private var fanIndex: MTLBuffer?
    /// each unit's run in the fan index buffer; the land's whole run; the lakes' run
    private var unitRun: [(start: Int, count: Int)] = []
    private var landRun = (start: 0, count: 0)
    private var lakeRun = (start: 0, count: 0)
    /// each place's units
    private var placeUnits: [Int: [Int]] = [:]
    private var segs: MTLBuffer?
    private var segCount = 0
    private var grid: MTLBuffer?
    private var gridIndex: MTLBuffer?
    private var gridCount = 0
    private var reliefTex: MTLTexture?
    private var texel = SIMD2<Float>(0, 0)

    private var last: CFTimeInterval = 0
    private let start = CACurrentMediaTime()
    private var built = false

    init?(controller: MapController) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        device = d; queue = q; self.controller = controller
        super.init()
    }

    func configure(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .stencil8
        view.sampleCount = 4
        let deep = Palette.blueV
        view.clearColor = MTLClearColor(red: Double(deep.x), green: Double(deep.y), blue: Double(deep.z), alpha: 1)
        view.clearStencil = 0
        view.preferredFramesPerSecond = 120
        view.isOpaque = true
        buildPipelines(view)
    }

    private func buildPipelines(_ view: MTKView) {
        // compiled at launch from the shader source in the bundle, so the map never depends on Xcode's Metal toolchain
        guard let url = Bundle.main.url(forResource: "MapShaders", withExtension: "metalsrc"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            print("wya map: MapShaders.metalsrc is missing from the bundle"); return
        }
        let lib: MTLLibrary
        do { lib = try device.makeLibrary(source: src, options: nil) } catch {
            // loud in a test build: a shader that does not compile leaves the map blank
            print("wya map: shader compile failed: \(error)"); assertionFailure("MapShaders.metalsrc does not compile"); return
        }
        func pipe(_ v: String, _ f: String, colour: Bool, blend: Bool) -> MTLRenderPipelineState? {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = lib.makeFunction(name: v)
            p.fragmentFunction = lib.makeFunction(name: f)
            p.rasterSampleCount = view.sampleCount
            p.colorAttachments[0].pixelFormat = view.colorPixelFormat
            p.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
            if !colour { p.colorAttachments[0].writeMask = [] }
            if blend {
                let c = p.colorAttachments[0]!
                c.isBlendingEnabled = true
                c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
                c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: p)
        }
        fanPipe = pipe("fanVertex", "fanFragment", colour: false, blend: false)
        reliefPipe = pipe("reliefVertex", "reliefFragment", colour: true, blend: false)
        linePipe = pipe("lineVertex", "lineFragment", colour: true, blend: true)
        auroraPipe = pipe("fullVertex", "auroraFragment", colour: true, blend: true)
        diamondPipe = pipe("diamondVertex", "diamondFragment", colour: true, blend: true)
        townDotPipe = pipe("townDotVertex", "townDotFragment", colour: true, blend: true)
        compositePipe = pipe("fullVertex", "lineComposite", colour: true, blend: true)
        compositeFocusPipe = pipe("fullVertex", "lineCompositeFocus", colour: true, blend: true)
        if let vf = lib.makeFunction(name: "fanVertex"), let ff = lib.makeFunction(name: "maskFragment") {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = vf; p.fragmentFunction = ff
            p.rasterSampleCount = 1
            let c = p.colorAttachments[0]!
            c.pixelFormat = .r8Unorm
            // one minus what is there: the fans fill even-odd
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
            c.sourceRGBBlendFactor = .oneMinusDestinationColor; c.sourceAlphaBlendFactor = .oneMinusDestinationAlpha
            c.destinationRGBBlendFactor = .zero; c.destinationAlphaBlendFactor = .zero
            maskPipe = try? device.makeRenderPipelineState(descriptor: p)
        }
        if let vf = lib.makeFunction(name: "lineVertex"), let ff = lib.makeFunction(name: "lineCoverage") {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = vf; p.fragmentFunction = ff
            p.rasterSampleCount = 1
            let c = p.colorAttachments[0]!
            c.pixelFormat = .r8Unorm
            c.isBlendingEnabled = true
            c.rgbBlendOperation = .max; c.alphaBlendOperation = .max
            c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .one
            coveragePipe = try? device.makeRenderPipelineState(descriptor: p)
            if let rv = lib.makeFunction(name: "regionLineVertex") {
                p.vertexFunction = rv
                regionCoveragePipe = try? device.makeRenderPipelineState(descriptor: p)
            }
        }

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .repeat; sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)

        func state(_ f: MTLCompareFunction, read: UInt32, write: UInt32, pass: MTLStencilOperation) -> MTLDepthStencilState? {
            let s = MTLStencilDescriptor()
            s.stencilCompareFunction = f
            s.readMask = read; s.writeMask = write
            s.depthStencilPassOperation = pass
            s.stencilFailureOperation = .keep
            s.depthFailureOperation = .keep
            let d = MTLDepthStencilDescriptor()
            d.frontFaceStencil = s; d.backFaceStencil = s
            return device.makeDepthStencilState(descriptor: d)
        }
        noStencil = device.makeDepthStencilState(descriptor: MTLDepthStencilDescriptor())
        markLand = state(.always, read: 0, write: 1, pass: .invert)
        insideLand = state(.equal, read: 1, write: 0, pass: .keep)
        markGroup = state(.always, read: 0, write: 2, pass: .invert)
        insideGroup = state(.equal, read: 2, write: 2, pass: .zero)
    }

    /// once the world is loaded: the buffers
    private func build() {
        guard let w = controller.world, let r = controller.relief else { return }
        // a rebuild for another borders view starts from nothing of the old one's
        placeUnits = [:]
        awayCache = [:]
        points = device.makeBuffer(bytes: w.points, length: w.points.count * MemoryLayout<SIMD2<Float>>.stride)
        var idx: [UInt32] = []
        idx.reserveCapacity(w.points.count * 3)
        func fans(_ ringIDs: [Int]) {
            for ri in ringIDs {
                let rg = w.rings[ri]
                guard rg.count >= 3 else { continue }
                let s = UInt32(rg.start)
                for i in 1 ..< rg.count - 1 { idx += [s, s + UInt32(i), s + UInt32(i + 1)] }
            }
        }
        unitRun = []
        for u in 0 ..< w.unitRings.count {
            let s = idx.count
            fans(w.unitRings[u])
            unitRun.append((s, idx.count - s))
            let owner = w.unitOwner[u]
            if owner >= 0 { placeUnits[owner, default: []].append(u) }
        }
        landRun = (0, idx.count)
        let ls = idx.count
        fans(w.lakeRings)
        lakeRun = (ls, idx.count - ls)
        fanIndex = device.makeBuffer(bytes: idx, length: idx.count * 4)
        // the world's segments in the lines' layout (ends, the same ends as the morph's start: the world never morphs,
        // its distance along, its kind)
        var s10: [Float] = []
        s10.reserveCapacity(w.segments.count / 6 * 10)
        for i in stride(from: 0, to: w.segments.count - 5, by: 6) {
            let g = w.segments[i ..< i + 6].map { $0 }
            s10 += [g[0], g[1], g[2], g[3], g[0], g[1], g[2], g[3], g[4], g[5]]
        }
        segs = device.makeBuffer(bytes: s10, length: s10.count * 4)
        segCount = s10.count / 10

        // the relief grid, one point a degree, laid in Equal Earth
        var g: [Float] = []
        // past the date line the sea carries on as open ocean, so the curved edge of the projection is never seen; the
        // grid runs 90° further each way
        let nx = 540, ny = 180
        for row in 0 ... ny {
            let lat = 90.0 - Double(row)
            for col in 0 ... nx {
                let lon = -270.0 + Double(col)
                let p = EqualEarth.project(lon: lon, lat: lat)
                g += [p.x, p.y, Float((lon + 180) / 360), Float((90 - lat) / 180)]
            }
        }
        var gi: [UInt32] = []
        for row in 0 ..< ny {
            for col in 0 ..< nx {
                let a = UInt32(row * (nx + 1) + col), b = a + 1, d = a + UInt32(nx + 1), e = d + 1
                gi += [a, b, d, b, e, d]
            }
        }
        grid = device.makeBuffer(bytes: g, length: g.count * 4)
        gridIndex = device.makeBuffer(bytes: gi, length: gi.count * 4)
        gridCount = gi.count

        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: r.width, height: r.height, mipmapped: false)
        td.usage = .shaderRead
        if let t = device.makeTexture(descriptor: td) {
            r.bytes.withUnsafeBytes { raw in
                t.replace(region: MTLRegionMake2D(0, 0, r.width, r.height), mipmapLevel: 0,
                          withBytes: raw.baseAddress!, bytesPerRow: r.width * 2)
            }
            reliefTex = t
        }
        texel = SIMD2(1 / Float(r.width), 1 / Float(r.height))
        let d = DetailMaps(device: device, world: w)
        d.onReady = { [weak controller] in controller?.needsFrame = true }
        detail = d
        controller.details = d
        builtWorld = w
        built = true
    }
    /// the world the buffers were made from: a borders view change gives the controller a new one (made off the main
    /// thread), and the next frame builds from it, so the old map stays on screen until the new one is complete
    private weak var builtWorld: World?

    /// the slices: the detailed outlines for the zoom (nil until the world has loaded)
    private var detail: DetailMaps?

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        controller.view = view.bounds.size
        controller.needsFrame = true
    }

    struct Cam { var c: SIMD2<Float>; var k: Float; var time: Float; var view: SIMD2<Float>; var pad = SIMD2<Float>(0, 0) }
    struct Look { var tint: SIMD4<Float>; var kind: Float; var texelU: Float; var texelV: Float; var pad: Float = 0
                  var clip = SIMD4<Float>(0, 0, 0, 0); var clip2 = SIMD4<Float>(1, 0, 0, 0) }
    struct LineStyle { var colour: SIMD4<Float>; var width: Float; var feather: Float; var dash: Float; var gap: Float }
    struct AuroraU { var yNorth: Float; var ySouth: Float; var bottom: Float; var strength: Float; var pin: Float = 0; var away: Float = 0 }

    /// THE CONTINENT'S FLAT BLUE: on a continent's map the sea and the rest of the world's land go into one flat blue,
    /// our blue 60% on cream (the old flatP), over half a second on the old continent curve, cubic-bezier(.3, 0, .3,
    /// 1), and come back the same way. What is away is worked out piece by piece: a country across two continents is
    /// drawn as its pieces, so on Europe's map Russia is Russia to the Urals (the old pieceItems).
    private var flatFrom: Float = 0, flatTo: Float = 0, flatAt: CFTimeInterval = -10
    private var awayKey: String?
    private func flatNow(_ now: CFTimeInterval) -> Float {
        flatFrom + (flatTo - flatFrom) * Float(Motion.blend((now - flatAt) / 0.5))
    }
    /// REGIONS' SELECTION MENU (A6.5): the aurora's bands move out past the screen's top and bottom edges and the
    /// diamonds shrink into their points while the menu is up, and come back the same way; on the water's settle
    /// (critically damped, 0.47 / 0.82 / 0.95 of the way at 25 / 50 / 75% of 0.42 s), from wherever they are
    private var menuFrom: Float = 0, menuTo: Float = 0, menuAt: CFTimeInterval = -10
    private func menuNow(_ now: CFTimeInterval) -> Float {
        let x = max(0, now - menuAt) * 15.2
        return menuFrom + (menuTo - menuFrom) * Float(1 - exp(-x) * (1 + x))
    }
    private var awayCache: [String: (units: [Int], places: Set<Int>)] = [:]
    /// each place's towns' buffers (points, fan index), made once per scene
    private var townBuffers: [String: (scene: TownScene, points: MTLBuffer, fans: MTLBuffer)] = [:]
    /// the open country's plain towns and its dots, kept until the marks or the pressed town change
    private var plainCache: (key: String, list: [Int])?
    private var dotCache: (key: String, buffer: MTLBuffer?, count: Int)?
    /// a focus key ("place:12", Regions) and its place
    static func focus(_ k: String) -> Int? { k.hasPrefix("place:") ? Int(k.dropFirst(6)) : nil }

    /// THE REGION MAP'S BUFFERS (6.5), made once per scene
    private weak var regionBuilt: RegionScene?
    private var regionMarksBuilt = -1
    private weak var regionMarksScene: RegionScene?
    private var regionStampedIndex: (MTLBuffer, Int)?, regionWishedIndex: (MTLBuffer, Int)?
    private var regionPoints: MTLBuffer?
    private var regionFans: MTLBuffer?
    /// the three sets of the borders' change and the change they were made for
    private weak var linesBuilt: RegionLines?
    private var linesShared: MTLBuffer?, linesNew: MTLBuffer?, linesOld: MTLBuffer?
    private func buildLines(_ l: RegionLines) {
        linesBuilt = l
        func buf(_ a: [Float]) -> MTLBuffer? { a.isEmpty ? nil : device.makeBuffer(bytes: a, length: a.count * 4) }
        linesShared = buf(l.shared); linesNew = buf(l.new); linesOld = buf(l.old)
    }
    private func buildRegion(_ s: RegionScene) {
        regionBuilt = s
        regionPoints = s.points.isEmpty ? nil : device.makeBuffer(bytes: s.points, length: s.points.count * MemoryLayout<SIMD2<Float>>.stride)
        regionFans = s.fans.isEmpty ? nil : device.makeBuffer(bytes: s.fans, length: s.fans.count * 4)
    }
    /// the world's units away from continent k (a sliced country's other piece among them), and the places wholly away
    private func away(_ k: String, _ w: World) -> (units: [Int], places: Set<Int>) {
        if let a = awayCache[k] { return a }
        // Regions (6.4): everything but the one country
        if let fp = Self.focus(k) {
            let units = w.unitOwner.indices.filter { w.unitOwner[$0] != fp }
            let a = (units, Set(w.places.indices.filter { $0 != fp }))
            awayCache[k] = a
            return a
        }
        let units = w.unitConts.indices.filter { !w.unitConts[$0].contains(k) }
        let places = Set(w.places.indices.filter { !w.inCont($0, k) })
        awayCache[k] = (units, places)
        return (units, places)
    }

    /// THE LIGHTS' PATH: the real auroral ovals, rings about 23° round the geomagnetic poles (80.7°N 72.7°W and
    /// 80.7°S 107.3°E), so on the map they dip to Hudson Bay and Labrador and ride high over Siberia, and in the south
    /// come up towards Tasmania. Each ring is laid out as one y per slice of the map's width (plus how much of the slice
    /// it covers, so it ends softly at the world's edge).
    static let auroraBins = 200
    private lazy var auroraTable: [SIMD2<Float>] = Self.oval(poleLat: 80.7, poleLon: -72.7) + Self.oval(poleLat: -80.7, poleLon: 107.3)
    private static func oval(poleLat: Double, poleLon: Double, radius: Double = 23) -> [SIMD2<Float>] {
        let n = auroraBins
        var sum = [Double](repeating: 0, count: n), hits = [Double](repeating: 0, count: n)
        let p1 = poleLat * .pi / 180, l1 = poleLon * .pi / 180, d = radius * .pi / 180
        for i in 0 ..< 7200 {
            let b = Double(i) / 7200 * 2 * .pi
            let p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(b))
            let l2 = remainder(l1 + atan2(sin(b) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2)), 2 * .pi)
            let q = EqualEarth.project(lon: l2 * 180 / .pi, lat: p2 * 180 / .pi)
            let bin = Int(Double(q.x) / 1000 * Double(n))
            guard bin >= 0, bin < n else { continue }
            sum[bin] += Double(q.y); hits[bin] += 1
        }
        let covered = (0 ..< n).filter { hits[$0] > 0 }
        guard let first = covered.first, let last = covered.last else { return Array(repeating: .zero, count: n) }
        var y = [Double](repeating: 0, count: n)
        for i in covered { y[i] = sum[i] / hits[i] }
        // fill the slices between hits, and hold the ends flat past them
        var prev = first
        for i in covered.dropFirst() {
            if i - prev > 1 { for j in prev + 1 ..< i { y[j] = y[prev] + (y[i] - y[prev]) * Double(j - prev) / Double(i - prev) } }
            prev = i
        }
        for j in 0 ..< first { y[j] = y[first] }
        for j in last + 1 ..< n { y[j] = y[last] }
        return (0 ..< n).map { i in
            // fades out over the last few slices at either end, where the world itself ends
            let edge = Double(min(i - first, last - i))
            let cover = i < first || i > last ? 0 : min(1, max(0, edge / 5))
            return SIMD2(Float(y[i]), Float(cover))
        }
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = last == 0 ? 1.0 / 120 : min(0.05, now - last)
        last = now
        if controller.view != view.bounds.size { controller.view = view.bounds.size }
        let moving = controller.step(dt)
        // the Places map's names (7.4), placed for this frame's camera
        (view as? MapMTKView)?.townNames.update(controller, moving: moving || controller.touching)
        // 120 a second while anything moves, 30 for the lights alone
        view.preferredFramesPerSecond = (moving || controller.touching || controller.needsFrame) ? 120 : 30
        controller.needsFrame = false

        guard controller.ready, fanPipe != nil, reliefPipe != nil, linePipe != nil, auroraPipe != nil, markLand != nil else { return }
        if !built || (builtWorld !== controller.world && controller.world != nil) { build() }
        guard built, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(), let w = controller.world else { return }
        if let sc = controller.regionScene, regionBuilt !== sc { buildRegion(sc) }
        if let l = controller.regionLines, linesBuilt !== l { buildLines(l) }

        var cam = Cam(c: SIMD2(Float(controller.c.x), Float(controller.c.y)), k: Float(controller.k),
                      time: Float(now - start), view: SIMD2(Float(view.bounds.width), Float(view.bounds.height)))
        // the slices for this zoom, or nil for the world's own outlines
        let tiles = detail?.visible(c: controller.c, k: controller.k, view: view.bounds.size)
        // a level that came in late settles over 0.35 s: drawn at the full rate until it has
        if detail?.settling == true { controller.needsFrame = true }
        // borders and coasts: one thickness at every zoom (BUILD-BOOK 1.4), 50% black
        var ls = LineStyle(colour: SIMD4(0, 0, 0, 0.5), width: 0.5, feather: 0.6, dash: 3, gap: 2)
        // 0. the lines' coverage first, in a pass of its own (see lineCoverage)
        let tw = drawable.texture.width, th = drawable.texture.height
        if coverage == nil || coverage!.width != tw || coverage!.height != th {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: tw, height: th, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]
            td.storageMode = .private
            coverage = device.makeTexture(descriptor: td)
        }
        if let cov = coverage, let cp = coveragePipe {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = cov
            d.colorAttachments[0].loadAction = .clear
            d.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            d.colorAttachments[0].storeAction = .store
            if let ce = cb.makeRenderCommandEncoder(descriptor: d) {
                ce.setRenderPipelineState(cp)
                ce.setVertexBytes(&cam, length: MemoryLayout<Cam>.stride, index: 1)
                func lines(_ set: [DetailTile]?, morph: Float) {
                    var st = ls
                    st.colour.w = 1
                    var m = morph
                    ce.setVertexBytes(&st, length: MemoryLayout<LineStyle>.stride, index: 2)
                    ce.setVertexBytes(&m, length: 4, index: 3)
                    ce.setFragmentBytes(&st, length: MemoryLayout<LineStyle>.stride, index: 0)
                    if let set {
                        for t in set where t.segCount > 0 {
                            ce.setVertexBuffer(t.segs, offset: 0, index: 0)
                            ce.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: t.segCount)
                        }
                    } else if segCount > 0 {
                        ce.setVertexBuffer(segs, offset: 0, index: 0)
                        ce.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: segCount)
                    }
                }
                // the level's lines, at their place in the morph (DetailMaps.visible): one set, never two
                if let d = detail {
                    for set in d.lineSets { lines(set.tiles, morph: set.morph) }
                } else {
                    lines(nil, morph: 1)
                }
                // THE BORDERS BETWEEN REGIONS (A6.7, A6.9, A6.13): shared ones as they are, new ones drawing in from both
                // their ends, old ones undrawing back into them, 0.4 s on the camera curve
                if let l = controller.regionLines, linesBuilt === l, let rp = regionCoveragePipe {
                    var st = ls
                    st.colour.w = 1
                    ce.setRenderPipelineState(rp)
                    ce.setVertexBytes(&st, length: MemoryLayout<LineStyle>.stride, index: 2)
                    ce.setFragmentBytes(&st, length: MemoryLayout<LineStyle>.stride, index: 0)
                    let dur = 0.4 * RegionLines.slow
                    let tIn = (now - l.start - l.delay * RegionLines.slow) / dur, tOut = (now - l.start) / dur
                    if tIn < 1 || tOut < 1 { controller.needsFrame = true }
                    func set(_ b: MTLBuffer?, _ count: Int, _ q: Float) {
                        guard let b, count > 0, q > 0.001 else { return }
                        var q = q
                        ce.setVertexBytes(&q, length: 4, index: 3)
                        ce.setVertexBuffer(b, offset: 0, index: 0)
                        ce.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count * 2)
                    }
                    set(linesShared, l.shared.count / 10, 1)
                    set(linesNew, l.new.count / 10, Float(Motion.camera(max(0, tIn))))
                    set(linesOld, l.old.count / 10, 1 - Float(Motion.camera(max(0, tOut))))
                }
                ce.endEncoding()
            }
        }
        // THE OPEN COUNTRY'S MASK (Regions, Places): its shape, so the lines outside it can go with the rest of the world
        let ck0 = controller.drawnContinent ?? controller.focusPlace.map { "place:\($0)" }
        if let ck0 { awayKey = ck0 }
        var maskOn = false
        if let fp = awayKey.flatMap(Self.focus), flatNow(now) > 0.001, let mp = maskPipe {
            if focusMask == nil || focusMask!.width != tw || focusMask!.height != th {
                let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: tw, height: th, mipmapped: false)
                td.usage = [.renderTarget, .shaderRead]
                td.storageMode = .private
                focusMask = device.makeTexture(descriptor: td)
            }
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = focusMask
            d.colorAttachments[0].loadAction = .clear
            d.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            d.colorAttachments[0].storeAction = .store
            if focusMask != nil, let me = cb.makeRenderCommandEncoder(descriptor: d) {
                me.setRenderPipelineState(mp)
                me.setVertexBytes(&cam, length: MemoryLayout<Cam>.stride, index: 1)
                if let tiles {
                    var m = detail?.morph ?? 1
                    me.setVertexBytes(&m, length: 4, index: 3)
                    for t in tiles {
                        me.setVertexBuffer(t.points, offset: 0, index: 0)
                        me.setVertexBuffer(t.from, offset: 0, index: 2)
                        for it in t.items where it.place == fp && it.count > 0 {
                            me.drawIndexedPrimitives(type: .triangle, indexCount: it.count, indexType: .uint32, indexBuffer: t.fans,
                                                     indexBufferOffset: it.start * 4)
                        }
                    }
                } else if let pts = points, let fi = fanIndex {
                    var one: Float = 1
                    me.setVertexBytes(&one, length: 4, index: 3)
                    me.setVertexBuffer(pts, offset: 0, index: 0)
                    me.setVertexBuffer(pts, offset: 0, index: 2)
                    for u in placeUnits[fp] ?? [] where unitRun[u].count > 0 {
                        me.drawIndexedPrimitives(type: .triangle, indexCount: unitRun[u].count, indexType: .uint32, indexBuffer: fi,
                                                 indexBufferOffset: unitRun[u].start * 4)
                    }
                }
                me.endEncoding()
                maskOn = true
            }
        }
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setVertexBytes(&cam, length: MemoryLayout<Cam>.stride, index: 1)
        enc.setFragmentBytes(&cam, length: MemoryLayout<Cam>.stride, index: 1)

        func relief(_ kind: Float, _ tint: SIMD4<Float> = .zero, pattern: Float = 0) {
            var look = Look(tint: tint, kind: kind, texelU: texel.x, texelV: texel.y)
            // Differentiate Without Colour (1.14): the pattern in screen points
            if pattern > 0 { look.clip2.z = pattern; look.clip2.x = Float(view.contentScaleFactor) }
            // clip2.y: Map settings' Style Simple (flat cream land, blue 25% on cream sea)
            look.clip2.y = controller.simple ? 1 : 0
            enc.setRenderPipelineState(reliefPipe)
            enc.setVertexBuffer(grid, offset: 0, index: 0)
            enc.setFragmentTexture(reliefTex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setFragmentBytes(&look, length: MemoryLayout<Look>.stride, index: 0)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: gridCount, indexType: .uint32, indexBuffer: gridIndex!, indexBufferOffset: 0)
        }
        func fan(_ run: (start: Int, count: Int)) {
            guard run.count > 0 else { return }
            enc.setRenderPipelineState(fanPipe)
            enc.setVertexBuffer(points, offset: 0, index: 0)
            enc.setVertexBuffer(points, offset: 0, index: 2)
            var one: Float = 1
            enc.setVertexBytes(&one, length: 4, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: run.count, indexType: .uint32, indexBuffer: fanIndex!,
                                      indexBufferOffset: run.start * 4)
        }

        // the continent's flat blue now: eased from where it is to where it is going over half a second
        let ck = controller.drawnContinent ?? controller.focusPlace.map { "place:\($0)" }
        if let ck { awayKey = ck }
        let goal: Float = ck == nil ? 0 : 1
        if goal != flatTo { flatFrom = flatNow(now); flatTo = goal; flatAt = now }
        let flat = flatNow(now)
        if now - flatAt < 0.55 { controller.needsFrame = true }
        let menuGoal: Float = controller.regionsMenu ? 1 : 0
        if menuGoal != menuTo { menuFrom = menuNow(now); menuTo = menuGoal; menuAt = now }
        let menu = menuNow(now)
        if now - menuAt < 0.7 { controller.needsFrame = true }

        // 1. the sea, and the lights over it; the sea keeps its relief on a continent too
        enc.setDepthStencilState(noStencil)
        relief(0)
        // the lights, on the real ovals big: from the top edge down to 56°N, from the bottom edge up to 50°S, so it is
        // seen over the northern seas and all round the Southern Ocean (under the land, where there is land) ON A
        // CONTINENT THE BANDS ARE PINNED TO THE SCREEN: each band's outer end on the screen's edge and its inner end at
        // 0.34 of the height from the top (north) and 0.27 from the bottom (south), reached with the continent's blend;
        // only the inner end moves, nothing flies across
        let H = Double(view.bounds.height), k = controller.k, cy = controller.c.y
        let pinNorth = Float(cy + (0.34 * H - H / 2) / k), pinSouth = Float(cy + (0.73 * H - H / 2) / k)
        let worldNorth = EqualEarth.project(lon: 0, lat: 56).y, worldSouth = EqualEarth.project(lon: 0, lat: -50).y
        var au = AuroraU(yNorth: worldNorth + (pinNorth - worldNorth) * flat, ySouth: worldSouth + (pinSouth - worldSouth) * flat,
                         bottom: Float(controller.bottom), strength: 1.0, pin: flat, away: menu)
        enc.setRenderPipelineState(auroraPipe)
        enc.setFragmentBytes(&au, length: MemoryLayout<AuroraU>.stride, index: 2)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        func tileFans(_ t: DetailTile, start: Int, count: Int) {
            guard count > 0 else { return }
            enc.setRenderPipelineState(fanPipe)
            enc.setVertexBuffer(t.points, offset: 0, index: 0)
            enc.setVertexBuffer(t.from, offset: 0, index: 2)
            var m = detail?.morph ?? 1
            enc.setVertexBytes(&m, length: 4, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: t.fans,
                                      indexBufferOffset: start * 4)
        }
        // 2. the land
        enc.setDepthStencilState(markLand)
        if let tiles { for t in tiles { tileFans(t, start: 0, count: t.fanCount) } } else { fan(landRun) }
        enc.setDepthStencilState(insideLand); enc.setStencilReferenceValue(1)
        relief(1)
        // 3. the coloured groups
        func group(_ places: [Int], kind: Float, tint: SIMD4<Float>, pattern: Float = 0) {
            guard !places.isEmpty else { return }
            if let tiles {
                let set = Set(places)
                enc.setDepthStencilState(markGroup)
                var any = false
                for t in tiles {
                    for it in t.items where set.contains(it.place) { tileFans(t, start: it.start, count: it.count); any = true }
                }
                guard any else { return }
            } else {
                let units = places.flatMap { placeUnits[$0] ?? [] }
                guard !units.isEmpty else { return }
                enc.setDepthStencilState(markGroup)
                for u in units { fan(unitRun[u]) }
            }
            enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
            relief(kind, tint, pattern: pattern)
        }
        // Differentiate Without Colour (the system setting, 1.14): stamped hatched, wished dotted
        let dwc = controller.withoutColour
        let hatch: Float = dwc ? 1 : 0, dots: Float = dwc ? 2 : 0
        // the place being pressed: drawn by the press below, not by its group
        // under a finger, or held while its stamping card is up
        let pressed = controller.pressed ?? controller.kept ?? controller.menuHeld
        // Style Simple (Part 1.4): an unmarked territory is white with its full lines, every other unmarked land cream
        // (the diamonds' rule, the old MapStyle.fill); Detailed draws all land by its relief
        if controller.simple {
            let marked = (controller.showsStamped ? controller.stamped : []).union(controller.showsWished ? controller.wished : [])
            group(controller.territories.filter { !marked.contains($0) && $0 != pressed }, kind: 2, tint: Palette.whiteV)
        }
        // PLACES (7.4): countries' fills drained so towns read
        let placesOn = controller.placesMode
        // Stamped+ and Wishlist+ (1.14): each place by its passes (lime by visits, ink where you lived; blue by want)
        if placesOn {
        } else if controller.filter == 2 {
            let sp = controller.stampPasses
            let st = controller.stamped.filter { $0 != pressed }
            group(st.filter { sp[$0] == 0 }.sorted(), kind: 2, tint: Palette.inkV)
            for n in 1 ... 5 { group(st.filter { (sp[$0] ?? 2) == n }.sorted(), kind: 2, tint: Palette.passes(Palette.limeV, n), pattern: hatch) }
        } else if controller.showsStamped {
            group(controller.stamped.filter { $0 != pressed }.sorted(), kind: 2, tint: Palette.limeV, pattern: hatch)
        }
        if placesOn {
        } else if controller.filter == 3 {
            let wp = controller.wantPasses
            let wi = controller.wished.filter { $0 != pressed }
            for n in 1 ... 5 { group(wi.filter { (wp[$0] ?? 1) == n }.sorted(), kind: 2, tint: Palette.passes(Palette.blueV, n), pattern: dots) }
        } else if controller.showsWished {
            group(controller.wished.filter { $0 != pressed }.sorted(), kind: 2, tint: Palette.blueV, pattern: dots)
        }
        // finds (9.4): darkened as a press darkens, over their own colour (a wished one stays blue under the shade); a
        // stamped place is never a find (its row reads "+n trips" instead)
        if !controller.found.isEmpty, !placesOn {
            let shade = SIMD4<Float>(0.80, 0.79, 0.77, 1)
            let f = controller.found.subtracting(controller.stamped).filter { $0 != pressed }
            let blue = controller.showsWished ? f.intersection(controller.wished) : []
            group(f.subtracting(blue).sorted(), kind: 2, tint: Palette.whiteV * shade)
            group(blue.sorted(), kind: 2, tint: Palette.blueV * shade)
        }
        // the press darkens the relief under your finger, keeping the country's own colour (A1.1): the whole place at
        // once
        func mark(_ i: Int) -> Bool {
            if let tiles {
                var any = false
                enc.setDepthStencilState(markGroup)
                for t in tiles { for it in t.items where it.place == i { tileFans(t, start: it.start, count: it.count); any = true } }
                return any
            }
            guard let units = placeUnits[i], !units.isEmpty else { return false }
            enc.setDepthStencilState(markGroup)
            for u in units { fan(unitRun[u]) }
            return true
        }
        if !placesOn, let p = pressed, mark(p) {
            let look = controller.look(of: p, stamped: controller.stamped, wished: controller.wished, filter: controller.filter)
            let base: SIMD4<Float>? = look == .lime ? Palette.limeV : look == .blue ? Palette.blueV : nil
            let shade = SIMD4<Float>(0.80, 0.79, 0.77, 1)
            enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
            relief(2, (base ?? Palette.whiteV) * shade)
        }
        // 3b. THE REGIONS (6.5): over the country, its regions: plain land, then yours lime and wished blue, the one under
        // the finger darkened in its own colour (never outlined)
        if let sc = controller.regionScene, regionBuilt === sc, let rp = regionPoints, let rf = regionFans {
            func regionFan(_ entries: [Int]) -> Bool {
                var any = false
                enc.setRenderPipelineState(fanPipe)
                enc.setVertexBuffer(rp, offset: 0, index: 0)
                enc.setVertexBuffer(rp, offset: 0, index: 2)
                var one: Float = 1
                enc.setVertexBytes(&one, length: 4, index: 3)
                for e in entries {
                    let r = sc.runs[e]
                    guard r.count > 0 else { continue }
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: r.count, indexType: .uint32, indexBuffer: rf,
                                              indexBufferOffset: r.start * 4)
                    any = true
                }
                return any
            }
            func regionGroup(_ units: Set<Int>, kind: Float, tint: SIMD4<Float>, pattern: Float = 0) {
                guard !units.isEmpty else { return }
                enc.setDepthStencilState(markGroup)
                guard regionFan(units.flatMap { sc.unitEntries[$0] }) else { return }
                enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
                relief(kind, tint, pattern: pattern)
            }
            // every region at once: their fans are one run from the start of the index, one draw
            func allRegions() -> Bool {
                guard !sc.fans.isEmpty else { return false }
                enc.setRenderPipelineState(fanPipe)
                enc.setVertexBuffer(rp, offset: 0, index: 0)
                enc.setVertexBuffer(rp, offset: 0, index: 2)
                var one: Float = 1
                enc.setVertexBytes(&one, length: 4, index: 3)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: sc.fans.count, indexType: .uint32, indexBuffer: rf,
                                          indexBufferOffset: 0)
                return true
            }
            // the country's own colour goes first (its stamp or wish is the regions' now): where its outline and its
            // regions' differ by a hair, no sliver of the country's lime shows
            if mark(sc.place) {
                enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
                relief(1)
            }
            enc.setDepthStencilState(markGroup)
            if allRegions() {
                enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
                relief(1)
            }
            // yours: lime and blue, each one draw from an index made once per change of marks
            if regionMarksBuilt != controller.regionMarksVersion || regionMarksScene !== sc {
                regionMarksBuilt = controller.regionMarksVersion
                regionMarksScene = sc
                func index(_ entries: [Int]) -> (MTLBuffer, Int)? {
                    var idx: [UInt32] = []
                    for e in entries { let r = sc.runs[e]; idx += sc.fans[r.start ..< r.start + r.count] }
                    guard !idx.isEmpty, let b = device.makeBuffer(bytes: idx, length: idx.count * 4) else { return nil }
                    return (b, idx.count)
                }
                regionStampedIndex = index(controller.regionStampedEntries)
                regionWishedIndex = index(controller.regionWishedEntries)
            }
            func marked(_ ix: (MTLBuffer, Int)?, tint: SIMD4<Float>, pattern: Float) {
                guard let (b, n) = ix else { return }
                enc.setDepthStencilState(markGroup)
                enc.setRenderPipelineState(fanPipe)
                enc.setVertexBuffer(rp, offset: 0, index: 0)
                enc.setVertexBuffer(rp, offset: 0, index: 2)
                var one: Float = 1
                enc.setVertexBytes(&one, length: 4, index: 3)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: n, indexType: .uint32, indexBuffer: b, indexBufferOffset: 0)
                enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
                relief(2, tint, pattern: pattern)
            }
            // the towns level (6.6): the finest regions as borders only, no fills, so the towns read
            let fills = !controller.regionTowns
            if fills, controller.showsStamped { marked(regionStampedIndex, tint: Palette.limeV, pattern: hatch) }
            if fills, controller.showsWished { marked(regionWishedIndex, tint: Palette.blueV, pattern: dots) }
            let rpress = pressed == sc.place && fills ? controller.regionPressed : nil
            if let u = rpress {
                let st = controller.showsStamped && controller.regionStamped.contains(u)
                let wi = controller.showsWished && controller.regionWished.contains(u)
                let base = st ? Palette.limeV : wi ? Palette.blueV : Palette.whiteV
                regionGroup([u], kind: 2, tint: base * SIMD4<Float>(0.80, 0.79, 0.77, 1))
            }
        }

        // 3c. THE TOWNS (7.4, the old native app's encodeTownShapes): the open country's built-up shapes, every one at
        // once, solid in our grey so neighbours are one colour; yours lime, wished blue; the one under the finger the
        // darker grey (or its colour darkened). They just appear. No circles (30 Oct 23:38); dots only with Map
        // settings' Town dots on
        if placesOn || controller.regionTowns, let cc = controller.placeOpenID, let sc = controller.townScenes[cc] {
            if townBuffers[cc]?.scene !== sc, !sc.fans.isEmpty,
               let pb = device.makeBuffer(bytes: sc.points, length: sc.points.count * MemoryLayout<SIMD2<Float>>.stride),
               let fb = device.makeBuffer(bytes: sc.fans, length: sc.fans.count * 4) {
                townBuffers[cc] = (sc, pb, fb)
            }
            let st = controller.townStamped[cc] ?? [], wi = controller.townWished[cc] ?? []
            // darkened while a finger is on it or its card is up (the press's place, as a region's is)
            let pressedTown = pressed == controller.placeOpen ? controller.townPressed.flatMap { $0.cc == cc ? $0.i : nil } : nil
            let grey = Palette.greyV, greyDark = SIMD4<Float>(0xa1, 0x9e, 0x95, 255) / 255
            func dark(_ c: SIMD4<Float>) -> SIMD4<Float> { SIMD4(c.x * 0.75, c.y * 0.75, c.z * 0.75, 1) }
            if let tb = townBuffers[cc], tb.scene === sc {
                func towns(_ set: [Int], _ colour: SIMD4<Float>) {
                    enc.setDepthStencilState(markGroup)
                    enc.setRenderPipelineState(fanPipe)
                    enc.setVertexBuffer(tb.points, offset: 0, index: 0)
                    enc.setVertexBuffer(tb.points, offset: 0, index: 2)
                    var one: Float = 1
                    enc.setVertexBytes(&one, length: 4, index: 3)
                    // one draw per run of neighbouring towns in the index (the towns are laid biggest first, one after another)
                    var draws: [(start: Int, count: Int)] = []
                    for i in set {
                        guard let r = sc.runs[i], r.count > 0 else { continue }
                        if let l = draws.last, l.start + l.count == r.start { draws[draws.count - 1].count += r.count }
                        else { draws.append(r) }
                    }
                    guard !draws.isEmpty else { return }
                    for r in draws {
                        enc.drawIndexedPrimitives(type: .triangle, indexCount: r.count, indexType: .uint32, indexBuffer: tb.fans,
                                                  indexBufferOffset: r.start * 4)
                    }
                    enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
                    relief(3, colour)
                }
                let marked = (controller.showsStamped ? st : []).union(controller.showsWished ? wi : [])
                // the plain towns' list, made again only when the marks or the pressed town change (not every frame)
                let plainKey = "\(cc)|\(controller.townsVersion)|\(pressedTown ?? -1)|\(controller.filter)"
                if plainCache?.key != plainKey {
                    var plain: [Int] = []
                    for i in sc.runs.indices where !marked.contains(i) && i != pressedTown { plain.append(i) }
                    plainCache = (plainKey, plain)
                }
                towns(plainCache?.list ?? [], grey)
                if controller.showsStamped { towns(st.filter { $0 != pressedTown }.sorted(), Palette.limeV) }
                if controller.showsWished { towns(wi.filter { $0 != pressedTown && !st.contains($0) }.sorted(), Palette.blueV) }
                if let tp = pressedTown {
                    towns([tp], st.contains(tp) ? dark(Palette.limeV) : wi.contains(tp) ? dark(Palette.blueV) : greyDark)
                }
            }
            // dots only with Town dots on (every town, the old app's 2.5 to 6 points by its population in the country)
            if MapSettingsStore.shared.value.townDots, let dp = townDotPipe {
                struct D { var p: SIMD2<Float>; var r: Float; var pad: Float; var colour: SIMD4<Float> }
                // made again only when the marks or the pressed town change (review 31 Oct: not every frame)
                let dotKey = "\(cc)|\(controller.townsVersion)|\(pressedTown ?? -1)"
                if dotCache?.key != dotKey {
                    let lo = log(Float(max(1, sc.towns.last?.people ?? 1))), hi = log(Float(max(1, sc.towns.first?.people ?? 1)))
                    let ds: [D] = sc.towns.indices.map { i in
                        let t = hi > lo ? min(1, max(0, (log(Float(max(1, sc.towns[i].people))) - lo) / (hi - lo))) : 0.5
                        var col = st.contains(i) ? Palette.limeV : wi.contains(i) ? Palette.blueV : grey
                        if i == pressedTown { col = st.contains(i) ? dark(Palette.limeV) : wi.contains(i) ? dark(Palette.blueV) : greyDark }
                        return D(p: sc.at[i], r: 2.5 + 3.5 * t, pad: 0, colour: col)
                    }
                    dotCache = (dotKey, ds.isEmpty ? nil : device.makeBuffer(bytes: ds, length: ds.count * MemoryLayout<D>.stride), ds.count)
                }
                enc.setDepthStencilState(noStencil)
                enc.setRenderPipelineState(dp)
                if let c = dotCache, let b = c.buffer, c.count > 0 {
                    enc.setVertexBuffer(b, offset: 0, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: c.count)
                }
            }
        }
        // 4. the lakes (the slices carry their own, as holes in the land through which the sea's relief shows): drawn
        // with the same sea relief, so a lake is the same colour at every level and nothing changes when a level comes in
        if tiles == nil {
            enc.setDepthStencilState(markGroup)
            fan(lakeRun)
            enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
            relief(0)
        }
        // 5. borders and coasts
        enc.setDepthStencilState(noStencil)
        if maskOn, let cp = compositeFocusPipe, let cov = coverage, let mk = focusMask {
            // a country's own map: the lines outside it go with the rest of the world
            enc.setRenderPipelineState(cp)
            enc.setFragmentTexture(cov, index: 0)
            enc.setFragmentTexture(mk, index: 1)
            // (index 3: the camera stays bound at 1 for the passes after this one)
            var aw = flat
            enc.setFragmentBytes(&aw, length: 4, index: 3)
            enc.setFragmentBytes(&ls, length: MemoryLayout<LineStyle>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        } else if let cp = compositePipe, let cov = coverage {
            enc.setRenderPipelineState(cp)
            enc.setFragmentTexture(cov, index: 0)
            enc.setFragmentBytes(&ls, length: MemoryLayout<LineStyle>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        // 5b. on a continent, the rest of the world goes into one blue (each place keeping its own colour until the
        // blue has it, so nothing pops); drawn over the lines, so their borders go into the blue with them
        if flat > 0.001, let k = awayKey {
            let aw = away(k, w)
            let focusAway = Self.focus(k)
            let st = controller.showsStamped ? controller.stamped : []
            let wi = controller.showsWished ? controller.wished : []
            func colourOf(_ p: Int) -> Int { p >= 0 && st.contains(p) ? 0 : p >= 0 && wi.contains(p) ? 1 : 2 }
            let tints = [Palette.limeV, Palette.blueV, Palette.whiteV]
            for g in 0 ..< 3 {
                let tint = SIMD4(tints[g].x, tints[g].y, tints[g].z, flat)
                enc.setDepthStencilState(markGroup)
                var any = false
                if let tiles {
                    for t in tiles {
                        for it in t.items {
                            let isAway = focusAway.map { it.place != $0 }
                                ?? it.cont.map { $0 != k } ?? (it.place < 0 || aw.places.contains(it.place))
                            if isAway && colourOf(it.place) == g { tileFans(t, start: it.start, count: it.count); any = true }
                        }
                    }
                } else {
                    for u in aw.units where colourOf(w.unitOwner[u]) == g { fan(unitRun[u]); any = true }
                }
                guard any else { continue }
                enc.setDepthStencilState(insideGroup); enc.setStencilReferenceValue(2)
                // a country's own map: the rest keeps its relief in the sea's lightest blue (kind 6); a continent's: the
                // flat blue (kind 5)
                relief(focusAway == nil ? 5 : 6, tint)
            }
        }
        enc.setDepthStencilState(noStencil)
        // 6. the small places' diamonds, while they are too small to see (one zoom for all of them)
        if controller.anyDiamond, let dp = diamondPipe {
            struct D { var p: SIMD2<Float>; var pad = SIMD2<Float>(0, 0); var colour: SIMD4<Float> }
            var ds: [D] = []
            for i in controller.tinyPlaces where controller.showsDiamond(i) {
                let pl = w.places[i]
                var c = controller.stamped.contains(i) && controller.showsStamped ? Palette.limeV
                    : controller.wished.contains(i) && controller.showsWished ? Palette.blueV
                    // unmarked: a territory pure white, everything else cream
                    : pl.k == "territory" ? Palette.whiteV : Palette.creamV
                if i == pressed || (controller.found.contains(i) && !controller.stamped.contains(i)) { c *= SIMD4<Float>(0.80, 0.79, 0.77, 1) }
                // away from the continent you're on, the diamond shrinks into its own point at its own colour (A1.15:
                // 0.72 of its size at a quarter of the blend, gone at its end, its place drawn under it), and grows back
                // from it coming out; never blended into the blue
                var size = Float(controller.diamondSize(i))
                if flat > 0.001, let k = awayKey, !w.inCont(i, k) { size *= 1 - flat }
                // under Regions' selection menu every diamond goes back into its point (A6.5: "no diamonds")
                size *= 1 - menu
                if size < 0.01 { continue }
                ds.append(D(p: SIMD2(Float(pl.c[0]), Float(pl.c[1])), pad: SIMD2(size, 0), colour: c))
            }
            if !ds.isEmpty {
                enc.setRenderPipelineState(dp)
                ds.withUnsafeBytes { enc.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: ds.count)
            }
        }
        _ = w
        enc.endEncoding()
        cb.present(drawable)
        #if DEBUG
        // the frame's cost, measured: CPU time to build it, and the GPU's time once it has run (logged every 2 s
        // while the map draws, so lag can be found by numbers, not by eye)
        let cpu = CACurrentMediaTime() - now
        cb.addCompletedHandler { [weak self] b in
            let gpu = b.gpuEndTime - b.gpuStartTime
            DispatchQueue.main.async { self?.timing(cpu: cpu, gpu: gpu) }
        }
        #endif
        cb.commit()
    }

    #if DEBUG
    private var tCount = 0, tCPU = 0.0, tGPU = 0.0, tMaxCPU = 0.0, tMaxGPU = 0.0, tAt = CACurrentMediaTime()
    private func timing(cpu: Double, gpu: Double) {
        tCount += 1; tCPU += cpu; tGPU += gpu; tMaxCPU = max(tMaxCPU, cpu); tMaxGPU = max(tMaxGPU, gpu)
        if FrameStats.on { FrameStats.cpu.append(cpu); FrameStats.gpu.append(gpu) }
        let t = CACurrentMediaTime()
        if t - tAt > 2 {
            NSLog("wya frame %d frames: cpu avg %.2f max %.2f ms, gpu avg %.2f max %.2f ms; %@", tCount, tCPU / Double(tCount) * 1000,
                  tMaxCPU * 1000, tGPU / Double(tCount) * 1000, tMaxGPU * 1000, detail?.debugState ?? "")
            tCount = 0; tCPU = 0; tGPU = 0; tMaxCPU = 0; tMaxGPU = 0; tAt = t
        }
    }
    #endif
}

/// The Metal view owns the map's fingers itself, the old app's way: - one finger pans; two fingers zoom about their
/// middle and pan with it, in the same event - when the number of fingers changes, the ones left carry on from where
/// they are (nothing jumps) - a quick one-finger flick glides on; a pinch never flings - a touch stops anything moving
/// where it is - a press darkens the place under the finger; locked, it does nothing but a soft knock (the lock stops
/// stamping, it never stops looking) - a double tap zooms in about the finger
final class MapMTKView: MTKView, UIContextMenuInteractionDelegate {
    weak var controller: MapController?
    /// the Places map's names, over the map (they take no touch)
    lazy var townNames: TownNamesView = {
        let v = TownNamesView(frame: bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(v)
        return v
    }()
    private var downAt: CGPoint?
    private var downTime: CFTimeInterval = 0
    private var lastTapTime: CFTimeInterval = 0
    private var lastTapAt: CGPoint = .zero
    private var last: CGPoint?
    private var lastMid: CGPoint?
    private var lastDist: CGFloat = 0
    private var pinched = false
    /// two fingers down together (the two-finger tap): where, when, and whether they moved since
    private var twoAt: CGPoint?
    private var twoTime: CFTimeInterval = 0
    private var twoMoved = false
    private var velocity = SIMD2<Double>(0, 0)
    private var lastMoveTime: CFTimeInterval = 0
    /// ONE-FINGER ZOOM (Part 1.3, Apple Maps' gesture): a second touch-down within the double-tap window, held and
    /// dragged: up zooms in, down zooms out (as Apple Maps: "drag it up to zoom in and down to zoom out"), about the
    /// first tap; let go without moving it is the double tap
    private var zoomAnchor: CGPoint?
    private var zoomStartY: CGFloat = 0
    private var zoomLast: Double = 1

    func installGestures() {
        isMultipleTouchEnabled = true
        // APPLE'S HOLD MENU ON THE MAP (Part 11.3): the one interaction on the map view; our own touches carry on and
        // stop when the menu begins
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    // MARK: the hold menu (11.3): no lift; the held place darkens in place and Apple's menu opens at the finger
    private var menuTarget: UIView?
    /// the menu is on screen (between willDisplay and willEnd); until then a press that pans or lifts leaves nothing
    private var menuUp = false
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        // UIKit asks this as the press starts, before it knows the press is a hold: nothing changes here; the place
        // darkens, other things close and the menu's actions are made only once the menu shows (willDisplay)
        guard let c = controller else { return nil }
        #if DEBUG
        NSLog("wya hold menu asked at %.0f %.0f", location.x, location.y)
        #endif
        // locked: no menu; the lift refuses the hold (finish) (11.7)
        if c.locked { return nil }
        // the sea, or a place off the continent you're on: no menu and no haptic
        guard let i = c.hit(at: location) else { return nil }
        if let k = c.drawnContinent, let w = c.world, !w.inCont(i, k) { return nil }
        // made now, once (making it changes nothing; its actions change things only when chosen), so what shows is
        // what was decided at the press
        #if DEBUG
        NSLog("wya hold menu on %@ piece %@", c.world?.places[i].id ?? "?", c.piece(at: location) ?? "none")
        #endif
        guard let menu = c.menuFor?(i, location) else { return nil }
        menuTarget?.removeFromSuperview()
        let v = UIView(frame: CGRect(x: location.x - 22, y: location.y - 22, width: 44, height: 44))
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        addSubview(v)
        menuTarget = v
        return UIContextMenuConfiguration(identifier: NSNumber(value: i), previewProvider: nil) { [weak c] _ in
            // runs as the menu is about to show
            c?.menuHeld = i
            return menu
        }
    }
    private func clearTarget() -> UITargetedPreview? {
        guard let v = menuTarget else { return nil }
        let p = UIPreviewParameters()
        p.backgroundColor = .clear
        p.visiblePath = UIBezierPath(ovalIn: v.bounds)
        return UITargetedPreview(view: v, parameters: p)
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? { clearTarget() }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? { clearTarget() }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        // our own press and pan stop: the hold is the menu's now
        #if DEBUG
        NSLog("wya hold menu shown for %d", controller?.menuHeld ?? -1)
        #endif
        menuUp = true
        lastTapTime = 0
        downAt = nil; last = nil; lastMid = nil; lastMoveTime = 0; velocity = .zero
        controller?.pressed = nil
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        let done = { [weak self] in
            self?.menuUp = false
            self?.menuTarget?.removeFromSuperview(); self?.menuTarget = nil
            self?.controller?.menuHeld = nil
        }
        if let animator { animator.addCompletion(done) } else { done() }
    }

    private func active(_ event: UIEvent?) -> [UITouch] {
        (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func reset(_ touches: [UITouch]) {
        if touches.count >= 2 {
            let a = touches[0].location(in: self), b = touches[1].location(in: self)
            lastMid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            lastDist = hypot(a.x - b.x, a.y - b.y)
            last = nil
        } else if let t = touches.first {
            last = t.location(in: self); lastMid = nil; lastDist = 0
        } else {
            last = nil; lastMid = nil; lastDist = 0
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let c = controller else { return }
        c.onTouch?()
        let now = active(event)
        if now.count == touches.count { c.grab(); pinched = false; velocity = .zero; lastMoveTime = 0 }
        if now.count >= 2 { pinched = true; c.pressed = nil; downAt = nil }
        if now.count == 2, let e = event, now.allSatisfy({ e.timestamp - $0.timestamp < 0.12 }) || twoAt == nil {
            let a = now[0].location(in: self), b = now[1].location(in: self)
            twoAt = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2); twoTime = now.map(\.timestamp).min() ?? 0; twoMoved = false
        }
        if now.count > 2 { twoAt = nil }
        reset(now)
        if now.count == 1, let t = now.first, let w = c.world {
            let p = t.location(in: self)
            downAt = p; downTime = t.timestamp
            if t.timestamp - lastTapTime < Map.doubleTapWindow, hypot(p.x - lastTapAt.x, p.y - lastTapAt.y) < 30 {
                // the second tap of a double tap, or the start of a one-finger zoom: never a press
                zoomAnchor = lastTapAt; zoomStartY = p.y; zoomLast = 1
                c.pressed = nil
                return
            }
            zoomAnchor = nil
            _ = w
            if !c.locked {
                let hit = c.hit(at: p)
                // on a continent's map only that continent's places take a touch (the old MapView)
                if let h = hit, let k = c.drawnContinent, !w.inCont(h, k) { c.pressed = nil } else { c.pressed = hit }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let c = controller else { return }
        let now = active(event)
        if now.count >= 2 {
            let a = now[0].location(in: self), b = now[1].location(in: self)
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let d = hypot(a.x - b.x, a.y - b.y)
            if let ta = twoAt, hypot(mid.x - ta.x, mid.y - ta.y) > 10 || abs(d - lastDist) > 10 { twoMoved = true }
            if let lm = lastMid, lastDist > 0, d > 0 {
                c.zoom(by: Double(d / lastDist), about: mid)
                c.pan(by: SIMD2(Double(mid.x - lm.x), Double(mid.y - lm.y)))
            }
            lastMid = mid; lastDist = d
        } else if let t = now.first, let anchor = zoomAnchor {
            // one-finger zoom: 2x for every 100 pt up, half for every 100 pt down
            let p = t.location(in: self)
            let f = pow(2, Double(zoomStartY - p.y) / 100)
            c.zoom(by: f / zoomLast, about: anchor)
            zoomLast = f
            if let d0 = downAt, hypot(p.x - d0.x, p.y - d0.y) > 8 { downAt = nil }
        } else if let t = now.first {
            let p = t.location(in: self)
            if let l = last {
                let d = SIMD2(Double(p.x - l.x), Double(p.y - l.y))
                c.pan(by: d)
                let dt = max(0.004, t.timestamp - lastMoveTime)
                let v = d / dt
                velocity = lastMoveTime == 0 ? v : velocity * 0.5 + v * 0.5
                lastMoveTime = t.timestamp
            }
            last = p
            if let d0 = downAt, hypot(p.x - d0.x, p.y - d0.y) > 8 { c.pressed = nil; downAt = nil }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, event, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, event, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, _ event: UIEvent?, cancelled: Bool) {
        guard let c = controller else { return }
        let left = active(event).filter { !touches.contains($0) }
        // a press UIKit readied a menu for, lifted before the menu showed: its clear target goes (not on a cancel:
        // UIKit cancels the touches as the menu begins, before it shows)
        if left.isEmpty, !cancelled, !menuUp, menuTarget != nil {
            menuTarget?.removeFromSuperview(); menuTarget = nil
            c.menuHeld = nil
        }
        if !left.isEmpty {
            // fingers remain: they carry on from where they are
            reset(left)
            return
        }
        let t = touches.first
        // TWO FINGERS TAPPED TOGETHER (no move, quick): one step out about the point between them (Part 1.3, A1.21)
        if !cancelled, let at = twoAt, !twoMoved, let t, t.timestamp - twoTime < 0.3 {
            twoAt = nil
            c.twoFingerTap(at: at)
            c.pressed = nil
            downAt = nil; last = nil; lastMid = nil; lastMoveTime = 0; velocity = .zero
            touching(false, c)
            return
        }
        twoAt = nil
        if zoomAnchor != nil {
            zoomAnchor = nil
            // held and dragged: the zoom stays where the finger left it; not dragged: the double tap
            if downAt == nil || cancelled {
                lastTapTime = 0
                c.release(velocity: nil)
                c.pressed = nil
                downAt = nil; last = nil; lastMid = nil; lastMoveTime = 0; velocity = .zero
                return
            }
        }
        // a tap (no move): a second one within `Map.doubleTapWindow`, near the first, zooms in (Parts 1.3, 4.2.1: the
        // one window for the double tap and for a single tap's wait, so one gesture never does both)
        if !cancelled, let d0 = downAt, let t, t.timestamp - downTime < 0.3 {
            if t.timestamp - lastTapTime < Map.doubleTapWindow, hypot(d0.x - lastTapAt.x, d0.y - lastTapAt.y) < 30 {
                c.doubleTap(at: d0); lastTapTime = 0
            } else {
                lastTapTime = t.timestamp; lastTapAt = d0
                if c.locked { Feel.refuse(); c.lockedPress() }
                else if let hit = c.pressed {
                    // A CONFIRMED TAP (Part 4.2.1): once the double-tap window has passed with no second tap, the place
                    // is handed over (the stamping card opens); a double tap within the window never opens anything
                    let stamp = t.timestamp
                    DispatchQueue.main.asyncAfter(deadline: .now() + Map.doubleTapWindow) { [weak self, weak c] in
                        guard let self, let c, self.lastTapTime == stamp, self.downAt == nil else { return }
                        c.onPlaceTap?(hit, d0)
                    }
                }
            }
        } else if !cancelled, c.locked, downAt != nil {
            // LOCKED, a hold that didn't move (11.7): refused once, the padlock pressing in
            Feel.refuse(); c.lockedPress()
        }
        let recent = t.map { $0.timestamp - lastMoveTime < 0.08 } ?? false
        c.release(velocity: (!pinched && !cancelled && recent && downAt == nil) ? velocity : nil)
        c.pressed = nil
        downAt = nil; last = nil; lastMid = nil; lastMoveTime = 0; velocity = .zero
    }
}

extension MapMTKView {
    /// the fingers are off with no glide
    fileprivate func touching(_ on: Bool, _ c: MapController) { if !on { c.release(velocity: nil) } }
}

/// The map's touch constants (Part 1.3)
enum Map {
    /// the one window for a double tap and for a single tap's wait (a starting value to tune; Parts 1.3, 4.2.1)
    static let doubleTapWindow: CFTimeInterval = 0.25
}

struct MapLayer: UIViewRepresentable {
    let controller: MapController

    final class Coordinator { var renderer: MapRenderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MapMTKView {
        let v = MapMTKView(frame: .zero, device: nil)
        v.controller = controller
        if let r = MapRenderer(controller: controller) {
            r.configure(v)
            v.delegate = r
            context.coordinator.renderer = r
        }
        v.installGestures()
        // a size change (the sideways turn, 1.11) keeps the last frame's pixels where they were, centred, until the next
        // frame is drawn at the new size: never stretched or squeezed for a frame (the camera's centre is the view's)
        v.layer.contentsGravity = .center
        return v
    }
    func updateUIView(_ uiView: MapMTKView, context: Context) {}
}

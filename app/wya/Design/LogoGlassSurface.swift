import SwiftUI
import UIKit
import Metal
import QuartzCore

/// THE LOGO'S LIGHT, DRAWN: the living field split by a giant planet's day and night, turning with the logo's light.
/// The shader is the old app's, line for line. New here: it is drawn on its own thread, so nothing the main thread does
/// (the map loading under the loading screen) can make it stutter; and `turn` lets the light go round by itself at a
/// steady speed, for the loading screen.
struct LogoGlassSurface: UIViewRepresentable {
    /// where the light stands (used when `turn` is nil)
    let phase: Double
    let spot: LogoLightSpot
    let still: Bool
    /// seconds a turn: the light goes round by itself, from `turnStart` (CACurrentMediaTime)
    var turn: Double? = nil
    var turnStart: CFTimeInterval? = nil

    func makeUIView(context: Context) -> LogoGlassView {
        let v = LogoGlassView(frame: .zero)
        v.set(phase: phase, spot: spot, still: still, turn: turn, turnStart: turnStart)
        return v
    }
    func updateUIView(_ v: LogoGlassView, context: Context) {
        v.set(phase: phase, spot: spot, still: still, turn: turn, turnStart: turnStart)
    }
    static func dismantleUIView(_ v: LogoGlassView, coordinator: ()) { v.stop() }
}

final class LogoGlassView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private var render: GlassRender?

    override init(frame: CGRect) {
        super.init(frame: frame)
        metalLayer.device = LogoGlassGPU.shared.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.magnificationFilter = .linear
        backgroundColor = .clear
        isUserInteractionEnabled = false
        if let gpu = LogoGlassGPU.shared.ready {
            render = GlassRender(layer: metalLayer, queue: gpu.queue, pipeline: gpu.pipeline)
        }
    }
    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    func set(phase: Double, spot: LogoLightSpot, still: Bool, turn: Double?, turnStart: CFTimeInterval?) {
        render?.update(phase: phase, turn: turnStart == nil ? nil : turn, turnStart: turnStart ?? 0, still: still,
                       spot: SIMD4(Float(spot.centre.x), Float(spot.centre.y), Float(spot.radius), Float(spot.strength)),
                       glow: SIMD4(Float(spot.glow.midX), Float(spot.glow.midY), Float(spot.glow.width / 2), Float(spot.glow.height / 2)))
        render?.start()
    }

    func stop() { render?.stop() }

    /// the light is soft everywhere: one pixel a point is plenty
    private let perPoint: CGFloat = 1

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = max(8, (bounds.width * perPoint).rounded()), h = max(8, (bounds.height * perPoint).rounded())
        render?.resize(width: Float(bounds.width), height: Float(bounds.height), perPoint: Float(perPoint))
        if metalLayer.drawableSize != CGSize(width: w, height: h) {
            metalLayer.drawableSize = CGSize(width: w, height: h)
            // its first frame comes with the view itself, never a frame late
            metalLayer.presentsWithTransaction = true
            render?.draw(withTransaction: true)
            metalLayer.presentsWithTransaction = false
        }
    }
}

/// the drawing, on its own thread: a display link on that thread's run loop draws whenever the light has moved
nonisolated final class GlassRender: NSObject, @unchecked Sendable {
    private let layer: CAMetalLayer
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let lock = NSLock()
    // guarded by lock
    private var phase = 0.0, turn: Double?, turnStart: CFTimeInterval = 0, still = false
    private var spot = SIMD4<Float>(0, 0, 1, 0), glow = SIMD4<Float>(0, 0, 0, 0)
    private var size = SIMD3<Float>(0, 0, 1)
    private var dirty = true, stopped = false, started = false
    // the thread's own
    private var lastDraw: CFTimeInterval = 0
    /// his drawing's rest: sin(rest) = 1/phi^2 (LogoMark.rest)
    static let rest: Double = {
        let phi: Double = (1 + 5.0.squareRoot()) / 2
        return asin(1 / (phi * phi))
    }()
    static let clockStart = CACurrentMediaTime()

    init(layer: CAMetalLayer, queue: any MTLCommandQueue, pipeline: any MTLRenderPipelineState) {
        self.layer = layer; self.queue = queue; self.pipeline = pipeline
    }

    func update(phase: Double, turn: Double?, turnStart: CFTimeInterval, still: Bool, spot: SIMD4<Float>, glow: SIMD4<Float>) {
        lock.lock(); defer { lock.unlock() }
        if phase != self.phase || turn != self.turn || still != self.still || spot != self.spot || glow != self.glow { dirty = true }
        self.phase = phase; self.turn = turn; self.turnStart = turnStart; self.still = still; self.spot = spot; self.glow = glow
    }
    func resize(width: Float, height: Float, perPoint: Float) {
        lock.lock(); size = SIMD3(width, height, perPoint); dirty = true; lock.unlock()
    }
    func start() {
        lock.lock(); let go = !started; started = true; lock.unlock()
        guard go else { return }
        let t = Thread { [self] in
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            link.add(to: .current, forMode: .default)
            while true {
                lock.lock(); let s = stopped; lock.unlock()
                if s { break }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.25))
            }
            link.invalidate()
        }
        t.name = "wya logo light"
        t.qualityOfService = .userInteractive
        t.start()
    }
    func stop() { lock.lock(); stopped = true; lock.unlock() }

    @objc private func step(_ l: CADisplayLink) {
        lock.lock()
        let turning = turn != nil
        let need = dirty || turning || (!still && l.timestamp - lastDraw >= 1.0 / 30)
        lock.unlock()
        guard need else { return }
        draw(withTransaction: false)
        lastDraw = l.timestamp
    }

    /// one frame; `withTransaction` on the main thread only, for the first frame shown with the view
    func draw(withTransaction: Bool) {
        lock.lock()
        let sz = size, sp = spot, gl = glow, still = still
        let now = CACurrentMediaTime() - Self.clockStart
        // a turn by itself: half speed with Reduce Motion, never still (Part 0.4: a still mark reads as stuck)
        let since = CACurrentMediaTime() - turnStart
        let ph = turn.map { Self.rest + 2 * .pi * since / ($0 * (still ? 2 : 1)) } ?? phase
        dirty = false
        lock.unlock()
        guard sz.x > 0, let drawable = layer.nextDrawable() else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = drawable.texture
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rp.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        // the field's own slow drift (the old app's time: 0.32 a second from 41)
        let t = Float(now * 0.32 + 41)
        var u: [SIMD4<Float>] = [SIMD4(sz.x, sz.y, sz.z, t), SIMD4(Float(ph), sp.w, sp.z, 0),
                                 SIMD4(sp.x, sp.y, 0, 0), gl]
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<SIMD4<Float>>.stride * 4, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        if withTransaction {
            cb.commit()
            cb.waitUntilScheduled()
            drawable.present()
        } else {
            cb.present(drawable)
            cb.commit()
        }
    }
}

#if DEBUG
extension GlassRender {
    /// the light as it is in its first frame, as a picture (the launch picture, ReviewSheet.launchPicture)
    @MainActor static func picture(width: Int, height: Int, phase: Double, spot: LogoLightSpot) -> CGImage? {
        guard let dev = LogoGlassGPU.shared.device, let gpu = LogoGlassGPU.shared.ready else { return nil }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget]
        td.storageMode = .shared
        guard let tex = dev.makeTexture(descriptor: td) else { return nil }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rp.colorAttachments[0].storeAction = .store
        guard let cb = gpu.queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        var u: [SIMD4<Float>] = [SIMD4(Float(width), Float(height), 1, 41), SIMD4(Float(phase), Float(spot.strength), Float(spot.radius), 0),
                                 SIMD4(Float(spot.centre.x), Float(spot.centre.y), 0, 0),
                                 SIMD4(Float(spot.glow.midX), Float(spot.glow.midY), Float(spot.glow.width / 2), Float(spot.glow.height / 2))]
        enc.setRenderPipelineState(gpu.pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<SIMD4<Float>>.stride * 4, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        return ctx.makeImage()
    }
}
#endif

/// the device, the queue and the compiled shader, made once
@MainActor
final class LogoGlassGPU {
    static let shared = LogoGlassGPU()
    struct Ready { let queue: any MTLCommandQueue; let pipeline: any MTLRenderPipelineState }
    let device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()
    private(set) lazy var ready: Ready? = make()

    private func make() -> Ready? {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        do {
            let lib = try device.makeLibrary(source: Self.source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "glassVertex")
            d.fragmentFunction = lib.makeFunction(name: "glassFragment")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            return Ready(queue: queue, pipeline: try device.makeRenderPipelineState(descriptor: d))
        } catch {
            assertionFailure("the logo's light shader did not compile: \(error)")
            return nil
        }
    }

    // THE LOGO'S LIGHT. One light, turning about the logo's line, falls on the page as the living field: lime where a
    // planet far larger than the screen, about the logo, has its day, blue where it has its night.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; };

    vertex VOut glassVertex(uint vid [[vertex_id]]) {
        float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VOut o; o.pos = float4(p[vid], 0.0, 1.0); return o;
    }

    \(ShaderNoise.msl)
    // THE TWELVE (Palette.rgb) the light is made of
    constant float3 kCream  = float3(0.984, 0.965, 0.949);
    constant float3 kLime   = float3(0.831, 0.886, 0.286);
    constant float3 kYellow = float3(1.000, 0.878, 0.290);
    constant float3 kBlue   = float3(0.471, 0.682, 0.973);
    constant float3 kTeal   = float3(0.690, 0.878, 0.804);

    // his line runs up and to the right (u); across it, towards the night, is down and to the right (n); y is down
    constant float2 kU = float2(0.70710678, -0.70710678);
    constant float2 kN = float2(0.70710678, 0.70710678);

    static float3 saturate3(float3 c, float s) {
        float lum = dot(c, float3(0.299, 0.587, 0.114));
        return clamp(mix(float3(lum), c, s), 0.0, 1.0);
    }

    // THE LIVING FIELD (LivingField.swift field(), v's FIELD_FS) at a point of the page, in points: the plane warped
    // twice so nothing stays round, four colours each on its own slow noise; the day in limes, the night in blues
    static float3 fieldLight(float2 x, float t, float day) {
        float2 p = x / 364.0;
        float2 w1 = float2(snoise(float3(p * 0.55, t * 0.045)), snoise(float3(p * 0.55 + 7.3, t * 0.045 + 3.0)));
        float2 w2 = float2(snoise(float3(p * 1.15 + w1 * 1.3 + 2.1, t * 0.07)), snoise(float3(p * 1.15 + w1 * 1.3 - 5.2, t * 0.07 + 1.0)));
        p += (w1 * 0.95 + w2 * 0.42);
        float4 w;
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float n = snoise(float3(p * 0.62 + float2(fk * 3.7, fk * -2.9), t * 0.085 + fk * 11.0));
            w[k] = pow(smoothstep(-0.44, 0.78, n), 2.2) + 0.07;
        }
        float ws = w.x + w.y + w.z + w.w;
        float3 dayC = (kLime * w.x + kYellow * w.y + kLime * w.z + kCream * w.w) / ws;
        float3 nightC = (kBlue * w.x + kTeal * w.y + kBlue * w.z + kCream * w.w) / ws;
        float breath = 0.97 + 0.08 * (snoise(float3(p * 0.5 + 31.0, t * 0.06)) * 0.5 + 0.5);
        return saturate3(mix(nightC, dayC, day) * breath, 1.12);
    }

    // where the light stands for the logo's phase, as (along the line, across it towards the night, towards the eye):
    // a sphere lit from here has his day exactly (LogoMark.Geo.day: the curve an ellipse |sin phase| as wide)
    static float3 lightDir(float phase) { return float3(0.0, -cos(phase), sin(phase)); }

    // THE LIGHT ON THE PAGE at x, and how much of it lies over the cream: the giant planet's day and night, the change
    // between them soft; a little less towards its far edge; and brightest near the logo, as light is near where it
    // comes from (glow: its centre and its reach across and down, round the logo and its name), its edge carried by
    // the field's own slow noise so it is never a shape
    static float4 pageLight(float2 x, float2 gc, float gr, float4 glow, float strength, float3 L, float t) {
        float2 d = (x - gc) / gr;
        float rho = length(d);
        if (strength <= 0.0 || rho >= 1.0) return float4(kCream, 0.0);
        // the giant planet sits up and to the left of the logo by its day's width at rest, so at rest its day/night
        // line runs through the logo as the logo's own does: lime above and to the left, blue below and to the right,
        // both on the page
        float2 dd = d + kN * 0.382;
        float a = dot(dd, kU), b = dot(dd, kN);
        float z = sqrt(max(0.0, 1.0 - dot(dd, dd)));
        float day = smoothstep(-0.24, 0.24, dot(float3(a, b, z), L));
        float edge = 1.0 - smoothstep(0.45, 1.0, rho);
        float near = 1.0;
        if (glow.z > 0.0) {
            float q = length((x - glow.xy) / glow.zw);
            q += 0.22 * snoise(float3(x / 170.0, t * 0.05 + 17.0));
            near = mix(0.16, 1.0, smoothstep(0.45, 1.45, q));
        }
        return float4(fieldLight(x, t, day), strength * edge * near);
    }

    struct GU { float4 a; float4 b; float4 c; float4 d; };

    fragment float4 glassFragment(VOut in [[stage_in]], constant GU& u [[buffer(0)]]) {
        float2 pos = in.pos.xy / u.a.z;
        float4 l = pageLight(pos, u.c.xy, u.b.z, u.d, u.b.y, lightDir(u.b.x), u.a.w);
        return float4(l.rgb * l.a, l.a);
    }
    """
}

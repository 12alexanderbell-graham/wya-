import SwiftUI
import UIKit
import Metal
import QuartzCore

/// THE LIVING GRADIENT (v: app.js 19-122):
/// simplex noise, the plane warped twice so nothing stays round, every colour a wide soft ramp so no edge forms, the
/// light barely breathing. v's WebGL shader, line for line in Metal, drawn the way v drew it: at a third of the pixels,
/// about 25 frames a second, scaled up and blurred by 8 points, 4% past every edge. The shader is compiled when the app
/// runs (Metal's own compiler on the phone), so the project needs no Metal build step.
struct LivingField: View {
    /// four of the twelve, by name (app.js FIELD_COLS: teal, lime, blue, cream)
    var colours: [String] = ["teal", "lime", "blue", "cream"]
    var speed: Double = 0.55
    var seed: Double = 0
    var paused: Bool = false
    /// v blurs the canvas by 8 points and makes it 108% of the screen so the blur never shows an edge
    var blur: CGFloat = 8
    /// the field's saturation, the power on its colour weights and how far it is washed toward cream; 0 is v's own
    /// (1.16, 2.0, none). A picture's gradient is stronger (data.js PGRAD_OPT: 1.42, 2.9).
    var saturation: Double = 0
    var power: Double = 0
    var wash: Double = 0

    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        GeometryReader { geo in
            FieldSurface(colours: colours, speed: speed, seed: seed, paused: paused, still: still,
                         look: SIMD3(Float(saturation), Float(power), Float(wash)))
                .frame(width: geo.size.width * 1.08, height: geo.size.height * 1.08)
                .offset(x: -geo.size.width * 0.04, y: -geo.size.height * 0.04)
                .blur(radius: blur)
        }
        .background(Palette.cream)      // before the first frame the field is cream, never black
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FieldSurface: UIViewRepresentable {
    let colours: [String]
    let speed: Double
    let seed: Double
    let paused: Bool
    let still: Bool
    var look: SIMD3<Float> = .zero

    func makeUIView(context: Context) -> FieldView {
        let v = FieldView(frame: .zero)
        v.saturation = look.x; v.power = look.y; v.wash = look.z
        v.configure(colours: colours, speed: speed, seed: seed, paused: paused, still: still, first: true)
        return v
    }
    func updateUIView(_ v: FieldView, context: Context) {
        v.saturation = look.x; v.power = look.y; v.wash = look.z
        v.configure(colours: colours, speed: speed, seed: seed, paused: paused, still: still, first: false)
    }
    static func dismantleUIView(_ v: FieldView, coordinator: ()) { v.stop() }
}

/// What the shader is given each frame. Everything is a float4 so Swift and Metal lay it out the same.
private struct FieldUniforms {
    var a: SIMD4<Float>     // width, height, time, saturation (0: v's 1.16)
    var b: SIMD4<Float>     // power (0: v's 2.0), wash, 0, 0
    var c0: SIMD4<Float>
    var c1: SIMD4<Float>
    var c2: SIMD4<Float>
    var c3: SIMD4<Float>
}

final class FieldView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private static let shared = FieldGPU()

    private var link: CADisplayLink?
    private var cur: [SIMD3<Double>] = []
    private var want: [SIMD3<Double>] = []
    private var t: Double = 0
    private var last: CFTimeInterval = 0
    private var speed: Double = 0.55
    private var paused = false
    private var still = false
    private var drewOnce = false
    /// the field's saturation and the power on its colour weights; 0 is v's own (1.16, 2.0). The map's lights
    /// are a little stronger (map.js mapLights: 1.18, 2.2).
    var saturation: Float = 0
    var power: Float = 0
    /// how far toward cream (v's GGRAD_OPT wash)
    var wash: Float = 0
    /// how many pixels per point it is drawn at before it is stretched: v's canvas was 0.34 of its size and then
    /// blurred by 8 points; the map's lights, blurred by 10 in v, are drawn coarser still, so the stretch blurs them
    var resolution: CGFloat = 0.34

    func configure(colours: [String], speed: Double, seed: Double, paused: Bool, still: Bool, first: Bool) {
        let cs = (0..<4).map { k in Palette.named[colours.isEmpty ? "cream" : colours[k % colours.count]] ?? .one }
        if first {
            cur = cs; want = cs; t = seed * 37.1
            metalLayer.device = Self.shared.device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.isOpaque = true
            // the drawable is a third of the view's points, stretched smoothly: v's canvas was 0.34 of its size
            metalLayer.magnificationFilter = .linear
            backgroundColor = UIColor(red: 0.984, green: 0.965, blue: 0.949, alpha: 1)
        } else {
            want = cs
        }
        self.speed = speed
        self.paused = paused
        self.still = still
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(step(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 25)
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    #if DEBUG && targetEnvironment(simulator)
    /// the harness's `glow` (Slice 90f): what the field is drawing at
    var debugState: String {
        "drawable \(Int(metalLayer.drawableSize.width))x\(Int(metalLayer.drawableSize.height)) res \(resolution) drew \(drewOnce) "
            + "link \(link != nil) paused \(paused) still \(still) t \(String(format: "%.1f", t)) window \(window != nil) "
            + "colours \(cur.map { String(format: "%.2f/%.2f/%.2f", $0.x, $0.y, $0.z) }.joined(separator: " ")) wash \(wash)"
    }
    #endif

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = max(24, (bounds.width * resolution).rounded()), h = max(24, (bounds.height * resolution).rounded())
        if metalLayer.drawableSize != CGSize(width: w, height: h) {
            metalLayer.drawableSize = CGSize(width: w, height: h)
            drewOnce = false
            // its first frame is drawn now and shown with the view itself, not on the next tick: a field that came in
            // with Settings was flat cream for a frame and then popped into colour (audit A48, r08 2.23 to 2.27 s)
            if !cur.isEmpty {
                metalLayer.presentsWithTransaction = true
                draw()
                metalLayer.presentsWithTransaction = false
            }
        }
    }

    @objc private func step(_ l: CADisplayLink) {
        let now = l.timestamp
        if last == 0 { last = now }
        // about 25 frames a second is plenty for a gradient (app.js 101)
        if now - last < 0.04 && drewOnce { return }
        // covered whole, or Reduce Motion once it has a frame: it waits (L016)
        if (paused || still) && drewOnce { last = now; return }
        let dt = min(0.05, now - last)
        last = now
        t += dt * speed
        // the colours drift to where they are wanted, a second or so (app.js 108-112)
        for k in 0..<4 {
            let d = want[k] - cur[k]
            cur[k] = (abs(d.x) + abs(d.y) + abs(d.z) > 0.006) ? cur[k] + d * min(1, dt * 2.2) : want[k]
        }
        draw()
    }

    private func draw() {
        guard bounds.width > 0, let gpu = Self.shared.ready, let drawable = metalLayer.nextDrawable() else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = drawable.texture
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let cb = gpu.queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        let size = metalLayer.drawableSize
        func f4(_ c: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(c.x), Float(c.y), Float(c.z), 1) }
        var u = FieldUniforms(a: SIMD4(Float(size.width), Float(size.height), Float(t), saturation),
                              b: SIMD4(power, wash, 0, 0),
                              c0: f4(cur[0]), c1: f4(cur[1]), c2: f4(cur[2]), c3: f4(cur[3]))
        enc.setRenderPipelineState(gpu.pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        if metalLayer.presentsWithTransaction {
            cb.commit()
            cb.waitUntilScheduled()
            drawable.present()
        } else {
            cb.present(drawable)
            cb.commit()
        }
        drewOnce = true
    }
}

/// The device, the queue and the compiled shader, made once for every field on screen.
@MainActor
private final class FieldGPU {
    struct Ready { let queue: any MTLCommandQueue; let pipeline: any MTLRenderPipelineState }
    let device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()
    private(set) lazy var ready: Ready? = make()

    private func make() -> Ready? {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        do {
            let lib = try device.makeLibrary(source: Self.source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "fieldVertex")
            d.fragmentFunction = lib.makeFunction(name: "fieldFragment")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            return Ready(queue: queue, pipeline: try device.makeRenderPipelineState(descriptor: d))
        } catch {
            assertionFailure("the living field's shader did not compile: \(error)")
            return nil
        }
    }

    /// v's FIELD_FS (app.js 29-58), in the Metal Shading Language. WebGL counts pixels from the bottom left
    /// and Metal from the top left, so the fragment flips y to draw the same field the same way up.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; };

    vertex VOut fieldVertex(uint vid [[vertex_id]]) {
        float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VOut o; o.pos = float4(p[vid], 0.0, 1.0); return o;
    }

    struct U { float4 a; float4 b; float4 c0; float4 c1; float4 c2; float4 c3; };

    \(ShaderNoise.msl)
    float3 field(float2 q, float t, constant U& u) {
        float2 p = q;
        float2 w1 = float2(snoise(float3(p * 0.55, t * 0.045)), snoise(float3(p * 0.55 + 7.3, t * 0.045 + 3.0)));
        float2 w2 = float2(snoise(float3(p * 1.15 + w1 * 1.3 + 2.1, t * 0.07)), snoise(float3(p * 1.15 + w1 * 1.3 - 5.2, t * 0.07 + 1.0)));
        p += (w1 * 0.95 + w2 * 0.42);
        float3 cs[4];
        cs[0] = u.c0.xyz; cs[1] = u.c1.xyz; cs[2] = u.c2.xyz; cs[3] = u.c3.xyz;
        float3 acc = float3(0.0);
        float ws = 0.0;
        float pw = u.b.x > 0.0 ? u.b.x : 2.0;
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float n = snoise(float3(p * 0.62 + float2(fk * 3.7, fk * -2.9), t * 0.085 + fk * 11.0));
            float w = smoothstep(-0.44, 0.78, n);
            w = pow(w, pw) + 0.07;
            acc += cs[k] * w;
            ws += w;
        }
        float3 col = acc / ws;
        float light = snoise(float3(p * 0.5 + 31.0, t * 0.06)) * 0.5 + 0.5;
        col *= 0.97 + 0.08 * light;
        float lum = dot(col, float3(0.299, 0.587, 0.114));
        col = mix(float3(lum), col, u.a.w > 0.0 ? u.a.w : 1.16);
        col = mix(col, float3(0.984, 0.965, 0.949), u.b.y);
        return clamp(col, 0.0, 1.0);
    }

    fragment float4 fieldFragment(VOut in [[stage_in]], constant U& u [[buffer(0)]]) {
        float2 res = u.a.xy;
        float2 frag = float2(in.pos.x, res.y - in.pos.y);
        float2 uv = frag / res;
        float ar = res.x / res.y;
        float2 q = float2(uv.x * ar, uv.y) * 2.4;
        float3 c = field(q, u.a.z, u);
        return float4(c, 1.0);
    }
    """
}

/// Ashima's simplex noise as v's shaders have it (app.js FIELD_FS), shared by the living field and the streak's
/// fire, which takes it from the same place in v (map.js FIRE_FS slices it out of FIELD_FS).
enum ShaderNoise {
    static let msl = """
    float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
    float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

    float snoise(float3 v) {
        const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
        const float4 D = float4(0.0, 0.5, 1.0, 2.0);
        float3 i = floor(v + dot(v, C.yyy));
        float3 x0 = v - i + dot(i, C.xxx);
        float3 g = step(x0.yzx, x0.xyz);
        float3 l = 1.0 - g;
        float3 i1 = min(g.xyz, l.zxy);
        float3 i2 = max(g.xyz, l.zxy);
        float3 x1 = x0 - i1 + C.xxx;
        float3 x2 = x0 - i2 + C.yyy;
        float3 x3 = x0 - D.yyy;
        i = mod289(i);
        float4 p = permute(permute(permute(i.z + float4(0.0, i1.z, i2.z, 1.0)) + i.y + float4(0.0, i1.y, i2.y, 1.0)) + i.x + float4(0.0, i1.x, i2.x, 1.0));
        float n_ = 0.142857142857;
        float3 ns = n_ * D.wyz - D.xzx;
        float4 j = p - 49.0 * floor(p * ns.z * ns.z);
        float4 x_ = floor(j * ns.z);
        float4 y_ = floor(j - 7.0 * x_);
        float4 x = x_ * ns.x + ns.yyyy;
        float4 y = y_ * ns.x + ns.yyyy;
        float4 h = 1.0 - abs(x) - abs(y);
        float4 b0 = float4(x.xy, y.xy);
        float4 b1 = float4(x.zw, y.zw);
        float4 s0 = floor(b0) * 2.0 + 1.0;
        float4 s1 = floor(b1) * 2.0 + 1.0;
        float4 sh = -step(h, float4(0.0));
        float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
        float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
        float3 p0 = float3(a0.xy, h.x);
        float3 p1 = float3(a0.zw, h.y);
        float3 p2 = float3(a1.xy, h.z);
        float3 p3 = float3(a1.zw, h.w);
        float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
        p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
        float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), float4(0.0));
        m = m * m;
        return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
    }
    """
}

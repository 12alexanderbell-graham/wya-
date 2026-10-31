import Foundation
import CoreGraphics
import simd

/// A MAP'S PICTURE (7.5's card): a square piece of our map drawn off the main thread the way the map's own relief
/// shader draws it (MapShaders' reliefFragment, Detailed style): the sea by depth from our blue to the shallows' near
/// white, the land white to grey by height with the soft north-west light; the land round the map in the shallows'
/// blue (as the world round an open country is, kind 6); your stamped towns and own places as lime points.
nonisolated enum MapPicture {
    private static let white = SIMD3<Double>(1, 1, 1)
    private static let blue = SIMD3<Double>(0.4706, 0.6824, 0.9725)
    private static let beigeDark = SIMD3<Double>(0.7373, 0.7216, 0.7137)
    private static let lime = SIMD3<Double>(0.8314, 0.8863, 0.2863)

    static func draw(world w: World, relief r: Relief?, box b0: SIMD4<Float>, own: Set<Int>?, everywhere: Bool,
                     dots: [SIMD2<Float>], plain: [SIMD2<Float>] = [], px: Int) -> CGImage? {
        guard px > 8 else { return nil }
        // the box with room round it, made square
        var x0 = Double(b0.x), y0 = Double(b0.y), x1 = Double(b0.z), y1 = Double(b0.w)
        let pad = everywhere ? 0 : max(x1 - x0, y1 - y0) * 0.12 + 0.3
        x0 -= pad; x1 += pad; y0 -= pad; y1 += pad
        if x1 - x0 > y1 - y0 { let c = (y0 + y1) / 2, h = (x1 - x0) / 2; y0 = c - h; y1 = c + h }
        else { let c = (x0 + x1) / 2, h = (y1 - y0) / 2; x0 = c - h; x1 = c + h }
        let s = Double(px) / (x1 - x0)
        func pt(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: (Double(p.x) - x0) * s, y: (Double(p.y) - y0) * s) }

        // 1. which pixels are the map's own land (255), other land (128), sea and lakes (0), from the world's rings
        var mask = [UInt8](repeating: 0, count: px * px)
        let gray = CGColorSpaceCreateDeviceGray()
        mask.withUnsafeMutableBytes { buf in
            guard let g = CGContext(data: buf.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px,
                                    space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            g.translateBy(x: 0, y: CGFloat(px)); g.scaleBy(x: 1, y: -1)
            let mine = CGMutablePath(), rest = CGMutablePath(), lakes = CGMutablePath()
            for ring in w.rings {
                guard Double(ring.box.z) >= x0, Double(ring.box.x) <= x1, Double(ring.box.w) >= y0, Double(ring.box.y) <= y1,
                      Double(max(ring.box.z - ring.box.x, ring.box.w - ring.box.y)) * s > 0.4 else { continue }
                let p = CGMutablePath()
                p.move(to: pt(w.points[ring.start]))
                for i in 1 ..< ring.count { p.addLine(to: pt(w.points[ring.start + i])) }
                p.closeSubpath()
                if ring.unit < 0 { lakes.addPath(p) }
                else if own == nil || own!.contains(w.unitOwner[ring.unit]) { mine.addPath(p) } else { rest.addPath(p) }
            }
            g.addPath(rest); g.setFillColor(gray: 0.5, alpha: 1); g.fillPath(using: .evenOdd)
            g.addPath(mine); g.setFillColor(gray: 1, alpha: 1); g.fillPath(using: .evenOdd)
            g.addPath(lakes); g.setFillColor(gray: 0, alpha: 1); g.fillPath()
        }

        // 2. each pixel coloured as the shader colours it
        var out = [UInt8](repeating: 255, count: px * px * 4)
        let rw = r?.width ?? 0, rh = r?.height ?? 0
        // how many relief texels a pixel covers (the shader's "detail": the relief eases out when zoomed past it)
        let texelsPerPixel = Double(rw) * (x1 - x0) / Double(w.width) / Double(px)
        let detail = smoothstep(0.15, 0.5, texelsPerPixel)
        // the slope is measured a pixel apart (at least a texel), so the shading shows the hills this size can show
        let step = max(1, Int(texelsPerPixel.rounded()))
        r?.bytes.withUnsafeBytes { (rb: UnsafeRawBufferPointer) in
            func sample(_ u: Int, _ v: Int) -> (Double, Double) {
                let uu = min(max(u, 0), rw - 1), vv = min(max(v, 0), rh - 1)
                let o = (vv * rw + uu) * 2
                return (Double(rb[o]) / 255, Double(rb[o + 1]) / 255)
            }
            for j in 0 ..< px {
                for i in 0 ..< px {
                    let m = mask[j * px + i]
                    let mx = x0 + (Double(i) + 0.5) / s, my = y0 + (Double(j) + 0.5) / s
                    let ll = EqualEarth.unproject(SIMD2(mx, my))
                    var c: SIMD3<Double>
                    // past the world's outline the inverse lands on some other point: open sea there
                    let back = EqualEarth.project(lon: ll.lon, lat: ll.lat)
                    let off = abs(Double(back.x) - mx) + abs(Double(back.y) - my) > 0.5
                    if off || !(abs(ll.lat) <= 90 && abs(ll.lon) <= 180) || rw == 0 {
                        c = m == 0 ? blue : white
                    } else {
                        let u = Int((ll.lon + 180) / 360 * Double(rw)), v = Int((90 - ll.lat) / 180 * Double(rh))
                        let (d, h) = sample(u, v)
                        if m < 64 {
                            let t = pow(min(max(d / 0.78, 0), 1), 0.85)
                            c = mix(mix(white, blue, t: 0.20), blue, t: t)
                        } else {
                            let hl = sample(u - step, v).1, hr = sample(u + step, v).1
                            let hu = sample(u, v - step).1, hd = sample(u, v + step).1
                            let n = simd_normalize(SIMD3((hl - hr) * 7, (hu - hd) * 7, 1))
                            let L = simd_normalize(SIMD3<Double>(-1, -1, 1.6))
                            let shade = simd_dot(n, L) / L.z
                            c = mix(white, beigeDark, t: min(max(pow(h, 1.15) * 1.05, 0), 1) * (0.10 + 0.9 * detail))
                            c *= 1 + (min(max(shade, 0.6), 1.25) - 1) * 0.55 * detail
                            if m < 192 && !everywhere { c *= mix(white, blue, t: 0.20) }
                        }
                    }
                    let o = (j * px + i) * 4
                    out[o] = UInt8(min(max(c.x, 0), 1) * 255); out[o + 1] = UInt8(min(max(c.y, 0), 1) * 255)
                    out[o + 2] = UInt8(min(max(c.z, 0), 1) * 255)
                }
            }
        }

        // 3. your marks, lime points
        let rgb = CGColorSpaceCreateDeviceRGB()
        return out.withUnsafeMutableBytes { buf -> CGImage? in
            guard let g = CGContext(data: buf.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                                    space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            g.translateBy(x: 0, y: CGFloat(px)); g.scaleBy(x: 1, y: -1)
            let d = CGFloat(px) / (everywhere ? 44 : 26)
            // a collection's places not yet yours, in ink (half), under the lime ones
            g.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.55)
            for p in plain {
                let c = pt(p)
                g.fillEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
            }
            g.setFillColor(red: lime.x, green: lime.y, blue: lime.z, alpha: 1)
            for p in dots {
                let c = pt(p)
                g.fillEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
            }
            return g.makeImage()
        }
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t)
    }
    private static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, t: Double) -> SIMD3<Double> { a + (b - a) * t }
}

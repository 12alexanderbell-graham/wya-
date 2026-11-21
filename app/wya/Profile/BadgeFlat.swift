import SwiftUI
import UIKit
import simd

/// FLAT RELIEF BADGES: a region's badge is its real terrain, shaded as a printed relief map lit from the north-west
/// and cut to its own shape, in its level's colour; a number's badge is a flat disc with the number printed on it. No
/// metal, no depth, no bevel, no studio light.
nonisolated enum BadgeFlat {
    /// the world's heights, the map's own picture (5400 by 2700, four minutes of arc a point), read once
    static let relief: Relief? = try? Relief.load()

    /// what a picture is cut from, worked out on the main actor and handed over whole
    struct Plan: Sendable {
        enum Plane: Sendable {
            /// the map's own Equal Earth units (x right, y down), inside `box` (x0, y0, x1, y1)
            case equalEarth(box: SIMD4<Double>)
            /// seen from straight above the North Pole down to `edge` degrees of latitude, 0° at the bottom
            case pole(edge: Double)
        }
        var plane: Plane
        /// the outline in the plane's 0...1 box (y down); none for the pole's disc
        var rings: [[CGPoint]] = []
        var aspect: CGFloat = 1
        /// the sea shaded too (a sea's own badge, the Arctic); otherwise only the land shows
        var sea = false
        /// a map tile with rounded corners round the box (a range, a sea: their outlines are too rough to cut to; the map
        /// of the place reads), not cut to the rings
        var tile = false
    }

    // MARK: the level's inks

    /// light, middle and deep of the level, the relief's shade running between them (the diamond as ice: white
    /// alone showed no relief at all)
    static func ramp(_ level: BadgeLevel) -> (light: SIMD3<Double>, body: SIMD3<Double>, deep: SIMD3<Double>) {
        func c(_ hex: UInt32) -> SIMD3<Double> {
            SIMD3(Double((hex >> 16) & 0xff), Double((hex >> 8) & 0xff), Double(hex & 0xff)) / 255
        }
        switch level {
        case .lime: return (c(0xf6ffb8), c(0xc9df2a), c(0x5d6e06))
        case .blue: return (c(0xd2f2ff), c(0x5b9cf5), c(0x1c3d96))
        case .silver: return (c(0xfafbfc), c(0xaeb3bb), c(0x474d57))
        case .gold: return (c(0xfdf1c9), c(0xd2a83c), c(0x6e4c08))
        case .diamond: return (c(0xffffff), c(0xcfdcea), c(0x5f7590))
        }
    }

    // MARK: heights

    /// metres at a longitude and latitude (the sea's depth below nought), read between the picture's points
    static func height(_ r: Relief, _ b: UnsafeRawBufferPointer, lon: Double, lat: Double) -> Double {
        let w = r.width, h = r.height
        var x = (lon + 180) / 360 * Double(w) - 0.5
        let y = min(Double(h) - 1.001, max(0, (90 - lat) / 180 * Double(h) - 0.5))
        x = x.truncatingRemainder(dividingBy: Double(w)); if x < 0 { x += Double(w) }
        let x0 = Int(x), y0 = Int(y), fx = x - Double(x0), fy = y - Double(y0)
        let x1 = (x0 + 1) % w, y1 = min(h - 1, y0 + 1)
        func at(_ px: Int, _ py: Int) -> Double {
            let i = (py * w + px) * 2
            let d = Double(b[i]), up = Double(b[i + 1])
            if up > 0 { return 150 * expm1(up / 255 * log1p(5000.0 / 150)) }
            if d > 0 { return -25 * expm1(d / 255 * log1p(6000.0 / 25)) }
            return 0
        }
        let a = at(x0, y0) * (1 - fx) + at(x1, y0) * fx
        let c = at(x0, y1) * (1 - fx) + at(x1, y1) * fx
        return a * (1 - fy) + c * fy
    }

    // MARK: the picture

    /// the badge drawn at `px` square (its content within the middle, a little room round it)
    static func render(_ plan: Plan?, number: String?, swirl: Bool, level: BadgeLevel, px: Int, scale: CGFloat) -> UIImage? {
        guard px > 8, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let inks = ramp(level)
        func cg(_ v: SIMD3<Double>, _ a: Double = 1) -> CGColor { CGColor(srgbRed: v.x, green: v.y, blue: v.z, alpha: a) }
        let side = CGFloat(px), pad = side * 0.06
        // (CoreGraphics' y is up: the plans' y is down, turned once here)
        ctx.translateBy(x: 0, y: side); ctx.scaleBy(x: 1, y: -1)

        if let plan, let picture = shaded(plan, inks: inks, px: px) {
            // the content's rectangle, its own width to height kept
            let room = side - 2 * pad
            let w = plan.aspect >= 1 ? room : room * plan.aspect, h = plan.aspect >= 1 ? room / plan.aspect : room
            let frame = CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)
            ctx.saveGState()
            let path = CGMutablePath()
            if case .pole = plan.plane {
                path.addEllipse(in: frame)
            } else if plan.tile {
                let r = min(frame.width, frame.height) * 0.22
                path.addRoundedRect(in: frame, cornerWidth: r, cornerHeight: r)
            } else {
                for r in plan.rings where r.count > 2 {
                    path.addLines(between: r.map { CGPoint(x: frame.minX + $0.x * frame.width, y: frame.minY + $0.y * frame.height) })
                    path.closeSubpath()
                }
            }
            ctx.addPath(path); ctx.clip()
            // (drawn with y down, as it was shaded)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: frame.maxY + frame.minY); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(picture, in: frame)
            ctx.restoreGState()
            ctx.restoreGState()
        } else if swirl {
            // the streak's sun, flat in the level's middle colour
            let p = BadgeOutline.swirl.applying(CGAffineTransform(translationX: 0.5, y: 0.5)
                .concatenating(CGAffineTransform(scaleX: side - 2 * pad, y: -(side - 2 * pad)))
                .concatenating(CGAffineTransform(translationX: pad, y: side - pad)))
            ctx.addPath(p.cgPath); ctx.setFillColor(cg(inks.body)); ctx.fillPath()
        } else {
            // a disc, flat, its number printed in black (the app's ink)
            let disc = CGRect(x: pad, y: pad, width: side - 2 * pad, height: side - 2 * pad)
            ctx.setFillColor(cg(inks.body)); ctx.fillEllipse(in: disc)
            // (the text upright: the context is turned for the plans' y down)
            ctx.saveGState(); ctx.translateBy(x: 0, y: side); ctx.scaleBy(x: 1, y: -1)
            defer { ctx.restoreGState() }
            if let number, !number.isEmpty {
                let size = side * (number.count <= 2 ? 0.40 : number.count == 3 ? 0.31 : 0.24)
                let base = UIFont.systemFont(ofSize: size, weight: .semibold)
                let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
                let text = NSAttributedString(string: number, attributes: [.font: font, .foregroundColor: UIColor.black])
                let line = CTLineCreateWithAttributedString(text)
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                ctx.textPosition = CGPoint(x: side / 2 - bounds.midX, y: side / 2 - bounds.midY)
                CTLineDraw(line, ctx)
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: scale, orientation: .up)
    }

    /// the relief of a plan's box as a picture (y down): every point's height read through the plane, shaded from the
    /// north-west, in the level's ramp; the sea flat and pale where it is shown, nothing where it is not
    static func shaded(_ plan: Plan, inks: (light: SIMD3<Double>, body: SIMD3<Double>, deep: SIMD3<Double>), px: Int) -> CGImage? {
        guard let r = relief else { return nil }
        let room = Double(px) * 0.88
        let w = max(8, Int(plan.aspect >= 1 ? room : room * Double(plan.aspect)))
        let h = max(8, Int(plan.aspect >= 1 ? room / Double(plan.aspect) : room))
        // each point's longitude and latitude, and the metres one point spans
        var lonlat = [SIMD2<Double>](repeating: SIMD2(.nan, .nan), count: w * h)
        let metres: Double
        switch plan.plane {
        case .equalEarth(let box):
            for j in 0 ..< h {
                for i in 0 ..< w {
                    let x = box.x + (box.z - box.x) * (Double(i) + 0.5) / Double(w)
                    let y = box.y + (box.w - box.y) * (Double(j) + 0.5) / Double(h)
                    let g = EqualEarth.unproject(SIMD2(x, y))
                    lonlat[j * w + i] = SIMD2(g.lon, g.lat)
                }
            }
            // (1,000 map units are the equator's 40,075 km)
            metres = (box.z - box.x) / Double(w) * 40_075_000 / 1000
        case .pole(let edge):
            let reach = 90 - edge
            for j in 0 ..< h {
                for i in 0 ..< w {
                    let u = (Double(i) + 0.5) / Double(w) * 2 - 1, v = (Double(j) + 0.5) / Double(h) * 2 - 1
                    let d = (u * u + v * v).squareRoot()
                    guard d <= 1.02 else { continue }
                    lonlat[j * w + i] = SIMD2(atan2(u, v) * 180 / .pi, 90 - d * reach)
                }
            }
            metres = reach * 111_320 * 2 / Double(w)
        }
        var z = [Double](repeating: .nan, count: w * h)
        r.bytes.withUnsafeBytes { b in
            for k in 0 ..< w * h where !lonlat[k].x.isNaN { z[k] = height(r, b, lon: lonlat[k].x, lat: lonlat[k].y) }
        }
        // (the relief drawn steeper the wider the badge's land: a range shows its folds, a continent its mountains)
        let lift = min(30, max(4, metres / 420))
        let light = simd_normalize(SIMD3<Double>(-1, -1, 1.35))
        var px8 = [UInt8](repeating: 0, count: w * h * 4)
        for j in 0 ..< h {
            for i in 0 ..< w {
                let k = j * w + i
                let e = z[k]
                guard !e.isNaN else { continue }
                func at(_ a: Int, _ b: Int) -> Double {
                    let ii = min(w - 1, max(0, a)), jj = min(h - 1, max(0, b))
                    let v = z[jj * w + ii]; return v.isNaN ? e : v
                }
                let land = e > 0 || !plan.sea
                // the sea's floor in a whisper of the land's relief
                let gain = land ? lift : lift * 0.12
                let dx = (at(i + 1, j) - at(i - 1, j)) / (2 * metres) * gain
                let dy = (at(i, j + 1) - at(i, j - 1)) / (2 * metres) * gain
                let n = simd_normalize(SIMD3<Double>(-dx, -dy, 1))
                let lit = max(0, simd_dot(n, light)) / simd_dot(SIMD3(0, 0, 1), light)
                var c: SIMD3<Double>
                if land {
                    // flat land the middle colour; slopes to the light toward light, away toward deep
                    c = lit >= 1 ? simd_mix(inks.body, inks.light, SIMD3(repeating: min(1, (lit - 1) * 2.2)))
                                 : simd_mix(inks.deep, inks.body, SIMD3(repeating: max(0, lit)))
                } else {
                    // the sea: near white, a breath of the level's colour where it is deep (the land stands on it)
                    let deep = min(1, -e / 5000)
                    c = simd_mix(SIMD3(repeating: 0.985), inks.light, SIMD3(repeating: 0.35 + 0.45 * deep))
                }
                px8[k * 4] = UInt8(max(0, min(255, c.x * 255)))
                px8[k * 4 + 1] = UInt8(max(0, min(255, c.y * 255)))
                px8[k * 4 + 2] = UInt8(max(0, min(255, c.z * 255)))
                px8[k * 4 + 3] = 255
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(px8) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// the outlines of the natural regions some badges are about (a range's, a sea's), from the Places sets' own shapes
/// files, read once each
@MainActor
enum BadgeNatural {
    private static var files: [String: [String: [[SIMD2<Double>]]]] = [:]

    /// the region's outline (longitude, latitude), or nil while it can't be had
    static func rings(file: String, key: String) async -> [[SIMD2<Double>]]? {
        if let f = files[file] { return f[key] }
        guard case .ok(let d) = await Servers.data.file(file) else { return nil }
        let shapes = await Task.detached { UrbanFile.parse(d) }.value
        guard let shapes else { return nil }
        var f: [String: [[SIMD2<Double>]]] = [:]
        for s in shapes { f[s.key] = s.rings }
        files[file] = f
        return f[key]
    }

    /// a plan for a region's outline: its rings in the map's units, its box round them
    static func plan(file: String, key: String, sea: Bool) async -> BadgeFlat.Plan? {
        guard let rings = await rings(file: file, key: key), !rings.isEmpty else { return nil }
        // (in the map's own Equal Earth, as the map draws it)
        let pts = rings.map { $0.map { p -> SIMD2<Double> in let q = EqualEarth.project(lon: p.x, lat: p.y); return SIMD2(Double(q.x), Double(q.y)) } }
        let all = pts.flatMap { $0 }
        guard let x0 = all.map(\.x).min(), let x1 = all.map(\.x).max(), let y0 = all.map(\.y).min(), let y1 = all.map(\.y).max(),
              x1 > x0, y1 > y0 else { return nil }
        // (a tile round it with room on every side, never wider than twice its height: the Himalayas in their plains and
        // plateau, the Mediterranean in its lands)
        var mx = (x1 - x0) * 0.12, my = (y1 - y0) * 0.12
        let wide = (x1 - x0 + 2 * mx) / (y1 - y0 + 2 * my)
        if wide > 2 { my += ((x1 - x0 + 2 * mx) / 2 - (y1 - y0 + 2 * my)) / 2 }
        if wide < 0.8 { mx += ((y1 - y0 + 2 * my) * 0.8 - (x1 - x0 + 2 * mx)) / 2 }
        let a = x0 - mx, b = y0 - my, c = x1 + mx, d = y1 + my
        return BadgeFlat.Plan(plane: .equalEarth(box: SIMD4(a, b, c, d)), aspect: CGFloat((c - a) / (d - b)), sea: true, tile: true)
    }
}

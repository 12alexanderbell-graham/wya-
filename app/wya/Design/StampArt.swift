import SwiftUI
import UIKit
import CoreImage

/// THE STAMP ART (Part 4.3.4): the old app's 104 stamps, drawn once by Chromium into one pack in their own inks
/// (Resources/Stamps/stamps.wyaf, tools/stamps-render.py), so the phone never draws SVG. A place without art shows a
/// black circle until its own stamp is made. Same pack format as the flags, each entry with its
/// size: {id: [offset, length, width, height]}, pictures 360 px on their long side.
@MainActor
enum StampArt {
    typealias Pack = (index: [String: [Int]], data: Data, base: Int)
    /// the stamps made since first (stamps-gen.wyaf: new countries, and old ones redrawn closer to their real stamp, as
    /// Monaco's real arms), then the old app's 104
    private static let packs: [Pack] = ["stamps-gen", "stamps"].compactMap(load)
    private static func load(_ name: String) -> Pack? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wyaf"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 12,
              d.prefix(4) == Data("WYAF".utf8) else { return nil }
        let hl = Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
        guard 12 + hl <= d.count,
              let head = try? JSONSerialization.jsonObject(with: d.subdata(in: 12 ..< 12 + hl)) as? [String: Any],
              let items = head["flags"] as? [String: [Int]] else { return nil }
        return (items, d, 12 + hl)
    }
    private static var cache: [String: UIImage] = [:]

    /// every place with art
    static var ids: [String] { Array(Set(packs.flatMap { $0.index.keys }).subtracting(withdrawn)) }

    /// art that is no real stamp, shown as the black circle like any place without its stamp: Andorra's (a drawn
    /// badge; Andorra stamps no passports), and the ones made without a photo of the real stamp to follow (Réunion
    /// and Mayotte drawn on another series' pattern, Taiwan and Turkey plausible designs, Indonesia's unsure). A
    /// stamp is the real one made from its images or the black circle, nothing between; each comes back when a photo
    /// of its real stamp is found.
    static let withdrawn: Set<String> = ["re", "yt"]

    /// the stamp's picture (its own inks), or nil when the place has no art yet each stamped country's day, set with
    /// the passport's order (MarkStore.passportOrder)
    static var days: [String: String] = [:] { didSet { if days != oldValue { cache = [:] } } }

    static func image(_ id: String) -> UIImage? {
        if let i = cache[id] { return i }
        guard !withdrawn.contains(id), let p = packs.first(where: { $0.index[id] != nil }), let e = p.index[id], e.count >= 2 else {
            // A PLACE WITHOUT ITS OWN STAMP YET: a plain black circle, no text, until its real stamp is made from
            // images of its real one; every place gets its own. A drawn stand-in stamp is never shown
            return blank
        }
        let s = p.base + e[0]
        guard s + e[1] <= p.data.count, let art = UIImage(data: p.data.subdata(in: s ..< s + e[1]), scale: 3) else { return nil }
        // ITS WORDS SET OVER ITS ART (the old app's RealStampView): the pack holds the art alone; each stamp's words,
        // your date in its own form among them, are set here for its day
        let worded = RealStamps.stamp(id).map { withWords(art, $0, day: days[id].flatMap(RealStamps.Day.init(iso:)) ?? today) } ?? art
        let ui = inked ? Self.inked(worded, seed: id) : worded
        cache[id] = ui
        return ui
    }

    private static var today: RealStamps.Day {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return RealStamps.Day(y: c.year ?? 2026, m: c.month ?? 1, d: c.day ?? 1)
    }

    /// AS A RUBBER STAMP LEAVES IT: the ink never lies perfectly even; it is a little lighter where the pad pressed
    /// less, in broad soft patches, and the paper's grain leaves small gaps. Each stamp's pattern comes from its own
    /// id, so it is the same every time it is shown
    static var inked = true
    private static let ci = CIContext()
    private static func inked(_ img: UIImage, seed: String) -> UIImage {
        guard let cg = img.cgImage else { return img }
        let src = CIImage(cgImage: cg)
        let e = src.extent
        var h: UInt32 = 2166136261
        for b in seed.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        let ox = CGFloat(h & 0x3ff), oy = CGFloat((h >> 10) & 0x3ff)
        guard let rnd = CIFilter(name: "CIRandomGenerator")?.outputImage else { return img }
        func gray(_ i: CIImage, _ k: CGFloat, _ bias: CGFloat) -> CIImage {
            i.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)])
        }
        let px = max(1, e.width / 360)   // the art's pixels to a stamp point at the page's size
        // broad patches: 84 percent to full ink
        let patches = gray(rnd.transformed(by: CGAffineTransform(translationX: ox, y: oy).scaledBy(x: 28 * px, y: 28 * px))
                            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14 * px]), 0.16, 0.84)
        // the paper's gaps: the brightest few percent of a finer noise, each a couple of points, ink kept at 40 percent there
        let fine = rnd.transformed(by: CGAffineTransform(translationX: oy, y: ox).scaledBy(x: 2.2 * px, y: 2.2 * px))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8 * px])
        let spots = gray(fine, 9, -8).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1), "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
        let gaps = gray(spots, -0.6, 1)
        let mask = gaps.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: patches])
            .cropped(to: e).applyingFilter("CIMaskToAlpha")
        let out = src.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty().cropped(to: e), kCIInputMaskImageKey: mask])
        guard let res = ci.createCGImage(out, from: e) else { return img }
        return UIImage(cgImage: res, scale: img.scale, orientation: .up)
    }

    /// the art with the stamp's words drawn on it, at the art's own size
    private static func withWords(_ art: UIImage, _ st: RealStamps.Stamp, day: RealStamps.Day) -> UIImage {
        let size = art.size
        let k = size.width / st.w
        let f = UIGraphicsImageRendererFormat(); f.scale = 3
        return UIGraphicsImageRenderer(size: size, format: f).image { r in
            art.draw(in: CGRect(origin: .zero, size: size))
            let ctx = r.cgContext
            ctx.scaleBy(x: k, y: k)
            for slot in st.slots {
                let words = RealStamps.words(slot, day)
                guard !words.isEmpty else { continue }
                let font = uiFont(slot.font, slot.size, slot.weight)
                let text = NSAttributedString(string: words, attributes: [
                    .font: font, .kern: slot.tracking, .foregroundColor: colour(slot.fill)])
                let w = text.size().width
                guard w > 0 else { continue }
                // squeezed only if it runs over its room, or set to its length exactly
                var sx: CGFloat = 1
                if let L = slot.length { sx = L / w } else if let m = slot.fit, w > m { sx = m / w }
                let dx: CGFloat = slot.anchor == .start ? 0 : slot.anchor == .middle ? -w * sx / 2 : -w * sx
                ctx.saveGState()
                let m = slot.m
                if m != .identity { ctx.concatenate(CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx, ty: m.ty)) }
                ctx.translateBy(x: slot.x + dx, y: slot.y)
                ctx.scaleBy(x: sx, y: 1)
                // (drawn from its baseline: the slot's y is where the letters sit)
                text.draw(at: CGPoint(x: 0, y: -font.ascender))
                ctx.restoreGState()
            }
        }
    }

    /// the stamps' type: Barlow Condensed (an Arabic or Persian figure in it falls to Noto Sans Arabic), Caveat, Noto
    /// Serif, Courier New; the phone's own for Japanese and Devanagari
    private static func uiFont(_ f: RealStamps.Face, _ size: Double, _ weight: Int) -> UIFont {
        func named(_ n: String) -> UIFont { UIFont(name: n, size: size) ?? .systemFont(ofSize: size, weight: weight >= 700 ? .bold : .semibold) }
        switch f {
        case .barlow:
            let n = weight >= 700 ? "BarlowCondensed-Bold" : weight >= 600 ? "BarlowCondensed-SemiBold" : "BarlowCondensed-Medium"
            let d = UIFontDescriptor(fontAttributes: [.name: n, .cascadeList: [UIFontDescriptor(fontAttributes: [.name: "NotoSansArabic-Bold"])]])
            return UIFont(descriptor: d, size: size)
        case .serif: return named(weight >= 700 ? "NotoSerif-Bold" : "NotoSerif-SemiBold")
        case .caveat: return named("Caveat-SemiBold")
        case .courier: return named(weight >= 700 ? "CourierNewPS-BoldMT" : "CourierNewPSMT")
        case .japanese, .devanagari: return .systemFont(ofSize: size, weight: weight >= 700 ? .bold : .regular)
        }
    }

    /// , "#000" (an ink as the drawings wrote it)
    private static func colour(_ hex: String) -> UIColor {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return .black }
        return UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    /// the black circle a place without art shows, made once
    private static let blank: UIImage = {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }())
        return r.image { _ in
            UIColor(Palette.ink).setFill()
            // (a stamp's height on the page, not its slot's: a circle the full slot stood larger than every stamp by it)
            UIBezierPath(ovalIn: CGRect(x: 14, y: 14, width: 72, height: 72)).fill()
        }
    }()
}

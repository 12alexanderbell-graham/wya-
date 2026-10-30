import SwiftUI
import UIKit

/// THE FLAGS for rows (search results first). Never simplified: every flag with its full arms and emblems, from
/// flag-icons' square compositions (MIT, Panayiotis Lipiridis) and, for the places it lacks (Abkhazia, South Ossetia,
/// Transnistria, Northern Cyprus, Somaliland, Rapa Nui, Mount Athos, Bonaire, Saba, Sint Eustatius), Wikimedia Commons'
/// flags (public domain), cut square round their emblem's side. The sovereign base areas fly the United Kingdom's flag,
/// the Coral Sea and Ashmore and Cartier Islands Australia's. Drawn by Chromium into one pack of 132-pixel pictures
/// (tools/flags- render.py, flags-pack.py), so the phone never draws SVG. Never cut blindly: a flag whose emblem sits
/// by a corner or at the fly (Oman, Malta, Uruguay, Fiji, Bermuda, the British ensigns with badges) is drawn a little
/// smaller and pulled toward its emblem, its stripes and fields carried out to the edge, so the circle keeps the emblem
/// whole. flags-round.wyaf: "WYAF", u32 version 1, u32 head length, a JSON head {"size": 132, "flags": {id: [offset,
/// length]}}, then the PNGs.
@MainActor
enum Flags {
    private static let pack = load("flags-round")
    /// THE SQUARE AND 4:3 FLAGS AS VECTORS (Part 17.4 D14: no flag ships as a raster): one PDF each in
    /// flags-vector.wyaf (head {"square": {id: [offset, length]}, "wide": {...}}; tools/flags-vector-*.py), drawn by
    /// iOS itself at the size a row asks for and kept; never rounded, never in a box. The old 132-pixel square pack
    /// answers only if the vector pack is missing.
    private static let vectorPack: (square: [String: [Int]], wide: [String: [Int]], data: Data, base: Int)? = {
        guard let url = Bundle.main.url(forResource: "flags-vector", withExtension: "wyaf"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 12,
              d.prefix(4) == Data("WYAF".utf8) else { return nil }
        let hl = Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
        guard 12 + hl <= d.count,
              let head = try? JSONSerialization.jsonObject(with: d.subdata(in: 12 ..< 12 + hl)) as? [String: Any],
              let sq = head["square"] as? [String: [Int]], let wide = head["wide"] as? [String: [Int]] else { return nil }
        #if DEBUG
        NSLog("wya flags: vector pack, %d square, %d 4:3", sq.count, wide.count)
        #endif
        return (sq, wide, d, 12 + hl)
    }()
    private static let squarePack = load("flags-square")
    private static var squareCache: [String: Image] = [:]
    private static var wideCache: [String: Image] = [:]

    /// the place's square flag, or nil if there is none
    static func square(_ id: String) -> Image? {
        if let i = squareCache[id] { return i }
        if let v = vectorPack, let e = v.square[id], let ui = draw(v.data, v.base, e, side) {
            let img = Image(uiImage: ui)
            squareCache[id] = img
            return img
        }
        guard let p = squarePack, let e = p.index[id], e.count == 2 else { return nil }
        let s = p.base + e[0]
        guard s + e[1] <= p.data.count, let ui = UIImage(data: p.data.subdata(in: s ..< s + e[1]), scale: 3) else { return nil }
        let img = Image(uiImage: ui)
        squareCache[id] = img
        return img
    }

    /// the place's 4:3 flag (pages, Part 16; cards, Part 7), or nil if there is none
    static func wide(_ id: String) -> Image? {
        if let i = wideCache[id] { return i }
        guard let v = vectorPack, let e = v.wide[id], let ui = draw(v.data, v.base, e, CGSize(width: 64, height: 48)) else { return nil }
        let img = Image(uiImage: ui)
        wideCache[id] = img
        return img
    }

    /// rows draw flags at 28 pt; drawn at 32 so they stay sharp a little above that
    private static let side = CGSize(width: 32, height: 32)

    /// THE ROWS' FLAGS DRAWN AHEAD, in the background (the Stamped list's rows then never wait on a PDF; drawing 34 on
    /// the main thread as the list opened cost a 220 ms hitch)
    static func prewarm(_ ids: [String]) {
        guard let v = vectorPack else { return }
        let data = v.data, base = v.base
        let jobs = ids.compactMap { id in v.square[id].map { (id, $0) } }.filter { squareCache[$0.0] == nil }
        guard !jobs.isEmpty else { return }
        Task.detached(priority: .utility) {
            var done: [(String, UIImage)] = []
            for (id, e) in jobs { autoreleasepool { if let ui = Flags.draw(data, base, e, Flags.side) { done.append((id, ui)) } } }
            let drawn = done
            await MainActor.run { for (id, ui) in drawn where squareCache[id] == nil { squareCache[id] = Image(uiImage: ui) } }
        }
    }

    /// one PDF of the pack drawn at a size (points, at the screen's scale), its page filling it
    nonisolated private static func draw(_ d: Data, _ base: Int, _ e: [Int], _ size: CGSize) -> UIImage? {
        guard e.count == 2, base + e[0] + e[1] <= d.count,
              let provider = CGDataProvider(data: d.subdata(in: base + e[0] ..< base + e[0] + e[1]) as CFData),
              let doc = CGPDFDocument(provider), let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            let c = ctx.cgContext
            // PDF space is y-up: flip, then scale the page's box onto the size
            c.translateBy(x: 0, y: size.height)
            c.scaleBy(x: size.width / box.width, y: -size.height / box.height)
            c.translateBy(x: -box.minX, y: -box.minY)
            c.interpolationQuality = .high
            c.drawPDFPage(page)
        }
    }

    private static func load(_ name: String) -> (index: [String: [Int]], data: Data, base: Int)? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wyaf"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 12,
              d.prefix(4) == Data("WYAF".utf8) else { return nil }
        let hl = Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
        guard 12 + hl <= d.count,
              let head = try? JSONSerialization.jsonObject(with: d.subdata(in: 12 ..< 12 + hl)) as? [String: Any],
              let flags = head["flags"] as? [String: [Int]] else { return nil }
        return (flags, d, 12 + hl)
    }
    private static var cache: [String: Image] = [:]
    /// every flag in the pack (for the review sheet)
    static var ids: [String] { pack.map { Array($0.index.keys) } ?? [] }

    /// the place's round flag, or nil if there is none
    static func round(_ id: String) -> Image? {
        if let i = cache[id] { return i }
        guard let p = pack, let e = p.index[id], e.count == 2 else { return nil }
        let s = p.base + e[0]
        guard s + e[1] <= p.data.count, let ui = UIImage(data: p.data.subdata(in: s ..< s + e[1]), scale: 3) else { return nil }
        let img = Image(uiImage: ui)
        cache[id] = img
        return img
    }
}

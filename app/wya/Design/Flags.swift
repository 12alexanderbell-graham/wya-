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
    private static let pack: (index: [String: [Int]], data: Data, base: Int)? = {
        guard let url = Bundle.main.url(forResource: "flags-round", withExtension: "wyaf"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 12,
              d.prefix(4) == Data("WYAF".utf8) else { return nil }
        let hl = Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
        guard 12 + hl <= d.count,
              let head = try? JSONSerialization.jsonObject(with: d.subdata(in: 12 ..< 12 + hl)) as? [String: Any],
              let flags = head["flags"] as? [String: [Int]] else { return nil }
        return (flags, d, 12 + hl)
    }()
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

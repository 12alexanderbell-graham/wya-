import SwiftUI
import UIKit

/// THE STAMP ART (Part 4.3.4): the old app's 104 stamps, drawn once by Chromium into one pack in their own inks
/// (Resources/Stamps/stamps.wyaf, tools/stamps-render.py), so the phone never draws SVG. A place without art shows its
/// slot's outline until the generator (Step 6) makes its stamp. Same pack format as the flags, each entry with its
/// size: {id: [offset, length, width, height]}, pictures 360 px on their long side.
@MainActor
enum StampArt {
    private static let pack: (index: [String: [Int]], data: Data, base: Int)? = {
        guard let url = Bundle.main.url(forResource: "stamps", withExtension: "wyaf"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 12,
              d.prefix(4) == Data("WYAF".utf8) else { return nil }
        let hl = Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
        guard 12 + hl <= d.count,
              let head = try? JSONSerialization.jsonObject(with: d.subdata(in: 12 ..< 12 + hl)) as? [String: Any],
              let items = head["flags"] as? [String: [Int]] else { return nil }
        return (items, d, 12 + hl)
    }()
    private static var cache: [String: UIImage] = [:]

    /// every place with art
    static var ids: [String] { pack.map { Array($0.index.keys) } ?? [] }

    /// the stamp's picture (its own inks), or nil when the place has no art yet
    static func image(_ id: String) -> UIImage? {
        if let i = cache[id] { return i }
        guard let p = pack, let e = p.index[id], e.count >= 2 else { return nil }
        let s = p.base + e[0]
        guard s + e[1] <= p.data.count, let ui = UIImage(data: p.data.subdata(in: s ..< s + e[1]), scale: 3) else { return nil }
        cache[id] = ui
        return ui
    }
}

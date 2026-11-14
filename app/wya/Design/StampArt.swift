import SwiftUI
import UIKit

/// THE STAMP ART (Part 4.3.4): the old app's 104 stamps, drawn once by Chromium into one pack in their own inks
/// (Resources/Stamps/stamps.wyaf, tools/stamps-render.py), so the phone never draws SVG. A place without art shows its
/// slot's outline until the generator (Step 6) makes its stamp. Same pack format as the flags, each entry with its
/// size: {id: [offset, length, width, height]}, pictures 360 px on their long side.
@MainActor
enum StampArt {
    typealias Pack = (index: [String: [Int]], data: Data, base: Int)
    /// the old app's art first, then the generator's (Step 6: `stamps-gen.wyaf`, made by tools/stamp-generator.py once
    /// its first 10 have been approved; until then there is no such file and only the 104 show)
    private static let packs: [Pack] = ["stamps", "stamps-gen"].compactMap(load)
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
    static var ids: [String] { Array(Set(packs.flatMap { $0.index.keys })) }

    /// the stamp's picture (its own inks), or nil when the place has no art yet
    static func image(_ id: String) -> UIImage? {
        if let i = cache[id] { return i }
        guard let p = packs.first(where: { $0.index[id] != nil }), let e = p.index[id], e.count >= 2 else {
            // (14 Nov: a place without art had a blank passport page; until the generator's stamps come, a plain
            // stamp drawn here: its name and code in one of three inks, two ruled edges)
            // -- shortcut: drawn stamp; upgrade when the generator's pack (stamps-gen.wyaf) is approved and shipped
            let ui = drawn(id)
            cache[id] = ui
            return ui
        }
        let s = p.base + e[0]
        guard s + e[1] <= p.data.count, let ui = UIImage(data: p.data.subdata(in: s ..< s + e[1]), scale: 3) else { return nil }
        cache[id] = ui
        return ui
    }

    /// a plain stamp for a place with no art: ENTRY, its name, its code, ruled twice round, in one of three inks
    private static func drawn(_ id: String) -> UIImage? {
        let code = id.split(separator: "/").last.map(String.init) ?? id
        let name = (code.count == 2 ? Locale(identifier: "en_US").localizedString(forRegionCode: code.uppercased()) : nil) ?? code
        var h: UInt32 = 2166136261
        for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        let inks = [Color(hex: 0x1d1d1f), Color(hex: 0xb8382a), Color(hex: 0x2c5aa0)]
        let ink = inks[Int(h % 3)]
        let round = h & 8 == 0
        let stamp = VStack(spacing: 3) {
            Text("ENTRY").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
            Text(name.uppercased()).font(.system(size: 14, weight: .heavy, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.45)
            Text(code.uppercased()).font(.system(size: 20, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .frame(width: 150, height: round ? 110 : 92)
        .overlay {
            if round {
                Ellipse().strokeBorder(ink, lineWidth: 3)
                Ellipse().strokeBorder(ink, lineWidth: 1).padding(6)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ink, lineWidth: 3)
                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(ink, lineWidth: 1).padding(6)
            }
        }
        .opacity(0.88)
        let r = ImageRenderer(content: stamp)
        r.scale = 3
        return r.uiImage
    }
}

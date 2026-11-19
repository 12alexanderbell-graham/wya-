import SwiftUI
import UIKit

/// A PLACE'S PHOTOS (Part 4.4.3, the shared Photo object): each photo picked in Details is kept on the phone as our
/// own copy at most 1200 px on its long side (Photos' id kept beside it when the picker gives one), so the tile still
/// shows if the original goes from the library. Never uploaded. A removed photo's file stays until the sheet's undo can
/// no longer bring it back (not yet cleared: the files are small).
nonisolated enum DetailPhotos {
    static var dir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("detail-photos")
    }
    // (NSCache is safe from any thread)
    nonisolated(unsafe) private static let shown = NSCache<NSString, UIImage>()
    /// a picked photo kept: its file's name, or nil when it can't be read or written
    static func keep(_ data: Data) -> String? {
        guard let dir, let full = UIImage(data: data) else { return nil }
        let longer = max(full.size.width, full.size.height)
        let scale = min(1, 1200 / max(1, longer))
        let small = scale < 1
            ? full.preparingThumbnail(of: CGSize(width: full.size.width * scale, height: full.size.height * scale)) ?? full
            : full
        let name = UUID().uuidString + ".jpg"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let jpeg = small.jpegData(compressionQuality: 0.85),
              (try? jpeg.write(to: dir.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
        shown.setObject(small, forKey: name as NSString)
        return name
    }
    /// a kept photo, read once
    static func image(_ name: String) -> UIImage? {
        if let i = shown.object(forKey: name as NSString) { return i }
        guard let dir, let i = UIImage(contentsOfFile: dir.appendingPathComponent(name).path) else { return nil }
        shown.setObject(i, forKey: name as NSString)
        return i
    }
}

/// A POSTAGE STAMP'S EDGE (4.4.3: a photo added in Details is drawn as a stamp): a rectangle whose four sides
/// are bitten by half circles, evenly spaced and clear of the corners (the circles taken out of the paper)
struct PostageEdge: Shape {
    /// each bite's radius
    var bite: CGFloat = 2.5
    func path(in r: CGRect) -> Path {
        var p = Path()
        func side(_ from: CGPoint, _ to: CGPoint) {
            let len = hypot(to.x - from.x, to.y - from.y)
            // a bite every 3 radii or so, a whole number of them, none on a corner
            let n = max(1, Int((len / (bite * 3)).rounded()) - 1)
            for i in 1 ... n {
                let t = CGFloat(i) / CGFloat(n + 1)
                let c = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                p.addEllipse(in: CGRect(x: c.x - bite, y: c.y - bite, width: bite * 2, height: bite * 2))
            }
        }
        side(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY))
        side(CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY))
        side(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY))
        side(CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY))
        return Path(r).subtracting(p)
    }
}

/// one photo as a 72 pt postage stamp: the white perforated paper, the picture 6 pt inside it
struct PhotoStampTile: View {
    let file: String
    var body: some View {
        ZStack {
            PostageEdge().fill(Palette.white)
            if let i = DetailPhotos.image(file) {
                Image(uiImage: i).resizable().scaledToFill()
                    .frame(width: 60, height: 60).clipped()
            } else {
                Palette.ink.opacity(0.08).frame(width: 60, height: 60)
            }
        }
        .frame(width: 72, height: 72)
        .compositingGroup()
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

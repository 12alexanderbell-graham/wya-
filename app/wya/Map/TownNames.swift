import UIKit

/// THE NAMES ON THE PLACES MAP (7.4: "the Apple Maps way"; the old app's TownNames rules, its labels over the map):
/// 13 pt semibold ink with a 2 pt cream halo; from 3x the country's framing zoom; the capital first, then regional
/// capitals, then by people; a name only once its town's shape is 12 pt across; at most 8 on screen, 4 pt clear of each
/// other, never under the head, the zoom column or the 25% water; a name that is up keeps its place while you zoom.
/// Each name rolls in (its letters rising into place) across its own band of zoom: the progress is the zoom's, so a
/// pinch scrubs it both ways and nothing arrives on a timer (29 Oct 02:10: "It needs to zoom in consistently, like
/// mathematically").
@MainActor
final class TownNamesView: UIView {
    private struct Shown { let i: Int; let holder: UIView; let halo: UILabel; let ink: UILabel; let size: CGSize }
    private var shown: [Int: Shown] = [:]
    private var key: String?
    private var orderFor: (cc: String, dots: Bool, order: [Int])?
    private static let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let cream = UIColor(red: 0xfb / 255, green: 0xf6 / 255, blue: 0xf2 / 255, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    /// called every frame the map draws; `moving`: the camera or a finger is moving it (at rest no name is left half
    /// rolled: nothing cut off at rest, 30 Oct 16:04)
    func update(_ m: MapController, moving: Bool) {
        guard m.placesMode || m.regionTowns, let cc = m.placeOpenID, let sc = m.townScenes[cc], let k0 = m.continentK else { clear(); return }
        if key != cc { clear(); key = cc }
        let k = m.k
        // from 3x the country's framing zoom (each name rolling in across its own band from there)
        guard k >= 3 * k0 * 0.999 else { clear(); return }
        let W = bounds.width
        let room = m.layout.room(sheetTop: m.layout.top(.quarter))
        let box = CGRect(x: 6, y: room.lowerBound, width: W - 6 - 64, height: room.upperBound - room.lowerBound)
        // the candidates, in order: capital, regional capitals, then by people (the scene is biggest first)
        // (worked out once per country, and only the towns that can ever be named: those with a shape, or every town with
        // Town dots on)
        let dotsOn = MapSettingsStore.shared.value.townDots
        if orderFor?.cc != cc || orderFor?.dots != dotsOn {
            var o: [Int] = []
            for kind in [2, 1, 0] { for i in sc.towns.indices where sc.towns[i].kind == kind && (dotsOn || sc.runs[i] != nil) { o.append(i) } }
            orderFor = (cc, dotsOn, o)
        }
        var order = orderFor?.order ?? []
        // the ones up first (they keep their places)
        let up = Set(shown.keys)
        order = order.filter { up.contains($0) } + order.filter { !up.contains($0) }
        var taken: [CGRect] = []
        var keep: [Int: CGFloat] = [:]
        for i in order {
            guard keep.count < 8 else { break }
            // a name only once its shape is 12 pt across (no shape, no name, unless Town dots are on)
            let b = sc.box(i)
            let across = CGFloat(max(b.z - b.x, b.w - b.y)) * CGFloat(k)
            let dots = MapSettingsStore.shared.value.townDots
            guard across >= 12 || (dots && sc.runs[i] == nil) else { continue }
            // its roll: from 12 pt across to 16 (and from 3x to 3.3x the framing zoom), by the zoom
            let a = min(1, max(0, (across - 12) / 4)), z = min(1, max(0, CGFloat((k / k0 - 3) / 0.3)))
            var p = dots && sc.runs[i] == nil ? z : min(a, z)
            if !moving { p = p >= 0.5 ? 1 : 0 }
            guard p > 0.001 || shown[i] != nil else { continue }
            let size = shown[i]?.size ?? Self.measure(sc.towns[i].name)
            let pt = m.screenPoint(SIMD2(Double(sc.at[i].x), Double(sc.at[i].y)))
            let r = CGRect(x: pt.x - size.width / 2, y: pt.y - size.height / 2, width: size.width, height: size.height)
            guard box.contains(r) else { continue }
            let clear4 = r.insetBy(dx: -4, dy: -4)
            guard !taken.contains(where: { $0.intersects(clear4) }) else { continue }
            taken.append(r)
            keep[i] = p
            place(i, name: sc.towns[i].name, at: r, progress: p, size: size)
        }
        for (i, s) in shown where keep[i] == nil { s.holder.removeFromSuperview(); shown[i] = nil }
    }

    private func place(_ i: Int, name: String, at r: CGRect, progress p: CGFloat, size: CGSize) {
        let s: Shown
        if let have = shown[i] { s = have } else {
            let holder = UIView()
            holder.clipsToBounds = true
            holder.isUserInteractionEnabled = false
            let halo = UILabel(), ink = UILabel()
            halo.attributedText = NSAttributedString(string: name, attributes: [
                .font: Self.font, .foregroundColor: Self.cream, .strokeColor: Self.cream, .strokeWidth: 4 * 100 / 13,
            ])
            ink.attributedText = NSAttributedString(string: name, attributes: [.font: Self.font, .foregroundColor: UIColor.black])
            halo.textAlignment = .center; ink.textAlignment = .center
            holder.addSubview(halo); holder.addSubview(ink)
            addSubview(holder)
            s = Shown(i: i, holder: holder, halo: halo, ink: ink, size: size)
            shown[i] = s
        }
        // the holder is the name's box with room for its halo; the letters rise into it by the zoom's progress
        let pad: CGFloat = 3
        s.holder.frame = r.insetBy(dx: -pad, dy: -pad)
        let y = pad + (1 - p) * (size.height + pad)
        let f = CGRect(x: pad, y: y, width: size.width, height: size.height)
        s.halo.frame = f; s.ink.frame = f
        s.holder.isHidden = p <= 0.001
    }

    private static func measure(_ name: String) -> CGSize {
        let z = (name as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(z.width) + 2, height: ceil(z.height))
    }

    private func clear() {
        for s in shown.values { s.holder.removeFromSuperview() }
        shown = [:]
    }
}

import UIKit
import SwiftUI

/// THE NAMES ON THE PLACES MAP (7.4: "the Apple Maps way"; the old app's TownNames rules, its labels over the map):
/// 13 pt semibold ink with a 2 pt cream halo; from 3x the country's framing zoom; the capital first, then regional
/// capitals, then by people; a name only once its town's shape is 12 pt across; at most 8 on screen, 4 pt clear of each
/// other, never under the head, the zoom column or the 25% water; a name keeps its place while you zoom (it is pinned to
/// its town), but a bigger town's name always wins the room (31 Oct: Frankfurt was kept out by eight smaller names
/// that came up first on the way in).
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
        let own = ownMarks(m)
        let named = names(m, moving: moving, taken: own)
        thingMarks(m, taken: named)
    }

    // MARK: THINGS' MARKS (7.4, D5; 31 Oct 01:17: "it needs to be really elegant. Think about how Apple Maps would do it"):
    // as Apple Maps shows its places: a thing comes with its name or not at all (a mark without words says nothing), by
    // the zoom across its fame's own band (World Heritage and the best known, in 40+ Wikipedias, from 2.5x the country's
    // framing zoom, 12+ from 5x, 4+ from 9x, the rest from 16x; the best known first within each);
    // its mark small and round, growing with the zoom from 6 pt to 10 pt over that band, never bigger; the map's darker
    // grey, lime when stamped, blue when wished; no outline, no shadow; its name (12 pt semibold, the cream halo) beside it on the right; a thing whose name has no room (a town's name, another thing) is not shown,
    // except one you stamped or wished, whose mark always shows; famous first, at most 40 on screen. The kind's icon
    // inside waits for the twelve kinds' icons (their review, Step 3b).
    private var thingViews: [String: (dot: UIView, name: UILabel)] = [:]
    private static let thingFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
    /// each thing's name's width (measured once)
    private var thingWidths: [String: CGFloat] = [:]
    /// what the marks were last laid out for (the camera, the room, the marks, the town names): unchanged, nothing is done
    private var thingKey: [Double] = []
    private func thingMarks(_ m: MapController, taken named: [CGRect]) {
        guard m.placesMode, let cc = m.placeOpenID, let all = ThingStore.shared.things(cc), let k0 = m.continentK else {
            clearThings(); m.thingFrames = [:]; thingKey = []; return
        }
        let marksNow = Double(MarkStore.shared.marks.count) + Double(MarkStore.shared.marks.values.filter { $0.stamped }.count) * 1e6
        let key: [Double] = [m.c.x, m.c.y, m.k, Double(bounds.width), Double(bounds.height), marksNow, Double(all.count),
                             Double(m.thingPressed?.hashValue ?? 0), Double(named.count)]
        guard key != thingKey else { return }
        thingKey = key
        let z = m.k / k0
        let room = m.layout.room(sheetTop: m.layout.top(.quarter))
        let box = CGRect(x: 6, y: room.lowerBound, width: bounds.width - 6 - 64, height: room.upperBound - room.lowerBound)
        var taken = named
        var frames: [String: CGRect] = [:]
        var named = Set<String>()
        for t in all {
            guard frames.count < 40 else { break }
            let st = MarkStore.shared.state(t.key)
            // (one found by search and shown is marked too while it is darkened)
            let marked = st.stamped || st.wished || m.thingPressed == t.id
            let start: Double = t.fame >= 3 ? 2.5 : t.fame == 2 ? 5 : t.fame == 1 ? 9 : 16
            guard z >= start || m.thingPressed == t.id else { continue }
            let q = m.screenPoint(SIMD2(Double(t.at.x), Double(t.at.y)))
            guard box.contains(q) else { continue }
            let u = CGFloat(min(1, max(0, (z - start) / start)))
            let size = 6 + 4 * u * u * (3 - 2 * u)
            let r = CGRect(x: q.x - size / 2, y: q.y - size / 2, width: size, height: size)
            let w = thingWidths[t.id] ?? {
                let w = min(150, ceil((t.name as NSString).size(withAttributes: [.font: Self.thingFont]).width) + 4)
                thingWidths[t.id] = w
                return w
            }()
            // its name on the right; where that has no room, on the left, then under, then over (as Apple Maps moves a label)
            let places = [CGRect(x: r.maxX + 3, y: q.y - 8, width: w, height: 16),
                          CGRect(x: r.minX - 3 - w, y: q.y - 8, width: w, height: 16),
                          CGRect(x: q.x - w / 2, y: r.maxY + 1, width: w, height: 16),
                          CGRect(x: q.x - w / 2, y: r.minY - 17, width: w, height: 16)]
            let markFree = !taken.contains { $0.intersects(r.insetBy(dx: -2, dy: -2)) }
            let at = places.firstIndex { nr in box.contains(nr) && !taken.contains { $0.intersects(nr.insetBy(dx: -3, dy: -3)) } }
            let nameFree = at != nil
            let nr = places[at ?? 0]
            guard (markFree && (nameFree || marked)) || m.thingPressed == t.id else { continue }
            let v = thingViews[t.id] ?? {
                let d = UIView(), l = UILabel()
                d.isUserInteractionEnabled = false; l.isUserInteractionEnabled = false
                l.attributedText = NSAttributedString(string: t.name, attributes: [
                    .font: Self.thingFont, .foregroundColor: UIColor.black, .strokeColor: Self.cream, .strokeWidth: -3.0,
                ])
                l.lineBreakMode = .byTruncatingTail
                addSubview(d); addSubview(l)
                thingViews[t.id] = (d, l)
                return (d, l)
            }()
            v.dot.backgroundColor = m.thingPressed == t.id ? Self.pressed
                : st.stamped ? UIColor(Palette.lime) : st.wished ? UIColor(Palette.blue) : UIColor(Palette.beigeDark)
            v.dot.frame = r
            v.dot.layer.cornerRadius = size / 2
            taken.append(r)
            frames[t.id] = r
            v.name.frame = nr
            v.name.textAlignment = at == 1 ? .right : (at ?? 0) >= 2 ? .center : .left
            v.name.isHidden = !nameFree
            if nameFree { taken.append(nr); named.insert(t.id) }
        }
        for (id, v) in thingViews where frames[id] == nil { v.dot.removeFromSuperview(); v.name.removeFromSuperview(); thingViews[id] = nil }
        // (a named thing answers a finger on its name too)
        var hits = frames
        for id in named { if let f = frames[id], let v = thingViews[id] { hits[id] = f.union(v.name.frame) } }
        m.thingFrames = hits
    }
    private static let pressed = UIColor(red: 0xa1 / 255, green: 0x9e / 255, blue: 0x95 / 255, alpha: 1)
    private func clearThings() {
        for v in thingViews.values { v.dot.removeFromSuperview(); v.name.removeFromSuperview() }
        thingViews = [:]
    }

    // MARK: YOUR OWN PLACES' MARKS (7.8; 31 Oct 01:17: a lime circle is right for these, "just do it correctly ... really
    // elegant ... how Apple Maps would do it"): a small dot when the map is far out, growing with the zoom (by the zoom,
    // never on a timer) to a 20 pt circle close in; lime when stamped, blue when wished, cream otherwise; no outline, no
    // shadow; its name (13 pt semibold, the cream halo) under it from twice the country's framing zoom. The kind's icon
    // inside waits for the twelve kinds' icons (their review, Step 3b).
    private var marks: [String: (dot: UIView, name: UILabel)] = [:]
    /// returns the frames of the names it put up (the towns' names keep clear of them)
    private func ownMarks(_ m: MapController) -> [CGRect] {
        guard m.placesMode, let k0 = m.continentK ?? Optional(m.worldKMin) else { clearMarks(); return [] }
        // names stay in the map's room: under the head, above the 25% water, clear of the zoom column
        let room = m.layout.room(sheetTop: m.layout.top(.quarter))
        let box = CGRect(x: 6, y: room.lowerBound, width: bounds.width - 6 - 64, height: room.upperBound - room.lowerBound)
        var taken: [CGRect] = []
        let z = m.k / k0
        // 7 pt (a dot) until 4x the country's framing zoom, 20 pt from 20x, smoothly between (by the zoom)
        let t = min(1, max(0, (z - 4) / 16)), size = CGFloat(7 + 13 * t * t * (3 - 2 * t))
        let named = z >= 6
        var seen = Set<String>()
        for o in OwnPlaces.shared.all {
            let q = m.screenPoint(SIMD2(Double(o.point.x), Double(o.point.y)))
            guard bounds.insetBy(dx: -40, dy: -40).contains(q) else { continue }
            seen.insert(o.id)
            let mk = marks[o.id] ?? {
                let d = UIView(), l = UILabel()
                d.isUserInteractionEnabled = false; l.isUserInteractionEnabled = false
                l.textAlignment = .center
                addSubview(d); addSubview(l)
                marks[o.id] = (d, l)
                return (d, l)
            }()
            let st = MarkStore.shared.state(o.key)
            mk.dot.backgroundColor = st.stamped ? UIColor(Palette.lime) : st.wished ? UIColor(Palette.blue) : Self.cream
            mk.dot.frame = CGRect(x: q.x - size / 2, y: q.y - size / 2, width: size, height: size)
            mk.dot.layer.cornerRadius = size / 2
            if named {
                mk.name.attributedText = NSAttributedString(string: o.name, attributes: [
                    .font: Self.font, .foregroundColor: UIColor.black, .strokeColor: Self.cream, .strokeWidth: -3.0,
                ])
                let w = ceil((o.name as NSString).size(withAttributes: [.font: Self.font]).width) + 4
                let r = CGRect(x: q.x - w / 2, y: q.y + size / 2 + 2, width: w, height: 18)
                let fits = box.contains(r) && !taken.contains { $0.intersects(r.insetBy(dx: -4, dy: -4)) }
                mk.name.frame = r
                mk.name.isHidden = !fits
                if fits { taken.append(r) }
            } else { mk.name.isHidden = true }
            // the mark itself is kept clear of too (a town's name never sits on it)
            taken.append(mk.dot.frame)
        }
        for (id, mk) in marks where !seen.contains(id) { mk.dot.removeFromSuperview(); mk.name.removeFromSuperview(); marks[id] = nil }
        return taken
    }
    private func clearMarks() {
        for mk in marks.values { mk.dot.removeFromSuperview(); mk.name.removeFromSuperview() }
        marks = [:]
    }

    @discardableResult
    private func names(_ m: MapController, moving: Bool, taken own: [CGRect]) -> [CGRect] {
        guard m.placesMode || m.regionTowns, let cc = m.placeOpenID, let sc = m.townScenes[cc], let k0 = m.continentK else { clear(); return own }
        if key != cc { clear(); key = cc }
        let k = m.k
        // from 3x the country's framing zoom (each name rolling in across its own band from there)
        guard k >= 3 * k0 * 0.999 else { clear(); return own }
        let W = bounds.width
        let room = m.layout.room(sheetTop: m.layout.top(.quarter))
        let box = CGRect(x: 6, y: room.lowerBound, width: W - 6 - 64, height: room.upperBound - room.lowerBound)
        // the candidates, in order: capital, regional capitals, then by people (the scene is biggest first)
        // (worked out once per country, and only the towns that can ever be named: those with a shape, or every town with
        // Town dots on)
        let dotsOn = MapSettingsStore.shared.value.townDots
        if orderFor?.cc != cc || orderFor?.dots != dotsOn {
            var o: [Int] = []
            for kind in [2, 1, 0] {
                for i in sc.towns.indices where sc.towns[i].kind == kind && sc.towns[i].part.isEmpty
                    && (dotsOn || sc.runs[i] != nil || Self.bigShapeless(sc, i)) { o.append(i) }
            }
            // a town's sections ("Gallus" of Frankfurt) after every town, so a section never takes its city's name place
            for i in sc.towns.indices where !sc.towns[i].part.isEmpty && (dotsOn || sc.runs[i] != nil) { o.append(i) }
            orderFor = (cc, dotsOn, o)
        }
        var order = orderFor?.order ?? []
        // sections only from 10x the framing zoom (their city's name first)
        if k / k0 < 10 { order = order.filter { sc.towns[$0].part.isEmpty } }
        // (pure priority: a name up never holds its place against a bigger town's, so a city's name is never kept out
        // by smaller ones that came up first on the way in)
        var taken: [CGRect] = own
        var keep: [Int: CGFloat] = [:]
        for i in order {
            guard keep.count < 8 else { break }
            // a name only once its shape is 12 pt across (no shape, no name, unless Town dots are on)
            let b = sc.box(i)
            let across = CGFloat(max(b.z - b.x, b.w - b.y)) * CGFloat(k)
            let dots = MapSettingsStore.shared.value.townDots
            // a big city whose built-up land is all its sections' (Frankfurt's is Gallus' and the others') is named at its
            // point by the zoom alone
            let atPoint = sc.runs[i] == nil && (dots || Self.bigShapeless(sc, i))
            guard across >= 12 || atPoint else { continue }
            // its roll: from 12 pt across to 16 (and from 3x to 3.3x the framing zoom), by the zoom
            let a = min(1, max(0, (across - 12) / 4)), z = min(1, max(0, CGFloat((k / k0 - 3) / 0.3)))
            var p = atPoint ? z : min(a, z)
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
        return taken
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

    /// a town of 100,000 people or more with no shape of its own
    static func bigShapeless(_ sc: TownScene, _ i: Int) -> Bool { sc.runs[i] == nil && sc.towns[i].people >= 100_000 }

    private static func measure(_ name: String) -> CGSize {
        let z = (name as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(z.width) + 2, height: ceil(z.height))
    }

    private func clear() {
        for s in shown.values { s.holder.removeFromSuperview() }
        shown = [:]
    }
}

import UIKit
import SwiftUI

/// THE NAMES ON THE PLACES MAP (7.4: "the Apple Maps way"; the old app's TownNames rules, its labels over the map):
/// 13 pt semibold ink with a 2 pt cream halo; from 3x the country's framing zoom; the capital first, then regional
/// capitals, then by people; a name only once its town's shape is 12 pt across; at most 8 on screen, 4 pt clear of each
/// other, never under the head, the zoom column or the 25% water; a name keeps its place while you zoom (it is pinned to
/// its town), but a bigger town's name always wins the room (31 Oct: Frankfurt was kept out by eight smaller names
/// that came up first on the way in).
/// Each name rolls in (its letters rising into place) across its own band of zoom: the progress is the zoom's, so a
/// pinch scrubs it both ways and nothing arrives on a timer.
@MainActor
final class TownNamesView: UIView {
    private struct Shown { let id: String; let holder: UIView; let halo: UILabel; let ink: UILabel; let size: CGSize }
    private var shown: [String: Shown] = [:]
    private var key: String?
    /// THE PLAN (LabelPlan): the zoom from which each town's and thing's name shows, worked out once per set of
    /// countries (or collection), Town dots and framing zoom
    private var plan: LabelPlan?
    private var planKey = ""
    /// a planned town's scene and index, by its plan id
    private var townPick: [String: Pick] = [:]
    /// the town names up now, by plan id (a tap on one opens its page)
    private(set) var nameFrames: [String: CGRect] = [:]
    /// the things' names up now, by thing id (a tap on one opens its page)
    private(set) var thingNameFrames: [String: CGRect] = [:]
    /// (31 Oct: bold system type with a hard cream outline read badly. Now as Apple Maps
    /// sets its names: San Francisco, medium, black, with a soft cream glow round the letters; Tellus was tried and read
    /// as handwriting at this size)
    private static let font = UIFont.systemFont(ofSize: 13, weight: .medium)
    /// the soft glow behind a name (a shadow with no offset, cached as a picture: the name never changes)
    static func glow(_ l: UILabel) {
        l.layer.shadowColor = UIColor(red: 0xfb / 255, green: 0xf6 / 255, blue: 0xf2 / 255, alpha: 1).cgColor
        l.layer.shadowOpacity = 1
        l.layer.shadowRadius = 2.5
        l.layer.shadowOffset = .zero
        l.layer.shouldRasterize = true
        l.layer.rasterizationScale = UIScreen.main.scale
    }
    /// what a name is drawn in
    static func words(_ name: String, _ font: UIFont) -> NSAttributedString {
        NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: UIColor.black])
    }
    private static let cream = UIColor(red: 0xfb / 255, green: 0xf6 / 255, blue: 0xf2 / 255, alpha: 1)

    /// the one on screen (the test driver's `nametap`)
    nonisolated(unsafe) static weak var current: TownNamesView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        Self.current = self
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    /// TEST ONLY: `nametap <x> <y>` (a tap on a name there, as the map's confirmed tap hands it over), `names` (the names
    /// up now, logged)
    static func drive(_ p: [String], map: MapController?) {
        guard let v = current, let m = map else { return }
        if p.first == "names" {
            let towns = v.nameFrames.keys.compactMap { v.townOf($0) }.compactMap { m.townScenes[$0.cc]?.towns[$0.i].name }.sorted()
            NSLog("wya names %d towns: %@; %d things", towns.count, towns.joined(separator: ", "), v.thingNameFrames.count)
            return
        }
        guard p.count > 2 else { return }
        let pt = CGPoint(x: Double(p[1]) ?? 0, y: Double(p[2]) ?? 0)
        if let h = v.nameHit(pt) { NSLog("wya nametap %@ %@: %@", h.town ?? "-", h.thing ?? "-", v.openPage(h, m) ? "page" : "no page") }
        else { NSLog("wya nametap: nothing") }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// called every frame the map draws; `moving`: the camera or a finger is moving it (at rest no name is left half
    /// rolled: nothing cut off at rest, 30 Oct 16:04)
    func update(_ m: MapController, moving: Bool) {
        // (the list up at full: the map's names and marks step back under its rows and caption, gone by the time the
        // water passes half way to full, back as it comes down)
        let half = m.layout.top(.half)
        let a = m.sheetTop <= 0 ? 1 : min(1, max(0, (m.sheetTop - half * 0.4) / (half * 0.6)))
        if abs(alpha - a) > 0.001 { alpha = a }
        // (the journey's capsules are clear glass: names under them read through as a muddle, so they keep clear)
        let own = ownMarks(m) + (HistoryLineView.current?.capsuleFrames ?? [])
        ensurePlan(m)
        let named = names(m, moving: moving, taken: own)
        thingMarks(m, taken: named, moving: moving)
    }

    /// the plan for what is on the map now: the towns of the countries in play (the same candidates as before: a shape,
    /// a big town with none, or every town with Town dots on; sections from 10x), and their things (or a collection's
    /// places), all in one plan so a thing's name and a town's never overlap
    private func ensurePlan(_ m: MapController) {
        let ccs = (m.placesMode || m.regionTowns) ? m.townCountries.filter { m.townScenes[$0] != nil } : []
        let near = m.placesMode && m.placeOpen == nil
        let k0 = near ? m.townsK / 3 : m.continentK
        let collection = m.markCollection
        let kThing: Double? = collection != nil ? (m.continentK ?? m.worldKMin) : nil
        let dotsOn = MapSettingsStore.shared.value.townDots
        let thingsCount = ccs.reduce(0) { $0 + (ThingStore.shared.things($1)?.count ?? 0) }
        let pk = "\(ccs.joined(separator: ","))|\(dotsOn)|\(k0 ?? -1)|\(kThing ?? -1)|\(collection?.id ?? "")|\(collection?.items.count ?? 0)|\(thingsCount)|\(m.placeOpen ?? -1)|\(m.setScene == nil ? 0 : 1)"
        guard pk != planKey else { return }
        planKey = pk
        var items: [LabelPlan.Item] = []
        townPick = [:]
        if let k0 {
            for cc in ccs {
                guard let sc = m.townScenes[cc] else { continue }
                for i in sc.towns.indices {
                    let t = sc.towns[i]
                    let whole = t.part.isEmpty
                    guard dotsOn || sc.runs[i] != nil || (whole && Self.bigShapeless(sc, i)) else { continue }
                    let size = Self.measure(t.name)
                    // a name once its shape is 12 pt across (a big shapeless city at its point by the zoom alone), from 3x
                    // the framing zoom; a city's sections from 10x
                    let b = sc.box(i)
                    let across = Double(max(b.z - b.x, b.w - b.y))
                    let atPoint = sc.runs[i] == nil
                    // (a big city before the best-known things round it: 31 Oct 11:07, Frankfurt Airport was named
                    // before Frankfurt; 500,000 people from 2x, 100,000 from 2.5x, the rest from 3x)
                    var th = (t.people >= 500_000 ? 2 : t.people >= 100_000 ? 2.5 : 3) * k0
                    if !atPoint, across > 0 { th = max(th, 12 / across) }
                    if !whole { th = max(th, 10 * k0) }
                    let id = "t:\(cc)#\(i)"
                    townPick[id] = Pick(cc: cc, i: i)
                    items.append(LabelPlan.Item(id: id, at: SIMD2(Double(sc.at[i].x), Double(sc.at[i].y)),
                                                box: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                                                threshold: th, rank: Double(t.kind) * 1e9 + Double(t.people)))
                }
            }
        }
        // (a set's places are not planned: every one of them is on the map as its shape or its mark at every zoom,
        // and their names are all up or none, setNames; 11 Nov)
        _ = kThing
        thingStart = [:]
        plan = items.isEmpty ? nil : LabelPlan(items)
        thingKey = []
    }

    /// a name under a finger (a town's or a thing's, as it is on screen now), for its page
    func nameHit(_ p: CGPoint) -> (town: String?, thing: String?)? {
        for (id, f) in nameFrames where f.insetBy(dx: -4, dy: -6).contains(p) { return (id, nil) }
        for (id, f) in thingNameFrames where f.insetBy(dx: -4, dy: -6).contains(p) { return (nil, id) }
        return nil
    }
    /// a planned town's scene and index
    func townOf(_ id: String) -> (cc: String, i: Int)? { townPick[id].map { ($0.cc, $0.i) } }

    /// A NAME TAPPED (31 Oct): a name opens its page wherever there is one: the town's or thing's page, growing from its name; false when it has none (a collection's stop)
    @discardableResult
    func openPage(_ hit: (town: String?, thing: String?), _ m: MapController) -> Bool {
        let country = { (cc: String) -> String in m.world.flatMap { w in w.placeIndex[cc].map { w.places[$0].n } } ?? "" }
        if let id = hit.town, let (cc, i) = townOf(id), let sc = m.townScenes[cc], i < sc.towns.count {
            let t = sc.towns[i]
            let parents = t.region.isEmpty ? country(cc) : "\(t.region), \(country(cc))"
            Feel.tap()
            PlacePageState.shared.open(t.key, name: t.name, what: "Town in \(parents)", country: cc, from: nameFrames[id] ?? .zero)
            return true
        }
        if let id = hit.thing, let (cc, t) = ThingStore.shared.thing(id) {
            let line = t.line.isEmpty ? country(cc) : t.line.prefix(1).uppercased() + t.line.dropFirst()
            Feel.tap()
            PlacePageState.shared.open(t.key, name: t.name, what: line, country: cc, from: thingNameFrames[id] ?? .zero)
            return true
        }
        return false
    }

    // MARK: THINGS' MARKS (7.4, D5)
    // as Apple Maps shows its places: a thing comes with its name or not at all (a mark without words says nothing), by
    // the zoom across its fame's own band (World Heritage and the best known, in 40+ Wikipedias, from 2.5x the country's
    // framing zoom, 12+ from 5x, 4+ from 9x, the rest from 16x; the best known first within each);
    // its mark small and round, growing with the zoom from 6 pt to 10 pt over that band, never bigger; the map's darker
    // grey, lime when stamped, blue when wished; no outline, no shadow; its name (12 pt semibold, the cream halo) beside it on the right; a thing whose name has no room (a town's name, another thing) is not shown,
    // except one you stamped or wished, whose mark always shows; famous first, at most 40 on screen. The kind's icon
    // inside waits for the twelve kinds' icons (their review, Step 3b).
    /// A THING'S ZOOM BAND (times the framing zoom from which it may show): a collection's stop at once; a picked
    /// country's best known at once; otherwise by fame from 2.5x out to 16x
    static func start(fame: Int, picked: Bool) -> Double {
        if fame >= 9 { return 0 }
        return fame >= 3 ? (picked ? 1 : 2.5) : fame == 2 ? (picked ? 2.5 : 5) : fame == 1 ? 9 : 16
    }
    /// each planned thing's zoom from which it may show (its band), for its mark's growth
    private var thingStart: [String: Double] = [:]
    private var thingViews: [String: (dot: UIView, name: UILabel)] = [:]
    private static let thingFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    /// each thing's name's width (measured once)
    private var thingWidths: [String: CGFloat] = [:]
    /// what the marks were last laid out for (the camera, the room, the marks, the town names): unchanged, nothing is done
    private var thingKey: [Double] = []
    private func thingMarks(_ m: MapController, taken: [CGRect], moving: Bool) {
        // the things of the open country, or a collection's places (its map up: every one of them is its map's place, so
        // all are shown from the start, names where they have room)
        let collection = m.markCollection
        if let c = collection { setNames(m, c, taken: taken, moving: moving); return }
        clearSet()
        let all: [ThingStore.Thing]
        if let c = collection, c.shapes != nil, m.setScene == nil {
            all = []
        } else if let c = collection {
            all = c.items.map { ThingStore.Thing(id: $0.id, name: $0.short, kind: 11, at: $0.at, fame: $0.fame, line: "", photo: "") }
        } else if m.placesMode {
            // the towns' map: the things of the countries shown that are yours (stamped or wished), or found by search
            all = m.townCountries.compactMap { ThingStore.shared.things($0) }.flatMap { $0 }.filter {
                let st = MarkStore.shared.state($0.key)
                return st.stamped || st.wished || m.thingPressed == $0.id
            }
        } else { all = [] }
        // (close in with none open the things count from about 1,000 km across, the framing of a mid-size country, so they
        // come in no sooner than in an open Germany and never crowd the towns of the countries round)
        guard m.placesMode, !all.isEmpty,
              let k0 = collection != nil ? (m.continentK ?? m.worldKMin) : m.placeOpen == nil ? m.townsK : m.continentK else {
            clearThings(); m.thingFrames = [:]; thingNameFrames = [:]; thingKey = []; return
        }
        let marksNow = Double(MarkStore.shared.marks.count) + Double(MarkStore.shared.marks.values.filter { $0.stamped }.count) * 1e6
        let key: [Double] = [m.c.x, m.c.y, m.k, Double(bounds.width), Double(bounds.height), marksNow, Double(all.count),
                             Double(m.thingPressed?.hashValue ?? 0), Double(taken.count)]
        guard key != thingKey else { return }
        thingKey = key
        _ = k0
        let room = m.layout.room(sheetTop: m.layout.top(.quarter))
        let box = CGRect(x: 6, y: room.lowerBound, width: bounds.width - 6 - 64, height: room.upperBound - room.lowerBound)
        // FROM THE PLAN (31 Oct 11:10): a thing is up once the zoom is past its own (its fame's band, kept clear of every
        // name before it), its name always to its right; one you stamped or wished keeps its mark before that, without
        // its name
        var frames: [String: CGRect] = [:]
        var named = Set<String>()
        var nameRects: [String: CGRect] = [:]
        // ONE MARK, ONE SIZE (dots of several sizes read as a mess): 6 pt at every zoom, ink until it is yours
        let size: CGFloat = 6
        var centres: [CGPoint] = []
        let scene = m.setScene
        func put(_ t: ThingStore.Thing, _ st: MarkState, _ r: CGRect, _ nr: CGRect, name: Bool, dot: Bool = true) {
            let v = thingViews[t.id] ?? {
                let d = UIView(), l = UILabel()
                d.isUserInteractionEnabled = false; l.isUserInteractionEnabled = false
                l.attributedText = Self.words(t.name, Self.thingFont)
                Self.glow(l)
                l.lineBreakMode = .byTruncatingTail
                addSubview(d); addSubview(l)
                thingViews[t.id] = (d, l)
                return (d, l)
            }()
            v.dot.backgroundColor = m.thingPressed == t.id ? Self.pressed
                : st.stamped ? UIColor(Palette.lime) : st.wished ? UIColor(Palette.blue) : UIColor(Palette.ink)
            v.dot.frame = r
            v.dot.layer.cornerRadius = size / 2
            v.dot.isHidden = !dot
            frames[t.id] = dot ? r : nr
            if dot { centres.append(CGPoint(x: r.midX, y: r.midY)) }
            v.name.frame = nr
            v.name.textAlignment = dot ? .left : .center
            v.name.isHidden = !name
            if name { named.insert(t.id); nameRects[t.id] = nr }
        }
        // first the named ones and yours; then (a set's map) the marks still without a name, each only where it stands
        // clear of the names and of the marks already up (16 pt), the list's best known first: a set far out reads as
        // its places, never as a blot (450 marks over Europe, 9 Nov), and zooming in only ever adds marks
        var waiting: [(ThingStore.Thing, MarkState, CGRect, CGRect)] = []
        // AN AREA SET'S BIG PLACES FIRST: one whose shape is as long as its name has its name alone in the shape's
        // middle, no mark, as a sea's on any map (its shape is what is filled and pressed); the marks' names after them
        // keep clear of these (9 Nov: "Alboran Sea" ran into "Mediterranean Sea")
        var centred: [CGRect] = []
        var big = Set<String>()
        if let scene {
            for t in all {
                guard let across = scene.across(t.id) else { continue }
                let w = thingWidths[t.id] ?? ceil((t.name as NSString).size(withAttributes: [.font: Self.thingFont]).width) + 4
                guard CGFloat(across) * CGFloat(m.k) >= max(44, w) else { continue }
                big.insert(t.id)
                let q = m.screenPoint(SIMD2(Double(t.at.x), Double(t.at.y)))
                let nr = CGRect(x: q.x - w / 2, y: q.y - 9, width: w, height: 18)
                guard box.contains(nr), !taken.contains(where: { $0.intersects(nr.insetBy(dx: -1, dy: -1)) }),
                      !centred.contains(where: { $0.intersects(nr.insetBy(dx: -4, dy: -2)) }) else { continue }
                put(t, MarkStore.shared.state(t.key), CGRect(x: q.x, y: q.y, width: 0, height: 0), nr, name: true, dot: false)
                centred.append(nr)
            }
        }
        for t in all where !big.contains(t.id) {
            let st = MarkStore.shared.state(t.key)
            // (one found by search and shown is marked too while it is darkened)
            let marked = st.stamped || st.wished || m.thingPressed == t.id
            let up = (plan?.zoom["h:" + t.id] ?? .infinity) <= m.k * 1.0001
            // (a set's place: its mark from its own band on, whether or not its name has room yet)
            let inBand = collection != nil && (thingStart[t.id] ?? .infinity) <= m.k * 1.0001
            guard up || marked || inBand else { continue }
            let q = m.screenPoint(SIMD2(Double(t.at.x), Double(t.at.y)))
            guard box.contains(q) else { continue }
            let r = CGRect(x: q.x - size / 2, y: q.y - size / 2, width: size, height: size)
            let w = thingWidths[t.id] ?? ceil((t.name as NSString).size(withAttributes: [.font: Self.thingFont]).width) + 4
            let nr = CGRect(x: q.x + 7, y: q.y - 9, width: w, height: 18)
            // (only what is not planned can still be in the way: your own places' marks, the journey's capsules)
            let nameFree = up && box.contains(nr) && !taken.contains { $0.intersects(nr.insetBy(dx: -1, dy: -1)) }
                && !centred.contains { $0.intersects(nr.insetBy(dx: -3, dy: -1)) }
            // (a mark never stands on a big place's name)
            if centred.contains(where: { $0.insetBy(dx: -3, dy: -1).intersects(r) }), !marked { continue }
            if nameFree || marked { put(t, st, r, nr, name: nameFree) }
            else if inBand { waiting.append((t, st, r, nr)) }
        }
        let rects = Array(nameRects.values)
        for (t, st, r, nr) in waiting {
            let c = CGPoint(x: r.midX, y: r.midY)
            guard !rects.contains(where: { $0.insetBy(dx: -3, dy: -1).intersects(r) }),
                  !centres.contains(where: { abs($0.x - c.x) < 16 && abs($0.y - c.y) < 16 }) else { continue }
            put(t, st, r, nr, name: false)
        }
        thingNameFrames = nameRects
        for (id, v) in thingViews where frames[id] == nil { v.dot.removeFromSuperview(); v.name.removeFromSuperview(); thingViews[id] = nil }
        // (a named thing answers a finger on its name too)
        var hits = frames
        for id in named { if let f = frames[id], let v = thingViews[id] { hits[id] = f.union(v.name.frame) } }
        m.thingFrames = hits
    }
    private static let pressed = UIColor(red: 0xa1 / 255, green: 0x9e / 255, blue: 0x95 / 255, alpha: 1)

    // MARK: A SET'S NAMES (11 Nov). The places themselves are the map's (their shapes and marks, MapRenderer: all of them
    // at every zoom). Here only their names, every one of them planned once per list (LabelPlan), so a name is up
    // exactly when the zoom is past its own and panning never changes which are up (names must not come and go
    // as the map is zoomed):
    // - a sea or a range has its name in its middle once it is big enough on screen to hold it, a bigger one first, as on
    //   any map;
    // - a mark's name stands to its right (a park's on its shape), the list's best known first. These names are all
    //   up or all away (some marks named and some not reads as broken: either all are
    //   named or none are): up when at most 30 of the list's marks are in sight and at least half of
    //   them have room for their names (the few left out stand closer together than a name is wide, and get theirs a
    //   little further in), away otherwise. Decided when the map comes to rest, never while it moves.
    // Names just appear.
    private var setLabels: [String: UILabel] = [:]
    private var setKey: [Double] = []
    private func clearSet() {
        guard !setLabels.isEmpty || !setKey.isEmpty else { return }
        for l in setLabels.values { l.removeFromSuperview() }
        setLabels = [:]; setKey = []; setPlan = nil; setPlanKey = ""; setOn = false
    }
    private var setPlan: LabelPlan?
    private var setPlanKey = ""
    /// the list's places by id, and those whose names are a mark's (up together or not at all)
    private var setItems: [String: CollectionStore.Item] = [:]
    private var setGated = Set<String>()
    /// each name's box about its place's point
    private var setBoxes: [String: CGRect] = [:]
    /// the marks' names are up
    private var setOn = false
    private func setNames(_ m: MapController, _ c: CollectionStore.Collection, taken: [CGRect], moving: Bool) {
        clearThings()
        let scene = m.setScene
        guard m.placesMode, !(c.shapes != nil && scene == nil) else { clearSet(); m.thingFrames = [:]; thingNameFrames = [:]; return }
        var fresh = false
        if setPlanKey != c.tag + (scene == nil ? "" : "+") {
            setPlanKey = c.tag + (scene == nil ? "" : "+")
            fresh = true
            setItems = Dictionary(c.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            setGated = []; setBoxes = [:]
            var items: [LabelPlan.Item] = []
            var markNames: [String: [CGRect]] = [:]
            for (n, it) in c.items.enumerated() where setBoxes[it.id] == nil {
                let w = thingWidths[it.id] ?? {
                    let w = ceil((it.short as NSString).size(withAttributes: [.font: Self.thingFont]).width) + 4
                    thingWidths[it.id] = w
                    return w
                }()
                let at = SIMD2(Double(it.at.x), Double(it.at.y))
                if let scene, let across = scene.across(it.id), across > 0, !scene.outlined {
                    let box = CGRect(x: -w / 2, y: -9, width: w, height: 18)
                    setBoxes[it.id] = box
                    items.append(LabelPlan.Item(id: it.id, at: at, box: box, threshold: Double(w + 8) / Double(across), rank: Double(across)))
                } else if scene?.across(it.id) != nil {
                    // a park: its name on its shape
                    let box = CGRect(x: -w / 2, y: -9, width: w, height: 18)
                    setBoxes[it.id] = box; setGated.insert(it.id)
                    items.append(LabelPlan.Item(id: it.id, at: at, box: box, threshold: 0, rank: Double(c.items.count - n)))
                } else {
                    // a mark and its name beside it, kept clear together: to its right, or its left, under it, over it,
                    // whichever lets the name show soonest (the name's own box is set once the plan has chosen)
                    setBoxes[it.id] = CGRect(x: 8, y: -9, width: w, height: 18); setGated.insert(it.id)
                    markNames[it.id] = [CGRect(x: 8, y: -9, width: w, height: 18), CGRect(x: -8 - w, y: -9, width: w, height: 18),
                                        CGRect(x: -w / 2, y: 6, width: w, height: 18), CGRect(x: -w / 2, y: -24, width: w, height: 18),
                                        CGRect(x: 6, y: 3, width: w, height: 18), CGRect(x: 6, y: -21, width: w, height: 18),
                                        CGRect(x: -6 - w, y: 3, width: w, height: 18), CGRect(x: -6 - w, y: -21, width: w, height: 18)]
                    items.append(LabelPlan.Item(id: it.id, at: at, box: CGRect(x: -5, y: -9, width: 13 + w, height: 18),
                                                threshold: 0, rank: Double(c.items.count - n),
                                                alts: [CGRect(x: -8 - w, y: -9, width: 13 + w, height: 18), CGRect(x: -w / 2, y: -5, width: w, height: 29),
                                                       CGRect(x: -w / 2, y: -24, width: w, height: 29),
                                                       CGRect(x: -5, y: -5, width: 11 + w, height: 26), CGRect(x: -5, y: -21, width: 11 + w, height: 26),
                                                       CGRect(x: -6 - w, y: -5, width: 11 + w, height: 26), CGRect(x: -6 - w, y: -21, width: 11 + w, height: 26)]))
                }
            }
            setPlan = items.isEmpty ? nil : LabelPlan(items, gap: 5)
            for (id, n) in setPlan?.choice ?? [:] { if let r = markNames[id], n < r.count { setBoxes[id] = r[n] } }
        }
        // (the map's room: under the head, above the water where it rests, clear of the zoom column)
        let top = m.sheetTop > 0 ? min(max(m.sheetTop, m.layout.top(.half)), m.layout.top(.quarter)) : m.layout.top(.quarter)
        let room = m.layout.room(sheetTop: top)
        let box = CGRect(x: 6, y: room.lowerBound, width: bounds.width - 6 - 64, height: room.upperBound - room.lowerBound)
        let card = RegionCardState.shared.isOpen
        let key: [Double] = [m.c.x, m.c.y, m.k, Double(bounds.width), Double(box.minY), Double(box.maxY), Double(c.tag.hashValue),
                             Double(c.items.count), scene == nil ? 0 : 1, card ? 1 : 0, moving ? 1 : 0]
        guard key != setKey else { return }
        setKey = key
        guard let plan = setPlan else { clearSet(); m.thingFrames = [:]; thingNameFrames = [:]; return }
        // ALL OF THE MARKS' NAMES OR NONE, decided at rest (and at once for a list just picked)
        if !moving || fresh {
            var seen = 0, named = 0
            for it in c.items where setGated.contains(it.id) {
                let q = m.screenPoint(SIMD2(Double(it.at.x), Double(it.at.y)))
                guard box.contains(q) else { continue }
                seen += 1
                if (plan.zoom[it.id] ?? .infinity) <= m.k * 1.0001 { named += 1 }
                if seen > 30 { break }
            }
            setOn = seen > 0 && seen <= 30 && named * 2 >= seen
        }
        // (a card up: it stands on the 25% water, its name about 220 pt above it; no name of the map's under it)
        let cardTop: CGFloat = card ? m.layout.top(.quarter) - 240 : .greatestFiniteMagnitude
        let live = bounds.insetBy(dx: -80, dy: -20)
        var rects: [String: CGRect] = [:]
        for (id, z) in plan.ordered {
            if z > m.k * 1.0001 { break }
            guard let it = setItems[id], let b = setBoxes[id] else { continue }
            if setGated.contains(id), !setOn { continue }
            let q = m.screenPoint(SIMD2(Double(it.at.x), Double(it.at.y)))
            guard live.contains(q) else { continue }
            let r = b.offsetBy(dx: q.x, dy: q.y)
            guard r.maxY < cardTop else { continue }
            rects[id] = r
        }
        for (id, r) in rects {
            guard let it = setItems[id] else { continue }
            let l = setLabels[id] ?? {
                let l = UILabel()
                l.isUserInteractionEnabled = false
                l.attributedText = Self.words(it.short, Self.thingFont)
                l.textAlignment = .center
                Self.glow(l)
                addSubview(l)
                setLabels[id] = l
                return l
            }()
            l.frame = r
        }
        for (id, l) in setLabels where rects[id] == nil { l.removeFromSuperview(); setLabels[id] = nil }
        thingNameFrames = rects
        m.thingFrames = rects
    }
    private func clearThings() {
        for v in thingViews.values { v.dot.removeFromSuperview(); v.name.removeFromSuperview() }
        thingViews = [:]
    }

    // MARK: YOUR OWN PLACES' MARKS (7.8; 31 Oct 01:17: a lime circle is right for these): a small dot when the map
    // is far out, growing with the zoom (by the zoom,
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
                if mk.name.attributedText?.string != o.name { mk.name.attributedText = Self.words(o.name, Self.font); Self.glow(mk.name) }
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
        // the open country's towns, or (Places close in with none open) the towns of the countries in view
        let ccs = (m.placesMode || m.regionTowns) ? m.townCountries.filter { m.townScenes[$0] != nil } : []
        // (close in with none open, the same zoom whatever framed the camera last: a country flown to, a continent or the world)
        let near = m.placesMode && m.placeOpen == nil
        guard !ccs.isEmpty, let k0 = near ? m.townsK / 3 : m.continentK else { clear(); return own }
        let setKey = ccs.joined(separator: ",")
        if key != setKey { clear(); key = setKey }
        let k = m.k
        // from 3x the country's framing zoom (each name rolling in across its own band from there)
        guard k >= 2 * k0 * 0.999 else { clear(); return own }
        let W = bounds.width
        let room = m.layout.room(sheetTop: m.layout.top(.quarter))
        let box = CGRect(x: 6, y: room.lowerBound, width: W - 6 - 64, height: room.upperBound - room.lowerBound)
        // FROM THE PLAN (31 Oct 11:10): a name is up once the zoom is past its own (LabelPlan), so names never swap while
        // you zoom or pan; it rolls in over the first 8% of zoom past it (by the zoom), whole at rest
        var taken: [CGRect] = own
        var keep: [String: CGFloat] = [:]
        if let plan {
            for e in plan.ordered {
                guard e.zoom <= k * 1.0001 else { break }
                guard e.id.hasPrefix("t:"), let pick = townPick[e.id], let sc = m.townScenes[pick.cc], pick.i < sc.towns.count else { continue }
                var p = CGFloat(min(1, max(0, (k / e.zoom - 1) / 0.08)))
                if !moving { p = 1 }
                let size = shown[e.id]?.size ?? Self.measure(sc.towns[pick.i].name)
                let pt = m.screenPoint(SIMD2(Double(sc.at[pick.i].x), Double(sc.at[pick.i].y)))
                let r = CGRect(x: pt.x - size.width / 2, y: pt.y - size.height / 2, width: size.width, height: size.height)
                guard box.contains(r) else { continue }
                // (only your own places' marks and the journey's capsules can still be in the way: they are not planned)
                guard !own.contains(where: { $0.intersects(r.insetBy(dx: -4, dy: -4)) }) else { continue }
                taken.append(r)
                keep[e.id] = p
                place(e.id, name: sc.towns[pick.i].name, at: r, progress: p, size: size)
            }
        }
        for (id, s) in shown where keep[id] == nil { s.holder.removeFromSuperview(); shown[id] = nil }
        nameFrames = keep.keys.reduce(into: [:]) { d, id in if let s = shown[id] { d[id] = s.holder.frame } }
        return taken
    }
    private struct Pick { let cc: String; let i: Int; var id: String { "\(cc)#\(i)" } }

    private func place(_ i: String, name: String, at r: CGRect, progress p: CGFloat, size: CGSize) {
        let s: Shown
        if let have = shown[i] { s = have } else {
            let holder = UIView()
            holder.clipsToBounds = true
            holder.isUserInteractionEnabled = false
            let halo = UILabel(), ink = UILabel()
            halo.isHidden = true
            ink.attributedText = Self.words(name, Self.font)
            Self.glow(ink)
            halo.textAlignment = .center; ink.textAlignment = .center
            holder.addSubview(halo); holder.addSubview(ink)
            addSubview(holder)
            s = Shown(id: i, holder: holder, halo: halo, ink: ink, size: size)
            shown[i] = s
        }
        // the holder is the name's box with room for its halo; the letters rise into it by the zoom's progress
        let pad: CGFloat = 4
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
        nameFrames = [:]
    }
}

import SwiftUI

/// TEST ONLY, simulator builds only: reads snaps/cmd.txt in the night folder four times a second and runs it when it
/// changes, so every state of the screen can be reached and checked from outside (with Snap's frames). The first
/// line is an id; each next line one command. Never in a phone build.
@MainActor
final class TestDriver {
    static let shared = TestDriver()
    weak var map: MapController?
    weak var water: Water?
    weak var head: HeadState?
    private var lastID = ""
    private var lostOwner = false
    /// where the whole content is on screen (to see whether the keyboard moves it)
    var contentFrame: CGRect = .zero

    func start(map: MapController, water: Water, head: HeadState) {
        #if targetEnvironment(simulator) && DEBUG
        self.map = map; self.water = water; self.head = head
        NSLog("wya test driver started")
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in NSLog("wya t keyboard will show") }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in NSLog("wya t keyboard did show") }
        // a launch to record: snaps/launch-burst.txt holds the burst's length in ms (read once, then emptied)
        let lb = Snap.dir + "/launch-burst.txt"
        if let ms = (try? String(contentsOfFile: lb, encoding: .utf8)).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }), ms > 0 {
            try? "".write(toFile: lb, atomically: true, encoding: .utf8)
            Snap.burst(ms: ms)
        }
        let path = Snap.dir + "/cmd.txt"
        // a command left over from the last run is not run again
        lastID = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n").first.map(String.init) ?? ""
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                if !Snap.isOwner {
                    // another copy of the app (another simulator) took the test files over: say so once
                    if !self.lostOwner {
                        self.lostOwner = true
                        let o = (try? String(contentsOfFile: Snap.dir + "/owner.txt", encoding: .utf8)) ?? "unreadable"
                        NSLog("wya test driver: owner is now %@, I am %@", o, Snap.me)
                    }
                    return
                }
                guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                var lines = s.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                guard let id = lines.first, id != self.lastID else { return }
                self.lastID = id
                lines.removeFirst()
                NSLog("wya test driver runs %@", lines.joined(separator: " | "))
                // "quiet" anywhere in the commands: no screen grabs (measuring lag, the grabs would be the lag)
                Snap.activeUntil = lines.contains("quiet") ? 0 : CACurrentMediaTime() + 20
                self.run(lines)
            }
        }
        #endif
    }

    private func run(_ lines: [String]) {
        Task { @MainActor in
            for l in lines {
                let p = l.split(separator: " ").map(String.init)
                guard let c = p.first else { continue }
                let a = p.count > 1 ? p[1] : ""
                switch c {
                case "wait": try? await Task.sleep(for: .milliseconds(Int(a) ?? 300))
                case "water":
                    let s: Water.Stop = ["closed": .closed, "quarter": .quarter, "half": .half, "full": .full][a] ?? .quarter
                    water?.go(s)
                case "dragwater":
                    // dragwater y0 y1 ms [hold]
                    let y0 = CGFloat(Double(a) ?? 700), y1 = CGFloat(Double(p.count > 2 ? p[2] : "400") ?? 400)
                    let ms = Int(p.count > 3 ? p[3] : "400") ?? 400
                    water?.begin(at: CGPoint(x: 201, y: y0))
                    let steps = max(1, ms / 16)
                    for i in 1 ... steps {
                        water?.move(to: CGPoint(x: 201, y: y0 + (y1 - y0) * CGFloat(i) / CGFloat(steps)))
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    if p.count > 4 && p[4] == "hold" { continue }
                    water?.end(velocity: (y1 - y0) / CGFloat(ms) * 1000 * 0.3)
                case "release": water?.end(velocity: 0)
                case "pull":
                    guard let h = head else { break }
                    // pull ai | <points> (held there, as a finger would) | off
                    // through the same code as a finger (from settings too), so a test sees what a person would
                    let v: CGFloat = a == "ai" ? HeadState.aiStop : a == "off" ? 0 : CGFloat(Double(a) ?? 0)
                    h.pullBegan()
                    h.pullMoved(v - h.pull)
                    if a == "ai" || a == "off" { h.settlePull(to: v >= HeadState.aiStop ? 1 : 0) }
                case "tools": head?.toolsOpen = a == "on"
                case "quick": head?.quickStamp = a == "on"
                case "dial": head?.testDial = a == "off" ? nil : CGFloat(Double(a) ?? 0)
                case "mode": head?.mode = HeadState.Mode(rawValue: Int(a) ?? 0) ?? .countries
                case "search":
                    if a == "off" { head?.searching = false }
                    else { NSLog("wya t search open"); head?.searching = true; head?.query = p.dropFirst().joined(separator: " ") }
                case "zoom":
                    if a == "in" { map?.zoomIn() } else if a == "out" { map?.zoomOut() } else { map?.goHome() }
                case "show":
                    if let m = map, let i = m.world?.placeIndex[a] { m.show(place: i) }
                case "continent": map?.show(continent: p.dropFirst().joined(separator: " "))
                case "look":
                    // look lon lat zoom
                    if p.count > 3, let lo = Double(p[1]), let la = Double(p[2]), let z = Double(p[3]) {
                        map?.look(lon: lo, lat: la, zoom: z)
                    }
                case "press":
                    if let m = map { m.pressed = a == "off" ? nil : m.world?.placeIndex[a] }
                case "hold": head?.dotHeld = a == "on"
                // gear <0..1>: holds the dot part way to the gear, to look at one frame of it
                case "gear": head?.gear = CGFloat(Double(a) ?? 0)
                case "drag":
                    // drag <dy> <ms>: the top pull as a finger would do it, through the same code as the gesture
                    guard let h = head else { break }
                    let dy = CGFloat(Double(a) ?? 0), ms = Int(p.count > 2 ? p[2] : "400") ?? 400
                    h.pullBegan()
                    let steps = max(1, ms / 16)
                    for i in 1 ... steps {
                        h.pullMoved(dy * CGFloat(i) / CGFloat(steps))
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    if !(p.count > 3 && p[3] == "hold") { h.pullEnded(velocity: 0) }
                // a finger on the map: the same hook the map's touch calls (ContentView: map.onTouch)
                case "maptap": map?.onTouch?()
                // wheel <dx> <ms>: a finger turning the dot sideways, through the same path as the capsule's drag
                case "wheel":
                    guard let h = head else { break }
                    let dx = CGFloat(Double(a) ?? 0), ms = Int(p.count > 2 ? p[2] : "600") ?? 600
                    let steps = max(1, ms / 16)
                    for k in 1 ... steps {
                        h.capsuleDrag = dx * CGFloat(k) / CGFloat(steps)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    h.capsuleDragFling = 0
                    h.capsuleDrag = nil
                // sheet flags: a review sheet (1p) into snaps/review-<name>.png
                case "sheet":
                    if a == "flags" { ReviewSheet.flags(world: map?.world) }
                    if a == "tabicons" { ReviewSheet.tabIcons() }
                    if a == "launch" { ReviewSheet.launchPicture() }
                    if a == "logoturn" { ReviewSheet.logoTurnMovie() }
                    if a == "icons" { ReviewSheet.icons() }
                case "maptab": if let w = water, let m = map { WaterView.mapAgain(water: w, map: m) }
                case "streak": map?.streakHeld = true; map?.streakWeeks = Int(a) ?? 0
                case "sunpick": map?.sunPicked = a == "on"
                case "settings": if a == "on" { head?.openSettings() } else { head?.closeSettings() }
                case "frames":
                    NSLog("wya frames content %@", NSCoder.string(for: contentFrame))
                    // the windows and their root views, to see whether anything has been moved (the keyboard)
                    for w in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
                        let v = w.rootViewController?.view
                        NSLog("wya frames %@ level %.0f frame %@ root %@ bounds %@ safe %@", String(describing: type(of: w)), w.windowLevel.rawValue,
                              NSCoder.string(for: w.frame), NSCoder.string(for: v?.frame ?? .zero), NSCoder.string(for: v?.bounds ?? .zero),
                              NSCoder.string(for: CGRect(x: 0, y: v?.safeAreaInsets.top ?? 0, width: 0, height: v?.safeAreaInsets.bottom ?? 0)))
                    }
                case "burst": Snap.burst(ms: Int(a) ?? 1000)
                case "quiet": break
                case "tap":
                    // tap x y (screen points): what a finger there would press, logged and pressed
                    if p.count > 2, let x = Double(p[1]), let y = Double(p[2]), let m = map {
                        let h = m.hit(at: CGPoint(x: x, y: y))
                        NSLog("wya tap %.0f %.0f -> %@", x, y, h.flatMap { m.world?.places[$0].id } ?? "nothing")
                        m.pressed = h
                    }
                case "mark":
                    // mark <place id> stamp|wish|none: the place's marks change (a fill front from its middle)
                    // through the store, as every marking surface does (MarkStore)
                    if p.count > 2, map?.world?.placeIndex[p[1]] != nil {
                        let k = PlaceKey.country(p[1]), st = MarkStore.shared
                        if p[2] == "stamp" { await st.stamp(k, source: .hand) }
                        else if p[2] == "wish" { await st.wish(k, source: .hand) }
                        else if st.state(k).stamped { await st.unstamp(k) } else { await st.unwish(k) }
                    }
                case "undo": await MarkStore.shared.undo()
                // nationality <id> | none: Profile's first nationality, for the home's centre (1.4)
                case "nationality":
                    if a == "none" { UserDefaults.standard.removeObject(forKey: MapController.nationalitiesKey) }
                    else { UserDefaults.standard.set([a], forKey: MapController.nationalitiesKey) }
                    map?.refreshHome(); map?.goHome()
                case "hittest": if let m = map { HitTest.run(map: m) }
                case "action":
                    // action <id> [arg] [source]: one registered action, logged with the screen state after it
                    let ok = await Actions.shared.perform(a, p.count > 2 ? p[2] : nil,
                                                          source: ActionSource(rawValue: p.count > 3 ? p[3] : "you") ?? .you)
                    try? await Task.sleep(for: .milliseconds(100))
                    var line = "action \(a) \(p.count > 2 ? p[2] : "") -> \(ok)"
                    if let m = map, let w = water, let h = head {
                        line += "\n\(ScreenStateSource(map: m, water: w, head: h, tab: { 0 }).now())"
                    }
                    line += "\nregistered: \(Actions.shared.all.keys.sorted().joined(separator: ", "))"
                    line += "\nfeatures: " + Feature.allCases.map { "\($0.rawValue) \($0.isOn)" }.joined(separator: ", ")
                    try? line.write(toFile: Snap.dir + "/action.log", atomically: true, encoding: .utf8)
                case "borders":
                    // borders defacto|un|<KEY> [piece=owner,...] [fallback un]: the map in another borders view; the time
                    // it took and the caption after, into snaps/borders.log
                    let v: Borders.View = a == "defacto" ? .deFacto : a == "un" ? .unitedNations : .country(a)
                    var picks: [String: String] = [:]
                    if p.count > 2, p[2] != "-" {
                        for kv in p[2].split(separator: ",") { let x = kv.split(separator: "="); if x.count == 2 { picks[String(x[0])] = String(x[1]) } }
                    }
                    let fb: Borders.View = p.count > 3 && p[3] == "un" ? .unitedNations : .deFacto
                    let t0 = CACurrentMediaTime()
                    let ok = await map?.setBorders(v, picks: picks, fallback: fb) ?? false
                    let ms = Int((CACurrentMediaTime() - t0) * 1000)
                    let line = "borders \(a) picks \(picks) -> \(ok) in \(ms) ms; caption \(map?.count.n ?? -1) of \(map?.count.of ?? -1); dotted \(Borders.dottedPlaces.count)"
                    try? line.write(toFile: Snap.dir + "/borders.log", atomically: true, encoding: .utf8)
                case "shake": NotificationCenter.default.post(name: .wyaShake, object: nil)
                case "redo": NotificationCenter.default.post(name: .wyaRedo, object: nil)
                // card <id>: its stamping card, as a tap on the place opens it; details: that card's Details;
                // close: Details first, then the card (as taps off do)
                case "card":
                    if let m = map, let w = m.world, let i = w.places.firstIndex(where: { $0.id == a }) {
                        let p = w.places[i]
                        CardState.shared.open(i, at: m.screenPoint(SIMD2(p.c[0], p.c[1])), map: m, water: water)
                    }
                // list on|off: the Stamped list, as the caption's number opens and closes it
                case "list": if a == "off" { water?.closeList() } else { water?.openList() }
                case "details":
                    if let m = map, let w = m.world, let i = CardState.shared.place, let water {
                        CardState.shared.heldTop = water.form().top
                        DetailsState.shared.open(.country(w.places[i].id), name: w.places[i].n, water: water)
                    }
                case "verify":
                    if let m = map, let w = m.world, let i = CardState.shared.place, let water {
                        CardState.shared.heldTop = water.form().top
                        VerifyState.shared.open(.country(w.places[i].id), name: w.places[i].n, place: i, water: water)
                    }
                case "close":
                    if VerifyState.shared.isOpen, let water { VerifyState.shared.close(water: water) }
                    else if DetailsState.shared.isOpen, let water { DetailsState.shared.close(water: water) }
                    else if let m = map { CardState.shared.close(map: m) }
                // stamp <id>: a country stamped as a test would (undoable)
                case "stamp": await MarkStore.shared.stamp(.country(a))
                // slowmo N: the stamp's flight N times slower, for frame checks (slowmo 1 = real speed)
                case "slowmo": CardState.slow = Double(a) ?? 1
                // unstamp <id>: a test's stamp taken off again (test residue)
                case "unstamp": await MarkStore.shared.unstamp(.country(a))
                case "marks":
                    // every mark in the store (stamped, then wished), and the places not in the debug demo set
                    let ms = MarkStore.shared.marks
                    let st = ms.filter { $0.value.stamped }.keys.map(\.description).sorted()
                    let wi = ms.filter { $0.value.wished }.keys.map(\.description).sorted()
                    let demo = Set(MarkStore.demoStamped.map { "c:" + $0 })
                    let line = "stamped \(st.count): \(st.joined(separator: " "))\nwished \(wi.count): \(wi.joined(separator: " "))\nnot demo: \(st.filter { !demo.contains($0) }.joined(separator: " "))"
                    try? line.write(toFile: Snap.dir + "/marks.log", atomically: true, encoding: .utf8)
                case "storecheck":
                    let lines = await StoreCheck.run()
                    try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/storecheck.log", atomically: true, encoding: .utf8)
                case "importold":
                    // importold <file in snaps>: the old app's stamps.json read into the store; what came in, into
                    // snaps/import.log (each row's key, state, name, level, and whether details/proof were kept)
                    if let d = try? Data(contentsOf: URL(fileURLWithPath: Snap.dir + "/" + a)) {
                        let n = await MarkStore.shared.importOld(d)
                        var lines = ["imported \(n)"]
                        if let book = try? OldBook(json: d) {
                            lines.append("waiting: \(book.waiting)")
                            for r in book.rows {
                                lines.append("\(r.key) stamped \(r.stamped) wished \(r.wished) want \(r.want) times \(r.times) "
                                    + "name \(r.name) cc \(r.cc) lvl \(r.level) at \(r.at) came \(r.came.map { "\($0)" } ?? "-") "
                                    + "details \(r.details != nil) proof \(r.verification != nil) how \(r.how ?? "-")")
                            }
                        }
                        lines.append("store now: \(MarkStore.shared.marks.count) marks; caption \(map?.count.n ?? -1) of \(map?.count.of ?? -1)")
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/import.log", atomically: true, encoding: .utf8)
                    }
                case "counts":
                    // the Count service's totals per borders view and Count setting (Part 17 D18's check: the world's
                    // total equals what the caption shows; each view as the old app counted it), into snaps/counts.log
                    if let m = map, let w = m.world,
                       let u = Bundle.main.url(forResource: "disputes", withExtension: "json"), let d = try? Data(contentsOf: u),
                       let f = try? JSONDecoder().decode(DisputeFile.self, from: d) {
                        let places = w.places.map { ($0.id, $0.s ?? $0.n, $0.k) }
                        let views: [(String, Borders.View)] = [("de facto", .deFacto), ("UN", .unitedNations)]
                            + ["US", "RU", "CN", "MA", "RS", "KO", "IN", "PK"].map { ($0, Borders.View.country($0)) }
                        let mine = Set(m.stamped.map { w.places[$0].id })
                        var lines = ["counts \(Date())", "caption now: \(m.count.n) of \(m.count.of)"]
                        for (name, v) in views {
                            let pos = Positions(file: f, places: places, view: v)
                            for kind in [CountKind.stamps, .countries] {
                                let sh = MapCounts.shares(stamped: mine, world: w, count: kind, positions: pos)
                                let conts = sh.filter { $0.key != "World" }
                                let sum = conts.filter { $0.key != "Antarctica" }.values.reduce(0) { $0 + $1.total }
                                lines.append("\(name) \(kind.rawValue): world \(sh["World"]?.have ?? 0)/\(sh["World"]?.total ?? 0); "
                                    + conts.keys.sorted().map { "\($0) \(conts[$0]!.have)/\(conts[$0]!.total)" }.joined(separator: ", ")
                                    + "; continents (no Antarctica) sum \(sum)")
                            }
                        }
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/counts.log", atomically: true, encoding: .utf8)
                    }
                case "probe":
                    // probe x y (screen points): the rings there log how the morph laid them (snaps/probe.log)
                    if p.count > 2, let x = Double(p[1]), let y = Double(p[2]), let m = map {
                        let q = m.mapPoint(CGPoint(x: x, y: y))
                        MorphIndex.probeFile = Snap.dir + "/probe.log"
                        MorphIndex.probe = SIMD2(Float(q.x), Float(q.y))
                        MorphIndex.note(String(format: "probe at %.3f %.3f", q.x, q.y))
                        m.details?.dropTiles()
                    }
                case "detail": FrameStats.log("wya detail \(a): " + (map?.details?.debugState ?? "none"))
                case "morph": map?.details?.testMorph = a == "auto" ? nil : Float(a)
                case "coarse": map?.details?.testCoarse = a == "on"
                case "off": Perf.shared.off.insert(a)
                case "on": Perf.shared.off.remove(a)
                case "sun": map?.sunPicked = a == "on"
                case "tabicons": TabIconsTest.on = a == "on"
                // FINGERS ON THE MAP (Step 1b-ii): the same MapController calls the Metal view's touches make, frame by
                // frame, so a scripted gesture is the gesture. pinch <factor> <x> <y> <ms>; pan <dx> <dy> <ms>;
                // flick <dx> <dy> <ms> (a pan let go at its speed); longpress <x> <y> <ms>; twofinger <x> <y>
                case "pinch", "pan", "flick":
                    guard let m = map, p.count > 3 else { break }
                    let n1 = Double(p[1]) ?? 1, n2 = Double(p[2]) ?? 0, n3 = Double(p[3]) ?? 0
                    let ms = Int(p.count > 4 ? p[4] : (c == "pinch" ? "800" : "400")) ?? 400
                    let steps = max(1, ms / 8)
                    m.grab()
                    for _ in 0 ..< steps {
                        if c == "pinch" { m.zoom(by: pow(n1, 1 / Double(steps)), about: CGPoint(x: n2, y: n3)) }
                        else { m.pan(by: SIMD2(n1 / Double(steps), n2 / Double(steps))) }
                        try? await Task.sleep(for: .milliseconds(8))
                    }
                    m.release(velocity: c == "flick" ? SIMD2(n1, n2) / (Double(ms) / 1000) : nil)
                case "longpress":
                    guard let m = map, p.count > 2, let x = Double(p[1]), let y = Double(p[2]) else { break }
                    m.grab(); m.pressed = m.hit(at: CGPoint(x: x, y: y))
                    try? await Task.sleep(for: .milliseconds(Int(p.count > 3 ? p[3] : "700") ?? 700))
                    m.pressed = nil; m.release(velocity: nil)
                case "twofinger":
                    guard let m = map, p.count > 2, let x = Double(p[1]), let y = Double(p[2]) else { break }
                    m.twoFingerTap(at: CGPoint(x: x, y: y))
                case "measure": if a == "on" { FrameStats.start() } else { FrameStats.stop(p.count > 2 ? p[2] : "scene") }
                case "layout":
                    if let L = water?.layout {
                        NSLog("wya layout model %@ W %.1f H %.1f safeTop %.1f safeBottom %.1f island %@ corner %.0f", L.model, L.W, L.H, L.safeTop, L.safeBottom, NSCoder.string(for: L.island), L.screenCorner)
                    }
                case "planet": map?.testPlanet = Int(a)
                case "moon": map?.testMoon = a == "off" ? nil : Double(a)
                default: NSLog("wya test driver: unknown %@", l)
                }
            }
        }
    }
}

/// TEST ONLY: parts switched off to find what costs frames ("off <part>", "on <part>"; observed, so a switch takes
/// effect on the next frame): map, cosmos, planets, sun, stars, caption, sheetglass, sheet, tabs, head, zoom, pull
@MainActor @Observable
final class Perf {
    static let shared = Perf()
    var off: Set<String> = []
}

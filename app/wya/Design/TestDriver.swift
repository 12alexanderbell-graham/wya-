import SwiftUI
import MapKit

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
    /// the session put back as after the system ended the app (19.2): `session restore`
    var restoreSession: (() -> Void)?

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
                // history on|off; history tap <x> <y> (a tap on the journey at that point, as the map's confirmed tap
                // would hand it over); history pull <dy> (the water grabbed at its top, moved dy pt, let go still)
                case "history": await HistoryLineView.drive(p, map: map, water: water, head: head)
                case "nametap", "names": TownNamesView.drive(p, map: map)
                // visit <id> <yyyy-mm-dd>: the country stamped with that day as a visit (test data for history lines)
                case "visit": if p.count > 2 { await MarkStore.shared.stamp(.country(a), day: p[2]) }
                case "quick": head?.quickStamp = a == "on"
                case "dial": head?.testDial = a == "off" ? nil : CGFloat(Double(a) ?? 0)
                case "mode": head?.mode = HeadState.Mode(rawValue: Int(a) ?? 0) ?? .countries
                // neighbours <id>: who borders it in this borders view (D19)
                case "neighbours":
                    if let w = map?.world, let i = w.placeIndex[a] {
                        NSLog("wya neighbours %@: %@", a, w.neighbours[i].map { w.places[$0].id }.sorted().joined(separator: " "))
                    }
                case "search":
                    if a == "off" { head?.searching = false }
                    // search suggest [new]: the empty field's suggestions, logged by id (new: as with no searches yet)
                    else if a == "suggest", let m = map, let w = m.world {
                        let s = SearchResults.suggestions(map: m, recentToo: p.count < 3)
                        NSLog("wya suggestions %@", s.map { w.places[$0].id }.joined(separator: " "))
                    }
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
                    if a == "emblems" { ReviewSheet.emblems() }
                    if a == "flagshapes" { ReviewSheet.flagShapes(world: map?.world) }
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
                // listdetails <id>: a row of the Stamped list swiped right (Details from the list, A4.21)
                case "listdetails": StampedList.testDetails?(a)
                // upload open | close | choose 0|1 | back: the upload sheet (9.3) as the Upload tool, a tap off, a tap on a
                // choice and the swipe right would
                case "upload":
                    switch a {
                    case "open": if let water, let map { UploadState.shared.open(water: water, map: map) }
                    case "close": UploadState.shared.close()
                    case "back": UploadState.shared.back()
                    case "choose": UploadState.shared.choose(Int(p.count > 2 ? p[2] : "0") ?? 0)
                    case "read": UploadState.shared.testRead(empty: p.count > 2 && p[2] == "none", more: p.count > 2 && p[2] == "more")
                    case "more": UploadState.shared.addMore()
                    // upload file <name in snaps>: as Files would hand it over
                    case "file": if p.count > 2 { UploadState.shared.imported([URL(fileURLWithPath: Snap.dir + "/" + p[2])]) }
                    case "cancel": UploadState.shared.cancel()
                    case "go": UploadState.shared.go()
                    case "drop": if let m = map, let w = m.world, let i = w.places.firstIndex(where: { $0.id == (p.count > 2 ? p[2] : "") }) { _ = UploadState.shared.tap(i) }
                    // upload dates <id> | trip <id> <k> | show <id>: the review row's hold menu and a trip's ×
                    case "dates": if p.count > 2 { UploadState.shared.toggleDates(p[2]) }
                    case "trip": if p.count > 3, let k = Int(p[3]) { UploadState.shared.tapTrip(p[2], k) }
                    case "show": if let m = map, let i = m.world?.placeIndex[p.count > 2 ? p[2] : ""] { UploadState.shared.show(i) }
                    default: break
                    }
                // drows <addtime | removelived N | addplace <kind> <name> | removeplace N>: Details' rows (A4.14 / A4.15)
                case "drows": DetailsSheet.test?(Array(p.dropFirst()))
                case "session": restoreSession?()
                case "waterhint": water?.hint()
                // lock on | off | press: the zoom column's lock, and a press on the locked map (A1.9)
                case "lock": if a == "press" { Feel.refuse(); map?.lockedPress() } else { map?.locked = a == "on" }
                // hints: forget that the gestures were used and play the first-time hints (A3.15)
                case "hints":
                    for k in ["hint.water", "hint.pull", "hint.hold"] { UserDefaults.standard.removeObject(forKey: k) }
                    if let water, let head { Hints.shared.start(water: water, head: head) }
                // sideways on | off: the sideways mark, and out of full screen (1.11)
                case "sideways":
                    if a == "off" { Sideways.shared.leave() }
                    // sideways frame 0.5: the turn held at that point (sideways frame none: let go)
                    else if a == "frame" { Sideways.shared.testTurn = p.count > 2 ? Double(p[2]) : nil }
                    else if let water, let head, let map { Sideways.shared.enter(water: water, head: head, map: map) { CardState.shared.close(map: map) } }
                case "details":
                    if let m = map, let w = m.world, let i = CardState.shared.place, let water {
                        CardState.shared.heldTop = water.form().top
                        DetailsState.shared.open(.country(w.places[i].id), name: w.places[i].n, water: water)
                    }
                // book [n]: the passport tool pressed (the book out or back); with n, open on page n (1-based)
                // regionpick fr: the Regions list's row for that place tapped (A6.7)
                // regiontap x y: a tap at that screen point on the region map, as a confirmed map tap
                case "regionpick":
                    if let m = map { RegionsMenuModel.shared.build(map: m) }
                    if let r = RegionsMenuModel.shared.rows.first(where: { $0.flag == a.lowercased() }) {
                        RegionsMenuModel.shared.load(r.flag)
                        RegionsMenuModel.shared.onPick?(r)
                    } else { NSLog("wya regionpick %@: not in the list", a) }
                // regiondirect fr: a country's "Open its region map" (A6.14), from whatever mode
                // thingfind jfk: search's first thing found, shown (as its row's tap)
                case "thingfind":
                    ThingIndex.shared.load()
                    for _ in 0 ..< 150 where !ThingIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let t = ThingIndex.shared.hits(p.dropFirst().joined(separator: " "), open: nil).first { map?.showThing(file: t.file, id: t.id) }
                // thingpage louvre museum: the first thing found, its country's things read, its page opened (Part 16)
                case "thingpage":
                    ThingIndex.shared.load()
                    for _ in 0 ..< 150 where !ThingIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let h = ThingIndex.shared.hits(p.dropFirst().joined(separator: " "), open: nil).first {
                        ThingStore.shared.load(h.file)
                        for _ in 0 ..< 100 where ThingStore.shared.things(h.file) == nil { try? await Task.sleep(for: .milliseconds(100)) }
                        if let t = ThingStore.shared.things(h.file)?.first(where: { $0.id == h.id }) {
                            PlacePageState.shared.open(t.key, name: t.name, what: t.line, country: h.file,
                                                       from: CGRect(x: 200, y: 400, width: 44, height: 44))
                        }
                    }
                // pick everywhere | pick it | pick cont Europe | pick reg Southern Europe: a shelf card's tap (7.5)
                case "pick":
                    let rest = p.dropFirst(2).joined(separator: " ")
                    if a == "everywhere" { map?.showPlacesMap(.everywhere) }
                    else if a == "cont" { map?.showPlacesMap(.continent(rest)) }
                    else if a == "reg" { map?.showPlacesMap(.region(rest)) }
                    else if a == "col" {
                        CollectionStore.shared.load()
                        for _ in 0 ..< 50 where !CollectionStore.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                        map?.showPlacesMap(.collection(rest))
                    }
                    else if let i = map?.world?.placeIndex[a] { map?.showPlacesMap(.country(i)) }
                // placeopen de: Places' country opened with its towns (7.4); placeopen off: back to the world
                case "placeopen":
                    if a == "off" { map?.closePlace(); map?.goHome() }
                    else if let m = map, let i = m.world?.placeIndex[a] { m.openPlace(i) }
                // page ru: a country's page opened from its box (Part 16); page off: closed
                case "page":
                    if a == "off" { PlacePageState.shared.close() }
                    else if a == "end" { PlacePageState.shared.toEnd += 1 }
                    // page city: the open page's first city pushed on top (16.7); page back: the top page closed
                    else if a == "city", let c = PlacePageState.shared.facts?.cities.first {
                        PlacePageState.shared.push(c.key, name: c.name, what: "Town in \(c.line)", country: PlacePageState.shared.country,
                                                   from: CGRect(x: 16, y: 520, width: 398, height: 52))
                    }
                    else if a == "back" { PlacePageState.shared.close() }
                    // page at <0..1>: the top page held part way open, to look at one frame of its growing
                    // page report <reason words>: Report a mistake open with that reason; page send: Send
                    else if a == "report" { PlacePageState.shared.reportTest = p.dropFirst(2).joined(separator: " ") }
                    else if a == "send" { PlacePageState.shared.sendTest += 1 }
                    else if a == "at", p.count > 2, let v = Double(p[2]) { PlacePageState.shared.top?.p = CGFloat(v) }
                    // page highlight: the open page's first highlight's page pushed (16.7)
                    else if a == "highlight", let h = PlacePageState.shared.facts?.highlights.first {
                        let cc = PlacePageState.shared.country
                        ThingStore.shared.load(cc)
                        PlacePageState.shared.push(PlaceKey(.thing, "wd:" + h.id), name: h.name, what: h.line, country: cc,
                                                   from: CGRect(x: 16, y: 500, width: 380, height: 300), photo: h.photo)
                    }
                    else if a == "sources" { PlacePageState.shared.sourcesTest += 1; PlacePageState.shared.toEnd = 5 }
                    else if let m = map, let i = m.world?.placeIndex[a], let pl = m.world?.places[i] {
                        PlacePageState.shared.open(.country(pl.id), name: pl.n, country: pl.id, from: m.screenRect(of: i))
                    }
                // ownclear: every own place removed with its stamp (test data)
                case "ownclear":
                    for o in OwnPlaces.shared.all {
                        await MarkStore.shared.unstamp(o.key, name: o.name)
                        OwnPlaces.shared.remove(o.id)
                    }
                // townpage frankf: the first town found's page (Part 16)
                case "townpage":
                    TownIndex.shared.load()
                    for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let m = map, let t = TownIndex.shared.hits(p.dropFirst().joined(separator: " "), open: nil).first {
                        let country = m.world?.placeIndex[t.file].map { m.world!.places[$0].n } ?? ""
                        PlacePageState.shared.open(PlaceKey(.town, t.id), name: t.name, what: "Town in \(t.region), \(country)",
                                                   country: t.file, from: CGRect(x: 200, y: 400, width: 44, height: 44))
                    }
                // regionfind bavar: search's first region found from Countries, opened (as its row's tap)
                case "regionfind":
                    RegionIndex.shared.load()
                    for _ in 0 ..< 100 where !RegionIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let m = map, let h = head, let r = RegionIndex.shared.hits(p.dropFirst().joined(separator: " ")).first,
                       let i = m.world?.placeIndex[r.place] {
                        h.searching = false
                        ContentView.openRegionMap(i, head: h, row: r.row, focus: r.id, map: m)
                    }
                // townfind frankf: Places' search's first town shown (as the search key would)
                case "townfind":
                    TownIndex.shared.load()
                    for _ in 0 ..< 150 where !TownIndex.shared.ready { try? await Task.sleep(for: .milliseconds(100)) }
                    if let m = map, let t = TownIndex.shared.hits(p.dropFirst().joined(separator: " "), open: m.placeOpenID).first {
                        head?.searching = false
                        m.showTown(file: t.file, id: t.id)
                    }
                case "regiondirect":
                    if let h = head, let i = map?.world?.placeIndex[a] { ContentView.openRegionMap(i, head: h) }
                // regionslow 8: the region borders' change at 1/8 speed (frame checks)
                case "regionslow": RegionLines.slow = Double(a) ?? 1
                // regionlevel 2: the open country's level from that row of its table (the level line's pick)
                case "regionlevel":
                    if let m = map, let sc = m.regionScene, let r = Int(a) {
                        if r == 99 { m.showRegionTowns() } else { m.leaveRegionTowns(); m.openRegions(sc.place, row: r) }
                    }
                // thingtap <words>: a tap on the open collection's stop whose name holds the words, at its mark; its mark
                // state logged a second later (D7: a stop's day as a visit)
                case "thingtap":
                    if let m = map, let cid = m.placesCollection, let c = CollectionStore.shared.collection(cid) {
                        let q = p.dropFirst().joined(separator: " ").lowercased()
                        if let it = c.items.first(where: { $0.name.lowercased().contains(q) || $0.label.lowercased().contains(q) }),
                           let f = m.thingFrames[it.id] {
                            let pt = CGPoint(x: f.midX, y: f.midY)
                            if let i = m.hit(at: pt) { m.onPlaceTap?(i, pt) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                let st = MarkStore.shared.state(it.key)
                                NSLog("wya thingtap %@ (%@): stamped %d wished %d visits %d", it.name, it.date, st.stamped ? 1 : 0, st.wished ? 1 : 0, st.visits)
                            }
                        } else { NSLog("wya thingtap %@: no mark", q) }
                    }
                // picker on|off | picker at <x 0-1> <y 0-1> | picker strength <0-1>: the colour picker's test host (Part 15)
                case "picker":
                    let t = PickerTest.shared
                    if a == "on" { t.on = true } else if a == "off" { t.on = false }
                    else if a == "at", p.count > 3, let x = Double(p[2]), let y = Double(p[3]) {
                        t.colour = ColourPick.at(CGPoint(x: x, y: y), strength: t.colour.strength); ColourStore.shared.add(t.colour)
                    } else if a == "strength", p.count > 2, let v = Double(p[2]) {
                        t.colour.strength = v; ColourStore.shared.add(t.colour)
                    }
                    NSLog("wya picker %@: P3 %.3f %.3f %.3f, %d kept", ColourNames.name(t.colour), t.colour.p3.x, t.colour.p3.y, t.colour.p3.z, ColourStore.shared.recent.count)
                // pinreview <map|apple|satellite|off> [spread|stacked|lines] | pinreview at <lat> <lon> <span>: the pins review (8.3)
                case "pinreview":
                    let r = PinReview.shared
                    if a == "off" { r.on = false }
                    else if a == "at", p.count > 4, let la = Double(p[2]), let lo = Double(p[3]), let sp = Double(p[4]) {
                        r.centre = CLLocationCoordinate2D(latitude: la, longitude: lo); r.span = sp
                    } else {
                        r.ground = a; if p.count > 2 { r.scene = p[2] }
                        r.on = true
                        if a != "map", let L = water?.layout { r.snapshot(size: CGSize(width: L.W, height: L.H)) }
                    }
                case "regiontap":
                    if let m = map, p.count > 2, let x = Double(p[1]), let y = Double(p[2]) {
                        let pt = CGPoint(x: x, y: y)
                        let mp = m.mapPoint(pt)
                        if let w = m.world, let wi = m.details?.place(at: SIMD2(Float(mp.x), Float(mp.y)), reach: 0, tiny: 0) ?? w.place(at: SIMD2(Float(mp.x), Float(mp.y))) {
                            NSLog("wya regiontap world place there: %@", w.places[wi].id)
                        }
                        if let i = m.hit(at: pt) {
                            NSLog("wya regiontap %.0f %.0f: region %d", x, y, m.regionPressed ?? -1)
                            m.onPlaceTap?(i, pt)
                        } else { NSLog("wya regiontap %.0f %.0f: nothing", x, y) }
                    }
                // regionfile fr: the place's bundled region level read back (D10), logged
                case "regionfile":
                    let cat = RegionCatalog.shared
                    for cc in p.dropFirst() {
                        guard let (row, lv) = cat.first(String(cc)), let f = cat.file(String(cc), row: row) else {
                            NSLog("wya regionfile %@: none", String(cc)); continue
                        }
                        let pts = f.units.flatMap { $0.rings.flatMap { $0 } }
                        let lo = pts.reduce(SIMD2(Double.infinity, .infinity)) { pointwiseMin($0, $1) }
                        let hi = pts.reduce(SIMD2(-Double.infinity, -.infinity)) { pointwiseMax($0, $1) }
                        NSLog("wya regionfile %@-%d %@: %d units, %d regions (table %d), %d points, box %.2f %.2f %.2f %.2f, pieces %@",
                              String(cc), row, lv.many, f.units.count, f.ids.count, lv.n, pts.count, lo.x, lo.y, hi.x, hi.y,
                              Set(f.units.compactMap(\.piece)).sorted().joined(separator: " "))
                    }
                // row labels on: a Map settings row set as a tap on it would (id, value id)
                case "row": if let m = map, p.count > 2 { _ = await MapSettingsRows.set(p[1], p[2], map: m) }
                // pageturn 45: the passport's leaf held at that angle (> 0 forward, < 0 the previous page coming back)
                case "pageturn": BookState.shared.turn = Double(a) ?? 0
                case "book":
                    if let n = Int(a) { BookState.shared.page = max(0, n - 1) }
                    BookState.shared.toggle()
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
                // historycheck: the history reader's fixtures (shapes A to D, the offsets) against the map's shapes
                case "historycheck":
                    if let m = map {
                        let lines = HistoryCheck.run(map: m)
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/historycheck.log", atomically: true, encoding: .utf8)
                    }
                // photocheck: the photo library read (asks for access the first time)
                case "photocheck":
                    if let m = map {
                        let lines = await HistoryCheck.photos(map: m)
                        try? lines.joined(separator: "\n").write(toFile: Snap.dir + "/photocheck.log", atomically: true, encoding: .utf8)
                    }
                // link <url>: a link into the Map opened as the system would hand it over (19.6)
                case "link": if let m = map, let u = URL(string: a) { await DeepLink.open(u, map: m) {} }
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
                // filter 0..4: the moon's five looks (1.14)
                case "filter": map?.filter = Int(a) ?? 0
                // nocolour on | off | system: Differentiate Without Colour's patterns (1.14)
                case "nocolour": map?.testWithoutColour = a == "system" ? nil : a == "on"
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

import SwiftUI
import PhotosUI
import CoreLocation
import UniformTypeIdentifiers

/// THE UPLOAD SHEET (Part 9.2 and 9.3): the plus's Upload tool opens it in the water at 25%; two choices side by side,
/// two taps to what is read: Photos (Pick | All) or Location (File | Here). No explanations.
///
/// Motion, one thing at a time and nothing fading: the caption's words roll out, then the pair's icons grow from their
/// own centres (the right one 0.03 s behind) and their words roll in (A9.2); a step changes by the pair going the same
/// way out and the next coming in (A9.3); closing is the exact reverse, then the water goes back to the stop it came
/// from and the caption's words roll back in.
///
/// The icons are bare rings until their glyphs are picked (as the plus's tools); the words are the book's.
/// FINDING (9.4) follows in the same water: the pair goes, the caption comes back reading World / 0 / found with the
/// working mark at its left and a × at its right, and each found country darkens (in one frame) as the number rolls
/// up, at most 10 times a second; × cancels (the finds clear in one frame, the caption back to your count). With
/// nothing found the words say so in the number's place, then the pair comes back.
/// THE REVIEW (9.5) is the go circle: a tap on a found country drops it (its darkening goes, the number rolls down)
/// or keeps it again; the go circle stamps every kept find with its found trips as dated visits, in one write and one
/// undo step (the colours change in one frame; the undo drop says what came in).
/// Pulled to 50% (or full) the review shows its finds as rows under the caption (flag, name, found dates), newest trip
/// first, dropped ones at the end in black 50%; a tap on a row drops or keeps it as a tap on its country does.
/// WAITING FINDS (9.6): a pull down leaves the review and the finds wait, darkened on the map, kept in a small file
/// beside the store (`waiting-finds.json`; the book's Proposal records wait for a store version); a tap on one, or
/// the Upload tool, opens the review again (the caption rolls to "found", the go circle grows at its place).
/// Not here yet (logged): a row's swipe and hold, the mode
/// wheel turning to Countries, the file's progress line, Add more, the second round.
@MainActor
@Observable
final class UploadState {
    static let shared = UploadState()
    /// 0: Photos | Location; 1: Pick | All; 2: File | Here
    private(set) var step = 0
    /// the pair's icons (left, right) grown, and its words in
    private(set) var shapes = [false, false]
    private(set) var words = false
    /// a choice's word rolled to what it has to say ("Allow Photos in Settings", "Can't find you"); key step * 2 + side
    private(set) var note: [Int: String] = [:]
    /// Here waiting for its fix: the icon gives way to the working mark
    private(set) var locating = false
    var picking = false
    var importing = false
    var picked: [PhotosPickerItem] = []
    /// the last read's samples and where they came from (finding, 9.4, starts from these)
    private(set) var samples: [HistoryReader.Sample] = []
    private(set) var source: MarkSource = .photos
    /// choosing (the pair), finding (the number rolling up), review (the go circle), words (A9.8)
    enum Phase { case choosing, finding, review, words }
    private(set) var phase: Phase = .choosing
    /// finding's row: the caption's words, the working mark, the × (or the go circle at the review)
    private(set) var captionIn = false
    private(set) var markIn = false
    private(set) var xIn = false
    private(set) var goIn = false
    /// places found so far (the number), and A9.8's words in its place
    private(set) var count = 0
    private(set) var message: String?
    private(set) var finds: [Finds.Find] = []
    /// the found places (map indices) in the order found, and the ones dropped at the review
    @ObservationIgnored private var order: [Int] = []
    private(set) var dropped: Set<Int> = []
    @ObservationIgnored weak var map: MapController?
    /// what A9.8 says when a file gave nothing (not a history, unreadable); nil: "No places found"
    @ObservationIgnored private var failed: String?
    @ObservationIgnored private var job = 0
    /// which read a result belongs to: a read started on one sheet, step or session that has since gone (back, closed,
    /// reopened) is dropped when it lands
    @ObservationIgnored private var readToken = 0
    /// the go's write or the leaving is under way: taps, pulls and a second go wait for it
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var moving = false

    var isOpen: Bool { water?.upload ?? false }
    @ObservationIgnored private weak var water: Water?

    static let names = [["Photos", "Location"], ["Pick", "All"], ["File", "Here"]]
    static let spoken = [["Photos", "Location"], ["Pick photos", "All photos"], ["Location history file", "Where I am now"]]

    /// A9.1 and A9.2: the water to 25% (it stays if it is there), the caption's words out, then the pair in
    func open(water w: Water, map m: MapController) {
        guard !w.upload else { return }
        readToken += 1
        // finds waiting: the Upload tool opens straight on their review (9.2)
        if !order.isEmpty { openReview(water: w, map: m); return }
        water = w; map = m
        phase = .choosing; captionIn = false; markIn = false; xIn = false; goIn = false; count = 0; message = nil
        step = 0; note = [:]; locating = false
        shapes = [false, false]; words = false
        let at25 = w.stop == .quarter
        w.openUpload()
        job += 1
        let me = job
        // at 25% only the caption has to go (its roll out clears in about 0.35 s); from elsewhere the water arrives first
        grow(after: at25 ? 0.36 : 0.45, job: me)
    }

    /// the pair in: icons from their own centres (right 0.03 s behind), then the words once the shapes are past 60%
    private func grow(after d: Double, job me: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { [self] in
            guard me == job else { return }
            withAnimation(Motion.quick) { shapes[0] = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
                guard me == job else { return }
                withAnimation(Motion.quick) { shapes[1] = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
                guard me == job else { return }
                withAnimation(Motion.quick) { words = true }
                moving = false
            }
        }
    }
    /// the pair out: the words roll out as the icons shrink into their centres (the tapped one 0.03 s behind)
    private func shrink(lead: Int? = nil) {
        withAnimation(.smooth(duration: 0.15)) { words = false }
        let first = lead.map { 1 - $0 } ?? 0
        withAnimation(Motion.quick) { shapes[first] = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
            withAnimation(Motion.quick) { shapes[1 - first] = false }
        }
    }

    /// A9.3: a tap on step 1's choices goes to its step 2
    func choose(_ side: Int) {
        guard phase == .choosing, !moving, words else { return }
        Feel.tap()
        switch step {
        case 0: go(to: side == 0 ? 1 : 2, lead: side)
        case 1: side == 0 ? pick() : all()
        default: side == 0 ? file() : here()
        }
    }
    /// A9.3 back: step 2 to step 1 (a swipe right on the water)
    func back() {
        guard phase == .choosing, step != 0, !moving else { return }
        Feel.tick()
        readToken += 1
        go(to: 0, lead: nil)
    }
    private func go(to s: Int, lead: Int?) {
        moving = true
        job += 1
        let me = job
        shrink(lead: lead)
        // the next pair only once the old words have rolled out and its icons are in their centres
        // (a word's roll out takes about 0.35 s to clear, whatever its curve)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [self] in
            guard me == job else { return }
            step = s
            locating = false
            grow(after: 0, job: me)
        }
    }

    /// pulled down or a tap on the map: the pair out, then the water back to where it was and the caption in (while
    /// finding, neither closes: finding holds the 25% and owns the map's presses; × cancels)
    func close() {
        guard !busy else { return }
        // leaving the review (a pull down): the finds wait (9.6)
        if phase == .review { leave(); return }
        guard let w = water, w.upload, phase == .choosing || phase == .words else { return }
        readToken += 1
        if phase == .words { endWords(close: true); return }
        job += 1
        let me = job
        shrink()
        picking = false; importing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [self] in
            guard me == job else { return }
            w.closeUpload()
            step = 0; note = [:]; locating = false
        }
    }

    // MARK: the four sources

    /// Pick: Apple's picker, no permission; when it closes with photos or videos, their own place and time are read
    private func pick() { picking = true }
    func picked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let t = readToken
        Task {
            var out: [HistoryReader.Sample] = []
            for it in items {
                // a video: a copy of its file read for its place and time, then the copy goes
                if it.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    guard let m = try? await it.loadTransferable(type: PickedMovie.self) else { continue }
                    let s = await PhotosReader.sample(movie: m.url)
                    try? FileManager.default.removeItem(at: m.url)
                    if let s { out.append(HistoryReader.Sample(lat: s.lat, lon: s.lon, at: s.at, offset: s.offset, end: nil, asset: it.itemIdentifier)) }
                    continue
                }
                guard let d = try? await it.loadTransferable(type: Data.self), let s = PhotosReader.sample(imageData: d) else { continue }
                out.append(HistoryReader.Sample(lat: s.lat, lon: s.lon, at: s.at, offset: s.offset, end: nil, asset: it.itemIdentifier))
            }
            found(out, from: .photos, read: items.count, token: t)
        }
    }
    /// All: Photos access asked at this press only; refused, the word says so and leads to Settings
    private func all() {
        if note[2] != nil { openSettings(); return }
        let t = readToken
        Task {
            guard await PhotosReader.ask() else { if t == readToken { refuse(2, "Allow Photos in Settings") }; return }
            let (s, skipped) = await PhotosReader.samples()
            found(s, from: .photos, read: s.count + skipped, token: t)
        }
    }
    /// File: the Files picker, JSON, several at once (Takeout's monthly files go in together)
    private func file() { importing = true }
    func imported(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let t = readToken
        Task.detached(priority: .userInitiated) {
            var out: [HistoryReader.Sample] = []
            var unreadable = 0, notHistory = 0
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                guard let d = try? Data(contentsOf: u, options: .alwaysMapped) else { unreadable += 1; continue }
                if let r = HistoryReader.read(d) { out += r.samples } else { notHistory += 1 }
            }
            let got = out
            // nothing read from any file: A9.8 says why in the number's place
            let why: String? = !got.isEmpty || urls.isEmpty ? nil
                : unreadable == urls.count ? "Couldn't read this file"
                : notHistory > 0 && unreadable == 0 ? "That file is not a location history" : nil
            await MainActor.run { UploadState.shared.found(got, from: .history, read: urls.count, why: why, token: t) }
        }
    }
    /// Here: one fix, When In Use asked at this press only; the icon gives way to the working mark while it waits
    private func here() {
        if note[5] == "Allow Location in Settings" { openSettings(); return }
        guard !locating else { return }
        withAnimation(Motion.quick) { note[5] = nil; locating = true }
        let t = readToken
        Task {
            let r = await OneFix.shared.get()
            guard t == readToken else { return }
            withAnimation(Motion.quick) { locating = false }
            switch r {
            case .fix(let l):
                Feel.land(speed: 0)
                found([HistoryReader.Sample(lat: l.coordinate.latitude, lon: l.coordinate.longitude, at: l.timestamp,
                                            offset: nil, end: nil, asset: nil)], from: .history, read: 1, token: t)
            case .refused: refuse(5, "Allow Location in Settings")
            case .none: refuse(5, "Can't find you")
            }
        }
    }
    private func refuse(_ k: Int, _ say: String) {
        Feel.refuse()
        withAnimation(Motion.quick) { note[k] = say }
    }
    private func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    /// what was read: finding starts (A9.4): the pair out, then the caption (World / 0 / found), the mark and the ×
    private func found(_ s: [HistoryReader.Sample], from src: MarkSource, read n: Int, why: String? = nil, token: Int? = nil) {
        NSLog("wya upload read %d items: %d samples with a place (%@)", n, s.count, src == .photos ? "photos" : "history")
        // a read from a sheet or step that has gone since is dropped
        guard token == nil || token == readToken, let w = water, w.upload, phase == .choosing, !moving else { return }
        samples = s; source = src
        failed = why
        job += 1
        let me = job
        moving = true
        shrink()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [self] in
            guard me == job else { return }
            phase = .finding
            count = 0
            withAnimation(Motion.quick) { captionIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
                guard me == job else { return }
                withAnimation(Motion.quick) { markIn = true; xIn = true }
                moving = false
                find(me)
            }
        }
    }

    #if DEBUG
    /// the test driver's read: a few dated points in eight countries, as if a history file had given them (none in
    /// a place you have stamped twice, one at sea), or none at all
    func testRead(empty: Bool = false) {
        let pts: [(Double, Double, String)] = [(38.72, -9.14, "2024-08-03T10:00:00Z"), (38.72, -9.14, "2024-08-05T10:00:00Z"),
            (35.68, 139.69, "2024-04-01T03:00:00Z"), (48.86, 2.35, "2023-06-10T12:00:00Z"), (-33.87, 151.21, "2022-12-24T01:00:00Z"),
            (64.14, -21.94, "2021-07-01T12:00:00Z"), (-1.29, 36.82, "2020-02-02T09:00:00Z"), (19.43, -99.13, "2019-11-01T18:00:00Z"),
            (-13.16, -72.54, "2018-05-05T15:00:00Z"), (30.0, -40.0, "2018-05-06T15:00:00Z")]
        let s = empty ? [] : pts.compactMap { p in HistoryReader.date(p.2).map { HistoryReader.Sample(lat: p.0, lon: p.1, at: $0, offset: 0, end: nil, asset: nil) } }
        found(s, from: .history, read: s.count)
    }
    #endif

    /// the places, from the samples (in the borders view you chose: the map's own shapes), then each darkens as the
    /// number rolls up: at most 10 steps a second, all within about 2 s
    private func find(_ me: Int) {
        guard let m = map, let world = m.world else { return }
        let placeAt: (Double, Double) -> String? = { lat, lon in
            world.place(at: EqualEarth.project(lon: lon, lat: lat)).map { world.places[$0].id }
        }
        let rows = HistoryReader.presence(samples, placeAt: placeAt)
        let all = Finds.finds(rows, source: source)
        finds = all
        let index = Dictionary(world.places.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        order = all.compactMap { index[$0.place] }
        dropped = []
        let order = self.order
        NSLog("wya upload found %d places from %d rows", order.count, rows.count)
        if order.isEmpty { say(failed ?? "No places found"); return }
        let per = max(1, Int((Double(order.count) / 20).rounded(.up)))
        func step(_ k: Int) {
            guard me == job, phase == .finding else { return }
            let upto = min(order.count, k + per)
            m.found.formUnion(order[k ..< upto])
            withAnimation(Motion.quick) { count = upto }
            if upto < order.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { step(upto) }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in ready(me) }
            }
        }
        step(0)
    }

    /// A9.7: the mark goes first; then the go circle grows from the ×'s centre behind it, the × giving way to the
    /// stamp's place (the review, 9.5, starts here)
    private func ready(_ me: Int) {
        guard me == job, phase == .finding else { return }
        UIAccessibility.post(notification: .announcement, argument: "Done, \(count) \(count == 1 ? "place" : "places") found")
        withAnimation(Motion.quick) { markIn = false; if stampAtOnce { xIn = false } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [self] in
            guard me == job else { return }
            phase = .review
            // Map settings' Found places = Stamp them: no review, the finds land as stamps at once (9.4)
            if stampAtOnce { go(); return }
            withAnimation(Motion.quick) { goIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { Feel.land(speed: 0) }
        }
    }

    private var stampAtOnce: Bool { MapSettingsStore.shared.value.foundPlaces == "stamp" }

    /// THE REVIEW'S ROWS (9.5 at 50%): newest trip first, the dropped ones at the end
    struct Row: Identifiable, Equatable {
        var id: String
        var place: Int
        var name: String
        var line: String
        var dropped: Bool
    }
    var rows: [Row] {
        guard let w = map?.world else { return [] }
        let byPlace = Dictionary(finds.map { ($0.place, $0) }, uniquingKeysWith: { a, _ in a })
        let all: [Row] = order.compactMap { i in
            let p = w.places[i]
            guard let f = byPlace[p.id] else { return nil }
            let stamped = MarkStore.shared.state(.country(p.id)).stamped
            return Row(id: p.id, place: i, name: p.n, line: Self.line(f, stamped: stamped), dropped: dropped.contains(i))
        }
        func last(_ r: Row) -> LocalDay { byPlace[r.id]?.visits.last?.to ?? LocalDay(y: 0, m: 1, d: 1) }
        return all.filter { !$0.dropped }.sorted { last($0) > last($1) } + all.filter(\.dropped).sorted { last($0) > last($1) }
    }
    /// a find's second line: its trip's dates ("12–18 Aug 2024"), "3 trips", "+2 trips" for a place already stamped,
    /// "Home" for your home base
    static func line(_ f: Finds.Find, stamped: Bool) -> String {
        if f.home { return "Home" }
        let n = f.visits.count
        if stamped { return "+\(n) \(n == 1 ? "trip" : "trips")" }
        if n != 1 { return "\(n) trips" }
        let a = f.visits[0].from, b = f.visits[0].to
        let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        if a == b { return "\(a.d) \(mon[a.m - 1]) \(a.y)" }
        if a.y == b.y && a.m == b.m { return "\(a.d)–\(b.d) \(mon[a.m - 1]) \(a.y)" }
        if a.y == b.y { return "\(a.d) \(mon[a.m - 1]) – \(b.d) \(mon[b.m - 1]) \(a.y)" }
        return "\(a.d) \(mon[a.m - 1]) \(a.y) – \(b.d) \(mon[b.m - 1]) \(b.y)"
    }

    // MARK: waiting finds (9.6)

    /// a waiting find (not stamped since) at this place
    func waits(_ i: Int) -> Bool { phase == .choosing && order.contains(i) && !dropped.contains(i) }

    /// THE REVIEW AGAIN (a tap on a waiting find, or the Upload tool): the water to 25%, the caption's number rolls to
    /// the waiting finds and its tail to "found", then the go circle grows at its place (A9.7's last half)
    func openReview(water w: Water, map m: MapController) {
        guard !w.upload, !order.isEmpty else { return }
        Feel.tap()
        water = w; map = m
        let at25 = w.stop == .quarter
        w.openUpload()
        phase = .review
        captionIn = false; markIn = false; xIn = false; goIn = false; message = nil
        count = order.count - dropped.count
        job += 1
        let me = job
        DispatchQueue.main.asyncAfter(deadline: .now() + (at25 ? 0.36 : 0.45)) { [self] in
            guard me == job else { return }
            withAnimation(Motion.quick) { captionIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
                guard me == job else { return }
                withAnimation(Motion.quick) { goIn = true }
            }
        }
    }

    /// LEAVING THE REVIEW (A9.13: a pull down): the go circle shrinks into its centre and the caption rolls back to
    /// your count; the finds stay darkened on the map, waiting, and are kept for the next launch
    private func leave() {
        guard let w = water, phase == .review, !busy else { return }
        Feel.land(speed: 0)
        busy = true
        job += 1
        let me = job
        withAnimation(Motion.quick) { goIn = false; captionIn = false }
        // every find dropped: nothing is left waiting (the way to let a whole upload go)
        if order.allSatisfy({ dropped.contains($0) }) { map?.found = []; forget() } else { save() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            busy = false
            guard me == job else { return }
            phase = .choosing; step = 0
            w.uploadFrom = nil
            w.closeUpload()
        }
    }

    /// the waiting finds' file, beside the store (in the app's own Application Support)
    private static var waitingURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("waiting-finds.json")
    }
    private struct Waiting: Codable {
        struct Find: Codable { var place: String; var visits: [[String]]; var home: Bool }
        var source: String
        var finds: [Find]
        var dropped: [String]
    }
    private func save() {
        guard let url = Self.waitingURL, let w = map?.world else { return }
        let ids = Set(order.map { w.places[$0].id })
        let out = Waiting(source: source.rawValue,
                          finds: finds.filter { ids.contains($0.place) }.map { f in
                              .init(place: f.place, visits: f.visits.map { [$0.from.description, $0.to.description] }, home: f.home) },
                          dropped: dropped.map { w.places[$0].id })
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(out) { try? d.write(to: url, options: .atomic) }
    }
    /// SIGN OUT: another account must never see these finds
    func signedOut() {
        job += 1
        map?.found = []
        forget()
    }
    /// nothing waits any more (go, ×): the file goes too
    private func forget() {
        order = []; dropped = []; finds = []
        if let url = Self.waitingURL { try? FileManager.default.removeItem(at: url) }
    }
    /// at launch, once the map is loaded: the waiting finds back, darkened (a place stamped since is not drawn darkened;
/// at the review it reads "+n trips")
    func restoreWaiting(map m: MapController) {
        guard let url = Self.waitingURL, let d = try? Data(contentsOf: url), let x = try? JSONDecoder().decode(Waiting.self, from: d),
              let w = m.world else { return }
        map = m
        source = MarkSource(rawValue: x.source) ?? .history
        let index = Dictionary(w.places.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        finds = x.finds.compactMap { f in
            let v = f.visits.compactMap { p -> Finds.Visit? in
                guard p.count == 2, let a = LocalDay(p[0]), let b = LocalDay(p[1]) else { return nil }
                return Finds.Visit(from: a, to: b, count: 1)
            }
            return Finds.Find(place: f.place, visits: v, home: f.home)
        }
        order = finds.compactMap { index[$0.place] }
        dropped = Set(x.dropped.compactMap { index[$0] })
        m.found = Set(order).subtracting(dropped)
        NSLog("wya upload: %d finds waiting", order.count)
    }

    /// THE REVIEW: a found country tapped is dropped (its darkening goes in one frame, the number rolls down) or kept
    /// again; true when the tap was the review's
    func tap(_ i: Int) -> Bool {
        guard phase == .review, !busy, let m = map, order.contains(i) else { return false }
        Feel.tap()
        if dropped.contains(i) { dropped.remove(i); m.found.insert(i) } else { dropped.insert(i); m.found.remove(i) }
        withAnimation(Motion.quick) { count = order.count - dropped.count }
        return true
    }

    /// GO (A9.10): every kept find becomes a stamp with its found trips, in one write and one undo step; the go circle
    /// shrinks into its centre, the caption's tail rolls back to "of 263" and the number to your count (the map's
    /// colours change in one frame as the write lands); then the sheet gives the water back
    func go() {
        guard phase == .review, !busy, let m = map, let world = m.world, let w = water else { return }
        let kept = order.filter { !dropped.contains($0) }
        guard !kept.isEmpty else { Feel.refuse(); return }
        Feel.stamp()
        // from here until the write has landed, taps, pulls and a second go wait
        busy = true
        job += 1
        let me = job
        let byPlace = Dictionary(finds.map { ($0.place, $0) }, uniquingKeysWith: { a, _ in a })
        let rows: [TravelStore.Found] = kept.compactMap { i in
            let p = world.places[i]
            guard let f = byPlace[p.id] else { return nil }
            return TravelStore.Found(key: .country(p.id), name: p.n, cc: p.id.uppercased(),
                                     trips: f.visits.map { ($0.from.description, $0.to.description) })
        }
        let src = source
        let n = rows.count
        withAnimation(Motion.quick) { goIn = false; captionIn = false }
        // above 25% the water comes down first (the rows roll out as it passes 50%)
        if w.stop != .quarter { w.go(.quarter) }
        Task {
            let ok = await MarkStore.shared.importFinds(rows, source: src, words: "\(n) \(n == 1 ? "place" : "places") from your \(src == .photos ? "photos" : "history")")
            guard ok else {
                // the store refused the write: nothing was stamped, the finds stay and the review comes back
                Feel.refuse()
                busy = false
                withAnimation(Motion.quick) { captionIn = true; goIn = true }
                return
            }
            m.found = []
            forget()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                busy = false
                guard me == job else { return }
                Feel.land(speed: 0)
                phase = .choosing; step = 0; count = 0
                w.uploadFrom = .quarter
                w.closeUpload()
            }
        }
    }

    /// × (A9.9): stops; nothing is stamped; the finds clear in one frame; the mark and × shrink; the number rolls back
    /// to your count and the tail to "of 263" (the sheet closes into the caption); the water stays at 25%
    func cancel() {
        guard let w = water, phase == .finding || phase == .review, !busy else { return }
        Feel.tap()
        job += 1
        map?.found = []
        forget()
        withAnimation(Motion.quick) { markIn = false; xIn = false; goIn = false; captionIn = false }
        let me = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            guard me == job else { return }
            phase = .choosing; step = 0; count = 0
            w.uploadFrom = .quarter
            w.closeUpload()
        }
    }

    /// A9.8: the mark goes, the number and tail roll out, the words roll in in the number's place; 1.5 s later step
    /// 2's pair comes back
    private func say(_ words: String) {
        Feel.refuse()
        UIAccessibility.post(notification: .announcement, argument: words)
        let me = job
        phase = .words
        // the number and its lines roll out (and the mark goes) before the words come into their place
        withAnimation(.smooth(duration: 0.15)) { markIn = false; captionIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [self] in
            guard me == job else { return }
            message = words
            withAnimation(Motion.quick) { captionIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38 + 1.5) { [self] in
                guard me == job, phase == .words else { return }
                endWords(close: false)
            }
        }
    }
    private func endWords(close: Bool) {
        job += 1
        let me = job
        withAnimation(.smooth(duration: 0.15)) { captionIn = false; xIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [self] in
            guard me == job else { return }
            message = nil
            phase = .choosing
            if close { water?.closeUpload(); step = 0 } else { grow(after: 0, job: me) }
        }
    }
}

/// THE SHEET: the pair at the water's top + 20, 96 pt tall, 16 pt inside the water's sides and 12 pt apart; each an
/// icon (22 pt) centred in its upper half and its word 12 pt under it, 15 pt semibold black; the whole box is the touch
struct UploadSheet: View {
    let water: Water
    let form: Water.Form
    @State private var u = UploadState.shared
    @State private var swipe: CGFloat = 0

    var body: some View {
        let L = water.layout
        let w = (L.W - 2 * L.sheetInset - 2 * 16 - 12) / 2
        let top = form.top + 20
        ZStack(alignment: .topLeading) {
            if u.phase == .choosing {
                ForEach(0 ..< 2, id: \.self) { side in
                    choice(side, width: w)
                        .position(x: L.sheetInset + 16 + w / 2 + CGFloat(side) * (w + 12), y: top + 48)
                }
            } else {
                finding(L)
                if u.phase == .review { reviewRows(L) }
            }
        }
        .frame(width: L.W, height: L.H, alignment: .topLeading)
        // a swipe right (more than 60 pt, mostly sideways) goes back from step 2; a tick as it passes the point
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { g in
            guard u.step != 0, abs(g.translation.width) > abs(g.translation.height) else { return }
            let past = g.translation.width > 60
            if past != (swipe > 60) { if past { Feel.tick() } }
            swipe = g.translation.width
        }.onEnded { g in
            defer { swipe = 0 }
            if u.step != 0, g.translation.width > 60 || g.predictedEndTranslation.width > 300,
               abs(g.translation.width) > abs(g.translation.height) { u.back() }
        })
        .photosPicker(isPresented: $u.picking, selection: $u.picked, maxSelectionCount: 0, selectionBehavior: .ordered,
                      matching: .any(of: [.images, .livePhotos, .videos]), photoLibrary: .shared())
        .onChange(of: u.picked) { _, items in
            u.picked(items)
            if !items.isEmpty { u.picked = [] }
        }
        .fileImporter(isPresented: $u.importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { u.imported(urls) }
        }
        .accessibilityAction(named: "Back") { u.back() }
    }

    /// FINDING'S ROW (9.4): the caption in its own place reading World / n / found (or A9.8's words in the number's
    /// place); the working mark 36 pt in from the water's left on the number's line; the × 44 pt in from its right
    /// (at the review the lime go circle, 44 pt, grows from the ×'s centre behind it)
    @ViewBuilder
    private func finding(_ L: Layout) -> some View {
        let y = max(L.headBottom + 12 + 52, form.top + 72)
        let name = u.map?.continent ?? "World"
        if let words = u.message {
            Text(u.captionIn ? words : Caption.blank(words, "\u{2002}"))
                .font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).lineLimit(2)
                .contentTransition(.numericText(value: u.captionIn ? 1 : 0))
                .frame(width: L.W - 2 * L.sheetInset - 2 * 72)
                .position(x: L.W / 2, y: y)
                .transition(.identity)
        } else {
            Caption(name: name, count: u.count, tail: "found", night: false, visible: u.captionIn)
                .position(x: L.W / 2, y: y)
                .transition(.identity)
        }
        WorkingMark(size: 20, running: u.markIn)
            .scaleEffect(u.markIn ? 1 : 0)
            .position(x: L.sheetInset + 36, y: y)
        ZStack {
            Circle().fill(Palette.lime).frame(width: 44, height: 44).scaleEffect(u.goIn ? 1 : 0)
            // the stamp's glyph is a bare ring until its icon is picked (as every unpicked icon); the × until the review
            if u.goIn {
                ToolRing(width: 2).fill(Palette.ink, style: FillStyle(eoFill: true)).frame(width: 22, height: 22)
                    .transition(.scale)
            } else {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.ink)
                    .scaleEffect(u.xIn ? 1 : 0)
                    .transition(.scale)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            if u.phase == .review { u.go() } else if u.phase == .finding { u.cancel() }
        }
        .position(x: L.W - L.sheetInset - 44, y: y)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(u.phase == .review ? "Stamp \(u.count) \(u.count == 1 ? "place" : "places")" : "Stop")
        .accessibilityAddTraits(.isButton)
    }

    /// THE REVIEW'S ROWS: under the caption once the water is at 50% or above (their words roll in as the water passes
    /// 50% and out as it comes back down); 56 pt rows, the flag 28 pt at 16 pt from the water's side
    @ViewBuilder
    private func reviewRows(_ L: Layout) -> some View {
        let y0 = max(L.headBottom + 12 + 52, form.top + 72) + 56
        let h = max(0, L.capsule.minY - 24 - y0)
        let shown = rowsShown
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(u.rows) { r in
                    HStack(spacing: 12) {
                        Group {
                            if let f = Flags.square(r.id) { f.resizable().interpolation(.high) } else { Color.clear }
                        }
                        .frame(width: 28, height: 28)
                        .scaleEffect(shown ? 1 : 0)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shown ? r.name : Caption.blank(r.name, "\u{2002}")).font(.body)
                                .foregroundStyle(Palette.ink.opacity(r.dropped ? 0.5 : 1))
                                .contentTransition(.numericText(value: shown ? 1 : 0))
                            Text(shown ? r.line : Caption.blank(r.line, "\u{2002}")).font(.footnote)
                                .foregroundStyle(Palette.ink.opacity(0.5))
                                .contentTransition(.numericText(value: shown ? 1 : 0))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                    .onTapGesture { _ = u.tap(r.place) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(r.name), \(r.line)\(r.dropped ? ", dropped" : "")")
                    .accessibilityAction(named: r.dropped ? "Keep" : "Drop") { _ = u.tap(r.place) }
                }
            }
            .animation(Motion.chrome, value: u.rows.map(\.id))
        }
        .scrollIndicators(.hidden)
        // the soft bottom edge (no word cut sharply), as Details' and the Stamped list's
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20)
            }
        }
        .frame(width: L.W - 2 * L.sheetInset, height: h)
        .position(x: L.W / 2, y: y0 + h / 2)
        .allowsHitTesting(shown)
        .onChange(of: form.top <= L.top(.half) + 12, initial: true) { _, v in
            withAnimation(v ? Motion.quick : .smooth(duration: 0.15)) { rowsShown = v }
        }
    }
    @State private var rowsShown = false

    private func choice(_ side: Int, width w: CGFloat) -> some View {
        let name = u.note[u.step * 2 + side] ?? UploadState.names[u.step][side]
        let grown = u.shapes[side]
        return VStack(spacing: 12) {
            ZStack {
                ToolRing(width: 2)
                    .fill(Palette.ink, style: FillStyle(eoFill: true))
                    .frame(width: 22, height: 22)
                    .scaleEffect(grown && !(u.locating && u.step == 2 && side == 1) ? 1 : 0)
                // Here waiting: the small working mark grows from the icon's centre as the icon shrinks into it
                if u.step == 2 && side == 1 {
                    WorkingMark(size: 20, running: u.locating).scaleEffect(u.locating ? 1 : 0)
                }
            }
            .frame(width: 22, height: 22)
            Text(u.words ? name : Caption.blank(name, "\u{2002}"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .contentTransition(.numericText(value: u.words ? 1 : 0))
        }
        .frame(width: w, height: 96)
        .contentShape(Rectangle())
        .onTapGesture { u.choose(side) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(u.note[u.step * 2 + side] ?? UploadState.spoken[u.step][side])
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(!u.words)
    }
}

/// A PICKED VIDEO, copied out of Photos into the app's temporary folder for reading (the copy is removed after)
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { f in
            let to = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + f.file.pathExtension)
            try FileManager.default.copyItem(at: f.file, to: to)
            return PickedMovie(url: to)
        }
    }
}

/// ONE LOCATION FIX for Here (the old app's Here.swift rule): When In Use asked at the press; the last known fix if it
/// is under an hour old; otherwise up to 15 s for a new one
@MainActor
final class OneFix: NSObject, CLLocationManagerDelegate {
    static let shared = OneFix()
    enum Result { case fix(CLLocation), refused, none }
    private let m = CLLocationManager()
    private var waiting: CheckedContinuation<Result, Never>?
    private var timer: DispatchWorkItem?

    func get() async -> Result {
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        switch m.authorizationStatus {
        case .denied, .restricted: return .refused
        default: break
        }
        if let l = m.location, -l.timestamp.timeIntervalSinceNow < 3600 { return .fix(l) }
        return await withCheckedContinuation { c in
            waiting = c
            if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() } else { m.requestLocation() }
            let t = DispatchWorkItem { [weak self] in self?.finish(.none) }
            timer = t
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: t)
        }
    }
    private func finish(_ r: Result) {
        timer?.cancel(); timer = nil
        waiting?.resume(returning: r); waiting = nil
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            guard self.waiting != nil else { return }
            switch s {
            case .denied, .restricted: self.finish(.refused)
            case .authorizedWhenInUse, .authorizedAlways: self.m.requestLocation()
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in self.finish(.fix(l)) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // a passing failure (no fix yet) keeps waiting until the 15 s are up; a refusal ends it
        if (error as? CLError)?.code == .denied { Task { @MainActor in self.finish(.refused) } }
    }
}

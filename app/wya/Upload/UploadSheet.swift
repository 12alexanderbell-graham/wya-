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
/// Not here yet (logged): finding on the map (9.4) and the review (9.5): a read's samples are counted, logged and
/// kept in `samples`; videos picked with Pick are not read (their place needs the file's own metadata).
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
    @ObservationIgnored private var job = 0
    @ObservationIgnored private var moving = false

    var isOpen: Bool { water?.upload ?? false }
    @ObservationIgnored private weak var water: Water?

    static let names = [["Photos", "Location"], ["Pick", "All"], ["File", "Here"]]
    static let spoken = [["Photos", "Location"], ["Pick photos", "All photos"], ["Location history file", "Where I am now"]]

    /// A9.1 and A9.2: the water to 25% (it stays if it is there), the caption's words out, then the pair in
    func open(water w: Water) {
        guard !w.upload else { return }
        water = w
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
        guard !moving, words else { return }
        Feel.tap()
        switch step {
        case 0: go(to: side == 0 ? 1 : 2, lead: side)
        case 1: side == 0 ? pick() : all()
        default: side == 0 ? file() : here()
        }
    }
    /// A9.3 back: step 2 to step 1 (a swipe right on the water)
    func back() {
        guard step != 0, !moving else { return }
        Feel.tick()
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

    /// pulled down or a tap on the map: the pair out, then the water back to where it was and the caption in
    func close() {
        guard let w = water, w.upload else { return }
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

    /// Pick: Apple's picker, no permission; when it closes with photos, their own place and time are read
    private func pick() { picking = true }
    func picked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var out: [HistoryReader.Sample] = []
            for it in items {
                guard let d = try? await it.loadTransferable(type: Data.self), let s = PhotosReader.sample(imageData: d) else { continue }
                out.append(HistoryReader.Sample(lat: s.lat, lon: s.lon, at: s.at, offset: s.offset, end: nil, asset: it.itemIdentifier))
            }
            found(out, from: .photos, read: items.count)
        }
    }
    /// All: Photos access asked at this press only; refused, the word says so and leads to Settings
    private func all() {
        if note[2] != nil { openSettings(); return }
        Task {
            guard await PhotosReader.ask() else { refuse(2, "Allow Photos in Settings"); return }
            let (s, skipped) = await PhotosReader.samples()
            found(s, from: .photos, read: s.count + skipped)
        }
    }
    /// File: the Files picker, JSON, several at once (Takeout's monthly files go in together)
    private func file() { importing = true }
    func imported(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            var out: [HistoryReader.Sample] = []
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                if let r = HistoryReader.read(url: u) { out += r.samples }
            }
            let got = out
            await MainActor.run { UploadState.shared.found(got, from: .history, read: urls.count) }
        }
    }
    /// Here: one fix, When In Use asked at this press only; the icon gives way to the working mark while it waits
    private func here() {
        if note[5] == "Allow Location in Settings" { openSettings(); return }
        guard !locating else { return }
        withAnimation(Motion.quick) { note[5] = nil; locating = true }
        Task {
            let r = await OneFix.shared.get()
            withAnimation(Motion.quick) { locating = false }
            switch r {
            case .fix(let l):
                Feel.land(speed: 0)
                found([HistoryReader.Sample(lat: l.coordinate.latitude, lon: l.coordinate.longitude, at: l.timestamp,
                                            offset: nil, end: nil, asset: nil)], from: .history, read: 1)
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

    /// what was read: kept for finding (9.4, next)
    private func found(_ s: [HistoryReader.Sample], from src: MarkSource, read n: Int) {
        samples = s; source = src
        NSLog("wya upload read %d items: %d samples with a place (%@)", n, s.count, src == .photos ? "photos" : "history")
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
            ForEach(0 ..< 2, id: \.self) { side in
                choice(side, width: w)
                    .position(x: L.sheetInset + 16 + w / 2 + CGFloat(side) * (w + 12), y: top + 48)
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
                      matching: .any(of: [.images, .livePhotos]), photoLibrary: .shared())
        .onChange(of: u.picked) { _, items in
            u.picked(items)
            if !items.isEmpty { u.picked = [] }
        }
        .fileImporter(isPresented: $u.importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { u.imported(urls) }
        }
        .accessibilityAction(named: "Back") { u.back() }
    }

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

import SwiftUI
import CoreLocation

/// WHICH STAMP'S VERIFY IS OPEN in the water (Part 4.5), and where it stands
@MainActor
@Observable
final class VerifyState {
    static let shared = VerifyState()
    private(set) var key: PlaceKey?
    private(set) var name = ""
    private(set) var place: Int?
    /// the stamp's proof as stored (nil: none yet)
    var proof: Verification?
    /// what the "Where you are" row says now (nil: its own name)
    var hereWord: String?
    var finding = false
    /// the consent line is up for this way (4.5.2)
    var consent: String?

    var isOpen: Bool { key != nil }

    func open(_ key: PlaceKey, name: String, place: Int, water: Water) {
        guard self.key == nil, !DetailsState.shared.isOpen else { return }
        Task {
            proof = await MarkStore.shared.verification(key)
            hereWord = nil; consent = nil; finding = false
            self.name = name
            self.place = place
            self.key = key
            Feel.tap()
            water.openDetails()
        }
    }
    func close(water: Water) {
        guard key != nil else { return }
        key = nil
        consent = nil
        water.closeDetails()
    }
}

/// VERIFY IN THE WATER (Part 4.5): the ways to prove a stamp, chosen by you, rows of 52 pt with no title (the card's
/// name is above). Laid out as Details and Map settings are: black and white, words on the water.
/// As built (30 Oct): there is no server yet, so nothing can be checked by a person or by the server. "Where you are"
/// works on the phone (asked at this press only; the inside test on the stamp's real place) and a proof is kept as
/// "Waiting to send" (the card reads "In process"); the other five ways are in the "not yet" look and refuse.
/// Remove the stamp works. Not here yet: the logo sphere while it waits (a plain "Finding you" for now), icons.
struct VerifySheet: View {
    let water: Water
    let map: MapController
    let form: Water.Form
    @State private var s = VerifyState.shared
    @State private var locator = Locator()

    static let ways: [(id: String, name: String)] = [
        ("here", "Where you are"), ("history", "Your location history"), ("library", "A photo from your library"),
        ("camera", "A photo now"), ("documents", "Travel documents"), ("other", "Send to us")]

    var body: some View {
        let L = water.layout
        let top = max(form.top + 20, L.headBottom + 8)
        let bottom = L.capsule.minY - 24
        let h = max(60, bottom - top)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if form.page > 0.5 || !CardState.shared.isOpen {
                    Text(s.name).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                        .padding(.bottom, 12)
                        .accessibilityAddTraits(.isHeader)
                }
                if let p = s.proof, p.state != "notAccepted" {
                    // the stamp's state as the sheet's top line (4.5.4)
                    Text(p.state == "verified" ? "Verified · \(Self.wayName(p.how))" : "Waiting to send · \(Self.wayName(p.how))")
                        .font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(minHeight: 52, alignment: .leading)
                } else {
                    ForEach(Self.ways, id: \.id) { w in wayRow(w.id, w.name) }
                }
                removeRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .frame(width: L.W - 2 * L.sheetInset, height: h)
        .position(x: L.W / 2, y: top + h / 2)
    }

    static func wayName(_ id: String) -> String { ways.first { $0.id == id }?.name ?? "Another way" }

    @ViewBuilder
    private func wayRow(_ id: String, _ name: String) -> some View {
        if s.consent == id {
            // THE CONSENT LINE (4.5.2): before anything leaves the phone; the lime go circle sends, anything else
            // rolls it back
            HStack(spacing: 12) {
                Text("Send to verify \(s.name)").font(.body).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Button { send(id) } label: {
                    Image(systemName: "arrow.right").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 36, height: 36).background(Palette.lime, in: .circle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
            }
            .frame(minHeight: 52)
        } else {
            let live = id == "here"
            Text(id == "here" ? (s.hereWord ?? name) : name)
                .font(.body)
                .foregroundStyle(Palette.ink.opacity(live ? 1 : 0.5))
                .contentTransition(.numericText())
                .animation(Motion.quick, value: s.hereWord)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    s.consent = nil
                    if live { here() } else { Feel.refuse() }
                }
                .accessibilityAddTraits(.isButton)
        }
    }

    /// Remove the stamp (red d94f3d, last): the water goes back first, then the stamp lifts (A4.18 as far as built:
    /// the card's own lift when this card made it, else the stamp just goes); the undo drop brings it back
    private var removeRow: some View {
        Text("Remove the stamp")
            .font(.body)
            .foregroundStyle(Palette.red)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let key = s.key else { return }
                Feel.tap()
                let n = s.name
                s.close(water: water)
                Task {
                    // after the water is back down (nothing moves into the card while it changes)
                    try? await Task.sleep(for: .milliseconds(450))
                    await MarkStore.shared.unstamp(key, name: n)
                    Feel.lift()
                    CardState.shared.order = await MarkStore.shared.passportOrder()
                }
            }
            .accessibilityAddTraits(.isButton)
    }

    /// WHERE YOU ARE: location asked at this press only; inside the stamp's place: the consent line; outside: the row
    /// rolls to "You're in <X>" for 2.5 s and back; location off: "Allow Location in Settings", a tap opens Settings
    private func here() {
        if s.hereWord == "Allow Location in Settings" {
            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            return
        }
        guard !s.finding else { return }
        Feel.tap()
        s.finding = true
        s.hereWord = "Finding you"
        Task {
            let r = await locator.once()
            s.finding = false
            switch r {
            case .denied:
                s.hereWord = "Allow Location in Settings"
            case .none:
                s.hereWord = "Can't find you"
            case .some(let c):
                guard let w = map.world, let i = s.place else { return }
                let at = w.place(at: EqualEarth.project(lon: c.longitude, lat: c.latitude))
                if at == i {
                    s.hereWord = nil
                    s.consent = "here"
                    Feel.land(speed: 0)
                } else {
                    Feel.refuse()
                    s.hereWord = "You're in \(at.map { w.places[$0].n } ?? "the sea")"
                    try? await Task.sleep(for: .seconds(2.5))
                    if s.hereWord?.hasPrefix("You're in") == true { s.hereWord = nil }
                }
            }
        }
    }

    /// sent: kept as Waiting to send until there is a server to send it to (one undo step)
    private func send(_ how: String) {
        guard let key = s.key else { return }
        Feel.tap()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let v = Verification(how: how, state: "waiting", when: f.string(from: Date()))
        s.proof = v
        s.consent = nil
        let n = s.name
        Task { await MarkStore.shared.setVerification(key, name: n, v) }
    }
}

/// one location, asked for at the press only; nil when it can't be found in 12 s
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    enum Result { case denied, none, some(CLLocationCoordinate2D) }
    private let m = CLLocationManager()
    private var wait: CheckedContinuation<Result, Never>?

    override init() {
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func once() async -> Result {
        if m.authorizationStatus == .denied || m.authorizationStatus == .restricted { return .denied }
        return await withCheckedContinuation { c in
            wait = c
            if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() } else { m.requestLocation() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.finish(.none) }
        }
    }
    private func finish(_ r: Result) {
        guard let w = wait else { return }
        wait = nil
        w.resume(returning: r)
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        Task { @MainActor in
            guard self.wait != nil else { return }
            if st == .denied || st == .restricted { self.finish(.denied) }
            else if st == .authorizedWhenInUse || st == .authorizedAlways { self.m.requestLocation() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let c = locations.last?.coordinate
        Task { @MainActor in self.finish(c.map { .some($0) } ?? .none) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.none) }
    }
}

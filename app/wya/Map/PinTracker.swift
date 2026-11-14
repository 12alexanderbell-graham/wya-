import Foundation
import CoreLocation

/// PINS' TRACKING (1 Oct; built now, 14 Nov): with your location shared, where you go is drawn as pins on its own map,
/// "Where I've been", at the precision you pick in Map settings: Exact (a new pin past 300 m), City (past 15 km) or
/// About 100 km. Apple's significant-change and visit services do the watching, so it goes on with the app closed when
/// the location is shared Always, and costs almost no battery. Off stops it at once.
@MainActor
final class PinTracker: NSObject, CLLocationManagerDelegate {
    static let shared = PinTracker()
    private let manager = CLLocationManager()
    private var mode = "off"
    static let mapName = "Where I've been"

    private override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = true
    }

    /// how far from the last tracked pin a new place must be
    private var step: CLLocationDistance {
        switch mode { case "exact": 300; case "city": 15_000; default: 100_000 }
    }

    /// the setting followed (at launch and whenever it changes)
    func follow(_ m: String) {
        mode = m
        guard m != "off" else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.stopMonitoringVisits()
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization(); start()
        case .authorizedAlways: start()
        default: break
        }
    }

    private func start() {
        guard mode != "off", CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
    }

    /// the tracked map, made the first time something is tracked
    private func trackedMap() -> UUID {
        if let m = PinMaps.shared.all.first(where: { $0.name == Self.mapName }) { return m.id }
        return PinMaps.shared.quietly(Self.mapName).id
    }

    private func took(_ l: CLLocation, when: Date) {
        guard mode != "off", l.horizontalAccuracy >= 0, l.horizontalAccuracy < max(1000, step / 2) else { return }
        let map = trackedMap()
        if let last = PinStore.shared.pins.last(where: { $0.map == map }),
           CLLocation(latitude: last.lat, longitude: last.lon).distance(from: l) < step { return }
        PinStore.shared.track(at: l.coordinate, map: map, when: when)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            let s = m.authorizationStatus
            if s == .authorizedAlways || s == .authorizedWhenInUse { self.start() }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations ls: [CLLocation]) {
        let got = ls.map { ($0, $0.timestamp) }
        Task { @MainActor in for (l, t) in got { self.took(l, when: t) } }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didVisit v: CLVisit) {
        let l = CLLocation(coordinate: v.coordinate, altitude: 0, horizontalAccuracy: v.horizontalAccuracy, verticalAccuracy: -1, timestamp: v.arrivalDate)
        let when = v.arrivalDate == .distantPast ? Date() : v.arrivalDate
        Task { @MainActor in self.took(l, when: when) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}

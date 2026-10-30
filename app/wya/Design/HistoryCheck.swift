#if DEBUG
import Foundation
import Photos

/// THE HISTORY READER'S CHECKS (Part 9.12's fixtures for shapes A to D, the time model's offsets; Part 10 Step 7), run
/// inside the app by the test driver's `historycheck`, against the map's own world shapes. Results into
/// snaps/historycheck.log: PASS or FAIL, and what was seen.
@MainActor
enum HistoryCheck {
    static func run(map: MapController) -> [String] {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool, _ seen: String) { out.append("\(ok ? "PASS" : "FAIL") \(name): \(seen)") }
        guard let w = map.world else { return ["FAIL world: not loaded"] }
        let placeAt: (Double, Double) -> String? = { lat, lon in
            w.place(at: EqualEarth.project(lon: lon, lat: lat)).map { w.places[$0].id }
        }
        func rows(_ json: String) -> (HistoryReader.Result?, [HistoryReader.Presence]) {
            let r = HistoryReader.read(Data(json.utf8))
            return (r, r.map { HistoryReader.presence($0.samples, placeAt: placeAt) } ?? [])
        }
        func show(_ p: [HistoryReader.Presence]) -> String { p.map { "\($0.day) \($0.place) x\($0.count)" }.joined(separator: ", ") }

        // A. Records.json: Munich at 23:30 UTC is the next day in Munich (UTC+2 in summer, from its zone); a point at
        // 3,000 m accuracy is dropped; 0,0 is dropped
        let a = """
        {"locations":[
         {"latitudeE7":481372000,"longitudeE7":115755000,"accuracy":20,"timestamp":"2024-07-01T23:30:00Z"},
         {"latitudeE7":481372000,"longitudeE7":115755000,"accuracy":3000,"timestamp":"2024-07-01T12:00:00Z"},
         {"latitudeE7":0,"longitudeE7":0,"accuracy":10,"timestampMs":"1719835200000"},
         {"latitudeE7":356762000,"longitudeE7":1396503000,"accuracy":15,"timestampMs":"1719867600000"}]}
        """
        let (ra, pa) = rows(a)
        check("A shape", ra?.shape == .records && ra?.dropped == 2, "shape \(ra?.shape.rawValue ?? "none"), dropped \(ra?.dropped ?? -1)")
        check("A days by the place's zone", show(pa) == "2024-07-02 de x1, 2024-07-02 jp x1", show(pa))

        // B. Semantic monthly: a visit in Lisbon 3 to 5 Aug (startTimestamp / endTimestamp, missed by the old code)
        // makes three days; an activity's two ends with the Ms form
        let b = """
        {"timelineObjects":[
         {"placeVisit":{"location":{"latitudeE7":387223000,"longitudeE7":-91393000},
          "duration":{"startTimestamp":"2024-08-03T10:00:00Z","endTimestamp":"2024-08-05T09:00:00Z"}}},
         {"activitySegment":{"startLocation":{"latitudeE7":387223000,"longitudeE7":-91393000},
          "endLocation":{"latitudeE7":404168000,"longitudeE7":-37038000},
          "duration":{"startTimestampMs":"1722852000000","endTimestampMs":"1722866400000"}}}]}
        """
        let (rb, pb) = rows(b)
        check("B shape", rb?.shape == .semantic, "shape \(rb?.shape.rawValue ?? "none")")
        check("B visit covers its days", show(pb) == "2024-08-03 pt x1, 2024-08-04 pt x1, 2024-08-05 pt x2, 2024-08-05 es x1", show(pb))

        // C. Android Timeline.json: a visit in Kathmandu with +05:45 (345 minutes) given by the segment: 19:00 UTC on
        // 1 Oct is 00:45 on 2 Oct there; a raw signal in degrees
        let c = """
        {"semanticSegments":[
         {"startTime":"2024-10-01T19:00:00.000Z","endTime":"2024-10-01T20:00:00.000Z","startTimeTimezoneUtcOffsetMinutes":345,
          "visit":{"topCandidate":{"placeLocation":{"latLng":"27.7172°, 85.3240°"}}}}],
         "rawSignals":[{"position":{"LatLng":"48.8566°, 2.3522°","timestamp":"2024-10-05T08:00:00.000+02:00"}}]}
        """
        let (rc, pc) = rows(c)
        check("C shape", rc?.shape == .android, "shape \(rc?.shape.rawValue ?? "none")")
        check("C Nepal offset +05:45", show(pc) == "2024-10-02 np x1, 2024-10-05 fr x1", show(pc))

        // D. iPhone export: a walk whose path points are timed by minutes from the start (the old code gave them all the
        // start): 23:50 local + 30 min crosses midnight, so the last point is the next day
        let d = """
        [{"startTime":"2024-12-31T23:50:00.000+01:00","endTime":"2025-01-01T00:40:00.000+01:00",
          "activity":{"start":"geo:47.376900,8.541700","end":"geo:47.366700,8.550000"},
          "timelinePath":[{"point":"geo:47.3700,8.5450","durationMinutesOffsetFromStartTime":"5"},
                          {"point":"geo:47.3680,8.5480","durationMinutesOffsetFromStartTime":"30"}]}]
        """
        let (rd, pd) = rows(d)
        let days = Set(pd.map { $0.day.description })
        check("D shape", rd?.shape == .iphone, "shape \(rd?.shape.rawValue ?? "none")")
        check("D path offsets", days == ["2024-12-31", "2025-01-01"] && pd.allSatisfy { $0.place == "ch" }, show(pd))

        // not a history: refused
        check("not a history", HistoryReader.read(Data(#"{"hello":[1,2,3]}"#.utf8)) == nil, "refused")
        return out
    }

    /// the simulator's photo library read (Part 9.13's library): asks for access the first time (the system's question),
    /// then every photo's place and day, the presence rows and the photo links; counts and the rows into the log
    static func photos(map: MapController) async -> [String] {
        guard let w = map.world else { return ["FAIL world: not loaded"] }
        let placeAt: (Double, Double) -> String? = { lat, lon in
            w.place(at: EqualEarth.project(lon: lon, lat: lat)).map { w.places[$0].id }
        }
        guard await PhotosReader.ask() else { return ["FAIL photos: no access (\(PhotosReader.access.rawValue))"] }
        let t0 = Date()
        let (samples, skipped) = await PhotosReader.samples()
        let rows = HistoryReader.presence(samples, placeAt: placeAt)
        let links = PhotosReader.links(samples, placeAt: placeAt)
        var out = ["photos: \(samples.count) with a place, \(skipped) without, read in \(Int(Date().timeIntervalSince(t0) * 1000)) ms",
                   "rows: \(rows.count); links: \(links.count)"]
        out += rows.prefix(30).map { "  \($0.day) \($0.place) x\($0.count)" }
        out.append((samples.count == links.count + samples.filter { placeAt($0.lat, $0.lon) == nil }.count ? "PASS" : "FAIL")
                   + " every photo in a place has its link")
        return out
    }
}
#endif

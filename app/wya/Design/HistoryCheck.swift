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
        func check(_ name: String, _ ok: Bool, _ seen: String) {
            out.append("\(ok ? "PASS" : "FAIL") \(name): \(seen)")
            NSLog("wya historycheck %@", out.last!)   // as it goes, so a check that never ends shows where
        }
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

        // the streaming scanner gives exactly what the parser gives (a nested activity's own timestamp ignored, a
        // string holding a brace, accuracy drops), then a 60 MB file: scanned, timed
        var pts: [String] = []
        for k in 0 ..< 2000 {
            let acc = k % 7 == 0 ? 2500 : 30
            let t = k % 2 == 0 ? "\"timestamp\":\"2024-05-\(String(format: "%02d", 1 + k % 28))T12:00:00Z\""
                                : "\"timestampMs\":\"\(1714564800000 + k * 3_600_000)\""
            pts.append("{\"latitudeE7\":\(470000000 + k * 1000),\"longitudeE7\":\(80000000 + k * 1000),\"accuracy\":\(acc),"
                       + "\"activity\":[{\"timestamp\":\"1999-01-01T00:00:00Z\",\"activity\":[{\"type\":\"STILL}{\",\"confidence\":90}]}],\(t)}")
        }
        let big = Data(("{\"locations\":[" + pts.joined(separator: ",") + "]}").utf8)
        let parsed = HistoryReader.read(big)
        let saved = HistoryReader.streamOver
        HistoryReader.streamOver = 0
        let scanned = HistoryReader.read(big)
        HistoryReader.streamOver = saved
        check("A scanner = parser", parsed?.samples == scanned?.samples && parsed?.dropped == scanned?.dropped && (parsed?.samples.count ?? 0) > 1500,
              "parsed \(parsed?.samples.count ?? -1)/\(parsed?.dropped ?? -1), scanned \(scanned?.samples.count ?? -1)/\(scanned?.dropped ?? -1)")
        var huge = Data("{\"locations\":[".utf8)
        let one = Data(pts[1].utf8), comma = Data(",".utf8)
        var copies = 0
        while huge.count < 60 * 1024 * 1024 { if copies > 0 { huge.append(comma) }; huge.append(one); copies += 1 }
        huge.append(Data("]}".utf8))
        let t0 = Date()
        let hr = HistoryReader.read(huge)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        check("A 60 MB scanned", hr?.samples.count == copies, "\(copies) points, \(hr?.samples.count ?? -1) read in \(ms) ms (debug build)")

        // times read from their bytes agree with Apple's ISO formatter (fractions, offsets, Z, a leap day, a bad day)
        let fFrac = ISO8601DateFormatter(); fFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fPlain = ISO8601DateFormatter(); fPlain.formatOptions = [.withInternetDateTime]
        let times = ["2024-10-01T19:00:00.000Z", "2024-12-31T23:50:00.000+01:00", "2024-10-05T08:00:00.123+05:45",
                     "1999-01-01T00:00:00Z", "2024-02-29T12:00:00-08:00", "2023-02-29T12:00:00Z", "2024-07-01T23:30:00.5Z",
                     "1969-07-20T20:17:40Z"]
        let bad = times.filter { t in
            // (an impossible day, 29 Feb 2023, is left by the byte reader to Apple's, which reads it leniently)
            let mine = HistoryReader.date(t)
            let apple = fFrac.date(from: t) ?? fPlain.date(from: t)
            return mine.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) } != apple.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) }
        }
        check("times read like Apple's", bad.isEmpty, bad.isEmpty ? "\(times.count) agree" : "differ: \(bad.joined(separator: " "))")

        // C and D cut into segments (big files): the same samples as parsing whole, on many copies of the fixtures above
        // (a string holding a bracket and a brace in C's profile, which is not a segment), then a 60 MB D, timed
        func same(_ name: String, _ json: String) {
            let whole = HistoryReader.read(Data(json.utf8))
            let saved = HistoryReader.streamOver
            HistoryReader.streamOver = 0
            let cut = HistoryReader.read(Data(json.utf8))
            HistoryReader.streamOver = saved
            check("\(name) cut = parsed", whole?.samples == cut?.samples && whole?.dropped == cut?.dropped && whole?.shape == cut?.shape
                  && (whole?.samples.count ?? 0) > 100,
                  "parsed \(whole?.samples.count ?? -1)/\(whole?.dropped ?? -1), cut \(cut?.samples.count ?? -1)/\(cut?.dropped ?? -1)")
        }
        let cSeg = #"{"startTime":"2024-10-01T19:00:00.000Z","endTime":"2024-10-01T20:00:00.000Z","startTimeTimezoneUtcOffsetMinutes":345,"visit":{"topCandidate":{"placeLocation":{"latLng":"27.7172°, 85.3240°"}}},"timelinePath":[{"point":"27.7°, 85.3°","time":"2024-10-01T19:30:00.000+05:45"}]}"#
        let cSig = #"{"position":{"LatLng":"48.8566°, 2.3522°","timestamp":"2024-10-05T08:00:00.000+02:00"}}"#
        same("C", "{\"semanticSegments\":[" + Array(repeating: cSeg, count: 150).joined(separator: ",")
             + "],\"rawSignals\":[" + Array(repeating: cSig, count: 150).joined(separator: ",")
             + #"],"userLocationProfile":{"frequentPlaces":[{"label":"HOME ]}{ \"x","placeLocation":"1°, 2°"}]}}"#)
        let dSeg = #"{"startTime":"2024-12-31T23:50:00.000+01:00","endTime":"2025-01-01T00:40:00.000+01:00","activity":{"start":"geo:47.376900,8.541700","end":"geo:47.366700,8.550000"},"timelinePath":[{"point":"geo:47.3700,8.5450","durationMinutesOffsetFromStartTime":"5"},{"point":"geo:47.3680,8.5480","durationMinutesOffsetFromStartTime":"30"}]}"#
        same("D", "[" + Array(repeating: dSeg, count: 150).joined(separator: ",\n") + "]")
        var hugeD = Data("[".utf8)
        let oneD = Data(dSeg.utf8)
        var segCount = 0
        while hugeD.count < 60 * 1024 * 1024 { if segCount > 0 { hugeD.append(comma) }; hugeD.append(oneD); segCount += 1 }
        hugeD.append(Data("]".utf8))
        let t1 = Date()
        let hd = HistoryReader.read(hugeD)
        let msD = Int(Date().timeIntervalSince(t1) * 1000)
        check("D 60 MB cut", hd?.samples.count == segCount * 4 && hd?.shape == .iphone,
              "\(segCount) segments, \(hd?.samples.count ?? -1) samples in \(msD) ms (debug build)")

        // visits (step 5): photos allow 4 days between, history 1; home (step 6): the place in over 40% of the months
        func row(_ day: String, _ place: String) -> HistoryReader.Presence {
            HistoryReader.Presence(day: LocalDay(day)!, place: place, count: 1, first: .now, last: .now, cell: 0)
        }
        let jp = ["2024-03-01", "2024-03-02", "2024-03-07", "2024-03-13"].map { row($0, "jp") }
        func spans(_ f: [Finds.Find]) -> String {
            f.map { "\($0.place)\($0.home ? " home" : ""): " + $0.visits.map { "\($0.from)..\($0.to)" }.joined(separator: " ") }.joined(separator: "; ")
        }
        let fp = Finds.finds(jp, source: .photos), fh = Finds.finds(jp, source: .history)
        check("visits from photos", spans(fp) == "jp: 2024-03-01..2024-03-07 2024-03-13..2024-03-13", spans(fp))
        check("visits from history", spans(fh) == "jp: 2024-03-01..2024-03-02 2024-03-07..2024-03-07 2024-03-13..2024-03-13", spans(fh))
        let lived = ["2024-01-05", "2024-02-05", "2024-03-05", "2024-04-05", "2024-06-05"].map { row($0, "ch") } + [row("2024-05-10", "it")]
        let fl = Finds.finds(lived, source: .history)
        check("home kept out of the trips", spans(fl) == "it: 2024-05-10..2024-05-10; ch home: ", spans(fl))

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

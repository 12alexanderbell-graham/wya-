import Foundation
import Photos
import ImageIO

/// THE PHOTOS READ (Part 9.7: "Photos", steps 1 and 8; Part 10 Step 7's reading core, no screens): every image and
/// video's place and time, read in batches of 1,000 inside an autorelease pool, yielding between batches; only
/// `location` and `creationDate` are read (no picture is decoded). Each becomes a history sample carrying its asset id,
/// so the rows it makes can keep their photo links (Verify's "your photos", Books).
///
/// Not here yet (logged): Pick without Photos access (each file's own metadata), the next scan reading only what
/// changed (`fetchPersistentChanges(since:)`), the UI's 10-a-second updates (no screen yet).
nonisolated enum PhotosReader {
    struct Link: Equatable, Sendable {
        var asset: String
        var day: LocalDay
        var place: String
    }

    /// what access there is now (nothing is asked here)
    static var access: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    /// ask for access (the system's own question); true when the library can be read, in full or limited
    static func ask() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    /// every photo and video with a place and a time, oldest first; `progress` is told how many have been read
    static func samples(progress: ((Int, Int) -> Void)? = nil) async -> (samples: [HistoryReader.Sample], skipped: Int) {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        opts.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let all = PHAsset.fetchAssets(with: opts)
        var out: [HistoryReader.Sample] = []
        var skipped = 0
        var i = 0
        while i < all.count {
            let end = min(all.count, i + 1000)
            autoreleasepool {
                all.enumerateObjects(at: IndexSet(i ..< end), options: []) { a, _, _ in
                    guard let l = a.location, let at = a.creationDate,
                          !(l.coordinate.latitude == 0 && l.coordinate.longitude == 0) else { skipped += 1; return }
                    out.append(HistoryReader.Sample(lat: l.coordinate.latitude, lon: l.coordinate.longitude, at: at,
                                                    offset: nil, end: nil, asset: a.localIdentifier))
                }
            }
            i = end
            progress?(i, all.count)
            await Task.yield()
        }
        return (out, skipped)
    }

    /// A PICKED PHOTO'S OWN PLACE AND TIME (Pick needs no Photos access, so no PHAsset): the file's GPS and the time it
    /// was taken, with the offset the camera wrote (OffsetTimeOriginal) when there is one; nil without a place or a time
    static func sample(imageData d: Data) -> (lat: Double, lon: Double, at: Date, offset: Int?)? {
        guard let src = CGImageSourceCreateWithData(d as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let gps = p[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var lat = gps[kCGImagePropertyGPSLatitude] as? Double, var lon = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        guard !(lat == 0 && lon == 0) else { return nil }
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard let when = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
                ?? ((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFDateTime] as? String) else { return nil }
        // "2024:10:01 19:00:00" in the camera's own time; "+05:45" beside it when the camera wrote one
        let offText = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String
        let off = offText.flatMap { HistoryReader.offsetOf("0000-00-00T00:00:00" + $0) }
        let iso = when.prefix(10).replacingOccurrences(of: ":", with: "-") + "T" + when.dropFirst(11).prefix(8)
            + (offText ?? "Z")
        guard let local = HistoryReader.date(iso) else { return nil }
        // with no offset written, the camera's clock is the place's own: read as UTC and given offset 0, so the day it
        // makes is the day on the camera's clock (the day where it was taken, Part 9.9); its instant is off by the
        // zone, which nothing here uses
        return (lat, lon, local, off ?? 0)
    }

    /// each photo that made a presence row, as a link (asset, the day where it was taken, its place)
    static func links(_ samples: [HistoryReader.Sample], placeAt: (Double, Double) -> String?) -> [Link] {
        var cellPlace: [Int64: String?] = [:]
        var out: [Link] = []
        for s in samples {
            guard let asset = s.asset else { continue }
            let cell = HistoryReader.cell(s.lat, s.lon)
            let place: String?
            if let p = cellPlace[cell] { place = p } else { place = placeAt(s.lat, s.lon); cellPlace[cell] = place }
            guard let place else { continue }
            out.append(Link(asset: asset, day: LocalDay(s.at, in: HistoryReader.zone(s, place)), place: place))
        }
        return out
    }
}

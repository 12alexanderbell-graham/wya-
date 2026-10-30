import Foundation
import Photos

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

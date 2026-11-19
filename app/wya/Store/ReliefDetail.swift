import Foundation

/// A COUNTRY'S FINER RELIEF: the sea's depth and the land's height round one country at 30 arc-seconds (NOAA's ETOPO
/// 2022, public domain), eight times the world picture's detail, on the same scale the map colours by (depth
/// log1p(d / 25) / log1p(6000 / 25), height log1p(h / 150) / log1p(5000 / 150), 0 to 255). The biggest countries are
/// kept to 4096 across, so theirs is a little coarser. It comes from the data server when the country opens (Part 17)
/// and is kept on the phone after.
///
/// native/relief/<cc>.wyar: "WYRD", u32 1, f32 west, south, east, north (degrees), u32 width, u32 height, then
/// width × height pairs of bytes (depth, height), rows from the north.
nonisolated struct ReliefDetail: Sendable {
    let west: Double, south: Double, east: Double, north: Double
    let width: Int
    let height: Int
    let bytes: Data

    static func path(_ cc: String) -> String { "native/relief/\(cc).wyar" }

    init?(data d: Data) {
        guard d.count >= 32, d.prefix(4) == Data("WYRD".utf8) else { return nil }
        func u32(_ o: Int) -> Int { Int(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
        func f32(_ o: Int) -> Double { Double(d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float32.self) }) }
        guard u32(4) == 1 else { return nil }
        west = f32(8); south = f32(12); east = f32(16); north = f32(20)
        width = u32(24); height = u32(28)
        // (a damaged header never asks for more than a picture can be)
        guard width > 1, height > 1, width <= 8192, height <= 8192, east > west, north > south,
              d.count == 32 + width * height * 2 else { return nil }
        bytes = d.subdata(in: d.startIndex + 32 ..< d.endIndex)
    }

    /// the country's picture from the phone, or the data server; nil when it can't be had now (no such country there:
    /// the map keeps the world's picture). `offline`: the server couldn't be reached, worth asking again
    @concurrent static func fetch(_ cc: String) async -> (detail: ReliefDetail?, offline: Bool) {
        let a = await Servers.data.file(path(cc))
        if case .offline = a { return (nil, true) }
        guard case .ok(let d) = a else { return (nil, false) }
        // (a kept file that can't be read is let go, so the next open asks the server again)
        guard let r = ReliefDetail(data: d) else { DevDataClient.forget(path(cc)); return (nil, false) }
        return (r, false)
    }
}

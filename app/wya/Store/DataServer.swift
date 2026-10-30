import Foundation

/// THE DATA CLIENT (Part 17.7): the files that are not in the app (finer region levels first; towns, things and
/// collections later), asked for by their path under `v1/` and kept in a cache in Application Support, so a file read
/// once works offline from then on. The base address is the Mac's dev server (`server/serve.py` on :8787, which the
/// Simulator reaches as localhost) until the real host (Step 16, Cloudflare R2): one setting, here.
///
/// On the Simulator, when the dev server is not running, the same files are read from the server's own folder on the
/// Mac (`server/public.nosync/v1/`, which the Simulator can read), so testing never depends on the server having been
/// started. A phone has no such fallback: no server, no file ("Not ready", 6.6).
nonisolated struct DevDataClient: DataClient {
    static let base = URL(string: "http://localhost:8787/v1/")!

    func file(_ path: String) async -> ServerAnswer<Data> {
        if let d = try? Data(contentsOf: Self.cache(path)) { return .ok(d) }
        var answer: ServerAnswer<Data> = .offline
        var req = URLRequest(url: Self.base.appending(path: path), timeoutInterval: 20)
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        if let (d, r) = try? await URLSession.shared.data(for: req), let h = r as? HTTPURLResponse {
            answer = h.statusCode == 200 ? .ok(d) : h.statusCode == 404 ? .missing : .offline
        }
        #if targetEnvironment(simulator)
        if case .offline = answer, let d = Self.fromServerFolder(path) { answer = .ok(d) }
        #endif
        if case .ok(let d) = answer {
            let url = Self.cache(path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: url, options: .atomic)
        }
        return answer
    }

    /// where a file is kept once it has come (Application Support/data/v1/<path>)
    static func cache(_ path: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appending(path: "data/v1").appending(path: path)
    }

    #if targetEnvironment(simulator)
    /// the server's own gzipped copy, read from the Mac's disk (Simulator only)
    static func fromServerFolder(_ path: String) -> Data? {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return nil }
        let folder = home + "/Library/Mobile Documents/com~apple~CloudDocs/wya?!/server/public.nosync/v1/"
        guard let gz = try? Data(contentsOf: URL(fileURLWithPath: folder + path + ".gz")) else { return nil }
        return gunzip(gz)
    }
    #endif

    /// a gzip member's body (the header's optional fields skipped), inflated
    static func gunzip(_ d: Data) -> Data? {
        guard d.count > 18, d[d.startIndex] == 0x1f, d[d.startIndex + 1] == 0x8b else { return d }
        let b = [UInt8](d)
        let flags = b[3]
        var i = 10
        if flags & 4 != 0 { i += 2 + Int(b[i]) + Int(b[i + 1]) << 8 }
        if flags & 8 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { return nil }
        return try? (Data(b[i ..< b.count - 8]) as NSData).decompressed(using: .zlib) as Data
    }
}

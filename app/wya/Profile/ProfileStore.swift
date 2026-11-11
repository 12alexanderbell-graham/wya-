import Foundation

/// WHO YOU ARE ON YOUR PROFILE: your name, handle, code, bio and picture, kept on the phone (Application Support,
/// profile.json). Nothing here is made up: an account with no name shows none.
@MainActor @Observable
final class ProfileStore {
    static let shared = ProfileStore()

    struct Me: Codable, Equatable {
        var name = ""
        /// lowercase, without the "@"; empty until picked (then it is made from the name)
        var handle = ""
        /// the account's code, given by the server once there is an account; empty until then
        var code = ""
        var bio = ""
    }
    private(set) var me = Me()

    /// the handle as it is shown: the one picked, else the name in small letters with nothing between them
    var handleShown: String {
        let h = me.handle.isEmpty ? me.name.lowercased().filter { $0.isLetter || $0.isNumber } : me.handle
        return h.isEmpty ? "" : "@" + h
    }

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("profile.json")
    }
    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u), let m = try? JSONDecoder().decode(Me.self, from: d) { me = m }
    }
    func set(_ change: (inout Me) -> Void) {
        var m = me
        change(&m)
        // (a bio is 120 characters at most)
        if m.bio.count > 120 { m.bio = String(m.bio.prefix(120)) }
        guard m != me else { return }
        me = m
        guard let u = Self.url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: u, options: .atomic) }
    }
}

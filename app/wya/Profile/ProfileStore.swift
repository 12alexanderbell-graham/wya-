import Foundation
import UIKit

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
        /// THE PICTURE: nil is your initial on `colour` (on black with none picked); "photo" is the photo you uploaded
        /// (profile-photo.jpg beside profile.json); "flag:de" is one of your nationalities' flags
        var picture: String?
        /// the picture's colour, picked on the colour picker (no presets)
        var colour: ColourPick?
    }
    private(set) var me = Me()
    /// the uploaded photo, read once
    private(set) var photo: UIImage?
    /// a change shown but not written yet (the colour picker's drag writes once, when the finger lifts)
    @ObservationIgnored private var unsaved = false

    /// the handle as it is shown: the one picked, else the name in small letters with nothing between them
    var handleShown: String {
        let h = me.handle.isEmpty ? me.name.lowercased().filter { $0.isLetter || $0.isNumber } : me.handle
        return h.isEmpty ? "" : "@" + h
    }

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("profile.json")
    }
    private static var photoURL: URL? { url?.deletingLastPathComponent().appendingPathComponent("profile-photo.jpg") }
    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u), let m = try? JSONDecoder().decode(Me.self, from: d) { me = m }
        if me.picture == "photo", let p = Self.photoURL { photo = UIImage(contentsOfFile: p.path) }
    }
    static let nameMax = 30, handleMax = 20, bioMax = 120
    /// a change; `keep: false` shows it without writing it (a drag on the colour picker), the next kept change writes
    func set(_ change: (inout Me) -> Void, keep: Bool = true) {
        var m = me
        change(&m)
        if m.name.count > Self.nameMax { m.name = String(m.name.prefix(Self.nameMax)) }
        if m.bio.count > Self.bioMax { m.bio = String(m.bio.prefix(Self.bioMax)) }
        if m != me { me = m; unsaved = true }
        guard keep, unsaved, let u = Self.url else { return }
        unsaved = false
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(me) { try? d.write(to: u, options: .atomic) }
    }
    /// the uploaded photo gone from the phone (the picture is your initial again)
    func removePhoto() {
        if let p = Self.photoURL { try? FileManager.default.removeItem(at: p) }
        photo = nil
        if me.picture == "photo" { set { $0.picture = nil } }
    }
    /// A PHOTO UPLOADED: its middle square, 600 pixels across, kept as the picture
    func setPhoto(_ data: Data) async {
        guard let made = await Task.detached(priority: .userInitiated, operation: { () -> (UIImage, Data)? in
            guard let img = UIImage(data: data) else { return nil }
            let s = min(img.size.width, img.size.height)
            let side: CGFloat = min(600, s * img.scale)
            let f = UIGraphicsImageRendererFormat(); f.scale = 1
            let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { _ in
                let k = side / s
                img.draw(in: CGRect(x: -(img.size.width - s) / 2 * k, y: -(img.size.height - s) / 2 * k,
                                    width: img.size.width * k, height: img.size.height * k))
            }
            guard let jpg = out.jpegData(compressionQuality: 0.85) else { return nil }
            return (out, jpg)
        }).value, let p = Self.photoURL else { Feel.refuse(); return }
        try? FileManager.default.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? made.1.write(to: p, options: .atomic)) != nil else { Feel.refuse(); return }
        photo = made.0
        set { $0.picture = "photo" }
    }
}

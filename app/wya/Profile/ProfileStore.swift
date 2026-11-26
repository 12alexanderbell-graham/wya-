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
        /// THE LETTER'S COLOUR (20 Oct #30), picked as the picture's is; nil: white, black on a pale picture
        var letter: ColourPick? = nil
        /// THE BACKGROUND'S FOUR COLOURS, picked on the colour picker; nil is the app's own living gradient
        var ground: [ColourPick]?
        /// THE BACKGROUND'S STRENGTH, 0 calm to 1 strong (nil: the middle, the picture's gradient of the first app);
        /// previewed live on the page as the slider moves
        var groundStrength: Double? = nil
        /// when the handle was changed (seconds since 1970): twice in any 14 days (W06 #42)
        var handleChanges: [Double]? = nil
        /// YOUR HOME BASE (13 Sep "a thing you pick"; 17 Sep, in v1's Profile): the town you live in, picked from the
        /// towns; nil until picked (then the badges' "far from home" measure from your first passport's middle)
        var home: Home? = nil
        /// WHERE THE PHOTO SITS IN ITS CIRCLE (3 Oct: move and zoom an uploaded photo): the circle's middle on the
        /// photo as a fraction of its width and height, and the zoom (1: the photo's short side fills the circle);
        /// nil: the middle at 1
        var photoFrame: [Double]? = nil
    }
    struct Home: Codable, Equatable {
        var id: String
        var name: String
        var cc: String
        var lat: Double
        var lon: Double
    }
    private(set) var me = Me()
    /// the uploaded photo, read once (the circle's square, 600 across)
    private(set) var photo: UIImage?
    /// the whole photo as it was picked (up to 1600 on its long side), so it can be moved and zoomed again; an older
    /// account's photo has only its square, which is then the whole photo
    private(set) var photoWhole: UIImage?
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
    private static var wholeURL: URL? { url?.deletingLastPathComponent().appendingPathComponent("profile-photo-whole.jpg") }
    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u), let m = try? JSONDecoder().decode(Me.self, from: d) { me = m }
        if me.picture == "photo", let p = Self.photoURL { photo = UIImage(contentsOfFile: p.path) }
        if me.picture == "photo", let p = Self.wholeURL { photoWhole = UIImage(contentsOfFile: p.path) }
    }
    static let nameMax = 30, handleMax = 20, bioMax = 120

    // THE HANDLE'S WINDOW (W06 #42: "editable as often as you like within a time window, twice every 14 days"; the
    // first handle is your name and is not a change)
    static let handleWindow: TimeInterval = 14 * 24 * 3600
    /// the day the handle can be changed again, or nil when it can be now
    var handleFreeFrom: Date? {
        let now = Date().timeIntervalSince1970
        let recent = (me.handleChanges ?? []).filter { now - $0 < Self.handleWindow }.sorted()
        guard recent.count >= 2 else { return nil }
        return Date(timeIntervalSince1970: recent[recent.count - 2] + Self.handleWindow)
    }
    /// a handle typing ended: a change from what it was counts, once
    func handleEdited(from old: String) {
        guard me.handle != old, !old.isEmpty || !me.handle.isEmpty else { return }
        set { $0.handleChanges = (($0.handleChanges ?? []) + [Date().timeIntervalSince1970]).suffix(4).map { $0 } }
    }
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
        if let p = Self.wholeURL { try? FileManager.default.removeItem(at: p) }
        photo = nil; photoWhole = nil
        if me.picture == "photo" { set { $0.picture = nil } }
    }
    /// A PHOTO UPLOADED: kept whole (1600 on its long side at most), its middle square, 600 pixels across, the picture
    func setPhoto(_ data: Data) async {
        guard let whole = await Task.detached(priority: .userInitiated, operation: { () -> (UIImage, Data)? in
            guard let img = UIImage(data: data) else { return nil }
            let long = max(img.size.width, img.size.height) * img.scale
            let k = min(1, 1600 / long)
            let size = CGSize(width: (img.size.width * img.scale * k).rounded(), height: (img.size.height * img.scale * k).rounded())
            let f = UIGraphicsImageRendererFormat(); f.scale = 1
            let out = UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            guard let jpg = out.jpegData(compressionQuality: 0.85) else { return nil }
            return (out, jpg)
        }).value, let w = Self.wholeURL else { Feel.refuse(); return }
        try? FileManager.default.createDirectory(at: w.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? whole.1.write(to: w, options: .atomic)
        photoWhole = whole.0
        await framePhoto([0.5, 0.5, 1], picture: true)
    }

    /// the circle's middle on the whole photo kept inside it: the square never shows past the photo's edges
    nonisolated static func clamped(_ f: [Double], size: CGSize) -> [Double] {
        guard f.count == 3, size.width > 0, size.height > 0 else { return [0.5, 0.5, 1] }
        let z = min(4, max(1, f[2]))
        let side = min(size.width, size.height) / z
        let hx = side / 2 / size.width, hy = side / 2 / size.height
        return [min(1 - hx, max(hx, f[0])), min(1 - hy, max(hy, f[1])), z]
    }

    /// THE PHOTO MOVED OR ZOOMED: its square cut again from the whole photo and kept
    func framePhoto(_ frame: [Double], picture: Bool = false) async {
        // (an older account's photo is only its square: that square is kept as the whole, so moving it again never
        // cuts a square out of a square)
        if photoWhole == nil, let sq = photo, let w = Self.wholeURL, let d = sq.jpegData(compressionQuality: 0.9) {
            try? d.write(to: w, options: .atomic); photoWhole = sq
        }
        guard let src = photoWhole, let p = Self.photoURL else { Feel.refuse(); return }
        let f = Self.clamped(frame, size: src.size)
        guard let made = await Task.detached(priority: .userInitiated, operation: { () -> (UIImage, Data)? in
            let w = src.size.width, h = src.size.height
            let s = min(w, h) / f[2]
            let side: CGFloat = min(600, s * src.scale)
            let fm = UIGraphicsImageRendererFormat(); fm.scale = 1
            let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fm).image { _ in
                let k = side / s
                src.draw(in: CGRect(x: -(f[0] * w - s / 2) * k, y: -(f[1] * h - s / 2) * k, width: w * k, height: h * k))
            }
            guard let jpg = out.jpegData(compressionQuality: 0.85) else { return nil }
            return (out, jpg)
        }).value else { Feel.refuse(); return }
        try? FileManager.default.createDirectory(at: p.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? made.1.write(to: p, options: .atomic)) != nil else { Feel.refuse(); return }
        photo = made.0
        set { $0.photoFrame = f; if picture { $0.picture = "photo" } }
    }
}

import SwiftUI
import UIKit

/// TEST ONLY, simulator builds only: writes what is on screen into the night folder 4 times a second (latest.jpg and
/// a ring of the last 40 frames, r00…r39), so the real running page can be checked frame by frame. Only the newest
/// app started writes (it claims snaps/owner.txt; an older one still running on another simulator stops). Never in
/// a phone build.
enum Snap {
    /// the test folder on the Mac the simulator runs on: WYA_SNAPS if set, else "Claude outputs/night-2026-10-22/snaps" in
    /// the project's parent folder, found from where this file was compiled (no one's home folder written in the code)
    static let dir: String = {
        if let d = ProcessInfo.processInfo.environment["WYA_SNAPS"], !d.isEmpty { return d }
        let src = URL(fileURLWithPath: #filePath)   // …/<parent>/<project>/wya/Design/Snap.swift
        let parent = src.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return parent.appendingPathComponent("Claude outputs/night-2026-10-22/snaps").path
    }()
    static let me = UUID().uuidString
    /// grabs are taken until this time (set by each test command)
    nonisolated(unsafe) static var activeUntil: CFTimeInterval = 0
    /// another copy of the app has taken the test files over; a moment when the file can't be read (iCloud busy with
    /// it) is not that: grabs stopped for good on such a moment, which looked like the app freezing
    static var isOwner: Bool {
        guard let o = try? String(contentsOfFile: dir + "/owner.txt", encoding: .utf8) else { return true }
        return o == me
    }

    static func start() {
        #if targetEnvironment(simulator) && DEBUG
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? me.write(toFile: dir + "/owner.txt", atomically: true, encoding: .utf8)
        NSLog("wya snap owner %@", me)
        let t0 = Date()
        let queue = DispatchQueue(label: "snap", qos: .utility)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard isOwner else { return }
                // ONLY WHILE I'M TESTING: a grab only in the 20 s after a test command, never while the app is just
                // being used
                guard CACurrentMediaTime() < activeUntil else { return }
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows).filter { !$0.isHidden && $0.alpha > 0 }
                    .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
                guard let base = windows.first else { return }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.5
                let img = UIGraphicsImageRenderer(bounds: base.bounds, format: format).image { _ in
                    for w in windows { w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) }
                }
                queue.async {
                    guard let data = img.jpegData(compressionQuality: 0.85) else { return }
                    let url = URL(fileURLWithPath: dir)
                    try? data.write(to: url.appendingPathComponent("latest.jpg"))
                    try? data.write(to: url.appendingPathComponent(String(format: "r%02d.jpg", (ms / 250) % 40)))
                }
            }
        }
        #endif
    }

    /// FRAME BY FRAME: every screen refresh for `ms` milliseconds, written as b000.jpg, b001.jpg … with the time of
    /// each in burst.txt, so an animation can be stepped through as it really ran (each grab costs time, so the frames
    /// come as fast as the simulator allows)
    @MainActor static func burst(ms: Int) {
        #if targetEnvironment(simulator) && DEBUG
        let t0 = CACurrentMediaTime()
        let queue = DispatchQueue(label: "burst", qos: .userInitiated)
        var n = 0
        var times: [String] = []
        let link = BurstLink { link in
            let t = CACurrentMediaTime() - t0
            if t * 1000 > Double(ms) || n >= 240 {
                link.stop()
                let log = times.joined(separator: "\n")
                queue.async { try? log.write(toFile: dir + "/burst.txt", atomically: true, encoding: .utf8) }
                return
            }
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).filter { !$0.isHidden && $0.alpha > 0 }
                .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
            guard let base = windows.first else { return }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let img = UIGraphicsImageRenderer(bounds: base.bounds, format: format).image { _ in
                for w in windows { w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) }
            }
            let i = n
            n += 1
            times.append(String(format: "b%03d %.0f ms", i, t * 1000))
            queue.async {
                if let data = img.jpegData(compressionQuality: 0.8) {
                    try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "b%03d.jpg", i)))
                }
            }
        }
        link.start()
        #endif
    }
}

/// THE HITCH COUNTER (test only): every frame's time since the last, and every 2 s the frames that came late (over
/// 1.5 times the screen's frame) and the longest gap, so lag shows as numbers in the log
@MainActor
enum Hitches {
    private static var link: BurstLink?
    private static var last: CFTimeInterval = 0, at: CFTimeInterval = 0, n = 0, late = 0, worst = 0.0
    static func start() {
        #if targetEnvironment(simulator) && DEBUG
        let l = BurstLink { _ in
            let t = CACurrentMediaTime()
            if last > 0 {
                let d = t - last
                n += 1
                if d > 1.5 / 60 { late += 1 }
                worst = max(worst, d)
            }
            last = t
            if at == 0 { at = t }
            if t - at > 2 {
                if late > 0 { NSLog("wya hitch %d of %d frames late, longest %.0f ms", late, n, worst * 1000) }
                at = t; n = 0; late = 0; worst = 0
            }
        }
        l.start()
        link = l
        #endif
    }
}

/// a display link that calls back on every frame until stopped (test only)
@MainActor
final class BurstLink: NSObject {
    private var link: CADisplayLink?
    private let tick: @MainActor (BurstLink) -> Void
    init(_ tick: @escaping @MainActor (BurstLink) -> Void) { self.tick = tick }
    func start() {
        let l = CADisplayLink(target: self, selector: #selector(fire))
        l.add(to: .main, forMode: .common)
        link = l
        BurstLink.alive.insert(self)
    }
    func stop() { link?.invalidate(); link = nil; BurstLink.alive.remove(self) }
    @objc private func fire() { tick(self) }
    static var alive: Set<BurstLink> = []
}

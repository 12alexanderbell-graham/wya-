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
        // (31 Oct 05:05: a folder iCloud leaves alone; the grabs written four times a second into the synced `snaps`
        // folder kept iCloud busy and the Mac slow, and the commands were sometimes read half written)
        return parent.appendingPathComponent("Claude outputs/night-2026-10-22/snaps.nosync").path
    }()
    static let me = UUID().uuidString
    /// grabs are taken until this time (set by each test command)
    nonisolated(unsafe) static var activeUntil: CFTimeInterval = 0
    /// a grab is still being written (main thread only)
    nonisolated(unsafe) static var writing = false
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
        // (31 Oct 06:10: at .utility the writes were starved while the Mac was busy and queued up behind each other,
        // so latest.jpg showed the screen of minutes before; now a grab is skipped while the last one is still being
        // written, and the writing runs at a level the system doesn't hold back)
        let queue = DispatchQueue(label: "snap", qos: .userInitiated)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard isOwner else { return }
                // ONLY WHILE I'M TESTING: a grab only in the 20 s after a test command, never while the app is just
                // being used
                guard CACurrentMediaTime() < activeUntil else { return }
                // never while frames are being measured (each grab is itself a late frame: the first Step 1c tables
                // counted the grabs, about 10 of the late frames in each 120)
                guard !FrameStats.on, !writing else { return }
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
                writing = true
                queue.async {
                    defer { DispatchQueue.main.async { writing = false } }
                    guard let data = img.jpegData(compressionQuality: 0.85) else { return }
                    let url = URL(fileURLWithPath: dir)
                    try? data.write(to: url.appendingPathComponent("latest.jpg"), options: .atomic)
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
                if FrameStats.on { FrameStats.gaps.append(d) }
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

/// THE FRAME-TIME CHECK (Step 1c; Part 19.7): while on, every frame's gap and the map's CPU and GPU time are kept;
/// "measure off <scene>" logs p50, p95, worst and the late frames (a gap over 1.5 frames), the numbers the book's
/// pass rule is written in (p95 under 8 ms and no more than 2 late frames in 120)
@MainActor
enum FrameStats {
    static var on = false
    static var gaps: [Double] = [], cpu: [Double] = [], gpu: [Double] = [], main: [Double] = []
    /// the main thread's busy time per run-loop turn (woken to asleep): our own work per frame, apart from what the
    /// render server (and on the simulator, the Mac drawing the glass) takes
    nonisolated(unsafe) private static var observer: CFRunLoopObserver?
    nonisolated(unsafe) private static var woke: CFTimeInterval = 0
    /// the main thread's own CPU time (not wall time: the simulator shares the Mac, whose other work lengthens wall
    /// time but not this)
    nonisolated static func cpuNow() -> CFTimeInterval {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return CFTimeInterval(ts.tv_sec) + CFTimeInterval(ts.tv_nsec) / 1e9
    }
    /// each result also goes on the end of snaps/measure.log, so a run can be read without the console
    static func log(_ s: String) {
        NSLog("%@", s)
        let url = URL(fileURLWithPath: Snap.dir).appendingPathComponent("measure.log")
        let line = Data((s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() } else { try? line.write(to: url) }
    }
    static func start() {
        gaps = []; cpu = []; gpu = []; main = []; on = true
        if observer == nil {
            let o = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, act in
                let t = cpuNow()
                if act == .afterWaiting { woke = t } else if woke > 0 {
                    let d = t - woke
                    MainActor.assumeIsolated { if FrameStats.on { FrameStats.main.append(d) } }
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
            observer = o
        }
    }
    static func stop(_ scene: String) {
        on = false
        func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a.sorted()[min(a.count - 1, Int(Double(a.count) * p))] * 1000 }
        let frame = gaps.isEmpty ? 1.0 / 60 : gaps.sorted()[gaps.count / 2]
        let late = gaps.filter { $0 > 1.5 * frame }.count
        log(String(format: "wya measure %@: %d frames at %.0f Hz; gap p50 %.1f p95 %.1f worst %.1f ms, late %d (%.1f in 120); map cpu p50 %.2f p95 %.2f worst %.2f ms; map gpu p50 %.2f p95 %.2f worst %.2f ms",
              scene, gaps.count, 1 / frame, pct(gaps, 0.5), pct(gaps, 0.95), (gaps.max() ?? 0) * 1000, late,
              gaps.isEmpty ? 0 : Double(late) * 120 / Double(gaps.count),
              pct(cpu, 0.5), pct(cpu, 0.95), (cpu.max() ?? 0) * 1000, pct(gpu, 0.5), pct(gpu, 0.95), (gpu.max() ?? 0) * 1000))
        log(String(format: "wya measure %@ main thread CPU per turn: p50 %.2f p95 %.2f worst %.1f ms, %d turns over 8 ms, total %.0f ms", scene,
              pct(main, 0.5), pct(main, 0.95), (main.max() ?? 0) * 1000, main.filter { $0 > 0.008 }.count, main.reduce(0, +) * 1000))
    }
}

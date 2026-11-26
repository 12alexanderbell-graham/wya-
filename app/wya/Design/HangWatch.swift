import Foundation
import Darwin
import UIKit

/// TEST ONLY, simulator builds only: when the main thread has not come round for 3 seconds, its stack is written to
/// the console (a signal sent to it, whose handler prints where it is), so a hang seen in a sweep says where it sits.
/// Never in a phone build.
enum HangWatch {
    #if targetEnvironment(simulator) && DEBUG
    nonisolated(unsafe) private static var main: pthread_t?
    nonisolated(unsafe) private static var beat = CFAbsoluteTimeGetCurrent()
    nonisolated(unsafe) private static var told = false
    /// the stack's room, made once here: the signal's handler may allocate nothing (26 Nov 03:03 the app was paused from
    /// outside and resumed; the handler's own array asked the runtime for its type while the main thread held the
    /// runtime's lock, and the app aborted on a recursive lock)
    nonisolated(unsafe) private static let frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 80)
    #endif

    @MainActor static func start() {
        #if targetEnvironment(simulator) && DEBUG
        main = pthread_self()
        // (and when the app leaves the front: a process that stops whole, with no HANG line, was put away by the system)
        for (n, w) in [(UIApplication.willResignActiveNotification, "inactive"), (UIApplication.didEnterBackgroundNotification, "background"),
                       (UIApplication.didBecomeActiveNotification, "active")] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in NSLog("wya app %@", w) }
        }
        _ = frames
        signal(SIGUSR2) { _ in
            let n = backtrace(HangWatch.frames, 80)
            let head: StaticString = "wya HANG main thread stack:\n"
            _ = write(2, head.utf8Start, head.utf8CodeUnitCount)
            backtrace_symbols_fd(HangWatch.frames, n, 2)
        }
        // (in every run loop mode: in the default one alone it stopped while a finger scrolled, and each scroll read as
        // the main thread a second late, 26 Nov)
        RunLoop.main.add(Timer(timeInterval: 0.25, repeats: true) { _ in beat = CFAbsoluteTimeGetCurrent() }, forMode: .common)
        let t = Thread {
            NSLog("wya hangwatch on")
            var k = 0
            var woke = CFAbsoluteTimeGetCurrent()
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                k += 1
                // (a half-second sleep that took far longer: the whole app was paused from outside, this thread too,
                // and the main thread is not late, only the clock moved; start counting again)
                let now = CFAbsoluteTimeGetCurrent()
                if now - woke > 2 { beat = now; told = false; NSLog("wya hangwatch: the app was paused %.1f s", now - woke) }
                woke = now
                // every 5 s: still here (no file read here: a read that hangs would stop this too)
                if k % 10 == 0 { NSLog("wya alive, main %.1f s ago", CFAbsoluteTimeGetCurrent() - beat) }
                let late = CFAbsoluteTimeGetCurrent() - beat
                if late > 3, !told, let m = main {
                    told = true
                    let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()).map { $0.rawValue as String } ?? "none"
                    NSLog("wya HANG main has not come round for %.1f s, its run loop in %@", late, mode)
                    pthread_kill(m, SIGUSR2)
                    // a second look a little later, in case the first caught it on the way through
                    Thread.sleep(forTimeInterval: 1.5)
                    if CFAbsoluteTimeGetCurrent() - beat > 4 { pthread_kill(m, SIGUSR2) }
                } else if late < 1 {
                    told = false
                }
            }
        }
        t.start()
        #endif
    }
}

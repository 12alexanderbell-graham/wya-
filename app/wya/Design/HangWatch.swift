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
    #endif

    @MainActor static func start() {
        #if targetEnvironment(simulator) && DEBUG
        main = pthread_self()
        // (and when the app leaves the front: a process that stops whole, with no HANG line, was put away by the system)
        for (n, w) in [(UIApplication.willResignActiveNotification, "inactive"), (UIApplication.didEnterBackgroundNotification, "background"),
                       (UIApplication.didBecomeActiveNotification, "active")] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in NSLog("wya app %@", w) }
        }
        signal(SIGUSR2) { _ in
            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 80)
            let n = backtrace(&frames, 80)
            let head = "wya HANG main thread stack:\n"
            _ = head.withCString { write(2, $0, strlen($0)) }
            backtrace_symbols_fd(&frames, n, 2)
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in beat = CFAbsoluteTimeGetCurrent() }
        let t = Thread {
            NSLog("wya hangwatch on")
            var k = 0
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                k += 1
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

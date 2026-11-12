import Foundation
import Darwin

/// THE MAIN-THREAD SAMPLER (test only, simulator builds only): "sample on" starts a thread that stops the main thread
/// every 2 ms, reads its program counter and walks its frame pointers, and lets it go again; "sample off <name>" names
/// the functions, and logs the ones the main thread was in most (inclusive, and where it was itself), so a slow
/// animation says which code costs it. No signals: the debugger sees none of it.
enum Sampler {
    /// sampling now (the screen grabs wait, as they do while frames are measured)
    @MainActor static var on: Bool {
        #if targetEnvironment(simulator) && DEBUG && arch(arm64)
        running
        #else
        false
        #endif
    }
    #if targetEnvironment(simulator) && DEBUG && arch(arm64)
    nonisolated(unsafe) private static var running = false
    nonisolated(unsafe) private static var stacks: [[UInt]] = []
    nonisolated(unsafe) private static var main: pthread_t?
    #endif

    @MainActor static func start() {
        #if targetEnvironment(simulator) && DEBUG && arch(arm64)
        guard !running else { return }
        main = pthread_self()
        stacks = []
        running = true
        let t = Thread {
            guard let m = main else { return }
            let port = pthread_mach_thread_np(m)
            let lo = UInt(bitPattern: pthread_get_stackaddr_np(m)) - UInt(pthread_get_stacksize_np(m))
            let hi = UInt(bitPattern: pthread_get_stackaddr_np(m))
            var got: [[UInt]] = []
            while running {
                if thread_suspend(port) == KERN_SUCCESS {
                    var state = arm_thread_state64_t()
                    var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
                    let kr = withUnsafeMutablePointer(to: &state) {
                        $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { thread_get_state(port, ARM_THREAD_STATE64, $0, &count) }
                    }
                    var s: [UInt] = []
                    if kr == KERN_SUCCESS {
                        s.append(UInt(state.__pc))
                        s.append(UInt(state.__lr))
                        var fp = UInt(state.__fp)
                        var k = 0
                        while fp >= lo, fp + 16 <= hi, fp & 7 == 0, k < 120 {
                            let p = UnsafePointer<UInt>(bitPattern: fp)!
                            let next = p[0], ret = p[1]
                            if ret == 0 { break }
                            s.append(ret)
                            if next <= fp { break }
                            fp = next; k += 1
                        }
                    }
                    thread_resume(port)
                    if !s.isEmpty { got.append(s) }
                }
                usleep(2000)
            }
            stacks = got
        }
        t.stackSize = 1 << 20
        t.start()
        #endif
    }

    @MainActor static func stop(_ name: String) {
        #if targetEnvironment(simulator) && DEBUG && arch(arm64)
        guard running else { return }
        running = false
        // (the sampling thread leaves within a turn; read its stacks then)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let all = stacks
            var names: [UInt: String] = [:]
            func sym(_ a: UInt) -> String {
                if let n = names[a] { return n }
                var info = Dl_info()
                var out = "?"
                if dladdr(UnsafeRawPointer(bitPattern: a), &info) != 0, let s = info.dli_sname {
                    let raw = String(cString: s)
                    out = demangle(raw)
                    if out.count > 140 { out = String(out.prefix(140)) }
                }
                names[a] = out
                return out
            }
            // the samples where the main thread was asleep (waiting for the next event) are left out
            let idle = ["mach_msg2_trap", "mach_msg_trap", "__CFRunLoopServiceMachPort", "semaphore_wait_trap"]
            var busy = 0
            var incl: [String: Int] = [:], leaf: [String: Int] = [:]
            for s in all {
                let syms = s.map(sym)
                if let first = syms.first, idle.contains(where: { first.contains($0) }) { continue }
                busy += 1
                leaf[syms.first ?? "?", default: 0] += 1
                for n in Set(syms) { incl[n, default: 0] += 1 }
            }
            var lines = ["wya sample \(name): \(all.count) samples, \(busy) busy (about \(busy * 2) ms of main thread work)"]
            lines.append("wya sample \(name) inclusive:")
            for (n, c) in incl.sorted(by: { $0.value > $1.value }).prefix(60) { lines.append(String(format: "  %4d %5.1f%%  %@", c, 100.0 * Double(c) / Double(max(1, busy)), n)) }
            // the app's own functions, inclusive: which of our views and models the time goes through
            lines.append("wya sample \(name) ours:")
            for (n, c) in incl.filter({ $0.key.contains("wya.") }).sorted(by: { $0.value > $1.value }).prefix(40) { lines.append(String(format: "  %4d %5.1f%%  %@", c, 100.0 * Double(c) / Double(max(1, busy)), n)) }
            lines.append("wya sample \(name) itself:")
            for (n, c) in leaf.sorted(by: { $0.value > $1.value }).prefix(25) { lines.append(String(format: "  %4d %5.1f%%  %@", c, 100.0 * Double(c) / Double(max(1, busy)), n)) }
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async { FrameStats.log(text) }
        }
        #endif
    }

    #if targetEnvironment(simulator) && DEBUG && arch(arm64)
    @_silgen_name("swift_demangle")
    private static func swift_demangle(_ mangled: UnsafePointer<CChar>?, _ length: Int, _ out: UnsafeMutablePointer<CChar>?, _ outLength: UnsafeMutablePointer<Int>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

    private static func demangle(_ s: String) -> String {
        guard s.hasPrefix("$s") || s.hasPrefix("_$s") else { return s }
        return s.withCString { p in
            guard let d = swift_demangle(p, strlen(p), nil, nil, 0) else { return s }
            defer { free(d) }
            return String(cString: d)
        }
    }
    #endif
}

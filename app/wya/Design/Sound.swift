import AVFoundation

/// THE APP'S SOUNDS. Tiny, quiet sounds made in code, played with the haptics: a soft tap for a button, a click for
/// each step of the mode wheel and the moon, a low settle when water lands. The session is "ambient", so the
/// ring/silent switch silences them and they never stop his music.
@MainActor
enum Sound {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var ready = false
    private static let rate: Double = 44_100
    private static var buffers: [String: AVAudioPCMBuffer] = [:]

    static func tap() { play("tap") }
    static func tick() { play("tick") }
    static func click() { play("click") }
    static func land(_ strength: CGFloat) { if strength > 0.15 { play("land", volume: Float(0.3 + 0.5 * min(1, strength))) } }
    /// a stamp landing: a 2,400 Hz click over a 120 Hz thud (Part 0.3, proposal)
    static func stamp() { play("stamp") }
    /// a stamp or wish removed: the stamp's sound backwards (proposal)
    static func lift() { play("lift") }
    /// a page turn committing: 40 ms of soft paper (proposal)
    static func page() { play("page", volume: 0.6) }

    /// Settings > Sounds (default on; the row comes with the Settings page)
    static let settingKey = "sounds"
    static var on: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    // MARK: FLOW: a soft, quiet, continuous sound under pans, pinches, glides, flights and the water's drag: silent at
    // rest, its volume and pitch rising with the speed and capped low. Each mover reports its speed every frame it
    // moves; the loudest wins; one not heard from for 0.1 s counts as still.
    private static let flowPlayer = AVAudioPlayerNode()
    private static let flowPitch = AVAudioUnitVarispeed()
    private static var flowLevels: [String: (speed: CGFloat, at: CFTimeInterval)] = [:]
    private static var flowTimer: Timer?
    /// the flow's volume as heard: it follows the speed's volume with a 60 ms rise and a 180 ms fall, so a frame
    /// without movement inside a gesture never cuts it (it would click on and off)
    private static var flowVolume: Float = 0
    private static var flowApplied: CFTimeInterval = 0
    /// `speed` in points a second on the screen
    static func flow(_ source: String, speed: CGFloat) {
        guard on else { return }
        setUp()
        guard ready else { return }
        flowLevels[source] = (speed, CACurrentMediaTime())
        if flowTimer == nil {
            flowApplied = CACurrentMediaTime()
            flowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
                MainActor.assumeIsolated { applyFlow() }
            }
        }
    }
    private static func applyFlow() {
        let now = CACurrentMediaTime()
        let dt = Float(max(0, now - flowApplied))
        flowApplied = now
        flowLevels = flowLevels.filter { now - $0.value.at < 0.12 }
        let s = flowLevels.values.map(\.speed).max() ?? 0
        let v = min(1, s / 2500)
        let target = v > 0.004 ? Float(0.22 * pow(v, 0.7)) : 0
        let tau: Float = target > flowVolume ? 0.06 : 0.18
        flowVolume += (target - flowVolume) * (1 - exp(-dt / tau))
        if target == 0 && flowVolume < 0.01 {
            flowVolume = 0
            flowPlayer.volume = 0
            if flowPlayer.isPlaying {
                flowPlayer.pause()
                #if DEBUG
                NSLog("wya sound flow off")
                #endif
            }
            flowTimer?.invalidate(); flowTimer = nil
            return
        }
        if !engine.isRunning { try? engine.start() }
        flowPlayer.volume = flowVolume
        if v > 0.004 { flowPitch.rate = Float(0.85 + 0.35 * v) }
        if !flowPlayer.isPlaying {
            flowPlayer.play()
            #if DEBUG
            NSLog("wya sound flow on (%@ %.0f pt/s)", flowLevels.max { $0.value.speed < $1.value.speed }?.key ?? "", Double(s))
            #endif
        }
    }

    private static func setUp() {
        guard !ready else { return }
        ready = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.attach(flowPlayer)
        engine.attach(flowPitch)
        engine.connect(flowPlayer, to: flowPitch, format: format)
        engine.connect(flowPitch, to: engine.mainMixerNode, format: format)
        flowPlayer.volume = 0
        engine.mainMixerNode.outputVolume = 0.35
        // a tap: a short, high, soft knock; a tick: shorter and drier; a click: the wheel's notch; land: a low thud
        buffers["tap"] = tone(format, freq: 1900, length: 0.018, decay: 260, noise: 0.15)
        buffers["tick"] = tone(format, freq: 3200, length: 0.008, decay: 600, noise: 0.25)
        buffers["click"] = tone(format, freq: 2400, length: 0.012, decay: 420, noise: 0.35)
        buffers["land"] = tone(format, freq: 140, length: 0.06, decay: 70, noise: 0.05)
        let click = tone(format, freq: 2400, length: 0.012, decay: 420, noise: 0.35)
        let thud = tone(format, freq: 120, length: 0.04, decay: 90, noise: 0.05)
        let stamp = mix(format, [click, thud])
        buffers["stamp"] = stamp
        buffers["lift"] = reversed(format, stamp)
        buffers["page"] = paper(format, length: 0.04)
        do { try engine.start() } catch { ready = false }
        if ready {
            // the flow's bed: one second of soft low noise, looped, its volume 0 until something moves
            flowPlayer.scheduleBuffer(rumble(format, length: 1), at: nil, options: .loops)
        }
    }

    private static func play(_ name: String, volume: Float = 1) {
        guard on else { return }
        #if DEBUG
        NSLog("wya sound %@", name)
        #endif
        setUp()
        guard ready, let b = buffers[name] else { return }
        if !engine.isRunning { try? engine.start() }
        player.volume = volume
        player.scheduleBuffer(b, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// sounds laid over each other, as long as the longest
    private static func mix(_ f: AVAudioFormat, _ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer {
        let n = parts.map(\.frameLength).max() ?? 0
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n)!
        b.frameLength = n
        let p = b.floatChannelData![0]
        for i in 0 ..< Int(n) { p[i] = 0 }
        for q in parts { let s = q.floatChannelData![0]; for i in 0 ..< Int(q.frameLength) { p[i] += s[i] * 0.6 } }
        return b
    }
    private static func reversed(_ f: AVAudioFormat, _ a: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let n = a.frameLength
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n)!
        b.frameLength = n
        let s = a.floatChannelData![0], p = b.floatChannelData![0]
        for i in 0 ..< Int(n) { p[i] = s[Int(n) - 1 - i] }
        return b
    }
    /// a soft paper sound: noise, smoothed, rising and falling over its length
    private static func paper(_ f: AVAudioFormat, length: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(length * rate)
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n)!
        b.frameLength = n
        let p = b.floatChannelData![0]
        var seed: UInt32 = 777, y: Double = 0
        for i in 0 ..< Int(n) {
            seed = seed &* 1664525 &+ 1013904223
            let r = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            y += (r - y) * 0.35
            let x = Double(i) / Double(n)
            p[i] = Float(y * sin(.pi * x) * 0.8)
        }
        return b
    }
    /// the flow's bed: low noise (twice smoothed), looping cleanly (its ends faded into each other)
    private static func rumble(_ f: AVAudioFormat, length: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(length * rate)
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n)!
        b.frameLength = n
        let p = b.floatChannelData![0]
        var seed: UInt32 = 4242, y1: Double = 0, y2: Double = 0
        for i in 0 ..< Int(n) {
            seed = seed &* 1664525 &+ 1013904223
            let r = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            y1 += (r - y1) * 0.04; y2 += (y1 - y2) * 0.04
            p[i] = Float(y2 * 6)
        }
        // crossfade the last 50 ms into the start so the loop has no click
        let fade = Int(0.05 * rate)
        for i in 0 ..< fade {
            let t = Float(i) / Float(fade)
            p[i] = p[i] * t + p[Int(n) - fade + i] * (1 - t)
        }
        return b
    }

    private static func tone(_ f: AVAudioFormat, freq: Double, length: Double, decay: Double, noise: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(length * rate)
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n)!
        b.frameLength = n
        let p = b.floatChannelData![0]
        var seed: UInt32 = 12345
        for i in 0 ..< Int(n) {
            let t = Double(i) / rate
            seed = seed &* 1664525 &+ 1013904223
            let r = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            let env = exp(-t * decay) * min(1, t * 4000)
            p[i] = Float((sin(2 * .pi * freq * t) * (1 - noise) + r * noise) * env)
        }
        return b
    }
}

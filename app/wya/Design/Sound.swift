import AVFoundation

/// THE APP'S SOUNDS. Tiny, quiet sounds made in code, played with the haptics: a soft tap for a button, a click for
/// each step of the mode wheel and the moon, a low settle when water lands. The session is "ambient", so the
/// ring/silent switch silences them and they never stop the person's music.
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

    private static func setUp() {
        guard !ready else { return }
        ready = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.35
        // a tap: a short, high, soft knock; a tick: shorter and drier; a click: the wheel's notch; land: a low thud
        buffers["tap"] = tone(format, freq: 1900, length: 0.018, decay: 260, noise: 0.15)
        buffers["tick"] = tone(format, freq: 3200, length: 0.008, decay: 600, noise: 0.25)
        buffers["click"] = tone(format, freq: 2400, length: 0.012, decay: 420, noise: 0.35)
        buffers["land"] = tone(format, freq: 140, length: 0.06, decay: 70, noise: 0.05)
        do { try engine.start() } catch { ready = false }
    }

    private static func play(_ name: String, volume: Float = 1) {
        setUp()
        guard ready, let b = buffers[name] else { return }
        if !engine.isRunning { try? engine.start() }
        player.volume = volume
        player.scheduleBuffer(b, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
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

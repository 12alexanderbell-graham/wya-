import AVFoundation

@MainActor
enum Sound {
    enum Name: String { case stamp, page, close }
    private static var players: [Name: AVAudioPlayer] = [:]
    private static var ready = false

    /// made once (the session set to ambient, both sounds loaded and primed): called as a card or the passport opens,
    /// so the first stamp sounds on its contact and not a quarter of a second after it
    static func prepare() {
        guard !ready else { return }
        ready = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for n in [Name.stamp, .page, .close] {
            guard let url = Bundle.main.url(forResource: n.rawValue, withExtension: "caf"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.prepareToPlay()
            players[n] = p
        }
    }

    static func play(_ n: Name, volume: Float = 1) {
        prepare()
        guard let p = players[n] else { return }
        p.volume = volume
        p.currentTime = 0
        p.play()
        #if DEBUG
        NSLog("wya sound %@", n.rawValue)
        #endif
    }
}

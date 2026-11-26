import AVFoundation

@MainActor
enum Sound {
    nonisolated enum Name: String, Sendable { case stamp, page, close }
    private static var players: [Name: AVAudioPlayer] = [:]
    private static var ready = false
    private static var loading = false

    /// made once (the session set to ambient, the sounds loaded and primed), off the main thread: the app starts it a few
    /// seconds after it opens, and a card or the passport asks again as it opens, so the first stamp sounds on its
    /// contact (made on the main thread as the first card opened, it held that card's first frames 80 ms, 26 Nov)
    static func prepare() {
        guard !ready, !loading else { return }
        loading = true
        Task.detached(priority: .utility) {
            let made = Self.make()
            await MainActor.run {
                if !ready { players = made.all; ready = true }
                loading = false
            }
        }
    }
    /// (a sound wanted before the background set-up has finished: made here, as before)
    private static func prepareNow() {
        guard !ready else { return }
        players = make().all
        ready = true
    }
    nonisolated private static func make() -> Made {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let out = Made()
        for n in [Name.stamp, .page, .close] {
            guard let url = Bundle.main.url(forResource: n.rawValue, withExtension: "caf"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.prepareToPlay()
            out.all[n] = p
        }
        return out
    }
    /// the players as made, handed from the background to the main thread once (never touched by both)
    private final class Made: @unchecked Sendable { var all: [Name: AVAudioPlayer] = [:] }

    static func play(_ n: Name, volume: Float = 1) {
        prepareNow()
        guard let p = players[n] else { return }
        p.volume = volume
        p.currentTime = 0
        p.play()
        #if DEBUG
        NSLog("wya sound %@", n.rawValue)
        #endif
    }
}

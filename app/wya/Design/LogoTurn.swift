import SwiftUI
import AVFoundation
import UIKit
import VideoToolbox

/// THE LOGO TURNING, FOR THE LOADING SCREEN, OFF THE MAIN THREAD. The map's loading keeps the main thread busy for up
/// to a quarter of a second at a time, so a logo drawn there each frame stops. Here the logo is drawn once per frame of
/// one turn, ahead of time, into a short film with a see-through ground (Resources/Launch/logo-turn.mov, made by
/// `ReviewSheet.logoTurnMovie`), and the system plays it on a loop: the video hardware draws it, so nothing the app
/// does can make it stutter. Until the film's first frame is up, the same first frame stands still in its place (the
/// launch picture's), so nothing jumps.
struct LogoTurnView: UIViewRepresentable {
    /// called once, when the film starts moving (the page's light starts turning with it)
    var started: () -> Void = {}
    func makeUIView(context: Context) -> LogoTurnUIView {
        let v = LogoTurnUIView()
        v.started = started
        return v
    }
    func updateUIView(_ v: LogoTurnUIView, context: Context) {}
    static func dismantleUIView(_ v: LogoTurnUIView, coordinator: ()) { v.stop() }
}

final class LogoTurnUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var watch: NSKeyValueObservation?
    var started: () -> Void = {}

    static let url = Bundle.main.url(forResource: "logo-turn", withExtension: "mov")

    /// THE FILM MADE READY AT THE APP'S START (wyaApp.init, before any view): the player and its loop exist and the
    /// file is opened while the first views are built, so the film is up with the loading screen (12 Nov: it came 2.6 s
    /// after it, with the map's loading)
    nonisolated(unsafe) private static var warmed: (player: AVQueuePlayer, looper: AVPlayerLooper)?
    static func warm() {
        guard warmed == nil, let url = url else { return }
        let item = AVPlayerItem(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: ["playable", "tracks", "duration"])
        let p = AVQueuePlayer()
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false
        p.automaticallyWaitsToMinimizeStalling = false
        let looper = AVPlayerLooper(player: p, templateItem: item)
        warmed = (p, looper)
        // the turn starts now, with the app: the page's light goes round from this moment on its own thread, and the
        // film joins it at the same point of the turn once its decoder is up
        if GlassRender.filmStart == nil { GlassRender.filmStart = CACurrentMediaTime() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
        playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        Self.warm()
        guard let w = Self.warmed else { return }
        let p = w.player
        looper = w.looper
        playerLayer.player = p
        player = p
        // (playing from the start, and its start told to the page's light here, on the film's own thread: the main thread
        // is busy loading the map for up to 3 s, and waiting for it left the logo and its light standing still, 12 Nov)
        let slow = Motion.reduce
        let rate: Float = slow ? 0.5 : 1
        p.playImmediately(atRate: rate)
        watch = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
            guard l.isReadyForDisplay else { return }
            // (the film joins the turn where the light has got to: the same point of its 2.7 s, never from its start)
            if let s = GlassRender.filmStart, let p = l.player {
                let period = 2.7 * (slow ? 2 : 1)
                let at = (CACurrentMediaTime() - s).truncatingRemainder(dividingBy: period) / (slow ? 2 : 1)
                p.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                p.playImmediately(atRate: rate)
            }
            DispatchQueue.main.async {
                guard let self, self.player != nil else { return }
                #if DEBUG
                NSLog("wya logoturn: film up %.3f s after launch", CACurrentMediaTime() - Launch.startTime)
                #endif
                self.started()
                self.watch = nil
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        watch = nil
    }
}

#if DEBUG
extension ReviewSheet {
    /// MAKES THE FILM (driver `sheet logoturn`): the logo at every 1/60 s of one turn (Launch.turn), drawn by LogoMark at
    /// the loading screen's size at 3x, into snaps/logo-turn.mov (HEVC with a see-through ground)
    @MainActor static func logoTurnMovie() {
        let W = Launch.planet(440) * 1024 / 700
        let px = Int((W * 3 / 2).rounded()) * 2
        let n = Int((Launch.turn * 60).rounded())
        let out = URL(fileURLWithPath: Snap.dir + "/logo-turn.mov")
        try? FileManager.default.removeItem(at: out)
        guard let w = try? AVAssetWriter(outputURL: out, fileType: .mov) else { NSLog("wya logoturn: no writer"); return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: px, AVVideoHeightKey: px,
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.9,
                                              kVTCompressionPropertyKey_TargetQualityForAlpha as String: 0.9],
        ])
        input.expectsMediaDataInRealTime = false
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: px, kCVPixelBufferHeightKey as String: px])
        w.add(input)
        guard w.startWriting() else { NSLog("wya logoturn: %@", String(describing: w.error)); return }
        w.startSession(atSourceTime: .zero)
        for i in 0 ..< n {
            let phase = GlassRender.rest + 2 * .pi * Double(i) / Double(n)
            let r = ImageRenderer(content: LogoMark(phase: phase).frame(width: CGFloat(px) / 3, height: CGFloat(px) / 3))
            r.scale = 3
            guard let cg = r.cgImage, let pool = ad.pixelBufferPool else { continue }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: px, height: px, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            ad.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 60))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        w.finishWriting { done.signal() }
        done.wait()
        NSLog("wya logoturn %d frames %dpx -> %@ (%@)", n, px, out.path, String(describing: w.error))
    }
}
#endif

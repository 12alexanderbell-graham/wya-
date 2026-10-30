import SwiftUI
import UIKit

/// THE FIRST SEARCH WITHOUT A STALL: the first time any text field takes the keyboard, iOS sets up its whole text input
/// system on the main thread, which held the screen still for about half a second as search opened (measured: the
/// frames stopped for 520 ms after the field appeared). That setup is done once at launch instead, while the map is
/// still loading, with a field the user never sees and an empty keyboard (so nothing rises), then dropped.
@MainActor
enum Prewarm {
    private static var done = false
    static func textInput() {
        guard !done, let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first else { return }
        done = true
        let field = UITextField(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
        field.inputView = UIView()
        field.autocorrectionType = .no
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }
}

/// THE SPACE'S SHADERS MADE READY AT LAUNCH (Step 1c): the solar system is drawn as one GPU pass (a drawing group), and
/// the first time such a pass ran, setting its shaders up held the screen 550 ms, on the first move to full. So for
/// the first second and a half a speck of each (the planet, Saturn's ring, the sun, a star), 4 points across at 2%
/// strength behind the tab capsule, is drawn the same way, and then removed: too small and faint to be seen.
struct ShaderPrewarm: View {
    @State private var on = true
    var body: some View {
        ZStack {
            if on {
                ZStack {
                    PlanetBody(tex: "planet-earth", size: 2, spin: 0, light: SIMD3(0, 0, 1), ring: true, lights: true)
                    SunView(size: 2, time: 0, flare: 1, glow: 0, heat: 0.5, swell: 1)
                    Rectangle()
                        .frame(width: 2, height: 2)
                        .colorEffect(ShaderLibrary.starPlasma(.float2(2, 2), .float(1), .float(Float(PlasmaStars.disc)), .float(1.0)))
                }
                .frame(width: 4, height: 4)
                .clipped()
                .drawingGroup(opaque: false)
                .opacity(0.02)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            on = false
        }
    }
}

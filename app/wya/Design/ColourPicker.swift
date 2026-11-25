import SwiftUI
import UIKit
import simd

// THE COLOUR PICKER (Part 15): one system for every colour a person chooses (pins, drawings, routes, the profile's
// picture, letter and gradient). No presets anywhere: a field of every hue (across) and lightness (down) at the most
// colour Display P3 allows, a strength strip under it, then your last ten colours led by one suggested from what the
// thing already has. No hex, no numbers, no words; no lime ring round anything.

/// A colour as the picker holds it: where it sits on the field and the strip. Its P3 value is worked out from these.
struct ColourPick: Codable, Hashable, Sendable {
    /// 0 to 360
    var hue: Double
    /// OKLab lightness, 0.15 (deep) to 0.97 (pale)
    var light: Double
    /// 0 (the hue's grey) to 1 (the most P3 allows)
    var strength: Double

    static let lightTop = 0.97, lightBottom = 0.15

    /// the field's spot for it (0 to 1 each way: x across the hues, y down from pale to deep)
    var spot: CGPoint { CGPoint(x: hue / 360, y: (Self.lightTop - light) / (Self.lightTop - Self.lightBottom)) }
    static func at(_ p: CGPoint, strength: Double) -> ColourPick {
        let x = min(1, max(0, Double(p.x))), y = min(1, max(0, Double(p.y)))
        return ColourPick(hue: x * 360, light: lightTop - y * (lightTop - lightBottom), strength: strength)
    }

    /// gamma-encoded Display P3, 0 to 1
    var p3: SIMD3<Double> { OKLCH.p3(light: light, chroma: OKLCH.maxChroma(light: light, hue: hue) * strength, hue: hue) }
    var color: Color { let v = p3; return Color(.displayP3, red: v.x, green: v.y, blue: v.z) }
    var uiColor: UIColor { let v = p3; return UIColor(displayP3Red: v.x, green: v.y, blue: v.z, alpha: 1) }
    /// OKLab, for telling near-identical colours apart (15.4: within ΔE OK 0.02 is the same colour)
    var lab: SIMD3<Double> {
        let c = OKLCH.maxChroma(light: light, hue: hue) * strength, r = hue * .pi / 180
        return SIMD3(light, c * cos(r), c * sin(r))
    }
    func near(_ o: ColourPick) -> Bool { simd_distance(lab, o.lab) < 0.02 }
    /// two colours that read as the same swatch (two blacks, two pale greens): the recent row keeps one
    func alike(_ o: ColourPick) -> Bool { simd_distance(lab, o.lab) < 0.04 }
}

/// OKLCH to Display P3 (Björn Ottosson's OKLab; the sRGB-to-P3 matrix in linear light)
enum OKLCH {
    static func linearP3(light L: Double, chroma C: Double, hue h: Double) -> SIMD3<Double> {
        let r = h * .pi / 180
        let a = C * cos(r), b = C * sin(r)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let sr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let sg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let sb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return SIMD3(0.8224621 * sr + 0.1775380 * sg,
                     0.0331941 * sr + 0.9668058 * sg,
                     0.0170827 * sr + 0.0723974 * sg + 0.9105199 * sb)
    }
    static func encode(_ x: Double) -> Double {
        let v = min(1, max(0, x))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
    static func p3(light: Double, chroma: Double, hue: Double) -> SIMD3<Double> {
        let v = linearP3(light: light, chroma: chroma, hue: hue)
        return SIMD3(encode(v.x), encode(v.y), encode(v.z))
    }
    /// the most chroma Display P3 holds at this lightness and hue (by halving, 14 steps)
    static func maxChroma(light: Double, hue: Double) -> Double {
        var lo = 0.0, hi = 0.37
        for _ in 0 ..< 14 {
            let mid = (lo + hi) / 2
            let v = linearP3(light: light, chroma: mid, hue: hue)
            let e = 1e-4
            if v.x >= -e && v.y >= -e && v.z >= -e && v.x <= 1 + e && v.y <= 1 + e && v.z <= 1 + e { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// THE WHEEL as a picture in Display P3: hues round it (red at the top, clockwise), the hue's grey in the middle
    /// out to the most colour P3 holds at the edge, all at one lightness
    static func wheel(size n: Int, light: Double) -> CGImage? {
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let r = Double(n) / 2
        for j in 0 ..< n {
            for i in 0 ..< n {
                let dx = Double(i) + 0.5 - r, dy = Double(j) + 0.5 - r
                let d = (dx * dx + dy * dy).squareRoot() / r
                guard d <= 1.01 else { continue }
                var hue = atan2(dx, -dy) * 180 / .pi
                if hue < 0 { hue += 360 }
                let v = p3(light: light, chroma: maxChroma(light: light, hue: hue) * min(1, d), hue: hue)
                let o = (j * n + i) * 4
                px[o] = UInt8(v.x * 255 + 0.5); px[o + 1] = UInt8(v.y * 255 + 0.5); px[o + 2] = UInt8(v.z * 255 + 0.5); px[o + 3] = 255
            }
        }
        guard let cs = CGColorSpace(name: CGColorSpace.displayP3),
              let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// the field as a picture in Display P3: hues across, pale to deep down, at this strength
    static func field(width w: Int, height h: Int, strength: Double) -> CGImage? {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for j in 0 ..< h {
            let light = ColourPick.lightTop - Double(j) / Double(max(1, h - 1)) * (ColourPick.lightTop - ColourPick.lightBottom)
            for i in 0 ..< w {
                let hue = Double(i) / Double(max(1, w - 1)) * 360
                let v = p3(light: light, chroma: maxChroma(light: light, hue: hue) * strength, hue: hue)
                let o = (j * w + i) * 4
                px[o] = UInt8(v.x * 255 + 0.5); px[o + 1] = UInt8(v.y * 255 + 0.5); px[o + 2] = UInt8(v.z * 255 + 0.5)
            }
        }
        guard let cs = CGColorSpace(name: CGColorSpace.displayP3),
              let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// YOUR COLOURS (15.3): the last ten picked anywhere in the app, newest first; never presets. A pick near one already
/// there moves that one to the front instead of adding a near-twin.
@MainActor
@Observable
final class ColourStore {
    static let shared = ColourStore()
    private(set) var recent: [ColourPick] = []
    private let key = "wya.colours.recent"
    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let a = try? JSONDecoder().decode([ColourPick].self, from: d) {
            // (kept before swatches that look alike were folded into one: folded now, newest kept)
            var one: [ColourPick] = []
            for c in a where !one.contains(where: { $0.alike(c) }) { one.append(c) }
            recent = one
        }
    }
    func add(_ c: ColourPick) {
        var a = recent
        a.removeAll { $0.alike(c) }
        a.insert(c, at: 0)
        recent = Array(a.prefix(10))
        save()
    }
    func remove(_ c: ColourPick) { recent.removeAll { $0 == c }; save() }
    private func save() { if let d = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(d, forKey: key) } }
}

/// THE PICKER (15.3): the field, the strength strip and your colours, the given width. `colour` changes live as the
/// finger moves (the thing it colours follows every frame); `done` is called once per gesture with the colour kept
/// (one undo step per gesture, 15.4).
struct ColourPicker: View {
    @Binding var colour: ColourPick
    let suggested: ColourPick?
    let width: CGFloat
    var done: (ColourPick) -> Void = { _ in }

    @State private var store = ColourStore.shared
    @State private var image: CGImage?
    @State private var imageStrength = -1.0
    /// the finger on the field (the loupe up) and where
    @State private var finger: CGPoint?
    @State private var lastEnd = 0
    @State private var stripEnd = 0

    static let fieldH: CGFloat = 132, stripH: CGFloat = 32, circle: CGFloat = 32, gap: CGFloat = 10
    /// the marker's half: it is drawn inside the field at every edge; the colour is still the one under the finger
    /// across the whole field
    static let edge: CGFloat = 11

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                field
                strip
            }
            .frame(width: width)
            row.padding(.top, 16)
        }
        .frame(width: width)
        .task(id: Int(colour.light * 40)) { await redraw() }
    }

    // MARK: the wheel

    /// the wheel's size: as tall as the field and its strip were, so the sheets keep their height
    static var wheelD: CGFloat { fieldH + 12 + stripH }
    /// the light-to-deep bar beside it
    static let barW: CGFloat = 32

    private var field: some View {
        let d = Self.wheelD, r = d / 2
        // the marker: round the wheel at its hue (red at the top, going clockwise), out from the middle by its strength
        let a = colour.hue * .pi / 180
        let reach = min(colour.strength * r, r - Self.edge)
        let marker = CGPoint(x: r + reach * sin(a), y: r - reach * cos(a))
        return ZStack(alignment: .topLeading) {
            Group {
                // THE WHEEL THERE FROM THE FIRST FRAME: drawn away from the screen, it was an empty ring for a tenth
                // of a second as its sheet came up, then all its colours at once; now a small one, quick to draw,
                // stands in its place until the full one is ready (soft, then sharp; never empty, then full)
                if let image { Image(decorative: image, scale: 1).resizable().interpolation(.high) }
                else if let quick = Self.quickWheel(colour.light) { Image(decorative: quick, scale: 1).resizable().interpolation(.high) }
                else { Color.clear }
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
            // the marker, which is the loupe while the finger is down (A15.2, A15.3: one disc changing size)
            disc(finger == nil ? 22 : 56)
                .position(loupeAt(marker))
                .animation(finger == nil ? .interpolatingSpring(duration: Motion.reduce ? 0.2 : 0.26, bounce: 0) : nil, value: finger)
                .allowsHitTesting(false)
        }
        .frame(width: d, height: d)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                finger = v.location
                let dx = Double(v.location.x - r), dy = Double(v.location.y - r)
                var hue = atan2(dx, -dy) * 180 / .pi
                if hue < 0 { hue += 360 }
                let s = min(1, (dx * dx + dy * dy).squareRoot() / Double(r))
                // a tick as the finger reaches the edge (a continuous gesture plays nothing else, Part 0.3)
                let end = s >= 1 ? 1 : 0
                if end != 0, end != lastEnd { Feel.tick() }
                lastEnd = end
                colour = ColourPick(hue: hue, light: colour.light, strength: s)
            }
            .onEnded { _ in
                finger = nil
                lastEnd = 0
                Feel.tap()
                keep()
            })
        .accessibilityElement()
        .accessibilityLabel("Colour")
        .accessibilityValue(ColourNames.name(colour))
        .accessibilityAdjustableAction { d in
            // hue in 24 steps (15.4); strength and lightness have their own below
            colour.hue = (colour.hue + (d == .increment ? 15 : -15) + 360).truncatingRemainder(dividingBy: 360)
            Feel.tick(); keep()
        }
        .accessibilityAction(named: "Stronger") { colour.strength = min(1, colour.strength + 0.1); keep() }
        .accessibilityAction(named: "Softer") { colour.strength = max(0, colour.strength - 0.1); keep() }
    }

    /// the loupe rides 64 pt above the finger (A15.2)
    private func loupeAt(_ marker: CGPoint) -> CGPoint {
        guard let f = finger else { return marker }
        let d = Self.wheelD
        return CGPoint(x: min(d, max(0, f.x)), y: min(d, max(0, f.y)) - 64)
    }

    private func disc(_ d: CGFloat) -> some View {
        Circle().fill(colour.color)
            .frame(width: d, height: d)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .overlay(Circle().inset(by: -0.5).stroke(Palette.ink.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: light to deep (the colour at its palest at the top, its deepest at the foot)

    private var strip: some View {
        let h = Self.wheelD, w = Self.barW
        let top = ColourPick(hue: colour.hue, light: ColourPick.lightTop, strength: colour.strength)
        let mid = ColourPick(hue: colour.hue, light: (ColourPick.lightTop + ColourPick.lightBottom) / 2, strength: colour.strength)
        let foot = ColourPick(hue: colour.hue, light: ColourPick.lightBottom, strength: colour.strength)
        let t = (ColourPick.lightTop - colour.light) / (ColourPick.lightTop - ColourPick.lightBottom)
        return ZStack(alignment: .top) {
            Capsule().fill(LinearGradient(colors: [top.color, mid.color, foot.color], startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: h)
                .overlay(Capsule().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
            disc(22).position(x: w / 2, y: 11 + t * (h - 22)).allowsHitTesting(false)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let f = min(1, max(0, Double((v.location.y - 11) / (h - 22))))
                let end = f <= 0 ? -1 : f >= 1 ? 1 : 0
                if end != 0, end != stripEnd { Feel.tick() }
                stripEnd = end
                colour.light = ColourPick.lightTop - f * (ColourPick.lightTop - ColourPick.lightBottom)
            }
            .onEnded { _ in stripEnd = 0; Feel.tap(); keep() })
        .accessibilityElement()
        .accessibilityLabel("Lightness")
        .accessibilityValue(colour.light > 0.8 ? "pale" : colour.light < 0.42 ? "deep" : "middle")
        .accessibilityAdjustableAction { d in
            colour.light = min(ColourPick.lightTop, max(ColourPick.lightBottom, colour.light + (d == .increment ? 0.06 : -0.06)))
            Feel.tick(); keep()
        }
    }

    // MARK: your colours, the suggested one first

    private var row: some View {
        let fit = max(1, Int((width + Self.gap) / (Self.circle + Self.gap)))
        let mine = Array(store.recent.filter { c in !(suggested.map { $0.near(c) } ?? false) }.prefix(fit - (suggested == nil ? 0 : 1)))
        return HStack(spacing: Self.gap) {
            if let s = suggested {
                swatch(s).accessibilityLabel("Suggested")
            }
            ForEach(mine, id: \.self) { c in
                swatch(c)
                    .contextMenu { Button("Remove", role: .destructive) { Feel.lift(); withAnimation(Motion.quick) { store.remove(c) } } }
                    .transition(.identity)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: Self.circle, alignment: .leading)
        .animation(Motion.quick, value: store.recent)
    }

    private func swatch(_ c: ColourPick) -> some View {
        Button {
            Feel.tap()
            // the colour just appears
            colour = c
            done(c)
        } label: {
            Circle().fill(c.color).frame(width: Self.circle, height: Self.circle)
                .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        // (VoiceOver says the colour's name: a swatch had only a value)
        .accessibilityLabel(ColourNames.name(c))
    }

    private func keep() {
        store.add(colour)
        done(colour)
    }

    /// a small wheel for a lightness, kept: drawn on the spot the first time (a quarter of the points, a few thousand)
    private static var quickWheels: [Int: CGImage] = [:]
    static func quickWheel(_ light: Double) -> CGImage? {
        let k = Int(light * 40)
        if let w = quickWheels[k] { return w }
        let w = OKLCH.wheel(size: max(24, Int((wheelD / 2).rounded())), light: light)
        quickWheels[k] = w
        return w
    }

    private func redraw() async {
        let l = colour.light
        guard abs(l - imageStrength) > 0.02 || image == nil else { return }
        // (drawn at three times the points: the wheel's edge soft at less)
        let d = Int((Self.wheelD * 3).rounded())
        let img = await Task.detached(priority: .userInitiated) { OKLCH.wheel(size: d, light: l) }.value
        image = img; imageStrength = l
    }
}

/// A colour's spoken name for VoiceOver (15.4:): its lightness word and its hue's name
enum ColourNames {
    static let hues: [(Double, String)] = [(15, "pink"), (40, "red"), (65, "orange"), (95, "yellow"), (130, "lime"),
                                           (165, "green"), (200, "teal"), (235, "cyan"), (270, "blue"), (300, "violet"),
                                           (330, "purple"), (360, "magenta")]
    static func name(_ c: ColourPick) -> String {
        if c.strength < 0.12 { return c.light > 0.8 ? "pale grey" : c.light < 0.35 ? "near black" : "grey" }
        let hue = hues.first { c.hue < $0.0 }?.1 ?? "pink"
        let tone = c.light > 0.82 ? "pale " : c.light < 0.42 ? "deep " : ""
        let muted = c.strength < 0.45 ? "muted " : ""
        return tone + muted + hue
    }
}

#if DEBUG
/// A TEST HOST (the picker's hosts, the pin sheet and Draw, come with Step 13's Pins): a glass sheet at the screen's foot
/// with a pin-like disc that takes the colour live, for the driver's `picker` commands
@MainActor
@Observable
final class PickerTest {
    static let shared = PickerTest()
    var on = false
    var colour = ColourPick(hue: 250, light: 0.62, strength: 0.8)
    var kept = 0
}

struct PickerTestHost: View {
    let L: Layout
    @State private var t = PickerTest.shared
    var body: some View {
        if t.on {
            let w = L.W - 2 * L.sheetInset
            VStack(spacing: 16) {
                Circle().fill(t.colour.color).frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                ColourPicker(colour: Bindable(t).colour, suggested: ColourPick(hue: 28, light: 0.6, strength: 0.9), width: w - 32) { _ in
                    t.kept += 1
                }
            }
            .padding(16)
            .frame(width: w)
            .glassEffect(.clear, in: .rect(cornerRadius: L.sheetCorner))
            .position(x: L.W / 2, y: L.capsule.minY - 220)
        }
    }
}
#endif

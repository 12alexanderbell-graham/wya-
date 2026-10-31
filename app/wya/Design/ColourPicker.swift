import SwiftUI
import UIKit
import simd

// THE COLOUR PICKER (Part 15): one system for every colour a person chooses (pins, drawings, routes, the profile's
// picture, letter and gradient). No presets anywhere (23 Oct 16:28: "We don't do pre-made colors ... We have a
// color-picking menu that's very intuitive"): a field of every hue (across) and lightness (down) at the most colour
// Display P3 allows, a strength strip under it, then your last ten colours led by one suggested from what the thing
// already has. No hex, no numbers, no words; no lime ring round anything (29 Oct 20:30, Q15.2).

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
        if let d = UserDefaults.standard.data(forKey: key), let a = try? JSONDecoder().decode([ColourPick].self, from: d) { recent = a }
    }
    func add(_ c: ColourPick) {
        var a = recent
        if let i = a.firstIndex(where: { $0.near(c) }) { a.remove(at: i) }
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

    static let fieldH: CGFloat = 168, stripH: CGFloat = 32, circle: CGFloat = 32, gap: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            field
            strip.padding(.top, 12)
            row.padding(.top, 16)
        }
        .frame(width: width)
        .task(id: Int(colour.strength * 20)) { await redraw() }
    }

    // MARK: the field

    private var field: some View {
        let s = colour.spot
        let marker = CGPoint(x: s.x * width, y: s.y * Self.fieldH)
        return ZStack(alignment: .topLeading) {
            Group {
                if let image { Image(decorative: image, scale: 1).resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: width, height: Self.fieldH)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            // the marker, which is the loupe while the finger is down (A15.2, A15.3: one disc changing size)
            disc(finger == nil ? 22 : 56)
                .position(loupeAt(marker))
                .animation(finger == nil ? .interpolatingSpring(duration: Motion.reduce ? 0.2 : 0.26, bounce: 0) : nil, value: finger)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: Self.fieldH)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                finger = v.location
                let p = CGPoint(x: v.location.x / width, y: v.location.y / Self.fieldH)
                // a tick at the field's left or right end (a continuous gesture plays nothing else, Part 0.3)
                let end = p.x <= 0 ? -1 : p.x >= 1 ? 1 : 0
                if end != 0, end != lastEnd { Feel.tick() }
                lastEnd = end
                colour = ColourPick.at(p, strength: colour.strength)
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
            // hue in 24 steps (15.4); lightness and strength have their own adjustables below
            colour.hue = (colour.hue + (d == .increment ? 15 : -15) + 360).truncatingRemainder(dividingBy: 360)
            Feel.tick(); keep()
        }
    }

    /// the loupe rides 64 pt above the finger, or beside it near the top (A15.2)
    private func loupeAt(_ marker: CGPoint) -> CGPoint {
        guard let f = finger else { return marker }
        let fx = min(width, max(0, f.x)), fy = min(Self.fieldH, max(0, f.y))
        return CGPoint(x: fx, y: fy - 64)
    }

    private func disc(_ d: CGFloat) -> some View {
        Circle().fill(colour.color)
            .frame(width: d, height: d)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .overlay(Circle().inset(by: -0.5).stroke(Palette.ink.opacity(0.5), lineWidth: 0.5))
    }

    // MARK: the strength strip (the hue's grey at the left, its full colour at the right)

    private var strip: some View {
        let grey = ColourPick(hue: colour.hue, light: colour.light, strength: 0)
        let full = ColourPick(hue: colour.hue, light: colour.light, strength: 1)
        return ZStack(alignment: .leading) {
            Capsule().fill(LinearGradient(colors: [grey.color, full.color], startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: Self.stripH)
            disc(22).position(x: 11 + colour.strength * (width - 22), y: Self.stripH / 2).allowsHitTesting(false)
        }
        .frame(width: width, height: Self.stripH)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let s = min(1, max(0, Double((v.location.x - 11) / (width - 22))))
                let end = s <= 0 ? -1 : s >= 1 ? 1 : 0
                if end != 0, end != stripEnd { Feel.tick() }
                stripEnd = end
                colour.strength = s
            }
            .onEnded { _ in stripEnd = 0; Feel.tap(); keep() })
        .accessibilityElement()
        .accessibilityLabel("Strength")
        .accessibilityValue("\(Int(colour.strength * 100)) percent")
        .accessibilityAdjustableAction { d in
            colour.strength = min(1, max(0, colour.strength + (d == .increment ? 0.1 : -0.1))); Feel.tick(); keep()
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
                    .transition(.scale)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: Self.circle, alignment: .leading)
        .animation(Motion.quick, value: store.recent)
    }

    private func swatch(_ c: ColourPick) -> some View {
        Button {
            Feel.tap()
            withAnimation(Motion.quick) { colour = c }
            done(c)
        } label: {
            Circle().fill(c.color).frame(width: Self.circle, height: Self.circle)
                .overlay(Circle().inset(by: -0.25).stroke(Palette.ink.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityValue(ColourNames.name(c))
    }

    private func keep() {
        store.add(colour)
        done(colour)
    }

    private func redraw() async {
        let s = colour.strength
        guard abs(s - imageStrength) > 0.02 || image == nil else { return }
        let w = Int(width.rounded()), h = Int(Self.fieldH)
        let img = await Task.detached(priority: .userInitiated) { OKLCH.field(width: w, height: h, strength: s) }.value
        image = img; imageStrength = s
    }
}

/// A colour's spoken name for VoiceOver (15.4: "deep teal"): its lightness word and its hue's name
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
            .glassEffect(.regular, in: .rect(cornerRadius: L.sheetCorner))
            .position(x: L.W / 2, y: L.capsule.minY - 220)
        }
    }
}
#endif

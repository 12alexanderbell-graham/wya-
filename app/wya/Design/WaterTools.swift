import SwiftUI

/// TOOLS IN THE WATER: a row of 44 pt glass circles where every map's caption sits, one line of words under them in
/// the caption's tail style (headline, the ink at 50%). A tool in use fills black, its icon white; one that can't be
/// used yet has its icon at 50%. No bar behind them, no lime. Pins' tools (Add pin, Route, Draw) and the draw tool's
/// Undo, Cancel, Done are both this row.
struct WaterTools: View {
    struct Tool {
        /// an Icon5 key, or "pin" for the pins' own shape
        let icon: String
        let label: String
        var on = false
        var dim = false
        /// a circle that opens Apple's menu of these choices instead of acting at once
        var menu: [(String, () -> Void)]? = nil
        let act: () -> Void
    }
    let tools: [Tool]
    let words: String
    /// the words dimmer still (a hint, not a measure)
    var hint = false
    /// the row's width: given, the circles share it evenly (each its own equal part, the button rule: widths are the
    /// width split in n), else they sit together in the middle
    var width: CGFloat? = nil
    /// where the circles and their words sit: together in the middle, or together from the leading edge (Pins)
    var align: HorizontalAlignment = .center
    /// the tools as words in one glass capsule, each an equal part of it; the one in use filled black, its word white
    var capsule = false

    var body: some View {
        VStack(alignment: align, spacing: 8) {
            if capsule, let w = width {
                HStack(spacing: 0) {
                    // (each part cuts its own word as it rolls: a word never runs into its neighbour)
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, t in segment(t, w / CGFloat(max(1, tools.count))).clipShape(Capsule()) }
                }
                .padding(3)
                .frame(width: w, height: 44)
                .glassEffect(PageGlass.head, in: .capsule)
                .animation(Motion.quick, value: tools.map(\.on))
            } else {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: width == nil ? 12 : 0) {
                    // (by place, not by tool: a circle stays where it is and only its icon changes, Apple's blur
                    // replace, when the row becomes another tool's controls)
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, t in
                        circle(t).frame(width: width.map { $0 / CGFloat(max(1, tools.count)) })
                    }
                }
            }
            }
            // a number changing rolls (Apple's numeric text); other words are a new line, blurred in over the old
            // one (rolled letter by letter, two different lines tangled into each other, 17:42)
            ZStack {
                // (an empty line keeps its height, so nothing moves when words come)
                Text(words.isEmpty ? " " : words)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .id(words.filter { !$0.isNumber })
                    .transition(Self.roll)
            }
            // (the line rolls whole, up through its own height, cut at its edges: never letter by letter, never faded)
            .clipped()
            .animation(Motion.quick, value: words)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// A WORD OR AN ICON GIVING WAY TO ANOTHER IN ITS PLACE (26 Nov: nothing fades one thing into another): the old one
    /// rolls up out of its slot, the new one up into it from below, the slot cutting both
    static let roll: AnyTransition = .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))

    /// one tool in the capsule: its word, centred in its part; a menu tool opens Apple's menu
    @ViewBuilder private func segment(_ t: Tool, _ w: CGFloat) -> some View {
        let label = Text(t.label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(t.on ? Palette.white : Palette.ink.opacity(t.dim ? 0.5 : 1))
            .lineLimit(1)
            .frame(width: w - 6, height: 38)
            .background { if t.on { Capsule().fill(Palette.ink) } }
            .contentShape(Capsule())
            .id(t.label)
            .transition(Self.roll)
        if let m = t.menu {
            Menu {
                ForEach(Array(m.enumerated()), id: \.offset) { _, e in Button(e.0) { e.1() } }
            } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel(t.label)
        } else {
            Button {
                if t.dim { Feel.refuse(); return }
                Feel.tap()
                t.act()
            } label: { label }
            .buttonStyle(.plain)
            .accessibilityAddTraits(t.on ? [.isButton, .isSelected] : .isButton)
        }
    }

    @ViewBuilder private func circle(_ t: Tool) -> some View {
        if let m = t.menu {
            Menu {
                ForEach(Array(m.enumerated()), id: \.offset) { _, e in Button(e.0) { e.1() } }
            } label: {
                icon(t.icon, Palette.ink).frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(PageGlass.head, in: .circle)
            .accessibilityLabel(t.label)
        } else {
            press(t)
        }
    }

    private func press(_ t: Tool) -> some View {
        return Button {
            if t.dim { Feel.refuse(); return }
            Feel.tap()
            t.act()
        } label: {
            ZStack {
                // (black and white both there, crossfading with the fill: one icon recoloured at once sat black on
                // the half-filled circle for a frame)
                ZStack {
                    icon(t.icon, Palette.ink.opacity(t.dim ? 0.5 : 1)).opacity(t.on ? 0 : 1)
                    icon(t.icon, Palette.white).opacity(t.on ? 1 : 0)
                }
                .id(t.icon)
                .transition(Self.roll)
            }
            .animation(Motion.quick, value: t.icon)
            .frame(width: 44, height: 44)
            // (a new icon rolls up into its circle, the old one out of its top, cut by the circle)
            .clipShape(Circle())
            .background { if t.on { Circle().fill(Palette.ink) } }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(t.on ? .identity : PageGlass.head, in: .circle)
        .animation(Motion.quick, value: t.on)
        .accessibilityLabel(t.label)
        .accessibilityAddTraits(t.on ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private func icon(_ key: String, _ ink: Color) -> some View {
        if key == "pin" { PinShape().fill(ink).frame(width: 16, height: 20) } else { Icon5(key: key, ink: ink, size: 20) }
    }
}

/// ONE OF THE WATER'S CONTENTS GIVING WAY TO ANOTHER: the leaving one rolls up through the water's open part and out of
/// its top edge, the coming one up into it from the capsule's top line, both moving the open part's height (never the
/// whole screen's, which took the old one away in one frame), and cut at the capsule's top while they move so no word
/// crosses the tabs; the cut opens back to the screen's foot only in the roll's last quarter, as the contents settle
extension AnyTransition {
    static func rollThrough(slot: CGFloat, cutY: CGFloat) -> AnyTransition {
        .asymmetric(insertion: .modifier(active: RollThrough(phase: 1, slot: slot, cutY: cutY),
                                         identity: RollThrough(phase: 0, slot: slot, cutY: cutY)),
                    removal: .modifier(active: RollThrough(phase: -1, slot: slot, cutY: cutY),
                                       identity: RollThrough(phase: 0, slot: slot, cutY: cutY)))
    }
}

struct RollThrough: ViewModifier, Animatable {
    var phase: CGFloat
    let slot: CGFloat
    let cutY: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    func body(content: Content) -> some View {
        let open = max(0, 1 - abs(phase) * 4)
        content
            .offset(y: phase * slot)
            .mask(alignment: .top) {
                GeometryReader { g in
                    let top = g.frame(in: .global).minY
                    let cut = cutY + 2000 * open
                    // (from far above the view, for the leaving one's way out, down to the cut, in the view's own space)
                    let bottom = cut - top
                    Rectangle()
                        .frame(width: g.size.width + 800, height: max(0, bottom + 400))
                        .position(x: g.size.width / 2, y: (bottom - 400) / 2)
                }
            }
    }
}

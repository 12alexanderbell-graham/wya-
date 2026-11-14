import SwiftUI

/// TOOLS IN THE WATER (12 Nov): a row of 44 pt glass circles where every map's caption sits,
/// one line of words under them in the caption's tail style (headline, the ink at 50%). A tool in use fills black,
/// its icon white; one that can't be used yet has its icon at 50%. No bar behind them, no lime.
/// Pins' tools (Add pin, Route, Draw) and the draw tool's Undo, Cancel, Done are both this row.
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

    var body: some View {
        VStack(alignment: align, spacing: 8) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: width == nil ? 12 : 0) {
                    // (by place, not by tool: a circle stays where it is and only its icon changes, Apple's blur
                    // replace, when the row becomes another tool's controls)
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, t in
                        circle(t).frame(width: width.map { $0 / CGFloat(max(1, tools.count)) })
                    }
                }
            }
            // a number changing rolls (Apple's numeric text); other words are a new line, blurred in over the old
            // one (rolled letter by letter, two different lines tangled into each other, 17:42)
            ZStack {
                // (an empty line keeps its height, so nothing moves when words come)
                Text(words.isEmpty ? " " : words)
                    .font(.headline)
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .id(words.filter { !$0.isNumber })
                    .transition(.blurReplace)
            }
            .animation(Motion.quick, value: words)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                .transition(.blurReplace)
            }
            .animation(Motion.quick, value: t.icon)
            .frame(width: 44, height: 44)
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

import SwiftUI

/// THE REGION MAP'S LINE IN THE SHEET (6.6, as the old native app had it in its band: paintLevels / levelWords): the
/// country's name, and under it every level the country has, as many to a line as fit (centred, wrapping onto a second
/// line only when they don't fit), all in ink; the level shown in the heaviest weight, the others lighter, no box and
/// no colour round it. No flag, no number, nothing to scroll.
/// A tap on a level shows it. A level that can't be had now says "Not ready" in its place (no network), or
/// "Couldn't load" (the server answered wrong); a tap on either tries again. A finer level still coming after 0.4 s
/// has the small working mark beside its word (12.5).
struct RegionLevels: View {
    struct Level: Identifiable, Equatable { let row: Int; let word: String; var id: Int { row } }
    let name: String
    let levels: [Level]
    let current: Int
    let notReady: Int?
    var failed = false
    var loading: Int? = nil
    let width: CGFloat
    let visible: Bool
    let pick: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // the name at the Countries caption's name size, the levels at the size of its tail (17 pt), set to use the
            // water: lines 10 pt apart, words 18 pt apart
            // (one line inside the levels' 24 pt margins: a long name gets a little smaller, never runs past them)
            roll(name).font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: width - 48)
                .accessibilityAddTraits(.isHeader)
            if levels.count > 1 {
                // (14 Nov: one line, the level shown a black chip with white words as every chosen thing in the app;
                // the line slides sideways when the levels are wider than the sheet, never wrapping onto a second line)
                ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(levels) { l in
                            let here = l.row == current
                            let coming = l.row == loading
                            HStack(spacing: 0) {
                                roll(l.row == notReady ? (failed ? "Couldn't load" : "Not ready") : l.word)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                                // the mark grows from its own centre (A12.2) as its room opens beside the word, and goes
                                // back into it as the level arrives (A12.3); the words beside it move, never jump
                                WorkingMark(size: 20, running: coming)
                                    .opacity(coming ? 1 : 0)
                                    .transaction { $0.animation = nil }
                                    .frame(width: coming ? 26 : 0, alignment: .trailing)
                            }
                            .foregroundStyle(here ? Palette.white : Palette.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background { if here { Capsule().fill(Palette.ink) } }
                            .frame(height: 44)
                            .animation(Motion.quick, value: coming)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(coming ? "Loading" : "")
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !here else { return }
                                Feel.tap()
                                pick(l.row)
                            }
                            .accessibilityAddTraits(here ? [.isButton, .isSelected] : .isButton)
                            .id(l.row)
                            // A LEVEL'S WORD HELD (11.5): the country's levels as rows, a quicker pick on a small
                            // phone; the one shown unavailable (the current row, 11.3)
                            .contextMenu {
                                Section(name) {
                                    ForEach(levels) { m in
                                        Button(m.word.prefix(1).uppercased() + m.word.dropFirst()) {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pick(m.row) }
                                        }
                                        .disabled(m.row == current)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minWidth: width)
                }
                .scrollIndicators(.hidden)
                .frame(width: width, height: 44)
                // (the ends go out softly, never cut by a hard line)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                             .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .onChange(of: current) { _, c in withAnimation(Motion.quick) { reader.scrollTo(c, anchor: .center) } }
                .onAppear { reader.scrollTo(current, anchor: .center) }
                }
                // (the words' places change with the words, in the same frame: see `roll`)
                .transaction(value: visible) { $0.animation = nil; $0.disablesAnimations = true }
            }
        }
        .foregroundStyle(Palette.ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// a word: there, or a blank of its length (never faded, never scaled). It changes in one frame, its place with
    /// it: while the change was still animated the words cut in at once but the line took a quarter of a second to
    /// re-space from the blanks' widths, so for a frame "communes" and "towns" stood as one word (12 Nov strip)
    private func roll(_ s: String) -> some View {
        Text(visible ? s : Caption.blank(s, "\u{2002}"))
            .contentTransition(.identity)
            .transaction(value: visible) { $0.animation = nil; $0.disablesAnimations = true }
            .transaction(value: s) { $0.animation = nil; $0.disablesAnimations = true }
    }
}

/// as many to a line as fit, each line centred
struct CentredFlow: SwiftUI.Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(subviews, width: proposal.width ?? .infinity)
        let h = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.midX - line.width / 2
            for i in line.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (line.height - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var out: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], w: CGFloat = 0, h: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !cur.isEmpty && w + spacing + s.width > width {
                out.append((cur, w, h)); cur = []; w = 0; h = 0
            }
            w += (cur.isEmpty ? 0 : spacing) + s.width
            h = max(h, s.height)
            cur.append(i)
        }
        if !cur.isEmpty { out.append((cur, w, h)) }
        return out
    }
}

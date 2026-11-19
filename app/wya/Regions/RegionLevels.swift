import SwiftUI

/// THE REGION MAP'S LINE IN THE SHEET (6.6, as the old native app had it in its band: paintLevels / levelWords): the
/// country's name, and under it every level the country has on one line that slides sideways when it is wider than
/// the sheet, the level shown a black chip with white words. No flag, no number. A tap on a level shows it. A level
/// that can't be had now says in its place (no network), or (the server answered wrong); a tap on either tries again.
/// A finer level still coming after 0.4 s has the small working mark beside its word (12.5).
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
    @Environment(\.dynamicTypeSize) private var typeSize

    /// a level's chip width: its word at body semibold for the type size in use, and the chip's 12 pt each side
    static func chipWidth(_ s: String, size: DynamicTypeSize) -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(min(size, .xxxLarge))))
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        return ceil((s as NSString).size(withAttributes: [.font: font]).width) + 24
    }

    var body: some View {
        VStack(spacing: 12) {
            // the name at the Countries caption's name size, the levels at the size of its tail (17 pt), set to use
            // the water: lines 10 pt apart, words 18 pt apart
            roll(name).font(.title2.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: width - 48)
                .accessibilityAddTraits(.isHeader)
            if levels.count > 1 {
                // THE LEVELS AS A WHEEL: one line, the level shown always in the middle on its black chip, the levels
                // before and after it either side, going out softly at the edges when they don't all fit. A tap on
                // another level, or a swipe along the line, turns it: the line slides so the new level stands in the
                // middle. All of them fitting, the line simply stands centred.
                let words = levels.map { $0.row == notReady ? (failed ? "Couldn't load" : "Not ready") : $0.word }
                let ws = words.enumerated().map { Self.chipWidth($0.element, size: typeSize) + (levels[$0.offset].row == loading ? 26 : 0) }
                let gap: CGFloat = 2
                let total = ws.reduce(0, +) + gap * CGFloat(max(0, ws.count - 1))
                let i = levels.firstIndex { $0.row == current } ?? 0
                let mid = ws.prefix(i).reduce(0, +) + gap * CGFloat(i) + ws[i] / 2
                let fits = total <= width - 32
                let x: CGFloat = fits ? (width - total) / 2 : width / 2 - mid
                HStack(spacing: gap) {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { k, l in
                        let here = l.row == current
                        let coming = l.row == loading
                        HStack(spacing: 0) {
                            roll(words[k])
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
                        // (the chip goes with the words: left behind, it lay over Upload's Photos as a black bar)
                        .background { if here && visible { Capsule().fill(Palette.ink) } }
                        .frame(height: 44)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(coming ? "Loading" : "")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !here else { return }
                            Feel.tap()
                            pick(l.row)
                        }
                        .accessibilityAddTraits(here ? [.isButton, .isSelected] : .isButton)
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
                .fixedSize()
                .offset(x: x)
                .frame(width: width, height: 44, alignment: .leading)
                .animation(Motion.quick, value: current)
                .animation(Motion.quick, value: loading)
                .clipped()
                // (the ends go out softly, never cut by a hard line, when the line is wider than the sheet)
                .mask(LinearGradient(stops: fits ? [.init(color: .black, location: 0), .init(color: .black, location: 1)]
                                     : [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                        .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .contentShape(Rectangle())
                // a swipe along the line turns it by one level
                .simultaneousGesture(DragGesture(minimumDistance: 16).onEnded { g in
                    guard abs(g.translation.width) > 30, abs(g.translation.width) > abs(g.translation.height) else { return }
                    let j = i + (g.translation.width < 0 ? 1 : -1)
                    guard levels.indices.contains(j) else { Feel.refuse(); return }
                    Feel.tap()
                    pick(levels[j].row)
                })
                // (the words' places change with the words, in the same frame: see `roll`)
                .transaction(value: visible) { $0.animation = nil; $0.disablesAnimations = true }
            }
        }
        .foregroundStyle(Palette.ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// a word: there, or a blank of its length (never faded, never scaled). It changes in one frame, its place with
    /// it: while the change was still animated the words cut in at once but the line took a quarter of a second to
    /// re-space from the blanks' widths, so for a frame and "towns" stood as one word
    private func roll(_ s: String) -> some View {
        Text(visible ? s : Caption.blank(s, "\u{2002}"))
            .contentTransition(.identity)
            .transaction(value: visible) { $0.animation = nil; $0.disablesAnimations = true }
            .transaction(value: s) { $0.animation = nil; $0.disablesAnimations = true }
    }
}

import SwiftUI

/// A DAY HOUR BY HOUR. The day's name tapped opens it: the things with no time stay above as they are, and the hours
/// run down the page, each timed thing a box from its start to its end in its colour (lime glass while the AI's plan
/// isn't kept). A box tapped opens the thing's sheet; an empty hour tapped makes a thing at that hour and opens its
/// sheet. From 06:00 unless something starts earlier.
struct PlanDayHours: View {
    let items: [PlanItem]
    let ai: Bool
    let open: (PlanItem) -> Void
    let add: (Int) -> Void

    static let hour: CGFloat = 48
    private let labelW: CGFloat = 52

    var body: some View {
        let timed = items.filter { $0.span != nil }
        let first = min(6, timed.compactMap { $0.span?.0 }.min().map { $0 / 60 } ?? 6)
        let hours = Array(first ..< 24)
        ZStack(alignment: .topLeading) {
            // the hours: the hour's words at 50%, nothing drawn across; an empty hour tapped makes a thing there
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { h in
                    HStack(alignment: .top, spacing: 0) {
                        Text(String(format: "%02d:00", h)).font(.footnote.monospacedDigit())
                            .foregroundStyle(Palette.ink.opacity(0.5))
                            .frame(width: labelW, alignment: .leading)
                            .offset(y: -8)
                        // (no line across the hour, 25 Nov: the hour is its number alone)
                        Color.clear.frame(height: 0.5)
                    }
                    .frame(height: Self.hour, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { Feel.tap(); add(h * 60) }
                    .accessibilityElement()
                    .accessibilityLabel(String(format: "%02d:00, add", h))
                    .accessibilityAddTraits(.isButton)
                }
            }
            // the timed things, each a box from its start to its end
            ForEach(timed) { it in
                if let (a, b) = it.span {
                    let y = CGFloat(a - first * 60) / 60 * Self.hour
                    let h = max(30, CGFloat(b - a) / 60 * Self.hour - 2)
                    let fill = it.c.isEmpty ? Palette.white.opacity(0.7) : PlanItemSheet.colour(it.c).opacity(0.85)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(it.what).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(h > 44 ? 2 : 1)
                        if h > 50, !it.place.isEmpty {
                            Text(it.place).font(.footnote).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: h, maxHeight: h, alignment: .topLeading)
                    .background(ai ? Color.clear : fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .glassEffect(ai ? .clear.tint(Palette.lime.opacity(0.55)) : .identity,
                                 in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture { Feel.tap(); open(it) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .padding(.leading, labelW)
                    .padding(.top, y + 1)
                }
            }
        }
        .frame(height: CGFloat(hours.count) * Self.hour, alignment: .top)
        .padding(.top, 10)
    }
}

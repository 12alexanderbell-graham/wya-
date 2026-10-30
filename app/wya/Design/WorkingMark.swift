import SwiftUI

/// THE WORKING MARK (Part 12.3, A12.1): the logo turning about its line, one turn every 1.2 s at a constant speed,
/// drawn from LogoMark on the TimelineView clock; still (and costing nothing) while `running` is
/// off. The small size (20 pt) is a control's: Here waiting, finding's number. It arrives and leaves by its caller's
/// scale about its own centre (A12.2, A12.3).
/// Not yet as the book has it: the planets' sphere shader with the logo's halves as its surface map (12.3 "To build");
/// the flat mark turning stands in until then.
struct WorkingMark: View {
    var size: CGFloat = 20
    var running = true
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !running)) { t in
            let s = t.date.timeIntervalSinceReferenceDate
            LogoMark(phase: LogoMark.rest + 2 * .pi * (s.truncatingRemainder(dividingBy: 1.2) / 1.2), glass: size >= 40)
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// DAYS THAT BELONG TOGETHER ARE ONE SHAPE (25 Nov): no lines anywhere, a run of things reads as one soft shape, its
/// pieces meeting softly. A run's days, one rectangle per week row, are drawn blurred and cut at half their
/// strength: rows that touch melt into one rounded form, a row's ends round off, and nothing else is drawn. Used as a
/// mask (a flag over a trip's days) or filled (a plan's days in black).
struct DayGoo: View {
    /// the run's rectangles, one per week row, in the grid's own space
    let rects: [CGRect]
    /// how soft the joins are: rows this far apart or less melt together
    var soft: CGFloat = 5
    var corner: CGFloat = 10
    var ink: Color = .black

    var body: some View {
        // (drawn past the grid by `pad` on every side, so the blur is never cut at the canvas edge)
        let pad = soft * 4
        Canvas { ctx, size in
            ctx.addFilter(.alphaThreshold(min: 0.5, color: ink))
            ctx.addFilter(.blur(radius: soft))
            ctx.drawLayer { l in
                for r in rects {
                    l.fill(Path(roundedRect: r.offsetBy(dx: pad, dy: pad), cornerRadius: corner, style: .continuous),
                           with: .color(.black))
                }
            }
        }
        .padding(-pad)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// a run of cells in a 7-column grid (cell indices counted from the grid's first cell) as one rectangle per row
    static func rows(_ cells: [Int], side: CGFloat, height: CGFloat? = nil, gapX: CGFloat, gapY: CGFloat) -> [CGRect] {
        let h = height ?? side
        var byRow: [Int: (lo: Int, hi: Int)] = [:]
        for c in cells {
            let r = c / 7, k = c % 7
            if let e = byRow[r] { byRow[r] = (min(e.lo, k), max(e.hi, k)) } else { byRow[r] = (k, k) }
        }
        let rects = byRow.keys.sorted().map { r in
            let e = byRow[r]!
            return CGRect(x: CGFloat(e.lo) * (side + gapX), y: CGFloat(r) * (h + gapY),
                          width: CGFloat(e.hi - e.lo + 1) * side + CGFloat(e.hi - e.lo) * gapX, height: h)
        }
        return meet(rects, gap: gapY)
    }

    /// rows one under the other that share columns reach across the gap between them and touch, so the blur rounds
    /// the join into one soft neck (left apart, a 4 pt gap stayed a white line)
    static func meet(_ rects: [CGRect], gap: CGFloat) -> [CGRect] {
        var out = rects
        for i in out.indices.dropLast() {
            let a = out[i], b = out[i + 1]
            let shared = min(a.maxX, b.maxX) - max(a.minX, b.minX)
            guard shared > 1, b.minY - a.maxY <= gap + 0.5 else { continue }
            // a bridge over the shared columns only, from inside one row to inside the other (a full-width reach
            // would square off the rows' outer corners)
            let x0 = max(a.minX, b.minX), x1 = min(a.maxX, b.maxX)
            out.append(CGRect(x: x0, y: a.maxY - 12, width: x1 - x0, height: b.minY - a.maxY + 24))
        }
        return out
    }

    /// the box round a run's rectangles (where its picture is laid)
    static func box(_ rects: [CGRect]) -> CGRect { rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) } }
}

import SwiftUI
import UIKit

/// WHERE EVERYTHING SITS, worked out from the real screen. Nothing on screen uses a fixed y or x: everything comes from
/// here, and this comes from the screen's size and its safe areas. The only fixed numbers are Apple's own sizes
/// (44-point controls, the 62-point tab capsule, the 8-point sheet inset), measured on iOS 27 (APPLE-MEASURED.md).
nonisolated struct Layout: Equatable, Sendable {
    var W: CGFloat
    var H: CGFloat
    var safeTop: CGFloat
    var safeBottom: CGFloat
    /// the machine name (e.g. "iPhone19,3"), for the island and the screen's corners
    var model: String

    static let placeholder = Layout(W: 402, H: 874, safeTop: 62, safeBottom: 34, model: "")

    // MARK: the head (Apple's toolbar: 44 glass circles, 16 from the edges, centred 22 under the safe top)
    var side: CGFloat { 16 }
    var circle: CGFloat { 44 }
    var headY: CGFloat { max(safeTop, 20) + 22 }
    var headTop: CGFloat { headY - 22 }
    var headBottom: CGFloat { headY + 22 }
    var leftX: CGFloat { side + circle / 2 }
    var rightX: CGFloat { W - side - circle / 2 }

    // MARK: the tab capsule (Apple's: 274 x 62, 21 above the screen's bottom edge, centred)
    var capsule: CGRect { CGRect(x: W / 2 - 137, y: H - 21 - 62, width: 274, height: 62) }
    var capsuleCorner: CGFloat { 31 }

    // MARK: the sheet
    var sheetInset: CGFloat { 8 }
    /// the screen's own corner radius; the sheet's is that less its inset, so the two curves run parallel
    var screenCorner: CGFloat { safeTop >= 47 ? 62 : 44 }
    var sheetCorner: CGFloat { screenCorner - sheetInset }
    /// the sheet's top edge at each height. 25% holds the name and number (Apple's 25% on the 18 Pro sits 227 over
    /// the bottom, and the caption is the same size on every phone); 50% is Apple's medium height, 47.5% of the screen
    func top(_ s: SheetStop) -> CGFloat {
        switch s {
        case .closed: capsule.minY
        case .quarter: H - 227
        case .half: (H * 0.4748).rounded()
        case .full: 0
        }
    }

    // MARK: the Dynamic Island
    var island: CGRect {
        guard safeTop >= 47 else { return .zero }
        return CGRect(x: W / 2 - 46.85, y: 14.5, width: 93.7, height: 35.7)
    }

    // MARK: the open map, between the head and a sheet whose top is at `sheetTop`
    func openMap(sheetTop: CGFloat) -> ClosedRange<CGFloat> { (headBottom + 8) ... max(headBottom + 9, sheetTop - 12) }

    /// read from the window the app is in: its size and its safe areas
    @MainActor static func current(size: CGSize, insets: EdgeInsets) -> Layout {
        var top = insets.top, bottom = insets.bottom
        var size = size
        if let w = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.windows.first {
            // a view that ignores the safe areas may be handed none: then ask the window
            if top == 0 { top = w.safeAreaInsets.top; bottom = w.safeAreaInsets.bottom }
            // the screen is the window, never the room the keyboard leaves: with the keyboard up the view's own size
            // shrank, every height was worked out for a shorter screen and the whole map jumped up under the keyboard
            if w.bounds.height > 0 { size = w.bounds.size }
        }
        return Layout(W: size.width, H: size.height, safeTop: top, safeBottom: bottom, model: machine)
    }

    static let machine: String = {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()
}

/// The sheet's four heights.
nonisolated enum SheetStop: Int, CaseIterable, Sendable { case closed, quarter, half, full }

import SwiftUI
import UIKit

/// THE TWELVE: there are no others. Anything else in the app is one of these mixed with black, white or another one of
/// these. Lime is wya's colour: the chosen thing, the AI, stamped land.
nonisolated enum Palette {
    static let cream     = Color(hex: 0xfbf6f2)
    static let beigeDark = Color(hex: 0xbcb8b6)
    static let white     = Color(hex: 0xffffff)
    static let ink       = Color(hex: 0x000000)
    static let grey      = Color(hex: 0xd7d2c7)
    static let greyDark  = Color(hex: 0xa19e95)
    static let lime      = Color(hex: 0xd4e249)
    static let blue      = Color(hex: 0x78aef8)
    static let teal      = Color(hex: 0xb0e0cd)
    static let yellow    = Color(hex: 0xffe04a)
    static let red       = Color(hex: 0xd94f3d)
    static let brown     = Color(hex: 0xa9784f)

    /// the same twelve as plain numbers, for Metal (sRGB 0...1)
    static func rgb(_ v: UInt32) -> SIMD4<Float> {
        SIMD4(Float((v >> 16) & 0xff) / 255, Float((v >> 8) & 0xff) / 255, Float(v & 0xff) / 255, 1)
    }
    static let creamV = rgb(0xfbf6f2), beigeDarkV = rgb(0xbcb8b6), whiteV = rgb(0xffffff), inkV = rgb(0x000000)
    static let greyV = rgb(0xd7d2c7), greyDarkV = rgb(0xa19e95), limeV = rgb(0xd4e249), blueV = rgb(0x78aef8)
    static let tealV = rgb(0xb0e0cd), yellowV = rgb(0xffe04a), redV = rgb(0xd94f3d), brownV = rgb(0xa9784f)
}

nonisolated extension Color {
    init(hex v: UInt32) {
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255, opacity: 1)
    }
}

/// The type (DL): SF for everything that isn't a name; Tellus only for names, Regular, never bolder, never numbers.
enum Typeface {
    static func nature(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Tellus-Regular", size: size, relativeTo: style)
    }
}

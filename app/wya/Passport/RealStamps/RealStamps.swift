import Foundation

/// THE REALISTIC STAMPS: each country's stamp is its art and the words the app sets on it: your date in the stamp's
/// own form (StampDate) and, where a stamp has one, the day you may stay until. Sizes are in Japan's units (its
/// sticker is 386 by 500); on the page one unit is `K`. A country without its own stamp yet shows a black circle
/// (StampArt).
enum RealStamps {
    static let K = 112.0 / 386.0
    /// the black circle a country has until its own is drawn, across, on the page
    static let blankDiameter = 86.0

    enum What: Equatable, Sendable {
        case fixed(String)
        /// the date in the stamp's own form: a template (StampDate),,
        case date(String)
    }

    /// the type a word is set in: Barlow Condensed, Caveat and Noto Serif come with the app (SIL OFL); Courier New
    /// and the Japanese type are the phone's own, as v set Japan's sticker
    enum Face: Sendable { case barlow, caveat, courier, japanese, devanagari, serif }
    enum Anchor: Sendable { case start, middle, end }

    /// one word set on a stamp, as its SVG text was: x and y its baseline's anchor, `m` the move its text and groups
    /// gave it (a turn, a squeeze), `fit` the width it is squeezed to only if it runs over, `length` the width it is set
    /// to exactly
    struct Slot: Sendable {
        let what: What
        let x, y: Double
        let font: Face
        let size: Double
        let weight: Int
        let anchor: Anchor
        let tracking: Double
        let fill: String
        let m: StampAffine
        let fit: Double?
        let length: Double?
    }

    struct Stamp: Sendable {
        let id: String
        let w, h: Double
        let ink: String
        /// a ring: turned, it keeps its own room on the page
        let round: Bool
        let slots: [Slot]
        /// its size on the page
        var size: (w: Double, h: Double) { (w * K, h * K) }
    }

    /// the countries with their own stamp so far
    static var ids: Set<String> { Set(data.keys).union(made.keys) }
    static func stamp(_ id: String) -> Stamp? { made[id] ?? data[id] }

    /// a day, as the stamps count them (no time zone: the day you went is the same day everywhere)
    struct Day: Equatable, Sendable {
        let y, m, d: Int
        init(y: Int, m: Int, d: Int) { self.y = y; self.m = m; self.d = d }
        /// , (the first), else nil
        init?(iso: String) {
            let p = iso.split(separator: "-").compactMap { Int($0) }
            guard p.count >= 2, (1...12).contains(p[1]) else { return nil }
            self.init(y: p[0], m: p[1], d: p.count > 2 ? max(1, p[2]) : 1)
        }
        func plus(_ days: Int) -> Day {
            var c = DateComponents(); c.year = y; c.month = m; c.day = d + days; c.hour = 12
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            guard let t = cal.date(from: c) else { return self }
            let r = cal.dateComponents([.year, .month, .day], from: t)
            return Day(y: r.year ?? y, m: r.month ?? m, d: r.day ?? d)
        }
    }

    /// what a slot says for a stamp dated `day`
    static func words(_ s: Slot, _ day: Day) -> String {
        switch s.what {
        case .fixed(let t): return t
        case .date(let t): return StampDate.render(t, day)
        }
    }

}

/// a word's move on its stamp (a turn, a squeeze), as its SVG text had it
struct StampAffine: Equatable, Sendable {
    var a, b, c, d, tx, ty: Double
    static let identity = StampAffine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
}

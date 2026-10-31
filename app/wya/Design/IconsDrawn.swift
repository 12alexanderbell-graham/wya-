// IconsDrawn.swift - THE FEW NEW ICONS (Part 18.4, cut down 31 Oct): only what a tool needs that the Icons5 set does
// not have, on the 8 by 8 grid in the Icons5 style (full shapes, 1-unit strokes, straight-cut ends, sharp corners,
// curves only for circles): the passport (the book, the Countries mark cut out of it) and history (a clock, its hands
// cut out). Upload uses cal-in, quick add stamp. Made by a script, each checked at size first. `reviewed` is empty
// until each has been looked at on the review sheet.

import SwiftUI

enum IconsDrawn {
    /// the order, for the review sheet
    static let order: [String] = ["passport", "history"]
    static let blob = ###"{"passport":{"id":"T1","reviewed":"","f":[[["M1 0 7 0 7 8 1 8ZM4.50 1.50 4.17 1.52 3.85 1.59 3.54 1.69 3.25 1.83 2.98 2.02 2.73 2.23 2.52 2.48 2.33 2.75 2.19 3.04 2.09 3.35 2.02 3.67 2.00 4.00 2.02 4.33 2.09 4.65 2.19 4.96 2.33 5.25 2.52 5.52 2.73 5.77 2.98 5.98 3.25 6.17 3.54 6.31 3.85 6.41 4.17 6.48 4.50 6.50Z","#000000"]]],"loop":false},"history":{"id":"T2","reviewed":"","f":[[["M8.00 4.00 7.97 4.52 7.86 5.04 7.70 5.53 7.46 6.00 7.17 6.44 6.83 6.83 6.44 7.17 6.00 7.46 5.53 7.70 5.04 7.86 4.52 7.97 4.00 8.00 3.48 7.97 2.96 7.86 2.47 7.70 2.00 7.46 1.56 7.17 1.17 6.83 0.83 6.44 0.54 6.00 0.30 5.53 0.14 5.04 0.03 4.52 0.00 4.00 0.03 3.48 0.14 2.96 0.30 2.47 0.54 2.00 0.83 1.56 1.17 1.17 1.56 0.83 2.00 0.54 2.47 0.30 2.96 0.14 3.48 0.03 4.00 0.00 4.52 0.03 5.04 0.14 5.53 0.30 6.00 0.54 6.44 0.83 6.83 1.17 7.17 1.56 7.46 2.00 7.70 2.47 7.86 2.96 7.97 3.48ZM3.5 1.25 4.5 1.25 4.5 4.5 3.5 4.5ZM4.5 3.5 6.25 3.5 6.25 4.5 4.5 4.5Z","#000000"]]],"loop":false}}"###
}

extension IC5 {
    /// the drawn set, parsed once like the others
    static let drawn: [String: IC5Icon] = {
        guard let d = IconsDrawn.blob.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] else { return [:] }
        var out: [String: IC5Icon] = [:]
        for (k, v) in raw {
            let fs = (v["f"] as? [[[String]]]) ?? []
            out[k] = IC5Icon(frames: fs.map { f in f.compactMap { l in l.count == 2 ? IC5Layer(colour: l[1], path: parse(l[0])) : nil } },
                             loop: false)
        }
        return out
    }()
    /// the T number of a drawn icon ("T23"), for the review sheet
    static let drawnIds: [String: String] = {
        guard let d = IconsDrawn.blob.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] else { return [:] }
        return raw.compactMapValues { $0["id"] as? String }
    }()
}

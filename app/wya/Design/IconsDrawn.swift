// IconsDrawn.swift - THE FEW NEW ICONS (Part 18.4): only what a tool needs that the Icons5 set does not have. 31 Oct:
// the plus's tools are the stamp (quick stamping), the book (the passport), the arrow up out of a line (upload), and
// this one: history, two square ends joined by one straight leg, on the 8 by 8 grid in the Icons5 style (full shapes,
// 1-unit strokes, straight-cut ends, sharp corners).

import SwiftUI

enum IconsDrawn {
    /// the order, for the review sheet
    static let order: [String] = ["history"]
    static let blob = ###"{"history":{"id":"T2","reviewed":"2026-10-31","f":[[["M8.00 2.00 8.00 0.00 6.00 0.00 6.00 1.29 1.29 6.00 0.00 6.00 0.00 8.00 2.00 8.00 2.00 6.71 6.71 2.00Z","#000000"]]],"loop":false}}"###
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

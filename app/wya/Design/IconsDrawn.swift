// IconsDrawn.swift - THE FEW NEW ICONS (Part 18.4): only what a tool needs that the Icons5 set does not have. 31 Oct
// 11:47: the plus's tools are the stamp (quick stamping), the book (the passport), the arrow up out of a line (upload)
// and this one: history, two square ends joined by one straight leg (8 Nov: Pins' dock adds route, two square ends
// joined by a leg that turns once, and layers, one full square over the corner of another; and saved, the bookmark g-save in ink, for the water), on the 8 by 8 grid in the Icons5 style (full
// shapes, 1-unit strokes, straight-cut ends, sharp corners; 12 Nov: the upload sheet's photo, one full square (the
// print with its wide lower edge read as a block over a bar), never the mountains picture, and all photos, four full squares; undo, the share arrow turned to point back).
// No outlined empty shapes: every shape is filled (12 Nov 14:11: the outlined bookmark, layers and print were redrawn full). The drawn passport and clock are in _to_delete.

import SwiftUI

enum IconsDrawn {
    /// the order, for the review sheet
    static let order: [String] = ["history", "route", "layers", "saved", "photo", "photos", "undo"]
    static let blob = ###"{"history":{"id":"T2","reviewed":"2026-10-31","f":[[["M8.00 2.00 8.00 0.00 6.00 0.00 6.00 1.29 1.29 6.00 0.00 6.00 0.00 8.00 2.00 8.00 2.00 6.71 6.71 2.00Z","#000000"]]],"loop":false},"route":{"id":"T29","reviewed":"","f":[[["M0 8 2 8 2 6 1.5 6 1.5 1.5 6 1.5 6 2 8 2 8 0 6 0 6 0.5 0.5 0.5 0.5 6 0 6Z","#000000"]]],"loop":false},"saved":{"id":"T33","reviewed":"","f":[[["M2 0 2 8 4 6 6 8 6 0Z","#000000"]]],"loop":false},"layers":{"id":"T32","reviewed":"","f":[[["M0 2 6 2 6 8 0 8ZM2 0 8 0 8 6 7 6 7 1 2 1Z","#000000"]]],"loop":false},"photo":{"id":"T75","reviewed":"","f":[[["M1 1 7 1 7 7 1 7Z","#000000"]]],"loop":false},"undo":{"id":"T80","reviewed":"","f":[[["M3.46 5.25 2.75 5.95 0 3.2 2.75 0.45 3.46 1.15 1.91 2.7 2.57 2.7 3.09 2.75 3.6 2.84 4.1 2.98 4.59 3.17 5.05 3.41 5.49 3.69 6.02 4.13 6.38 4.51 6.71 4.91 6.99 5.35 7.23 5.81 7.42 6.3 7.56 6.8 7.65 7.31 7.7 7.99 6.7 8.01 6.68 7.58 6.59 7.02 6.47 6.62 6.26 6.1 5.98 5.61 5.72 5.27 5.44 4.96 5.02 4.59 4.43 4.21 4.05 4.03 3.65 3.89 3.24 3.78 2.82 3.72 1.91 3.7Z","#000000"]]],"loop":false},"photos":{"id":"T78","reviewed":"","f":[[["M0 0 3.5 0 3.5 3.5 0 3.5ZM4.5 0 8 0 8 3.5 4.5 3.5ZM0 4.5 3.5 4.5 3.5 8 0 8ZM4.5 4.5 8 4.5 8 8 4.5 8Z","#000000"]]],"loop":false}}"###
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

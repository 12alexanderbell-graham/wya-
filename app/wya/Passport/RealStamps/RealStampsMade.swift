import Foundation

// THE STAMPS MADE IN THE APP'S TIME: each from a real stamp's own form, drawn in the style (their art:
// Resources/Stamps/stamps-gen.wyaf, from SVGs made from the old stamps' own parts by tools' gen.py). Schengen states
// use the Schengen entry stamp every member stamps: its code in its ring, the plane, the date, the officer's number,
// the crossing and its code; Switzerland, Spain and Sweden first, then Slovakia and Slovenia; Cyprus uses the same
// form outside Schengen. The rest each follow a photo of the country's own entry stamp (references kept beside the
// art's sources): the emblems in them are the real ones (from public-domain files, traced to one ink), never drawn
// from memory.

extension RealStamps {
    static let made: [String: Stamp] = [
        "ar": Stamp(id: "ar", w: 420, h: 268, ink: "#2b4aa8", round: false, slots: [
            Slot(what: .date("{d1} {d2} {PE} {yyyy}"), x: 238, y: 148, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 4, fill: "#2b4aa8", m: .identity, fit: 302, length: nil)
        ]),
        "es": Stamp(id: "es", w: 340, h: 234, ink: "#000000", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 132, y: 134, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 2.2, fill: "#d94f3d", m: .identity, fit: 170, length: nil)
        ]),
        "se": Stamp(id: "se", w: 340, h: 234, ink: "#000000", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 132, y: 134, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 2.2, fill: "#d94f3d", m: .identity, fit: 170, length: nil)
        ]),
        "ch": Stamp(id: "ch", w: 340, h: 234, ink: "#000000", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 132, y: 134, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 2.2, fill: "#d94f3d", m: .identity, fit: 170, length: nil)
        ]),
        "sk": Stamp(id: "sk", w: 340, h: 234, ink: "#000000", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 132, y: 134, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 2.2, fill: "#d94f3d", m: .identity, fit: 170, length: nil)
        ]),
        "si": Stamp(id: "si", w: 340, h: 234, ink: "#000000", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 132, y: 134, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 2.2, fill: "#d94f3d", m: .identity, fit: 170, length: nil)
        ]),
        "gb": Stamp(id: "gb", w: 360, h: 258, ink: "#1d1d1d", round: false, slots: [
            Slot(what: .date("{d_} {MON} {yyyy}"), x: 180, y: 160, font: .barlow, size: 46, weight: 600, anchor: .middle, tracking: 1.5, fill: "#1d1d1d", m: .identity, fit: 259, length: nil)
        ]),
        "us": Stamp(id: "us", w: 400, h: 262, ink: "#2c5fa8", round: false, slots: [
            Slot(what: .date("{MON} {d1} {d2} {yyyy}"), x: 200, y: 176, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 2, fill: "#b8203a", m: .identity, fit: 288, length: nil)
        ]),
        "ca": Stamp(id: "ca", w: 384, h: 240, ink: "#5a4fa0", round: false, slots: [
            Slot(what: .date("{d} {CA} {yyyy}"), x: 192, y: 152, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 7, fill: "#5a4fa0", m: .identity, fit: 276, length: nil)
        ]),
        "mx": Stamp(id: "mx", w: 400, h: 250, ink: "#2f9447", round: false, slots: [
            Slot(what: .date("{dd} {ES} {yy} E"), x: 222, y: 160, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 3, fill: "#d94f3d", m: .identity, fit: 288, length: nil)
        ]),
        "br": Stamp(id: "br", w: 400, h: 230, ink: "#4f4772", round: false, slots: [
            Slot(what: .date("{dd} {MM} {yy}"), x: 118, y: 122, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 6, fill: "#4f4772", m: .identity, fit: 288, length: nil)
        ]),
        "pe": Stamp(id: "pe", w: 400, h: 250, ink: "#c23a6a", round: false, slots: [
            Slot(what: .date("{d1} {d2} {PE} {yyyy}"), x: 196, y: 146, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 3, fill: "#3a4f8c", m: .identity, fit: 288, length: nil)
        ]),
        "za": Stamp(id: "za", w: 300, h: 300, ink: "#262626", round: true, slots: [
            Slot(what: .date("{yyyy+90}-{MM+90}-{dd+90}"), x: 150, y: 148, font: .caveat, size: 46, weight: 600, anchor: .middle, tracking: 0, fill: "#4a3fa6", m: StampAffine(a: 0.9925, b: -0.1219, c: 0.1219, d: 0.9925, tx: -16.92, ty: 19.38), fit: 216, length: nil)
        ]),
        "ma": Stamp(id: "ma", w: 400, h: 270, ink: "#2f5fa6", round: false, slots: [
            Slot(what: .date("{d1} {d2} {FRAF} {yyyy}"), x: 200, y: 148, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 3, fill: "#2f5fa6", m: .identity, fit: 288, length: nil)
        ]),
        "ke": Stamp(id: "ke", w: 400, h: 230, ink: "#3f3a66", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 200, y: 128, font: .barlow, size: 36, weight: 500, anchor: .middle, tracking: 3, fill: "#8a4a3a", m: .identity, fit: 288, length: nil)
        ]),
        "au": Stamp(id: "au", w: 400, h: 270, ink: "#1f1f1f", round: false, slots: [
            Slot(what: .date("{d_} {MON} {yyyy}"), x: 200, y: 148, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 2, fill: "#1f1f1f", m: .identity, fit: 288, length: nil)
        ]),
        "tn": Stamp(id: "tn", w: 440, h: 260, ink: "#d0505a", round: false, slots: [
            Slot(what: .date("{yyyy}"), x: 118, y: 136, font: .barlow, size: 36, weight: 500, anchor: .middle, tracking: 3, fill: "#d0505a", m: .identity, fit: 317, length: nil),
            Slot(what: .date("{TN}"), x: 206, y: 134, font: .barlow, size: 26, weight: 500, anchor: .middle, tracking: 0, fill: "#d0505a", m: .identity, fit: 317, length: nil),
            Slot(what: .date("{d1} {d2}"), x: 292, y: 136, font: .barlow, size: 36, weight: 500, anchor: .middle, tracking: 3, fill: "#d0505a", m: .identity, fit: 317, length: nil)
        ]),
        "sd": Stamp(id: "sd", w: 400, h: 238, ink: "#6a3a7a", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 200, y: 132, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 3, fill: "#a8284a", m: .identity, fit: 288, length: nil)
        ]),
        "ss": Stamp(id: "ss", w: 420, h: 220, ink: "#3b45a8", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 210, y: 138, font: .barlow, size: 46, weight: 500, anchor: .middle, tracking: 3, fill: "#c8323c", m: .identity, fit: 302, length: nil)
        ]),
        "tz": Stamp(id: "tz", w: 400, h: 240, ink: "#7f7cc4", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 200, y: 140, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 3, fill: "#7f7cc4", m: .identity, fit: 288, length: nil)
        ]),
        "nz": Stamp(id: "nz", w: 400, h: 250, ink: "#262626", round: false, slots: [
            Slot(what: .date("{d} {MON} {yyyy}"), x: 200, y: 136, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 1.5, fill: "#262626", m: .identity, fit: 288, length: nil)
        ]),
        "ua": Stamp(id: "ua", w: 400, h: 250, ink: "#d2454f", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MM}  {yy}"), x: 88, y: 142, font: .barlow, size: 42, weight: 500, anchor: .start, tracking: 2, fill: "#d2454f", m: .identity, fit: 288, length: nil)
        ]),
        "kh": Stamp(id: "kh", w: 400, h: 290, ink: "#2b3a9e", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 200, y: 158, font: .barlow, size: 46, weight: 600, anchor: .middle, tracking: 2, fill: "#c4303d", m: .identity, fit: 288, length: nil),
            Slot(what: .date("{d1+29} {d2+29} {MON+29} {yyyy+29}"), x: 219, y: 216, font: .barlow, size: 40, weight: 600, anchor: .middle, tracking: 2, fill: "#c4303d", m: .identity, fit: 288, length: nil)
        ]),
        "ec": Stamp(id: "ec", w: 400, h: 240, ink: "#d0458a", round: false, slots: [
            Slot(what: .date("{dd} {yyyy} {ESL}:"), x: 204, y: 140, font: .barlow, size: 32, weight: 500, anchor: .middle, tracking: 2, fill: "#d9822b", m: .identity, fit: 200, length: nil)
        ]),
        "cn": Stamp(id: "cn", w: 400, h: 292, ink: "#e0242f", round: false, slots: [
            Slot(what: .date("{yyyy} -{MM}- {d1} {d2}"), x: 200, y: 162, font: .barlow, size: 46, weight: 500, anchor: .middle, tracking: 1.5, fill: "#e0242f", m: .identity, fit: 208, length: nil)
        ]),
        "fj": Stamp(id: "fj", w: 400, h: 218, ink: "#1e1e1e", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 196, y: 130, font: .barlow, size: 46, weight: 600, anchor: .middle, tracking: 1.5, fill: "#1e1e1e", m: .identity, fit: 200, length: nil)
        ]),
        "bd": Stamp(id: "bd", w: 400, h: 250, ink: "#2a2a2a", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 200, y: 128, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1.5, fill: "#c8285e", m: .identity, fit: 288, length: nil)
        ]),
        "jm": Stamp(id: "jm", w: 392, h: 250, ink: "#5a4a9e", round: false, slots: [
            Slot(what: .date("{d1}{d2} {MON} {yyyy}"), x: 204, y: 130, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 1.5, fill: "#5a4a9e", m: .identity, fit: 184, length: nil)
        ]),
        "pa": Stamp(id: "pa", w: 300, h: 300, ink: "#262626", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 146, y: 160, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 1.5, fill: "#262626", m: .identity, fit: 174, length: nil)
        ]),
        "ug": Stamp(id: "ug", w: 280, h: 280, ink: "#3a3a3a", round: false, slots: [
            Slot(what: .date("{dd}.  {MM}.  {yyyy}"), x: 140, y: 146, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#3a3a3a", m: .identity, fit: 200, length: nil)
        ]),
        "rw": Stamp(id: "rw", w: 280, h: 280, ink: "#3a7cc0", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 140, y: 145, font: .barlow, size: 36, weight: 500, anchor: .middle, tracking: 1.5, fill: "#a0304f", m: .identity, fit: 185, length: nil)
        ]),
        "zw": Stamp(id: "zw", w: 400, h: 250, ink: "#5b3f8c", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 200, y: 148, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 2, fill: "#5b3f8c", m: .identity, fit: 288, length: nil)
        ]),
        "sn": Stamp(id: "sn", w: 400, h: 200, ink: "#4a3fb0", round: false, slots: [
            Slot(what: .date("{dd} {FRCG} {yyyy}"), x: 290, y: 184, font: .barlow, size: 36, weight: 500, anchor: .middle, tracking: 2, fill: "#5a5470", m: .identity, fit: 288, length: nil)
        ]),
        "ci": Stamp(id: "ci", w: 400, h: 250, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{d1} {d2} {FRAF} {yyyy}"), x: 202, y: 144, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#2b2b2b", m: .identity, fit: 230, length: nil)
        ]),
        "am": Stamp(id: "am", w: 400, h: 240, ink: "#e0602e", round: false, slots: [
            Slot(what: .date("{dd} {MM} {yy}"), x: 238, y: 136, font: .barlow, size: 46, weight: 500, anchor: .end, tracking: 5, fill: "#e0602e", m: .identity, fit: 164, length: nil)
        ]),
        "az": Stamp(id: "az", w: 400, h: 290, ink: "#2f8f7a", round: false, slots: [
            Slot(what: .date("{dd} {MM} {yy}"), x: 68, y: 166, font: .barlow, size: 54, weight: 500, anchor: .start, tracking: 1, fill: "#2f8f7a", m: .identity, fit: 160, length: nil)
        ]),
        "bh": Stamp(id: "bh", w: 400, h: 270, ink: "#4a4a4a", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 200, y: 158, font: .barlow, size: 46, weight: 500, anchor: .middle, tracking: 2, fill: "#4a4a4a", m: .identity, fit: 270, length: nil)
        ]),
        "hn": Stamp(id: "hn", w: 400, h: 230, ink: "#2a2a2a", round: false, slots: [
            Slot(what: .date("{dd}/{MM}/{yyyy} 12:30:32"), x: 112, y: 141, font: .serif, size: 20, weight: 700, anchor: .start, tracking: 0.4, fill: "#2a2a2a", m: .identity, fit: 288, length: nil),
            Slot(what: .date("{dd+90}/{MM+90}/{yyyy+90}"), x: 112, y: 213, font: .serif, size: 20, weight: 700, anchor: .start, tracking: 0.4, fill: "#2a2a2a", m: .identity, fit: 288, length: nil)
        ]),
        "cy": Stamp(id: "cy", w: 340, h: 234, ink: "#000000", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 132, y: 134, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 2.2, fill: "#d94f3d", m: .identity, fit: 170, length: nil)
        ]),
        "ne": Stamp(id: "ne", w: 420, h: 240, ink: "#c8262b", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 201, y: 138, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 2, fill: "#c8262b", m: .identity, fit: 210, length: nil)
        ]),
        "mw": Stamp(id: "mw", w: 300, h: 300, ink: "#5b3c78", round: false, slots: [
            Slot(what: .date("{yyyy} -{MM}- {d1} {d2}"), x: 150, y: 164, font: .barlow, size: 26, weight: 500, anchor: .middle, tracking: 1.5, fill: "#5b3c78", m: .identity, fit: 156, length: nil)
        ]),
        "sz": Stamp(id: "sz", w: 260, h: 260, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 130, y: 150, font: .barlow, size: 36, weight: 600, anchor: .middle, tracking: 1, fill: "#2b2b2b", m: .identity, fit: 196, length: nil)
        ]),
        "tg": Stamp(id: "tg", w: 440, h: 200, ink: "#3f74c0", round: false, slots: [
            Slot(what: .date("{dd}/{MM}/{yy}"), x: 300, y: 176, font: .caveat, size: 40, weight: 600, anchor: .middle, tracking: 0, fill: "#20306e", m: StampAffine(a: 0.9976, b: -0.0698, c: 0.0698, d: 0.9976, tx: -11.55, ty: 21.36), fit: 317, length: nil)
        ]),
        "lr": Stamp(id: "lr", w: 400, h: 220, ink: "#1f5d8a", round: false, slots: [
            Slot(what: .date("{dd}/{MM}/{yy}"), x: 110, y: 170, font: .caveat, size: 40, weight: 600, anchor: .middle, tracking: 0, fill: "#20306e", m: StampAffine(a: 0.9986, b: -0.0523, c: 0.0523, d: 0.9986, tx: -8.75, ty: 5.99), fit: 288, length: nil)
        ]),
        "gd": Stamp(id: "gd", w: 410, h: 240, ink: "#2a6fc9", round: false, slots: [
            Slot(what: .date("{MON} {d1} {d2} {yyyy}"), x: 205, y: 134, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 2, fill: "#2a6fc9", m: .identity, fit: 180, length: nil),
            Slot(what: .date("{d+90} {Mon+90} {yy+90}"), x: 296, y: 192, font: .caveat, size: 30, weight: 600, anchor: .middle, tracking: 0, fill: "#20306e", m: StampAffine(a: 0.9986, b: -0.0523, c: 0.0523, d: 0.9986, tx: -9.64, ty: 15.75), fit: 295, length: nil)
        ]),
        "lc": Stamp(id: "lc", w: 380, h: 286, ink: "#4b3a9a", round: false, slots: [
            Slot(what: .date("{MON} {d1} {d2} {yyyy}"), x: 190, y: 162, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#4b3a9a", m: .identity, fit: 230, length: nil)
        ]),
        "ag": Stamp(id: "ag", w: 360, h: 280, ink: "#2d63c0", round: false, slots: [
            Slot(what: .date("{MON} {d1} {d2} {yyyy}"), x: 180, y: 158, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 2, fill: "#2d63c0", m: .identity, fit: 250, length: nil),
            Slot(what: .date("{dd+90}.{MM+90}.{yy+90}"), x: 160, y: 184, font: .caveat, size: 28, weight: 600, anchor: .middle, tracking: 0, fill: "#20306e", m: StampAffine(a: 0.9994, b: -0.0349, c: 0.0349, d: 0.9994, tx: -6.32, ty: 5.70), fit: 259, length: nil)
        ]),
        "tt": Stamp(id: "tt", w: 300, h: 300, ink: "#e04848", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 150, y: 152, font: .barlow, size: 26, weight: 500, anchor: .middle, tracking: 1.5, fill: "#e04848", m: .identity, fit: 180, length: nil),
            Slot(what: .date("{d+28} {Mon+28} {yyyy+28}"), x: 196, y: 180, font: .caveat, size: 22, weight: 600, anchor: .middle, tracking: 0, fill: "#20306e", m: StampAffine(a: 0.9976, b: -0.0698, c: 0.0698, d: 0.9976, tx: -12.08, ty: 14.11), fit: 216, length: nil)
        ]),
        "ht": Stamp(id: "ht", w: 440, h: 220, ink: "#d6454c", round: false, slots: [
            Slot(what: .date("{d1} {d2} {FRAF} {yyyy}"), x: 218, y: 124, font: .barlow, size: 30, weight: 500, anchor: .middle, tracking: 2, fill: "#d6454c", m: .identity, fit: 200, length: nil)
        ]),
        "py": Stamp(id: "py", w: 300, h: 300, ink: "#e03a3a", round: false, slots: [
            Slot(what: .date("{d1} {d2} {ES} {yyyy}"), x: 150, y: 166, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 2, fill: "#e03a3a", m: .identity, fit: 200, length: nil)
        ]),
        "dm": Stamp(id: "dm", w: 400, h: 270, ink: "#56709a", round: false, slots: [
            Slot(what: .date("{d}.{M}.{yy}"), x: 220, y: 194, font: .caveat, size: 34, weight: 600, anchor: .middle, tracking: 0, fill: "#1f3a8a", m: StampAffine(a: 0.9976, b: -0.0698, c: 0.0698, d: 0.9976, tx: -13.00, ty: 15.82), fit: 288, length: nil)
        ]),
        "ga": Stamp(id: "ga", w: 400, h: 230, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{yyyy} -{MM}- {d1} {d2}"), x: 200, y: 122, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 2, fill: "#2b2b2b", m: .identity, fit: 220, length: nil)
        ]),
        "so": Stamp(id: "so", w: 400, h: 240, ink: "#2b3fa8", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 200, y: 134, font: .barlow, size: 46, weight: 500, anchor: .middle, tracking: 2, fill: "#d1474e", m: .identity, fit: 200, length: nil)
        ]),
        "to": Stamp(id: "to", w: 400, h: 250, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{d1}{d2} {MON} {yyyy}"), x: 184, y: 142, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 2, fill: "#2b2b2b", m: .identity, fit: 180, length: nil)
        ]),
        "sc": Stamp(id: "sc", w: 360, h: 380, ink: "#1f3fae", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 180, y: 200, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#d1472b", m: .identity, fit: 250, length: nil),
            Slot(what: .date("{dd+30}-{MM+30}-{yy+30}"), x: 252, y: 114, font: .caveat, size: 44, weight: 600, anchor: .middle, tracking: 0, fill: "#7a2a1a", m: StampAffine(a: 0.9962, b: -0.0872, c: 0.0872, d: 0.9962, tx: -8.98, ty: 22.40), fit: 259, length: nil)
        ]),
        "gp": Stamp(id: "gp", w: 400, h: 240, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 180, y: 136, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#b8383a", m: .identity, fit: 170, length: nil)
        ]),
        "mq": Stamp(id: "mq", w: 400, h: 240, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 180, y: 136, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#a8303c", m: .identity, fit: 170, length: nil)
        ]),
        "gf": Stamp(id: "gf", w: 400, h: 240, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 180, y: 136, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#b8383f", m: .identity, fit: 170, length: nil)
        ]),
        "re": Stamp(id: "re", w: 400, h: 240, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 180, y: 136, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#b8383a", m: .identity, fit: 170, length: nil)
        ]),
        "yt": Stamp(id: "yt", w: 400, h: 240, ink: "#2b2b2b", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 180, y: 136, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#b8383a", m: .identity, fit: 170, length: nil)
        ]),
        "pf": Stamp(id: "pf", w: 360, h: 240, ink: "#2b4fae", round: false, slots: [
            Slot(what: .date("{d1} {d2} {FRAF} {yyyy}"), x: 180, y: 136, font: .barlow, size: 44, weight: 600, anchor: .middle, tracking: 1.5, fill: "#2b4fae", m: .identity, fit: 300, length: nil)
        ]),
        "nc": Stamp(id: "nc", w: 380, h: 240, ink: "#2b4fae", round: false, slots: [
            Slot(what: .date("{d_}  {FRAF}  {yyyy}"), x: 190, y: 132, font: .barlow, size: 44, weight: 600, anchor: .middle, tracking: 4, fill: "#2b4fae", m: .identity, fit: 250, length: nil)
        ]),
        "ai": Stamp(id: "ai", w: 400, h: 270, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{MON} {d1}{d2} {yyyy}"), x: 200, y: 142, font: .barlow, size: 28, weight: 600, anchor: .middle, tracking: 1, fill: "#1a1a1a", m: .identity, fit: 140, length: nil),
            Slot(what: .date("{Mon+30} {d+30} {yyyy+30}"), x: 262, y: 196, font: .caveat, size: 40, weight: 600, anchor: .middle, tracking: 0, fill: "#1f3a8a", m: StampAffine(a: 0.9994, b: -0.0349, c: 0.0349, d: 0.9994, tx: -6.68, ty: 9.26), fit: 288, length: nil)
        ]),
        "tv": Stamp(id: "tv", w: 420, h: 280, ink: "#2e2e2e", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 210, y: 156, font: .barlow, size: 44, weight: 600, anchor: .middle, tracking: 0, fill: "#2e2e2e", m: .identity, fit: 196, length: nil)
        ]),
        "nu": Stamp(id: "nu", w: 420, h: 260, ink: "#1d1d1d", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 210, y: 140, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 0, fill: "#1d1d1d", m: .identity, fit: 196, length: nil)
        ]),
        "ve": Stamp(id: "ve", w: 380, h: 236, ink: "#c8457a", round: false, slots: [
            Slot(what: .date("{d1} {d2} {ES} {yyyy}"), x: 190, y: 126, font: .barlow, size: 44, weight: 700, anchor: .middle, tracking: 2, fill: "#c8457a", m: .identity, fit: 200, length: nil)
        ]),
        "gl": Stamp(id: "gl", w: 412, h: 300, ink: "#3f73b8", round: false, slots: [
            Slot(what: .date("{d}  {DKd}   {yyyy}"), x: 206, y: 165, font: .barlow, size: 54, weight: 500, anchor: .middle, tracking: 1, fill: "#3f73b8", m: .identity, fit: 290, length: nil)
        ]),
        "sx": Stamp(id: "sx", w: 440, h: 270, ink: "#3d4fb0", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 228, y: 154, font: .barlow, size: 50, weight: 500, anchor: .middle, tracking: 0, fill: "#3d4fb0", m: .identity, fit: 211, length: nil)
        ]),
        "do": Stamp(id: "do", w: 360, h: 230, ink: "#d1342c", round: false, slots: [
            Slot(what: .date("{d1} {d2} {ES} {yyyy}"), x: 178, y: 126, font: .barlow, size: 46, weight: 500, anchor: .middle, tracking: 1, fill: "#d1342c", m: .identity, fit: 190, length: nil),
            Slot(what: .date("{dd+30}-{MM+30}-{yy+30}"), x: 200, y: 204, font: .caveat, size: 34, weight: 600, anchor: .middle, tracking: 0, fill: "#2c3c9a", m: StampAffine(a: 0.9986, b: -0.0523, c: 0.0523, d: 0.9986, tx: -10.40, ty: 10.75), fit: 259, length: nil)
        ]),
        "na": Stamp(id: "na", w: 300, h: 300, ink: "#2b2b33", round: false, slots: [
            Slot(what: .date("{yyyy} -{MM}- {dd}"), x: 150, y: 156, font: .barlow, size: 44, weight: 600, anchor: .middle, tracking: 0.5, fill: "#2b2b33", m: .identity, fit: 219, length: nil)
        ]),
        "gw": Stamp(id: "gw", w: 420, h: 240, ink: "#3b44b8", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {FRCG}  {yyyy}"), x: 210, y: 139, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 1, fill: "#3b44b8", m: .identity, fit: 236, length: nil)
        ]),
        "gy": Stamp(id: "gy", w: 400, h: 274, ink: "#5c5c58", round: false, slots: [
            Slot(what: .date("{yyyy}-{MM}-{dd}"), x: 214, y: 110, font: .caveat, size: 44, weight: 600, anchor: .middle, tracking: 0, fill: "#1f3c9a", m: StampAffine(a: 0.9986, b: -0.0523, c: 0.0523, d: 0.9986, tx: -5.46, ty: 11.35), fit: 288, length: nil)
        ]),
        "sb": Stamp(id: "sb", w: 420, h: 285, ink: "#4a9cc4", round: false, slots: [
            Slot(what: .date("{dd}  {MON}  {yyyy}"), x: 210, y: 146, font: .barlow, size: 36, weight: 500, anchor: .middle, tracking: 2, fill: "#4a9cc4", m: .identity, fit: 200, length: nil),
            Slot(what: .date("{d+30} {Mon+30} {yyyy+30}"), x: 230, y: 184, font: .caveat, size: 36, weight: 600, anchor: .middle, tracking: 0, fill: "#3b2a8c", m: StampAffine(a: 0.9976, b: -0.0698, c: 0.0698, d: 0.9976, tx: -12.27, ty: 16.49), fit: 302, length: nil)
        ]),
        "vu": Stamp(id: "vu", w: 400, h: 300, ink: "#2c3fa8", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 200, y: 172, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 1, fill: "#2c3fa8", m: .identity, fit: 230, length: nil)
        ]),
        "ky": Stamp(id: "ky", w: 360, h: 242, ink: "#6a52b8", round: false, slots: [
            Slot(what: .date("{dd} {MON}{yyyy}"), x: 180, y: 136, font: .barlow, size: 40, weight: 700, anchor: .middle, tracking: 0, fill: "#6a52b8", m: .identity, fit: 200, length: nil)
        ]),
        "fk": Stamp(id: "fk", w: 300, h: 300, ink: "#4a4a6a", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 150, y: 164, font: .barlow, size: 36, weight: 600, anchor: .middle, tracking: 0.5, fill: "#4a4a6a", m: .identity, fit: 190, length: nil)
        ]),
        "bs": Stamp(id: "bs", w: 420, h: 238, ink: "#262626", round: false, slots: [
            Slot(what: .date("{MON}  {d1} {d2}  {yyyy}"), x: 204, y: 142, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 1, fill: "#262626", m: .identity, fit: 190, length: nil)
        ]),
        "hk": Stamp(id: "hk", w: 420, h: 250, ink: "#4a3f9c", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 210, y: 143, font: .barlow, size: 58, weight: 700, anchor: .middle, tracking: 1, fill: "#4a3f9c", m: .identity, fit: 270, length: nil)
        ]),
        "km": Stamp(id: "km", w: 420, h: 262, ink: "#cf3046", round: false, slots: [
            Slot(what: .date("{dd}  {MON}  {yyyy}"), x: 208, y: 148, font: .barlow, size: 48, weight: 600, anchor: .middle, tracking: 1, fill: "#cf3046", m: .identity, fit: 280, length: nil)
        ]),
        "tm": Stamp(id: "tm", w: 420, h: 216, ink: "#d0485a", round: false, slots: [
            Slot(what: .date("{d1} {d2}.{MM}. {yyyy}"), x: 218, y: 128, font: .barlow, size: 50, weight: 600, anchor: .middle, tracking: 1, fill: "#d0485a", m: .identity, fit: 270, length: nil)
        ]),
        "sy": Stamp(id: "sy", w: 420, h: 244, ink: "#4a8fb0", round: false, slots: [
            Slot(what: .date("{d@ar} {SY} {yyyy@ar}"), x: 224, y: 160, font: .barlow, size: 38, weight: 600, anchor: .middle, tracking: 1, fill: "#4a8fb0", m: .identity, fit: 240, length: nil)
        ]),
        "bw": Stamp(id: "bw", w: 400, h: 292, ink: "#e0605e", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 200, y: 170, font: .barlow, size: 50, weight: 500, anchor: .middle, tracking: 1, fill: "#e0605e", m: .identity, fit: 280, length: nil)
        ]),
        "bf": Stamp(id: "bf", w: 420, h: 214, ink: "#2f6fe0", round: false, slots: [
            Slot(what: .date("{d}-{MM}-{yy}"), x: 230, y: 144, font: .caveat, size: 40, weight: 600, anchor: .middle, tracking: 0, fill: "#2a3fa8", m: StampAffine(a: 0.9994, b: -0.0349, c: 0.0349, d: 0.9994, tx: -4.89, ty: 8.11), fit: 302, length: nil)
        ]),
        "bt": Stamp(id: "bt", w: 300, h: 300, ink: "#3a3fb0", round: false, slots: [
            Slot(what: .date("{d}/{M}/{yy}"), x: 150, y: 186, font: .caveat, size: 40, weight: 600, anchor: .middle, tracking: 0, fill: "#1f2a8a", m: StampAffine(a: 0.9976, b: -0.0698, c: 0.0698, d: 0.9976, tx: -12.61, ty: 10.92), fit: 130, length: nil)
        ]),
        "ru": Stamp(id: "ru", w: 360, h: 220, ink: "#3c577c", round: false, slots: [
            Slot(what: .date("{dd}"), x: 85, y: 131, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 1.4, fill: "#3c577c", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{MM}"), x: 136, y: 131, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 1.4, fill: "#3c577c", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{yy}"), x: 184, y: 131, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 1.4, fill: "#3c577c", m: .identity, fit: 259, length: nil)
        ]),
        "vn": Stamp(id: "vn", w: 364, h: 246, ink: "#3c4fa0", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 180, y: 135, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#3c4fa0", m: .identity, fit: 220, length: nil)
        ]),
        "la": Stamp(id: "la", w: 360, h: 256, ink: "#d94f4a", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 224, y: 146, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 1, fill: "#3c4fa8", m: .identity, fit: 210, length: nil),
            Slot(what: .date("{d1+29} {d2+29}  {MON+29}  {yyyy+29}"), x: 232, y: 196, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 1, fill: "#3c4fa8", m: .identity, fit: 196, length: nil)
        ]),
        "mn": Stamp(id: "mn", w: 360, h: 252, ink: "#6a7125", round: false, slots: [
            Slot(what: .date("{dd} -{MON}- {yyyy}"), x: 166, y: 168, font: .barlow, size: 40, weight: 600, anchor: .middle, tracking: 1, fill: "#6a7125", m: .identity, fit: 178, length: nil)
        ]),
        "ae": Stamp(id: "ae", w: 360, h: 255, ink: "#3c577c", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 190.939, y: 144.199, font: .barlow, size: 36, weight: 600, anchor: .middle, tracking: 1, fill: "#3c577c", m: .identity, fit: 199, length: nil)
        ]),
        "my": Stamp(id: "my", w: 360, h: 310, ink: "#3c577c", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 182.182, y: 172.364, font: .barlow, size: 45.8182, weight: 500, anchor: .middle, tracking: 1.6, fill: "#3c577c", m: .identity, fit: 225, length: nil),
            Slot(what: .date("{dd+30}/{MM+30}/{yy+30}"), x: 160, y: 262, font: .caveat, size: 28, weight: 600, anchor: .middle, tracking: 0, fill: "#3c577c", m: StampAffine(a: 0.9986, b: -0.0523, c: 0.0523, d: 0.9986, tx: -13.49, ty: 8.73), fit: 259, length: nil)
        ]),
        "mk": Stamp(id: "mk", w: 360, h: 257, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 134.618, y: 145.985, font: .barlow, size: 48, weight: 500, anchor: .middle, tracking: 3.2, fill: "#1a1a1a", m: .identity, fit: 175, length: nil)
        ]),
        "kz": Stamp(id: "kz", w: 400, h: 226, ink: "#2f9a6a", round: false, slots: [
            Slot(what: .date("{dd} {MM} {yy} 7·"), x: 164, y: 126, font: .barlow, size: 50, weight: 600, anchor: .middle, tracking: 3, fill: "#2f9a6a", m: .identity, fit: 200, length: nil)
        ]),
        "il": Stamp(id: "il", w: 360, h: 232, ink: "#d94f3d", round: false, slots: [
            Slot(what: .date("{dd}. {MM}. {yyyy}"), x: 180, y: 120.649, font: .barlow, size: 42.8108, weight: 500, anchor: .middle, tracking: 1.6, fill: "#d94f3d", m: .identity, fit: 243, length: nil)
        ]),
        "xk": Stamp(id: "xk", w: 360, h: 251, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 169.091, y: 139.636, font: .barlow, size: 45.8182, weight: 500, anchor: .middle, tracking: 1.8, fill: "#1a1a1a", m: .identity, fit: 212, length: nil)
        ]),
        "md": Stamp(id: "md", w: 360, h: 244, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 141.565, y: 136.906, font: .barlow, size: 46.5882, weight: 500, anchor: .middle, tracking: 4, fill: "#d94f3d", m: .identity, fit: 175, length: nil)
        ]),
        "dz": Stamp(id: "dz", w: 360, h: 226, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{dd} {MONd} {yyyy}"), x: 180, y: 131, font: .barlow, size: 50, weight: 500, anchor: .middle, tracking: 3.2, fill: "#d94f3d", m: .identity, fit: 206, length: nil)
        ]),
        "ir": Stamp(id: "ir", w: 360, h: 279, ink: "#3c577c", round: false, slots: [
            Slot(what: .date("{jyyyy@fa}"), x: 136.364, y: 149.455, font: .barlow, size: 43.6364, weight: 700, anchor: .end, tracking: 0, fill: "#3c577c", m: .identity, fit: 259, length: nil),
            Slot(what: .date("/{jM@fa}/"), x: 139.636, y: 149.455, font: .barlow, size: 43.6364, weight: 700, anchor: .start, tracking: 0, fill: "#3c577c", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{jd_@fa}"), x: 257.455, y: 149.455, font: .barlow, size: 43.6364, weight: 700, anchor: .middle, tracking: 0, fill: "#3c577c", m: .identity, fit: 259, length: nil)
        ]),
        "in": Stamp(id: "in", w: 386, h: 216, ink: "#3c577c", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 193, y: 128, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 1.6, fill: "#d94f3d", m: .identity, fit: 212, length: nil)
        ]),
        "ye": Stamp(id: "ye", w: 390, h: 244, ink: "#3c577c", round: false, slots: [
            Slot(what: .date("{d1} {d2} {MON} {yyyy}"), x: 195, y: 134, font: .barlow, size: 38, weight: 600, anchor: .middle, tracking: 1, fill: "#d94f3d", m: .identity, fit: 210, length: nil)
        ]),
        "eg": Stamp(id: "eg", w: 382, h: 230, ink: "#1f1f1f", round: false, slots: [
            Slot(what: .date("{d@ar} {EG} {yyyy@ar}"), x: 191, y: 138, font: .barlow, size: 34, weight: 700, anchor: .middle, tracking: 0, fill: "#1f1f1f", m: .identity, fit: 230, length: nil)
        ]),
        "cv": Stamp(id: "cv", w: 330, h: 222, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{dd}.{MM}.{yy}"), x: 40, y: 146, font: .barlow, size: 44, weight: 500, anchor: .start, tracking: 3.6, fill: "#d94f3d", m: .identity, fit: 170, length: nil)
        ]),
        "er": Stamp(id: "er", w: 360, h: 263, ink: "#4a46a8", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 177.882, y: 148.235, font: .barlow, size: 46.5882, weight: 500, anchor: .middle, tracking: 3.4, fill: "#4a46a8", m: .identity, fit: 254, length: nil)
        ]),
        "ie": Stamp(id: "ie", w: 360, h: 230, ink: "#2f8a5a", round: false, slots: [
            Slot(what: .date("{d1}"), x: 97, y: 138, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 0, fill: "#2f8a5a", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{d2}"), x: 121, y: 138, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 0, fill: "#2f8a5a", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{MON}"), x: 168, y: 138, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1.4, fill: "#2f8a5a", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{yyyy}"), x: 247, y: 138, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 2, fill: "#2f8a5a", m: .identity, fit: 259, length: nil)
        ]),
        "sa": Stamp(id: "sa", w: 360, h: 181, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{hyyyy@ar}"), x: 101.854, y: 103.61, font: .barlow, size: 29.8537, weight: 700, anchor: .middle, tracking: 0, fill: "#1a1a1a", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{hHM}"), x: 189.659, y: 100.976, font: .barlow, size: 16.6829, weight: 700, anchor: .middle, tracking: 0, fill: "#1a1a1a", m: .identity, fit: 93, length: nil),
            Slot(what: .date("{hd@ar}"), x: 263.415, y: 103.61, font: .barlow, size: 29.8537, weight: 700, anchor: .middle, tracking: 0, fill: "#1a1a1a", m: .identity, fit: 259, length: nil)
        ]),
        "th": Stamp(id: "th", w: 392, h: 236, ink: "#5a3f9e", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 196, y: 128, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#5a3f9e", m: .identity, fit: 230, length: nil),
            Slot(what: .date("{dd+29} {MON+29} {yyyy+29}"), x: 210, y: 176, font: .barlow, size: 26, weight: 500, anchor: .middle, tracking: 1, fill: "#5a3f9e", m: .identity, fit: 180, length: nil)
        ]),
        "pk": Stamp(id: "pk", w: 296, h: 296, ink: "#1a1a1a", round: false, slots: [
            Slot(what: .date("{dd} {MON} {yyyy}"), x: 148, y: 162, font: .barlow, size: 40, weight: 600, anchor: .middle, tracking: 1, fill: "#1a1a1a", m: .identity, fit: 200, length: nil)
        ]),
        "kn": Stamp(id: "kn", w: 400, h: 214, ink: "#3e3aa8", round: false, slots: [
            Slot(what: .date("{MON}  {d1} {d2}  {yyyy}"), x: 200, y: 122, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#3e3aa8", m: .identity, fit: 270, length: nil)
        ]),
        "ph": Stamp(id: "ph", w: 360, h: 240, ink: "#d0505a", round: false, slots: [
            Slot(what: .date("{MON} {d1} {d2} {yyyy}"), x: 180, y: 124, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 1, fill: "#d0505a", m: .identity, fit: 230, length: nil)
        ]),
        "gt": Stamp(id: "gt", w: 400, h: 236, ink: "#1f1f1f", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 215, y: 126, font: .barlow, size: 36, weight: 500, anchor: .middle, tracking: 1, fill: "#b8333a", m: .identity, fit: 180, length: nil)
        ]),
        "co": Stamp(id: "co", w: 400, h: 266, ink: "#e2672e", round: false, slots: [
            Slot(what: .date("{dd} {ES}. {yyyy}"), x: 180, y: 148, font: .barlow, size: 46, weight: 500, anchor: .middle, tracking: 2, fill: "#e2672e", m: .identity, fit: 250, length: nil)
        ]),
        "bn": Stamp(id: "bn", w: 360, h: 344, ink: "#3a4fb8", round: false, slots: [
            Slot(what: .date("{d1} {d2}   {MON}   {yyyy}"), x: 180, y: 204, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#3a4fb8", m: .identity, fit: 250, length: nil)
        ]),
        "mh": Stamp(id: "mh", w: 300, h: 300, ink: "#2b3550", round: false, slots: [
            Slot(what: .date("{MON} {d1} {d2} {yyyy}"), x: 150, y: 160, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 0.6, fill: "#e2482e", m: .identity, fit: 200, length: nil)
        ]),
        "bm": Stamp(id: "bm", w: 400, h: 290, ink: "#d9584c", round: false, slots: [
            Slot(what: .date("{MON}  {d1} {d2}  {yyyy}"), x: 200, y: 164, font: .barlow, size: 38, weight: 500, anchor: .middle, tracking: 0.6, fill: "#d9584c", m: .identity, fit: 220, length: nil)
        ]),
        "ws": Stamp(id: "ws", w: 400, h: 270, ink: "#3a4a6a", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 200, y: 142, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#3a4a6a", m: .identity, fit: 210, length: nil)
        ]),
        "ck": Stamp(id: "ck", w: 400, h: 270, ink: "#2a2a2a", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 200, y: 150, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#2a2a2a", m: .identity, fit: 230, length: nil)
        ]),
        "vg": Stamp(id: "vg", w: 340, h: 360, ink: "#3a5ac0", round: false, slots: [
            Slot(what: .date("{MON}  {d1} {d2}  {yyyy}"), x: 176, y: 190, font: .barlow, size: 40, weight: 500, anchor: .middle, tracking: 1, fill: "#3a5ac0", m: .identity, fit: 230, length: nil),
            Slot(what: .date("{d+30}-{M+30}-{yy+30}"), x: 200, y: 121, font: .caveat, size: 34, weight: 600, anchor: .middle, tracking: 0, fill: "#2a2a6a", m: StampAffine(a: 0.9994, b: -0.0349, c: 0.0349, d: 0.9994, tx: -4.10, ty: 7.05), fit: 245, length: nil)
        ]),
        "vc": Stamp(id: "vc", w: 400, h: 262, ink: "#2b4fd0", round: false, slots: [
            Slot(what: .date("{MON}  {d1} {d2}  {yyyy}"), x: 210, y: 124, font: .barlow, size: 34, weight: 500, anchor: .middle, tracking: 1, fill: "#1a1a1a", m: .identity, fit: 210, length: nil),
            Slot(what: .date("{d+30} {Mon+30} {yyyy+30}"), x: 276, y: 182, font: .caveat, size: 34, weight: 600, anchor: .middle, tracking: 0, fill: "#2b4fd0", m: StampAffine(a: 0.9986, b: -0.0523, c: 0.0523, d: 0.9986, tx: -9.15, ty: 14.69), fit: 288, length: nil)
        ]),
        "bb": Stamp(id: "bb", w: 400, h: 290, ink: "#1f1f1f", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 200, y: 150, font: .barlow, size: 44, weight: 500, anchor: .middle, tracking: 1, fill: "#1f1f1f", m: .identity, fit: 210, length: nil)
        ]),
        "mz": Stamp(id: "mz", w: 340, h: 300, ink: "#3a3a48", round: false, slots: [
            Slot(what: .date("{yyyy} -{MM}- {d1} {d2}"), x: 170, y: 160, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 1, fill: "#3a3a48", m: .identity, fit: 230, length: nil)
        ]),
        "bz": Stamp(id: "bz", w: 300, h: 300, ink: "#2a3fd8", round: false, slots: [
            Slot(what: .date("{dd}/{MM}/{yy}"), x: 170, y: 112, font: .caveat, size: 32, weight: 600, anchor: .middle, tracking: 0, fill: "#3a2a8a", m: StampAffine(a: 0.9976, b: -0.0698, c: 0.0698, d: 0.9976, tx: -7.40, ty: 12.13), fit: 216, length: nil),
            Slot(what: .date("{dd+30}/{MM+30}/{yy+30}"), x: 166, y: 142, font: .caveat, size: 32, weight: 600, anchor: .middle, tracking: 0, fill: "#3a2a8a", m: StampAffine(a: 0.9976, b: -0.0698, c: 0.0698, d: 0.9976, tx: -9.50, ty: 11.93), fit: 216, length: nil)
        ]),
        "pg": Stamp(id: "pg", w: 400, h: 260, ink: "#3a3a3a", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 200, y: 176, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 1, fill: "#3a3a3a", m: .identity, fit: 260, length: nil)
        ]),
        "mu": Stamp(id: "mu", w: 400, h: 290, ink: "#2a2a2a", round: false, slots: [
            Slot(what: .date("{d1} {d2}  {MON}  {yyyy}"), x: 200, y: 136, font: .barlow, size: 42, weight: 500, anchor: .middle, tracking: 1, fill: "#2a2a2a", m: .identity, fit: 230, length: nil)
        ]),
        "kr": Stamp(id: "kr", w: 360, h: 360, ink: "#2a2a2a", round: false, slots: [
            Slot(what: .date("{yyyy} {MON} {dd}"), x: 26, y: 224, font: .barlow, size: 22, weight: 700, anchor: .start, tracking: 0.6, fill: "#2a2a2a", m: .identity, fit: 259, length: nil),
            Slot(what: .date("{yyyy+90} {MON+90} {dd+90}"), x: 26, y: 316, font: .barlow, size: 22, weight: 700, anchor: .start, tracking: 0.6, fill: "#2a2a2a", m: .identity, fit: 259, length: nil)
        ]),
    ]
}

# Tellus

The display font of wya?!. Every letter is a real place seen from above: a river bend, an oxbow lake, a crater lake, a dam, traced from satellite and aerial images and smoothed into one even, round-ended line. The w, y, a, ? and ! are the wya?! wordmark's own letters. Tellus is Latin for the Earth.

[CREDITS.md](CREDITS.md) lists the place behind every character, with its coordinates and the image it was traced from.

## Files

| Folder | What |
|---|---|
| `static/` | 12 OpenType (.otf) files: Thin, Light, Regular, Medium, SemiBold and Bold, each upright and italic. The app bundles Light, Regular and Medium. |
| `variable/` | `TellusVariable.ttf` and `TellusVariable-Italic.ttf`: one file each, any weight from 100 to 700. |

Use either the static files or the variable ones in a project, not both: they share the family name.

## Use

It is for big and stylistic text. Body and small text in the app stays in the system font (SF).

In SwiftUI, after adding the files to the target and listing them under `UIAppFonts` in Info.plist:

```swift
Text("where you at?!")
    .font(.custom("Tellus-Regular", size: 34, relativeTo: .largeTitle))
```

PostScript names: `Tellus-Thin`, `Tellus-Light`, `Tellus-Regular`, `Tellus-Medium`, `Tellus-SemiBold`, `Tellus-Bold`, and the same with `Italic` (`Tellus-Italic` for the regular italic). The variable files are `TellusVariable` and `TellusVariable-Italic`.

## What it covers

- Latin (every European language and Vietnamese), Greek, Cyrillic, Georgian and Armenian
- Figures, punctuation, currency signs, arrows, maths, degrees, stars, fractions, circled numbers, superscripts and subscripts, combining accents
- OpenType features: kerning, mark positioning, tabular figures (`tnum`), small capitals (`smcp`), fractions (`frac`), superiors and inferiors, and `ss01` (single-storey a, alternate y and w)

Scripts it doesn't draw (Arabic, Hebrew, the Indian scripts, Thai, Chinese, Japanese, Korean and others) fall back to the system font.

## Weights

The pen is 42, 78, 96, 114, 132 and 150 font units from Thin to Bold. Accents and dots keep the Regular gap at every weight, and letters whose holes would close in Bold use a slightly lighter pen.

## Licence

All rights reserved. The font may not be copied, used or redistributed outside wya?! without permission.

The traces come from NASA/USGS Landsat through NASA's *Your Name in Landsat* (public domain), Esri World Imagery (Esri, Maxar, Earthstar Geographics and the GIS user community) and OpenStreetMap (© OpenStreetMap contributors, ODbL); see CREDITS.md.

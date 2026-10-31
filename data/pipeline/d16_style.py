#!/usr/bin/env python3
"""D16: the Pins base map's MapLibre style in our palette, over the OpenMapTiles schema (OpenFreeMap's tiles while
building). Part 8.2's proposal: water #78aef8, land white, built-up grey #d7d2c7, roads black 50% (the one low-opacity
black), land use cream #fbf6f2, no green, no outlines, no shadows, no point-of-interest icons; place names and street
names in ink with a 2 px cream halo. Writes wya-pins-style-1.json.

Not yet (said in the book's D16 line): our own border layer per borders view (OSM's country lines stand in), the
relief (OpenFreeMap has no elevation tiles), Tellus and SF in the labels (the glyph server has Noto Sans)."""
import json, sys

WATER, LAND, BUILT, CREAM, INK = "#78aef8", "#ffffff", "#d7d2c7", "#fbf6f2", "#000000"
BUILDING = "#cdc7ba"
FONT = ["Noto Sans Regular"]
FONT_B = ["Noto Sans Bold"]

def z(*stops):
    """an exponential zoom curve: z(5, 0.5, 10, 1, 16, 4)"""
    out = ["interpolate", ["exponential", 1.4], ["zoom"]]
    for s in stops:
        out.append(s)
    return out

layers = [
    {"id": "land", "type": "background", "paint": {"background-color": LAND}},
    # land use and cover: cream, never green; ice white (the land's own)
    {"id": "landcover", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
     "filter": ["match", ["get", "class"], ["wood", "grass", "farmland", "wetland", "sand", "rock"], True, False],
     "paint": {"fill-color": CREAM}},
    {"id": "park", "type": "fill", "source": "openmaptiles", "source-layer": "park", "paint": {"fill-color": CREAM}},
    {"id": "landuse_other", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
     "filter": ["match", ["get", "class"], ["residential", "suburb", "neighbourhood", "quarter", "commercial", "industrial",
                                            "retail", "railway", "garages", "hospital", "school", "university", "college"], False, True],
     "paint": {"fill-color": CREAM}},
    # built-up: our grey
    {"id": "builtup", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
     "filter": ["match", ["get", "class"], ["residential", "suburb", "neighbourhood", "quarter", "commercial", "industrial",
                                            "retail", "railway", "garages", "hospital", "school", "university", "college"], True, False],
     "paint": {"fill-color": BUILT}},
    {"id": "aeroway", "type": "fill", "source": "openmaptiles", "source-layer": "aeroway", "minzoom": 11,
     "filter": ["match", ["geometry-type"], ["Polygon", "MultiPolygon"], True, False], "paint": {"fill-color": BUILT}},
    # water
    {"id": "water", "type": "fill", "source": "openmaptiles", "source-layer": "water",
     "filter": ["!=", ["get", "brunnel"], "tunnel"], "paint": {"fill-color": WATER}},
    {"id": "waterway", "type": "line", "source": "openmaptiles", "source-layer": "waterway",
     "filter": ["!=", ["get", "brunnel"], "tunnel"],
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": WATER, "line-width": z(8, 0.5, 14, 2, 18, 6)}},
    # buildings, a shade under the built-up grey, flat (no 3D, no outline)
    {"id": "building", "type": "fill", "source": "openmaptiles", "source-layer": "building", "minzoom": 13,
     "paint": {"fill-color": BUILDING}},
]

# roads: black 50%, widths by class, round, no casing; tunnels dashed lighter; rail a thin line
ROADS = [
    ("minor", ["minor", "service", "track", "path", "pedestrian"], 12, (12, 0.4, 16, 1.6, 19, 6)),
    ("secondary", ["secondary", "tertiary"], 8, (8, 0.4, 14, 1.4, 18, 7)),
    ("primary", ["primary", "trunk"], 6, (6, 0.5, 14, 1.8, 18, 9)),
    ("motorway", ["motorway"], 5, (5, 0.6, 14, 2.2, 18, 11)),
]
for name, classes, minz, w in ROADS:
    layers.append({"id": f"road_{name}", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                   "minzoom": minz,
                   "filter": ["all", ["match", ["get", "class"], classes, True, False],
                              ["match", ["geometry-type"], ["LineString", "MultiLineString"], True, False]],
                   "layout": {"line-cap": "round", "line-join": "round"},
                   # black 50% on open land at country zooms; white over the built-up grey (and the cream) close in, where
                   # the towns fill the screen (8.2: "roads white over grey and black 50% on open land")
                   "paint": {"line-color": ["interpolate", ["linear"], ["zoom"], 12.5, INK, 14, LAND],
                             "line-opacity": ["interpolate", ["linear"], ["zoom"],
                                              12.5, ["case", ["==", ["get", "brunnel"], "tunnel"], 0.25, 0.5],
                                              14, ["case", ["==", ["get", "brunnel"], "tunnel"], 0.6, 1]],
                             "line-width": z(*w)}})
layers.append({"id": "rail", "type": "line", "source": "openmaptiles", "source-layer": "transportation", "minzoom": 10,
               # main lines only (no sidings and yards: a station's fan of tracks was a black smear)
               "filter": ["all", ["match", ["get", "class"], ["rail", "transit"], True, False], ["!", ["has", "service"]],
                          ["!=", ["get", "brunnel"], "tunnel"]],
               "layout": {"line-join": "round"},
               "paint": {"line-color": INK, "line-opacity": 0.35, "line-width": z(10, 0.3, 16, 0.8, 19, 1.5)}})

# country lines (stand-in for our border layer per view): 0.5 pt black 50%, land only
layers.append({"id": "border", "type": "line", "source": "openmaptiles", "source-layer": "boundary",
               "filter": ["all", ["==", ["get", "admin_level"], 2], ["!=", ["get", "maritime"], 1]],
               "layout": {"line-join": "round"},
               "paint": {"line-color": INK, "line-opacity": 0.5, "line-width": 0.5}})

def label(lid, layer, flt, size, minz, font=FONT, line=False, maxz=None):
    l = {"id": lid, "type": "symbol", "source": "openmaptiles", "source-layer": layer, "minzoom": minz, "filter": flt,
         "layout": {"text-field": ["coalesce", ["get", "name:en"], ["get", "name"]], "text-font": font, "text-size": size,
                    "text-max-width": 8},
         "paint": {"text-color": INK, "text-halo-color": CREAM, "text-halo-width": 2}}
    if maxz: l["maxzoom"] = maxz
    if line:
        l["layout"]["symbol-placement"] = "line"
        l["layout"]["text-field"] = ["get", "name"]
    return l

layers += [
    label("street", "transportation_name", ["match", ["get", "class"], ["primary", "secondary", "tertiary", "minor", "trunk"], True, False],
          z(13, 10, 18, 14), 13, line=True),
    label("water_name", "water_name", ["match", ["geometry-type"], ["Point", "MultiPoint"], True, False], 12, 8),
    label("village", "place", ["match", ["get", "class"], ["village", "suburb", "neighbourhood", "quarter"], True, False], z(10, 10, 16, 14), 11),
    label("town", "place", ["==", ["get", "class"], "town"], z(8, 11, 14, 15), 8, FONT_B),
    label("city", "place", ["==", ["get", "class"], "city"], z(5, 12, 12, 18), 5, FONT_B),
]

style = {
    "version": 8,
    "name": "wya pins 1",
    "sources": {"openmaptiles": {"type": "vector", "url": "https://tiles.openfreemap.org/planet"}},
    "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
    "layers": layers,
}
out = sys.argv[1] if len(sys.argv) > 1 else "wya-pins-style-1.json"
json.dump(style, open(out, "w"), indent=1)
print(out, len(layers), "layers")

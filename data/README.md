# The map data

How the map files in `app/wya/Resources/Map` are made. The scripts are Python 3 with shapely and numpy.

## The world map (`world.wyam`, `world-meta.json`, `disputes.json`)

Built from the earlier wya?! app's own world data (`world.json` and `world-arcs.bin`, Natural Earth based; not in this repository):

    python3 pipeline/world_prep.py <old Map folder>         # world.wyam, world-meta.json, disputes.json
    python3 pipeline/world_continents.py <old Map folder>   # adds each place's continents to world-meta.json

`disputes.json` was then edited for the pieces added later (Sool, Western Sahara's Moroccan-held part), so the files in the app are the reference; running these again overwrites them.

## The de facto and disputed lines

The detailed tiles (`detail-100m.wyad`, `detail-500m.wyad`) came from the earlier app with Natural Earth's coarse lines for de facto borders. These scripts redraw those lines from OpenStreetMap's boundaries (`sources/osm`) so they are as detailed as every other border.

    python3 pipeline/nepieces.py <original detail-100m.wyad>              # nepieces.pkl: the data's own shape of every piece
    python3 pipeline/truth.py                                             # truth.pkl: the fine shape of every piece, in groups
    python3 pipeline/rebuild.py <original detail-100m.wyad> detail-100m.wyad 0.003
    python3 pipeline/rebuild.py <original detail-500m.wyad> detail-500m.wyad 0.01
    python3 pipeline/worldfix.py world.wyam world-meta.json world-new.wyam world-meta-new.json disputes.json

- `truth.py` holds every group: the places that keep what is left (the parents) and the pieces drawn from OpenStreetMap (the children), in the order that decides overlaps. A fine shape is kept within about 7 km of the data's own piece, so a source drawing a slightly different area never takes land from a place outside the group.
- `rebuild.py` changes only the tiles a group's pieces are in or reach; every other tile stays byte for byte as it was. The last number is the width of the thin slivers it cleans up, in degrees.
- `worldfix.py` redraws the same pieces on the world map, so the line doesn't jump when the map hands over from the world to the tiles.
- `positions.py` prints who holds each piece in each point of view, to check a change. `borderlen.py <tiles> <out.json>` lists every border by how finely it is drawn, to find coarse lines. `search.py` looks places up on Nominatim.

Where no finer source exists, the data's own line stays: the Green Line around the West Bank, Siachen, the Korean DMZ, the Belize and Suriname claims, the Southern Patagonian Ice Field, the Bhutan valleys, Baykonur, Junagadh and the Shebaa Farms. Bir Tawil, the edges of Western Sahara, Abyei's northern edge and the Ilemi Triangle are straight lines on the ground too.

## Flags (`flags-round.wyaf`)

    python3 pipeline/flags-render.py   # draws every flag as a square with Chromium (Playwright)
    python3 pipeline/flags-pack.py     # cuts them to circles and packs them for the app

## The reference data (`pipeline/reference/`)

The scripts that built the earlier app's reference data: country facts, cities, climate, daylight, holidays, rates,
advisories, UNESCO sites, Wikivoyage guides, region levels, image credits and the passport cover colours. They read
public sources (Wikidata, Wikipedia, Wikivoyage, Wikimedia Commons, the World Bank, GeoNames and others) and write the
JSON files the data server builds from (`server/build_api.py`). Set `WYA_CONTACT` to your contact address before running
any script that calls a public API; it goes into the User-Agent, as those services ask.

The earlier app's region, town, urban-area and things pipelines and its stamp builds are not in this repository; their
output is what the app keeps using until each is rebuilt.

## Towns (`towns-<file>.wyat`, `town-zones.json`)

A towns file is one place's towns: raw DEFLATE of JSON rows `[name, region, population, lat, lon, kind, GeoNames id, part of]` (kind 2 the capital, 1 a regional capital). The earlier app's 51,694 towns are merged with GeoNames `cities500` (every place over 500 people and every seat of an administrative division):

    python3 pipeline/d3_towns.py <old Towns folder> <GeoNames folder> <out>     # cities500.txt, admin1CodesASCII.txt
    python3 pipeline/d3_zones.py world.wyam world-meta.json <out> <old town-zones.json> <out>/town-zones.json --only-new <old Towns folder>

- The merge never re-keys: every earlier row stays exactly as it was; a GeoNames place joins only if its id is new, and not when one of its names matches an earlier row with no id within 15 km. Sections of a city (PPLX) are left out.
- `town-zones.json` lists, for every disputed piece and every place a view can move, the towns of each file that lie in it, so a place's towns follow the borders view. New towns are placed by the world map's outlines; a town of a file that can't hold the item (a border slip on the coarse outline) is left out.

## Countries' names in every language (`place-names.json`)

    python3 pipeline/d12_country_names.py <GeoNames folder> world-meta.json place-names.json   # countryInfo.txt, alternateNamesV2.txt

Search finds a country by any of these names starting with what was typed, after every match on its own names.

## Finer region levels (`<cc>-<level>.wyar`)

A region level is one file: "WYAR", a JSON head (the quantization, the units with their ids, names and codes, each unit's rings as arc indices) and the shared arcs as absolute quantized integers, raw DEFLATE. From geoBoundaries' TopoJSON:

    python3 pipeline/d2_level.py geoBoundaries-FRA-ADM5.topojson fr 5 fr-5.wyar 0.002 -5.5 41 10 51.5   # the box: metropolitan France
    python3 pipeline/d2_parents.py fr-5.wyar fr-4.wyar                                                    # each unit's parent, by the larger share of its area

Each shared arc is simplified once, so neighbouring units keep one border.

France's coarser levels on the communes' borders: each commune's arrondissement, department and region from INSEE's official code tables (v_commune, v_arrondissement, v_departement), then each level built from the finer one's arcs (a unit's border is the arcs its members use once), so every level shares the same lines:

    python3 pipeline/d2_insee.py fr-5.wyar fr-3.wyar fr-2.wyar fr-1.wyar <INSEE folder> <out>

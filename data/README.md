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

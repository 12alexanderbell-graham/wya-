# Credits

## Map

- **World shapes, the places and their disputes**: Natural Earth (public domain), with wya?!'s own fixes for the places and pieces it shows separately.
- **De facto and disputed lines in detail** (Ukraine's four regions and Crimea, Transnistria, Abkhazia and South Ossetia, Northern Cyprus and the UN buffer zone, Akrotiri and Dhekelia, Mount Athos, Somaliland and Sool, Western Sahara, Guantánamo Bay, Kashmir, Arunachal Pradesh, the Golan Heights, the UNDOF zone, Gaza, the West Bank's Areas A and B, the Halayib triangle, Abyei, the Essequibo, Olivenza): OpenStreetMap, © OpenStreetMap contributors, available under the Open Database License (ODbL), openstreetmap.org/copyright. The boundaries used are in `data/sources/osm`, fetched through polygons.openstreetmap.fr. Place names were looked up with Nominatim.
- **Time zones by point** (`timezones.wytz`, built by `data/pipeline/tz-pack.py`): [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder) release 2025b, from OpenStreetMap, © OpenStreetMap contributors, Open Database License (ODbL).

## Flags

- Round and square flags: [flag-icons](https://github.com/lipis/flag-icons), © 2013 Panayiotis Lipiridis, MIT licence (below).
- Flags flag-icons doesn't have (Abkhazia, South Ossetia, Transnistria, Northern Cyprus, Somaliland, Rapa Nui, Mount Athos, Bonaire, Saba, Sint Eustatius): Wikimedia Commons, public domain.

## Font

- Tellus: traced from NASA/USGS Landsat (*Your Name in Landsat*, public domain), Esri World Imagery (Esri, Maxar, Earthstar Geographics and the GIS user community) and OpenStreetMap (ODbL). Every character's place is in `fonts/Tellus/CREDITS.md`.

## Planets

- The planet, moon and night-sky textures in `app/wya/Resources/Cosmos` were carried over from the earlier wya?! build. Their source is being confirmed and will be credited here.

## Data server

- The server builds its travel data from GeoNames (CC BY 4.0), geoBoundaries (CC BY 4.0), Wikidata (CC0), Wikivoyage (CC BY-SA 3.0), Wikimedia Commons (credited per photo in the built `credits/` files), the World Bank (CC BY 4.0), CHELSA climate (CC BY 4.0) and UNESCO's World Heritage list. `server/build_api.py` says which file comes from where.

## MIT licence (flag-icons)

Copyright (c) 2013 Panayiotis Lipiridis

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

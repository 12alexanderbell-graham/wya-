# The wya?! data server

The travel data (country facts, climate, travel advisories, guides, listings, places,
cities, region shapes, photo credits, phrasebooks, routes, rates, heritage) lives here, not in
the app. The app asks for one country or one file at a time from one address.

## Running it

You don't have to do anything: when you press Run in Xcode, the scheme starts the server first
(Scheme → Edit Scheme → Run → Pre-actions, "Start the data server"). The first time, it builds
the data before it starts (under a minute); after that it starts at once. If anything the data
is built from has changed since (these scripts, `reference/data`), it rebuilds first; and a
server started by an older copy of `serve.py` is stopped and replaced, so a change here reaches
the app without anyone quitting anything.

By hand, from the wya?! folder in Terminal:

    python3 server/serve.py              # stays in the window, Ctrl-C stops it
    python3 server/build_api.py          # rebuilds the data after reference/data changes (about 20 s)

Check it's up: open http://localhost:8787/v1/manifest.json in Safari.
The background server's log is in `$TMPDIR/wya-data-server.log`.
To stop the background one: `pkill -f server/serve.py`.

## What the app does with it

- `src/api.js` holds the address: `http://localhost:8787/v1/`.
- If the server isn't there, the app carries on: every question answers "nothing". The region
  shapes and the sample's pictures come only from here since 24 Sep ("take all of the big files
  that have no need to be inside of the app"), so without the server the map has no regions and
  the sample's photographs show as plain grey.
- The Simulator reaches the Mac as `localhost`. A real iPhone can't reach it: that's what the
  real host below is for.

## Moving to a real server later

The built data is plain files in `server/public.nosync/v1/`. The `.nosync` keeps it out of
iCloud: each Mac builds its own copy, so the two never fight over 124 MB. Upload `v1/` to any static host (Cloudflare R2 or Pages, S3
with CloudFront, Netlify), with the `.gz` files served as `Content-Encoding: gzip`, and change
`API_BASE` in `src/api.js` to that address (https). The paths don't change.

## What's in it

`v1/manifest.json` lists every endpoint, what's in it and where it came from. In short:

| Path | What |
|---|---|
| `countries.json` | every place the app knows: code, name, continent, capital, flag |
| `country/{cc}.json` | facts, World Bank figures, price level, climate by month, daylight, advisories (Canada, US, UK), holidays, the country's guide, visa rules for its passport, airports, World Heritage |
| `guides/{cc}.json`, `listings/{cc}.json`, `places/{cc}.json` | Wikivoyage guides for every destination, See/Do/Eat/Drink/Sleep/Buy listings, destinations with a photo |
| `regions/{cc}.json`, `cities/{cc}.json` | regions and cities, with climate |
| `shapes/{cc}-{level}.js` | region shapes for the map |
| `credits/{xx}.json` | photo credits, split in 256 files by a hash of the file name |
| `phrasebooks.json`, `phrasebooks/{lang}.json` | phrasebooks |
| `routes.json`, `rates.json`, `heritage.json` | non-stop flight routes, exchange rates (a snapshot), every World Heritage site |
| `passports.json`, `passports/{name}.svg` or `.jpg` | the real passport covers: 72 drawn as vectors in the app's colours (`recolour.py`), 97 more as the Commons photograph the app used to carry; the index gives each cover's file and credit |
| `sample/photo/{key}.jpg`, `sample/clip/{key}.mp4`, `sample/cover/{key}.jpg` | the sample account's own pictures, clips and list covers (24 Sep: big files out of the app); `sample/{photo,clip,cover}.json` list the keys |

Standard library Python only, nothing to install. Works on the Mac's own `/usr/bin/python3`
(3.9) and newer.

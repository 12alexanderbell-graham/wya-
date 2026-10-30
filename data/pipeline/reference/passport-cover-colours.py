#!/usr/bin/env python3
"""Measure each passport cover's own colour, for server/recolour.py.

    python3 reference/tools/passport-cover-colours.py     # from the wya?! folder

Needs Playwright with Chromium (pip install playwright; playwright install chromium): each
original vector in reference/data/passport-vectors.json is drawn at 60 by 85, and the most
common colour family among its pixels, gold left out, is the cover's colour. Its lightness
is kept too, so print in the cover's own colour (an embossed crest) can be told from the
cover itself. Writes reference/data/passport-cover-colours.json. Run it again only when the
vectors change.
"""
import asyncio, base64, collections, colorsys, json, os, statistics, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'server'))
from recolour import family                       # the same families the recolouring uses
from playwright.async_api import async_playwright

SRC = os.path.join(ROOT, 'reference', 'data', 'passport-vectors.json')
OUT = os.path.join(ROOT, 'reference', 'data', 'passport-cover-colours.json')
SKIP = {'Maldives'}          # a photograph inside an SVG: nothing to recolour

async def main():
    d = json.load(open(SRC, encoding='utf-8'))
    out = {'_about': "The family (red, blue, green, purple, brown, ink) of each passport cover's own colour, and that colour's lightness, measured from the original vector drawn at 60 by 85 (the most common family of its pixels, gold left out). server/recolour.py reads this to put each cover in the app's colours. Made by reference/tools/passport-cover-colours.py. Maldives is left out: its file is a photograph inside an SVG."}
    async with async_playwright() as pw:
        br = await pw.chromium.launch()
        pg = await br.new_page(viewport={'width': 120, 'height': 170})
        for n in sorted(d):
            if n in SKIP: continue
            await pg.set_content('<body style="margin:0"><img id=i style="width:120px;height:170px" src="data:image/svg+xml;base64,%s"></body>' % base64.b64encode(d[n].encode()).decode())
            await pg.wait_for_function("document.getElementById('i').complete", timeout=20000)
            px = await pg.evaluate("""() => { const i = document.getElementById('i'); const c = document.createElement('canvas'); c.width = 60; c.height = 85;
              const x = c.getContext('2d'); x.drawImage(i, 0, 0, 60, 85); const d = x.getImageData(0, 0, 60, 85).data; const o = [];
              for (let k = 0; k < d.length; k += 4) if (d[k + 3] > 200) o.push([d[k], d[k + 1], d[k + 2]]); return o; }""")
            cnt = collections.Counter(family(tuple(p)) for p in px)
            top = [f for f, c in cnt.most_common(4) if f != 'gold'] or ['red']
            ls = [colorsys.rgb_to_hls(*(c / 255 for c in p))[1] for p in px if family(tuple(p)) == top[0]]
            out[n] = {'cover': top[0], 'l': round(statistics.median(ls), 3) if ls else None}
        await br.close()
    with open(OUT, 'w', encoding='utf-8') as f: json.dump(out, f, ensure_ascii=False, indent=1)
    print('%d covers measured -> %s' % (len(out) - 1, OUT))

if __name__ == '__main__':
    asyncio.run(main())

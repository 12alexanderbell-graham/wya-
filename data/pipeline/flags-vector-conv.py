# D14: every square and 4:3 flag as a PDF (a vector iOS draws natively), checked against Chromium's own render of the
# SVG: both drawn at 128 px, the mean colour difference per pixel reported; anything over the bar is listed for a fix
import json, os, io, struct, asyncio, base64, sys
import cairosvg, fitz
from PIL import Image, ImageChops, ImageStat
from playwright.async_api import async_playwright
d = open('/home/claude/wya-/app/wya/Resources/Flags/flags-round.wyaf', 'rb').read()
hl = struct.unpack('<I', d[8:12])[0]; R = json.loads(d[12:12 + hl])['flags']
ALIAS = {'x-akrotiri': 'gb', 'x-dhekelia': 'gb', 'x-ashmore-and-cartier-islands': 'au', 'x-coral-sea-islands': 'au'}
os.makedirs('pdf/1x1', exist_ok=True); os.makedirs('pdf/4x3', exist_ok=True); os.makedirs('cmp', exist_ok=True)
missing = []
jobs = []
for k in sorted(R):
    for kind, (w, h) in (('1x1', (128, 128)), ('4x3', (128, 96))):
        src = f'pkg/package/flags/{kind}/{ALIAS.get(k, k)}.svg'
        if not os.path.exists(src): src = f'wmcut/{kind}/{k}.svg'
        if not os.path.exists(src): missing.append((k, kind)); continue
        dst = f'pdf/{kind}/{k}.pdf'
        cairosvg.svg2pdf(url=src, write_to=dst, output_width=w, output_height=h)
        jobs.append((k, kind, src, dst, w, h))
async def chrome():
    out = {}
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for k, kind, src, dst, w, h in jobs:
            pg = await b.new_page(viewport={'width': w, 'height': h})
            uri = 'data:image/svg+xml;base64,' + base64.b64encode(open(src, 'rb').read()).decode()
            await pg.set_content(f'<html><body style="margin:0;background:white"><img src="{uri}" style="width:{w}px;height:{h}px;display:block"></body></html>')
            await pg.wait_for_timeout(20)
            out[(k, kind)] = Image.open(io.BytesIO(await pg.screenshot())).convert('RGB')
            await pg.close()
        await b.close()
    return out
ch = asyncio.run(chrome())
rows = []
for k, kind, src, dst, w, h in jobs:
    doc = fitz.open(dst); pix = doc[0].get_pixmap(matrix=fitz.Matrix(w / doc[0].rect.width, h / doc[0].rect.height), alpha=False)
    a = Image.frombytes('RGB', (pix.width, pix.height), pix.samples).resize((w, h))
    diff = ImageChops.difference(a, ch[(k, kind)])
    m = sum(ImageStat.Stat(diff).mean) / 3
    rows.append((m, k, kind, os.path.getsize(dst)))
    if m > 6 or k.startswith('x-'):
        both = Image.new('RGB', (w * 2 + 4, h), 'white'); both.paste(ch[(k, kind)], (0, 0)); both.paste(a, (w + 4, 0)); both.save(f'cmp/{kind}-{k}.png')
rows.sort(reverse=True)
print('converted', len(jobs), 'missing', len(missing), missing[:12])
print('worst', [(round(m, 1), k, kind) for m, k, kind, _ in rows[:15]])
print('over 6:', sum(1 for r in rows if r[0] > 6), 'total pdf bytes', sum(r[3] for r in rows))

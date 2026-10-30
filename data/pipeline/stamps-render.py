# THE STAMP ART PACK (Part 4.3.4, D8's existing 104): the old app's stamp SVGs (wya?! old/wya native/Resources/Stamps),
# drawn by Chromium at 360 px on their long side in their own inks (each stamp keeps its colours: red, blue, green,
# brown, black), on transparent, so the phone never draws SVG. stamps.wyaf: "WYAF", u32 1, u32 head length, JSON head
# {"size": 360, "flags": {id: [offset, length, width, height]}}, then the PNGs.
import json,os,io,re,struct,asyncio,base64,glob
from PIL import Image
from playwright.async_api import async_playwright
L=360
async def main():
    os.makedirs('png',exist_ok=True)
    async with async_playwright() as p:
        b=await p.chromium.launch(); pg=await b.new_page(device_scale_factor=1)
        for f in sorted(glob.glob('Stamps/stamp-*.svg')   # the earlier app's Resources/Stamps):
            k=os.path.basename(f)[6:-4]; t=open(f).read()
            vb=[float(x) for x in re.search(r'viewBox="([^"]+)"',t).group(1).replace(',',' ').split()]
            w,h=vb[2],vb[3]; s=L/max(w,h); W,H=round(w*s),round(h*s)
            await pg.set_viewport_size({'width':W,'height':H})
            uri='data:image/svg+xml;base64,'+base64.b64encode(t.encode()).decode()
            await pg.set_content(f'<html><body style="margin:0;background:transparent"><img src="{uri}" style="width:{W}px;height:{H}px;display:block"></body></html>')
            await pg.wait_for_timeout(30)
            await pg.screenshot(path=f'png/{k}.png',omit_background=True)
        await b.close()
if not os.path.isdir('png') or len(os.listdir('png'))<104: asyncio.run(main())
idx={}; blob=bytearray()
for f in sorted(glob.glob('png/*.png')):
    k=os.path.basename(f)[:-4]; im=Image.open(f).convert('RGBA')
    bio=io.BytesIO(); im.save(bio,'PNG',optimize=True); v=bio.getvalue()
    idx[k]=[len(blob),len(v),im.size[0],im.size[1]]; blob+=v
h=json.dumps({'size':L,'flags':idx},separators=(',',':')).encode()
open('stamps.wyaf','wb').write(b'WYAF'+struct.pack('<II',1,len(h))+h+blob)
print(len(idx),len(blob))

# D14: the SQUARE detailed flags (Part 17.4). The same sources as the round pack: flag-icons 7.2.3's 1x1 compositions
# (MIT) drawn by Chromium, uncut; the ten places flag-icons lacks come from the round pack's own square crops (Wikimedia
# Commons, public domain, cut square round their emblem). No circle adjustments (those exist only for the round set).
import json,os,io,struct,asyncio,base64
from PIL import Image
from playwright.async_api import async_playwright
S=264; OUT=132
d=open('app/wya/Resources/Flags/flags-round.wyaf','rb').read()
hl=struct.unpack('<I',d[8:12])[0]; head=json.loads(d[12:12+hl]); base=12+hl; R=head['flags']
FI='flag-icons/flags/1x1/'   # npm pack flag-icons@7.2.3
ALIAS={'x-akrotiri':'gb','x-dhekelia':'gb','x-ashmore-and-cartier-islands':'au','x-coral-sea-islands':'au'}
async def main():
    os.makedirs('sq',exist_ok=True)
    async with async_playwright() as p:
        b=await p.chromium.launch(); pg=await b.new_page(viewport={'width':S,'height':S},device_scale_factor=1)
        for k in sorted(R):
            src=FI+ALIAS.get(k,k)+'.svg'
            if not os.path.exists(src):
                o,n=R[k]; Image.open(io.BytesIO(d[base+o:base+o+n])).convert('RGBA').save(f'sq/{k}.png'); continue
            uri='data:image/svg+xml;base64,'+base64.b64encode(open(src,'rb').read()).decode()
            await pg.set_content(f'<html><body style="margin:0;background:transparent"><img src="{uri}" style="width:{S}px;height:{S}px;display:block"></body></html>')
            await pg.wait_for_timeout(40)
            await pg.screenshot(path=f'sq/{k}.png',omit_background=True)
        await b.close()
asyncio.run(main())
flags={}; blob=bytearray()
for k in sorted(R):
    im=Image.open(f'sq/{k}.png').convert('RGBA').resize((OUT,OUT),Image.LANCZOS)
    bio=io.BytesIO(); im.save(bio,'PNG',optimize=True); v=bio.getvalue()
    flags[k]=[len(blob),len(v)]; blob+=v
h=json.dumps({'size':OUT,'flags':flags},separators=(',',':')).encode()
open('flags-square.wyaf','wb').write(b'WYAF'+struct.pack('<II',1,len(h))+h+blob)
print(len(flags),len(blob))

# THE ROUND FLAGS, detailed. Sources: flag-icons 1x1 (MIT, Lipiridis), the square compositions of every flag with their
# full arms; the places it lacks from Wikimedia Commons (public domain flags). Drawn by Chromium. A rectangular flag is
# cut to a square around a chosen point (the emblem's side).
import json,os,asyncio,base64,sys
from playwright.async_api import async_playwright
S=264
m=json.load(open('flags/flagsv-round.json'))
FI='fi/flags/1x1/'
WM={'x-abk':'Flag_of_Abkhazia.svg','x-sos':'Flag_of_South_Ossetia.svg','x-pmr':'Flag_of_Transnistria_(state).svg',
    'x-ncy':'Flag_of_the_Turkish_Republic_of_Northern_Cyprus.svg','x-som':'Flag_of_Somaliland.svg',
    'x-rapa':'Flag_of_Rapa_Nui,_Chile.svg','x-athos':'Flag_of_Mount_Athos.svg','x-bq-bo':'Flag_of_Bonaire.svg',
    'x-bq-sa':'Flag_of_Saba.svg','x-bq-se':'Flag_of_Sint_Eustatius.svg'}
ALIAS={'x-akrotiri':'gb','x-dhekelia':'gb','x-ashmore-and-cartier-islands':'au','x-coral-sea-islands':'au'}
# where the square is cut from a wide flag: the x of its middle, 0 hoist .. 1 fly
CUT={'x-abk':0.25,'x-sos':0.5,'x-pmr':0.25,'x-ncy':0.4,'x-som':0.5,'x-rapa':0.5,'x-athos':0.5,'x-bq-bo':0.32,'x-bq-sa':0.5,'x-bq-se':0.5}
def source(k):
    if k in WM: return 'wm/'+WM[k],'rect'
    k2=ALIAS.get(k,k)
    if os.path.exists(FI+k2+'.svg'): return FI+k2+'.svg','sq'
    return None,None
async def main():
    os.makedirs('cr2',exist_ok=True)
    async with async_playwright() as p:
        b=await p.chromium.launch()
        pg=await b.new_page(viewport={'width':S,'height':S},device_scale_factor=1)
        for k in m:
            src,mode=source(k)
            if not src: print('no source',k); continue
            uri='data:image/svg+xml;base64,'+base64.b64encode(open(src,'rb').read()).decode()
            if mode=='sq':
                html=f'<img src="{uri}" style="width:{S}px;height:{S}px;display:block">'
            else:
                c=CUT.get(k,0.5)
                import re
                t=open(src).read()
                vb=re.search(r'viewBox="\s*([-\d.]+)[ ,]+([-\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)',t)
                wh=re.search(r'<svg[^>]*?width="([\d.]+)(?:px)?"[^>]*?height="([\d.]+)(?:px)?"',t)
                if wh: ar=float(wh.group(1))/float(wh.group(2))
                else: ar=float(vb.group(3))/float(vb.group(4))
                w=S*ar; left=min(0,max(S-w,S/2-c*w))
                html=(f'<div style="width:{S}px;height:{S}px;overflow:hidden;position:relative">'
                      f'<img src="{uri}" style="width:{w}px;height:{S}px;position:absolute;top:0;left:{left}px"></div>')
            await pg.set_content(f'<html><body style="margin:0;background:transparent">{html}</body></html>')
            await pg.wait_for_timeout(60)
            await pg.screenshot(path=f'cr2/{k}.png',omit_background=True)
        await b.close()
asyncio.run(main())

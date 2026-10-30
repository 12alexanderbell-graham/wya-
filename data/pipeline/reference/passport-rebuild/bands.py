import json, os, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
import trace as T
need=[n for n in json.load(open('/mnt/user-data/outputs/coa-need.json'))]
def load(u):
    f=[x for x in os.listdir('hi') if x.rsplit('.',1)[0]==u][0]
    raw=cv2.imread('hi/'+f, cv2.IMREAD_UNCHANGED)
    if raw.ndim==2: raw=cv2.cvtColor(raw,cv2.COLOR_GRAY2BGR)
    if raw.shape[2]==4:
        a=raw[...,3:4].astype(float)/255; raw=(raw[...,:3]*a+255*(1-a)).astype(np.uint8)
    rgb=cv2.cvtColor(raw,cv2.COLOR_BGR2RGB)
    return T.squared(rgb, T.CROP.get(u))
def bands(m):
    rows=m.sum(1)>2
    out=[]; y=0; H=len(rows)
    while y<H:
        if rows[y]:
            y0=y
            while y<H and (rows[y] or (y+6<H and rows[y:y+7].any())): y+=1
            cols=np.where(m[y0:y].sum(0)>0)[0]
            if len(cols) and y-y0>=4: out.append([int(y0),int(y),int(cols.min()),int(cols.max())])
        y+=1
    return out
if __name__ == "__main__":
    res={}
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',22)
    os.makedirs('bandsheets',exist_ok=True)
    for n in need:
        u=n.replace(' ','_')
        cov=load(u); m=T.print_mask(cov, T.LIMIT.get(u,0.075), fill=u in T.FILL, emboss=u in T.EMBOSS)
        b=bands(m); res[n]=b
        im=Image.fromarray(cov); d=ImageDraw.Draw(im)
        for i,(y0,y1,x0,x1) in enumerate(b):
            d.rectangle([x0,y0,x1,y1],outline=(0,255,255),width=2); d.text((4,y0),str(i),font=font,fill=(0,255,255))
        im.save('bandsheets/%s.jpg'%u,quality=80)
    json.dump(res,open('bands.json','w'))
    print('ok')

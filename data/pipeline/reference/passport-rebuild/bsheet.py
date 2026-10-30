import sys, io, json, cairosvg, numpy as np
from PIL import Image, ImageDraw, ImageFont
import build as Bd, bands as B
names=sys.argv[2:]; out=sys.argv[1]
W,H=240,341; cols=4
f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',14)
img=Image.new('RGB',(cols*(2*W+14),((len(names)+cols-1)//cols)*(H+22)),'#fbf6f2'); d=ImageDraw.Draw(img)
import os; os.makedirs('rebuilt',exist_ok=True)
for i,n in enumerate(names):
    svg=Bd.build(n,Bd.SPECS[n]); open('rebuilt/%s.svg'%n.replace(' ','_'),'w').write(svg)
    a=Image.fromarray(B.load(n.replace(' ','_'))).resize((W,H))
    b=Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(),output_width=W*2))).convert('RGB').resize((W,H),Image.LANCZOS)
    x=(i%cols)*(2*W+14); y=(i//cols)*(H+22)
    d.text((x,y+2),n,font=f,fill='black'); img.paste(a,(x,y+20)); img.paste(b,(x+W+4,y+20))
img.save(out,quality=88)

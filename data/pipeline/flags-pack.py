import json,io,struct,numpy as np
from PIL import Image,ImageDraw
m=json.load(open('flags/flagsv-round.json'))
OUT=132
# THE EMBLEMS THE CIRCLE CUT: these designs are square, made for a square, with the emblem near a corner; a circle cut
# it. Each is drawn smaller and pulled toward its emblem's side so the emblem sits inside the circle; the stripes and
# fields run on outward to fill the edges (each edge's own colours carried out). (x, y) is where the emblem sits on the
# square, s how big the square is drawn.
E={'om':(0.17,0.17,0.74),'mt':(0.14,0.14,0.78),'uy':(0.22,0.22,0.82),'fj':(0.74,0.6,0.8),'bm':(0.74,0.55,0.82),'fk':(0.72,0.55,0.84),'gs':(0.72,0.55,0.84),'ms':(0.74,0.5,0.84),'tc':(0.74,0.55,0.84),'ky':(0.74,0.55,0.84),'ai':(0.74,0.5,0.84),'vg':(0.74,0.55,0.84)}
def comp(k):
    im=np.asarray(Image.open('cr2/%s.png'%k).convert('RGBA'))
    big=im.shape[0]
    if k not in E: return Image.fromarray(im).resize((OUT,OUT),Image.LANCZOS)
    ex,ey,s=E[k]
    pad=big
    P=Image.fromarray(np.pad(im,((pad,pad),(pad,pad),(0,0)),mode='edge'))
    tx=-0.3*(ex-0.5); ty=-0.3*(ey-0.5)
    a=1/s; c0=pad+big*(0.5-(0.5+tx)/s); c1=pad+big*(0.5-(0.5+ty)/s)
    return P.transform((big,big),Image.AFFINE,(a,0,c0,0,a,c1),resample=Image.BICUBIC).resize((OUT,OUT),Image.LANCZOS)
if __name__=='__main__':
    flags={}; blob=bytearray()
    for k in sorted(m):
        bio=io.BytesIO(); comp(k).save(bio,'PNG',optimize=True); d=bio.getvalue()
        flags[k]=[len(blob),len(d)]; blob+=d
    head=json.dumps({'size':OUT,'flags':flags},separators=(',',':')).encode()
    open('flags-round.wyaf','wb').write(b'WYAF'+struct.pack('<II',1,len(head))+head+blob)
    print(len(flags), len(blob))
    S=110; ids=list(E)+['x-abk','x-som','x-pmr','x-athos','x-rapa','x-ncy']
    g=Image.new('RGB',(len(ids)*S,S),(225,225,225))
    for i,k in enumerate(ids):
        im=comp(k).resize((S-8,S-8),Image.LANCZOS)
        mk=Image.new('L',im.size,0); ImageDraw.Draw(mk).ellipse((0,0,S-9,S-9),fill=255); g.paste(im,(i*S+4,4),mk)
    g.save('emblems.png')

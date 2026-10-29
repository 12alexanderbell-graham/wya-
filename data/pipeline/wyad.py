import zlib,struct,json
def pack(path):
    d=open(path,'rb').read()
    assert d[:4]==b'WYDP'
    hl=struct.unpack_from('<I',d,8)[0]
    head=json.loads(d[12:12+hl]); base=12+hl
    return d,head,base
def tile(d,base,t):
    x,y,off,ln=t
    raw=zlib.decompress(d[base+off:base+off+ln],-15)
    assert raw[:4]==b'WYAD',raw[:4]
    hl=struct.unpack_from('<I',raw,8)[0]
    h=json.loads(raw[12:12+hl]); at=12+hl
    qx=round(x*1e5); qy=round(y*1e5)
    def nxt():
        nonlocal at
        z=0;s=0
        while True:
            b=raw[at]; at+=1
            z|=(b&0x7f)<<s
            if not b&0x80: break
            s+=7
        return (z>>1)^-(z&1)
    items=[]
    for key,counts in h['p']:
        rings=[]
        for n in counts:
            r=[]
            for _ in range(n):
                qx+=nxt(); qy+=nxt(); r.append((qx/1e5,qy/1e5))
            rings.append(r)
        items.append((key,rings))
    xl=[]
    for a,b,n in h.get('x',[]):
        l=[]
        for _ in range(n):
            qx+=nxt(); qy+=nxt(); l.append((qx/1e5,qy/1e5))
        xl.append((a,b,l))
    return h,items,xl

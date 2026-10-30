import zlib, json, struct
def read(path):
    raw=open(path,'rb').read()
    try: b=zlib.decompress(raw,-15)
    except Exception: b=raw
    jn=struct.unpack_from('<I',b,8)[0]
    h=json.loads(b[12:12+jn]); o=12+jn
    n=struct.unpack_from('<I',b,o)[0]; o+=4
    starts=struct.unpack_from('<%dI'%(n+1),b,o); o+=4*(n+1)
    tot=starts[n]
    xy=struct.unpack_from('<%di'%(2*tot),b,o)
    arcs=[[(xy[2*k],xy[2*k+1]) for k in range(starts[i],starts[i+1])] for i in range(n)]
    return h, arcs, raw[:2]!=b[:2]
def write(path, h, arcs, deflate=True):
    js=json.dumps(h,ensure_ascii=False,separators=(',',':')).encode()
    out=bytearray(b'WYAR')+struct.pack('<I',1)+struct.pack('<I',len(js))+js
    out+=struct.pack('<I',len(arcs))
    s=0; starts=[0]
    for a in arcs: s+=len(a); starts.append(s)
    out+=struct.pack('<%dI'%len(starts),*starts)
    for a in arcs:
        for x,y in a: out+=struct.pack('<ii',x,y)
    data=bytes(out)
    if deflate:
        c=zlib.compressobj(9,zlib.DEFLATED,-15); data=c.compress(data)+c.flush()
    open(path,'wb').write(data)

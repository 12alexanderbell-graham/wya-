import sys, struct, zlib
raw = zlib.decompress(open(sys.argv[1],'rb').read(), -15)
assert raw[:4]==b'WYTZ'
ver, nz = struct.unpack_from('<II', raw, 4); o = 12
names=[]
for _ in range(nz):
    l=raw[o]; o+=1; names.append(raw[o:o+l].decode()); o+=l
npoly=struct.unpack_from('<I',raw,o)[0]; o+=4
px=py=0
def v():
    global o
    z=0;s=0
    while True:
        b=raw[o]; o+=1; z|=(b&0x7f)<<s
        if not b&0x80: break
        s+=7
    return (z>>1)^-(z&1)
polys=[]
for _ in range(npoly):
    z,nr=struct.unpack_from('<HH',raw,o); o+=4
    rings=[]
    for _ in range(nr):
        n=struct.unpack_from('<I',raw,o)[0]; o+=4
        r=[]
        for _ in range(n):
            px+=v(); py+=v(); r.append((px/1e4,py/1e4))
        rings.append(r)
    polys.append((z,rings))
def inside(r,x,y):
    c=False; j=len(r)-1
    for i in range(len(r)):
        xi,yi=r[i]; xj,yj=r[j]
        if (yi>y)!=(yj>y) and x < (xj-xi)*(y-yi)/(yj-yi)+xi: c=not c
        j=i
    return c
def zone(lat,lon):
    for z,rings in polys:
        if sum(inside(r,lon,lat) for r in rings)%2: return names[z]
    return None
tests=[('Tokyo',35.68,139.69,'Asia/Tokyo'),('Tijuana',32.525,-117.03,'America/Tijuana'),('San Diego',32.72,-117.16,'America/Los_Angeles'),
 ('Baarle-Hertog',51.4378,4.9306,'Europe/Brussels'),('Baarle-Nassau',51.4456,4.9278,'Europe/Amsterdam'),('Kathmandu',27.7172,85.324,'Asia/Kathmandu'),
 ('Zurich',47.37,8.54,'Europe/Zurich'),('Atlantic',30.0,-40.0,None),('Munich',48.137,11.5755,'Europe/Berlin'),('Lisbon',38.72,-9.14,'Europe/Lisbon'),
 ('Shakhimardan',39.977,71.81,'Asia/Tashkent'),('Ciudad Juarez',31.69,-106.42,'America/Ciudad_Juarez'),('El Paso',31.76,-106.49,'America/Denver')]
bad=0
for n,la,lo,want in tests:
    got=zone(la,lo); ok=got==want; bad+= not ok
    print('PASS' if ok else 'FAIL', n, got, '' if ok else '(want %s)'%want)
print(len(names),'zones',npoly,'polygons', 'fails',bad)

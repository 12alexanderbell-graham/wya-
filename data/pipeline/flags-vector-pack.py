# D14 (Part 17.4): the square (1:1) and 4:3 flags as vectors, one PDF each (cairosvg from flag-icons 7.2.3's SVGs, MIT;
# the ten places it lacks from Wikimedia Commons, public domain, cut by tools/flags-vector-crop.py), checked against
# Chromium's render by tools/flags-vector-conv.py, packed into flags-vector.wyaf: "WYAF", u32 version 2, u32 head length,
# a JSON head {"square": {id: [offset, length]}, "wide": {...}}, then the PDFs. iOS draws them natively (CGPDFDocument).
import json, struct, os
idx = {'square': {}, 'wide': {}}; blob = bytearray()
for kind, name in (('1x1', 'square'), ('4x3', 'wide')):
    for f in sorted(os.listdir(f'pdf/{kind}')):
        d = open(f'pdf/{kind}/{f}', 'rb').read()
        idx[name][f[:-4]] = [len(blob), len(d)]; blob += d
h = json.dumps(idx, separators=(',', ':')).encode()
open('flags-vector.wyaf', 'wb').write(b'WYAF' + struct.pack('<II', 2, len(h)) + h + blob)
print(len(idx['square']), len(idx['wide']), len(blob))

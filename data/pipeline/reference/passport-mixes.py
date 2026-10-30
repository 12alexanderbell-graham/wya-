"""Plan row 136: each drawn passport cover's own colour and the closest mix of ours to it (sheet 3, 13 Oct 19:11), for
reference/data/passport-cover-mixes.json (it wrote svg-mixes.json; the data file is that, Maldives left out)."""
import json, re, io, sys, numpy as np, cairosvg
from PIL import Image
import mixes
import os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'server'))
from recolour import clean, rgb_of, PROP
GOLD = '#ffe04a'

def raster(svg, w=200):
    png = cairosvg.svg2png(bytestring=svg.encode('utf-8'), output_width=w)
    return np.array(Image.open(io.BytesIO(png)).convert('RGBA'))

def dominant(a):
    px = a[a[..., 3] > 200][:, :3].astype(int)
    q = (px // 12)
    keys, counts = np.unique(q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2], return_counts=True)
    k = keys[counts.argmax()]
    m = (q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]) == k
    return tuple(int(v) for v in np.median(px[m], 0))

def lab(rgb): return mixes.oklab(np.array(rgb, float) / 255)

def recolour_v2(svg, cover_rgb, cover_hex):
    cl = lab(cover_rgb)
    def sub(m):
        rgb = rgb_of(m.group(2))
        if rgb is None: return m.group(0)
        d = float(np.sqrt(((lab(rgb) - cl) ** 2).sum()))
        return m.group(1) + (cover_hex if d < 0.075 else GOLD)
    return PROP.sub(sub, svg)

if __name__ == '__main__':
    vec = json.load(open('passport-vectors.json')); out = {}
    for name in sorted(vec):
        svg = clean(vec[name])
        try:
            rgb = dominant(raster(svg))
        except Exception as x:
            print('FAIL', name, repr(x)[:100]); continue
        parts, hexs, err = mixes.best(rgb)
        new = recolour_v2(svg, rgb, hexs)
        open('work/%s.svg' % name.replace(' ', '_'), 'w').write(new)
        out[name] = {'drawn': '#%02x%02x%02x' % rgb, 'mix': parts, 'cover': hexs, 'err': round(err, 4)}
        print(name, out[name]['drawn'], parts, hexs, flush=True)
    json.dump(out, open('svg-mixes.json', 'w'), indent=1)

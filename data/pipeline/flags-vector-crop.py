# the ten flags flag-icons lacks (Wikimedia Commons, public domain), cut to 1:1 and 4:3 around the round pack's own
# points (tools/flags-render.py CUT: the x of the cut's middle, 0 hoist .. 1 fly), by rewriting the root viewBox
import re, os
CUT={'x-abk':0.25,'x-sos':0.5,'x-pmr':0.25,'x-ncy':0.4,'x-som':0.5,'x-rapa':0.5,'x-athos':0.5,'x-bq-bo':0.32,'x-bq-sa':0.5,'x-bq-se':0.5}
def num(s): return float(re.match(r'[-\d.]+', s).group(0))
os.makedirs('wmcut/1x1', exist_ok=True); os.makedirs('wmcut/4x3', exist_ok=True)
for k, c in CUT.items():
    t = open(f'wm/{k}.svg').read()
    m = re.search(r'<svg\b[^>]*>', t, re.S); tag = m.group(0)
    vb = re.search(r'viewBox="\s*([-\d.]+)[ ,]+([-\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)\s*"', tag)
    w = re.search(r'\swidth="([\d.]+)', tag); h = re.search(r'\sheight="([\d.]+)', tag)
    if vb: vx, vy, vw, vh = map(float, vb.groups())
    else: vx, vy, vw, vh = 0.0, 0.0, float(w.group(1)), float(h.group(1))
    for kind, ar in (('1x1', 1.0), ('4x3', 4 / 3)):
        nw = min(vw, vh * ar)
        x = min(max(vx + c * vw - nw / 2, vx), vx + vw - nw)
        nt = re.sub(r'\s(width|height|viewBox|preserveAspectRatio)="[^"]*"', '', tag)
        nt = nt[:-1].rstrip('/') + f' width="{nw:.4f}" height="{vh:.4f}" viewBox="{x:.4f} {vy:.4f} {nw:.4f} {vh:.4f}">'
        open(f'wmcut/{kind}/{k}.svg', 'w').write(t[:m.start()] + nt + t[m.end():])
    print(k, (vx, vy, vw, vh))

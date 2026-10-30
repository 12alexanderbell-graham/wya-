"""Plan row 136, part 2: a passport cover that Commons has only as a photograph, drawn as vectors from that photograph.
No AI and no hand drawing: the cover is found in the photo and squared up, its colour is measured and given as the
closest mix of ours (mixes.py, sheet 3's rule), and the print (crest, words, chip) is whatever differs from the cover
around it, traced with potrace into paths in our gold. Usage: python3 trace.py IMAGE NAME OUTDIR"""
import sys, json, cv2, numpy as np, potrace
import mixes   # reference/tools/mixes.py

W, H = 600, 852
GOLD = '#ffe04a'
# where finding the cover goes wrong, the cover's place in the photo, measured by eye (fractions: left, top, right,
# bottom); the whole photo for a scan edge to edge
CROP = {'Portugal': (0, 0, 1, 1), 'Senegal': (0, 0, 1, 1), "Côte_d'Ivoire": (0.548, 0.03, 0.978, 0.962)}
# where the print is faint (pressed into the cover, little gold) or the cover grainy, how far from the cover around it
# a colour must be to count as print (the usual 0.075)
# a solid gold medallion, where the cover around it is gold too (gold far from the cover's own is print however wide)
FILL = {'Ethiopia'}
# print pressed into the cover with little gold, found by its light alone
EMBOSS = {"Côte_d'Ivoire", 'Falkland_Islands', 'Uzbekistan'}
LIMIT = {'Uganda': 0.12, 'Guinea': 0.1, 'Finland': 0.05, 'Falkland_Islands': 0.06, "Côte_d'Ivoire": 0.04, 'Uzbekistan': 0.03, 'Mauritania': 0.055, 'Congo_(Kinshasa)': 0.055,
         'São_Tomé_and_Príncipe': 0.055, 'Saint_Lucia': 0.055, 'Palestine': 0.055, 'Nepal': 0.06, 'Pakistan': 0.06}


def lab_img(rgb):
    """OKLab of an RGB image (0..255), shape (h, w, 3)"""
    a = rgb.reshape(-1, 3).astype(float) / 255
    return mixes.oklab(a).reshape(rgb.shape)


def find_cover(rgb):
    """the cover's four corners in the photo, or None when the photo is the cover edge to edge"""
    h, w = rgb.shape[:2]
    L = lab_img(rgb)
    ring = np.concatenate([L[:4].reshape(-1, 3), L[-4:].reshape(-1, 3), L[:, :4].reshape(-1, 3), L[:, -4:].reshape(-1, 3)])
    bg = np.median(ring, 0)
    spread = np.median(np.sqrt(((ring - bg) ** 2).sum(1)))
    d = np.sqrt(((L - bg) ** 2).sum(2))
    mask = (d > max(0.08, spread * 3)).astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    cs, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cs: return None
    c = max(cs, key=cv2.contourArea)
    area = cv2.contourArea(c)
    if area > 0.93 * w * h or area < 0.15 * w * h: return None
    # what the ring shows is the cover itself (a scan edge to edge): what was found is its print, not the cover
    x, y, bw, bh = cv2.boundingRect(c)
    inside = rgb[y:y + bh, x:x + bw]
    if np.sqrt(((lab_img(np.uint8([[dominant(inside)]]))[0, 0] - bg) ** 2).sum()) < 0.07: return None
    hull = cv2.convexHull(c)
    for eps in (0.01, 0.02, 0.03, 0.05):
        q = cv2.approxPolyDP(hull, eps * cv2.arcLength(hull, True), True)
        if len(q) == 4:
            q = order(q.reshape(4, 2).astype(np.float32))
            # a sound four-sided cover: most of what was found, no side shorter than half the one facing it
            sides = [np.linalg.norm(q[i] - q[(i + 1) % 4]) for i in range(4)]
            if (cv2.contourArea(q) > 0.8 * area and min(sides[0], sides[2]) > 0.5 * max(sides[0], sides[2])
                    and min(sides[1], sides[3]) > 0.5 * max(sides[1], sides[3])):
                return q
    x, y, bw, bh = cv2.boundingRect(c)
    return np.float32([[x, y], [x + bw, y], [x + bw, y + bh], [x, y + bh]])


def order(p):
    s, d = p.sum(1), np.diff(p, axis=1).ravel()
    return np.float32([p[s.argmin()], p[d.argmin()], p[s.argmax()], p[d.argmax()]])


def squared(rgb, crop=None, inset=0.012):
    """the cover alone, W x H; `crop` (x0, y0, x1, y1 as fractions) overrides finding it"""
    h, w = rgb.shape[:2]
    if crop:
        x0, y0, x1, y1 = crop
        q = np.float32([[x0 * w, y0 * h], [x1 * w, y0 * h], [x1 * w, y1 * h], [x0 * w, y1 * h]])
    else:
        q = find_cover(rgb)
        if q is None: q = np.float32([[0, 0], [w, 0], [w, h], [0, h]])
    # a hair inside the edge, so the table or the page under it never shows at the rim
    c = q.mean(0); q = c + (q - c) * (1 - inset)
    M = cv2.getPerspectiveTransform(q, np.float32([[0, 0], [W, 0], [W, H], [0, H]]))
    return cv2.warpPerspective(rgb, M, (W, H), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)


def dominant(rgb):
    px = rgb.reshape(-1, 3).astype(int); q = px // 12
    k = q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]
    keys, n = np.unique(k, return_counts=True)
    return tuple(int(v) for v in np.median(px[k == keys[n.argmax()]], 0))


def print_mask(cov, t=0.075, k=61, fill=False, emboss=False):
    """what differs from the cover around it: the print. The cover around each point is the image with the print
    smoothed away (a wide median), so light falling across the photo is not taken for print."""
    small = cv2.resize(cov, (W // 3, H // 3), interpolation=cv2.INTER_AREA)
    around = cv2.resize(cv2.medianBlur(small, k // 3 | 1), (W, H), interpolation=cv2.INTER_CUBIC)
    a, b = lab_img(cv2.medianBlur(cov, 5)), lab_img(around)
    d = np.sqrt(((a - b) ** 2).sum(2))
    # and from the cover's own colour: the cover showing inside a big crest is cover, not print
    cl = lab_img(np.uint8([[dominant(cov)]]))[0, 0]
    dc = np.sqrt(((a - cl) ** 2).sum(2))
    if emboss:
        # print pressed into the cover with little or no gold: only its light, against the light around it
        d = np.abs(a[..., 0] - b[..., 0])
    m = ((d > t) & ((dc > 0.055) | emboss)).astype(np.uint8)
    if fill: m |= ((dc > 0.17) & (a[..., 2] > 0.06)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
    keep = np.zeros(n, bool); keep[1:] = st[1:, cv2.CC_STAT_AREA] >= 30
    m = keep[lab].astype(np.uint8)
    # never the rim: a photo's edge, its shadow or its wear is not print
    r = 16; m[:r] = 0; m[-r:] = 0; m[:, :r] = 0; m[:, -r:] = 0
    return m


def path_of(mask):
    bm = potrace.Bitmap(~mask.astype(bool))   # potracer traces the False pixels
    plist = bm.trace(turdsize=10, turnpolicy=potrace.POTRACE_TURNPOLICY_MINORITY, alphamax=1.0,
                     opticurve=True, opttolerance=0.3)
    f = lambda p: '%.1f %.1f' % (p.x, p.y)
    out = []
    for curve in plist:
        s = ['M' + f(curve.start_point)]
        for seg in curve.segments:
            if seg.is_corner: s.append('L%sL%s' % (f(seg.c), f(seg.end_point)))
            else: s.append('C%s %s %s' % (f(seg.c1), f(seg.c2), f(seg.end_point)))
        out.append(''.join(s) + 'Z')
    return ''.join(out)


def make(path, crop=None, t=None, name=None):
    crop = crop or CROP.get(name)
    t = t or LIMIT.get(name, 0.075)
    raw = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if raw.ndim == 2: raw = cv2.cvtColor(raw, cv2.COLOR_GRAY2BGR)
    if raw.shape[2] == 4:
        # a picture with see-through corners: on white, as Commons shows it
        a = raw[..., 3:4].astype(float) / 255
        raw = (raw[..., :3] * a + 255 * (1 - a)).astype(np.uint8)
    rgb = cv2.cvtColor(raw, cv2.COLOR_BGR2RGB)
    cov = squared(rgb, crop)
    m = print_mask(cov, t, fill=name in FILL, emboss=name in EMBOSS)
    # the cover's own colour: measured where there is no print
    drawn = dominant(cov[m == 0].reshape(-1, 1, 3))
    parts, hexs, err = mixes.best(drawn)
    d = path_of(m)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">'
           '<rect width="%d" height="%d" fill="%s"/><path fill="%s" fill-rule="evenodd" d="%s"/></svg>'
           % (W, H, W, H, W, H, hexs, GOLD, d))
    return svg, {'drawn': '#%02x%02x%02x' % drawn, 'mix': parts, 'cover': hexs, 'err': round(err, 4),
                 'print': round(float(m.mean()), 4)}, cov


if __name__ == '__main__':
    svg, info, cov = make(sys.argv[1])
    open(sys.argv[3] + '/' + sys.argv[2] + '.svg', 'w').write(svg)
    print(json.dumps(info))

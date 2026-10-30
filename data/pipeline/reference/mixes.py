"""each cover's colour as the closest mix of ours (sheet 3, 13 Oct 19:11): at most three of our twelve, our gradient
green #a9e448 and the stamps' purple #9b7fd4, in whole percents, mixed as the app mixes (CSS color-mix in srgb),
judged in OKLab"""
import numpy as np, itertools
OURS = {"cream": 0xfbf6f2, "beige-dark": 0xbcb8b6, "white": 0xffffff, "ink": 0x000000, "grey": 0xd7d2c7,
        "grey-dark": 0xa19e95, "lime": 0xd4e249, "blue": 0x78aef8, "teal": 0xb0e0cd, "yellow": 0xffe04a,
        "red": 0xd94f3d, "brown": 0xa9784f, "green": 0xa9e448, "purple": 0x9b7fd4}
names = list(OURS); C = np.array([[(v >> 16) & 255, (v >> 8) & 255, v & 255] for v in OURS.values()], float) / 255

def oklab(rgb):
    rgb = np.asarray(rgb, float)
    l = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
    lms = np.cbrt(l @ M1.T)
    M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
    return lms @ M2.T

# every mix: weights in whole percents over at most three colours
W = []
for a in range(0, 101):
    for b in range(0, 101 - a):
        W.append((a, b, 100 - a - b))
W = np.array(W, float) / 100                       # (5151, 3)
TRI = list(itertools.combinations(range(len(names)), 3))
MIX = np.concatenate([W @ C[list(t)] for t in TRI])  # (364*5151, 3)
LAB = oklab(MIX)
TRI_IDX = np.repeat(np.arange(len(TRI)), len(W)); W_IDX = np.tile(np.arange(len(W)), len(TRI))

def best(rgb255):
    t = oklab(np.array(rgb255, float) / 255)
    d = ((LAB - t) ** 2).sum(1)
    # a mix that needs fewer colours wins a near tie (within 0.0004)
    k = np.argsort(d)[:200]
    def n_used(i): return int((W[W_IDX[i]] > 0).sum())
    top = min(k, key=lambda i: (d[i] > d[k[0]] + 4e-4, n_used(i), d[i]))
    tri, w = TRI[TRI_IDX[top]], W[W_IDX[top]]
    parts = sorted([(names[c], int(round(x * 100))) for c, x in zip(tri, w) if x > 0], key=lambda p: -p[1])
    hexs = '#%02x%02x%02x' % tuple(int(round(v * 255)) for v in MIX[top])
    return parts, hexs, float(np.sqrt(d[top]))

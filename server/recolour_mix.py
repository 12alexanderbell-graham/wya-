"""Plan row 136: each passport cover in its own colour, the closest mix (at most three, judged in OKLab) of our
colours, our gradient green and the stamps' purple, and the print our gold on every cover. The mix is found once
(reference/tools/passport-mixes.py) and kept in reference/data/passport-cover-mixes.json; here every colour of a
drawing near the cover's own drawn colour becomes the mix, and every other colour (gold, white,
black, the crest's own colours) becomes our gold. Standard library only (build_api.py uses it)."""
import re
from recolour import PROP, rgb_of

GOLD = '#e4bf4c'   # row 136: the middle of the app's gold metal (our yellow, a third of our brown); the app lays its gold metal where this colour shows
NEAR = 0.075          # OKLab distance under which a colour is the cover's own


def _lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def oklab(rgb):
    r, g, b = (_lin(v) for v in rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def recolour_mix(svg, drawn_hex, cover_hex):
    """the drawing with its cover in `cover_hex` and its print in our gold; `drawn_hex` is the cover's colour as drawn"""
    c = oklab(rgb_of(drawn_hex))
    def sub(m):
        rgb = rgb_of(m.group(2))
        if rgb is None: return m.group(0)
        d = sum((a - b) ** 2 for a, b in zip(oklab(rgb), c)) ** 0.5
        return m.group(1) + (cover_hex if d < NEAR else GOLD)
    return PROP.sub(sub, svg)

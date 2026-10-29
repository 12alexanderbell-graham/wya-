"""wya?! passport covers in the app's own colours. Standard library only (build_api.py uses it).

Every colour in a cover belongs to a family (gold, brown, red, green, blue, purple, black, white, grey) and becomes
the app's colour for that family: red our red, blue our blue, green our green (lime), black ink. The cover's own
family is measured once, from the drawn cover (reference/tools/passport-cover-colours.py). The print, gold or white,
becomes our yellow where it reads (on red and on black); on a light cover (our blue, our green) it becomes black,
the way the app's blank passports already print on a light colour; on brown it is cream, since brown and yellow are
never a pair. Print in the cover's own colour, lighter or darker than the cover (an embossed crest), becomes the
print colour, or it would vanish. What the editors left in the files (metadata, their view settings, their
attributes) is dropped.
"""
import colorsys, re

PAL = {'red': '#d94f3d', 'yellow': '#ffe04a', 'blue': '#78aef8', 'lime': '#d4e249', 'teal': '#b0e0cd',
       'ink': '#000000', 'white': '#ffffff', 'grey': '#d7d2c7', 'cream': '#fbf6f2', 'brown': '#a9784f'}
NAMED = {'black': '#000000', 'white': '#ffffff', 'red': '#ff0000', 'gold': '#ffd700', 'yellow': '#ffff00',
         'green': '#008000', 'blue': '#0000ff', 'navy': '#000080', 'maroon': '#800000', 'gray': '#808080',
         'grey': '#808080', 'silver': '#c0c0c0', 'orange': '#ffa500', 'purple': '#800080', 'darkred': '#8b0000',
         'darkgreen': '#006400', 'goldenrod': '#daa520', 'darkgoldenrod': '#b8860b'}
COVER = {'brown': 'brown', 'red': 'red', 'blue': 'blue', 'green': 'lime', 'purple': 'blue', 'ink': 'ink',
         'gold': 'yellow', 'grey': 'grey', 'white': 'white'}
LIGHT = {'blue', 'lime', 'yellow', 'grey', 'white', 'teal'}
PROP = re.compile(r'((?:fill|stroke|stop-color|flood-color|color)\s*(?::|=\s*["\']))\s*'
                  r'(#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b|rgb\([^)]*\)|[a-zA-Z]+)')

def rgb_of(v):
    v = v.strip().lower()
    if v in NAMED: v = NAMED[v]
    m = re.fullmatch(r'#([0-9a-f]{3})', v)
    if m: return tuple(int(c * 2, 16) for c in m.group(1))
    m = re.fullmatch(r'#([0-9a-f]{6})', v)
    if m: return tuple(int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4))
    m = re.fullmatch(r'rgb\(\s*([\d.]+%?)\s*,\s*([\d.]+%?)\s*,\s*([\d.]+%?)\s*\)', v)
    if m:
        return tuple(int(round(float(x[:-1]) * 2.55)) if x.endswith('%') else int(float(x)) for x in m.groups())
    return None

def family(rgb):
    h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
    H = h * 360
    if l < 0.10: return 'ink'
    if l > 0.93: return 'white'
    if s < 0.15: return 'ink' if l < 0.35 else 'white' if l > 0.80 else 'grey'
    if 20 <= H < 70: return 'gold' if l >= 0.30 else 'brown'
    if H < 20 or H >= 330: return 'red'
    if H < 170: return 'green'
    if H < 255: return 'blue'
    return 'purple'

def clean(svg):
    """drop the editors' leftovers; if the result does not parse as XML, keep the file as it came"""
    import xml.dom.minidom
    out = re.sub(r'<metadata\b.*?</metadata>', '', svg, flags=re.S)
    out = re.sub(r'<sodipodi:namedview\b[^>]*/>', '', out, flags=re.S)
    out = re.sub(r'<sodipodi:namedview\b[^>]*>.*?</sodipodi:namedview>', '', out, flags=re.S)
    out = re.sub(r'\s(?:inkscape|sodipodi):[a-zA-Z-]+="[^"]*"', '', out)
    try:
        xml.dom.minidom.parseString(out.encode('utf-8'))
        return out
    except Exception:
        return svg

def recolour(svg, cover_family, cover_l=None):
    """the cover in our colours; returns (svg, the palette name of its cover)"""
    P = COVER.get(cover_family, 'red')
    light = P in LIGHT
    fg = 'ink' if light else 'cream' if P == 'brown' else 'yellow'
    def pal(rgb):
        f = family(rgb)
        if f == cover_family:
            if cover_l is not None and abs(colorsys.rgb_to_hls(*(c / 255 for c in rgb))[1] - cover_l) > 0.16:
                return PAL[fg]
            return PAL[P]
        if f == 'gold': return PAL[fg]
        if f in ('white', 'grey'): return PAL['ink'] if light else PAL[f]
        if f == 'ink': return PAL['ink']
        return PAL[COVER.get(f, 'red')]
    def sub(m):
        rgb = rgb_of(m.group(2))
        return m.group(1) + (pal(rgb) if rgb else m.group(2))
    return PROP.sub(sub, svg), P

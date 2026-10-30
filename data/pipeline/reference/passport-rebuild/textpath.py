"""Row 136, redone: a line of a passport cover's words as vector paths. The words are shaped with HarfBuzz (so Arabic
joins, Devanagari and Sinhala combine) in the Noto family, then each glyph's outline is turned into SVG path data.
`line(text, face, box)` fits the line to the box the photo shows: its height from the box, its width by letter spacing
(a wide-spaced AUSTRALIA) or by condensing a little when it runs over."""
import os, functools
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts')
FACES = {
    'sans': 'NotoSans-Regular.ttf', 'sans-b': 'NotoSans-Bold.ttf', 'sans-l': 'NotoSans-Light.ttf', 'sans-sb': 'NotoSans-SemiBold.ttf',
    'serif': 'NotoSerif-Regular.ttf', 'serif-b': 'NotoSerif-Bold.ttf', 'serif-i': 'NotoSerif-Italic.ttf', 'serif-bi': 'NotoSerif-BoldItalic.ttf',
    'arab': 'NotoNaskhArabic-Bold.ttf', 'ethi': 'NotoSansEthiopic-Bold.ttf', 'deva': 'NotoSansDevanagari-Bold.ttf',
    'sinh': 'NotoSansSinhala-Bold.ttf', 'taml': 'NotoSansTamil-Bold.ttf', 'hebr': 'NotoSansHebrew-Bold.ttf',
    'kore': '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc#1', 'kore-serif': '/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc#1',
}


@functools.lru_cache(None)
def font(face):
    p = FACES[face]
    idx = 0
    if '#' in p: p, idx = p.split('#'); idx = int(idx)
    if not p.startswith('/'): p = os.path.join(D, p)
    blob = hb.Blob.from_file_path(p)
    f = hb.Font(hb.Face(blob, idx))
    tt = TTFont(p, fontNumber=idx)
    return f, tt


def shaped(text, face):
    f, tt = font(face)
    buf = hb.Buffer(); buf.add_str(text); buf.guess_segment_properties()
    hb.shape(f, buf, {})
    return buf.glyph_infos, buf.glyph_positions, tt


def outline(text, face, tracking=0.0):
    """the line at 1 unit per font unit: (svg path data in font units, y up -> drawn flipped later, its bounds)"""
    infos, poss, tt = shaped(text, face)
    gs = tt.getGlyphSet(); order = tt.getGlyphOrder()
    pen = SVGPathPen(gs); bp = BoundsPen(gs)
    x = 0.0
    n = len(infos)
    for i, (inf, pos) in enumerate(zip(infos, poss)):
        name = order[inf.codepoint]
        t = (1, 0, 0, -1, x + pos.x_offset, -pos.y_offset)      # flip y: font up is svg down
        gs[name].draw(TransformPen(pen, t))
        gs[name].draw(TransformPen(bp, t))
        x += pos.x_advance + (tracking if i < n - 1 else 0)
    return pen.getCommands(), bp.bounds, x


def line(text, face, box, align='c', cap=None, squeeze=True, space=True):
    """`text` set into `box` (x0, y0, x1, y1 in the cover's 600 x 852): its ink as tall as the box (or `cap` of it),
    spaced out or condensed to the box's width. Returns svg path data in cover units."""
    x0, y0, x1, y1 = box
    upm = font(face)[1]['head'].unitsPerEm
    d, b, adv = outline(text, face)
    if not b: return ''
    ink_h = b[3] - b[1]
    k = (y1 - y0) * (cap or 1.0) / ink_h
    w = (b[2] - b[0]) * k
    target = x1 - x0
    tr = 0.0; sx = 1.0
    nchar = max(1, len(text) - 1)
    joined = face in ('arab', 'deva', 'sinh', 'taml')
    if space and w < target * 0.97 and len(text) > 1 and not joined:
        # spaced out to the photo's width (only for wide-spaced lines: never more than 0.6 em a letter)
        tr = min((target - w) / k / nchar, 0.6 * upm)
        d, b, adv = outline(text, face, tracking=tr)
        w = (b[2] - b[0]) * k
    elif w > target and squeeze:
        sx = target / w
        w = target
    wsx = w
    if align == 'c': ox = (x0 + x1) / 2 - wsx / 2
    elif align == 'l': ox = x0
    else: ox = x1 - wsx
    # the ink's bottom on the box's bottom, its top on the box's top
    oy = y0 + (y1 - y0) / 2 - ((b[1] + b[3]) / 2) * k
    tx = ox - b[0] * k * sx
    return '<path transform="matrix(%.5f 0 0 %.5f %.2f %.2f)" d="%s"/>' % (k * sx, k, tx, oy, d)

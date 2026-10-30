"""Row 136, redone: a country's coat of arms as gold line art for its passport cover. The arms' SVG is read with every
style resolved (svgelements), and each shape kept as a plain path: its dark parts (the outlines and the black lines
heraldic drawings are made of) become our gold, everything else the cover's own colour, so the arms read as the foil
on a real cover does. `place(svg, box, cover)` fits it into the box the photo shows."""
import io, re, numpy as np
from svgelements import SVG, Shape, Path, Color, Matrix
import mixes

GOLD = '#e4bf4c'   # row 136: the middle of the app's gold metal (our yellow, a third of our brown); the app lays its gold metal where this colour shows


def _lab(c):
    return mixes.oklab(np.array([c.red, c.green, c.blue], float) / 255)


def flat(svg_text):
    """every shape of the arms: (path d in the drawing's own units after its moves, fill Color|None, stroke Color|None,
    stroke width), and the drawing's bounds"""
    doc = SVG.parse(io.StringIO(svg_text), reify=True)
    cw, ch = float(doc.width or 0), float(doc.height or 0)
    out = []
    for e in doc.elements():
        if not isinstance(e, Shape): continue
        try:
            p = Path(e)
            if len(p) == 0: continue
            d = p.d()
        except Exception:
            continue
        fill = e.fill if (e.fill is not None and e.fill.value is not None and e.fill.alpha > 20) else None
        stroke = e.stroke if (e.stroke is not None and e.stroke.value is not None and e.stroke.alpha > 20) else None
        sw = float(e.stroke_width or 0) if stroke is not None else 0
        if fill is None and (stroke is None or sw <= 0): continue
        bb = p.bbox()
        if bb is None: continue
        # a shape mostly off the drawing's own canvas is not seen in it (a file's leftovers past its edge)
        if cw > 0 and ch > 0:
            a = max(1e-9, (bb[2] - bb[0]) * (bb[3] - bb[1]))
            ix = max(0, min(bb[2], cw) - max(bb[0], 0)) * max(0, min(bb[3], ch) - max(bb[1], 0))
            if ix / a < 0.5: continue
        out.append((d, fill, stroke, sw, bb))
    if not out: return [], None
    # the arms themselves: the biggest shape, grown by every shape that touches it (with a tenth of room), so a stray
    # dot or a far-off frame in the file does not shrink them
    area = lambda b: max(0, b[2] - b[0]) * max(0, b[3] - b[1])
    order = sorted(range(len(out)), key=lambda i: -area(out[i][4]))
    B = list(out[order[0]][4]); keep = {order[0]}
    changed = True
    while changed:
        changed = False
        pw, ph = (B[2] - B[0]) * 0.1, (B[3] - B[1]) * 0.1
        for i in order:
            if i in keep: continue
            b = out[i][4]
            if b[2] >= B[0] - pw and b[0] <= B[2] + pw and b[3] >= B[1] - ph and b[1] <= B[3] + ph:
                keep.add(i); B = [min(B[0], b[0]), min(B[1], b[1]), max(B[2], b[2]), max(B[3], b[3])]; changed = True
    out = [o for i, o in enumerate(out) if i in keep]
    return out, tuple(B)


def gold_or_cover(c, dark=0.42):
    """a colour of the arms: dark (its lines) to gold, light (its fields) to the cover"""
    L = _lab(c)[0]
    return GOLD if L < dark else None


def place(svg_text, box, cover, dark=0.42, line=1.1, big_share=0.12, solid=False):
    """the arms fitted into `box` (x0, y0, x1, y1), centred, kept in proportion; returns svg markup. Dark parts gold;
    light parts the cover's colour, each edged with a gold line `line` cover-units wide, so arms drawn in colour with
    no black outlines still come out as line art"""
    shapes, bb = flat(svg_text)
    if not shapes: return ''
    x0, y0, x1, y1 = box
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    k = min((x1 - x0) / w, (y1 - y0) / h)
    tx = (x0 + x1) / 2 - (bb[0] + w / 2) * k
    ty = (y0 + y1) / 2 - (bb[1] + h / 2) * k
    lw = line
    M = Matrix(k, 0, 0, k, tx, ty)
    num = re.compile(r'-?\d+\.\d+(?:e-?\d+)?')
    def moved(d):
        # into the cover's own units, at a tenth of a point (the files' long decimals cost a file ten times the size)
        return num.sub(lambda m: ('%.1f' % float(m.group(0))).rstrip('0').rstrip('.'), (Path(d) * M).d())
    parts = []
    big = big_share * w * h
    if solid:
        # SOLID ARMS: where the cover's own crest is a gold silhouette, the arms' fields are gold and their dark lines
        # are cut into it in the cover's colour
        for d, fill, stroke, sw, sb in shapes:
            d = moved(d)
            a = 'd="%s"' % d
            if fill is not None: a += ' fill="%s"' % (cover if gold_or_cover(fill, dark) else GOLD)
            else: a += ' fill="none"'
            if stroke is not None and sw > 0:
                a += ' stroke="%s" stroke-width="%.4g"' % (cover if gold_or_cover(stroke, dark) else GOLD, sw * k)
            parts.append('<path %s/>' % a)
        return '<g>%s</g>' % ''.join(parts)
    for d, fill, stroke, sw, sb in shapes:
        # a dark shape that covers much of the arms is a silhouette under the details (a falcon's body, a black
        # backing): drawn as its outline, or the arms come out as one gold blob
        large = (sb[2] - sb[0]) * (sb[3] - sb[1]) > big
        d = moved(d)
        sw = sw * k
        if fill is not None and gold_or_cover(fill, dark) and not large:
            a = 'd="%s" fill="%s"' % (d, GOLD)
        elif fill is not None:
            a = 'd="%s" fill="%s" stroke="%s" stroke-width="%.4g" stroke-linejoin="round"' % (d, cover, GOLD, lw)
        else:
            a = 'd="%s" fill="none"' % d
        if stroke is not None and sw > 0:
            a = a.replace(' stroke="%s" stroke-width="%.4g" stroke-linejoin="round"' % (GOLD, lw), '')
            a += ' stroke="%s" stroke-width="%.4g"' % (GOLD, max(sw, lw * 0.8))
        parts.append('<path %s/>' % a)
    return '<g>%s</g>' % ''.join(parts)

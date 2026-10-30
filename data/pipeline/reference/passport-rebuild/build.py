"""Row 136, redone (16 Oct evening, after his "they all look glitched"): each photographed passport cover rebuilt as a
clean vector. The cover in its mixed colour; the country's arms as gold line art (emblem.py) where the photo has them;
the cover's own words, read off the photo, typeset in Noto and turned into paths (textpath.py) in the boxes the photo
shows them in (bands.json, measured from the photo); the chip symbol. Nothing traced except where a cover is plain
geometry (Brazil's arc and stars are drawn as geometry here)."""
import json, math, os, numpy as np
import textpath as tp, emblem

W, H = 600, 852
GOLD = '#e4bf4c'   # row 136: the middle of the app's gold metal (our yellow, a third of our brown); the app lays its gold metal where this colour shows
COA = '/home/claude/coanpm/x/package/dist/coats/'
COA2 = '/home/claude/pp/coa_commons/'
BANDS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bands.json')))
INFO = {}
for p in ('aa', 'ab', 'ac', 'ad'):
    for k, v in json.load(open('/tmp/claude-0/full_%s.jpg.json' % p)).items(): INFO[k.replace('_', ' ')] = v


def box(name, b):
    """a band's box (x0, y0, x1, y1): a band's index, several bands' indices joined, or a box written out"""
    bs = BANDS[name]
    if isinstance(b, int): y0, y1, x0, x1 = bs[b]; return (x0, y0, x1, y1)
    if isinstance(b, list): return (min(bs[i][2] for i in b), min(bs[i][0] for i in b), max(bs[i][3] for i in b), max(bs[i][1] for i in b))
    return tuple(b)


def sym(bx):
    """the box made symmetric about the cover's middle (a punched hole or a shadow widened one side)"""
    x0, y0, x1, y1 = bx
    half = min(W / 2 - x0, x1 - W / 2)
    return (W / 2 - half, y0, W / 2 + half, y1)


def chip(bx, cover, centre=None):
    """the e-passport symbol: a gold rounded box, a circle and a line through it in the cover's colour"""
    x0, y0, x1, y1 = bx
    h = y1 - y0; w = h * 1.55
    cx = centre if centre is not None else (x0 + x1) / 2
    cy = (y0 + y1) / 2
    lw = h * 0.1
    return ('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s"/>' % (cx - w / 2, y0, w, h, h * 0.12, GOLD)
            + '<path d="M%.1f %.1fH%.1fM%.1f %.1fH%.1f" stroke="%s" stroke-width="%.2f" fill="none"/>' % (cx - w / 2 + lw, cy, cx - h * 0.22, cx + h * 0.22, cy, cx + w / 2 - lw, cover, lw)
            + '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="%.2f"/>' % (cx, cy, h * 0.22, cover, lw))


def star(cx, cy, r, rot=-90):
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * 0.4
        a = math.radians(rot + i * 36)
        pts.append('%.1f,%.1f' % (cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return '<polygon points="%s" fill="%s"/>' % (' '.join(pts), GOLD)


def emblem_svg(code):
    for d in (COA2, COA):
        p = os.path.join(d, code + '.svg')
        if os.path.exists(p): return open(p, encoding='utf-8').read()
    return None


def build(name, spec):
    cover = INFO[name]['cover']
    out = ['<rect width="%d" height="%d" fill="%s"/>' % (W, H, cover)]
    for it in spec['items']:
        k = it[0]
        if k == 't':
            _, b, text, face = it[:4]
            opt = it[4] if len(it) > 4 else {}
            bx = box(name, b)
            if opt.get('sym'): bx = sym(bx)
            if opt.get('pad'): p = opt['pad']; bx = (bx[0] + p[0], bx[1] + p[1], bx[2] + p[2], bx[3] + p[3])
            lines = text if isinstance(text, list) else text.split('\n')
            faces = face if isinstance(face, list) else [face] * len(lines)
            fr = opt.get('fr') or [1 / len(lines)] * len(lines)
            gap = opt.get('gap', 0.18)
            y = bx[1]; hh = bx[3] - bx[1]
            for t, f, q in zip(lines, faces, fr):
                lh = hh * q
                lb = (bx[0], y + lh * gap / 2, bx[2], y + lh - lh * gap / 2) if len(lines) > 1 else (bx[0], y, bx[2], y + lh)
                out.append(tp.line(t, f, lb, align=opt.get('align', 'c'), squeeze=opt.get('squeeze', True),
                                   space=opt.get('space', len(lines) == 1)))
                y += lh
        elif k == 'e':
            bx = box(name, it[1])
            opt = it[2] if len(it) > 2 else {}
            svg = emblem_svg(spec['coa'])
            if svg: out.append(emblem.place(svg, bx, cover, dark=opt.get('dark', 0.42), line=opt.get('line', 1.1), big_share=opt.get('big', 0.12), solid=spec.get('solid', False)))
        elif k == 'c':
            bx = box(name, it[1]); opt = it[2] if len(it) > 2 else {}
            out.append(chip(bx, cover, centre=W / 2 if opt.get('centre') else None))
        elif k == 'raw':
            out.append(it[1].replace('{cover}', cover))
        elif k == 'l':
            svg = emblem_svg(spec['logo'])
            if svg: out.append(emblem.place(svg, box(name, it[1]), cover, big_share=10))
        elif k == 'raw_fn':
            out.append(globals()[it[1] + '_medallion'](box(name, it[2]) if not (isinstance(it[2], tuple)) else it[2], cover))
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d"><g fill="%s">%s</g></svg>'
            % (W, H, W, H, GOLD, ''.join(out)))


def circle_through(pts):
    """the circle through points (x, y) by least squares"""
    A = np.array([[2 * x, 2 * y, 1] for x, y in pts]); b = np.array([x * x + y * y for x, y in pts])
    cx, cy, c = np.linalg.lstsq(A, b, rcond=None)[0]
    return cx, cy, math.sqrt(c + cx * cx + cy * cy)


def brazil_art():
    cx, cy, r = circle_through([(241, 40), (164, 120), (112, 200), (79, 280), (53, 400), (51, 460), (62, 560), (85, 640), (123, 720)])
    arc = '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="6"/>' % (cx, cy, r, GOLD)
    stars = ''.join(star(x, y, s) for x, y, s in [(232, 403, 21), (325, 493, 21), (148, 494, 21), (199, 574, 14), (232, 658, 21)])
    return arc + stars


SPECS = {
    'Abkhazia': {'coa': 'Abkhazia', 'items': [('t', 0, 'Аԥсны\nАбхазия', 'sans-b'), ('e', 1), ('t', 2, 'АТӘЫЛАУАҨШӘҞӘЫ', 'sans-b'), ('t', 3, 'ПАСПОРТ', 'sans-b')]},
    'Australia': {'coa': 'AU', 'items': [('e', 0), ('t', 1, 'AUSTRALIA', 'sans-l'), ('t', 2, 'PASSPORT', 'sans-l'), ('c', 3)]},
    'Bahrain': {'coa': 'BH', 'items': [('t', 0, 'مملكة البحرين', 'arab'), ('t', 1, 'KINGDOM OF BAHRAIN', 'serif'), ('e', 2),
                                      ('t', 3, 'جواز سفر', 'arab'), ('t', 4, 'PASSPORT', 'serif'), ('c', 5)]},
    'Benin': {'coa': 'BJ', 'items': [('t', 0, 'Communauté Economique', 'serif-b'), ('t', 1, "des Etats de l’Afrique de l’Ouest", 'serif-b'),
                                    ('t', 2, '(CEDEAO / ECOWAS)', 'serif-b'), ('t', 3, 'REPUBLIQUE DU BENIN', 'serif-b'), ('e', 4),
                                    ('t', 5, ['PASSEPORT', 'PASSPORT'], ['serif-b', 'serif-bi']), ('c', (262, 738, 338, 776), {'centre': True})]},
    'Bolivia': {'coa': 'BO', 'items': [('t', 0, 'COMUNIDAD ANDINA', 'serif'), ('t', 1, 'ESTADO', 'serif'), ('t', 2, 'PLURINACIONAL DE', 'serif'),
                                      ('t', 3, 'BOLIVIA', 'serif-b'), ('e', 4), ('t', 5, 'PASAPORTE', 'serif'), ('t', 6, 'PASSPORT', 'serif'), ('c', 7)]},
    'Brazil': {'coa': None, 'items': [('raw', brazil_art()), ('t', (352, 44, 538, 75), 'REPÚBLICA', 'sans-b', {'align': 'r'}),
                                      ('t', (274, 91, 538, 118), 'FEDERATIVA DO', 'sans-b', {'align': 'r'}),
                                      ('t', (270, 128, 538, 188), 'BRASIL', 'sans-b', {'align': 'r'}),
                                      ('t', (332, 726, 538, 752), 'PASSAPORTE', 'sans-b', {'align': 'r'}),
                                      ('t', (333, 764, 540, 794), 'MERCOSUL', 'sans-b', {'align': 'r'}), ('c', (52, 751, 118, 791))]},
    'Bulgaria': {'coa': 'BG', 'items': [('t', 0, 'РЕПУБЛИКА', 'sans'), ('t', 1, 'БЪЛГАРИЯ', 'sans'), ('t', 2, 'REPUBLIC OF BULGARIA', 'sans'),
                                       ('e', 3), ('t', 4, 'ПАСПОРТ', 'sans'), ('t', 5, 'PASSPORT', 'sans')]},
    'Burkina Faso': {'coa': 'BF', 'items': [('t', 0, 'COMMUNAUTE ECONOMIQUE DES', 'serif'), ('t', 1, "ETATS DE L’AFRIQUE DE L’OUEST", 'serif'),
                                           ('t', 2, 'BURKINA FASO', 'serif-b'), ('e', 3), ('t', 4, 'PASSEPORT', 'serif-b'), ('t', 5, 'PASSPORT', 'serif-b'), ('c', 6)]},
    'Cape Verde': {'coa': 'CV', 'items': [('t', 0, 'REPÚBLICA', 'serif-b'), ('t', 1, 'DE', 'serif-b'), ('t', 2, 'CABO VERDE', 'serif-b'), ('e', 3),
                                         ('t', 4, 'PASSAPORTE', 'serif-b')]},
    'Chad': {'coa': 'TD', 'items': [('t', (90, 25, 510, 105), 'جمهورية تشاد', 'arab'), ('t', (150, 112, 450, 150), 'REPUBLIC OF CHAD', 'serif-b'),
                                   ('e', (60, 227, 540, 637)), ('t', (180, 690, 420, 740), 'PASSEPORT', 'serif-b'), ('t', (190, 760, 410, 828), 'جواز سفر', 'arab')]},
    'Chile': {'coa': 'CL', 'items': [('t', 0, 'REPÚBLICA DE CHILE', 'sans'), ('e', 1), ('t', 2, 'PASAPORTE', 'sans'), ('t', 3, 'PASSPORT', 'sans'), ('c', 4)]},
    'Comoros': {'coa': 'KM', 'items': [('t', 0, 'UNION DES COMORES', 'sans-b'), ('t', 1, 'جمهورية القمر المتحدة', 'arab'), ('e', 2),
                                      ('t', 3, 'PASSEPORT', 'sans-b'), ('t', 4, 'جواز', 'arab')]},
}


def ethiopia_medallion(bx, cover):
    """Ethiopia's cover: a solid gold disc with the star drawn in lines of the cover's colour"""
    x0, y0, x1, y1 = bx
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2; r = min(x1 - x0, y1 - y0) / 2
    pts = [(cx + r * 0.78 * math.cos(math.radians(-90 + i * 144)), cy + r * 0.78 * math.sin(math.radians(-90 + i * 144))) for i in range(5)]
    star = 'M' + 'L'.join('%.1f %.1f' % p for p in pts) + 'Z'
    rays = ''.join('M%.1f %.1fL%.1f %.1f' % (cx + r * 0.35 * math.cos(math.radians(-54 + i * 72)), cy + r * 0.35 * math.sin(math.radians(-54 + i * 72)),
                                            cx + r * 0.9 * math.cos(math.radians(-54 + i * 72)), cy + r * 0.9 * math.sin(math.radians(-54 + i * 72))) for i in range(5))
    return ('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (cx, cy, r, GOLD)
            + '<path d="%s%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>' % (star, rays, cover, r * 0.05))


SPECS.update({
    'Congo (Brazzaville)': {'coa': 'CG', 'items': [('t', 0, ['COMMUNAUTÉ ÉCONOMIQUE', 'ET MONÉTAIRE'], 'serif'), ('t', 1, 'DE L’AFRIQUE CENTRALE', 'serif'),
                            ('t', 2, 'RÉPUBLIQUE DU CONGO', 'serif'), ('e', [3, 4]), ('t', 5, 'PASSEPORT', 'serif'), ('c', 6)]},
    'Congo (Kinshasa)': {'coa': 'CD', 'items': [('t', (64, 103, 536, 199), ['République Démocratique', 'du Congo'], 'serif'), ('e', 1),
                         ('t', (178, 666, 422, 730), 'PASSEPORT', 'serif'), ('c', 3)]},
    'Costa Rica': {'coa': 'CR', 'items': [('t', 0, 'REPUBLICA', 'serif-b'), ('t', 1, 'DE', 'serif-b'), ('t', 2, 'COSTA RICA', 'serif-b'),
                   ('t', 3, 'AMERICA CENTRAL', 'serif-b'), ('e', [4, 5]), ('t', 6, 'PASAPORTE', 'serif-b'), ('t', 7, 'PASSPORT', 'serif-b')]},
    'Cuba': {'coa': 'CU', 'items': [('t', 0, 'REPUBLICA DE CUBA', 'serif-b'), ('e', 1), ('t', 2, 'PASAPORTE', 'serif-b')]},
    'Cyprus': {'coa': 'CY', 'items': [('t', (52, 16, 300, 85), ['ΕΥΡΩΠΑΪΚΗ ΕΝΩΣΗ', 'AVRUPA BİRLİĞİ', 'EUROPEAN UNION'], 'sans-b', {'align': 'l'}),
               ('t', (53, 98, 367, 169), ['ΚΥΠΡΙΑΚΗ ΔΗΜΟΚΡΑΤΙΑ', 'KIBRIS CUMHURİYETİ', 'REPUBLIC OF CYPRUS'], 'sans-b', {'align': 'l'}),
               ('e', (116, 244, 250, 430)), ('t', (140, 490, 240, 556), ['ΔΙΑΒΑΤΗΡΙΟ', 'PASAPORT', 'PASSPORT'], 'sans-b'), ('c', 3)]},
    'Czechia': {'coa': 'CZ', 'items': [('t', (118, 104, 468, 136), 'ČESKÁ REPUBLIKA', 'sans-b'), ('e', (138, 160, 418, 491)),
                ('t', 2, 'CESTOVNÍ', 'sans-b'), ('t', 3, 'PAS', 'sans-b')]},
    "Côte d'Ivoire": {'coa': 'CI', 'items': [('t', [0, 1], 'COMMUNAUTÉ ÉCONOMIQUE DES', 'serif', {'sym': 1}),
                      ('t', 2, 'ETATS DE L’AFRIQUE DE L’OUEST', 'serif', {'sym': 1}), ('t', 3, '(CEDEAO)', 'serif', {'sym': 1}),
                      ('t', 4, 'RÉPUBLIQUE', 'serif', {'sym': 1}), ('t', 5, 'DE', 'serif', {'sym': 1}), ('t', 6, 'CÔTE D’IVOIRE', 'serif', {'sym': 1}),
                      ('e', 7), ('t', 8, 'PASSEPORT', 'serif', {'sym': 1}), ('t', 9, 'PASSPORT', 'serif', {'sym': 1}),
                      ('t', 10, 'PASAPORTE', 'serif', {'sym': 1}), ('c', 11, {'centre': True})]},
    'Djibouti': {'coa': 'DJ', 'items': [('t', 0, 'جمهورية جيبوتي', 'arab'), ('t', 1, 'RÉPUBLIQUE DE DJIBOUTI', 'serif'), ('e', 2),
                 ('t', 3, 'جواز سفر', 'arab'), ('t', 4, 'PASSEPORT', 'serif'), ('c', 5)]},
    'Dominica': {'coa': 'DM', 'items': [('t', (150, 88, 300, 146), ['Caribbean', 'Community'], 'sans-sb', {'align': 'l'}),
                 ('raw', '<rect x="310" y="138" width="260" height="4" fill="#e4bf4c"/>'), ('e', 1),
                 ('t', 2, 'COMMONWEALTH OF', 'sans', {'align': 'l'}), ('t', 3, 'DOMINICA', 'sans', {'align': 'l'}),
                 ('t', (65, 645, 300, 712), 'PASSPORT', 'sans', {'align': 'l'}), ('c', (445, 652, 529, 704))]},
    'Dominican Republic': {'coa': 'DO', 'items': [('t', 0, 'REPÚBLICA', 'sans-b'), ('t', 1, 'DOMINICANA', 'sans-b'), ('t', 2, 'PASAPORTE', 'sans-b'),
                           ('t', 3, 'PASSPORT', 'sans-b'), ('e', 4), ('c', 5)]},
    'Eritrea': {'coa': 'ER', 'items': [('t', 0, 'ERITREA', 'serif-b'), ('t', (138, 160, 280, 200), 'ኤርትራ', 'ethi', {'align': 'l'}),
                ('t', (320, 160, 449, 200), 'إرتريا', 'arab', {'align': 'r'}), ('e', 2), ('t', 3, 'PASSPORT', 'serif-b'),
                ('t', (138, 711, 260, 740), 'ፓስፖርት', 'ethi', {'align': 'l'}), ('t', (320, 708, 447, 742), 'جواز سفر', 'arab', {'align': 'r'})]},
    'Eswatini': {'coa': 'SZ', 'items': [('t', 0, ['Kingdom of Swaziland', 'Royaume de Swaziland'], 'sans-b'), ('e', 1),
                 ('t', 2, 'PASSPORT', 'sans-b'), ('t', 3, 'PASSEPORT', 'sans-b')]},
    'Ethiopia': {'coa': None, 'items': [('t', 0, ['የኢትዮጵያ ፌዴራላዊ', 'ዲሞክራሲያዊ ሪፐብሊክ'], 'ethi'), ('t', 1, 'FEDERAL DEMOCRATIC REPUBLIC', 'serif-b'),
                 ('t', 2, 'OF ETHIOPIA', 'serif-b'), ('raw_fn', 'ethiopia', 3), ('t', 4, 'ፓስፖርት', 'ethi'), ('t', 5, 'PASSPORT', 'serif-b')]},
    'Falkland Islands': {'coa': 'GB', 'items': [('t', (130, 180, 470, 210), 'BRITISH PASSPORT', 'serif'), ('e', (118, 240, 482, 600)),
                         ('t', (80, 630, 520, 660), 'COLONY OF THE FALKLAND ISLANDS', 'serif')]},
    'Finland': {'coa': 'FI', 'items': [('t', (180, 58, 420, 130), ['Euroopan unioni', 'Europeiska unionen'], 'sans'), ('e', (210, 184, 390, 430)),
                ('t', (150, 510, 450, 544), 'SUOMI · FINLAND', 'sans'), ('t', (262, 604, 338, 632), 'Passi', 'sans'),
                ('t', (266, 644, 334, 672), 'Pass', 'sans'), ('c', (270, 750, 330, 784))]},
    'Gabon': {'coa': 'GA', 'items': [('t', 0, 'REPUBLIQUE', 'sans-b'), ('t', 1, 'GABONAISE', 'sans-b'), ('e', 2), ('t', 3, 'PASSEPORT', 'sans-b'),
              ('t', 4, 'PASSPORT', 'sans-b'), ('c', 5)]},
    'Germany': {'coa': 'DE', 'items': [('t', 0, 'EUROPÄISCHE UNION', 'sans'), ('t', 1, 'BUNDESREPUBLIK', 'sans'), ('t', 2, 'DEUTSCHLAND', 'sans'),
                ('e', 3), ('t', 4, 'REISEPASS', 'sans-b'), ('t', 5, 'PASSPORT', 'sans'), ('t', 6, 'PASSEPORT', 'sans'), ('c', 7)]},
    'Ghana': {'coa': 'ECOWAS', 'items': [('t', 0, ['ECONOMIC COMMUNITY OF', 'WEST AFRICAN STATES', '(ECOWAS)'], 'serif'),
              ('t', 1, ['COMMUNAUTE ECONOMIQUE DES', 'ETATS DE L’AFRIQUE DE L’OUEST', '(CEDEAO)'], 'serif'), ('t', 2, 'REPUBLIC OF GHANA', 'serif'),
              ('e', 3), ('t', 4, 'PASSPORT', 'serif'), ('t', 5, 'PASSEPORT', 'serif')]},
    'Grenada': {'coa': 'GD', 'items': [('t', 0, 'GRENADA', 'serif'), ('e', 1), ('t', 2, 'PASSPORT', 'serif')]},
    'Guinea': {'coa': 'ECOWAS', 'items': [('t', 0, ['COMMUNAUTE ECONOMIQUE DES', 'ETATS DE L’AFRIQUE DE L’OUEST', '(CEDEAO / ECOWAS)'], 'serif'),
               ('t', 2, 'REPUBLIQUE DE GUINEE', 'serif'), ('e', (150, 262, 450, 620)), ('t', (170, 654, 430, 684), 'PASSEPORT', 'serif'), ('c', 4)]},
})


def central_america(bx, cover, focus):
    """Central America from Natural Earth (public domain, 1:110m, the one geopandas carried): the countries' outlines in
    gold, `focus` (Honduras, Nicaragua) filled, fitted into the box"""
    import shapefile
    r = shapefile.Reader(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ne', 'naturalearth_lowres.shp'))
    want = {'GTM', 'BLZ', 'SLV', 'HND', 'NIC', 'CRI', 'PAN', 'MEX'}
    shapes = [(rec[3], sh) for rec, sh in zip(r.records(), r.shapes()) if rec[3] in want]
    lon0, lon1, lat0, lat1 = -92.5, -77.0, 7.0, 18.5
    x0, y0, x1, y1 = bx
    kx = math.cos(math.radians((lat0 + lat1) / 2))
    s = min((x1 - x0) / ((lon1 - lon0) * kx), (y1 - y0) / (lat1 - lat0))
    ox = (x0 + x1) / 2 - (lon1 - lon0) * kx * s / 2; oy = (y0 + y1) / 2 - (lat1 - lat0) * s / 2
    def P(lo, la): return '%.1f %.1f' % (ox + (lo - lon0) * kx * s, oy + (lat1 - la) * s)
    out = ['<clipPath id="ca"><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/></clipPath><g clip-path="url(#ca)">' % (x0, y0, x1 - x0, y1 - y0)]
    for iso, sh in shapes:
        pts = sh.points; parts = list(sh.parts) + [len(pts)]
        d = ''.join('M' + 'L'.join(P(*pts[i]) for i in range(parts[j], parts[j + 1])) + 'Z' for j in range(len(parts) - 1))
        fill = GOLD if iso == focus else cover
        out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="2.4" stroke-linejoin="round"/>' % (d, fill, GOLD))
    out.append('</g>')
    return ''.join(out)


def crescent_star(bx):
    """Libya's (and Turkey's kind of) crescent and star, as geometry: the crescent from two circles, the star five-pointed"""
    x0, y0, x1, y1 = bx
    h = y1 - y0; cy = (y0 + y1) / 2
    R = h * 0.5; cx = x0 + R
    r2 = R * 0.8; c2 = cx + R * 0.32
    # where the two circles meet
    d = c2 - cx; a = (R * R - r2 * r2 + d * d) / (2 * d); yy = math.sqrt(max(0, R * R - a * a))
    px = cx + a
    cres = 'M%.1f %.1fA%.1f %.1f 0 1 0 %.1f %.1fA%.1f %.1f 0 1 1 %.1f %.1fZ' % (px, cy - yy, R, R, px, cy + yy, r2, r2, px, cy - yy)
    return '<path d="%s" fill="%s"/>' % (cres, GOLD) + star(x1 - h * 0.42, cy, h * 0.42, rot=-90)


def iran_rules():
    return '<rect x="228" y="274" width="317" height="5" fill="#e4bf4c"/>'


SPECS.update({
    'Guyana': {'coa': 'GY', 'logo': 'CARICOM', 'items': [('l', 0), ('t', 1, 'Caribbean Community', 'sans'), ('e', 2),
               ('t', 3, 'REPUBLIC OF GUYANA', 'sans'), ('t', 4, 'PASSPORT', 'sans')]},
    'Haiti': {'coa': 'HT', 'logo': 'CARICOM', 'items': [('l', 0), ('t', 1, 'Communauté Caribéenne', 'serif'), ('e', 2),
              ('t', 3, 'REPUBLIQUE D’HAITI', 'serif-b'), ('t', 4, 'PASSEPORT', 'serif-b'), ('c', 5)]},
    'Honduras': {'coa': None, 'items': [('t', 0, 'CENTROAMERICA', 'sans-b'), ('t', 1, 'República de', 'sans-b'), ('t', 2, 'HONDURAS', 'sans-b'),
                 ('raw', central_america((65, 343, 514, 676), '{cover}', 'HND')), ('t', 4, 'PASAPORTE', 'sans-b')]},
    'Hungary': {'coa': 'HU', 'items': [('t', 0, 'EURÓPAI UNIÓ', 'serif'), ('t', 1, 'MAGYARORSZÁG', 'serif'), ('e', 2), ('t', 3, 'ÚTLEVÉL', 'serif-b'), ('c', 4)]},
    'Iceland': {'coa': 'IS', 'items': [('t', 1, 'ISLAND', 'serif'), ('t', 2, 'ICELAND', 'serif'), ('t', 3, 'ISLANDE', 'serif'),
                ('e', (150, 242, 432, 520)), ('t', 5, 'VEGABRÉF', 'serif-b'), ('t', (187, 602, 394, 633), 'PASSPORT', 'serif-b'),
                ('t', 7, 'PASSEPORT', 'serif-b'), ('c', 8)]},
    'Iran': {'coa': 'IR', 'items': [('e', (88, 124, 178, 244)), ('t', (328, 84, 508, 110), 'گذرنامه', 'arab'),
             ('t', (228, 114, 548, 154), 'جمهوری اسلامی ایران', 'arab'), ('t', (228, 180, 544, 208), 'ISLAMIC REPUBLIC OF', 'sans-b'),
             ('t', (318, 218, 458, 262), 'IRAN', 'sans-b'), ('raw', iran_rules()), ('c', (82, 714, 148, 754)),
             ('t', (268, 718, 488, 750), 'PASSPORT', 'sans-b')]},
    'Iraq': {'coa': 'IQ', 'items': [('t', 0, 'جمهورية العراق', 'arab'), ('t', 1, 'REPUBLIC OF IRAQ', 'serif-b'), ('e', 2),
             ('t', 3, 'جواز سفر', 'arab'), ('t', 4, 'PASSPORT', 'serif-b')]},
    'Jordan': {'coa': 'JO', 'items': [('t', (60, 27, 540, 95), 'المملكة الأردنية الهاشمية', 'arab'),
               ('t', (60, 120, 540, 205), ['THE HASHEMITE KINGDOM', 'OF JORDAN'], 'serif'), ('e', 1),
               ('t', (223, 637, 411, 700), 'جواز سفر', 'arab'), ('t', (223, 712, 411, 756), 'PASSPORT', 'serif')]},
    'Kenya': {'coa': 'KE', 'items': [('t', 0, 'EAST AFRICAN COMMUNITY', 'serif-b'), ('t', 1, 'REPUBLIC OF KENYA', 'serif-b'), ('e', 2),
              ('t', 3, 'DIPLOMATIC PASSPORT', 'serif-b'), ('c', 4)]},
    'Korea': {'coa': 'KR', 'items': [('e', 0), ('t', 1, '대한민국 여권', 'kore', {'align': 'r'}), ('t', 2, 'REPUBLIC OF KOREA', 'sans-b', {'align': 'r'}),
              ('t', 3, 'PASSPORT', 'sans-b', {'align': 'r'}), ('c', 4)]},
    'Kuwait': {'coa': 'KW', 'items': [('t', 0, 'دولة الكويت', 'arab'), ('t', 1, 'STATE OF KUWAIT', 'serif-b'), ('e', 2),
               ('t', 3, 'جواز سفر', 'arab'), ('t', 4, 'PASSPORT', 'serif-b'), ('c', 5)]},
    'Lebanon': {'coa': 'LB', 'items': [('e', (54, 70, 184, 190)), ('raw', '<rect x="203" y="70" width="3" height="120" fill="#e4bf4c"/>'),
                ('t', (234, 70, 544, 138), 'الجمهورية اللبنانية', 'arab'), ('t', (234, 144, 544, 164), 'REPUBLIQUE LIBANAISE', 'sans-b'),
                ('t', (234, 168, 544, 188), 'REPUBLIC OF LEBANON', 'sans-b'), ('t', (96, 713, 232, 761), 'جواز سفر', 'arab', {'align': 'l'}),
                ('t', (96, 772, 224, 814), ['PASSEPORT', 'PASSPORT'], 'sans-b', {'align': 'l'}), ('c', (494, 768, 564, 808))]},
    'Liberia': {'coa': 'ECOWAS', 'items': [('t', 0, 'ECONOMIC COMMUNITY OF', 'serif'), ('t', 1, 'WEST AFRICAN STATES', 'serif'),
                ('t', 2, '(ECOWAS)', 'serif'), ('t', 3, 'REPUBLIC OF LIBERIA', 'serif'), ('e', (186, 373, 414, 611)), ('t', 7, 'PASSPORT', 'serif')]},
    'Libya': {'coa': None, 'items': [('t', 0, 'دولة ليبيا', 'arab'), ('t', 1, 'STATE OF LIBYA', 'serif-b'), ('raw', crescent_star((179, 317, 410, 477))),
              ('t', 3, 'جواز سفر', 'arab'), ('t', 4, 'PASSPORT', 'serif-b')]},
    'Liechtenstein': {'coa': 'LI', 'items': [('e', (59, 50, 208, 233)), ('t', 1, 'FÜRSTENTUM LIECHTENSTEIN', 'sans-b', {'align': 'l'}),
                      ('t', 2, 'PRINCIPALITY OF LIECHTENSTEIN', 'sans', {'align': 'l'}), ('c', (152, 652, 212, 686)),
                      ('t', (224, 650, 346, 688), ['REISEPASS', 'PASSPORT'], 'sans-b', {'align': 'l'})]},
    'Malta': {'coa': 'MT', 'items': [('t', 0, 'UNJONI EWROPEA', 'serif'), ('t', 1, 'MALTA', 'serif'), ('e', 2), ('t', 3, 'PASSAPORT', 'serif'), ('c', 4)]},
})


SPECS.update({
    'Marshall Islands': {'coa': 'MH', 'items': [('t', 0, 'PASSPORT', 'serif'), ('e', 1), ('t', 2, ['Republic of', 'The Marshall Islands'], 'serif')]},
    'Mauritania': {'coa': 'MR', 'items': [('t', 0, 'الجمهورية الإسلامية الموريتانية', 'arab'), ('t', 1, ['REPUBLIQUE ISLAMIQUE', 'DE MAURITANIE'], 'serif'),
                   ('t', 2, 'ISLAMIC REPUBLIC', 'serif'), ('t', 3, 'OF MAURITANIA', 'serif'), ('e', 4), ('t', 5, 'جواز', 'arab'),
                   ('t', 6, 'PASSEPORT', 'serif'), ('t', 7, 'PASSPORT', 'serif'), ('c', 8)]},
    'Mexico': {'coa': 'MX', 'items': [('t', 0, 'MEXICO', 'serif-b'), ('e', 1), ('t', 2, 'PASAPORTE', 'serif-b')]},
    'Micronesia': {'coa': 'FM', 'items': [('e', 0), ('t', 1, 'PASSPORT', 'sans-l'), ('t', 2, 'FEDERATED STATES OF', 'sans'), ('t', 3, 'MICRONESIA', 'sans')]},
    'Monaco': {'coa': 'MC', 'items': [('t', 0, 'PRINCIPAUTÉ DE MONACO', 'serif'), ('e', 1), ('t', 2, 'PASSEPORT', 'serif'), ('c', 3)]},
    'Mozambique': {'coa': 'MZ', 'items': [('t', 0, 'REPÚBLICA', 'serif-b'), ('t', 1, 'DE', 'serif-b'), ('t', 2, 'MOÇAMBIQUE', 'serif-b'), ('e', 3),
                   ('t', 4, 'PASSAPORTE', 'serif'), ('t', 5, 'PASSPORT', 'serif'), ('c', 6)]},
    'Namibia': {'coa': 'NA', 'items': [('t', 0, ['REPUBLIC', 'OF NAMIBIA'], 'serif-b'), ('e', 1), ('c', 2), ('t', 3, 'PASSPORT', 'serif-b')]},
    'Nepal': {'coa': 'NP', 'items': [('t', (255, 118, 345, 144), 'नेपाल', 'deva'), ('t', (250, 154, 350, 178), 'NEPAL', 'serif'), ('e', 3),
              ('t', 4, 'राहदानी', 'deva'), ('t', 5, 'PASSPORT', 'serif'), ('c', 6)]},
    'New Zealand': {'coa': 'NZ', 'items': [('t', 0, 'NEW ZEALAND', 'serif-b'), ('e', (120, 230, 460, 520)), ('t', (190, 610, 410, 650), 'PASSPORT', 'serif'), ('c', 3)]},
    'Nicaragua': {'coa': None, 'items': [('t', (80, 30, 520, 100), 'AMERICA CENTRAL', 'sans-b'), ('raw', central_america((58, 120, 538, 440), '{cover}', 'NIC')),
                  ('t', (138, 476, 488, 530), 'REPUBLICA DE', 'sans-b'), ('t', (138, 540, 488, 600), 'NICARAGUA', 'sans-b'),
                  ('t', (198, 650, 448, 690), 'PASAPORTE', 'sans-b'), ('t', (198, 700, 448, 740), 'ORDINARIO', 'sans-b')]},
    'Niger': {'coa': 'NE', 'items': [('t', 0, 'REPUBLIQUE DU NIGER', 'serif'), ('e', 1), ('t', 3, 'PASSEPORT', 'serif')]},
    'Nigeria': {'coa': 'ECOWAS', 'items': [('t', (120, 30, 480, 160), ['ECONOMIC COMMUNITY OF', 'WEST AFRICAN STATES', '(ECOWAS)'], 'sans-b'),
                ('e', 1), ('t', 2, 'FEDERAL REPUBLIC OF NIGERIA', 'sans-b'), ('t', 3, 'PASSPORT', 'sans-b'), ('c', 4)]},
    'North Korea': {'coa': 'KP', 'items': [('t', 0, '조선민주주의인민공화국', 'kore'), ('t', 1, 'DEMOCRATIC PEOPLE’S REPUBLIC OF', 'serif'),
                    ('t', 2, 'KOREA', 'serif'), ('e', 3), ('t', 4, '려 권', 'kore'), ('t', 5, '(공무려행용)', 'kore'), ('t', 6, 'PASSPORT', 'serif'),
                    ('t', (147, 712, 438, 736), '(FOR PUBLIC AFFAIRS)', 'serif'), ('c', (260, 746, 330, 781))]},
    'Northern Cyprus': {'coa': 'NCY', 'items': [('t', 0, 'KUZEY KIBRIS', 'serif-b'), ('t', 1, 'TÜRK CUMHURİYETİ', 'serif-b'),
                        ('t', 2, 'TURKISH REPUBLIC OF', 'serif'), ('t', 3, 'NORTHERN CYPRUS', 'serif'), ('e', (150, 275, 450, 630)),
                        ('t', (148, 644, 444, 684), 'PASAPORT', 'serif-b'), ('t', (190, 694, 410, 730), 'PASSPORT', 'serif-b'), ('c', (268, 754, 328, 784))]},
    'Pakistan': {'coa': 'PK', 'items': [('t', (140, 88, 446, 116), 'ISLAMIC REPUBLIC OF', 'sans'), ('t', (176, 124, 412, 168), 'PAKISTAN', 'sans'),
                 ('e', (176, 224, 396, 444)), ('t', (136, 584, 446, 654), 'اسلامی جمہوریہ پاکستان', 'arab'),
                 ('t', (140, 682, 306, 714), 'PASSPORT', 'sans', {'align': 'l'}), ('t', (326, 678, 446, 716), 'پاسپورٹ', 'arab', {'align': 'r'}),
                 ('c', (266, 730, 328, 772))]},
    'Palestine': {'coa': 'PS', 'items': [('t', 1, 'السلطة الفلسطينية', 'arab'), ('t', 2, 'THE PALESTINIAN', 'serif'), ('t', 3, 'AUTHORITY', 'serif'),
                  ('e', [4, 5, 6]), ('t', 7, 'جواز سفر', 'arab'), ('t', 8, 'PASSPORT', 'serif'), ('t', 9, 'TRAVEL DOCUMENT', 'serif'), ('c', 10)]},
})


def traced_in(name, rects):
    """the photo's own trace, only inside `rects` (x0, y0, x1, y1): for plain geometry a trace draws cleanly (Portugal's
    lines), where it would blur arms or words it is never used"""
    import re as _re
    svg = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'traced', name.replace(' ', '_') + '.svg')).read()
    d = _re.search(r'<path fill="#[0-9a-f]{6}" fill-rule="evenodd" d="([^"]*)"', svg).group(1)
    cid = 'tr' + str(abs(hash(name)) % 10000)
    clip = ''.join('<rect x="%d" y="%d" width="%d" height="%d"/>' % (a, b, c - a, e - b) for a, b, c, e in rects)
    return '<clipPath id="%s">%s</clipPath><path clip-path="url(#%s)" fill="%s" fill-rule="evenodd" d="%s"/>' % (cid, clip, cid, GOLD, d)


SPECS.update({
    'Panama': {'coa': 'PA', 'items': [('t', 0, 'REPÚBLICA DE PANAMÁ', 'serif-b'), ('e', 1), ('t', 2, 'PASAPORTE', 'serif'), ('t', 3, 'PASSPORT', 'serif'),
               ('t', 4, 'PASSEPORT', 'serif'), ('c', 5)]},
    'Papua New Guinea': {'coa': 'PG', 'items': [('e', 0), ('t', 1, 'PASSPORT', 'sans-b')]},
    'Peru': {'coa': 'PE', 'items': [('t', (176, 84, 366, 108), 'COMUNIDAD', 'sans-b', {'align': 'r'}), ('t', (252, 121, 370, 143), 'ANDINA', 'sans-b', {'align': 'r'}),
             ('t', (281, 158, 521, 236), ['REPÚBLICA', 'DEL PERÚ'], 'sans-b', {'align': 'l'}), ('raw', '<rect x="282" y="253" width="239" height="5" fill="#e4bf4c"/>'),
             ('e', 4), ('raw', '<rect x="277" y="633" width="246" height="5" fill="#e4bf4c"/>'),
             ('t', (275, 653, 430, 675), 'PASAPORTE', 'sans-b', {'align': 'l'}), ('t', (275, 683, 408, 705), 'PASSPORT', 'sans', {'align': 'l'}),
             ('c', (274, 728, 339, 770))]},
    'Portugal': {'coa': 'PT', 'items': [('e', (64, 30, 254, 190)), ('t', (68, 220, 250, 246), 'União Europeia', 'sans-sb', {'align': 'l', 'space': False}),
                 ('t', (68, 254, 358, 320), 'Portugal', 'sans-sb', {'align': 'l', 'space': False}),
                 ('t', (68, 330, 220, 354), 'Passaporte', 'sans-sb', {'align': 'l', 'space': False}),
                 ('raw', traced_in('Portugal', [(380, 0, 600, 440), (330, 600, 600, 852)])), ('c', (74, 754, 134, 790))]},
    'Qatar': {'coa': 'QA', 'items': [('t', 0, 'دولة قطر', 'arab'), ('t', 1, 'STATE OF QATAR', 'serif-b'), ('e', 2), ('t', 3, 'جواز سفر', 'arab'),
              ('t', 4, 'PASSPORT', 'serif-b'), ('c', 5)]},
    'Rwanda': {'coa': 'RW', 'items': [('t', 0, 'EAST AFRICAN COMMUNITY', 'serif-b'), ('t', 1, 'REPUBULIKA Y’U RWANDA', 'serif-b'),
               ('t', 2, 'REPUBLIC OF RWANDA', 'serif-b'), ('t', 3, 'REPUBLIQUE DU RWANDA / JAMHURI YA RWANDA', 'serif-b'), ('e', 4),
               ('t', 5, 'PASIPORO / PASSPORT', 'serif-b'), ('t', 6, 'PASSEPORT / PASIPOTI', 'serif-b'), ('c', 7)]},
    'Saint Lucia': {'coa': 'LC', 'logo': 'CARICOM', 'items': [('l', 0), ('t', 1, 'SAINT LUCIA', 'sans', {'align': 'l'}), ('t', 2, 'PASSPORT', 'sans', {'align': 'l'}),
                    ('e', 3), ('l', (86, 702, 140, 760)), ('t', (150, 720, 412, 744), 'CARIBBEAN COMMUNITY', 'sans', {'align': 'l'})]},
    'Saint Vincent and the Grenadines': {'coa': 'VC', 'logo': 'CARICOM', 'items': [('l', (135, 58, 178, 114)),
                    ('t', (190, 76, 447, 96), 'CARIBBEAN COMMUNITY', 'sans', {'align': 'l'}), ('e', 1),
                    ('raw', '<rect x="140" y="484" width="269" height="6" fill="#e4bf4c"/>'), ('t', 3, 'ST. VINCENT', 'serif', {'align': 'l'}),
                    ('t', 4, 'AND THE', 'serif', {'align': 'l'}), ('t', (140, 576, 407, 607), 'GRENADINES', 'serif', {'align': 'l'}),
                    ('t', 6, 'PASSPORT', 'sans', {'align': 'l'}), ('t', 7, 'PASSEPORT', 'sans', {'align': 'l'}), ('t', 8, 'PASAPORTE', 'sans', {'align': 'l'}),
                    ('c', 9)]},
    'Senegal': {'coa': 'SN', 'items': [('t', 0, ['COMMUNAUTE ECONOMIQUE DES', 'ETATS DE L’AFRIQUE DE L’OUEST'], 'sans'), ('t', 1, 'REPUBLIQUE DU SENEGAL', 'sans-b'),
                ('e', 2), ('t', 3, 'PASSEPORT', 'sans-b'), ('t', 4, 'Passport', 'serif-i'), ('c', 5)]},
    'Seychelles': {'coa': 'SC', 'items': [('t', 0, 'REPUBLIC OF SEYCHELLES', 'serif'), ('t', 1, 'REPUBLIQUE DES SEYCHELLES', 'serif'), ('e', 2),
                   ('t', 3, 'PASSPORT', 'serif'), ('t', 4, 'PASSEPORT', 'serif'), ('c', 5)]},
    'Sierra Leone': {'coa': 'ECOWAS', 'items': [('t', 0, ['ECONOMIC COMMUNITY', 'OF WEST AFRICAN STATES'], 'serif'), ('t', 2, 'REPUBLIC OF', 'serif'),
                     ('t', 3, 'SIERRA LEONE', 'serif'), ('e', 4), ('t', 5, 'PASSPORT', 'serif')]},
    'Slovakia': {'coa': 'SK', 'items': [('t', 0, 'EURÓPSKA ÚNIA', 'sans-b'), ('t', 1, 'SLOVENSKÁ REPUBLIKA', 'sans-b'), ('e', 2),
                 ('t', 3, 'CESTOVNÝ PAS', 'sans-b'), ('c', 4)]},
    'Somalia': {'coa': 'SO', 'items': [('t', 0, 'JAMHUURIYADDA SOOMAALIYA', 'serif'), ('t', 1, 'جمهورية الصومال', 'arab'), ('t', 2, 'SOMALI REPUBLIC', 'serif'),
                ('e', (100, 241, 500, 562)), ('t', (210, 628, 390, 654), 'BAASABOOR', 'serif'), ('t', (240, 664, 360, 694), 'جواز سفر', 'arab'),
                ('t', (220, 708, 380, 736), 'PASSPORT', 'serif'), ('c', (280, 764, 340, 796))]},
    'South Ossetia': {'coa': 'SOS', 'items': [('t', (45, 96, 555, 203), ['РЕСПУБЛИКӔ ХУССАР ИРЫСТОН', 'РЕСПУБЛИКА ЮЖНАЯ ОСЕТИЯ'], 'serif'),
                      ('e', (90, 290, 510, 700))]},
    'Sri Lanka': {'coa': 'LK', 'items': [('t', 0, 'PASSPORT', 'serif-b'), ('t', 1, 'ගමන් බලපත්‍රය', 'sinh'), ('t', 2, 'கடவுச்சீட்டு', 'taml'), ('e', 3),
                  ('t', 4, 'DEMOCRATIC SOCIALIST REPUBLIC OF', 'serif-b'), ('t', 5, 'SRI LANKA', 'serif-b'),
                  ('t', 6, ['ශ්‍රී ලංකා ප්‍රජාතාන්ත්‍රික සමාජවාදී ජනරජය', 'இலங்கைச் சனநாயக சோசலிசக் குடியரசு'], ['sinh', 'taml'])]},
    'Sudan': {'coa': 'SD', 'items': [('t', 0, 'جمهورية السودان', 'arab'), ('t', 1, 'THE REPUBLIC OF THE SUDAN', 'sans-b'), ('e', 2),
              ('t', 3, 'جواز سفر', 'arab'), ('t', 4, 'PASSPORT', 'sans-b'), ('c', (270, 782, 330, 820))]},
})


def arc_text(text, face, cx, cy, r, mid_deg, size, inside=False, spacing=1.0):
    """`text` set round a circle (centre cx, cy, radius r to the letters' baseline), centred on the angle `mid_deg`
    (0 = right, 90 = down, svg's way), each letter upright to the circle; `inside` reads along the bottom"""
    upm = tp.font(face)[1]['head'].unitsPerEm
    infos, poss, tt = tp.shaped(text, face)
    k = size / upm
    advs = [p.x_advance * k * spacing for p in poss]
    total = sum(advs)
    ang_total = total / r
    out = []
    a = math.radians(mid_deg) + (ang_total / 2 if inside else -ang_total / 2)
    gs = tt.getGlyphSet(); order = tt.getGlyphOrder()
    from fontTools.pens.svgPathPen import SVGPathPen
    for inf, adv in zip(infos, advs):
        step = adv / r
        am = a + (-step / 2 if inside else step / 2)
        x = cx + r * math.cos(am); y = cy + r * math.sin(am)
        rot = math.degrees(am) + (-90 if inside else 90)
        pen = SVGPathPen(gs); gs[order[inf.codepoint]].draw(pen)
        out.append('<path transform="translate(%.2f %.2f) rotate(%.2f) scale(%.5f %.5f) translate(%.1f 0)" d="%s"/>'
                   % (x, y, rot, k, -k, -adv / k / 2 / spacing, pen.getCommands()))
        a += -step if inside else step
    return ''.join(out)


def ecowas_medallion(bx, cover):
    """the ECOWAS / CEDEAO emblem as its passports carry it: a double ring, CEDEAO round the top, ECOWAS round the
    bottom, and West Africa (Natural Earth's outlines) in the middle"""
    import shapefile
    x0, y0, x1, y1 = bx
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2; R = min(x1 - x0, y1 - y0) / 2
    out = ['<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="%.1f"/>' % (cx, cy, R * 0.97, GOLD, R * 0.035),
           '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="%.1f"/>' % (cx, cy, R * 0.66, GOLD, R * 0.03),
           arc_text('CEDEAO', 'sans-b', cx, cy, R * 0.73, -90, R * 0.26, spacing=1.15),
           arc_text('ECOWAS', 'sans-b', cx, cy, R * 0.9, 90, R * 0.26, inside=True, spacing=1.15)]
    r = shapefile.Reader(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ne', 'naturalearth_lowres.shp'))
    lon0, lon1, lat0, lat1 = -18.5, 52, -36, 38
    s = R * 1.2 / (lat1 - lat0); kx = 1.0
    ox = cx - (lon1 - lon0) * s / 2 + R * 0.05; oy = cy - (lat1 - lat0) * s / 2
    clip = '<clipPath id="ew%d"><circle cx="%.1f" cy="%.1f" r="%.1f"/></clipPath>' % (int(cx), cx, cy, R * 0.6)
    ds = []
    for rec, sh in zip(r.records(), r.shapes()):
        if rec[1] != 'Africa': continue
        pts = sh.points; parts = list(sh.parts) + [len(pts)]
        ds.append(''.join('M' + 'L'.join('%.1f %.1f' % (ox + (lo - lon0) * s, oy + (lat1 - la) * s) for lo, la in pts[parts[j]:parts[j + 1]]) + 'Z'
                          for j in range(len(parts) - 1)))
    out.append(clip + '<path clip-path="url(#ew%d)" d="%s" fill="%s"/>' % (int(cx), ''.join(ds), GOLD))
    return ''.join(out)


def vatican_words(bx):
    x0, y0, x1, y1 = bx
    cx = (x0 + x1) / 2; cy = y0 + (y1 - y0) * 0.38; r = (x1 - x0) * 0.47
    return arc_text('STATO DELLA CITTÀ DEL VATICANO', 'serif', cx, cy, r, 90, (y1 - y0) * 0.11, inside=True, spacing=1.05)


SPECS.update({
    'Switzerland': {'coa': None, 'items': [('t', (231, 74, 556, 228), ['Schweizer Pass', 'Passeport suisse', 'Passaporto svizzero', 'Passaport svizzer', 'Swiss passport'],
                    'sans', {'align': 'r'}), ('raw', '<path d="M488 248h36v36h36v36h-36v36h-36v-36h-36v-36h36z" fill="#e4bf4c" transform="translate(-26 -14) scale(1)"/>')]},
    'São Tomé and Príncipe': {'coa': 'ST', 'items': [('t', (60, 109, 534, 175), ['REPÚBLICA DEMOCRÁTICA', 'DE SÃO TOMÉ E PRÍNCIPE'], 'serif'), ('e', (90, 251, 470, 585)),
                              ('t', 2, 'PASSAPORTE', 'serif')]},
    'Tanzania': {'coa': 'TZ', 'items': [('t', 0, 'PASSPORT', 'sans-b'), ('e', 1), ('t', 2, 'UNITED REPUBLIC', 'serif-b'), ('t', 3, 'OF TANZANIA', 'serif-b')]},
    'Togo': {'coa': 'TG', 'items': [('t', 0, ['COMMUNAUTE ECONOMIQUE DES', 'ETATS DE L’AFRIQUE DE L’OUEST'], 'sans-b'), ('t', 1, '(CEDEAO / ECOWAS)', 'sans-b'),
             ('t', 2, 'REPUBLIQUE TOGOLAISE', 'sans-b'), ('e', 3), ('t', 4, 'PASSEPORT', 'sans-b'), ('c', 5)]},
    'Transnistria': {'coa': 'TRA', 'items': [('e', 0), ('t', 1, 'ПАСПОРТ', 'serif')]},
    'Tuvalu': {'coa': 'TV', 'items': [('t', 0, 'TUVALU', 'serif-b'), ('e', 1), ('t', 2, 'PASSPORT', 'serif-b')]},
    'Uganda': {'coa': 'UG', 'items': [('t', 0, ['Republic of', 'UGANDA'], 'sans-b'), ('e', 2), ('t', 3, 'PASSPORT', 'sans-b')]},
    'United Arab Emirates': {'coa': 'AE', 'items': [('t', (87, 54, 528, 104), 'الإمارات العربية المتحدة', 'arab'), ('t', (87, 110, 528, 138), 'UNITED ARAB EMIRATES', 'serif'),
                             ('e', 1), ('t', 2, 'جواز سفر', 'arab'), ('t', 3, 'PASSPORT', 'serif'), ('c', 4)]},
    'Uzbekistan': {'coa': 'UZ', 'items': [('t', (58, 75, 531, 101), 'OʻZBEKISTON RESPUBLIKASI', 'sans'), ('t', (100, 119, 520, 146), 'REPUBLIC OF UZBEKISTAN', 'sans'),
                   ('e', 3), ('t', 4, 'PASPORT • PASSPORT', 'sans'), ('c', 5)]},
    'Vanuatu': {'coa': 'VU', 'items': [('t', (81, 59, 260, 122), ['Republic of', 'VANUATU'], 'sans-b', {'align': 'l'}),
                ('t', (300, 59, 520, 122), ['République de', 'VANUATU'], 'sans-b', {'align': 'r'}), ('e', 1),
                ('t', 2, 'PASSPORT', 'sans-b'), ('t', 3, 'PASSEPORT', 'sans-b')]},
    'Vatican': {'coa': 'VA', 'items': [('e', (230, 132, 364, 300)), ('raw', vatican_words((119, 130, 475, 360))), ('t', 1, 'PASSAPORTO', 'serif'), ('c', 2)]},
    'Venezuela': {'coa': 'VE', 'items': [('t', 1, ['REPÚBLICA BOLIVARIANA', 'DE VENEZUELA'], 'serif-b'), ('e', 2), ('t', 3, ['PASAPORTE', 'PASSPORT'], 'serif-b'), ('c', 4)]},
    'Åland': {'coa': 'AX', 'items': [('t', 0, 'Europeiska unionen', 'sans'), ('t', 1, 'Europeiska unionen', 'sans'), ('e', 3), ('t', 4, 'SUOMI · FINLAND', 'sans'),
              ('t', 5, 'ÅLAND', 'sans'), ('t', 6, 'Passi', 'sans'), ('t', 7, 'Pass', 'sans'), ('c', 8)]},
})
for _n in ('Ghana', 'Guinea', 'Liberia', 'Nigeria', 'Sierra Leone'):
    SPECS[_n]['items'] = [('raw_fn', 'ecowas', it[1]) if it[0] == 'e' else it for it in SPECS[_n]['items']]
SPECS['Slovakia']['items'] = [('e', 2, {'dark': 0.25}) if it[0] == 'e' else it for it in SPECS['Slovakia']['items']]

SPECS['Åland'] = {'coa': 'FI', 'items': [('t', 0, 'Euroopan unioni', 'sans'), ('t', 1, 'Europeiska unionen', 'sans'), ('e', 3), ('t', 4, 'SUOMI · FINLAND', 'sans'),
                  ('t', 5, 'ÅLAND', 'sans'), ('t', 6, 'Passi', 'sans'), ('t', 7, 'Pass', 'sans'), ('c', 8)]}
SPECS['United Arab Emirates']['items'] = [('e', 1, {'dark': 0.3}) if it[0] == 'e' else it for it in SPECS['United Arab Emirates']['items']]
SPECS['Uzbekistan']['items'] = [('c', (266, 756, 326, 790)) if it[0] == 'c' else it for it in SPECS['Uzbekistan']['items']]

SPECS['Tanzania']['items'] = [('e', 1, {'big': 0.03}) if it[0] == 'e' else it for it in SPECS['Tanzania']['items']]
SPECS['Saint Lucia']['items'] = [('e', 3, {'big': 0.03}) if it[0] == 'e' else it for it in SPECS['Saint Lucia']['items']]

# solid where the cover's own crest is a gold silhouette (judged from each photo: its print covers about half of the
# crest's box and reads as one piece; Czechia's and Panama's are fine lines, Cyprus' is dark, so not those)
for _n in ('Germany', 'Uganda', 'Liechtenstein', 'Iceland', 'Comoros', 'Dominica', 'Senegal', 'Djibouti', 'Sri Lanka'):
    SPECS[_n]['solid'] = True

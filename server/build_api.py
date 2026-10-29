#!/usr/bin/env python3
"""Build the wya?! data API from reference/data.

The app keeps no travel data inside itself. It asks this API, one country or one shard at a
time, so the app stays small and the data can change without a new app release.

The output is plain files under public.nosync/v1/, gzipped. Any static host serves them unchanged:
serve.py on this Mac today, and later Cloudflare R2 or Pages, S3 with CloudFront, or Netlify.
Moving to a real server means uploading v1/ and changing one address in the app.

    python3 server/build_api.py          # from the wya?! folder; takes a minute or two

Every endpoint, what is in it and where it came from is written to v1/manifest.json.
"""
import gzip, hashlib, io, json, os, shutil, sys, time, collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
DATA = os.path.join(ROOT, 'reference', 'data')
SRC = os.path.join(ROOT, 'reference', 'run', 'redo', 'src')
# public.nosync: iCloud Drive leaves anything ending in .nosync alone, so the 124 MB this
# builds stays on the Mac that built it (each Mac builds its own in under a minute) and two
# Macs building never make iCloud "2" copies. The folder to upload to a real host is v1/.
OUT = os.path.join(HERE, 'public.nosync', 'v1')
VERSION = 'v1'

def load(name):
    with io.open(os.path.join(DATA, name), encoding='utf-8') as f:
        return json.load(f)

written = collections.OrderedDict()   # path -> (records, bytes)

def shard_of(name):
    """FNV-1a of the filename's UTF-8 bytes, low byte in hex: the same sum as API.shardOf"""
    h = 0x811c9dc5
    for b in name.encode('utf-8'):
        h ^= b; h = (h * 0x01000193) & 0xffffffff
    return '%02x' % (h & 0xff)

def put(rel, obj, records=None):
    """write one endpoint as gzip; the server and any static host send it as JSON"""
    raw = json.dumps(obj, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    p = os.path.join(OUT, rel + '.gz')
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(gzip.compress(raw, 6, mtime=0))       # mtime 0: same data, same bytes, same ETag. Level 6: 9 took 1.6x as long for files 0.8% smaller
    written[rel] = (records if records is not None else (len(obj) if hasattr(obj, '__len__') else 1), len(raw))

def put_raw(rel, raw):
    p = os.path.join(OUT, rel + '.gz')
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(gzip.compress(raw, 6, mtime=0))
    written[rel] = (1, len(raw))

def main():
    t0 = time.time()
    if os.path.isdir(OUT):
        # rebuilt from scratch every time, so nothing stale survives; the old tree is moved,
        # not deleted, so a bad build can be rolled back by hand
        old = OUT + '.previous'
        if os.path.isdir(old):
            try: shutil.rmtree(old)
            except OSError: old = OUT + '.previous-' + time.strftime('%Y%m%d-%H%M%S')   # a folder that can't delete
        os.rename(OUT, old)
    os.makedirs(OUT)

    world = json.load(io.open(os.path.join(SRC, 'world.json'), encoding='utf-8'))
    facts = load('country-facts.json')                  # ISO2 upper -> facts
    wd = load('country-wikidata.json')

    # every name a country goes by -> iso2 lower, so files keyed by name can be joined
    name2cc = {}
    def learn(n, cc):
        if n: name2cc.setdefault(n.strip().lower(), cc)
    for w in world:
        if w.get('code'): learn(w['name'], w['code'].lower())
    for cc, v in facts.items():
        learn(v.get('name'), cc.lower())
        for a in v.get('alias') or []: learn(a, cc.lower())
    for n, cc in (('United States', 'us'), ('United Kingdom', 'gb'), ('States', 'us'), ('Britain', 'gb'),
                  ('Czech Republic', 'cz'), ('Ivory Coast', 'ci'), ('Democratic Republic of the Congo', 'cd'),
                  ('Republic of the Congo', 'cg'), ('Vatican City', 'va'), ('Holland', 'nl'),
                  ('Burma', 'mm'), ('Swaziland', 'sz'), ('Timor-Leste', 'tl'), ('Cabo Verde', 'cv'),
                  ('Macao', 'mo'), ('North Korea', 'kp'), ('South Korea', 'kr'), ('Micronesia', 'fm')):
        learn(n, cc)
    q2cc = {v['q']: cc.lower() for cc, v in facts.items() if v.get('q')}
    q2cc.update({v['q']: cc.lower() for cc, v in wd.items() if v.get('q')})
    ccs = sorted({w['code'].lower() for w in world if w.get('code')} | {c.lower() for c in facts})

    # ---- per-country bundles -------------------------------------------------------
    climate = load('climate.json'); daylight = load('daylight.json'); adv = load('advisories.json')
    hol = load('holidays.json'); visa = load('visa.json'); wb = load('worldbank.json')
    price = load('price-level.json'); wv = load('wikivoyage-countries.json')
    heritage = load('world-heritage.json'); airports = load('airports.json')
    us = adv.get('_us', {}); uk = adv.get('_uk', {})
    # the two governments' own names for places, where they differ from ours; an advisory
    # covering several places is given to each of them
    US_NAMES = {'Mainland China, Hong Kong &amp; Macau - See Summaries': ['cn', 'hk', 'mo'],
                'West Bank': ['ps'], 'Gaza': ['ps'], 'Sint Eustatius': ['bq'], 'Bonaire': ['bq'], 'Saba': ['bq'],
                'Cote d Ivoire': ['ci'], 'The Kyrgyz Republic': ['kg'], 'Mexico Travel Advisory': ['mx'],
                'Kingdom of Denmark': ['dk'], 'French West Indies': ['gp', 'mq', 'bl', 'mf']}
    UK_NAMES = {'St Helena, Ascension and Tristan da Cunha': ['sh'], 'Falkland Islands (British Overseas Territory)': ['fk'],
                'USA': ['us'], 'Gibraltar (British Overseas Territory)': ['gi'], 'Hong Kong (SAR of China)': ['hk'],
                'Turks and Caicos Islands (British Overseas Territory)': ['tc'], 'Macao (SAR of China)': ['mo'],
                'Cook Islands, Tokelau and Niue': ['ck', 'tk', 'nu'], 'Sao Tome & Príncipe': ['st'],
                'Korea, DPR (North Korea)': ['kp'], 'Bonaire, St Eustatius and Saba': ['bq'],
                'Wallis & Futuna Islands': ['wf'], 'East Timor (Timor-Leste)': ['tl'],
                'St Martin and St Barthélemy': ['mf', 'bl'], 'St Maarten': ['sx'],
                'British Virgin Islands (British Overseas Territory)': ['vg'], 'Bermuda (British Overseas Territory)': ['bm'],
                'Cayman Islands (British Overseas Territory)': ['ky'],
                'South Georgia and South Sandwich Islands (British Overseas Territory)': ['gs'],
                'Antarctica/British Antarctic Territory': ['aq'], 'Pitcairn Island': ['pn'],
                'Anguilla (British Overseas Territory)': ['ai']}
    us_by, uk_by = {}, {}
    for k, v in us.items():
        for cc in US_NAMES.get(k) or ([name2cc[k.lower()]] if k.lower() in name2cc else []): us_by.setdefault(cc, v)
    for k, v in uk.items():
        n = k.replace(' travel advice', '')
        for cc in UK_NAMES.get(n) or ([name2cc[n.lower()]] if n.lower() in name2cc else []): uk_by.setdefault(cc, v)
    wv_by = {name2cc.get(k.lower()): v for k, v in wv.items() if name2cc.get(k.lower())}
    visa_by = {name2cc.get(k.lower()): v for k, v in visa.items() if name2cc.get(k.lower())}
    air_by = {name2cc.get(k.lower()): v for k, v in airports.items() if name2cc.get(k.lower())}
    her_by = collections.defaultdict(list)
    for q, h in heritage.items():
        for c in h.get('cc') or []:
            her_by[c.lower()].append(q)
    index = []
    wnames = {w['code'].lower(): w for w in world if w.get('code')}
    for cc in ccs:
        up = cc.upper(); f = facts.get(up, {})
        iso3 = f.get('iso3')
        b = {'cc': cc, 'name': (wnames.get(cc) or {}).get('name') or f.get('name'),
             'facts': f or None,
             'worldbank': wb.get(iso3) if iso3 else None,
             'priceLevel': price.get(iso3) if iso3 else None,
             'climate': climate.get(up), 'daylight': daylight.get(up),
             'advisories': {'ca': (adv.get(up) or {}).get('ca'), 'us': us_by.get(cc), 'uk': uk_by.get(cc)},
             'holidays': hol.get(up), 'guide': wv_by.get(cc),
             'visaFromHere': visa_by.get(cc), 'airports': air_by.get(cc),
             'heritage': her_by.get(cc, [])}
        put('country/%s.json' % cc, b, records=1)
        index.append({'cc': cc, 'name': b['name'], 'iso3': iso3, 'continent': (wnames.get(cc) or {}).get('continent') or f.get('continent'),
                      'capital': f.get('capital'), 'flag': ''.join(chr(0x1F1E6 + ord(c) - 65) for c in up) if len(up) == 2 and up.isalpha() else None})
    put('countries.json', index)

    # ---- guides, listings, places, regions, cities, per country -----------------------
    for folder, key in (('wv-guides', 'guides'), ('wv-listings', 'listings')):
        d = os.path.join(DATA, folder)
        for fn in sorted(os.listdir(d)):
            if not fn.endswith('.json'): continue
            with open(os.path.join(d, fn), 'rb') as f: raw = f.read()
            put_raw('%s/%s' % (key, fn), raw)
            written['%s/%s' % (key, fn)] = (len(json.loads(raw)), len(raw))

    # ---- one place at a time: a Wikivoyage article with its listings, and each country's
    # index of its articles. A place's page asks for that place alone: the United States'
    # guides and listings together are 16 MB gzipped, too much for one city's page on a phone.
    # The files are named by FNV-1a of the title (8 hex); the index gives each title its file,
    # so two titles with the same sum can never be confused. They are counted in the manifest
    # as one line per kind, not one line each (29,000 lines would make it too big to ask for).
    def fnv32(name):
        h = 0x811c9dc5
        for b in name.encode('utf-8'):
            h ^= b; h = (h * 0x01000193) & 0xffffffff
        return '%08x' % h
    gdir = os.path.join(DATA, 'wv-guides'); ldir = os.path.join(DATA, 'wv-listings')
    n_art = n_bytes = 0
    for fn in sorted(os.listdir(gdir)):
        if not fn.endswith('.json'): continue
        cc = fn[:-5]
        with io.open(os.path.join(gdir, fn), encoding='utf-8') as f: g = json.load(f)
        lp = os.path.join(ldir, fn); L = {}
        if os.path.isfile(lp):
            with io.open(lp, encoding='utf-8') as f: L = json.load(f)
        idx, used = [], set()
        for title in sorted(g):
            a = g[title] or {}
            key = fnv32(title); k2 = 2
            while key in used: key = fnv32(title) + '-' + str(k2); k2 += 1
            used.add(key)
            ll = a.get('ll') or [None, None]
            idx.append([title, a.get('kind') or '', (a.get('in') or '').replace('_', ' '), ll[0], ll[1], key])
            raw = json.dumps({'t': title, 'g': a, 'l': L.get(title) or []}, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
            fp = os.path.join(OUT, 'place', cc, key + '.json.gz')
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, 'wb') as f: f.write(gzip.compress(raw, 6, mtime=0))
            n_art += 1; n_bytes += len(raw)
        put('placeindex/%s.json' % cc, idx)
    written['place/{cc}/{key}.json'] = (n_art, n_bytes)

    places = collections.defaultdict(dict)
    for q, v in load('destinations.json').items():
        for c in v.get('cty') or []:
            cc = q2cc.get(c)
            if cc: places[cc][q] = v; break
    for cc, d in places.items(): put('places/%s.json' % cc, d)

    rf = load('region-facts.json'); rc = load('climate-regions.json')
    regs = collections.defaultdict(dict)
    for k, v in rf.items():
        v = dict(v); cl = rc.get(k)
        if cl: v['climate'] = {'hi': cl['hi'], 'lo': cl['lo'], 'mm': cl['mm']}
        regs[k.split('-')[0].lower()][k] = v
    for cc, d in regs.items(): put('regions/%s.json' % cc, d)

    cities = load('cities.json'); ccl = load('climate-cities.json')
    for place, lst in cities.items():
        cc = name2cc.get(place.lower())
        if not cc: continue
        out = []
        for c in lst:
            c = dict(c)
            cl = ccl.get(str(c.get('gid'))) if c.get('gid') else ccl.get(place + '/' + c.get('n', ''))
            if cl: c['climate'] = {'hi': cl['hi'], 'lo': cl['lo'], 'mm': cl['mm']}
            out.append(c)
        put('cities/%s.json' % cc, out)

    # ---- the map's region shapes, one file per country and level ---------------------
    rdir = os.path.join(SRC, 'regions')
    for fn in sorted(os.listdir(rdir)):
        if fn.endswith('.js'):
            with open(os.path.join(rdir, fn), 'rb') as f: put_raw('shapes/%s' % fn, f.read())

    # ---- photo credits, in 256 shards; api.js computes the same shard -----------------
    cr = load('image-credits.json'); shards = collections.defaultdict(dict)
    for name, v in cr.items():
        if not v.get('lic'): continue
        shards[shard_of(name)][name] = {k: v[k] for k in ('credit', 'lic', 'url', 'file', 'by') if v.get(k)}
    for s, d in shards.items(): put('credits/%s.json' % s, d)

    # ---- phrasebooks, one file per language -----------------------------------------
    pb = load('phrasebooks.json'); langs = []
    for lang, v in pb.items():
        slug = ''.join(ch if ch.isalnum() else '-' for ch in lang.lower()).strip('-')
        put('phrasebooks/%s.json' % slug, v); langs.append({'lang': lang, 'file': 'phrasebooks/%s.json' % slug})
    put('phrasebooks.json', langs)

    # ---- passport covers: every cover a drawing, in its own mixed colour with our gold print (plan row 136) -------.
    # Sheet 3's rule: each cover its own colour as the closest mix of ours, the print our gold on every cover. Commons'
    # drawings (passport-vectors.json, and two more found in row 136) are recoloured here by that rule (recolour_mix.py,
    # the mixes measured once in passport-cover-mixes.json); the covers Commons has only as a photograph were traced
    # from it in row 136 (passport-traced.json: the cover squared up, its colour measured, its print traced with
    # potrace; no AI, no hand drawing). passports.json says which file, its colour, how it was drawn and whose it is.
    sys.path.insert(0, HERE)
    from recolour import clean
    from recolour_mix import recolour_mix
    vec136 = load('passport-vectors-136.json')
    vec = load('passport-vectors.json'); vec.update(vec136)
    vcr = load('passport-vectors-credits.json'); vmix = load('passport-cover-mixes.json')
    vcr.update(vec136.get('_credits', {}))     # the drawings found in row 136, credited as Commons gives them
    traced = load('passport-traced.json'); pindex = {}
    try:
        with io.open(os.path.join(SRC, 'passports.json'), encoding='utf-8') as f: jpgs = json.load(f)
        with io.open(os.path.join(SRC, 'passports-credits.json'), encoding='utf-8') as f: jcr = {c['country']: c for c in json.load(f)}
    except (IOError, OSError, ValueError):
        jpgs, jcr = {}, {}
    jcr.update(traced.get('_credits', {}))       # row 136: the better photographs found for a few covers
    def photo_credit(name):
        c = jcr.get(name) or {}
        return {k2: c[k1] for k1, k2 in (('author', 'by'), ('licence', 'lic'), ('page', 'url'), ('file', 'file')) if c.get(k1)}
    def slug_of(name): return ''.join(ch if ch.isalnum() else '-' for ch in name.lower()).strip('-')
    for name in sorted(vec):
        m = vmix.get(name)
        if not m or name.startswith('_'): continue      # no mix measured (Maldives: a photograph inside an SVG)
        svg = recolour_mix(clean(vec[name]), m['drawn'], m['cover'])
        slug = slug_of(name)
        put_raw('passports/%s.svg' % slug, svg.encode('utf-8'))
        c = vcr.get(name)
        pindex[name] = {'file': 'passports/%s.svg' % slug, 'cover': m['cover'], 'mix': m['mix'], 'drawn': 'vector',
                        'credit': {k: c[k] for k in ('by', 'lic', 'url', 'file') if c.get(k)} if c else photo_credit(name)}
    # 16 Oct 21:16: the traces are not good enough at full size. None is published until it is redrawn (row 136 again:
    # the coat of arms as a vector and the cover's words); meanwhile each keeps the photograph's entry below, with its
    # mixed colour for the app's drawn stand-in. A cover redrawn and checked is named here. 16 Oct evening: rebuilt
    # instead (passport-rebuilt.json: the arms as gold line art, the words typeset from the photo); a cover is published
    # once it is in '_ready'
    rebuilt = load('passport-rebuilt.json')
    jcr.update(rebuilt.get('_credits', {}))
    TRACED_READY = set(rebuilt.get('_ready', []))
    mixed_only = {}
    for name in sorted(rebuilt):
        if name.startswith('_') or name in pindex: continue
        t = rebuilt[name]; slug = slug_of(name)
        if name not in TRACED_READY:
            mixed_only[name] = {'cover': t['cover'], 'mix': t['mix']}
            continue
        put_raw('passports/%s.svg' % slug, t['svg'].encode('utf-8'))
        pindex[name] = {'file': 'passports/%s.svg' % slug, 'cover': t['cover'], 'mix': t['mix'], 'drawn': 'traced',
                        'arms': t.get('arms'), 'credit': photo_credit(name)}
    # a cover with no drawing yet (no photograph of it on Commons either): the photograph the app used to carry, as
    # before, until one is found
    import base64
    for name in sorted(jpgs):
        if name in pindex: continue
        slug = slug_of(name)
        put_raw('passports/%s.jpg' % slug, base64.b64decode(jpgs[name]))
        pindex[name] = {'file': 'passports/%s.jpg' % slug, 'credit': photo_credit(name)}
        pindex[name].update(mixed_only.get(name, {}))
    put('passports.json', pindex)

    # ---- the heavy flags as vectors ----------------------. The app carries every flag drawing under 20 KB; these are
    # the coats of arms above that, one SVG each, by the slug the app asks for.
    fv_path = os.path.join(DATA, 'flag-vectors.json')
    if os.path.isfile(fv_path):
        for slug, svg in load('flag-vectors.json').items():
            put_raw('flags/%s.svg' % slug, svg.encode('utf-8'))

    # ---- the sample's own pictures and clips: they are the sample, not the app, so they live
    # here and the app asks for them (sample/photo/{key}.jpg, sample/clip/{key}.mp4, sample/cover/{key}.jpg)
    for fname, kind, ext in (('photos.json', 'photo', 'jpg'), ('clips.json', 'clip', 'mp4'), ('covers.json', 'cover', 'jpg')):
        try:
            with io.open(os.path.join(SRC, fname), encoding='utf-8') as f: media = json.load(f)
        except (IOError, OSError, ValueError):
            media = {}
        for key, b64 in media.items():
            put_raw('sample/%s/%s.%s' % (kind, key, ext), base64.b64decode(b64))
        put('sample/%s.json' % kind, sorted(media))

    # ---- small whole-world files ------------------------------------------------------
    put('routes.json', load('routes.json'))
    put('rates.json', load('rates.json'), records=1)
    put('heritage.json', heritage)

    manifest = {
        'version': VERSION,
        'built': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'endpoints': {
            'countries.json': 'every place the app knows: code, name, continent, capital, flag',
            'country/{cc}.json': 'one country: facts, World Bank, price level, capital climate, daylight, advisories (Canada, US, UK, never merged), holidays, the Wikivoyage country guide, visa rules for its passport, airports, World Heritage ids',
            'guides/{cc}.json': 'Wikivoyage guides for every destination in the country',
            'listings/{cc}.json': 'Wikivoyage See/Do/Eat/Drink/Sleep/Buy listings, per article',
            'places/{cc}.json': 'destinations with a photo filename, by Wikidata id',
            'placeindex/{cc}.json': 'every Wikivoyage article in the country: [title, kind, in, lat, lon, key]',
            'place/{cc}/{key}.json': 'one article and its listings: {t: title, g: the guide, l: the listings}; key from placeindex',
            'regions/{cc}.json': 'level-1 regions: picture, flag, arms, population, capital, climate',
            'cities/{cc}.json': 'cities with population, height, time zone and climate',
            'shapes/{cc}-{level}.js': 'the map shapes for one country at one level',
            'credits/{xx}.json': 'photo credits; xx = the low byte of FNV-1a(filename), in hex (API.shardOf)',
            'phrasebooks.json, phrasebooks/{lang}.json': 'phrases with pronunciation',
            'routes.json': 'non-stop routes between airports (IATA)',
            'rates.json': 'exchange rates, a snapshot; refetch live in the app',
            'heritage.json': 'every UNESCO World Heritage site and part, by Wikidata id',
            'flags/{slug}.svg': 'the flags too detailed to carry in the app (coats of arms), as vectors; public domain (Wikimedia Commons, via svg-country-flags)',
            'passports.json, passports/{name}.svg|.jpg': 'real passport covers as drawings, each in its own colour (the closest mix of the app\'s) with the print in the app\'s gold: Commons\' drawings recoloured, the rest traced from their Commons photographs (row 136); the index gives each file, its colour, its mix, how it was drawn and its credit',
            'sample/{photo|clip|cover}/{key}': 'the sample account\'s own pictures, clips and list-cover pictures (not the app\'s: they go with the sample)'},
        'credit': {
            'Wikivoyage': 'guides, listings, phrasebooks: CC BY-SA 4.0, credit and link Wikivoyage',
            'Wikimedia Commons': 'photos: per picture, print credits/{xx}.json "credit" under it',
            'CHELSA': 'climate: Karger et al. 2017, CC BY 4.0', 'NASA POWER': 'rain days',
            'Wikidata': 'facts, places, heritage: CC0', 'World Bank': 'CC BY 4.0',
            'GeoNames': 'cities: CC BY 4.0', 'geoBoundaries': 'shapes: CC BY 4.0',
            'Governments of Canada, the US and the UK': 'advisories: OGL-Canada, public domain, OGL v3',
            'OpenFlights': 'routes: ODbL',
            'Passport covers': 'Wikimedia Commons, per cover: passports.json "credit"'},
        'files': {k: {'records': r, 'bytes': b} for k, (r, b) in written.items()},
    }
    put('manifest.json', manifest, records=1)
    total = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(OUT) for f in fs)
    print('built %d files, %.1f MB gzipped (%.1f MB as JSON), in %.0fs' % (
        len(written), total / 1e6, sum(b for _, b in written.values()) / 1e6, time.time() - t0))

if __name__ == '__main__':
    main()

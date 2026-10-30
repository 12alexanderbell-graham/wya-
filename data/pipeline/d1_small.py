#!/usr/bin/env python3
"""D1 coverage: the first region level of five places that had none, from OpenStreetMap boundary relations
(downloaded as GeoJSON from polygons.openstreetmap.fr into d1-34/<place>/<division>.geojson) and the map's own land
of each place (land-<cc>.geojson, from the 100 m tiles): a division inside another is cut out of the bigger one, then
mapshaper cleans them and clips them to the land (Macau kept whole: the map's outline misses its peninsula), and
d2_level.py writes <cc>-1.wyar. Run in the folder holding d1-34/ and the land files; report.json gives each place's coverage of its land.
"""
import json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapely.geometry import shape
from shapely.ops import unary_union
P = {
 'x-ncy': ('northern-cyprus', 'District', 'Districts', {'lefkosa': 'Lefkoşa', 'gazimagusa': 'Gazimağusa', 'girne': 'Girne', 'guzelyurt': 'Güzelyurt', 'iskele': 'İskele', 'lefke': 'Lefke'}),
 'ky': ('cayman-islands', 'District', 'Districts', {'bodden-town': 'Bodden Town', 'east-end': 'East End', 'george-town': 'George Town', 'north-side': 'North Side', 'sister-islands': 'Sister Islands', 'west-bay': 'West Bay'}),
 'tk': ('tokelau', 'Atoll', 'Atolls', {'atafu': 'Atafu', 'fakaofo': 'Fakaofo', 'nukunonu': 'Nukunonu'}),
 'mo': ('macau', 'Parish', 'Parishes', {'nossa-senhora-de-fatima': 'Nossa Senhora de Fátima', 'santo-antonio': 'Santo António', 'sao-lazaro': 'São Lázaro', 'se': 'Sé', 'sao-lourenco': 'São Lourenço', 'nossa-senhora-do-carmo': 'Nossa Senhora do Carmo', 'sao-francisco-xavier': 'São Francisco Xavier', 'cotai': 'Cotai'}),
 'x-pmr': ('transnistria', 'District', 'Districts', {'camenca': 'Camenca', 'ribnita': 'Rîbnița', 'dubasari': 'Dubăsari', 'grigoriopol': 'Grigoriopol', 'slobozia': 'Slobozia', 'tiraspol': 'Tiraspol', 'bender': 'Bender'}),
}
report = {}
for cc, (folder, one, many, names) in P.items():
    land = shape(json.load(open(f'land-{cc}.geojson'))['geometry'])
    feats = []
    for slug, n in names.items():
        g = json.load(open(f'd1-34/{folder}/{slug}.geojson'))
        geom = shape(g['geometry'] if 'geometry' in g else g['features'][0]['geometry'] if 'features' in g else g)
        feats.append({'type': 'Feature', 'properties': {'shapeName': n, 'shapeISO': slug}, 'geometry': geom.__geo_interface__})
    # a division inside another (a city inside its district's outline) is cut out of the bigger one first
    gs = [shape(f['geometry']).buffer(0) for f in feats]
    order = sorted(range(len(gs)), key=lambda i: gs[i].area)
    for n_, i in enumerate(order):
        for j in order[:n_]:
            if gs[i].intersects(gs[j]): gs[i] = gs[i].difference(gs[j])
    for f, g in zip(feats, gs): f['geometry'] = g.__geo_interface__
    json.dump({'type': 'FeatureCollection', 'features': feats}, open(f'{cc}-div.geojson', 'w'))
    # the divisions on the map's own land: clipped to it, overlaps and gaps cleaned
    # (Macau: the map's own outline misses the peninsula, so its parishes are kept whole: a base-map defect to fix)
    clip = [] if cc == 'mo' else ['-clip', f'land-{cc}.geojson', '-clean']
    subprocess.run(['mapshaper', f'{cc}-div.geojson', '-clean'] + clip +
                   ['-o', 'format=topojson', 'quantization=1000000', f'{cc}-div.topojson'], check=True, capture_output=True)
    out = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'd2_level.py'), f'{cc}-div.topojson', cc, '1',
                          f'{cc}-1.wyar', '0', '--code-ids'], check=True, capture_output=True, text=True).stdout
    # coverage of the land by the divisions
    t = json.load(open(f'{cc}-div.topojson'))
    import subprocess as sp
    gj = sp.run(['mapshaper', f'{cc}-div.topojson', '-o', 'format=geojson', '-'], capture_output=True, text=True).stdout
    cov = unary_union([shape(f['geometry']) for f in json.loads(gj)['features'] if f['geometry']])
    report[cc] = {'type': [one, many], 'n': len(names), 'built': json.loads(out)['units'],
                  'land covered': round(cov.area / land.area, 4)}
    print(cc, report[cc])
json.dump(report, open('report.json', 'w'), ensure_ascii=False, indent=1)

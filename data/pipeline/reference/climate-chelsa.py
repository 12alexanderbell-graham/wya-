#!/usr/bin/env python3
"""Mean daily high and low per month for every capital from CHELSA v2.1 (1 km, 1981-2010,
CC BY 4.0), read straight out of the remote GeoTIFFs a row at a time, so nothing big is downloaded.
Run as  chelsa.py <var> <month>  ; writes chelsa/<var>-<mm>.json"""
import sys, json, io, os, rasterio
from rasterio.env import Env
var, m = sys.argv[1], int(sys.argv[2])
CAPS = json.load(io.open('/mnt/user-data/outputs/sync/capitals.json', encoding='utf-8'))
os.makedirs('/home/claude/facts/chelsa', exist_ok=True)
OUT = '/home/claude/facts/chelsa/%s-%02d.json' % (var, m)
if os.path.exists(OUT): print('have', OUT); sys.exit()
u = ('/vsicurl/https://os.zhdk.cloud.switch.ch/chelsav2/GLOBAL/climatologies/1981-2010/%s/'
     'CHELSA_%s_%02d_1981-2010_V.2.1.tif' % (var, var, m))
ccs = sorted(CAPS); pts = [(CAPS[c][1], CAPS[c][0]) for c in ccs]
res = {}
with Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR', CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif',
         GDAL_HTTP_MAX_RETRY='5', GDAL_HTTP_RETRY_DELAY='3'):
    with rasterio.open(u) as src:
        sc, off = src.scales[0], src.offsets[0]
        for c, v in zip(ccs, src.sample(pts)):
            x = int(v[0])
            res[c] = None if x in (0, 65535) else round(x * sc + off, 1)
json.dump(res, io.open(OUT, 'w'), ensure_ascii=False)
print('%s %02d: %d values, %d empty' % (var, m, sum(1 for x in res.values() if x is not None),
                                         sum(1 for x in res.values() if x is None)), flush=True)

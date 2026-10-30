#!/usr/bin/env python3
"""Hours of daylight, and sunrise and sunset, for the 15th of each month in every capital.
Computed here from latitude and longitude (NOAA's solar position algorithm), so it needs no
network and never goes stale.  "Four hours of light in December" is the kind of thing that
decides a trip."""
import json, io, math, datetime
CLIM='/home/claude/facts/climate.json'
CITIES='/home/claude/dl/countryInfo.txt'

def solar(lat, lon, d):
    """sunrise, sunset (UTC hours, decimal) and daylight length, or None for polar day/night."""
    n = d.toordinal() - datetime.date(2000,1,1).toordinal() + 0.5 - lon/360.0
    M = (357.5291 + 0.98560028*n) % 360
    C = 1.9148*math.sin(math.radians(M)) + 0.0200*math.sin(math.radians(2*M)) + 0.0003*math.sin(math.radians(3*M))
    L = (M + C + 180 + 102.9372) % 360
    Jt = 2451545.0 + n + 0.0053*math.sin(math.radians(M)) - 0.0069*math.sin(math.radians(2*L))
    dec = math.asin(math.sin(math.radians(L)) * math.sin(math.radians(23.4397)))
    cosw = ((math.sin(math.radians(-0.833)) - math.sin(math.radians(lat))*math.sin(dec))
            / (math.cos(math.radians(lat))*math.cos(dec)))
    if cosw >= 1: return None, None, 0.0          # sun never rises
    if cosw <= -1: return None, None, 24.0        # sun never sets
    w = math.degrees(math.acos(cosw))
    Jset = Jt + w/360.0; Jrise = Jt - w/360.0
    def hhmm(J):
        frac = (J - 2451545.0) % 1.0
        return round(frac*24, 3)
    return hhmm(Jrise), hhmm(Jset), round(w/360.0*48, 2)

caps = {}
for line in io.open(CITIES, encoding='utf-8'):
    if line.startswith('#') or not line.strip(): continue
    f = line.split('\t')
    if len(f) > 5 and f[0] and f[5]: caps[f[0]] = f[5]
coords = {}
for line in io.open('/home/claude/dl/cities500.txt', encoding='utf-8'):
    f = line.split('\t')
    if len(f) < 18: continue
    cc, name, lat, lon, feat = f[8], f[1], f[4], f[5], f[7]
    if cc in caps and (name == caps[cc] or f[2] == caps[cc]) and feat.startswith('PPLC'):
        coords.setdefault(cc, (float(lat), float(lon)))
tz = {}
for line in io.open('/home/claude/dl/cities500.txt', encoding='utf-8'):
    f = line.split('\t')
    if len(f) < 18: continue
    if f[8] in coords and f[7].startswith('PPLC'): tz.setdefault(f[8], f[17].strip())
out = {}
for cc, (lat, lon) in coords.items():
    months = []
    for m in range(1, 13):
        r, s, h = solar(lat, lon, datetime.date(2026, m, 15))
        def clock(x):
            if x is None: return None
            hh = int(x) % 24; mm = int(round((x - int(x))*60)) % 60
            return '%02d:%02d' % (hh, mm)
        months.append({'rise': clock(r), 'set': clock(s), 'hours': h})
    out[cc] = {'cap': caps.get(cc), 'll': [lat, lon], 'months': months,
               'tz': tz.get(cc), 'tzNote': 'rise and set are UTC; apply the tz for local time'}
json.dump(out, io.open('/home/claude/extra/daylight.json','w',encoding='utf-8'), ensure_ascii=False)
ex = out.get('IS') or out.get('NO') or list(out.values())[0]
print('SAVED daylight for %d capitals' % len(out))
print('  check  %s  Jun %sh  Dec %sh' % (ex['cap'], ex['months'][5]['hours'], ex['months'][11]['hours']))
for cc in ('SG','IS','AU','RU','NO','EC'):
    if cc in out:
        o = out[cc]
        print('  %s %-14s Jun %5sh (%s-%s)   Dec %5sh (%s-%s)' % (cc, o['cap'],
              o['months'][5]['hours'], o['months'][5]['rise'], o['months'][5]['set'],
              o['months'][11]['hours'], o['months'][11]['rise'], o['months'][11]['set']))

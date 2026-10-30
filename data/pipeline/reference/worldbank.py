import os
#!/usr/bin/env python3
"""The economic and human-development figures a country page shows, from the World Bank.
Free, no key, one call per indicator for the whole world, latest year that has a number."""
import json, time, urllib.request
UA = 'wya-travel-app-data/1.0 (country indicators; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
IND = {
 'NY.GDP.MKTP.CD':'gdp', 'NY.GDP.PCAP.CD':'gdpPerCapita', 'NY.GDP.PCAP.PP.CD':'gdpPerCapitaPPP',
 'SP.POP.TOTL':'population', 'SP.DYN.LE00.IN':'lifeExpectancy', 'SP.URB.TOTL.IN.ZS':'urbanPercent',
 'ST.INT.ARVL':'touristArrivals', 'ST.INT.RCPT.CD':'tourismReceipts',
 'SI.POV.GINI':'gini', 'SL.UEM.TOTL.ZS':'unemployment', 'FP.CPI.TOTL.ZG':'inflation',
 'IT.NET.USER.ZS':'internetPercent', 'EG.ELC.ACCS.ZS':'electricityPercent',
 'SP.POP.GROW':'populationGrowth', 'AG.LND.TOTL.K2':'landArea',
 'EN.POP.DNST':'populationDensity', 'SE.ADT.LITR.ZS':'literacy',
}
def get(url, t=90):
    for k in range(4):
        try:
            r = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(r, timeout=t) as f: return json.loads(f.read().decode())
        except Exception as e:
            if k == 3: return None
            time.sleep(4 * (k + 1))
out = {}
for code, key in IND.items():
    got = {}
    for page in (1, 2, 3, 4, 5, 6):
        d = get('https://api.worldbank.org/v2/country/all/indicator/%s?format=json&per_page=500'
                '&date=2015:2026&page=%d' % (code, page))
        if not d or len(d) < 2 or not d[1]: break
        for row in d[1]:
            iso = row.get('countryiso3code') or ''
            v = row.get('value'); yr = row.get('date')
            if not iso or v is None: continue
            cur = got.get(iso)
            if not cur or yr > cur[1]: got[iso] = (v, yr)
        if page >= (d[0].get('pages') or 1): break
    for iso, (v, yr) in got.items():
        out.setdefault(iso, {})[key] = [round(v, 3) if isinstance(v, float) else v, yr]
    print('  %-22s %-18s %4d countries' % (code, key, len(got)), flush=True)
json.dump(out, open('/home/claude/facts/worldbank.json', 'w'), ensure_ascii=False)
print('SAVED', len(out), 'iso3 codes')
print('FRA:', json.dumps(out.get('FRA', {}), ensure_ascii=False)[:400])

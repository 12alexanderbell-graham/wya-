"""D7's collections, the easy ones first (29 Oct 20:30): Formula 1's 2026 season as it stands (23 rounds: Bahrain and
Saudi Arabia called off in March, the Bahrain round run at Sepang in October; RaceFans' 2026 calendar page, 31 Oct 2026),
each round's circuit from Wikidata (its id and point, found by name). Writes collections-1.wyco (gzipped) for the data
server: [{id, title, scope, event, source, items: [{q, n, cc, ll, d, l}]}]."""
import json, gzip, re, sys
tracks = json.load(open(sys.argv[1])); dst = sys.argv[2]
CAL = [
 ("2026-03-08", "Australian Grand Prix", "Albert Park Circuit", "au"),
 ("2026-03-15", "Chinese Grand Prix", "Shanghai International Circuit", "cn"),
 ("2026-03-29", "Japanese Grand Prix", "Suzuka International Racing Course", "jp"),
 ("2026-05-03", "Miami Grand Prix", "Miami International Autodrome", "us"),
 ("2026-05-24", "Canadian Grand Prix", "Circuit Gilles Villeneuve", "ca"),
 ("2026-06-07", "Monaco Grand Prix", "Circuit de Monaco", "mc"),
 ("2026-06-14", "Barcelona-Catalunya Grand Prix", "Circuit de Barcelona-Catalunya", "es"),
 ("2026-06-28", "Austrian Grand Prix", "Red Bull Ring", "at"),
 ("2026-07-05", "British Grand Prix", "Silverstone Circuit", "gb"),
 ("2026-07-19", "Belgian Grand Prix", "Circuit de Spa-Francorchamps", "be"),
 ("2026-07-26", "Hungarian Grand Prix", "Hungaroring", "hu"),
 ("2026-08-23", "Dutch Grand Prix", "Circuit Zandvoort", "nl"),
 ("2026-09-06", "Italian Grand Prix", "Monza Circuit", "it"),
 ("2026-09-13", "Spanish Grand Prix", "Madring", "es"),
 ("2026-09-26", "Azerbaijan Grand Prix", "Baku City Circuit", "az"),
 ("2026-10-04", "Bahrain Grand Prix, at Sepang", "Sepang International Circuit", "my"),
 ("2026-10-11", "Singapore Grand Prix", "Marina Bay Street Circuit", "sg"),
 ("2026-10-25", "United States Grand Prix", "Circuit of the Americas", "us"),
 ("2026-11-01", "Mexico City Grand Prix", "Autódromo Hermanos Rodríguez", "mx"),
 ("2026-11-08", "São Paulo Grand Prix", "Interlagos Circuit", "br"),
 ("2026-11-21", "Las Vegas Grand Prix", "Las Vegas Strip Circuit", "us"),
 ("2026-11-29", "Qatar Grand Prix", "Lusail International Circuit", "qa"),
 ("2026-12-06", "Abu Dhabi Grand Prix", "Yas Marina Circuit", "ae"),
]
# the right hit where the search's first isn't the circuit (checked by hand)
PICK = {"Suzuka International Racing Course": "Q174170"}
# Wikidata's English label misspelt ("Spa-Francochamps"): the circuit's own name
NAME = {"Q172851": "Circuit de Spa-Francorchamps"}
items = []; missing = []
for d, gp, circuit, cc in CAL:
    hits = tracks.get(circuit) or []
    h = next((x for x in hits if x[0] == PICK.get(circuit)), None) or (hits[0] if hits else None)
    if not h: missing.append(circuit); continue
    lon, lat = map(float, re.findall(r'-?\d+\.?\d*', h[2])[:2])
    items.append({"q": h[0], "n": NAME.get(h[0], h[1]), "cc": cc, "ll": [round(lat, 5), round(lon, 5)], "d": d, "l": gp})
out = [{"id": "f1-2026", "title": "Formula 1 2026", "scope": "world", "event": True,
        "source": "Formula 1's 2026 calendar as changed in the season (RaceFans, 31 Oct 2026); circuits: Wikidata, CC0",
        "items": items}]
with gzip.open(dst, 'wb') as g: g.write(json.dumps(out, ensure_ascii=False, separators=(',', ':')).encode())
print(len(items), 'of', len(CAL), 'missing', missing)
for i in items: print(i['d'], i['q'], i['n'], i['ll'])

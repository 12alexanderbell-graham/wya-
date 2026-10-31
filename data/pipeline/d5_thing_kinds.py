"""D5's kinds: each Wikidata class seen on the server's places (places-next, 90,242 items) put in one of the twelve
kinds (Part 7.3: city, area, landmark, mountain, water, nature, spot, stay, station, route, event, other) by its English
label, or "town" (a settlement: towns come from the town data, never as things) or "drop" (not a place to go: a
company, a school, a dish). Rules are tried in order; the first that matches decides. Writes thing-kinds.json
{class: kind} and a review list."""
import json, re, sys
src, dst = sys.argv[1], sys.argv[2]
rows = json.load(open(src))
R = [
  ('drop', r'organi[sz]ation|nonprofit|charit|business|enterprise|company|airline|newspaper|publish|dish|food|team\b|club\b|'
           r'hospital|medical|school|college\b|research institute|archives|agency|embassy|consulate|high commission|prison|'
           r'military base|airbase|factory|office building|bank building|residential building|tower block|single-family|'
           r'collection|battle|administrative|educational institution|historical society|religious community|'
           r'power station|water tower|transit district|library network|library branch|bus company|theatre company|'
           r'memory institution|cultural institution|government|courthouse|county courthouse|geographic location|facility|'
           r'commercial building|building of public administration|former hospital|mine\b|grave\b|estate\b|farm\b|plantation|'
           r'Passport to Your|visitor center|border checkpoint|major regional center|component city|largest city'),
  ('spot', r'amusement park|theme park|water park|car park'),
  ('landmark', r'archaeological park|sculpture garden|historical park|historic site'),
  ('station', r'station|airport|aerodrome|aeroport|\bport\b|ferry|tram stop|railway stop|bus station|terminus|bahnhof|last station'),
  ('stay', r'hotel|\binn\b|lodge|mountain hut|wilderness hut|campground|lean-to|caravanserai'),
  ('route', r'trail|railway line|heritage railway|funicular|narrow-gauge|\broad\b|bus route|scenic route|\bstreet\b'),
  ('event', r'festival|recurring|annual event|\bfair\b|sporting event'),
  ('mountain', r'mountain|volcano|\bhill\b|summit|mountain pass|peak'),
  ('water', r'\blake\b|river|waterfall|reservoir|\bbay\b|lagoon|\bspring\b|hot spring|canal|crater lake|\bdam\b'),
  ('nature', r'park\b(?!.*amusement)|national park|nature|protected area|forest|garden|arboretum|island|archipelago|'
             r'wildlife|wetland|biosphere|valley|canyon|\bcave\b|cliff|\bcape\b|headland|peninsula|glacier|natura 2000|'
             r'remarkable tree|landform|geographical feature|recreation area|National Park|rock formation|National Forest|'
             r'proclaimed forest|cultural landscape'),
  ('area', r'neighbo|quarter\b|ortsteil|suburb|historic district|unparished area'),
  ('town', r'city|town|village|settlement|municipal|commune|comune|civil parish|county seat|census|locality|hamlet|'
           r'borough|township|frazione|kecamatan|mahalle|district capital|district municipality|prefecture|megacity|'
           r'metropolis|community|freguesia|kreisfreie|place with town|single entity of population|urban area|'
           r'local government area|county of china|district of taiwan|first-level|municipality capital|county town|'
           r'Einheitsgemeinde|Catalan historical locality|masia|region\b|polis(?!h)|ghost town'),
  ('spot', r'beach|square|viewpoint|\bzoo\b|aquarium|amusement|theme park|water park|market|shopping|department store|'
           r'restaurant|caf[eé]|\bpub\b|\bbar\b|nightclub|brewery|winery|distiller|casino|stadium|arena|sports venue|'
           r'golf|racing|venue|concert hall|theat|opera|cinema|movie|performing arts|convention|ski resort|resort|pier|'
           r'fountain|ride|roller coaster|bathing|swimming|observatory|planetarium|science center|onsen|hammam|cricket field|'
           r'tourist destination|tourist attraction|hall of fame|sylvan|seaside'),
  ('landmark', r'museum|church|cathedral|basilica|chapel|abbey|monaster|convent|priory|mosque|temple|synagogue|shrine|'
               r'\bwat\b|pagoda|gurdwara|madrasa|castle|ch[aâ]teau|palace|palazzo|fort|citadel|castrum|tower|lighthouse|'
               r'monument|memorial|statue|sculpture|bridge|archaeolog|ruins|ancient|heritage|historic|mansion|manor|villa|'
               r'country house|city hall|rathaus|capitol|parliament|gate|arch|wall|mausoleum|tomb|necropolis|cemetery|'
               r'skyscraper|windmill|watermill|dolmen|hillfort|\btell\b|amphitheat|building|structure|\bhouse\b|landmark|'
               r'cultural property|library|university|art gallery|arts? cent|cultural center|candi|hermitage|official residence|'
               r'preserved watercraft|museum ship|ensemble|construction|observation'),
]
kinds = {}
review = []
for qid, n, label in rows:
    k = 'unknown'
    for kind, rx in R:
        if label and re.search(rx, label, re.I):
            k = kind; break
    kinds[qid] = k
    review.append(f'{qid}\t{n}\t{label}\t{k}')
json.dump(kinds, open(dst, 'w'), indent=0)
open(dst.replace('.json', '-review.tsv'), 'w').write('\n'.join(review) + '\n')
import collections
print(collections.Counter(kinds.values()))

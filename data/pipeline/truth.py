# The fine geometry of every de facto / disputed line the map draws coarsely. Sources: OpenStreetMap relations at full
# detail (polygons.openstreetmap.fr, ODbL).
import json, pickle
from shapely.geometry import shape
from shapely.ops import unary_union
from shapely import make_valid
import os
OSM=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','sources','osm')
def osm(i): return make_valid(shape(json.load(open(os.path.join(OSM,'r%d.json'%i)))))
crimea=unary_union([osm(72639),osm(1574364)])
T={}
# group: (parents, [(child key, fine polygon)] in priority order): the four oblasts whole, by their OSM boundaries
T['ua']=(['o:ua'],[('p:crimea',crimea),
                   ('p:kherson-oblast',osm(71022)),
                   ('p:zaporizhzhia-oblast',osm(71980)),
                   ('p:donetsk-people-s-republic',osm(71973)),
                   ('p:luhansk-people-s-republic',osm(71971))])
T['md']=(['o:md'],[('o:x-pmr',osm(65335))])
T['ge']=(['o:ge|Asia','o:ge|Europe'],[('o:x-abk',osm(1152720)),('o:x-sos',osm(1152717))])
T['cy']=(['o:cy'],[('o:x-akrotiri',osm(3267302)),('o:x-dhekelia',osm(3267303)),('p:cyprus-u-n-buffer-zone',unary_union([osm(3263909),osm(10063900),osm(3272527)])),('o:x-ncy',osm(2514541))])
T['gr']=(['o:gr'],[('o:x-athos',osm(2135921))])
# Somaliland less Sool, which SSC-Khatumo has held since 2023 (OSM's Sool region, 1720066: the nearest drawn line;
# Somaliland still holds the far west of it around Oog)
sool=osm(1720066)
T['so']=(['o:so'],[('p:sool',sool),('o:x-som',osm(3586169).difference(sool))])
# Western Sahara: the part Morocco holds, west of the sand wall, is a piece; the rest, the Polisario's (OSM's Sahrawi
# Arab Democratic Republic, 5441968, is drawn as the land it holds), stays Western Sahara
from shapely.geometry import box
T['eh']=(['o:eh'],[('p:w-sahara-morocco',box(-18,20,-8,28).difference(osm(5441968)))])
T['cu']=(['o:cu'],[('p:guantanamo-bay-usnb',osm(20058275))])

# --- every other de facto / disputed line with a finer source. Each fine shape is kept to within about 7 km of the
# data's own piece (SAFE), so a source that draws a slightly different area never takes land from a place that is not in
# the group; the order of the children decides who has an overlap.
import pickle as _p
NE=_p.load(open('nepieces.pkl','rb'))
def SAFE(k,g,d=0.07): return make_valid(g).intersection(NE[k].buffer(d))
# Kashmir: the Line of Control and the Line of Actual Control (Siachen, Demchok and the small valleys keep the data's
# own shape: no finer source)
T['kashmir']=(['o:in','o:pk','o:cn'],[
    ('p:shaksam-valley',SAFE('p:shaksam-valley',osm(7935380))),
    ('p:aksai-chin',SAFE('p:aksai-chin',osm(2713465))),
    ('p:gilgit-baltistan',SAFE('p:gilgit-baltistan',osm(357995))),
    ('p:azad-kashmir',SAFE('p:azad-kashmir',osm(3780130))),
    ('p:jammu-and-kashmir',SAFE('p:jammu-and-kashmir',unary_union([osm(1943188),osm(5515045)])))])
# Arunachal Pradesh: its line with Assam (the McMahon line, with China, is already fine)
T['arunachal']=(['o:in'],[('p:arunachal-pradesh',SAFE('p:arunachal-pradesh',osm(2027346)))])
# Israel and Palestine: the UNDOF zone before the Golan Heights; Gaza; Areas A and B of the West Bank (OSM 1613659, the
# Palestinian-administered areas, which is what the data's Palestine piece is) inside Area C. The Green Line itself,
# East Jerusalem and the no man's lands keep the data's own shape (OSM has no finer outline of the West Bank).
T['il']=(['o:il','o:sy','o:eg|Asia','p:west-bank-area-c'],[
    ('p:undof-zone',SAFE('p:undof-zone',osm(184888))),
    ('p:golan-heights',SAFE('p:golan-heights',osm(16119376))),
    ('p:gaza',SAFE('p:gaza',osm(1473938))),
    ('o:ps',SAFE('o:ps',osm(1613659),0.02))])
# Africa: the Halayib triangle (its 1902 line with Egypt) and Abyei
T['halayib']=(['o:eg|Africa','o:sd'],[('p:halayib-triangle',SAFE('p:halayib-triangle',osm(4081614)))])
T['abyei']=(['o:sd','o:ss'],[('p:abyei',SAFE('p:abyei',osm(13501064)))])
# Venezuela's claim to the Essequibo, and Olivenza (with Taliga)
T['gy']=(['o:gy'],[('p:west-of-essequibo-river',SAFE('p:west-of-essequibo-river',osm(16782944)))])
T['es']=(['o:es'],[('p:olivenza',SAFE('p:olivenza',unary_union([osm(345593),osm(340013)])))])
pickle.dump({'groups':T},open('truth.pkl','wb'))
for g,(ps,cs) in T.items(): print(g,ps,[(k,round(c.area,4),c.geom_type) for k,c in cs])

# the data's own (Natural Earth) shape of every disputed piece and entity, from the ORIGINAL 100 m tiles
import wyad, pickle
from shapely.ops import unary_union
import rebuild as R
import sys
# the 100 m tiles as they were before any de facto rebuild: the first argument
d,h,b=wyad.pack(sys.argv[1])
acc={}
for t in h['tiles']:
    th,items,xl=wyad.tile(d,b,t)
    for k,rs in items:
        if k.startswith('p:') or k.startswith('o:x-') or k in ('o:xk','o:ps','o:eh','o:tw','o:gi'):
            g=R.geo_of(rs)
            if not g.is_empty: acc.setdefault(k,[]).append(g)
out={k:unary_union(v) for k,v in acc.items()}
pickle.dump(out,open('nepieces.pkl','wb'))
print(len(out))

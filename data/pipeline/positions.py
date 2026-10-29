import json
import os, sys
MAP=sys.argv[1] if len(sys.argv)>1 else os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','app','wya','Resources','Map')
D=json.load(open(os.path.join(MAP,'disputes.json')))
M=json.load(open(os.path.join(MAP,'world-meta.json')))
kind={p['id']:p['k'] for p in M['places']}; short={(p.get('s') or p['n']):p['id'] for p in M['places']}
objOwner={o:p['id'] for p in M['places'] for o in p.get('objs',[])}
L=D['list']; jure=D['jure']; unrec=D['unrecognised']
def some(s): return None if not s else s
def says(d,v):
    if v=='defacto':
        c=some(d.get('controller'))
        return c if c and c!='none' and c in d['options'] else None
    if v=='un':
        un=some(d.get('un'))
        if un and un!='none':
            u=short.get(un,un); return u if u in d['options'] else None
        j=jure.get(d['id']); return j if j in d['options'] else None
    o=some((d.get('owner') or {}).get(v)); return o if o in d['options'] else None
def assign(d,v): return says(d,v) or says(d,'defacto') or some(d.get('pref')) or d['default']
def drawn(i,v):
    return not any(d.get('entity')==i and not d['piece'] and assign(d,v)!=i for d in L)
def pieceOwner(d,v):
    a=assign(d,v)
    if a=='none' or a not in kind or drawn(a,v): return a
    m=next((x for x in L if x.get('entity')==a and not x['piece'] and assign(x,v)!=a),None)
    return assign(m,v) if m else a
def unitOwner(key,v):
    if key.startswith('piece:'):
        d=next((x for x in L if x['id']==key[6:]),None)
        if not d: return None
        o=pieceOwner(d,v); return o if o in kind else None
    p=objOwner.get(key)
    if not p: return None
    if drawn(p,v): return p
    d=next((x for x in L if x.get('entity')==p and not x['piece'] and assign(x,v)!=p),None)
    if not d: return p
    o=assign(d,v); return o if o in kind else None
for v in ['defacto','un','US','MA','DZ','RU','UA','IL','SO']:
    print(v, {k:unitOwner(k,v) for k in ['eh','piece:w-sahara-morocco','x-som','piece:sool','piece:crimea','piece:kherson-oblast','x-pmr']})

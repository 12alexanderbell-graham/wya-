import os
#!/usr/bin/env python3
"""What a currency is worth, so prices in a guide can be shown in the traveller's own money.
Two sources: the European Central Bank's daily reference rates (public data) and
open.er-api.com, which covers the currencies the ECB does not."""
import json, io, urllib.request, time
UA='wya-travel-app-data/1.0 (exchange rates; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
def get(u):
    for a in range(5):
        try:
            r=urllib.request.Request(u, headers={'User-Agent':UA})
            with urllib.request.urlopen(r, timeout=90) as f: return json.loads(f.read().decode())
        except Exception as e:
            print(' retry', a, str(e)[:70], flush=True); time.sleep(6*(a+1))
    return None
out={}
ecb=get('https://api.frankfurter.dev/v1/latest?base=EUR')
if ecb: out['ecb']={'date':ecb.get('date'),'base':'EUR','rates':ecb.get('rates',{}),
                    'source':'European Central Bank via frankfurter.dev'}
wide=get('https://open.er-api.com/v6/latest/USD')
if wide: out['wide']={'date':wide.get('time_last_update_utc','')[:16],'base':'USD',
                      'rates':wide.get('rates',{}),'source':wide.get('provider','open.er-api.com'),
                      'terms':wide.get('terms_of_use')}
json.dump(out, io.open('/home/claude/extra/rates.json','w',encoding='utf-8'), ensure_ascii=False, indent=1)
print('ECB %d currencies (%s); wide %d currencies (%s)' % (
    len(out.get('ecb',{}).get('rates',{})), out.get('ecb',{}).get('date'),
    len(out.get('wide',{}).get('rates',{})), out.get('wide',{}).get('date')), flush=True)

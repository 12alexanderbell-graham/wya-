import os
#!/usr/bin/env python3
import json, sys, time, urllib.parse, urllib.request
UA='wya-travel-app-data/1.0 (country facts; ' + os.environ.get('WYA_CONTACT', 'set WYA_CONTACT') + ')'
EP='https://query.wikidata.org/sparql'
def run(q, tries=4):
    for k in range(tries):
        try:
            url=EP+'?'+urllib.parse.urlencode({'query':q,'format':'json'})
            r=urllib.request.Request(url, headers={'User-Agent':UA,'Accept':'application/sparql-results+json'})
            with urllib.request.urlopen(r, timeout=180) as f:
                return json.loads(f.read().decode())['results']['bindings']
        except Exception as e:
            if k==tries-1: raise
            time.sleep(8*(k+1))

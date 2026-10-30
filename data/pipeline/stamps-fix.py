# THE STAMPS WHOSE WORDS OVERLAPPED (30 Oct): each one's parts moved or narrowed so no word runs into another or into
# the stamp's own lines; the earlier SVG is left as it is and the corrected copy written to fixed/, which
# stamps-render.py draws instead. A part is named by its path of child indices from the <svg> element (defs counted).
import os
from xml.dom import minidom
EDITS = {
    'eg': {'/1/28': 'translate(0,6) rotate(-6,182,47) translate(182,47) scale(0.9) translate(-182,-47)',  # the banner
           '/1/29': 'translate(0,3) rotate(-4,187,81)',                                                  # EGYPT
           '/1/33': 'translate(-12,-34) rotate(-10,276,168)'},                                           # Cairo, Arabic
    'ir': {'/1/5': 'translate(0,10)', '/1/6': 'translate(0,10)', '/1/7': 'translate(0,10)',              # the arrow box
           '/1/12': 'translate(0,-9)', '/1/14': 'translate(0,-4)'},                                      # ENTRY, ISFAHAN
    'lb': {'/1/8': 'translate(-6,0)', '/1/10': 'matrix(0.82,0,0,0.95,210,86)'},                          # 7982, the airport
    'pk': {'/1/5': 'translate(127,51)', '/1/6': 'translate(0,14)'},                                      # the flag, PAK
    'om': {'/1/8': 'translate(0,2) translate(146,61) scale(0.85) translate(-146,-61)'},                  # the airport line
    'ps': {'/1/3': 'translate(191,37) scale(0.8) translate(-191,-37)', '/1/5': 'translate(0,5)'},        # the two top lines
    'ye': {'/1/15': 'translate(195,223) scale(0.85,1) translate(-195,-223)'},                            # ADEN AIRPORT
    'tw': {'/1/14': 'translate(0,-4) translate(240,223) scale(0.92) translate(-240,-223)'},              # 90 above DAYS
}
os.makedirs('fixed', exist_ok=True)
for k, edits in EDITS.items():
    d = minidom.parse(f'Stamps/stamp-{k}.svg')
    for path, tr in edits.items():
        e = d.documentElement
        for i in path.strip('/').split('/'): e = [c for c in e.childNodes if c.nodeType == 1][int(i)]
        e.setAttribute('transform', tr)
    open(f'fixed/stamp-{k}.svg', 'w').write(d.documentElement.toxml())
print(len(EDITS))

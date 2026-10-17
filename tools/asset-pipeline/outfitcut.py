"""Cut outfit sheets (4 views in a row on magenta) -> outfits/outfit_<id>_<view>.png. python3 outfitcut.py"""
import os, json
from post import cut_sheet, demagenta_file
NEUTRAL = {'flatcap', 'fisherman', 'hoodie', 'skeleton', 'santahat', 'pyjamas'}
from cat import OUTFITS
V = ['side', 'tqfront', 'front', 'tqback']
rep = {}
for oid, slot, _ in OUTFITS:
    p = f'gen/outfit/{oid}.png'
    if not os.path.exists(p): continue
    res, n = cut_sheet(p, 'outfits', [f'outfit_{oid}_{v}' for v in V], min_frac=0.001, merge=30)
    if oid in NEUTRAL:
        for v in V:
            if os.path.exists(f'outfits/outfit_{oid}_{v}.png'): demagenta_file(f'outfits/outfit_{oid}_{v}.png')
    rep[oid] = {'slot': slot, 'pieces': n}
    print(oid, n)
json.dump(rep, open('outfits/report.json', 'w'), indent=1)

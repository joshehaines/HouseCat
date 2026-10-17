"""Cut pose sheets: gen/pose/<set>_<coat>.png -> cat/poses/<coat>/cat_<set>_<pose>.png. python3 posecut.py [filter]"""
import os, sys, json
from catcut import matte, pieces, save_piece
from markcut import grey_matte
from extra import POSES
flt = sys.argv[1] if len(sys.argv) > 1 else ''
rep_p = 'cat/poses/report.json'
rep = json.load(open(rep_p)) if os.path.exists(rep_p) else {}
for f in sorted(os.listdir('gen/pose')):
    if flt not in f: continue
    base = f[:-4]; st, coat = base.rsplit('_', 1)
    rgb, a = (matte if coat == 'plain' else grey_matte)(f'gen/pose/{f}')
    for merge in (10, 6, 3):
        bs = pieces(a, 0.006, merge)
        if len(bs) == 8: break
    os.makedirs(f'cat/poses/{coat}', exist_ok=True)
    for (y0, y1, x0, x1, own), nm in zip(bs, POSES):
        save_piece(rgb, a, (y0, y1, x0, x1), f'cat/poses/{coat}/cat_{st}_{nm}.png', own=own)
    rep[base] = len(bs); print(base, len(bs))
json.dump(rep, open(rep_p, 'w'), indent=1)

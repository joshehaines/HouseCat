"""Cut the cat extras: expression heads (3 views x 6), rounded ears (4 views x 2), whiskers (3 styles x L/R),
marking reference wholes (on grey). python3 extrascut.py"""
import os, json
import numpy as np
from PIL import Image
from scipy import ndimage
from catcut import matte, pieces, save_piece

EXPR = ['calm', 'slowblink', 'content', 'surprised', 'sleepy', 'squint']
os.makedirs('cat/expr', exist_ok=True); os.makedirs('cat/ears_rounded', exist_ok=True)
os.makedirs('cat/whiskers', exist_ok=True); os.makedirs('cat/markings', exist_ok=True)
report = {}

for v in ('tqfront', 'front', 'side'):
    rgb, a = matte(f'gen/cat/eyes_{v}.png')
    ps = pieces(a, 0.01, 12)
    report[f'expr_{v}'] = len(ps)
    for name, (y0, y1, x0, x1, own) in zip(EXPR, ps):
        save_piece(rgb, a, (y0, y1, x0, x1), f'cat/expr/head_{v}_{name}.png', own=own)

rgb, a = matte('gen/cat/ears_rounded.png')
ps = pieces(a, 0.002, 6)
report['ears_rounded'] = len(ps)
views = ['side', 'tqfront', 'front', 'tqback']
for k, (y0, y1, x0, x1, own) in enumerate(ps[:8]):
    save_piece(rgb, a, (y0, y1, x0, x1), f'cat/ears_rounded/ear_rounded_{views[k // 2]}_{"far" if k % 2 == 0 else "near"}.png', own=own)

# whiskers: white strokes on black -> alpha from luminance, colour white
im = np.asarray(Image.open('gen/cat/whiskers.png').convert('RGB')).astype(np.float32)
lum = im.max(axis=2)
alpha = np.clip((lum - 18) / (235 - 18), 0, 1)
ps = pieces(alpha, 0.0005, 40)
report['whiskers'] = len(ps)
styles = ['short', 'long', 'curly']
white = np.full(im.shape, 250, np.float32)
for k, (y0, y1, x0, x1, own) in enumerate(ps[:6]):
    side = 'L' if k % 2 == 0 else 'R'
    save_piece(white, alpha, (y0, y1, x0, x1), f'cat/whiskers/whiskers_{styles[k // 2]}_{side}.png', own=own)

# markings: whole cats on grey, rembg only (no cream backstop needed)
from rembg import remove
from catcut import session
for m in ('tuxedo', 'locket', 'socks'):
    src = Image.open(f'gen/cat/mark_{m}.png').convert('RGB')
    cut = remove(src, session=session())
    bb = cut.getbbox(); cut.crop(bb).save(f'cat/markings/cat_short_slim_tqfront_{m}_ref.png')
json.dump(report, open('cat/extras_report.json', 'w'), indent=1)
print(report)

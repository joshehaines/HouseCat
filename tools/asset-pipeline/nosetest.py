import glob, os, sys, json, numpy as np
from PIL import Image
import custcut as C
H = C.NOSE_HINTS
miss = []; ok = 0
fs = sorted(glob.glob('cat/custom/base/expr/*.png') + glob.glob('cat/custom/base/parts/*_head.png') + glob.glob('cat/custom/base/poses/*.png'))
if len(sys.argv) > 1: fs = [f for f in fs if sys.argv[1] in f]
for f in fs:
    rel = os.path.relpath(f, 'cat/custom/base')
    if 'sit_back' in rel or 'tqback' in rel: continue
    want = 2 if ('_front' in rel or '_tqfront' in rel) else 1
    im = np.asarray(Image.open(f).convert('RGBA')).astype(np.float32)
    h = H.get(rel)
    feat, ne, nc = C.features(im[..., :3], im[..., 3] / 255, h, exact=h is not None, want_eyes=want)
    n = int((feat[..., 2] > 0.3).sum())
    if n == 0: miss.append(rel)
    else: ok += 1
print('ok', ok, 'miss', len(miss))
for m in miss: print(' ', m)

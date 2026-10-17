import glob, os, sys, numpy as np
from PIL import Image
import custcut as C
C.HULL = sys.argv[1] == 'hull'
CLOSED = ('sleep_curl', 'slowblink', 'content', 'sleepy', 'stretch_side')
res = {'ok': 0, 'miss': [], 'extra': []}
fs = sorted(glob.glob('cat/custom/base/expr/*.png') + glob.glob('cat/custom/base/parts/*_head.png') + glob.glob('cat/custom/base/poses/*.png'))
for f in fs:
    rel = os.path.relpath(f, 'cat/custom/base')
    if 'sit_back' in rel or 'tqback' in rel: continue
    want = 2 if ('_front' in rel or '_tqfront' in rel) else 1
    im = np.asarray(Image.open(f).convert('RGBA')).astype(np.float32)
    _, ne, _ = C.features(im[..., :3], im[..., 3] / 255, None, want_eyes=want)
    closed = any(k in rel for k in CLOSED)
    if ne == want or (closed and ne == 0): res['ok'] += 1
    elif ne < want: res['miss'].append((rel, ne, want))
    else: res['extra'].append((rel, ne, want))
print(sys.argv[1], 'ok', res['ok'], 'miss', len(res['miss']), 'extra', len(res['extra']))
for m in res['miss'][:60]: print('  miss', *m)
for m in res['extra'][:30]: print('  extra', *m)

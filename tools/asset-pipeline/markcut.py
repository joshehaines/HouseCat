"""Cut marked-coat puppet sheets (grey background) into named parts.
gen/cat/markparts_<marking>_<set>_<view>.png -> cat/marked/<marking>/cat_<set>_<view>_<part>.png
python3 markcut.py [filter]"""
import os, sys, json
import numpy as np
from PIL import Image
from catcut import matte, pieces, save_piece

PARTS = ['head', 'ear_far', 'ear_near', 'torso', 'leg_front_near', 'leg_front_far', 'leg_back_near', 'leg_back_far',
         'tail_up', 'tail_curl', 'tail_low']

def grey_matte(path):
    rgb, a = matte(path)
    lum = rgb.mean(axis=2); sat = rgb.max(axis=2) - rgb.min(axis=2)
    bg = (lum > 95) & (lum < 190) & (sat < 14)
    a = np.where(bg & (a < 0.9), 0, a)
    return rgb, a

def split_ears(boxes, a):
    """If the two ears touch, the top row has 3 pieces; split the 2nd one at its narrowest column."""
    H, W = a.shape
    top = sorted([i for i, b in enumerate(boxes) if (b[0] + b[1]) / 2 / H < 0.45 and (b[2] + b[3]) / 2 / W <= 0.72],
                 key=lambda i: boxes[i][2])
    if len(top) != 3: return boxes
    i = top[1]; y0, y1, x0, x1, own = boxes[i]
    m = (a > 0.5) & own
    cols = m[y0:y1, x0:x1].sum(0); w = x1 - x0
    lo, hi = int(w * 0.3), int(w * 0.7)
    cut = x0 + lo + int(np.argmin(cols[lo:hi]))
    left = own.copy(); left[:, cut:] = False
    right = own.copy(); right[:, :cut] = False
    def bb(msk):
        ys, xs = np.where(msk & (a > 0.5)); return (ys.min(), ys.max() + 1, xs.min(), xs.max() + 1, msk)
    out = [b for k, b in enumerate(boxes) if k != i] + [bb(left), bb(right)]
    return out

def name_boxes(boxes, shape):
    H, W = shape
    cx = [((b[2] + b[3]) / 2) / W for b in boxes]
    cy = [((b[0] + b[1]) / 2) / H for b in boxes]
    area = [(b[1] - b[0]) * (b[3] - b[2]) for b in boxes]
    idx = list(range(len(boxes)))
    tails = sorted([i for i in idx if cx[i] > 0.72], key=lambda i: cy[i])
    rest = [i for i in idx if i not in tails]
    top = sorted([i for i in rest if cy[i] < 0.45], key=lambda i: cx[i])
    bottom = sorted([i for i in rest if cy[i] >= 0.45], key=lambda i: cx[i])
    names = {}
    if len(top) >= 4:
        names[top[0]] = 'head'; names[top[1]] = 'ear_far'; names[top[2]] = 'ear_near'
        names[max(top[3:], key=lambda i: area[i])] = 'torso'
    for k, i in zip(PARTS[4:8], bottom[:4]): names[i] = k
    for k, i in zip(PARTS[8:], tails[:3]): names[i] = k
    return names

if __name__ == '__main__':
    flt = sys.argv[1] if len(sys.argv) > 1 else ''
    rep_path = 'cat/marked/report.json'
    report = json.load(open(rep_path)) if os.path.exists(rep_path) else {}
    for f in sorted(os.listdir('gen/cat')):
        if not f.startswith('markparts_') or flt not in f: continue
        base = f[:-4]; _, m, rest = base.split('_', 2)          # rest = <set>_<view>
        out_dir = f'cat/marked/{m}'; os.makedirs(out_dir, exist_ok=True)
        rgb, a = grey_matte(f'gen/cat/{f}')
        for merge in (4, 1, 0):
            boxes = pieces(a, 0.002, merge) if merge else pieces(a, 0.001, 1)
            names = name_boxes(boxes, a.shape)
            if len(names) == len(PARTS): break
            boxes = split_ears(boxes, a); names = name_boxes(boxes, a.shape)
            if len(names) == len(PARTS): break
        for i, nm in names.items():
            b = boxes[i]
            save_piece(rgb, a, b[:4], f'{out_dir}/cat_{rest}_{nm}.png', own=b[4])
        missing = [k for k in PARTS if k not in names.values()]
        report[base] = {'pieces': len(boxes), 'missing': missing}
        print(base, len(boxes), 'missing', missing)
    json.dump(report, open(rep_path, 'w'), indent=1)

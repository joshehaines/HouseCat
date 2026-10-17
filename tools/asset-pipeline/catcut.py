"""Cut cat sheets painted on pale cream: rembg on the whole sheet, then split into pieces.
python3 catcut.py turn|parts"""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, '.')
from extract import session
from rembg import remove
from post import components

VIEWS = ['side', 'tqfront', 'front', 'tqback']
PARTS = ['head', 'ear_far', 'ear_near', 'torso', 'leg_front_near', 'leg_front_far', 'leg_back_near', 'leg_back_far', 'tail_up', 'tail_curl', 'tail_low']

def matte(path):
    im = Image.open(path).convert('RGB')
    cut = np.array(remove(im, session=session()))
    a = cut[..., 3].astype(np.float32) / 255
    # backstop: anything clearly cream background stays out
    rgb = np.asarray(im).astype(np.float32)
    lum = rgb.mean(axis=2); sat = rgb.max(axis=2) - rgb.min(axis=2)
    bg = (lum > 215) & (sat < 45)
    a = np.where(bg & (a < 0.9), 0, a)
    return rgb, a

def pieces(a, min_frac, merge):
    m = a > 0.5
    grown = ndimage.binary_dilation(m, iterations=merge)
    lab, n = ndimage.label(grown)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        own = (lab == i)
        if (own & m).sum() < min_frac * m.size: continue
        out.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop, own))
    out.sort(key=lambda b: (b[0] + b[1]) / 2)
    rows = []
    for b in out:
        c = (b[0] + b[1]) / 2
        if rows and abs(c - rows[-1][0]) < (b[1] - b[0]) * 0.5: rows[-1][1].append(b)
        else: rows.append([c, [b]])
    res = []
    for _, rb in rows: res += sorted(rb, key=lambda b: b[2])
    return res

def save_piece(rgb, a, box, path, pad=10, own=None):
    if own is not None: a = a * own
    y0, y1, x0, x1 = box
    y0, x0 = max(0, y0 - pad), max(0, x0 - pad); y1, x1 = min(a.shape[0], y1 + pad), min(a.shape[1], x1 + pad)
    img = Image.fromarray(np.dstack([rgb[y0:y1, x0:x1].astype(np.uint8), (a[y0:y1, x0:x1] * 255).astype(np.uint8)]))
    bb = img.getbbox(); img.crop(bb).save(path)

def do(kind):
    os.makedirs('cat', exist_ok=True)
    for f in sorted(os.listdir('gen/cat')):
        if not f.startswith(kind): continue
        rgb, a = matte(f'gen/cat/{f}')
        base = f[:-4]
        if kind == 'turn':
            s = base[5:]
            boxes = pieces(a, 0.01, 8)
            boxes = sorted(boxes, key=lambda b: b[2])
            for v, b in zip(VIEWS, boxes):
                save_piece(rgb, a, b[:4], f'cat/cat_{s}_{v}_whole.png', own=b[4])
            print(base, len(boxes))
        else:
            s_v = base[6:]
            boxes = pieces(a, 0.002, 4)
            os.makedirs(f'cat/parts_{s_v}', exist_ok=True)
            for i, b in enumerate(boxes):
                save_piece(rgb, a, b[:4], f'cat/parts_{s_v}/piece_{i:02d}.png', own=b[4])
            print(base, len(boxes), 'pieces')

if __name__ == '__main__' and sys.argv[1] in ('turn', 'parts'):
    do(sys.argv[1])


def name_parts():
    """Name cut pieces by layout: top row = head, two ears, torso; tall pieces bottom-left = legs;
    pieces in the right-hand column = tails (top to bottom: up, curl, low)."""
    import json, shutil
    report = {}
    for d in sorted(os.listdir('cat')):
        if not d.startswith('parts_') or not os.path.isdir(f'cat/{d}'): continue
        s_v = d[6:]
        info = []
        for f in sorted(os.listdir(f'cat/{d}')):
            if not f.startswith('piece_'): continue
            im = Image.open(f'cat/{d}/{f}'); a = np.asarray(im)[..., 3] > 0
            info.append((f, im.size, int(a.sum())))
        # positions come from the cut order (reading order) plus the source sheet geometry
        rgb, a = matte(f'gen/cat/parts_{s_v}.png')
        boxes = pieces(a, 0.002, 4)
        W = a.shape[1]
        cx = [((b[2] + b[3]) / 2) / W for b in boxes]
        cy = [((b[0] + b[1]) / 2) / a.shape[0] for b in boxes]
        hh = [b[1] - b[0] for b in boxes]; ww = [b[3] - b[2] for b in boxes]
        idx = list(range(len(boxes)))
        tails = sorted([i for i in idx if cx[i] > 0.72], key=lambda i: cy[i])
        rest = [i for i in idx if i not in tails]
        top = sorted([i for i in rest if cy[i] < 0.45], key=lambda i: cx[i])
        bottom = sorted([i for i in rest if cy[i] >= 0.45], key=lambda i: cx[i])
        names = {}
        if len(top) >= 4:
            names[top[0]] = 'head'; names[top[1]] = 'ear_far'; names[top[2]] = 'ear_near'
            names[max(top[3:], key=lambda i: hh[i] * ww[i])] = 'torso'
        for k, i in zip(['leg_front_near', 'leg_front_far', 'leg_back_near', 'leg_back_far'], bottom[:4]):
            names[i] = k
        for k, i in zip(['tail_up', 'tail_curl', 'tail_low'], tails[:3]):
            names[i] = k
        out = {}
        for i, nm in names.items():
            src = f'cat/{d}/piece_{i:02d}.png'
            dst = f'cat/cat_{s_v}_{nm}.png'
            shutil.copy(src, dst); out[nm] = os.path.basename(dst)
        missing = [k for k in ['head', 'ear_far', 'ear_near', 'torso', 'leg_front_near', 'leg_front_far', 'leg_back_near', 'leg_back_far', 'tail_up', 'tail_curl', 'tail_low'] if k not in out]
        report[s_v] = {'pieces': len(boxes), 'missing': missing}
        print(s_v, len(boxes), 'missing', missing)
    json.dump(report, open('cat/parts_report.json', 'w'), indent=1)

if __name__ == '__main__' and sys.argv[1] == 'name':
    name_parts()

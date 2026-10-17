"""Cut motion-effect sheets into frames. Emissive sheets (black background) get luminance alpha; magenta sheets are keyed.
Frames of a loop are padded to one cell size and aligned on a shared anchor. python3 fxcut.py
-> fx/<name>/<name>_NN.png, fx/<name>/<name>_strip.png, fx/fx.json"""
import os, json
import numpy as np
from PIL import Image
from scipy import ndimage
from post import magenta_alpha, despill, components

OUT = 'fx'
EMISSIVE = {'fire': 'bottom', 'candle': 'bottom', 'steam': 'bottom', 'smoke': 'bottom', 'water': 'center'}
KEYED = {'robin': ['perched', 'pecking', 'head_tilt', 'hop', 'takeoff', 'fly_up', 'fly_down', 'fluffed'],
         'butterfly': None,
         'reactions': ['heart', 'zzz', 'note', 'notes', 'sparkle', 'question', 'exclaim', 'paw']}
meta = json.load(open(f'{OUT}/fx.json')) if os.path.exists(f'{OUT}/fx.json') else {}

def blobs(alpha, thr, merge, min_frac):
    m = alpha > thr
    lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=merge))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        own = (lab == i) & m
        if own.sum() < min_frac * m.size: continue
        out.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop, lab == i))
    return out

def reading_order(bs):
    bs = sorted(bs, key=lambda b: (b[0] + b[1]) / 2)
    rows = []
    for b in bs:
        c = (b[0] + b[1]) / 2
        if rows and abs(c - rows[-1][0]) < (b[1] - b[0]) * 0.6: rows[-1][1].append(b)
        else: rows.append([c, [b]])
    res = []
    for _, r in rows: res += sorted(r, key=lambda b: b[2])
    return res

def pack(frames, anchor):
    """frames: list of RGBA images; pad to one cell and align on the anchor (bottom-centre or centre)."""
    W = max(f.width for f in frames) + 8; H = max(f.height for f in frames) + 8
    cells = []
    for f in frames:
        c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        x = (W - f.width) // 2
        y = H - 4 - f.height if anchor == 'bottom' else (H - f.height) // 2
        c.alpha_composite(f, (x, y)); cells.append(c)
    strip = Image.new('RGBA', (W * len(cells), H), (0, 0, 0, 0))
    for i, c in enumerate(cells): strip.alpha_composite(c, (i * W, 0))
    return cells, strip, (W, H)

for name, anchor in EMISSIVE.items():
    p = f'gen/fx/{name}.png'
    if not os.path.exists(p): continue
    a = np.asarray(Image.open(p).convert('RGB')).astype(np.float32)
    lum = a.max(axis=2)
    alpha = np.clip((lum - 12) / 200, 0, 1)
    rgb = np.where(alpha[..., None] > 0.01, np.clip(a / np.maximum(alpha[..., None], 1e-3), 0, 255), 0)
    bs = reading_order(blobs(alpha, 0.06, 18, 0.0008))
    frames = []
    for y0, y1, x0, x1, own in bs:
        al = (alpha * own)[y0:y1, x0:x1]
        frames.append(Image.fromarray(np.dstack([rgb[y0:y1, x0:x1], al * 255]).astype(np.uint8)))
    cells, strip, size = pack(frames, anchor)
    os.makedirs(f'{OUT}/{name}', exist_ok=True)
    for i, c in enumerate(cells): c.save(f'{OUT}/{name}/fx_{name}_{i:02d}.png')
    strip.save(f'{OUT}/{name}/fx_{name}_strip.png')
    meta[name] = {'frames': len(cells), 'cell': size, 'anchor': anchor, 'blend': 'add (or normal with this alpha)',
                  'note': 'luminance alpha; loop the frames at ~10 fps'}
    print(name, len(cells), size)

for name, names in KEYED.items():
    p = f'gen/fx/{name}.png'
    if not os.path.exists(p): continue
    a = np.asarray(Image.open(p).convert('RGB')).astype(np.float32)
    alpha = magenta_alpha(a); rgb = despill(a, alpha)
    bs = reading_order(blobs(alpha, 0.5, 10, 0.001))
    frames = []
    for y0, y1, x0, x1, own in bs:
        al = (alpha * own)[y0:y1, x0:x1]
        frames.append(Image.fromarray(np.dstack([rgb[y0:y1, x0:x1], al * 255]).astype(np.uint8)))
    os.makedirs(f'{OUT}/{name}', exist_ok=True)
    if names:      # separate named sprites, each cropped
        for f, nm in zip(frames, names):
            f.crop(f.getbbox()).save(f'{OUT}/{name}/fx_{name}_{nm}.png')
        meta[name] = {'sprites': names[:len(frames)], 'found': len(frames)}
    else:          # a loop: pack into cells
        cells, strip, size = pack(frames, 'center')
        for i, c in enumerate(cells): c.save(f'{OUT}/{name}/fx_{name}_{i:02d}.png')
        strip.save(f'{OUT}/{name}/fx_{name}_strip.png')
        meta[name] = {'frames': len(cells), 'cell': size, 'anchor': 'center'}
    print(name, len(frames))
json.dump(meta, open(f'{OUT}/fx.json', 'w'), indent=1)

"""Pulls each cat's garment out of an edited sheet: where the edit changed the cat (inside the mask).
A resting pose's layer is the size of the pose's master painting, so the app draws it over the pose exactly; a
standing view's is the puppet's torso part with TORSO_PAD of its size added on every side, so it rides the torso.
python extract.py <body> <tint> <garment> <edited.png> -> layers/<garment>/... + out/preview_<garment>_<body>.png"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, 'work')  # sheets, edits, layers and check-sheets (not in git)
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
TORSO_PAD = 0.15
sys.path.insert(0, HERE)
from sheet import assemble, TINTS  # noqa: E402

def lab(rgb):
    c = np.clip(rgb / 255.0, 0, 1)
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = np.einsum('...c,rc->...r', c, m) / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(np.maximum(xyz, 0)), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)

def garment_region(changed, diff, threshold):
    region = ndimage.binary_closing(changed, iterations=3)
    filled = ndimage.binary_fill_holes(region)
    # A hole the edit left alone (a paw tucked in front of the garment) stays bare; the rest is filled.
    holes, n = ndimage.label(filled & ~region)
    for i in range(1, n + 1):
        hole = holes == i
        if hole.sum() > 120 and diff[hole].mean() < threshold * 0.6:
            filled &= ~hole
    region = filled
    lab_, n = ndimage.label(region)
    if n:
        sizes = ndimage.sum(region, lab_, range(1, n + 1))
        region = np.isin(lab_, [i + 1 for i, s in enumerate(sizes) if s >= max(150, 0.03 * sizes.max())])
    return ndimage.binary_opening(region, iterations=1)

def extract(body, tint, garment, edited_path, threshold=16.0, rest=False):
    """`rest`: an edit of sheet.py's curled-up and stretching sheet (its reference tiles are left alone)."""
    stem = f'{WORK}/sheets/{body}_{tint}' + (f'_rest_{garment}' if rest else '')
    meta = json.load(open(f'{stem}.json'))
    before = np.asarray(Image.open(f'{stem}.png').convert('RGB')).astype(np.float32)
    after = np.asarray(Image.open(edited_path).convert('RGB')).astype(np.float32)
    mask = np.asarray(Image.open(f'{WORK}/sheets/{body}_rest_mask.png' if rest else f'{stem}_mask.png')) > 127
    diff = np.linalg.norm(lab(after) - lab(before), axis=-1)
    outside = diff[~ndimage.binary_dilation(mask, iterations=6)]
    changed = (ndimage.gaussian_filter(diff, 1.5) > threshold) & mask
    out_dir = f'{WORK}/layers/{garment}'
    os.makedirs(out_dir, exist_ok=True)
    report = {'outside_p99': round(float(np.percentile(outside, 99)), 1), 'cover': {}}
    for t in meta['tiles']:
        if t['kind'] == 'ref':
            continue
        x, y, w, h = t['x'], t['y'], t['w'], t['h']
        region = garment_region(changed[y:y + h, x:x + w], diff[y:y + h, x:x + w], threshold)
        alpha = np.clip(ndimage.gaussian_filter(region.astype(np.float32), 0.8), 0, 1)
        rgba = Image.fromarray(np.dstack([after[y:y + h, x:x + w], alpha * 255]).astype(np.uint8))
        full = rgba.resize(tuple(t['src']), Image.LANCZOS)   # back to master pixels
        if t['kind'] == 'pose':
            name = f'outfit_{garment}_{body}_{t["name"]}.png'
            full.save(f'{out_dir}/{name}')
        else:
            tx, ty, tw, th = t['torso']
            px, py = int(round(tw * TORSO_PAD)), int(round(th * TORSO_PAD))
            canvas = Image.new('RGBA', (tw + 2 * px, th + 2 * py), (0, 0, 0, 0))
            canvas.paste(full.crop((tx - px, ty - py, tx + tw + px, ty + th + py)), (0, 0))
            name = f'outfit_{garment}_{body}_{t["name"]}_torso.png'
            canvas.save(f'{out_dir}/{name}')
        report['cover'][t['name']] = round(float(region.mean()), 2)
    return report

def extract_better(body, tint, garment, edited_path, threshold=16.0, margin=1.25):
    """Like extract, but keeps the layer already there unless the new edit covers clearly more of that cat."""
    out_dir = f'{WORK}/layers/{garment}'
    keep = {}
    for name in os.listdir(out_dir):
        if f'_{body}_' in name:
            a = np.asarray(Image.open(f'{out_dir}/{name}'))[..., 3]
            keep[name] = (Image.open(f'{out_dir}/{name}').copy(), float((a > 127).mean()))
    report = extract(body, tint, garment, edited_path, threshold)
    chosen = {}
    for name, (old, old_cover) in keep.items():
        new_cover = float((np.asarray(Image.open(f'{out_dir}/{name}'))[..., 3] > 127).mean())
        if new_cover < old_cover * margin:
            old.save(f'{out_dir}/{name}')
            chosen[name] = 'old'
        else:
            chosen[name] = 'new'
    report['chosen'] = {k.split(f'_{body}_')[1][:-4]: v for k, v in chosen.items()}
    return report

def preview(body, garment, path):
    """The layers over a black cat and a ginger cat, for checking by eye: the six poses, then the puppet views."""
    meta = json.load(open(f'{WORK}/sheets/{body}_dark.json'))
    rows = [[], []]
    for t in meta['tiles']:
        if t['kind'] == 'pose':
            base = Image.open(f'{REPO}/assets/cat/custom/base/poses/cat_{body}_{t["name"]}.png').convert('RGBA')
            layer = Image.open(f'{WORK}/layers/{garment}/outfit_{garment}_{body}_{t["name"]}.png')
            at = (0, 0)
        else:
            base, placed = assemble(body, t['name'])
            layer = Image.open(f'{WORK}/layers/{garment}/outfit_{garment}_{body}_{t["name"]}_torso.png')
            tx, ty, tw, th = t['torso']
            at = (tx - int(round(tw * TORSO_PAD)), ty - int(round(th * TORSO_PAD)))
        for k, tint in enumerate(((0.22, 0.2, 0.22), (1.0, 0.62, 0.32))):
            a = np.asarray(base).astype(np.float32)
            a[..., :3] *= np.array(tint)
            cat = Image.fromarray(a.astype(np.uint8))
            pad = 60
            board = Image.new('RGBA', (cat.width + 2 * pad, cat.height + 2 * pad), (150, 170, 190, 255))
            board.alpha_composite(cat, (pad, pad))
            board.alpha_composite(layer, (pad + at[0], pad + at[1]))
            rows[0 if t['kind'] == 'pose' else 1].append(board.resize((int(board.width * 260 / board.height), 260)).convert('RGB'))
    width = max(sum(c.width + 8 for c in r) for r in rows)
    sheet = Image.new('RGB', (width, 530), (40, 40, 40))
    for r, row in enumerate(rows):
        x = 0
        for c in row:
            sheet.paste(c, (x, r * 270))
            x += c.width + 8
    sheet.save(path)

if __name__ == '__main__':
    body, tint, garment, edited = sys.argv[1:5]
    print(json.dumps(extract(body, tint, garment, edited)))
    preview(body, garment, f'{WORK}/out/preview_{garment}_{body}.png')

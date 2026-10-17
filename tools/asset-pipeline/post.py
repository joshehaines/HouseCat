"""Post-processing for everything painted on flat magenta (and a few special cases).
python3 post.py houses|terrain|strips|weather|cobweb|glows|sheet <args>"""
import sys, os, json
import numpy as np, cv2
from PIL import Image
from scipy import ndimage

def magenta_alpha(a, connected_only=False):
    """Soft alpha that removes flat magenta. a = float RGB array."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # 'magentaness': how far the pixel is towards (255,0,255)
    m = np.clip(((r + b) / 2 - g - 60) / 120, 0, 1) * (np.abs(r - b) < 110)
    hard = m > 0.5
    if connected_only:
        lab, n = ndimage.label(hard)
        border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        keep = np.isin(lab, list(border))
        m = np.where(ndimage.binary_dilation(keep, iterations=2), m, 0)
    alpha = 1 - m
    alpha = cv2.GaussianBlur(alpha.astype(np.float32), (0, 0), 0.7)
    return np.clip(alpha, 0, 1)

def despill(a, alpha):
    """Pull residual magenta out of semi-transparent edge pixels."""
    out = a.copy()
    edge = (alpha < 0.98) & (alpha > 0.02)
    r, g, b = out[..., 0], out[..., 1], out[..., 2]
    spill = edge & (r > g + 25) & (b > g + 25)
    mid = (r + g + b) / 3
    for c in (0, 2):
        out[..., c] = np.where(spill, g + (out[..., c] - g) * 0.35, out[..., c])
    return out

def cyan_mask(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = (r < 120) & (g > 160) & (b > 160) & (np.abs(g - b) < 90)
    return ndimage.binary_opening(m, iterations=1)

def save_rgba(rgb, alpha, path, crop=True):
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)]))
    bbox = img.getbbox() if crop else None
    if bbox: img = img.crop(bbox)
    img.save(path)
    return bbox

def components(alpha, min_frac=0.002, merge=25):
    """Bounding boxes of separate sprites on a sheet, small specks merged into neighbours, reading order."""
    m = alpha > 0.5
    grown = ndimage.binary_dilation(m, iterations=merge)
    lab, n = ndimage.label(grown)
    boxes = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        part = (lab[sl] == i) & m[sl]
        if part.sum() < min_frac * m.size: continue
        boxes.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop, part.sum()))
    # reading order: cluster rows by vertical centre
    boxes.sort(key=lambda b: (b[0] + b[1]) / 2)
    rows = []
    for b in boxes:
        c = (b[0] + b[1]) / 2
        if rows and abs(c - rows[-1][0]) < (b[1] - b[0]) * 0.5: rows[-1][1].append(b)
        else: rows.append([c, [b]])
    out = []
    for _, rb in rows: out += sorted(rb, key=lambda b: b[2])
    return out

def cut_sheet(path, outdir, names, min_frac=0.002, merge=25):
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    alpha = magenta_alpha(a)
    rgb = despill(a, alpha)
    boxes = components(alpha, min_frac, merge)
    os.makedirs(outdir, exist_ok=True)
    res = []
    for i, (y0, y1, x0, x1, _) in enumerate(boxes):
        nm = names[i] if i < len(names) else f'extra{i}'
        p = 12
        y0, x0 = max(0, y0 - p), max(0, x0 - p); y1, x1 = min(a.shape[0], y1 + p), min(a.shape[1], x1 + p)
        save_rgba(rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1], f'{outdir}/{nm}.png')
        res.append((nm, (x0, y0, x1, y1)))
    return res, len(boxes)

def houses():
    os.makedirs('world/houses', exist_ok=True)
    for f in sorted(os.listdir('gen/house')):
        iid = f[:-4]
        a = np.asarray(Image.open(f'gen/house/{f}').convert('RGB')).astype(np.float32)
        alpha = magenta_alpha(a, connected_only=False)
        glass = cyan_mask(a) & (alpha > 0.5)
        rgb = despill(a, alpha)
        body = alpha * (~glass)
        bbox = save_rgba(rgb, body, f'world/houses/ext_{iid}.png')
        Image.fromarray((glass * 255).astype(np.uint8)).crop(bbox).save(f'world/houses/ext_{iid}_glass.png')
        print(iid, bbox)

def terrain():
    os.makedirs('world/terrain', exist_ok=True)
    for f in sorted(os.listdir('gen/terrain')):
        a = np.asarray(Image.open(f'gen/terrain/{f}').convert('RGB')).astype(np.float32)
        alpha = magenta_alpha(a, connected_only=False)
        rgb = despill(a, alpha)
        save_rgba(rgb, alpha, f'world/terrain/terr_{f}', crop=False)
        print(f, 'sky fraction %.2f' % (1 - alpha.mean()))

def strips():
    os.makedirs('surfaces/garden_strips', exist_ok=True)
    for f in sorted(os.listdir('gen/strip')):
        a = np.asarray(Image.open(f'gen/strip/{f}').convert('RGB')).astype(np.float32)
        alpha = magenta_alpha(a, connected_only=False)
        rgb = despill(a, alpha)
        h, w = alpha.shape
        # horizontal wrap: cross-fade the outer 12% with the half-shifted copy
        sh = w // 2
        rgb2 = np.roll(rgb, sh, axis=1); al2 = np.roll(alpha, sh, axis=1)
        x = np.arange(w) / (w - 1); d = np.minimum(x, 1 - x); t = np.clip(d / 0.12, 0, 1); wgt = (t * t * (3 - 2 * t))[None, :]
        rgb = rgb * wgt[..., None] + rgb2 * (1 - wgt[..., None]); alpha = alpha * wgt + al2 * (1 - wgt)
        ys = np.where(alpha.max(axis=1) > 0.05)[0]
        y0 = ys.min()
        save_rgba(rgb[y0:], alpha[y0:], f'surfaces/garden_strips/strip_{f}', crop=False)
        print(f, 'height', h - y0)

def weather():
    res, n = cut_sheet('gen/misc/weather_sheet.png', 'world/weather', ['raindrop', 'snowflake', 'leaf', 'petal', 'cloud', 'fog'])
    print(n, res)

def cobweb():
    a = np.asarray(Image.open('gen/misc/cobweb.png').convert('RGB')).astype(np.float32)
    lum = a.mean(axis=2) / 255
    alpha = np.clip((lum - 0.06) / 0.6, 0, 1)
    rgb = np.full_like(a, 240); rgb[..., 2] = 250
    for side, arr in (('R', alpha), ('L', alpha[:, ::-1])):
        save_rgba(rgb if side == 'R' else rgb[:, ::-1], arr, f'sprites/attic/furn_attic_cobweb_{side}.png')
    print('cobweb done')

def glows():
    for p in ['sprites/garden/furn_garden_sunpatch_R.png', 'sprites/garden/furn_garden_sunpatch_L.png',
              'sprites/attic/furn_attic_skylightpatch_R.png', 'sprites/attic/furn_attic_skylightpatch_L.png']:
        if not os.path.exists(p): continue
        keep = p.replace('.png', '_painted.png')
        if not os.path.exists(keep): os.rename(p, keep)
        a = np.asarray(Image.open(keep).convert('RGBA')).astype(np.float32)
        shape = (a[..., 3] > 0).astype(np.float32)
        shape = cv2.GaussianBlur(shape, (0, 0), max(4, shape.shape[1] / 40))
        rgb = np.zeros(a.shape[:2] + (3,), np.float32); rgb[...] = (255, 226, 160)
        save_rgba(rgb, shape * 0.55, p)
        print('glow', p)

if __name__ == '__main__':
    globals()[sys.argv[1]]()

def demagenta_file(path, strength=0.75):
    """Remove a magenta colour cast from an already-cut sprite (for items meant to be neutral grey/cream)."""
    im = np.asarray(Image.open(path).convert('RGBA')).astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    cast = np.clip(np.minimum(r, b) - g, 0, None)
    im[..., 0] = r - cast * strength; im[..., 2] = b - cast * strength
    Image.fromarray(np.clip(im, 0, 255).astype(np.uint8), 'RGBA').save(path)

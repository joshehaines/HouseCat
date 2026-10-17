"""Cut the cat-builder sheets.
White base sheet gen/cust/w_<id>.png -> sprites under cat/custom/base/...
Each overlay gen/cust/ov_<pattern>__w_<id>.png -> greyscale mask with the SAME size and crop as the base sprite,
under cat/custom/masks/<pattern>/... ; features masks (iris L/R + nose) under cat/custom/masks/features/...
python3 custcut.py [filter]
"""
import os, sys, json, re
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage.morphology import convex_hull_image
HULL = True
from catcut import matte, pieces
from markcut import name_boxes, split_ears, PARTS
from extra import POSES

SETS = ['short_slim', 'short_chunky', 'long_slim', 'long_chunky']
BREEDS = ['persian', 'siamese', 'mainecoon', 'sphynx']
VIEWS = ['side', 'tqfront', 'front', 'tqback']
EXPR = ['calm', 'slowblink', 'content', 'surprised', 'sleepy', 'squint']
OUT = 'cat/custom'
REPORT = os.environ.get('CUT_REPORT', f'{OUT}/cut_report.json')
# hand-placed nose positions (fraction of sprite width, height) for whole-cat poses with closed eyes
NOSE_HINTS = json.load(open('nose_hints.json')) if os.path.exists('nose_hints.json') else {}


def grey_matte(path):
    rgb, a = matte(path)
    lum = rgb.mean(axis=2); sat = rgb.max(axis=2) - rgb.min(axis=2)
    bg = (lum > 95) & (lum < 190) & (sat < 14)
    a = np.where(bg & (a < 0.9), 0, a)
    return rgb, a


def lum(rgb): return (rgb @ np.array([0.3, 0.55, 0.15], np.float32)) / 255.0


def decontaminate(rgb, a):
    """Edge pixels are a blend of fur and the grey background: give every soft-edge pixel the colour of the nearest
    solid pixel so a tinted cat has no dark grey rim. Alpha keeps the soft silhouette."""
    solid = a >= 0.9
    if not solid.any(): return rgb
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    fill = rgb[iy, ix]
    w = np.clip((a - 0.6) / 0.3, 0, 1)[..., None]      # alpha 0.9+ keeps its own colour, below 0.6 takes the fill
    return rgb * w + fill * (1 - w)


def grid_split(a, rows, cols):
    """Fallback for fluffy sheets whose pieces touch: cut the sheet into a rows x cols grid at the emptiest lines."""
    m = a > 0.3
    ys, xs = np.where(m)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    def cuts(prof, lo, hi, n):
        out = [lo]
        for c in range(1, n):
            e = lo + (hi - lo) * c / n; w = (hi - lo) / n * 0.3
            s, t2 = int(e - w), int(e + w)
            out.append(s + int(np.argmin(prof[s:t2])))
        return out + [hi]
    cx = cuts(m.sum(0), x0, x1, cols); cy = cuts(m.sum(1), y0, y1, rows)
    res = []
    for r in range(rows):
        for c in range(cols):
            own = np.zeros_like(m); own[cy[r]:cy[r + 1], cx[c]:cx[c + 1]] = True
            yy, xx = np.where(own & m)
            if not len(yy): continue
            # keep only the biggest blob in the cell (drops stray wisps from the neighbour)
            lab, n = ndimage.label(own & m)
            if n > 1:
                sz = ndimage.sum(own & m, lab, range(1, n + 1)); big = lab == (int(np.argmax(sz)) + 1)
                own = own & ndimage.binary_dilation(big, iterations=6)
                yy, xx = np.where(own & m)
            res.append((yy.min(), yy.max() + 1, xx.min(), xx.max() + 1, own))
    return res


def layout(kind, a):
    """-> list of (name, (y0,y1,x0,x1), own) for the pieces of a sheet."""
    if kind == 'parts':
        for merge in (4, 1, 0):
            boxes = pieces(a, 0.002, merge) if merge else pieces(a, 0.001, 1)
            names = name_boxes(boxes, a.shape)
            if len(names) == len(PARTS): break
            boxes = split_ears(boxes, a); names = name_boxes(boxes, a.shape)
            if len(names) == len(PARTS): break
        return [(nm, boxes[i][:4], boxes[i][4]) for i, nm in names.items()]
    if kind == 'pose':
        for merge in (10, 6, 3):
            bs = pieces(a, 0.006, merge)
            if len(bs) == 8: break
        return [(nm, b[:4], b[4]) for nm, b in zip(POSES, bs)]
    if kind == 'expr':
        for merge in (12, 6, 2):
            bs = pieces(a, 0.01, merge)
            if len(bs) == 6: break
        if len(bs) != 6: bs = grid_split(a, 2, 3)
        return [(nm, b[:4], b[4]) for nm, b in zip(EXPR, bs)]
    if kind == 'ears':
        bs = sorted(pieces(a, 0.002, 6), key=lambda b: b[2])[:8]
        return [(f'{VIEWS[k // 2]}_{"far" if k % 2 == 0 else "near"}', b[:4], b[4]) for k, b in enumerate(bs)]
    if kind == 'bobtail':
        bs = pieces(a, 0.002, 6)[:12]          # reading order: rows (up, curl, low) x columns (views)
        rows = ['up', 'curl', 'low']
        return [(f'{VIEWS[k % 4]}_{rows[k // 4]}', b[:4], b[4]) for k, b in enumerate(bs)]
    if kind == 'turn':
        bs = sorted(pieces(a, 0.01, 8), key=lambda b: b[2])[:4]
        if len(bs) != 4: bs = sorted(pieces(a, 0.01, 2), key=lambda b: b[2])[:4]
        if len(bs) != 4: bs = grid_split(a, 1, 4)
        return [(v, b[:4], b[4]) for v, b in zip(VIEWS, bs)]


def parse(base_id):
    """w_<...> -> (kind, body, view) and a function name -> relative output path."""
    m = re.match(r'w_parts_(\w+)_(side|tqfront|front|tqback)$', base_id)
    if m: b, v = m.groups(); return 'parts', lambda nm: f'parts/cat_{b}_{v}_{nm}.png'
    m = re.match(r'w_pose_(\w+?)__(\w+)$', base_id)     # ear / tail variant of a pose sheet (variants.py)
    if m: b, var = m.groups(); return 'pose', lambda nm: f'poses/cat_{b}_{nm}__{var}.png'
    m = re.match(r'w_expr_noear_(tqfront|front|side)$', base_id)   # ear-less standard expression heads
    if m: v = m.group(1); return 'expr', lambda nm: f'expr/head_stdnoear_{v}_{nm}.png'
    m = re.match(r'w_pose_(\w+)$', base_id)
    if m: b = m.group(1); return 'pose', lambda nm: f'poses/cat_{b}_{nm}.png'
    m = re.match(r'w_expr_(?:(\w+)_)?(tqfront|front|side)$', base_id)
    if m: b, v = m.groups(); b = b or 'std'; return 'expr', lambda nm: f'expr/head_{b}_{v}_{nm}.png'
    m = re.match(r'w_ears_(\w+)$', base_id)
    if m: e = m.group(1); return 'ears', lambda nm: f'ears/ear_{e}_{nm}.png'
    if base_id == 'w_bobtail': return 'bobtail', lambda nm: f'tails/bobtail_{nm}.png'
    m = re.match(r'w_turn_(\w+)$', base_id)
    if m: b = m.group(1); return 'turn', lambda nm: f'whole/cat_{b}_{nm}_whole.png'
    return None, None


def parent(base_id):
    """A variant sheet (variants.py) is an edit of a parent sheet that changes only ears or tail: it reuses the parent's
    pattern overlays."""
    if '__' in base_id: return base_id.split('__')[0]
    m = re.match(r'w_expr_noear_(tqfront|front|side)$', base_id)
    return f'w_expr_{m.group(1)}' if m else base_id


def piece_boxes(kind, a):
    """name -> tight box of each piece (same rule as cut_base)."""
    H, W = a.shape; out = {}
    for nm, (y0, y1, x0, x1), own in layout(kind, a):
        aa = a * own; pad = 10
        Y0, X0, Y1, X1 = max(0, y0 - pad), max(0, x0 - pad), min(H, y1 + pad), min(W, x1 + pad)
        ys, xs = np.where(aa[Y0:Y1, X0:X1] > 0.004)
        if len(ys): out[nm] = (Y0 + ys.min(), Y0 + ys.max() + 1, X0 + xs.min(), X0 + xs.max() + 1)
    return out


def align(base_l, ov_l, mask):
    """Integer shift that best aligns the overlay to the base (phase correlation on luminance inside the cat)."""
    A = np.where(mask, base_l, 0); B = np.where(mask, ov_l, 0)
    F = np.fft.fft2(A) * np.conj(np.fft.fft2(B))
    r = np.fft.ifft2(F / (np.abs(F) + 1e-9)).real
    dy, dx = np.unravel_index(np.argmax(r), r.shape)
    if dy > r.shape[0] // 2: dy -= r.shape[0]
    if dx > r.shape[1] // 2: dx -= r.shape[1]
    return int(dy), int(dx)


def features(rgb, a, hint=None, exact=False, want_eyes=None):
    """Iris of each eye (left/right in the image) + nose leather. The white bases all have amber eyes: an eye is a warm,
    saturated blob well inside the silhouette (the warm rim light sits on the edge and is excluded)."""
    mx, mn = rgb.max(2), rgb.min(2); sat = (mx - mn) / np.maximum(mx, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1e-3)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    dark = mx < 70

    def find_eyes(erode):
        inner = ndimage.binary_erosion(a > 0.5, iterations=erode)
        warm = (hue > 22) & (hue < 70) & (sat > 0.22) & (mx > 90) & inner
        warm = ndimage.binary_closing(warm, iterations=2)
        lab, n = ndimage.label(warm)
        if not n: return lab, []
        sizes = ndimage.sum(warm, lab, range(1, n + 1))
        # an iris always wraps a dark pupil: drop warm patches with no dark centre (inner ears, rim light, chest)
        ok = []
        for i, sl in enumerate(ndimage.find_objects(lab)):
            blob = lab[sl] == i + 1
            if sizes[i] < 40: continue
            # the pupil can break the iris ring open (a crescent), so test the blob's convex hull, not its filled shape
            near = ndimage.binary_dilation(convex_hull_image(blob) if HULL else ndimage.binary_fill_holes(blob), iterations=3)
            if (dark[sl] & near).sum() >= 0.12 * sizes[i]: ok.append(i)
        if not ok: return lab, []
        sizes = np.array([sizes[i] if i in ok else 0 for i in range(n)])
        big = [i for i in ok if sizes[i] >= max(40, 0.18 * sizes.max())]
        big = sorted(big, key=lambda i: -sizes[i])[:2]
        cx = ndimage.center_of_mass(warm, lab, [i + 1 for i in big])
        return lab, [i for _, i in sorted(zip([c[1] for c in cx], big))]

    lab, order = find_eyes(10)
    if want_eyes == 2 and len(order) < 2:     # a 3/4 face can put the far eye right on the silhouette edge
        lab2, order2 = find_eyes(3)
        if len(order2) > len(order): lab, order = lab2, order2
    L = np.zeros(a.shape, np.float32); R = np.zeros(a.shape, np.float32)
    if len(order) == 2 and (ndimage.binary_dilation(lab == order[0] + 1, iterations=6) & (lab == order[1] + 1)).any():
        lab = np.where(lab == order[1] + 1, order[0] + 1, lab); order = order[:1]   # a highlight split one iris in two
    for k, i in enumerate(order):
        eye = ndimage.binary_fill_holes(lab == i + 1)
        # recolour the iris only: not the dark pupil / outline, not the white catchlight
        w = np.clip((mx - 70) / 50, 0, 1) * np.clip((sat - 0.08) / 0.12, 0, 1)
        m = ndimage.gaussian_filter(eye.astype(np.float32), 0.6) * w
        if len(order) == 1:   # one eye visible (side view): call it the near eye = left channel
            L = m
        else:
            (L if k == 0 else R)[:] = m
    # nose leather: a small pink blob. Inner ears are the big pink shapes; the nose sits just below the eyes when
    # they are visible, otherwise it is the small pink blob with the dark nostril/mouth line right under it.
    nose = ((hue > 330) | (hue < 18)) & (sat > 0.16) & (mx > 120) & (a > 0.5)
    lab, n = ndimage.label(nose)
    N = np.zeros(a.shape, np.float32)
    eyes = [ndimage.center_of_mass(m) for m in (L, R) if (m > 0.2).any()]
    if hint is not None and exact:
        # hand-placed point (nose_hints.json): profiles and sleeping poses, where the nose is tiny or the eyes closed.
        # Take the pink patch nearest the point, inside a small disc, with a looser pink test.
        hy, hx = hint[1] * a.shape[0], hint[0] * a.shape[1]
        yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
        rad = (hint[2] if len(hint) > 2 else 0.035) * np.hypot(*a.shape)
        disc = np.hypot(yy - hy, xx - hx) < rad
        soft = ((hue > 325) | (hue < 20)) & (sat > 0.10) & (mx > 90) & (a > 0.3) & disc
        lab2, n2 = ndimage.label(soft)
        if n2:
            c2 = ndimage.center_of_mass(soft, lab2, range(1, n2 + 1))
            s2 = ndimage.sum(soft, lab2, range(1, n2 + 1))
            ok = [i for i in range(n2) if s2[i] >= 6]
            if ok:
                # the biggest pink patch, discounted by its distance from the point
                i = max(ok, key=lambda i: s2[i] * np.exp(-np.hypot(c2[i][0] - hy, c2[i][1] - hx) / (0.5 * rad)))
                N = ndimage.gaussian_filter((lab2 == i + 1).astype(np.float32), 0.7)
    elif n:
        sizes = ndimage.sum(nose, lab, range(1, n + 1))
        cms = ndimage.center_of_mass(nose, lab, range(1, n + 1))
        best, score = None, -1e9
        if not eyes:     # closed eyes: only with a hint (nose position borrowed from the open-eyed calm head)
            if hint is not None:
                hy, hx = hint[1] * a.shape[0], hint[0] * a.shape[1]
                dists = [np.hypot(c[0] - hy, c[1] - hx) for c in cms]
                ok = [i for i in range(n) if sizes[i] >= 12 and dists[i] < 0.12 * np.hypot(*a.shape)]
                if ok:
                    i = min(ok, key=lambda i: dists[i]); N = ndimage.gaussian_filter((lab == i + 1).astype(np.float32), 0.7)
        else:
            ey = np.mean([e[0] for e in eyes]); ex = np.mean([e[1] for e in eyes])
            span = max(abs(eyes[0][1] - eyes[-1][1]), 0.18 * a.shape[1])
            for i in range(n):
                if sizes[i] < 0.0003 * a.size or sizes[i] > 0.012 * a.size: continue   # inner ears sit above the eyes
                dy, dx = cms[i][0] - ey, cms[i][1] - ex
                if len(eyes) == 1:     # profile: the nose is out at the tip of the face, about level with the eye
                    if dy < -0.6 * span or dy > 1.2 * span or np.hypot(dy, dx) > 2.8 * span: continue
                elif dy < -0.1 * span or dy > 0.75 * span or np.hypot(dy, dx) > 1.1 * span: continue
                if sizes[i] > score: best, score = i + 1, sizes[i]       # the biggest small pink blob below the eyes
            if best: N = ndimage.gaussian_filter((lab == best).astype(np.float32), 0.7)
    nc = None
    if N.max() > 0.3:
        cy, cx = ndimage.center_of_mass(N > 0.3); nc = (cx / a.shape[1], cy / a.shape[0])
    return np.dstack([L, R, N]), int((L > 0.2).any()) + int((R > 0.2).any()), nc


def save_rgba(rgb, a, box, path):
    y0, y1, x0, x1 = box
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.dstack([rgb[y0:y1, x0:x1], a[y0:y1, x0:x1] * 255]).clip(0, 255).astype(np.uint8)).save(path)


def cut_base(base_id, report):
    kind, path_of = parse(base_id)
    src = f'gen/cust/{base_id}.png'
    rgb, a = grey_matte(src)
    clean = decontaminate(rgb, a)
    pcs = layout(kind, a)
    H, W = a.shape
    boxes = {}
    hint_from = {}
    var_hints = {}
    if kind == 'pose' and parent(base_id) != base_id:
        _, ppath = parse(parent(base_id)); _, pa = grey_matte(f'gen/cust/{parent(base_id)}.png')
        for nm, (py0, py1, px0, px1) in piece_boxes('pose', pa).items():
            h = NOSE_HINTS.get(ppath(nm))
            if h: var_hints[nm] = (px0 + h[0] * (px1 - px0), py0 + h[1] * (py1 - py0)) + tuple(h[2:])
    if kind == 'expr':          # do the open-eyed heads first so the closed-eyed ones can borrow their nose position
        pcs = sorted(pcs, key=lambda p: p[0] in ('slowblink', 'content', 'sleepy'))
    for nm, (y0, y1, x0, x1), own in pcs:
        aa = a * own
        pad = 10
        Y0, X0, Y1, X1 = max(0, y0 - pad), max(0, x0 - pad), min(H, y1 + pad), min(W, x1 + pad)
        ys, xs = np.where(aa[Y0:Y1, X0:X1] > 0.004)
        if not len(ys): continue
        box = (Y0 + ys.min(), Y0 + ys.max() + 1, X0 + xs.min(), X0 + xs.max() + 1)
        rel = path_of(nm)
        save_rgba(clean, aa, box, f'{OUT}/base/{rel}')
        boxes[nm] = (box, own)
        if kind in ('parts', 'pose', 'expr', 'turn') and (nm == 'head' or kind != 'parts'):
            hint = hint_from.get('calm') if kind == 'expr' else NOSE_HINTS.get(rel)
            if nm in var_hints:
                hx, hy = var_hints[nm][:2]
                hint = [(hx - box[2]) / (box[3] - box[2]), (hy - box[0]) / (box[1] - box[0])] + list(var_hints[nm][2:])
            f, neyes, nc = features(rgb[box[0]:box[1], box[2]:box[3]], aa[box[0]:box[1], box[2]:box[3]], hint,
                                    exact=kind != 'expr' and (rel in NOSE_HINTS or nm in var_hints),
                                    want_eyes=2 if ('_front' in rel or '_tqfront' in rel) else 1)
            if nm == 'calm' and nc: hint_from['calm'] = nc
            if neyes or f[..., 2].any():
                p = f'{OUT}/masks/features/{rel}'; os.makedirs(os.path.dirname(p), exist_ok=True)
                Image.fromarray((f * 255).clip(0, 255).astype(np.uint8)).save(p)
    expect = {'parts': 11, 'pose': 8, 'expr': 6, 'ears': 8, 'bobtail': 12, 'turn': 4}[kind]
    report[base_id] = {'kind': kind, 'pieces': len(boxes), 'expected': expect, 'overlays': {}}
    return kind, path_of, rgb, a, boxes


def cut_overlay(base_id, pattern, kind, path_of, rgb, a, boxes, report):
    ov = np.asarray(Image.open(f'gen/cust/ov_{pattern}__{parent(base_id)}.png').convert('RGB')).astype(np.float32)
    if ov.shape != rgb.shape:
        ov = np.asarray(Image.fromarray(ov.astype(np.uint8)).resize((rgb.shape[1], rgb.shape[0]), Image.LANCZOS)).astype(np.float32)
    Lw, Lt = lum(rgb), lum(ov)
    inside = a > 0.5
    dy, dx = align(Lw, Lt, ndimage.binary_dilation(inside, iterations=6))
    if abs(dy) <= 8 and abs(dx) <= 8 and (dy or dx):
        Lt = np.roll(Lt, (dy, dx), axis=(0, 1)); ov = np.roll(ov, (dy, dx), axis=(0, 1))
    # silhouette agreement: the overlay's cat should sit where the base cat is
    obg = np.median(np.concatenate([ov[:6].reshape(-1, 3), ov[-6:].reshape(-1, 3)]), axis=0)
    osil = np.abs(ov - obg).sum(2) > 40
    iou = float((osil & inside).sum() / max((osil | inside).sum(), 1))
    m = np.clip((Lw - Lt - 0.05) / 0.28, 0, 1)
    m = ndimage.gaussian_filter(m, 0.8)
    if parent(base_id) != base_id:
        # a variant's new fur (bigger ears, fur where a tail used to be) has no pattern in the parent's overlay: plain coat
        new = inside & ~ndimage.binary_dilation(osil, iterations=3)
        m = np.where(new, 1.0 if pattern.startswith('white_') else 0.0, m)
    solid = a >= 0.9
    if solid.any():          # soft edges take the mask of the nearest solid pixel (the edge itself is unreliable)
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        m = np.where(solid, m, m[iy, ix])
    if pattern.startswith('white_'):
        m = 1 - m            # white_* masks: 1 = this fur is white
    cover = []
    crops = {nm: ((m * (own > 0))[b[0]:b[1], b[2]:b[3]], a[b[0]:b[1], b[2]:b[3]]) for nm, (b, own) in boxes.items()}
    if kind == 'expr' and 'calm' in crops:
        # the six expression heads are one head with different eyes: give every head the calm head's markings so the
        # pattern doesn't jump when the app swaps heads (blink, squint...)
        mc, ac = crops['calm']
        for nm in list(crops):
            if nm == 'calm': continue
            mo, ao = crops[nm]
            H2, W2 = max(ac.shape[0], ao.shape[0]), max(ac.shape[1], ao.shape[1])
            A = np.zeros((H2, W2)); B = np.zeros((H2, W2)); M = np.zeros((H2, W2))
            A[:ao.shape[0], :ao.shape[1]] = ao; B[:ac.shape[0], :ac.shape[1]] = ac; M[:ac.shape[0], :ac.shape[1]] = mc
            dy2, dx2 = align(A, B, np.ones_like(A, bool))
            Ms = np.roll(M, (dy2, dx2), axis=(0, 1))[:ao.shape[0], :ao.shape[1]]
            Bs = np.roll(B, (dy2, dx2), axis=(0, 1))[:ao.shape[0], :ao.shape[1]]
            iou2 = ((Bs > 0.5) & (ao > 0.5)).sum() / max(((Bs > 0.5) | (ao > 0.5)).sum(), 1)
            if iou2 > 0.85:
                crops[nm] = (np.where(Bs > 0.5, Ms, mo), ao)
    for nm, (box, own) in boxes.items():
        y0, y1, x0, x1 = box
        mm = crops[nm][0] * (a[y0:y1, x0:x1] > 0.004)
        p = f'{OUT}/masks/{pattern}/{path_of(nm)}'; os.makedirs(os.path.dirname(p), exist_ok=True)
        Image.fromarray((mm * 255).clip(0, 255).astype(np.uint8), 'L').save(p)
        cover.append(float(mm[a[y0:y1, x0:x1] > 0.5].mean()) if (a[y0:y1, x0:x1] > 0.5).any() else 0)
    report[base_id]['overlays'][pattern] = {'shift': [dy, dx], 'iou': round(iou, 3), 'coverage': round(float(np.mean(cover)), 3)}


if __name__ == '__main__':
    flt = sys.argv[1] if len(sys.argv) > 1 else ''
    report = json.load(open(REPORT)) if os.path.exists(REPORT) else {}
    files = sorted(os.listdir('gen/cust'))
    for f in files:
        if not f.startswith('w_') or not re.search(flt, f) or f.endswith('_v1.png'): continue
        base_id = f[:-4]
        kind, path_of = parse(base_id)
        if not kind: continue
        kind, path_of, rgb, a, boxes = cut_base(base_id, report)
        if os.environ.get('FEATURES_ONLY'):      # re-cut sprites + iris/nose masks only, keep the pattern masks
            print(base_id, 'features'); continue
        for g in files:
            if g.startswith('ov_') and g.endswith(f'__{parent(base_id)}.png'):
                pattern = g[3:].split('__')[0]
                cut_overlay(base_id, pattern, kind, path_of, rgb, a, boxes, report)
        r = report[base_id]
        print(base_id, r['pieces'], '/', r['expected'], {k: (v['iou'], v['coverage']) for k, v in r['overlays'].items()})
        json.dump(report, open(REPORT, 'w'), indent=1)

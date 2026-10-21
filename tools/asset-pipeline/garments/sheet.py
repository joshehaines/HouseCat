"""Builds an edit sheet for one body: its six resting poses and the puppet standing in its three views, on grey,
with a mask of each body below the head (the puppet's: its torso part). `tint` darkens the cats so a pale garment
stands out from the fur when it is cut out.
python sheet.py <body> <dark|white|ginger> -> work/sheets/<body>_<tint>.png, _mask.png, .json (tile placements)
python sheet.py <body> <tint> rest <garment>: the curled-up and stretching poses for one garment (build_rest)"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, 'work')  # sheets, edits, layers and check-sheets (not in git)
POSES = ['sit_tqfront', 'sit_front', 'sit_side', 'loaf_tqfront', 'loaf_side', 'sit_back']
W, H, COLS, ROWS = 2048, 2048, 3, 3
VIEWS = ['side', 'tqfront', 'front']
RIG = json.load(open(f'{REPO}/assets/cat/rig.json'))
TINTS = {'dark': (0.25, 0.23, 0.25), 'white': (1.0, 1.0, 1.0), 'ginger': (1.0, 0.62, 0.32)}
TW, TH = W // COLS, H // ROWS
BG = (128, 132, 140)

def centroid(m):
    ys, xs = np.nonzero(m)
    return (xs.mean(), ys.mean()) if len(xs) > 8 else None

FIXES = f'{REPO}/tools/app-assets/features_fixes'

CLOSED = json.load(open(f'{REPO}/assets/outfits/poses.json'))['eyes']

def features(rel):
    """A features mask (R, G = the irises, B = the nose), the repaired one when there is one. Curled up or stretching
    the eyes are shut, so not in the mask: they are drawn in where assets/outfits/poses.json measured them."""
    for root in (FIXES, f'{REPO}/assets/cat/custom/masks/features'):
        if os.path.exists(f'{root}/{rel}'):
            f = np.asarray(Image.open(f'{root}/{rel}').convert('RGB')).copy()
            key = os.path.basename(rel)[4:-4]
            if key in CLOSED:
                src = Image.open(f'{REPO}/assets/cat/custom/base/{rel}')
                sx, sy = f.shape[1] / src.width, f.shape[0] / src.height
                yy, xx = np.mgrid[0:f.shape[0], 0:f.shape[1]]
                for i, (x, y) in enumerate(CLOSED[key]):
                    f[..., i][np.hypot(xx - x * sx, yy - y * sy) < 6 * max(sx, sy)] = 255
            return f
    return None

def face_points(feats):
    eyes = sorted(c for c in (centroid(feats[..., 0] > 127), centroid(feats[..., 1] > 127)) if c)
    return eyes, centroid(feats[..., 2] > 127)

def scale_ref(eyes, nose):
    """A length that scales with the head: the eye span, or eye to nose in a profile."""
    if len(eyes) == 2:
        return np.hypot(eyes[1][0] - eyes[0][0], eyes[1][1] - eyes[0][1]), np.mean(eyes, 0)
    return (np.hypot(eyes[0][0] - nose[0], eyes[0][1] - nose[1]) if nose else None), np.array(eyes[0])

PART_VIEW = {'sit_tqfront': 'tqfront', 'loaf_tqfront': 'tqfront', 'sit_front': 'front', 'sit_side': 'side', 'loaf_side': 'side',
             'sleep_curl': 'tqfront', 'stretch_side': 'side'}

def head_template(body, view):
    """The puppet's head in a view: its opaque shape, and the scale length and anchor of its face."""
    img = Image.open(f'{REPO}/assets/cat/custom/base/parts/cat_{body}_{view}_head.png').convert('RGBA')
    shape = np.asarray(img)[..., 3] > 100
    if view == 'tqback':
        return shape, None, None
    eyes, nose = face_points(features(f'parts/cat_{body}_{view}_head.png'))
    ref, anchor = scale_ref(eyes, nose)
    return shape, ref, anchor

def stamp(shape, scale, at_src, at_dst, size):
    """`shape` scaled by `scale` and moved so `at_src` lands on `at_dst`, in a canvas of `size` (h, w)."""
    h, w = shape.shape
    small = np.asarray(Image.fromarray(shape.astype(np.uint8) * 255).resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.BILINEAR)) > 127
    out = np.zeros(size, bool)
    ox, oy = int(round(at_dst[0] - at_src[0] * scale)), int(round(at_dst[1] - at_src[1] * scale))
    sh, sw = small.shape
    y0, x0 = max(0, oy), max(0, ox)
    y1, x1 = min(size[0], oy + sh), min(size[1], ox + sw)
    if y1 > y0 and x1 > x0:
        out[y0:y1, x0:x1] = small[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    return out

def inner_ears(rgb, opaque, below, centre, reach):
    """The pink inside of the ears above the eyes and near the face (the white base's ears are pink inside; the
    warm rim light along the back is orange, its blue well under its green)."""
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    pink = (r > g + 20) & (b >= g - 8) & (sat > 0.15) & (mx > 110) & opaque
    yy, xx = np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]]
    pink &= (yy < below) & (np.hypot(xx - centre[0], yy - centre[1]) < reach)
    lab, n = ndimage.label(pink)
    if not n:
        return pink
    sizes = ndimage.sum(pink, lab, range(1, n + 1))
    return np.isin(lab, [i + 1 for i, a in enumerate(sizes) if a >= 0.2 * sizes.max() and a > 60])

def hull(points, size):
    """The filled convex hull of some points, as a mask."""
    from scipy.spatial import ConvexHull, Delaunay
    pts = np.array(points, float)
    if len(pts) < 3:
        return np.zeros(size, bool)
    tri = Delaunay(pts[ConvexHull(pts).vertices])
    yy, xx = np.mgrid[0:size[0], 0:size[1]]
    return (tri.find_simplex(np.stack([xx.ravel(), yy.ravel()], -1)) >= 0).reshape(size)

def head_region(body, src, feats, pose):
    """The pose's head, from three cues together: the puppet's own head for that view, scaled by the face and set on
    the pose's face; an oval round the eyes and nose; and the hull of the face and the pink inner ears. From behind:
    the back of the head as big as the front pose's, on top of the silhouette, and everything above the neck."""
    rgb = np.asarray(src)[..., :3].astype(np.float32)
    alpha = np.asarray(src)[..., 3] / 255.0
    h, w = alpha.shape
    opaque = alpha > 0.5
    yy, xx = np.mgrid[0:h, 0:w]
    if pose == 'sit_back':
        front, fref, _ = head_template(body, 'front')
        eyes, nose = face_points(features(f'poses/cat_{body}_sit_front.png'))
        pref, _ = scale_ref(eyes, nose)
        shape, _, _ = head_template(body, 'tqback')
        ys, xs = np.nonzero(opaque)
        top = ys.min()
        cx = xs[ys < top + 0.12 * h].mean()
        sys_, sxs = np.nonzero(shape)
        region = stamp(shape, pref / fref, (sxs.mean(), sys_.min()), (cx, top), (h, w))
        rows = opaque.sum(1).astype(float)
        lo, hi = top + int(0.12 * h), top + int(0.45 * h)
        neck = lo + int(np.argmin(rows[lo:hi]))
        # No taller than the head is on the front pose (top of the ears to the chin, a little over an eye span
        # under the eyes); a ruff painted on the back of the head part would otherwise take the shoulders.
        fsrc = Image.open(f'{REPO}/assets/cat/custom/base/poses/cat_{body}_sit_front.png').convert('RGBA')
        fa = np.asarray(fsrc)[..., 3] > 127
        ftop = np.nonzero(fa.any(1))[0][0]
        eye_y = np.mean([e[1] for e in eyes])
        head_h = (eye_y + 1.25 * pref - ftop) * (h / fa.shape[0])
        region &= yy < top + head_h
        # Only a real neck (a fluffy cat from behind narrows nowhere): clearly narrower than the body under it.
        below = rows[neck + int(0.1 * h):neck + int(0.3 * h)]
        if len(below) and rows[neck] < 0.8 * np.median(below):
            region |= opaque & (yy < neck)
        return ndimage.binary_dilation(region, iterations=max(2, int(0.02 * h)))
    if pose == 'sleep_curl':
        return curled_head(src, feats, rgb, opaque, yy, xx, h, w)
    shape, tref, tanchor = head_template(body, PART_VIEW[pose])
    eyes, nose = face_points(feats)
    if len(eyes) == 1 and (nose is None or nose[1] < eyes[0][1] - 5 or abs(nose[0] - eyes[0][0]) > 0.4 * w):
        # A profile whose nose was not found where a nose can be: its size from the three-quarter pose instead.
        teyes, tnose = face_points(features(f'poses/cat_{body}_{pose.replace("side", "tqfront")}.png'))
        tq_span, _ = scale_ref(teyes, tnose)
        _, tq_ref, _ = head_template(body, 'tqfront')
        pref, panchor = tq_span / tq_ref * tref, np.array(eyes[0])
        nose = None
    else:
        pref, panchor = scale_ref(eyes, nose)
    scale = pref / tref
    region = stamp(shape, scale, tanchor, panchor, (h, w))
    # An oval round the eyes (and nose), as the head is at least that big.
    if len(eyes) == 2:
        span = pref
        cx, cy = panchor[0], panchor[1] + 0.25 * span
        rx, ry = 1.35 * span, 1.05 * span
    else:
        d = pref
        ex, ey = eyes[0]
        back = 1 if (nose is None or ex > nose[0]) else -1
        if nose is None:
            back = 1 if ex < w / 2 else -1
        cx, cy = ex + back * 1.1 * d, ey + 0.55 * d
        rx, ry = 2.6 * d, 2.1 * d
    region |= ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 < 1
    # The face and the ears: the hull of the eyes, nose and pink inner ears.
    pts = [tuple(e) for e in eyes] + ([tuple(nose)] if nose else [])
    ears = inner_ears(rgb, opaque, max(e[1] for e in eyes), panchor, 2.4 * pref if len(eyes) == 2 else 4.5 * pref)
    eys, exs = np.nonzero(ears)
    pts += list(zip(exs[::7], eys[::7]))
    face = hull(pts, (h, w))
    region |= ndimage.binary_dilation(face, iterations=max(3, int(0.3 * (pref if len(eyes) == 2 else 2 * pref))))
    return ndimage.binary_dilation(region, iterations=max(2, int(0.02 * h))) & ndimage.binary_dilation(opaque, iterations=20)

def curled_head(src, feats, rgb, opaque, yy, xx, h, w):
    """Curled up the head lies tilted inside the round body: an oval turned with the eye line round the eyes and
    nose, with the face and the pink inner ears (the standing head's shape, stamped upright, left straight edges)."""
    eyes, nose = face_points(feats)
    (ax, ay), (bx, by) = eyes[0], eyes[1]
    span = np.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / span, (by - ay) / span          # along the eye line
    dx, dy = -uy, ux                                      # down the face
    if dy < 0:
        dx, dy = -dx, -dy
    cx, cy = (ax + bx) / 2 + dx * 0.25 * span, (ay + by) / 2 + dy * 0.25 * span
    along = (xx - cx) * ux + (yy - cy) * uy
    down = (xx - cx) * dx + (yy - cy) * dy
    region = (along / (1.5 * span)) ** 2 + (down / (1.15 * span)) ** 2 < 1
    # The ears, each with a round border (a hull round them left straight edges in the garment behind the head).
    ears = inner_ears(rgb, opaque, max(e[1] for e in eyes), ((ax + bx) / 2, (ay + by) / 2), 2.6 * span)
    r = max(3, int(0.35 * span))
    disc = np.hypot(*np.mgrid[-r:r + 1, -r:r + 1]) <= r
    region |= ndimage.binary_dilation(ears, structure=disc)
    return ndimage.binary_dilation(region, iterations=max(2, int(0.02 * h))) & ndimage.binary_dilation(opaque, iterations=20)

def assemble(body, view):
    """The puppet's rest pose in a view, as the game puts it together: each part's pivot on its parent's joint.
    Returns the picture and each part's (left, top, image)."""
    spec = RIG['sets'][body][view]['parts']
    imgs = {n: Image.open(f'{REPO}/assets/cat/custom/base/parts/cat_{body}_{view}_{n}.png').convert('RGBA') for n in spec}
    pos = {}
    def place(n):
        if n in pos:
            return pos[n]
        p = spec[n]
        if p['parent'] is None:
            pos[n] = (0.0, 0.0)
        else:
            px, py = place(p['parent'])
            par = imgs[p['parent']]
            jx, jy = px + p['at'][0] * par.width, py + p['at'][1] * par.height
            pos[n] = (jx - p['pivot'][0] * imgs[n].width, jy - p['pivot'][1] * imgs[n].height)
        return pos[n]
    for n in spec:
        place(n)
    x0 = min(pos[n][0] for n in spec); y0 = min(pos[n][1] for n in spec)
    x1 = max(pos[n][0] + imgs[n].width for n in spec); y1 = max(pos[n][1] + imgs[n].height for n in spec)
    canvas = Image.new('RGBA', (int(np.ceil(x1 - x0)), int(np.ceil(y1 - y0))), (0, 0, 0, 0))
    placed = {}
    for n in sorted(spec, key=lambda n: spec[n]['z']):
        x, y = int(round(pos[n][0] - x0)), int(round(pos[n][1] - y0))
        canvas.alpha_composite(imgs[n], (x, y))
        placed[n] = (x, y, imgs[n])
    return canvas, placed

def tinted(img, tint):
    a = np.asarray(img).astype(np.float32)
    a[..., :3] *= np.array(TINTS[tint])
    return Image.fromarray(a.astype(np.uint8))

def build(body, tint):
    sheet = Image.new('RGB', (W, H), BG)
    mask = np.zeros((H, W), np.uint8)   # 255 = repaint
    tiles = []
    items = [('pose', p) for p in POSES] + [('puppet', v) for v in VIEWS]
    for i, (kind, name) in enumerate(items):
        if kind == 'pose':
            src = Image.open(f'{REPO}/assets/cat/custom/base/poses/cat_{body}_{name}.png').convert('RGBA')
            feats = features(f'poses/cat_{body}_{name}.png')
            alpha = np.asarray(src)[..., 3] / 255.0
            head = head_region(body, src, feats, name)
            # Without the whiskers' thin strokes.
            body_m = ndimage.binary_opening((alpha > 0.5) & ~head, iterations=4)
            # Only the body itself (ear tips past the head's outline are small pieces).
            lab, n = ndimage.label(body_m)
            if n:
                sizes = ndimage.sum(body_m, lab, range(1, n + 1))
                body_m = np.isin(lab, [i + 1 for i, a in enumerate(sizes) if a >= 0.15 * sizes.max()])
            body_m = ndimage.binary_dilation(body_m, iterations=14) & ~ndimage.binary_erosion(head, iterations=2)
            extra = {}
        else:
            src, placed = assemble(body, name)
            alpha = np.zeros((src.height, src.width), bool)
            def part_mask(n):
                x, y, im = placed[n]
                m = np.zeros_like(alpha)
                a = np.asarray(im)[..., 3] > 127
                m[y:y + a.shape[0], x:x + a.shape[1]] |= a
                return m
            torso = part_mask('torso')
            above = part_mask('head')
            for ear in ('ear_near', 'ear_far'):   # some breeds have their ears painted on the head
                if ear in placed:
                    above |= part_mask(ear)
            body_m = ndimage.binary_dilation(torso & ~above, iterations=14) & ~above
            tx, ty, tim = placed['torso']
            extra = {'torso': [tx, ty, tim.width, tim.height]}
        pad = 40
        s = min((TW - 2 * pad) / src.width, (TH - 2 * pad) / src.height)
        tw, th = int(round(src.width * s)), int(round(src.height * s))
        col, row = i % COLS, i // COLS
        ox, oy = col * TW + (TW - tw) // 2, row * TH + (TH - th) // 2
        small = tinted(src, tint).resize((tw, th), Image.LANCZOS)
        sheet.paste(small, (ox, oy), small)
        m = Image.fromarray((body_m * 255).astype(np.uint8)).resize((tw, th), Image.BILINEAR)
        region = mask[oy:oy + th, ox:ox + tw]
        np.maximum(region, (np.asarray(m) > 127).astype(np.uint8) * 255, out=region)
        tiles.append({'kind': kind, 'name': name, 'x': ox, 'y': oy, 'w': tw, 'h': th, 'scale': s, 'src': [src.width, src.height], **extra})
    os.makedirs(f'{WORK}/sheets', exist_ok=True)
    stem = f'{WORK}/sheets/{body}_{tint}'
    sheet.save(f'{stem}.png')
    Image.fromarray(mask).save(f'{stem}_mask.png')
    json.dump({'body': body, 'tint': tint, 'size': [W, H], 'tiles': tiles}, open(f'{stem}.json', 'w'), indent=1)
    a = np.asarray(sheet).astype(float)
    a[mask > 0] = a[mask > 0] * 0.5 + np.array([255, 40, 40]) * 0.5
    Image.fromarray(a.astype(np.uint8)).resize((W // 2, H // 2)).save(f'{stem}_preview.png')

REST = ['sleep_curl', 'stretch_side']
REFS = ['sit_tqfront', 'loaf_side']

def build_rest(body, tint, garment):
    """The curled-up and stretching poses to dress (masked like the others), on a sheet of four: under them the same
    cat sitting and lying in the garment already painted for it (not masked), so the new ones match it.
    -> work/sheets/<body>_<tint>_rest_<garment>.png, <body>_rest_mask.png, <body>_<tint>_rest_<garment>.json"""
    sheet = Image.new('RGB', (W, H), BG)
    mask = np.zeros((H, W), np.uint8)
    tiles = []
    tw_, th_ = W // 2, H // 2
    for i, (kind, name) in enumerate([('pose', p) for p in REST] + [('ref', p) for p in REFS]):
        src = Image.open(f'{REPO}/assets/cat/custom/base/poses/cat_{body}_{name}.png').convert('RGBA')
        pad = 40
        s = min((tw_ - 2 * pad) / src.width, (th_ - 2 * pad) / src.height)
        tw, th = int(round(src.width * s)), int(round(src.height * s))
        ox, oy = (i % 2) * tw_ + (tw_ - tw) // 2, (i // 2) * th_ + (th_ - th) // 2
        small = tinted(src, tint)
        if kind == 'ref':
            small.alpha_composite(Image.open(f'{REPO}/assets/outfits/body/outfit_{garment}_{body}_{name}.png').convert('RGBA'))
        small = small.resize((tw, th), Image.LANCZOS)
        sheet.paste(small, (ox, oy), small)
        if kind == 'pose':
            feats = features(f'poses/cat_{body}_{name}.png')
            alpha = np.asarray(src)[..., 3] / 255.0
            head = head_region(body, src, feats, name)
            body_m = ndimage.binary_opening((alpha > 0.5) & ~head, iterations=4)
            lab, n = ndimage.label(body_m)
            if n:
                sizes = ndimage.sum(body_m, lab, range(1, n + 1))
                body_m = np.isin(lab, [i + 1 for i, a in enumerate(sizes) if a >= 0.15 * sizes.max()])
            body_m = ndimage.binary_dilation(body_m, iterations=14) & ~ndimage.binary_erosion(head, iterations=2)
            m = Image.fromarray((body_m * 255).astype(np.uint8)).resize((tw, th), Image.BILINEAR)
            region = mask[oy:oy + th, ox:ox + tw]
            np.maximum(region, (np.asarray(m) > 127).astype(np.uint8) * 255, out=region)
        tiles.append({'kind': kind, 'name': name, 'x': ox, 'y': oy, 'w': tw, 'h': th, 'scale': s, 'src': [src.width, src.height]})
    os.makedirs(f'{WORK}/sheets', exist_ok=True)
    stem = f'{WORK}/sheets/{body}_{tint}_rest_{garment}'
    sheet.save(f'{stem}.png')
    Image.fromarray(mask).save(f'{WORK}/sheets/{body}_rest_mask.png')
    json.dump({'body': body, 'tint': tint, 'size': [W, H], 'tiles': tiles}, open(f'{stem}.json', 'w'), indent=1)
    a = np.asarray(sheet).astype(float)
    a[mask > 0] = a[mask > 0] * 0.5 + np.array([255, 40, 40]) * 0.5
    Image.fromarray(a.astype(np.uint8)).resize((W // 2, H // 2)).save(f'{stem}_preview.png')

if __name__ == '__main__':
    # python sheet.py <body> <tint> [rest <garment>]: the curled-up and stretching sheet for one garment
    if len(sys.argv) > 4 and sys.argv[3] == 'rest':
        build_rest(sys.argv[1], sys.argv[2], sys.argv[4])
    else:
        build(sys.argv[1], sys.argv[2])

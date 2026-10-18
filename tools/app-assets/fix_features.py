#!/usr/bin/env python3
"""Repairs features masks the automatic cut got wrong (tools/asset-pipeline/custcut.py took the warm rim light on
the fur's edge for an iris, and a pink chin edge for the nose). FIXES lists each sprite and the channels to find
again; the other channels are kept. An iris is looked for near the mirror of the other eye about the nose (or the
face's middle): the warm, saturated pixels inside a disc there, the blob with a dark pupil, its holes filled; the
nose leather is the pink blob just below and between the eyes. The masters in assets/ are not touched: the
repaired masks go to tools/app-assets/features_fixes/<rel>, which build_cat_art.py prefers.

Run: python3 tools/app-assets/fix_features.py  (needs numpy, Pillow, SciPy), then
     python3 tools/app-assets/build_cat_art.py --features <rel> ...
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CUSTOM = os.path.join(ROOT, 'assets', 'cat', 'custom')
OUT = os.path.join(HERE, 'features_fixes')

# Which channels to find again (R = the iris on the image's left, G = the other, B = the nose leather).
FIXES = {
    'parts/cat_short_chunky_front_head.png': 'GB',
    'parts/cat_short_slim_tqfront_head.png': 'R',
}


def colour(rgb):
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1e-3)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    return mx, sat, hue


def blob(channel):
    """Centre (y, x) and half-size (h, w) of a channel's pixels."""
    ys, xs = np.nonzero(channel > 0.5)
    return np.array([ys.mean(), xs.mean()]), np.array([(ys.max() - ys.min()) / 2, (xs.max() - xs.min()) / 2])


def disc(shape, centre, radius):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    return np.hypot((yy - centre[0]) / radius[0], (xx - centre[1]) / radius[1]) < 1


def find_iris(rgb, a, centre, radius):
    mx, sat, hue = colour(rgb)
    dark = mx < 70
    warm = (hue > 22) & (hue < 70) & (sat > 0.22) & (mx > 90) & (a > 0.5) & disc(a.shape, centre, radius)
    warm = ndimage.binary_closing(warm, iterations=2)
    lab, n = ndimage.label(warm)
    if not n:
        raise SystemExit('no iris found')
    best, score = None, -1
    for i, sl in enumerate(ndimage.find_objects(lab)):
        part = lab[sl] == i + 1
        size = part.sum()
        near = ndimage.binary_dilation(ndimage.binary_fill_holes(part), iterations=3)
        if size < 40 or (dark[sl] & near).sum() < 0.12 * size:
            continue
        if size > score:
            best, score = i + 1, size
    if best is None:
        raise SystemExit('no iris with a pupil found')
    eye = ndimage.binary_fill_holes(lab == best)
    # the iris only: not the dark pupil or outline, not the white catchlight (as custcut.py does)
    w = np.clip((mx - 70) / 50, 0, 1) * np.clip((sat - 0.08) / 0.12, 0, 1)
    return ndimage.gaussian_filter(eye.astype(np.float32), 0.6) * w


def find_nose(rgb, a, centre, radius):
    mx, sat, hue = colour(rgb)
    pink = ((hue > 330) | (hue < 18)) & (sat > 0.16) & (mx > 120) & (a > 0.5) & disc(a.shape, centre, radius)
    # the mouth line under it is pinkish too: open the shape so thin strokes go, keep the biggest blob, then let it
    # grow back to its own edge (a few pixels, never along a line)
    core = ndimage.binary_opening(pink, iterations=3)
    lab, n = ndimage.label(core)
    if not n:
        raise SystemExit('no nose found')
    sizes = ndimage.sum(core, lab, range(1, n + 1))
    nose = ndimage.binary_dilation(lab == int(np.argmax(sizes)) + 1, iterations=3, mask=pink)
    return ndimage.gaussian_filter(nose.astype(np.float32), 0.7)


def main():
    for rel, channels in FIXES.items():
        base = np.asarray(Image.open(os.path.join(CUSTOM, 'base', rel)).convert('RGBA')).astype(np.float32)
        rgb, a = base[..., :3], base[..., 3] / 255
        mask = np.asarray(Image.open(os.path.join(CUSTOM, 'masks', 'features', rel)).convert('RGB')).astype(np.float32) / 255
        fixed = mask.copy()
        for c in channels:
            fixed[..., 'RGB'.index(c)] = 0
        keep = {c: blob(fixed[..., 'RGB'.index(c)]) for c in 'RGB' if (fixed[..., 'RGB'.index(c)] > 0.5).any()}
        ys, xs = np.nonzero(a > 0.5)
        middle = keep['B'][0][1] if 'B' in keep else (xs.min() + xs.max()) / 2
        for c in channels:
            if c in 'RG':
                other = keep['G' if c == 'R' else 'R']
                centre = np.array([other[0][0], 2 * middle - other[0][1]])
                fixed[..., 'RGB'.index(c)] = find_iris(rgb, a, centre, other[1] * 1.9 + 4)
        if 'B' in channels:
            (ly, lx), (lh, lw) = blob(fixed[..., 0])
            (ry, rx), _ = blob(fixed[..., 1])
            centre = np.array([max(ly, ry) + lh * 1.6, (lx + rx) / 2])
            fixed[..., 2] = find_nose(rgb, a, centre, np.array([lh * 1.3, lw * 1.3]))
        for c in 'RGB':
            if (fixed[..., 'RGB'.index(c)] > 0.5).any():
                (cy, cx), (h, w) = blob(fixed[..., 'RGB'.index(c)])
                print(f'{rel} {c}: centre ({cx:.0f}, {cy:.0f}) size {2 * w:.0f}x{2 * h:.0f}')
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.fromarray((np.clip(fixed, 0, 1) * 255).astype(np.uint8)).save(dst, optimize=True)


if __name__ == '__main__':
    main()

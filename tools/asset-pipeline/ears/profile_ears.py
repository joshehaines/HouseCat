"""Profile ears for the side view (Josh, 19 Oct: the cat's ears looked strange going sideways; the side view used the
front view's cupped ears, both pink insides facing out). Each body's and each ear shape's pair painted with
gpt_image_2_5 on flat green, near ear left and far ear right, from its side head, its sitting profile and the first
pair as references; keyed here into new white-base masters beside the old ones (nothing is edited):

  assets/cat/custom/base/parts/cat_<body>_side_ear_{near,far}_profile.png   (a body's own ears, for the bodies whose
                                                                           side head is a true profile with no ears)
  assets/cat/custom/base/ears/ear_<shape>_side_{near,far}_profile.png       (the swap ears)

and their pattern masks, each the old cupped ear's mean for that pattern over the new ear (an ear's back is near enough
one colour; a colourpoint's ears are all point), at assets/cat/custom/masks/<pattern>/<same path>.

    uv run --with numpy --with pillow --with scipy python tools/asset-pipeline/ears/profile_ears.py <raw.png> <rel-stem>

<rel-stem> is "parts/cat_short_slim_side_ear" or "ears/ear_rounded_side". Then tools/app-assets/build_profile_ears.py.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
CUSTOM = os.path.join(ROOT, 'assets', 'cat', 'custom')
# The masters' heights: a body's near ear a little taller than its old cupped one, the far ear as tall. The swap
# ears' old masters were painted larger than a body's own; theirs are sized against the short-haired slim body's
# profile ear instead: rounded and folded ears are smaller, tufted and oriental ones taller.
NEAR_SCALE, FAR_SCALE = 1.15, 1.0
SWAP_HEIGHT = {'rounded': 0.82, 'folded': 0.62, 'tufted': 1.2, 'oriental': 1.25}


def key(path):
    """Alpha from the green: the further from the key colour, the more solid; green spill on the rims greyed."""
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    keycol = np.median(border, axis=0)
    dist = np.sqrt(((a - keycol) ** 2).sum(-1))
    alpha = np.clip((dist - 50) / 90, 0, 1)
    lab, n = ndimage.label(alpha > 0.5)
    sizes = ndimage.sum(np.ones_like(lab), lab, index=range(1, n + 1))
    keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > a.shape[0] * a.shape[1] * 0.002])
    alpha = np.where(ndimage.binary_dilation(keep, iterations=3), alpha, 0)
    alpha = ndimage.gaussian_filter(alpha, 0.7)
    safe = np.maximum(alpha, 0.05)[..., None]
    fg = np.where(alpha[..., None] < 0.999, np.clip((a - (1 - safe) * keycol) / safe, 0, 255), a)
    spill = (g > r + 12) & (g > b + 12)
    grey = fg.mean(-1, keepdims=True)
    fg = np.where(spill[..., None], grey, fg)
    return np.dstack([fg, alpha * 255]).astype(np.uint8)


def ears(rgba):
    """The two ears, left (near) and right (far), each cut to its outline."""
    alpha = rgba[..., 3] > 128
    cols = np.nonzero(alpha.any(0))[0]
    gaps = np.nonzero(np.diff(cols) > 8)[0]
    split = (cols[gaps[0]] + cols[gaps[0] + 1]) // 2 if len(gaps) else rgba.shape[1] // 2
    out = []
    for part in (rgba[:, :split], rgba[:, split:]):
        a = part[..., 3] > 128
        ys, xs = np.nonzero(a)
        crop = part[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        # Cut tight; the puppet finds the base's middle (its pivot) from the outline.
        crop = np.pad(crop, ((4, 0), (4, 4), (0, 0)))
        out.append(Image.fromarray(crop, 'RGBA'))
    return out


def main(raw, stem):
    near, far = ears(key(raw))
    old = Image.open(os.path.join(CUSTOM, 'base', f'{stem}_near.png'))
    reference = old.height
    shape = next((k for k in SWAP_HEIGHT if stem == f'ears/ear_{k}_side'), None)
    if shape:
        body = Image.open(os.path.join(CUSTOM, 'base', 'parts', 'cat_short_slim_side_ear_near.png'))
        reference = body.height * SWAP_HEIGHT[shape]
    for img, side, scale in ((near, 'near', NEAR_SCALE), (far, 'far', FAR_SCALE)):
        h = round(reference * scale)
        w = round(img.width * h / img.height)
        img = img.convert('RGBa').resize((w, h), Image.LANCZOS).convert('RGBA')
        rel = f'{stem}_{side}_profile.png'
        img.save(os.path.join(CUSTOM, 'base', rel), optimize=True)
        alpha = np.asarray(img)[..., 3].astype(np.float32) / 255
        for pattern in sorted(os.listdir(os.path.join(CUSTOM, 'masks'))):
            src = os.path.join(CUSTOM, 'masks', pattern, f'{stem}_{side}.png')
            if pattern in ('features', 'whiskers') or not os.path.exists(src):
                continue
            m = np.asarray(Image.open(src).convert('L')).astype(np.float32) / 255
            base_alpha = np.asarray(Image.open(os.path.join(CUSTOM, 'base', f'{stem}_{side}.png')).convert('RGBA'))[..., 3] > 128
            value = 1.0 if pattern == 'colourpoint' else float(m[base_alpha].mean()) if base_alpha.any() else 0.0
            dst = os.path.join(CUSTOM, 'masks', pattern, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            Image.fromarray((np.clip(alpha * value, 0, 1) * 255).astype(np.uint8), 'L').save(dst, optimize=True)
        print(rel, img.size)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

"""Single legs for the long-haired slim body's side view (Josh, 19 Oct: the legs looked completely off walking; each
of this body's side leg paintings held a pair of legs, so the jointed puppet walked on eight). One front leg and one
hind leg painted with gpt_image_2_5 on flat green, from the old pair (fur and light) and the short-haired slim body's
leg (shape) as references; keyed here into new white-base masters beside the old ones (nothing is edited), each the
old painting's size with its leg's top where the rig joins it to the body and its paw on the old floor line:

  assets/cat/custom/base/parts/cat_long_slim_side_leg_{front,back}_{near,far}_single.png

and their pattern masks, carried over from the old painting row by row: each row of the new leg takes the mask
across the old leg nearest it at the same height (a leg's stripes, spots, mitts and points run across it, so they
land where they were).

    uv run --with numpy --with pillow --with scipy python tools/asset-pipeline/legs/single_legs.py <front.png> <hind.png>

Then tools/app-assets/build_single_legs.py.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ears'))
from profile_ears import CUSTOM, ROOT, key  # noqa: E402

BODY = 'long_slim'


def leg(rgba):
    """The leg cut to its outline."""
    a = rgba[..., 3] > 128
    ys, xs = np.nonzero(a)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def runs(row):
    """The opaque runs across one row of an alpha mask, as (left, right)."""
    cols = np.nonzero(row)[0]
    if not len(cols):
        return []
    breaks = np.nonzero(np.diff(cols) > 3)[0]
    starts = np.concatenate([[cols[0]], cols[breaks + 1]])
    ends = np.concatenate([cols[breaks], [cols[-1]]])
    return list(zip(starts, ends))


def fit(new, old, pivot_x):
    """The new leg on the old painting's canvas: as tall as the old pair, its top's middle where the rig joins the
    leg to the body, its paw on the old floor line."""
    oa = old[..., 3] > 128
    ys = np.nonzero(oa.any(1))[0]
    top, bottom = ys[0], ys[-1]
    h = bottom - top + 1
    w = round(new.shape[1] * h / new.shape[0])
    img = Image.fromarray(new, 'RGBA').convert('RGBa').resize((w, h), Image.LANCZOS).convert('RGBA')
    arr = np.asarray(img)
    a = arr[..., 3] > 128
    head = [np.nonzero(a[r])[0] for r in range(max(1, h // 20))]
    centre = np.mean([(c[0] + c[-1]) / 2 for c in head if len(c)])
    left = int(round(pivot_x * old.shape[1] - centre))
    left = max(0, min(old.shape[1] - w, left))
    out = np.zeros_like(old)
    out[top:top + h, left:left + w] = arr
    return out


def carry(mask, old_alpha, new_alpha):
    """The old mask across the new leg, row by row (see the module's note)."""
    out = np.zeros(new_alpha.shape, np.float32)
    ny = np.nonzero(new_alpha.any(1))[0]
    oy = np.nonzero(old_alpha.any(1))[0]
    last = None
    for r in ny:
        t = (r - ny[0]) / max(1, ny[-1] - ny[0])
        ro = int(round(oy[0] + t * (oy[-1] - oy[0])))
        new_runs, old_runs = runs(new_alpha[r]), runs(old_alpha[ro])
        if not old_runs or not new_runs:
            continue
        # The leg's widest run in this row; where the old pair splits, the old leg nearest it, keeping to the same one
        # down the leg.
        nl, nr = max(new_runs, key=lambda s: s[1] - s[0])
        mid = (nl + nr) / 2
        ol, orr = min(old_runs, key=lambda s: abs((s[0] + s[1]) / 2 - mid) + (abs((s[0] + s[1]) / 2 - last) if last else 0))
        last = (ol + orr) / 2
        xs = np.arange(nl, nr + 1)
        s = (xs - nl) / max(1, nr - nl)
        xo = np.clip(np.round(ol + s * (orr - ol)).astype(int), 0, mask.shape[1] - 1)
        out[r, nl:nr + 1] = mask[ro, xo]
    # A little softening down the leg, so the rows meet without steps.
    return ndimage.gaussian_filter1d(out, 1.5, axis=0)


def main(front_raw, hind_raw):
    rig = json.load(open(os.path.join(ROOT, 'App', 'Art', 'cat', 'rig.json')))['sets'][BODY]['side']['parts']
    raws = {'front': leg(key(front_raw)), 'back': leg(key(hind_raw))}
    for end in ('front', 'back'):
        for side in ('near', 'far'):
            name = f'leg_{end}_{side}'
            stem = f'parts/cat_{BODY}_side_{name}'
            old = np.asarray(Image.open(os.path.join(CUSTOM, 'base', stem + '.png')).convert('RGBA'))
            new = fit(raws[end], old, rig[name]['pivot'][0])
            rel = stem + '_single.png'
            Image.fromarray(new, 'RGBA').save(os.path.join(CUSTOM, 'base', rel), optimize=True)
            old_alpha, new_alpha = old[..., 3] > 128, new[..., 3] > 128
            alpha = new[..., 3].astype(np.float32) / 255
            for pattern in sorted(os.listdir(os.path.join(CUSTOM, 'masks'))):
                src = os.path.join(CUSTOM, 'masks', pattern, stem + '.png')
                if pattern in ('features', 'whiskers') or not os.path.exists(src):
                    continue
                m = np.asarray(Image.open(src).convert('L')).astype(np.float32) / 255
                value = carry(m, old_alpha, new_alpha) * alpha
                dst = os.path.join(CUSTOM, 'masks', pattern, rel)
                Image.fromarray((np.clip(value, 0, 1) * 255).astype(np.uint8), 'L').save(dst, optimize=True)
            print(rel, new.shape[1], 'x', new.shape[0])


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

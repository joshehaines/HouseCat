"""A side head with no ears, for swapped ears (Josh, 20 Oct: "The ears on the cats need to be looked at, they are very
buggy and show two sets of ears"). The long-haired slim body's side head is painted with its own ear (the puppet takes
no ear parts over it), so a rounded, folded, tufted or oriental ear went on beside the painted one. Its ear was painted
out with an Ideogram 4.5 masked edit in Higgsfield (job 8a778f06-d1a7-4363-a769-65d09a916e89, from the master on flat
green scaled to 1000 px tall in a 1200 square, the mask a polygon round the ear and the far ear's tuft, prompt in
PROMPT), and this keys the edit back into a new master beside the old one (nothing is edited):

  assets/cat/custom/base/parts/cat_long_slim_side_head_noears.png

with the head's masks (patterns, white markings, features) at the same path, the repainted crown filled from the fur
round it ("new fur is plain coat", docs/ASSETS.md). Then:

    uv run --with numpy --with pillow --with scipy python tools/asset-pipeline/ears/earless_head.py <raw.png>
    uv run --with numpy --with pillow --with scipy python tools/app-assets/build_cat_art.py --only parts/cat_long_slim_side_head_noears.png
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
CUSTOM = os.path.join(ROOT, 'assets', 'cat', 'custom')
SOURCE = 'parts/cat_long_slim_side_head.png'
TARGET = 'parts/cat_long_slim_side_head_noears.png'
# Where the edit was allowed, in the master's pixels: the ear and the far ear's tuft above the crown.
EAR = [(165, 0), (315, 0), (315, 115), (290, 150), (262, 198), (225, 218), (188, 205), (168, 160), (160, 60)]
CANVAS, TALL = 1200, 1000
PROMPT = ("The same fluffy long-haired cat's head in profile facing left, unchanged, but with no ears at all: the top "
          "of the head is a smooth rounded dome of soft fluffy fur where the ear was, with the same fur texture and soft "
          "warm rim light as the rest of the head. Same soft painterly style with visible brushwork. Plain flat green "
          "background.")


def main(raw):
    head = Image.open(os.path.join(CUSTOM, 'base', SOURCE)).convert('RGBA')
    w, h = head.size
    k = TALL / h
    bw, bh = round(w * k), round(h * k)
    ox, oy = (CANVAS - bw) // 2, (CANVAS - bh) // 2
    edit = Image.open(raw).convert('RGB').crop((ox, oy, ox + bw, oy + bh)).resize((w, h), Image.LANCZOS)
    a = np.asarray(edit).astype(np.float32)
    # Key the green: the further from the key colour, the more solid; green spill on the rims greyed.
    border = np.concatenate([a[0], a[:, 0], a[:, -1]])
    keycol = np.median(border, axis=0)
    dist = np.sqrt(((a - keycol) ** 2).sum(-1))
    alpha = np.clip((dist - 50) / 90, 0, 1)
    safe = np.maximum(alpha, 0.05)[..., None]
    fg = np.where(alpha[..., None] < 0.999, np.clip((a - (1 - safe) * keycol) / safe, 0, 255), a)
    r, g, b = fg[..., 0], fg[..., 1], fg[..., 2]
    spill = (g > r + 8) & (g > b + 8)
    fg = np.where(spill[..., None], fg.mean(-1, keepdims=True), fg)
    # The edit only inside the ear's region, feathered into the old painting.
    region = Image.new('L', (w, h), 0)
    ImageDraw.Draw(region).polygon(EAR, fill=255)
    region = region.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(3))
    m = np.asarray(region).astype(np.float32)[..., None] / 255
    old = np.asarray(head).astype(np.float32)
    new = np.dstack([fg, alpha * 255])
    out = old * (1 - m) + new * m
    Image.fromarray(np.clip(np.round(out), 0, 255).astype(np.uint8)).save(os.path.join(CUSTOM, 'base', TARGET))
    # The masks: the head's, with the repainted region filled from the nearest fur outside it.
    inside = np.asarray(region) > 8
    _, (iy, ix) = ndimage.distance_transform_edt(inside, return_indices=True)
    for folder in sorted(os.listdir(os.path.join(CUSTOM, 'masks'))):
        src = os.path.join(CUSTOM, 'masks', folder, SOURCE)
        if not os.path.exists(src):
            continue
        img = Image.open(src)
        arr = np.asarray(img)
        if folder != 'features':
            arr = arr[iy, ix] if arr.ndim == 2 else arr[iy, ix, :]
        Image.fromarray(arr).save(os.path.join(CUSTOM, 'masks', folder, TARGET))
        print(folder)
    print(TARGET, (w, h))


if __name__ == '__main__':
    main(sys.argv[1])

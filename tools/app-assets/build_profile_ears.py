#!/usr/bin/env python3
"""Adds the side view's profile ears (tools/asset-pipeline/ears/profile_ears.py) to App/Art/cat/custom the way
build_cat_art.py builds every sprite (white base as JPEG plus alpha, the fur mask, the pattern masks at half size in
16 levels), merging them into index.json, without rebuilding the rest. build_cat_art.py also picks them up when
they are listed in its sprites().

    uv run --with numpy --with pillow --with scipy python tools/app-assets/build_profile_ears.py
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cat_art as cat  # noqa: E402


def profile_rels():
    base = os.path.join(cat.CUSTOM, 'base')
    found = glob.glob(os.path.join(base, 'parts', '*_side_ear_*_profile.png')) + \
        glob.glob(os.path.join(base, 'ears', '*_side_*_profile.png'))
    return sorted(os.path.relpath(f, base) for f in found)


def build(rel):
    base = Image.open(os.path.join(cat.CUSTOM, 'base', rel)).convert('RGBA')
    scale = cat.PART_SCALE
    size = (max(1, round(base.width * scale)), max(1, round(base.height * scale)))
    alpha = np.asarray(base)[..., 3]
    masks = []

    def save(name, img):
        dst = os.path.join(cat.OUT, 'masks', name, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        small = (max(1, round(size[0] * cat.MASK_SCALE)), max(1, round(size[1] * cat.MASK_SCALE)))
        cat.save_levels(cat.bled(img, alpha).resize(small, Image.BOX), dst)
        masks.append(name)

    save('fur', cat.grey(cat.fur_mask(base)))
    for m in cat.PATTERNS + cat.WHITES:
        mp = os.path.join(cat.CUSTOM, 'masks', m, rel)
        if os.path.exists(mp):
            img = Image.open(mp).convert('L')
            if img.getextrema()[1] > 0:
                save(m, img)
    small = np.asarray(cat.resized(base, scale))
    for folder, img, ext, kw in [('base', Image.fromarray(small[..., :3]), '.jpg', {'quality': 90}),
                                 ('alpha', Image.fromarray(small[..., 3]), '', {'optimize': True})]:
        dst = os.path.join(cat.OUT, folder, rel + ext)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        img.save(dst, **kw)
    return {'master': [base.width, base.height], 'size': list(size), 'scale': scale, 'masks': sorted(masks)}


def main():
    path = os.path.join(cat.OUT, 'index.json')
    index = json.load(open(path))
    for rel in profile_rels():
        index['files'][rel] = build(rel)
        print(rel, index['files'][rel]['masks'])
    with open(path, 'w') as f:
        json.dump(index, f, indent=1, sort_keys=True)
        f.write('\n')


if __name__ == '__main__':
    main()

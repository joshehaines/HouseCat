#!/usr/bin/env python3
"""Builds App/Art/cat/custom: the cat builder's white sprites at app size with their masks, for the coat recipe
in the app (HouseCatGame CoatRenderer; reference tools/asset-pipeline/tint.py), plus builder.json, the builder's
options and presets as ordered lists for HouseCatCore's CatBuilderData.

Per sprite, at the same relative path as under assets/cat/custom (sizes kept down: about 25 MB in all):
  base/<rel>.jpg + alpha/<rel> the white painting's colour (JPEG) and its alpha (PNG), the tail's root and the
                              torso's rump cleaned (caps.py)
  masks/fur/<rel>             tint.py's fur mask (1 = tint, 0 = keep the painting: pink inner ears, nose, pads;
                              the silhouette edge always fur), worked out at master size
  masks/<pattern|white>/<rel> pattern and white-marking masks; a mask that is 0 everywhere is left out
     (fur, pattern and white masks are half the sprite's size in 16 levels of 8-bit grey; the app scales them up)
  masks/features/<rel>        R, G = the irises, B = the nose leather, at the sprite's size
  masks/whiskers/<rel>        the painted whiskers (thin strokes around the muzzle), for the whisker slider
index.json gives each sprite's master size, its scale and the masks it has.

Run from the repo root after build_app_art.py (which leaves App/Art/cat/custom alone); needs Pillow, numpy, scipy:
  python3 tools/app-assets/build_cat_art.py
A features mask repaired by fix_features.py (tools/app-assets/features_fixes/<rel>) is used instead of the
master's. Only the features and whisker masks of some sprites, after a repair:
  python3 tools/app-assets/build_cat_art.py --features parts/cat_short_chunky_front_head.png ...
"""
import glob
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'asset-pipeline'))
import caps  # noqa: E402
from tint import _fur_mask  # noqa: E402

CUSTOM = os.path.join(ROOT, 'assets', 'cat', 'custom')
FIXED_FEATURES = os.path.join(ROOT, 'tools', 'app-assets', 'features_fixes')
OUT = os.path.join(ROOT, 'App', 'Art', 'cat', 'custom')
CB = json.load(open(os.path.join(CUSTOM, 'catbuilder.json')))
RIG = json.load(open(os.path.join(ROOT, 'assets', 'cat', 'rig.json')))

VIEWS = ['side', 'tqfront', 'front']
PARTS = ['head', 'ear_far', 'ear_near', 'torso', 'leg_front_far', 'leg_front_near', 'leg_back_far', 'leg_back_near', 'tail_up']
PATTERNS = [p for p in CB['patterns'] if p != 'none']
WHITES = [w for w in CB['white_markings'] if w != 'none']
PART_SCALE, POSE_SCALE = 0.35, 0.4
MASK_SCALE = 0.5   # of the sprite's own size: fur, pattern and white masks
LEVELS = 16


def sprites():
    """(rel, scale, body, view, part) for every sprite the app draws."""
    out = []
    for body in CB['bodies']:
        for view in VIEWS:
            for part in PARTS:
                if part in RIG['sets'][body][view]['parts']:
                    out.append((f'parts/cat_{body}_{view}_{part}.png', PART_SCALE, body, view, part))
    for name in sorted(os.listdir(os.path.join(CUSTOM, 'base', 'poses'))):
        out.append((f'poses/{name}', POSE_SCALE, None, None, None))
    for ears in CB['ears']:
        if ears == 'own':
            continue
        for view in VIEWS:
            for side in ('far', 'near'):
                out.append((f'ears/ear_{ears}_{view}_{side}.png', PART_SCALE, None, view, f'ear_{side}'))
    for view in VIEWS:
        out.append((f'tails/bobtail_{view}_up.png', PART_SCALE, None, view, 'tail_up'))
    # The side view's profile ears (tools/asset-pipeline/ears/profile_ears.py) and single legs
    # (tools/asset-pipeline/legs/single_legs.py).
    for folder, pattern in (('parts', '*_side_ear_*_profile.png'), ('ears', '*_side_*_profile.png'),
                            ('parts', '*_side_leg_*_single.png')):
        for path in sorted(glob.glob(os.path.join(CUSTOM, 'base', folder, pattern))):
            out.append((f'{folder}/{os.path.basename(path)}', PART_SCALE, None, 'side', None))
    return out


def resized(img, scale):
    size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
    if img.mode == 'RGBA':  # scale premultiplied, so transparent pixels' colours never bleed in
        return img.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')
    return img.resize(size, Image.BOX)


def fur_mask(base):
    """tint.py's fur mask before the irises are taken out: 1 = tint, 0 = keep the painting."""
    a = np.asarray(base).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3]
    fm = _fur_mask(rgb)
    inside = ndimage.binary_erosion(al > 128, iterations=7)
    return np.where(~inside & (al > 0), 1.0, fm)


def whisker_mask(base, features):
    """The painted whiskers: thin strokes outside the solid head, level with the nose."""
    if features is None or not features[..., 2].any():
        return None
    al = np.asarray(base)[..., 3]
    solid = ndimage.binary_opening(al > 40, iterations=4)
    thin = (al > 8) & ~ndimage.binary_dilation(solid, iterations=2)
    ys, _ = np.nonzero(features[..., 2] > 0.5)
    if len(ys) == 0:
        return None
    h = al.shape[0]
    band = np.zeros_like(thin)
    band[max(0, int(ys.mean() - 0.18 * h)):int(ys.mean() + 0.25 * h)] = True
    lab, n = ndimage.label(thin & band)
    if n == 0:
        return None
    sizes = ndimage.sum(np.ones_like(lab), lab, index=range(1, n + 1))
    keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 12])
    return keep if keep.any() else None


def grey(arr):
    return Image.fromarray(np.clip(np.round(arr * 255), 0, 255).astype(np.uint8))


def bled(img, alpha):
    """A mask with each transparent pixel given its nearest painted pixel's value, so that scaling it down and
    back up never pulls the cat's outline towards the empty value outside it."""
    a = np.asarray(img.convert('L'))
    _, (iy, ix) = ndimage.distance_transform_edt(alpha == 0, return_indices=True)
    return Image.fromarray(a[iy, ix])


def save_levels(img, dst):
    """A greyscale mask in 16 levels (half the size of 256 once compressed), kept as plain 8-bit grey so the
    app reads the bytes as they are, with no colour management."""
    a = np.asarray(img.convert('L')).astype(np.float32)
    step = 255 / (LEVELS - 1)
    Image.fromarray(np.round(np.round(a / step) * step).astype(np.uint8)).save(dst, optimize=True)


def builder_json():
    def options(d):
        return [{'id': k, 'label': v['label']} for k, v in d.items()]

    def swatches(d):
        return [{'id': k, 'label': v['label'], 'rgb': v['rgb']} for k, v in d.items()]

    bodies = [{'id': k, 'label': v['label'], 'fur': v['fur'], 'build': v['build'], 'scale': v['scale'],
               'earSwaps': v['ear_swaps'], 'tailSwaps': v['tail_swaps'], 'expressionHeads': v['expression_heads'],
               'weightPair': v['weight_pair']} for k, v in CB['bodies'].items()]
    presets = []
    for p in CB['presets']:
        look = {f: p[f] for f in CB['look_fields'] if f in p and p[f] is not None}
        presets.append({'id': p['id'], 'name': p['name'], 'look': look})
    return {'note': 'Generated by tools/app-assets/build_cat_art.py from assets/cat/custom/catbuilder.json: the same '
                    'options and presets, as lists in builder order.',
            'bodies': bodies, 'ears': options(CB['ears']), 'tails': options(CB['tails']),
            'patterns': options(CB['patterns']), 'whites': options(CB['white_markings']),
            'coats': swatches(CB['palettes']['coat']), 'eyes': swatches(CB['palettes']['eyes']),
            'noses': swatches(CB['palettes']['nose']), 'presets': presets,
            'nameSuggestions': CB['naming']['suggestions']}


def main(features_only=None):
    if features_only is None:
        if os.path.isdir(OUT):
            shutil.rmtree(OUT)
        os.makedirs(OUT)
    index = {}
    for rel, scale, body, view, part in sprites():
        if features_only is not None and rel not in features_only:
            continue
        src = os.path.join(CUSTOM, 'base', rel)
        base = Image.open(src).convert('RGBA')
        if body and view:
            base = caps.clean(base, RIG['sets'][body][view], part)
        elif rel.startswith('tails/'):
            base = caps.erase(base, [tuple(RIG['sets']['short_slim'][view]['parts']['tail_up']['pivot'])])
        masks = {}
        size = (max(1, round(base.width * scale)), max(1, round(base.height * scale)))
        alpha = np.asarray(base)[..., 3]

        def save(name, img, half=True):
            dst = os.path.join(OUT, 'masks', name, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if half:
                small = (max(1, round(size[0] * MASK_SCALE)), max(1, round(size[1] * MASK_SCALE)))
                save_levels(bled(img, alpha).resize(small, Image.BOX), dst)
            elif img.mode == '1':
                img.resize(size, Image.NEAREST).save(dst, optimize=True)
            else:
                img.resize(size, Image.BOX).save(dst, optimize=True)
            masks[name] = True

        if features_only is None:
            save('fur', grey(fur_mask(base)))
        fp = os.path.join(FIXED_FEATURES, rel)
        if not os.path.exists(fp):
            fp = os.path.join(CUSTOM, 'masks', 'features', rel)
        features = None
        if os.path.exists(fp):
            features = np.asarray(Image.open(fp).convert('RGB')).astype(np.float32) / 255
            if features.any():
                save('features', Image.open(fp).convert('RGB'), half=False)
        whiskers = whisker_mask(base, features)
        if whiskers is not None:
            # thin strokes: kept wherever any of the master's pixels under an app pixel was whisker
            w = Image.fromarray((whiskers * 255).astype(np.uint8)).resize(size, Image.BOX)
            save('whiskers', w.point(lambda v: 255 if v > 0 else 0).convert('1'), half=False)
        if features_only is not None:
            print(f'{rel}: features and whiskers')
            continue
        for m in PATTERNS + WHITES:
            mp = os.path.join(CUSTOM, 'masks', m, rel)
            if os.path.exists(mp):
                img = Image.open(mp).convert('L')
                if img.getextrema()[1] > 0:
                    save(m, img)
        small = np.asarray(resized(base, scale))
        for folder, img, ext, kw in [('base', Image.fromarray(small[..., :3]), '.jpg', {'quality': 90}),
                                     ('alpha', Image.fromarray(small[..., 3]), '', {'optimize': True})]:
            dst = os.path.join(OUT, folder, rel + ext)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            img.save(dst, **kw)
        index[rel] = {'master': [base.width, base.height], 'size': list(size), 'scale': scale, 'masks': sorted(masks)}
    if features_only is not None:
        return
    with open(os.path.join(OUT, 'index.json'), 'w') as f:
        json.dump({'note': 'Generated by tools/app-assets/build_cat_art.py: each sprite\'s master size, its scale in '
                           'the app and the masks it has.', 'files': index}, f, indent=1, sort_keys=True)
        f.write('\n')
    with open(os.path.join(OUT, 'builder.json'), 'w') as f:
        json.dump(builder_json(), f, indent=1)
        f.write('\n')
    total = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(OUT) for n in ns)
    print(f'{len(index)} sprites into App/Art/cat/custom ({total / 1e6:.1f} MB)')


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--features':
        main(features_only=set(sys.argv[2:]))
    else:
        main()

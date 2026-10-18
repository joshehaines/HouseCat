#!/usr/bin/env python3
"""Fixtures for HouseCatGame's CoatRecipeTests: the Swift coat recipe checked against the reference
(tools/asset-pipeline/tint.py).

1. Pixel for pixel: a few crops of app-size sprites, with every input plane written out losslessly, and the
   reference's output for them. The reference here is tint.render's own maths with the fur mask given (the app
   bundles it, worked out at master size); the script first checks that this equals tint.render exactly.
2. Every preset (presetsheet.py's sit_tqfront render, at master size, scaled to the app's size) as a 4 x 4 grid
   of mean colours, which the app's render of the same preset from the bundled art must match.

Run from the repo root after build_cat_art.py; needs Pillow, numpy, scipy:
  python3 tools/app-assets/coat_fixtures.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'asset-pipeline'))
sys.path.insert(0, os.path.dirname(__file__))
from tint import W_LUM, render as tint_render, load_masks  # noqa: E402
import build_cat_art  # noqa: E402

CUSTOM = os.path.join(ROOT, 'assets', 'cat', 'custom')
APP = os.path.join(ROOT, 'App', 'Art', 'cat', 'custom')
OUT = os.path.join(ROOT, 'Packages', 'HouseCatGame', 'Tests', 'HouseCatGameTests', 'Fixtures', 'coat')
CB = json.load(open(os.path.join(CUSTOM, 'catbuilder.json')))
PAL = CB['palettes']


def recipe(rgb, al, fm, pattern=None, white=None, features=None, look=None):
    """tint.render with the fur mask given (fm: tint.py's fm before the irises are taken out)."""
    L = (rgb @ W_LUM) / 255.0
    shade = np.clip(L, 0, 1) ** 1.15
    col = np.broadcast_to(np.array(look['coat'], np.float32), rgb.shape).copy()
    if pattern is not None:
        pm = pattern[..., None]
        col = col * (1 - pm) + np.array(look['pattern_colour'], np.float32) * pm
    fur = shade[..., None] * col
    k = 0.35 * float(np.clip((np.array(look['coat'], np.float32) @ W_LUM) / 180.0, 0.3, 1.0))
    hi = np.clip((L - 0.85) / 0.15, 0, 1)[..., None]
    fur = fur * (1 - k * hi) + rgb * k * hi
    if white is not None:
        wm = white[..., None]
        fur = fur * (1 - wm) + rgb * wm
    fm = fm.copy()
    if features is not None:
        fm = fm * (1 - np.clip(features[..., 0] + features[..., 1], 0, 1))
    fm = fm[..., None]
    out = fur * fm + rgb * (1 - fm)
    if features is not None:
        for ch, key in ((0, 'eye_left'), (1, 'eye_right')):
            m = features[..., ch:ch + 1]
            if not m.any():
                continue
            v = np.clip(L / 0.62, 0, 1.35)[..., None]
            out = out * (1 - m) + np.clip(np.array(look[key], np.float32) * v, 0, 255) * m
        if features[..., 2].any():
            m = features[..., 2:3]
            v = np.clip(L / 0.72, 0, 1.3)[..., None]
            out = out * (1 - m) + np.clip(np.array(look['nose'], np.float32) * v, 0, 255) * m
    return np.clip(out, 0, 255).astype(np.uint8)


def look_of(p):
    return {'coat': PAL['coat'][p['coat']]['rgb'], 'pattern': p['pattern'],
            'pattern_colour': PAL['coat'][p['pattern_colour']]['rgb'] if p['pattern_colour'] else (0, 0, 0),
            'white': p['white'], 'eye_left': PAL['eyes'][p['eye_left']]['rgb'],
            'eye_right': PAL['eyes'][p['eye_right']]['rgb'], 'nose': PAL['nose'][p['nose']]['rgb']}


def preset(pid):
    return next(p for p in CB['presets'] if p['id'] == pid)


def self_check():
    """The recipe with the fur mask given equals tint.render (which works the mask out itself)."""
    rel = 'poses/cat_short_slim_sit_tqfront.png'
    base = Image.open(os.path.join(CUSTOM, 'base', rel)).convert('RGBA')
    p = preset('calico')
    masks = load_masks(CUSTOM, rel, p['pattern'], p['white'])
    want = np.asarray(tint_render(base, look_of(p), masks))[..., :3]
    a = np.asarray(base).astype(np.float32)
    got = recipe(a[..., :3], a[..., 3], build_cat_art.fur_mask(base), masks.get('pattern'), masks.get('white'),
                 masks.get('features'), look_of(p))
    assert np.array_equal(want, got), 'recipe() drifted from tint.render'


def app_planes(rel, size):
    """The app's inputs for a sprite, as the app reads them (masks scaled up to the sprite's size)."""
    rgb = np.asarray(Image.open(os.path.join(APP, 'base', rel + '.jpg')).convert('RGB')).astype(np.float32)
    al = np.asarray(Image.open(os.path.join(APP, 'alpha', rel)).convert('L'))

    def mask(name):
        path = os.path.join(APP, 'masks', name, rel)
        if not os.path.exists(path):
            return None
        img = Image.open(path)
        if img.size != size:
            img = img.convert('L').resize(size, Image.BILINEAR)
        return np.asarray(img).astype(np.float32) / 255
    return rgb, al, mask


CASES = [  # (name, sprite, preset, crop as fractions)
    ('calico_sit', 'poses/cat_short_slim_sit_tqfront.png', 'calico', (0.1, 0.0, 0.9, 0.6)),
    ('seal_point_head', 'parts/cat_siamese_tqfront_head.png', 'seal_point', (0, 0, 1, 1)),
    ('ragdoll_loaf', 'poses/cat_long_slim_loaf_side.png', 'ragdoll', (0.0, 0.2, 0.7, 1.0)),
    ('midnight_head', 'parts/cat_short_slim_front_head.png', 'midnight', (0, 0, 1, 1)),
]


def pixel_cases():
    for name, rel, pid, (x0, y0, x1, y1) in CASES:
        p = preset(pid)
        img = Image.open(os.path.join(APP, 'alpha', rel))
        size = img.size
        rgb, al, mask = app_planes(rel, size)
        fur = mask('fur')
        pattern = mask(p['pattern']) if p['pattern'] else None
        white = mask(p['white']) if p['white'] else None
        features = mask('features')
        out = recipe(rgb, al, fur, pattern, white, features, look_of(p))
        box = (int(size[0] * x0), int(size[1] * y0), int(size[0] * x1), int(size[1] * y1))

        def crop(a):
            return a[box[1]:box[3], box[0]:box[2]]

        def save(suffix, arr):
            Image.fromarray(np.clip(np.round(arr), 0, 255).astype(np.uint8)).save(os.path.join(OUT, f'{name}_{suffix}.png'))
        save('rgb', crop(rgb))
        save('alpha', crop(al))
        save('fur', crop(fur) * 255)
        if pattern is not None:
            save('pattern', crop(pattern) * 255)
        if white is not None:
            save('white', crop(white) * 255)
        if features is not None:
            save('features', crop(features) * 255)
        save('expected', crop(out))
        yield {'name': name, 'preset': pid, 'sprite': rel}


def signature(rgba, grid=4):
    a = np.asarray(rgba).astype(np.float32)
    h, w = a.shape[:2]
    cells = []
    for gy in range(grid):
        for gx in range(grid):
            c = a[gy * h // grid:(gy + 1) * h // grid, gx * w // grid:(gx + 1) * w // grid]
            m = c[..., 3] > 128
            cells.append([round(float(v), 2) for v in c[m][:, :3].mean(axis=0)] if m.sum() > 20 else None)
    return cells


def presets():
    out = {}
    for p in CB['presets']:
        rel = 'poses/cat_{}_sit_tqfront{}.png'.format(p['body'], (
            '__' + '_'.join(v for v in (p['ears'] if p['ears'] != 'own' else None,
                                        p['tail'] if p['tail'] != 'own' else None) if v)
        ) if (p['ears'] != 'own' or p['tail'] != 'own') else '')
        base = Image.open(os.path.join(CUSTOM, 'base', rel)).convert('RGBA')
        ref = tint_render(base, look_of(p), load_masks(CUSTOM, rel, p['pattern'], p['white']))
        size = Image.open(os.path.join(APP, 'alpha', rel)).size
        small = ref.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')
        out[p['id']] = {'sprite': rel, 'cells': signature(small)}
    return out


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    self_check()
    cases = list(pixel_cases())
    with open(os.path.join(OUT, 'cases.json'), 'w') as f:
        json.dump({'note': 'Generated by tools/app-assets/coat_fixtures.py.', 'cases': cases, 'presets': presets()}, f, indent=1)
        f.write('\n')
    total = sum(os.path.getsize(os.path.join(OUT, n)) for n in os.listdir(OUT))
    print(f'{len(cases)} pixel cases and {len(CB["presets"])} presets into {os.path.relpath(OUT, ROOT)} ({total / 1e3:.0f} KB)')

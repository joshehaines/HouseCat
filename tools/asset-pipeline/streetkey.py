"""Keys the city street's pieces (cars, bus shelter, post box, phone box, cafe, terraces; Josh, 19 Oct: a city should look
like a city) off the magenta they were painted on, into assets/world/props/city_<name>.png, and bundles each at 0.3 as
HEIC in App/Art with its entry in App/Art/art.json, as build_app_art.py does for the other props.

Like shopkey.py, but only what is joined to the background round a piece goes see-through, and the magenta spill is
greyed only along the edges: these pieces are red paint with pink highlights the shop's key took for magenta.

    uv run --with numpy --with pillow --with scipy python tools/asset-pipeline/streetkey.py <raw_dir> car_red car_blue ...

<raw_dir> holds the Higgsfield renders as raw_<name>.png (painted with gpt_image_2_5 on magenta, with city_plane and
city_lamp as style references).
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SCALE = 0.3


def key(src):
    a = np.asarray(Image.open(src).convert('RGB')).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = np.clip(((r + b) / 2 - g - 40) / 90, 0, 1)
    lab, _ = ndimage.label(m > 0.5)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    border = np.isin(lab, list(edge))
    keycol = np.median(a[border], axis=0)
    dist = np.sqrt(((a - keycol) ** 2).sum(-1))
    alpha = np.clip((dist - 40) / 80, 0, 1)
    alpha[border] = 0
    # Only what is joined to the background round the piece goes see-through: flood from the edges through
    # key-like pixels. A pink highlight on red paint, inside the piece, stays solid (flat magenta holes still key).
    near = dist < 60
    reach, _ = ndimage.label(near)
    outside_labels = set(np.unique(np.concatenate([reach[0], reach[-1], reach[:, 0], reach[:, -1]]))) - {0}
    outside = ndimage.binary_dilation(np.isin(reach, list(outside_labels)), iterations=2)
    inside = ~outside & (dist >= 25)
    alpha[inside] = 1
    alpha = ndimage.gaussian_filter(alpha, 0.6)
    alpha[inside & (ndimage.binary_erosion(inside, iterations=1))] = 1
    safe = np.maximum(alpha, 0.05)[..., None]
    fg = (a - (1 - safe) * keycol) / safe
    out = np.where(alpha[..., None] < 0.999, np.clip(fg, 0, 255), a)
    # The kept highlights were painted with the key's pink in them: their blue is pulled towards their green.
    pink = inside & ((a[..., 0] + a[..., 2]) / 2 - a[..., 1] > 40)
    out[..., 2] = np.where(pink, out[..., 1] + (out[..., 2] - out[..., 1]) * 0.35, out[..., 2])
    # Spill only in the soft rim (a few pixels in from the edge), never across solid paint.
    rim = ndimage.binary_dilation(alpha < 0.98, iterations=3) & (alpha > 0.02)
    mx, mn = out.max(-1), out.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    rr, gg, bb = out[..., 0], out[..., 1], out[..., 2]
    hue = (np.degrees(np.arctan2(np.sqrt(3) * (gg - bb), 2 * rr - gg - bb)) + 360) % 360
    spill = rim & (hue > 288) & (hue < 328) & (sat > 0.66) & (mx > 90)
    grey = out.mean(-1, keepdims=True)
    out = np.where(spill[..., None], grey * 0.85 + out * 0.15, out)
    im = Image.fromarray(np.dstack([out, np.clip(alpha * 255, 0, 255)]).astype(np.uint8))
    return im.crop(im.getbbox())


def main(raw_dir, names):
    index_path = os.path.join(ROOT, 'App/Art/art.json')
    index = json.load(open(index_path))
    for name in names:
        im = key(os.path.join(raw_dir, f'raw_{name}.png'))
        rel = f'world/props/city_{name}.png'
        master = os.path.join(ROOT, 'assets', rel)
        im.save(master, optimize=True)
        w, h = im.size
        heic = f'world/props/city_{name}.heic'
        subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', '82', '-z', str(round(h * SCALE)),
                        str(round(w * SCALE)), master, '--out', os.path.join(ROOT, 'App/Art', heic)], capture_output=True, check=True)
        index['files'][rel] = {'file': heic, 'master': [w, h], 'scale': SCALE}
        print(rel, im.size)
    with open(index_path, 'w') as out:
        json.dump(index, out, indent=1, sort_keys=True)
        out.write('\n')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:])

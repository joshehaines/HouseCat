"""Keys and cuts the Games paintings (art.py) off their magenta into assets/arcade.

uv run --with numpy --with pillow --with scipy --with opencv-python-headless python cut.py <raw folder> <out folder>

The raw folder holds the Higgsfield results under the names art.py gives them (tile_zoomies.png, sheet_match.png ...).
Tiles are keyed whole (shopkey.py's key: soft edges, the magenta unmixed out of them, spill greyed); sheets are cut into
their pieces in reading order (post.cut_sheet); the four-in-a-row board has its cyan holes cut clear as well.
Only the files whose raws are present are written; nothing in assets/ outside the out folder is touched.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import post  # noqa: E402
from art import ICON_NAMES, LEDGE_NAMES, MATCH_NAMES, PLACES, POUNCE_NAMES, RUN_NAMES, RUN_SCENES  # noqa: E402


def key(src, crop=True):
    """shopkey.py's key, returned as an RGBA image (cropped to its subject unless `crop` is False). It keys by the
    distance to the background's own colour, so violet and coral in a picture stay solid."""
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
    alpha = ndimage.gaussian_filter(alpha, 0.6)
    safe = np.maximum(alpha, 0.05)[..., None]
    fg = (a - (1 - safe) * keycol) / safe
    out = np.where(alpha[..., None] < 0.999, np.clip(fg, 0, 255), a)
    mx, mn = out.max(-1), out.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    rr, gg, bb = out[..., 0], out[..., 1], out[..., 2]
    hue = (np.degrees(np.arctan2(np.sqrt(3) * (gg - bb), 2 * rr - gg - bb)) + 360) % 360
    spill = (hue > 288) & (hue < 328) & (sat > 0.66) & (mx > 90) & (alpha > 0.02)
    grey = out.mean(-1, keepdims=True)
    out = np.where(spill[..., None], grey * 0.85 + out * 0.15, out)
    im = Image.fromarray(np.dstack([out, np.clip(alpha * 255, 0, 255)]).astype(np.uint8))
    return im.crop(im.getbbox()) if crop else im


def keyed_sheet(src, outdir, names):
    """A sheet keyed as a whole with `key`, then cut into its pieces in reading order (post.components)."""
    im = key(src, crop=False)
    a = np.asarray(im).astype(np.float32)
    alpha = a[..., 3] / 255
    boxes = post.components(alpha, 0.002, 25)
    os.makedirs(outdir, exist_ok=True)
    for i, (y0, y1, x0, x1, _) in enumerate(boxes):
        name = names[i] if i < len(names) else f'extra{i}'
        p = 8
        y0, x0 = max(0, y0 - p), max(0, x0 - p)
        y1, x1 = min(a.shape[0], y1 + p), min(a.shape[1], x1 + p)
        piece = im.crop((x0, y0, x1, y1))
        piece.crop(piece.getbbox()).save(os.path.join(outdir, f'{name}.png'), optimize=True)
    return len(boxes)


def wrap(src, dst, band=0.12):
    """A wide background made to repeat side by side: its left and right edges cross-faded with the picture moved
    round by half (tiles.py's way, across only), saved as JPEG."""
    a = np.asarray(Image.open(src).convert('RGB')).astype(np.float32)
    h, w = a.shape[:2]
    shifted = np.roll(a, w // 2, axis=1)
    x = np.arange(w) / (w - 1)
    d = np.minimum(x, 1 - x)
    t = np.clip(d / band, 0, 1)
    weight = (t * t * (3 - 2 * t))[None, :, None]
    out = a * weight + shifted * (1 - weight)
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(dst, quality=92)


def board(src, dst):
    """The board: magenta round it and cyan in its holes both go clear."""
    a = np.asarray(Image.open(src).convert('RGB')).astype(np.float32)
    alpha = post.magenta_alpha(a)
    holes = ndimage.binary_dilation(post.cyan_mask(a), iterations=2)
    alpha = np.where(holes, 0, alpha)
    rgb = post.despill(a, alpha)
    post.save_rgba(rgb, alpha, dst)


def main(raw, out):
    """`out` is assets/arcade (or a scratch folder): ui/, match/, row/, run/, pounce/ under it."""
    have = lambda name: os.path.exists(os.path.join(raw, f'{name}.png'))
    folder = lambda name: os.makedirs(os.path.join(out, name), exist_ok=True) or os.path.join(out, name)
    for name in ('tile_zoomies', 'tile_catapult', 'tile_match', 'tile_row', 'tile_puzzle'):
        if have(name):
            key(os.path.join(raw, f'{name}.png')).save(os.path.join(folder('ui'), f'{name}.png'), optimize=True)
            print(name)
    sheets = [('sheet_match', 'match', [f'match_{n}' for n in MATCH_NAMES]),
              ('icons_games', 'ui', [f'icon_game_{n}' for n in ICON_NAMES]),
              ('sheet_run', 'run', [f'thing_{n}' for n in RUN_NAMES]),
              ('sheet_pounce', 'pounce', [f'piece_{n}' for n in POUNCE_NAMES]),
              ('sheet_ledges', 'pounce', LEDGE_NAMES)]
    for raw_name, sub, names in sheets:
        if have(raw_name):
            n = keyed_sheet(os.path.join(raw, f'{raw_name}.png'), folder(sub), names)
            print(raw_name, n, 'pieces of', len(names))
    if have('board_row'):
        board(os.path.join(raw, 'board_row.png'), os.path.join(folder('row'), 'row_board.png'))
        print('board')
    for name in RUN_SCENES:
        if have(name):
            wrap(os.path.join(raw, f'{name}.png'), os.path.join(folder('run'), name.replace('run_', 'bg_') + '.jpg'))
            print(name)
    for name in PLACES:
        if have(name):
            Image.open(os.path.join(raw, f'{name}.png')).convert('RGB').save(os.path.join(folder('pounce'), f'{name}.jpg'), quality=92)
            print(name)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

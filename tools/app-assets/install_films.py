"""Copies the cat's film frames (assets/cat/films/frames, made by tools/asset-pipeline/walk/filmwalk.py and indexed by
filmwalk's filmindex.py) into App/Art/cat/custom, as build_cat_art.py's last step, and packs them for the app (21 Oct:
96 films would have been 275 MB as the masters are): each frame's painting and alpha become one WebP with alpha
(base/films/<frame>.webp, quality WEBP_QUALITY, the alpha kept exact; read by CatArt.painting. Not HEIC: the simulator's
HEVC decoder deadlocks when the films are tinted off the main thread while SwiftUI decodes a HEIC on it, as the shop
tab found on 21 Oct), and the smooth masks (the torso map `uv`, `tortie`, `colourpoint` and the white markings) are
kept at a quarter of the frame's size (the tabbies and spots keep half, their stripes and spots need it; CatArt scales
any mask up to the frame).

    uv run --with pillow python -I tools/app-assets/install_films.py
"""
import os
import shutil
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
FRAMES = os.path.join(ROOT, 'assets', 'cat', 'films', 'frames')
OUT = os.path.join(ROOT, 'App', 'Art', 'cat', 'custom')
WEBP_QUALITY = 85
QUARTER = ['uv', 'tortie', 'colourpoint', 'white_bicolour', 'white_mitts', 'white_tuxedo', 'white_van']


def pack(name):
    """One frame: its painting and alpha into a WebP, the master JPEG and PNG dropped from the app."""
    jpg = os.path.join(OUT, 'base', 'films', name + '.jpg')
    png = os.path.join(OUT, 'alpha', 'films', name)
    webp = os.path.join(OUT, 'base', 'films', name + '.webp')
    if not (os.path.exists(jpg) and os.path.exists(png)):
        return 0
    image = Image.open(jpg).convert('RGB')
    image.putalpha(Image.open(png).convert('L'))
    image.save(webp, quality=WEBP_QUALITY, method=6)
    os.remove(jpg)
    os.remove(png)
    return os.path.getsize(webp)


def main():
    shutil.copytree(FRAMES, OUT, dirs_exist_ok=True)
    base = os.path.join(OUT, 'base', 'films')
    for stale in os.listdir(base):
        if stale.endswith('.heic'):
            os.remove(os.path.join(base, stale))
    frames = sorted(n for n in os.listdir(os.path.join(FRAMES, 'alpha', 'films')) if n.endswith('.png'))
    with ThreadPoolExecutor(8) as pool:
        packed = sum(pool.map(pack, frames))
    for kind in QUARTER:
        folder = os.path.join(OUT, 'masks', kind, 'films')
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            path = os.path.join(folder, name)
            source = os.path.join(FRAMES, 'masks', kind, 'films', name)
            mask = Image.open(source if os.path.exists(source) else path)
            small = mask.resize((max(1, mask.width // 2), max(1, mask.height // 2)), Image.BILINEAR)
            if small.mode == 'L':
                # Back to the masks' 16 levels of grey (they compress far better).
                small = small.point(lambda v: round(v / 17) * 17)
            small.save(path, optimize=True)
    films = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(OUT) for n in ns if dp.endswith('films'))
    print(f'{len(frames)} frames into App/Art/cat/custom: {packed / 1e6:.1f} MB of WebP, films {films / 1e6:.1f} MB in all')


if __name__ == '__main__':
    main()

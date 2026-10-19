"""Keys the curl film (Higgsfield, Kling 3.0: Midnight landing on the letters and curling up asleep, made from the
frames tests render with renderTheCurlKeyframes) off its chroma green into transparent frames for the logo's films.

    uv run --with numpy --with pillow --with scipy --with opencv-python-headless python \
        tools/asset-pipeline/logo/curlkey.py assets/brand/logo/logo_curl_film.mp4 <out folder>

(tools/app-assets/build_logo_film.sh runs it.) The film is 1920 x 1080 with the cat's feet on the ledge in the middle.
Writes frame_NNN.png and fps.txt. Each frame: the green is keyed by how much greener than red and blue a pixel is, the green spill on the fur's edge
is pulled back to the cat's own colour, everything at and below the ledge's top (the letters in the logo) is cut away,
and the result is cropped to a fixed box round the cat so every frame lines up. Frames at the end where the cat no
longer moves are dropped (the logo's film holds its last frame, and the app breathes it).
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

# The frames' layout (renderTheCurlKeyframes): 1920 x 1080, the ledge's top 300 px up from the bottom, the cat's feet
# in the middle. The box kept round the cat, in the frame's pixels (left, top, right, bottom).
LEDGE_TOP = 1080 - 300
BOX = (360, 60, 1560, LEDGE_TOP)
# Greenness (G minus the larger of R and B) where a pixel starts and stops being background.
SOLID, CLEAR = 18, 70
# A frame differing from the last by less than this (mean over the box, 0-255) is the cat lying still; a few are kept.
STILL, STILL_KEPT = 1.2, 6


def key(frame):
    rgb = np.asarray(frame.convert('RGB')).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    greenness = g - np.maximum(r, b)
    alpha = 1 - np.clip((greenness - SOLID) / (CLEAR - SOLID), 0, 1)
    # Spill: no pixel of the cat is greener than its red and blue allow.
    g2 = np.minimum(g, np.maximum(r, b) * 1.02)
    out = np.dstack([r, g2, b])
    # The ledge (the letters in the logo) and anything under it go.
    alpha[LEDGE_TOP:, :] = 0
    # Specks of background the green missed, and holes inside the cat.
    solid = alpha > 0.5
    labels, count = ndimage.label(solid)
    if count:
        sizes = ndimage.sum(solid, labels, range(1, count + 1))
        keep = np.isin(labels, 1 + np.flatnonzero(sizes >= sizes.max() * 0.05))
        alpha = np.where(keep | (alpha < 0.5), alpha, 0)
        alpha = np.where(ndimage.binary_dilation(keep, iterations=3), alpha, 0)
    rgba = np.dstack([out, alpha * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(rgba, 'RGBA').crop(BOX)


def main():
    source, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    film = cv2.VideoCapture(source)
    fps = film.get(cv2.CAP_PROP_FPS)
    keyed = []
    while True:
        ok, bgr = film.read()
        if not ok:
            break
        frame = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        if frame.size != (1920, 1080):
            frame = frame.resize((1920, 1080), Image.LANCZOS)
        keyed.append(key(frame))
    last = np.asarray(keyed[-1]).astype(np.float32)
    moving = [i for i, k in enumerate(keyed) if np.abs(np.asarray(k).astype(np.float32) - last).mean() > STILL]
    end = min(len(keyed), (moving[-1] if moving else 0) + 1 + STILL_KEPT)
    for i, k in enumerate(keyed[:end - 1] + [keyed[-1]]):
        k.save(os.path.join(out, f'frame_{i:03d}.png'))
    with open(os.path.join(out, 'fps.txt'), 'w') as f:
        f.write(f'{fps}\n')
    print(end, 'of', len(keyed), 'frames at', fps, 'fps keyed into', out)


if __name__ == '__main__':
    main()

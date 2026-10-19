"""Keys the curl film (Higgsfield, Kling 3.0: Midnight landing on the letters and curling up asleep, made from the
frames tests render with renderTheCurlKeyframes) off its chroma green into transparent frames for the logo's films.

    uv run --with numpy --with pillow --with scipy --with opencv-python-headless python \
        tools/asset-pipeline/logo/curlkey.py assets/brand/logo/logo_curl_film.mp4 <out folder>

(tools/app-assets/build_logo_film.sh runs it.) The film is 1920 x 1080 with the cat's feet on the ledge in the middle.
Writes frame_NNN.png and fps.txt. Each frame: the green is keyed by how much greener than red and blue a pixel is, the green spill on the fur's edge
is pulled back to the cat's own colour, everything at and below the ledge's top (the letters in the logo) is cut away,
and the result is cropped to a fixed box round the cat so every frame lines up. Over the film, a sudden change in the
cat's colour (the clip lights its fur orange for a moment as it turns) is evened out against the frames round it. The
still opening (the cat standing as it lands, before it moves) and the still end are dropped: the logo's cat is already
moving when the film takes over, and the film holds its last frame while the app breathes it.
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
# The opening frames differing from the first by less than this are the cat standing still as it lands.
STILL_START = 1.6
# The cat's colour is held to its average over this many frames round each, changing it by at most this share.
EVEN_FRAMES, EVEN_MOST = 17, 0.2


def even_out(frames):
    """Each frame's cat scaled, channel by channel, towards the running average of the cat's colour round it."""
    arrays = [np.asarray(f).astype(np.float32) for f in frames]
    means = []
    for a in arrays:
        solid = a[..., 3] > 200
        means.append(a[..., :3][solid].mean(axis=0) if solid.any() else np.ones(3))
    means = np.array(means)
    half = EVEN_FRAMES // 2
    out = []
    for i, a in enumerate(arrays):
        window = means[max(0, i - half):i + half + 1]
        target = np.median(window, axis=0)
        gain = np.clip(target / np.maximum(means[i], 1), 1 - EVEN_MOST, 1 + EVEN_MOST)
        a = a.copy()
        a[..., :3] = np.clip(a[..., :3] * gain, 0, 255)
        out.append(Image.fromarray(a.round().astype(np.uint8), 'RGBA'))
    return out


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
    keyed = even_out(keyed)
    first = np.asarray(keyed[0]).astype(np.float32)
    last = np.asarray(keyed[-1]).astype(np.float32)
    begin = next((i for i, k in enumerate(keyed) if np.abs(np.asarray(k).astype(np.float32) - first).mean() > STILL_START), 1)
    moving = [i for i, k in enumerate(keyed) if np.abs(np.asarray(k).astype(np.float32) - last).mean() > STILL]
    end = min(len(keyed), (moving[-1] if moving else 0) + 1 + STILL_KEPT)
    # The first frame (the art the cat lands as) stays, the still ones after it go.
    kept = [keyed[0]] + keyed[max(1, begin - 1):end - 1] + [keyed[-1]]
    for i, k in enumerate(kept):
        k.save(os.path.join(out, f'frame_{i:03d}.png'))
    with open(os.path.join(out, 'fps.txt'), 'w') as f:
        f.write(f'{fps}\n')
    print(len(kept), 'of', len(keyed), 'frames at', fps, 'fps keyed into', out, f'(from frame {max(1, begin - 1)})')


if __name__ == '__main__':
    main()

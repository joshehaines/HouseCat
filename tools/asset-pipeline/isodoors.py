"""Doors painted in 3D at the LEFT wall's 2:1 angle (Josh, 19 Oct: "make the doors 3d"), keyed off magenta.

Each was painted by gpt_image_2_5 from two references: a render of the living room's left wall, and a guide on magenta
with the outer edge of the door frame drawn at the wall's slope. The cut (openings.cut) keeps the frame, the door and
the hallway seen through it; then the picture is squared up so its sides are exactly vertical and its threshold rises
exactly 1 in 2 to the right, and cropped to the frame. The bottom-left corner of the result is the frame's front foot
on the floor line, and its right edge is the back foot, so the game hangs it by the width it spans along the wall.

uv run --with numpy --with pillow --with scipy python tools/asset-pipeline/isodoors.py <raw.png> <out.png> [...]
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from openings import cut  # noqa: E402

SLOPE = -0.5  # the floor line along the left wall, in picture pixels (y down): up 1 for every 2 to the right


def fit(xs, ys, rounds=4, tolerance=4.0):
    """A least-squares line ys = a + b xs, refitted without the points far off it (feet, mouldings)."""
    keep = np.ones(len(xs), bool)
    for _ in range(rounds):
        b, a = np.polyfit(xs[keep], ys[keep], 1)
        keep = np.abs(ys - (a + b * xs)) < tolerance
    return a, b


def square(path_in, path_out):
    tmp_frame, tmp_open = path_out + '.frame.png', path_out + '.open.png'
    cut(path_in, tmp_frame, tmp_open)
    os.remove(tmp_open)
    img = Image.open(tmp_frame).convert('RGBA')
    os.remove(tmp_frame)
    alpha = np.asarray(img)[..., 3] > 128
    h, w = alpha.shape
    # Its sides: the left edge of the frame down the middle of its height should be straight up.
    rows = np.arange(int(h * 0.35), int(h * 0.75))
    lefts = np.array([np.argmax(alpha[y]) for y in rows], float)
    _, lean = fit(rows.astype(float), lefts)
    if abs(lean) > 0.002:
        img = img.transform(img.size, Image.AFFINE, (1, lean, -lean * h / 2, 0, 1, 0), Image.BICUBIC)
        alpha = np.asarray(img)[..., 3] > 128
    # Its threshold: the lowest painted pixel of each column across the middle of the door.
    cols = np.arange(int(w * 0.15), int(w * 0.85))
    bottoms = np.array([h - 1 - np.argmax(alpha[::-1, x]) if alpha[:, x].any() else -1 for x in cols], float)
    ok = bottoms >= 0
    _, slope = fit(cols[ok].astype(float), bottoms[ok])
    shear = SLOPE - slope
    # y_out = y_in + shear * x, so the picture is read from y_in = y_out - shear * x; room above for the lift.
    pad = int(abs(shear) * w) + 4
    big = Image.new('RGBA', (w, h + 2 * pad), (0, 0, 0, 0))
    big.paste(img, (0, pad))
    img = big.transform(big.size, Image.AFFINE, (1, 0, 0, -shear, 1, 0), Image.BICUBIC)
    img = img.crop(img.getbbox())
    img.save(path_out)
    return img.size, round(lean, 4), round(slope, 4)


if __name__ == '__main__':
    args = sys.argv[1:]
    for raw, out in zip(args[::2], args[1::2]):
        print(out, square(raw, out))

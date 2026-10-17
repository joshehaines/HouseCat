"""Cut windows and doors painted on magenta with cyan openings.
Outputs per item: <kind>_<id>.png (frame only, RGBA, openings transparent) and <kind>_<id>_opening.png
(white = glass / doorway, where the app draws the sky or the next room).
python3 openings.py window|door"""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage

def cut(path, out_frame, out_open):
    a = np.asarray(Image.open(path).convert('RGB')).astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # magenta background: high R and B, low G
    mag = (r > 150) & (b > 150) & (g < 120) & (np.abs(r - b) < 90)
    # cyan opening: low R, high G and B
    cya = (r < 120) & (g > 150) & (b > 150) & (np.abs(g - b) < 90)
    # the background is the magenta region connected to the border
    lab, n = ndimage.label(mag)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    bg = ndimage.binary_closing(bg, iterations=2)
    opening = ndimage.binary_opening(cya, iterations=2)
    opening = ndimage.binary_fill_holes(ndimage.binary_closing(opening, iterations=3)) & ~bg
    frame = ~(bg | opening)
    frame = ndimage.binary_opening(frame, iterations=1)
    # keep the largest frame component plus anything big attached
    lab, n = ndimage.label(frame)
    if n > 1:
        s = ndimage.sum(frame, lab, range(1, n + 1)); keep = np.zeros_like(frame)
        for i, v in enumerate(s, 1):
            if v > 0.01 * s.max(): keep |= lab == i
        frame = keep
    # de-spill: pull magenta and cyan fringes towards neutral on the frame edge
    edge = frame & ~ndimage.binary_erosion(frame, iterations=3)
    rgb = a.copy()
    spill_m = edge & (r > g + 40) & (b > g + 40)
    rgb[spill_m, 0] = rgb[spill_m, 1] + (rgb[spill_m, 0] - rgb[spill_m, 1]) * 0.3
    rgb[spill_m, 2] = rgb[spill_m, 1] + (rgb[spill_m, 2] - rgb[spill_m, 1]) * 0.3
    spill_c = edge & (g > r + 40) & (b > r + 40)
    rgb[spill_c, 1] = rgb[spill_c, 0] + (rgb[spill_c, 1] - rgb[spill_c, 0]) * 0.3
    rgb[spill_c, 2] = rgb[spill_c, 0] + (rgb[spill_c, 2] - rgb[spill_c, 0]) * 0.3
    alpha = (frame * 255).astype(np.uint8)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), alpha]))
    bbox = img.getbbox()
    img.crop(bbox).save(out_frame)
    Image.fromarray((opening * 255).astype(np.uint8)).crop(bbox).save(out_open)
    return img.crop(bbox).size, float(opening.sum() / max(1, frame.sum()))

if __name__ == '__main__':
    kind = sys.argv[1]
    os.makedirs(f'surfaces/{kind}s', exist_ok=True)
    for f in sorted(os.listdir(f'gen/{kind}')):
        iid = f[:-4]
        print(iid, cut(f'gen/{kind}/{f}', f'surfaces/{kind}s/{kind}_{iid}.png', f'surfaces/{kind}s/{kind}_{iid}_opening.png'))

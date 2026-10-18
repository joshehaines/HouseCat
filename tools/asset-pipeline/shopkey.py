"""Keys the shop illustrations (assets/ui/shop) off the magenta they are painted on.

Run with the raw Higgsfield renders as raw_<name>.png in the current directory and an empty v3/ beside
them: python3 shopkey.py club starter housewarming forever adopt gifts
"""
import sys, numpy as np
from PIL import Image
from scipy import ndimage
# The background is a flat magenta. Pixels near it go transparent wherever they are (gaps between leaves
# and tassel strands too), blends get partial alpha, and the key colour is unmixed out of their colour.
def key(src, dst):
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
    # unmix: c = alpha * fg + (1 - alpha) * key
    safe = np.maximum(alpha, 0.05)[..., None]
    fg = (a - (1 - safe) * keycol) / safe
    out = np.where(alpha[..., None] < 0.999, np.clip(fg, 0, 255), a)
    # Magenta spill painted into the picture (leaves beside the key): saturated magenta is no colour these
    # pictures use, so it is greyed to its own lightness.
    mx, mn = out.max(-1), out.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    rr, gg, bb = out[..., 0], out[..., 1], out[..., 2]
    hue = (np.degrees(np.arctan2(np.sqrt(3) * (gg - bb), 2 * rr - gg - bb)) + 360) % 360
    spill = (hue > 288) & (hue < 328) & (sat > 0.66) & (mx > 90) & (alpha > 0.02)
    grey = out.mean(-1, keepdims=True)
    out = np.where(spill[..., None], grey * 0.85 + out * 0.15, out)
    print('  spill greyed', int(spill.sum()))
    im = Image.fromarray(np.dstack([out, np.clip(alpha * 255, 0, 255)]).astype(np.uint8))
    im = im.crop(im.getbbox())
    im.save(dst, optimize=True)
    return im.size, keycol
for n in sys.argv[1:]:
    print(n, key(f'raw_{n}.png', f'v3/shop_{n}.png'))

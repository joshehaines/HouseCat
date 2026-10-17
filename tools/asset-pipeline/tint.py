"""Cat builder: the reference implementation of the coat recipe (port this to Swift/Metal; a CIColorKernel or a
SpriteKit SKShader does the same per-pixel maths).

Inputs for one sprite (all the same size, from cat/custom/):
  base/<path>.png                 white-base painting (RGBA)
  masks/<pattern>/<path>.png      8-bit greyscale, 255 = pattern colour here     (tabby_*, spotted, tortie, colourpoint)
  masks/white_<style>/<path>.png  8-bit greyscale, 255 = this fur stays white    (white_tuxedo, _bicolour, _mitts, _van)
  masks/features/<path>.png       RGB: R = iris of the left-hand eye in the image, G = right-hand eye, B = nose leather
A missing mask file means 0 everywhere (e.g. swap ears/tails never carry white markings).

render(base, look, masks) -> RGBA
look = {'coat': rgb, 'pattern': name|None, 'pattern_colour': rgb, 'white': name|None,
        'eye_left': rgb, 'eye_right': rgb, 'nose': rgb|None}
"""
import numpy as np
from PIL import Image
from scipy import ndimage

W_LUM = np.array([0.3, 0.55, 0.15], np.float32)


def _fur_mask(rgb):
    """1 = fur/skin to tint, 0 = keep the painting. Only pink things are kept (inner ears, nose, paw pads); the warm
    rim light is fur. Eyes are protected separately by the features mask."""
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1e-3)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    pinkhue = np.clip(np.minimum((24 - hue) / 6, 1), 0, 1) + np.clip((hue - 320) / 10, 0, 1)
    pink = np.clip((sat - 0.14) / 0.12, 0, 1) * np.clip(pinkhue, 0, 1)
    return 1 - pink


def _arr(img): return np.asarray(img.convert('RGBA')).astype(np.float32)


def render(base, look, masks=None, depth=1.15):
    masks = masks or {}
    a = _arr(base); rgb, al = a[..., :3], a[..., 3:]
    L = (rgb @ W_LUM) / 255.0
    shade = np.clip(L, 0, 1) ** depth
    col = np.broadcast_to(np.array(look['coat'], np.float32), rgb.shape).copy()
    pm = masks.get('pattern')
    if pm is not None:
        pm = pm[..., None]
        col = col * (1 - pm) + np.array(look['pattern_colour'], np.float32) * pm
    fur = shade[..., None] * col
    # keep a little of the painted highlight / warm rim light; less of it on dark coats so the rim doesn't sparkle
    k = 0.35 * float(np.clip((np.array(look['coat'], np.float32) @ W_LUM) / 180.0, 0.3, 1.0))
    hi = np.clip((L - 0.85) / 0.15, 0, 1)[..., None]
    fur = fur * (1 - k * hi) + rgb * k * hi
    wm = masks.get('white')
    if wm is not None:                                          # white markings: show the white painting itself
        wm = wm[..., None]; fur = fur * (1 - wm) + rgb * wm
    fm = _fur_mask(rgb)
    inside = ndimage.binary_erosion(al[..., 0] > 128, iterations=7)
    fm = np.where(~inside & (al[..., 0] > 0), 1.0, fm)     # the silhouette edge is always fur
    ft = masks.get('features')
    if ft is not None:
        fm = fm * (1 - np.clip(ft[..., 0] + ft[..., 1], 0, 1))   # irises keep their painting unless recoloured below
    fm = fm[..., None]
    out = fur * fm + rgb * (1 - fm)
    if ft is not None:
        for ch, key in ((0, 'eye_left'), (1, 'eye_right')):
            m = ft[..., ch:ch + 1]
            if look.get(key) is None or not m.any(): continue
            tgt = np.array(look[key], np.float32)
            # keep the painted value structure of the iris (dark rim, bright centre), swap the hue
            v = np.clip(L / 0.62, 0, 1.35)[..., None]
            out = out * (1 - m) + np.clip(tgt * v, 0, 255) * m
        if look.get('nose') is not None and ft[..., 2].any():
            m = ft[..., 2:3]
            v = np.clip(L / 0.72, 0, 1.3)[..., None]
            out = out * (1 - m) + np.clip(np.array(look['nose'], np.float32) * v, 0, 255) * m
    return Image.fromarray(np.dstack([np.clip(out, 0, 255), al]).astype(np.uint8))


def load_masks(root, rel, pattern=None, white=None):
    """root = 'cat/custom', rel = e.g. 'poses/cat_short_slim_sit_side.png'."""
    import os
    m = {}
    def g(p):
        return np.asarray(Image.open(p).convert('L')).astype(np.float32) / 255 if os.path.exists(p) else None
    if pattern: m['pattern'] = g(f'{root}/masks/{pattern}/{rel}')
    if white: m['white'] = g(f'{root}/masks/{white}/{rel}')
    fp = f'{root}/masks/features/{rel}'
    if os.path.exists(fp): m['features'] = np.asarray(Image.open(fp).convert('RGB')).astype(np.float32) / 255
    return {k: v for k, v in m.items() if v is not None}


COLOURS = {   # fur colours (sRGB of a fully lit hair); the app can also offer a free colour picker
 'black': (58, 50, 62), 'smoke': (96, 96, 108), 'blue': (138, 148, 168), 'lilac': (196, 184, 196),
 'chocolate': (120, 78, 54), 'cinnamon': (176, 112, 70), 'fawn': (214, 184, 160), 'brown': (150, 108, 72),
 'red': (214, 104, 46), 'ginger': (236, 140, 62), 'cream': (246, 222, 180), 'white': (250, 248, 244),
 'silver': (214, 216, 222), 'seal': (70, 52, 44), 'golden': (222, 170, 96), 'rose': (236, 194, 180),
}
EYES = {'amber': (236, 168, 40), 'gold': (240, 200, 60), 'copper': (214, 110, 40), 'green': (110, 190, 80),
        'hazel': (170, 160, 70), 'blue': (90, 160, 236), 'aqua': (90, 200, 200), 'lilac': (176, 150, 220)}
NOSES = {'pink': (232, 150, 160), 'brick': (196, 96, 80), 'black': (52, 44, 48), 'grey': (120, 120, 132),
         'chocolate': (110, 70, 56)}

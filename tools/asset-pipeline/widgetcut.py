"""Widget frames: full painted wall + sill with cyan glass. Output widget/widget_<id>.png (glass transparent, soft edge)
and widget/widget_<id>_glass.png (white = glass). python3 widgetcut.py"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

os.makedirs('widget', exist_ok=True)
for f in sorted(os.listdir('gen/widget')):
    iid = f[:-4]
    a = np.asarray(Image.open(f'gen/widget/{f}').convert('RGB')).astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # 'cyan-ness' 0..1
    c = np.clip(((g + b) / 2 - r - 60) / 110, 0, 1) * (np.abs(g - b) < 90)
    hard = ndimage.binary_opening(c > 0.5, iterations=2)
    hard = ndimage.binary_fill_holes(ndimage.binary_closing(hard, iterations=2))
    lab, n = ndimage.label(hard)
    if n:
        sizes = ndimage.sum(hard, lab, range(1, n + 1))
        hard = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 0.0015 * hard.size])
    soft = np.maximum(hard.astype(float), np.where(ndimage.binary_dilation(hard, iterations=3), c, 0))
    alpha = 1 - soft
    rgb = a.copy()
    edge = (alpha > 0.02) & (alpha < 0.999) | (ndimage.binary_dilation(hard, iterations=4) & ~hard)
    spill = edge & (g > r + 30) & (b > r + 30)
    for ch in (1, 2):
        rgb[..., ch] = np.where(spill, r + (rgb[..., ch] - r) * 0.3, rgb[..., ch])
    Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)).save(f'widget/widget_{iid}.png')
    Image.fromarray((hard * 255).astype(np.uint8)).save(f'widget/widget_{iid}_glass.png')
    print(iid, 'glass', round(float(hard.mean()), 3))

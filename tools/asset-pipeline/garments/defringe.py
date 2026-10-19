"""Garments painted over ginger cats keep a sliver of ginger fur along their edges (round the outline and round a
tail or paw in front): within BAND px of the garment's edge, ginger pixels are made clear so the cat's own fur shows.
A hairless cat has no fur to leave behind: for HAIRLESS bodies the warm light is only recoloured, nothing cleared.
python defringe.py <garment> [body ...]  (in place on work/layers/<garment>/; keeps the first cut in work/backup/<garment>_fringe/)"""
import glob, os, shutil, sys
import numpy as np
from PIL import Image
from scipy import ndimage
WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'work')
BAND = 10
HAIRLESS = ('sphynx',)

g, bodies = sys.argv[1], sys.argv[2:]
os.makedirs(f'{WORK}/backup/{g}_fringe', exist_ok=True)
for path in sorted(glob.glob(f'{WORK}/layers/{g}/*.png')):
    if bodies and not any(f'_{b}_' in os.path.basename(path) for b in bodies):
        continue
    keep = f'{WORK}/backup/{g}_fringe/{os.path.basename(path)}'
    if not os.path.exists(keep):
        shutil.copyfile(path, keep)
    im = np.asarray(Image.open(keep).convert('RGBA')).astype(np.float32)
    rgb, a = im[..., :3] / 255, im[..., 3] / 255
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    r, gg, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1e-3)
    hue = np.where(mx == r, ((gg - b) / d) % 6, np.where(mx == gg, (b - r) / d + 2, (r - gg) / d + 4)) * 60
    hue_warm = ((hue > 10) & (hue < 50)).astype(np.float32) * (mx > 0.25)
    # Ginger fur itself (as saturated as the tint): cleared where it borders the garment's edge.
    fur = hue_warm * np.clip((sat - 0.45) / 0.1, 0, 1)
    band = ndimage.distance_transform_edt(a > 0.5) <= BAND
    clear = fur * band * (0 if any(f'_{h}_' in os.path.basename(path) for h in HAIRLESS) else 1)
    clear = np.maximum(clear, ndimage.grey_dilation(clear, size=3) * band * np.clip((sat - 0.35) / 0.1, 0, 1))
    # Warm light thrown on the garment by the ginger cat: the garment's own colour at the same brightness.
    warm = hue_warm * np.clip((sat - 0.25) / 0.15, 0, 1) * (1 - clear)
    lum = 0.299 * r + 0.587 * gg + 0.114 * b
    own = (a > 0.9) & (warm < 0.05)
    if own.sum() > 100:
        base = np.median(rgb[own], axis=0)
        base_lum = max(1e-3, float(0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2]))
        tinted = np.clip(lum[..., None] * (base / base_lum)[None, None, :], 0, 1)
        rgb = rgb * (1 - warm[..., None]) + tinted * warm[..., None]
    im[..., :3] = rgb * 255
    im[..., 3] = a * (1 - clear) * 255
    Image.fromarray(np.clip(im, 0, 255).astype(np.uint8)).save(path)
    print(os.path.basename(path), f'{float((clear > 0.5).sum() / max(1, (a > 0.5).sum())):.3f}')

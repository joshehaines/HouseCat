"""The painted cut faces ("caps") where the cat's cut-out parts were separated: a flat mauve ellipse at the
tail's root and at the torso's rump. Overlapping parts would show them as a disc at the joint, so the app art
build (tools/app-assets/build_app_art.py) erases the tail's and paints fur over the torso's. The masters keep
theirs. Other joints are covered by the part in front (the head over the neck, the torso over the legs)."""
import numpy as np
from PIL import Image
from scipy import ndimage

TAILS = ("tail_up", "tail_curl", "tail_low")


def cap_mask(img, points, reach=0.1, grow=6):
    """True on a cut face near any of `points` (fractions of the image)."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3]
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    disc = (mx >= 110) & (mx <= 208) & (sat >= 0.07) & (sat <= 0.36) & (r >= g) & (b >= g - 6) & (al > 8)
    # cut faces are flat fills; fur, even in shadow, is textured
    lum = rgb @ np.array([0.3, 0.55, 0.15], np.float32)
    mean = ndimage.uniform_filter(lum, 7)
    disc &= ndimage.uniform_filter(lum * lum, 7) - mean * mean < 40
    disc = ndimage.binary_opening(disc, iterations=1)
    lab, _ = ndimage.label(disc)
    h, w = al.shape
    yy, xx = np.mgrid[0:h, 0:w]
    out = np.zeros_like(disc)
    rad = reach * max(h, w)
    # a cut face ends the part: it runs along the silhouette's edge
    rim = (al > 8) & ndimage.binary_dilation(al <= 8, iterations=12)
    for px, py in points:
        near = (xx - px * w) ** 2 + (yy - py * h) ** 2 <= rad ** 2
        for i in np.unique(lab[near & disc]):
            if i == 0:
                continue
            comp = lab == i
            ys, xs = np.nonzero(comp)
            small = np.ptp(ys) < 0.4 * h and np.ptp(xs) < 0.4 * w
            if comp.sum() >= 0.002 * h * w and small and (comp & rim).sum() / comp.sum() >= 0.05:
                out |= comp
    out = ndimage.binary_fill_holes(ndimage.binary_closing(out, iterations=2))
    return ndimage.binary_dilation(out, iterations=grow)


def erase(img, points, reach=0.07, grow=6):
    """The cut face made transparent (the tail's root, which lies in front of the torso)."""
    m = cap_mask(img, points, reach, grow)
    a = np.asarray(img.convert("RGBA")).copy()
    a[..., 3] = np.where(m, 0, a[..., 3])
    return Image.fromarray(a)


def fill(img, points, reach=0.1, grow=6):
    """The cut face painted over with the fur beside it, copied from further into the part, keeping the outline
    (the torso's rump: wider than the tail, so erasing it would leave a hole)."""
    m = cap_mask(img, points, reach, grow)
    a = np.asarray(img.convert("RGBA")).copy()
    if not m.any():
        return Image.fromarray(a)
    ys, xs = np.nonzero(m)
    ay, ax = np.nonzero(a[..., 3] > 128)
    dy, dx = ay.mean() - ys.mean(), ax.mean() - xs.mean()
    n = max(np.hypot(dy, dx), 1e-3)
    dy, dx = dy / n, dx / n
    span = max(np.ptp(ys) * abs(dy) + np.ptp(xs) * abs(dx), 4) + 6
    sy = np.clip(np.round(ys + dy * span).astype(int), 0, a.shape[0] - 1)
    sx = np.clip(np.round(xs + dx * span).astype(int), 0, a.shape[1] - 1)
    a[ys, xs, :3] = a[sy, sx, :3]
    return Image.fromarray(a)


def joints(view_rig, name):
    """The cut-face points on a part, from the rig view (assets/cat/rig.json)."""
    parts = view_rig["parts"]
    if "tail_up" not in parts:
        return []
    if name in TAILS:
        return [tuple(parts["tail_up"]["pivot"])]
    if name == "torso":
        return [tuple(parts["tail_up"]["at"])]
    return []


def clean(img, view_rig, name):
    """A part ready for the app: its cut faces erased or furred over."""
    pts = joints(view_rig, name)
    if not pts:
        return img
    return fill(img, pts) if name == "torso" else erase(img, pts)

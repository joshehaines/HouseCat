"""Ear + bobtail pose sheets without another generation: the ear variant and the bobtail variant are both aligned edits
of the same white pose sheet, the first changing only the ears and the second only the tail. Take the ear variant and
paste in the bobtail variant wherever the bobtail edit changed the cat (the tail region), feathered.
  python3 combos.py   -> gen/cust/w_pose_<body>__<ears>_bobtail.png  (+ ../combos_check.jpg)"""
import numpy as np
from PIL import Image
from scipy import ndimage
from custcut import matte, grey_matte, align, lum

STD = ['short_slim', 'short_chunky', 'long_slim', 'long_chunky']
EARS = ['rounded', 'folded', 'tufted', 'oriental']


def load(n):
    return np.asarray(Image.open(f'gen/cust/{n}.png').convert('RGB')).astype(np.float32)


def shift_to(base, img):
    _, ab = grey_matte_arr(base); _, ai = grey_matte_arr(img)
    dy, dx = align(lum(base), lum(img), ndimage.binary_dilation(ab > 0.5, iterations=6))
    if abs(dy) <= 8 and abs(dx) <= 8: img = np.roll(img, (dy, dx), axis=(0, 1))
    return img, (dy, dx)


def grey_matte_arr(rgb):
    l = rgb.mean(2); sat = rgb.max(2) - rgb.min(2)
    bg = (l > 95) & (l < 190) & (sat < 14)
    return rgb, (~bg).astype(np.float32)


def changed(base, img, thr=0.10):
    """Where img differs from base by more than painterly noise: big blobs only."""
    d = np.abs(ndimage.gaussian_filter(lum(img), 3) - ndimage.gaussian_filter(lum(base), 3))
    _, ab = grey_matte_arr(base); _, ai = grey_matte_arr(img)
    sil = ndimage.gaussian_filter(np.abs(ab - ai), 2) > 0.3
    m = (d > thr) | sil
    m = ndimage.binary_opening(m, iterations=2)
    lab, n = ndimage.label(m)
    if n:
        sz = ndimage.sum(m, lab, range(1, n + 1))
        m = np.isin(lab, [i + 1 for i in range(n) if sz[i] > 400])
    return m


def main():
    tiles = []
    for b in STD:
        base = load(f'w_pose_{b}')
        bob, sb = shift_to(base, load(f'w_pose_{b}__bobtail'))
        T = changed(base, bob)
        Tz = ndimage.binary_dilation(T, iterations=25)
        for e in EARS:
            ear, se = shift_to(base, load(f'w_pose_{b}__{e}'))
            # the ear edit's own changes, minus anything that is really a repainted tail (mostly inside the tail zone)
            Ec = changed(base, ear); lab, n = ndimage.label(Ec); E = np.zeros_like(Ec)
            for i in range(1, n + 1):
                c = lab == i
                if (c & Tz).sum() < 0.3 * c.sum(): E |= c
            E = ndimage.binary_dilation(E, iterations=8)
            # everywhere near the tail where the ear sheet and the bobtail sheet disagree takes the bobtail sheet
            D2 = changed(ear, bob) & Tz
            R = ndimage.binary_dilation(T | D2, iterations=10) & ~E
            w = ndimage.gaussian_filter(R.astype(np.float32), 4)[..., None]
            out = ear * (1 - w) + bob * w
            res = float(np.abs(lum(out) - lum(bob))[Tz & ~E].mean())
            Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(f'gen/cust/w_pose_{b}__{e}_bobtail.png')
            t = Image.fromarray(out.clip(0, 255).astype(np.uint8)); t.thumbnail((900, 520)); tiles.append(t)
            print(b, e, 'shift', sb, se, 'tail px', int(T.sum()), 'ear px', int(E.sum()), 'residual near tail', round(res, 4))
    S = Image.new('RGB', (1800, 520 * 8))
    for k, t in enumerate(tiles): S.paste(t, ((k % 2) * 900, (k // 2) * 520))
    S.save('../combos_check.jpg', quality=80)


if __name__ == '__main__':
    main()

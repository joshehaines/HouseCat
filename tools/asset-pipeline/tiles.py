"""Make wallpaper and floor paintings tile seamlessly.
Cross-fades each tile with a copy of itself shifted by half, only in a band along the edges, so the
centre keeps the painting untouched and the edges wrap. python3 tiles.py wall|floor"""
import sys, os
import numpy as np
from PIL import Image

def seam_error(a):
    lr = np.abs(a[:, 0].astype(float) - a[:, -1].astype(float)).mean()
    tb = np.abs(a[0].astype(float) - a[-1].astype(float)).mean()
    inner = np.abs(a[:, 1:].astype(float) - a[:, :-1].astype(float)).mean()
    return (lr + tb) / 2, inner

def make_seamless(img, band=0.14):
    a = np.asarray(img.convert('RGB')).astype(float)
    h, w = a.shape[:2]
    # pick the shift near half that best lines the pattern up with itself (stripes, tiles, checks)
    small = np.asarray(img.convert('L').resize((w // 4, h // 4))).astype(float)
    def best(axis, n):
        cands = range(int(n * 0.35), int(n * 0.65))
        errs = [np.abs(small - np.roll(small, s, axis=axis)).mean() for s in cands]
        return list(cands)[int(np.argmin(errs))] * 4
    sy, sx = best(0, h // 4), best(1, w // 4)
    shifted = np.roll(np.roll(a, sy, axis=0), sx, axis=1)
    def ramp(n):
        x = np.arange(n) / (n - 1)
        d = np.minimum(x, 1 - x)                # 0 at the edges, 0.5 in the middle
        t = np.clip(d / band, 0, 1)
        return t * t * (3 - 2 * t)              # smoothstep
    wy, wx = ramp(h)[:, None], ramp(w)[None, :]
    wgt = np.minimum(wy, wx)[..., None]
    out = a * wgt + shifted * (1 - wgt)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))

MIRROR = {'study_navy_pinstripe', 'study_oak_panel', 'kitchen_metro_tiles', 'kitchen_checker', 'kitchen_quarry'}   # structured patterns: mirror-tile instead

def make_mirror(img):
    a = img.convert('RGB').resize((1024, 1024), Image.LANCZOS)
    out = Image.new('RGB', (2048, 2048))
    out.paste(a, (0, 0)); out.paste(a.transpose(Image.FLIP_LEFT_RIGHT), (1024, 0))
    out.paste(a.transpose(Image.FLIP_TOP_BOTTOM), (0, 1024)); out.paste(a.transpose(Image.ROTATE_180), (1024, 1024))
    return out

if __name__ == '__main__':
    kind = sys.argv[1]
    os.makedirs(f'surfaces/{kind}s', exist_ok=True)
    for f in sorted(os.listdir(f'gen/{kind}')):
        im = Image.open(f'gen/{kind}/{f}').convert('RGB')
        im = im.resize((2048, 2048), Image.LANCZOS) if im.size != (2048, 2048) else im
        e, inner = seam_error(np.asarray(im))
        out = make_mirror(im) if f[:-4] in MIRROR else make_seamless(im)
        e2, _ = seam_error(np.asarray(out))
        out.save(f'surfaces/{kind}s/{kind}_{f}')
        # 2x2 preview at small size
        t = out.resize((256, 256), Image.LANCZOS); p = Image.new('RGB', (512, 512))
        for i in range(2):
            for j in range(2): p.paste(t, (i * 256, j * 256))
        os.makedirs('previews', exist_ok=True); p.save(f'previews/{kind}_{f}')
        print(f, 'seam before %.1f after %.1f (pixel step %.1f)' % (e, e2, inner))

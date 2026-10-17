"""Extract a painted item from an in-room generation: diff against the reference room to find it,
crop around it, run a local background remover on the crop, clean the alpha."""
from PIL import Image, ImageFilter
import numpy as np
from scipy import ndimage
from rembg import remove, new_session
import sys, os
_sess = None
def session():
    global _sess
    if _sess is None: _sess = new_session('isnet-general-use')
    return _sess
REF = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ref_room_v2.png')).convert('RGB')

def silhouette_bbox(im):
    a = np.asarray(im.convert('RGB')).astype(int)
    nonwhite = (a.sum(axis=2) < 3*245)
    nonwhite = ndimage.binary_opening(nonwhite, iterations=4)
    ys, xs = np.where(nonwhite)
    return xs.min(), ys.min(), xs.max(), ys.max()

def align_ref(gen, ref, with_transform=False):
    """Resize/translate the reference so its room silhouette matches the generated image's."""
    gx0, gy0, gx1, gy1 = silhouette_bbox(gen); rx0, ry0, rx1, ry1 = silhouette_bbox(ref)
    sx = (gx1 - gx0) / (rx1 - rx0); sy = (gy1 - gy0) / (ry1 - ry0)
    r2 = ref.resize((int(ref.width * sx), int(ref.height * sy)), Image.LANCZOS)
    out = Image.new('RGB', gen.size, (255, 255, 255))
    dx, dy = gx0 - rx0 * sx, gy0 - ry0 * sy
    out.paste(r2, (int(dx), int(dy)))
    if with_transform: return out, (sx, sy, dx, dy)
    return out

# wall-floor base lines in reference-crop coordinates (build_room geometry minus the crop offset)
_B = (1200 - 380, 520 - 100); _RN = (_B[0] + 720, _B[1] + 360); _LN = (_B[0] - 720, _B[1] + 360)
def base_band_mask(size, t, width=30):
    from PIL import ImageDraw
    sx, sy, dx, dy = t
    def P(p): return (p[0] * sx + dx, p[1] * sy + dy)
    m = Image.new('L', size, 0); d = ImageDraw.Draw(m)
    d.line([P(_LN), P(_B), P(_RN)], fill=255, width=width)
    return np.asarray(m) > 0

def find_bbox(gen, ref, thr=40, return_mask=False):
    """Locate the added item: compare a high-passed luminance (lighting-invariant) and the chroma."""
    ref, t = align_ref(gen, ref, with_transform=True)
    g = np.asarray(gen).astype(float); r = np.asarray(ref).astype(float)
    def lum(x): return 0.299*x[:,:,0] + 0.587*x[:,:,1] + 0.114*x[:,:,2]
    def blur(x, s): return np.asarray(Image.fromarray(np.clip(x,0,255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(s))).astype(float)
    gL, rL = lum(g), lum(r)
    hp_g = gL - blur(gL, 25); hp_r = rL - blur(rL, 25)
    d_hp = np.abs(blur(hp_g + 128, 2) - blur(hp_r + 128, 2))
    ga = g[:,:,0] - g[:,:,1]; gb = (g[:,:,0] + g[:,:,1]) / 2 - g[:,:,2]
    ra = r[:,:,0] - r[:,:,1]; rb = (r[:,:,0] + r[:,:,1]) / 2 - r[:,:,2]
    d_ch = np.sqrt((blur(ga + 128, 3) - blur(ra + 128, 3)) ** 2 + (blur(gb + 128, 3) - blur(rb + 128, 3)) ** 2)
    mask = (d_hp > 16) | (d_ch > 20)
    mask &= ~base_band_mask(gen.size, t)          # ignore the wall-floor seam the model likes to redraw
    mask = ndimage.binary_opening(mask, structure=np.ones((9, 9)))
    mask = ndimage.binary_closing(mask, iterations=8)
    lab, n = ndimage.label(mask)
    if n == 0: return None
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    main = lab == (np.argmax(sizes) + 1)
    ys, xs = np.where(main); y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    for i, s in enumerate(sizes, 1):
        if s < 0.05 * sizes.max(): continue
        yy, xx = np.where(lab == i)
        if xx.min() < x1 + 60 and xx.max() > x0 - 60 and yy.min() < y1 + 60 and yy.max() > y0 - 60:
            y0, y1, x0, x1 = min(y0, yy.min()), max(y1, yy.max()), min(x0, xx.min()), max(x1, xx.max())
    bb = (int(x0), int(y0), int(x1), int(y1))
    if return_mask:
        full = ndimage.binary_fill_holes(ndimage.binary_closing(mask, iterations=10))
        # shadow = darker than the reference with the same hue; the item is anything else that differs
        # bulk of the item from edge/texture differences only (the model's smooth repainting of the
        # floor and wall around an item has no edges, so it drops out here)
        # strong core: pixels that plainly differ from the reference (used to score the remover's coverage)
        dL = blur(gL, 2) - blur(rL, 2)
        shadow = (dL < -5) & (d_ch < 14)
        core = ndimage.binary_opening((np.abs(g - r).mean(axis=2) > 40) & ~shadow, structure=np.ones((5, 5)))
        return bb, full, core
    return bb

SKIRT = np.array([224.0, 121.0, 90.0])
def key_skirting(a, frac=0.4, tol=48):
    h = a.shape[0]; y0 = int(h * (1 - frac))
    rgb = a[y0:, :, :3].astype(float)
    d = np.sqrt(((rgb - SKIRT) ** 2).sum(axis=2))
    a[y0:, :, 3] = np.where(d < tol, 0, a[y0:, :, 3])
    return a

def extract(path, out, pad=60, thr=40, strip_skirting=False):
    gen = Image.open(path).convert('RGB')
    res = find_bbox(gen, REF, thr, return_mask=True)
    if res is None: return None
    bb, fullmask, core = res
    x0, y0, x1, y1 = bb
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad); x1 = min(gen.width, x1 + pad); y1 = min(gen.height, y1 + pad)
    crop = gen.crop((x0, y0, x1, y1))
    cut = remove(crop, session=session())
    a = np.array(cut)
    a[:, :, 3] = np.where(a[:, :, 3] < 128, 0, 255).astype(np.uint8)
    # combine: the remover's alpha limited to the difference region, plus every differing pixel that
    # is not a cast shadow (pale items against the pale wall are what the remover misses)
    diffm = fullmask[y0:y1, x0:x1]; cm = core[y0:y1, x0:x1]
    near = ndimage.binary_dilation(diffm, iterations=12)
    alpha = (a[:, :, 3] > 0) & near
    coverage = float((alpha & cm).sum() / max(1, cm.sum()))   # <0.6 means the remover lost part of the item
    a = np.dstack([np.asarray(crop), np.where(alpha, 255, 0).astype(np.uint8)])
    if strip_skirting: a = key_skirting(a)
    # keep only the largest alpha component (+ nearby)
    m = a[:, :, 3] > 0
    lab, n = ndimage.label(m)
    if n > 1:
        sizes = ndimage.sum(m, lab, range(1, n + 1)); keep = np.zeros_like(m)
        for i, s in enumerate(sizes, 1):
            if s > 0.02 * sizes.max(): keep |= (lab == i)
        a[:, :, 3] = np.where(keep, 255, 0).astype(np.uint8)
    # fill small holes (under 1% of the item) left by the remover inside the item
    m = a[:, :, 3] > 0
    filled = ndimage.binary_fill_holes(m)
    holes = filled & ~m
    lab, n = ndimage.label(holes)
    if n:
        sizes = ndimage.sum(holes, lab, range(1, n + 1)); area = m.sum()
        for i, s in enumerate(sizes, 1):
            if s < 0.01 * area: a[:, :, 3][lab == i] = 255
    im = Image.fromarray(a); bbox = im.getbbox()
    if bbox is None: return None
    im = im.crop(bbox); im.save(out)
    return im.size, (x0 + bbox[0], y0 + bbox[1]), round(coverage, 2)  # size, position in the room image, coverage

if __name__ == '__main__':
    for p in sys.argv[1:]:
        print(p, extract(p, p.replace('.png', '_cut.png')))


# ---------------------------------------------------------------------------------------------
# Grey-room pipeline (reference ref_room_grey.png, media d8ab3b05): the room is neutral grey, so
# any coloured or pale pixel is the item; neutral darker pixels are shadow unless the remover
# says they are part of the object (dark trunks, black radios).
REF_GREY = Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ref_room_grey.png')).convert('RGB')

def outline_mask(size, t, width=22):
    """The reference room's outer silhouette (floor front edges, wall tops and outer edges), where a
    slightly shifted redraw shows up as a bright line."""
    from PIL import ImageDraw
    sx, sy, dx, dy = t
    def P(p): return (p[0] * sx + dx, p[1] * sy + dy)
    WH = 5 * 72
    RN, LN = _RN, _LN; F = (_B[0], _B[1] + 720)
    pts = [P((LN[0], LN[1] - WH)), P((_B[0], _B[1] - WH)), P((RN[0], RN[1] - WH)), P(RN), P(F), P(LN)]
    m = Image.new('L', size, 0); d = ImageDraw.Draw(m)
    d.line(pts + [pts[0]], fill=255, width=width)
    d.line([P((_B[0], _B[1] - WH)), P(_B)], fill=255, width=width)     # the corner seam
    return np.asarray(m) > 0

def grey_matte(gen, thr=22):
    r2, t = align_ref(gen, REF_GREY, with_transform=True)
    g = np.asarray(gen).astype(float); r = np.asarray(r2).astype(float)
    def lum(x): return 0.299*x[:,:,0] + 0.587*x[:,:,1] + 0.114*x[:,:,2]
    gL = lum(g)
    sat = g.max(axis=2) - g.min(axis=2)
    raw = np.abs(g - r).mean(axis=2)
    # the room is neutral grey (saturation under 4), so any coloured pixel is the item; neutral pixels
    # count only when near-white (sheets, cream paint); neutral shadows, glows and mid-grey item parts
    # are left to the remover
    m = (sat > 9) | ((gL > 205) & (raw > thr))
    m &= ~(base_band_mask(gen.size, t, width=24) & (raw < 45) & (sat < 10))
    m &= ~(outline_mask(gen.size, t) & (sat < 10))
    m = ndimage.binary_opening(m, structure=np.ones((5, 5)))
    m = ndimage.binary_closing(m, iterations=3)
    filled = ndimage.binary_fill_holes(m); holes = filled & ~m
    hl, hn = ndimage.label(holes)
    if hn:
        hs = ndimage.sum(holes, hl, range(1, hn + 1)); area = m.sum()
        for i, s in enumerate(hs, 1):
            if s < 0.02 * area: m |= (hl == i)
    lab, k = ndimage.label(m)
    if k == 0: return None
    sizes = ndimage.sum(m, lab, range(1, k + 1))
    # main = the largest component that is not a line (fill ratio of its box under 0.12)
    order = np.argsort(sizes)[::-1]; main = None
    for i in order:
        yy, xx = np.where(lab == i + 1)
        fill = sizes[i] / max(1, (yy.max() - yy.min() + 1) * (xx.max() - xx.min() + 1))
        if fill >= 0.12: main = lab == (i + 1); break
    if main is None: return None
    grow = ndimage.binary_dilation(main, iterations=40)
    for i, s in enumerate(sizes, 1):
        if s > 0.01 * sizes.max() and (grow & (lab == i)).any(): main |= (lab == i)
    bg = (sat < 7) & (raw < 25)      # unmistakably the untouched room: never part of the item
    return main, bg

def extract_grey(path, out, pad=60):
    gen = Image.open(path).convert('RGB')
    res = grey_matte(gen)
    if res is None: return None
    m, bg = res
    ys, xs = np.where(m)
    x0, y0, x1, y1 = max(0, xs.min() - pad), max(0, ys.min() - pad), min(gen.width, xs.max() + pad), min(gen.height, ys.max() + pad)
    crop = gen.crop((x0, y0, x1, y1)); mc = m[y0:y1, x0:x1]; bgc = bg[y0:y1, x0:x1]
    cut = np.array(remove(crop, session=session()))
    near = ndimage.binary_dilation(mc, iterations=10)
    alpha = (mc | ((cut[:, :, 3] >= 128) & near)) & ~bgc
    alpha = ndimage.binary_closing(alpha, iterations=2)
    # fill only small holes (under 0.5% of the item): gaps between chair spindles stay see-through
    filled = ndimage.binary_fill_holes(alpha); holes = filled & ~alpha
    hl, hn = ndimage.label(holes)
    if hn:
        hs = ndimage.sum(holes, hl, range(1, hn + 1)); area = alpha.sum()
        for i, s in enumerate(hs, 1):
            if s < 0.005 * area: alpha |= (hl == i)
    lab, k = ndimage.label(alpha)
    if k > 1:
        sizes = ndimage.sum(alpha, lab, range(1, k + 1)); keep = np.zeros_like(alpha)
        for i, s in enumerate(sizes, 1):
            if s > 0.02 * sizes.max(): keep |= (lab == i)
        alpha = keep
    a = np.dstack([np.asarray(crop), np.where(alpha, 255, 0).astype(np.uint8)])
    im = Image.fromarray(a); bbox = im.getbbox()
    if bbox is None: return None
    im = im.crop(bbox); im.save(out)
    return im.size, (x0 + bbox[0], y0 + bbox[1]), round(float(mc.sum()) / max(1, alpha.sum()), 2)

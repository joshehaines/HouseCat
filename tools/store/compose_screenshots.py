"""compose.py <spec.json> <raw dir> <out dir> <device: iphone69|iphone63|ipad13|duoinner|duoouter>"""
import json, sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage
spec, raw, out, device = sys.argv[1:5]
F = os.path.dirname(os.path.abspath(__file__)) + "/fonts/"
SIZES = {"iphone69": (2868, 1320), "iphone63": (2622, 1206), "ipad13": (2064, 2752),
         "duoinner": (2853, 2007), "duoouter": (2034, 1398)}  # iPhone Duo, unfolded and folded
W, H = SIZES[device]
THEMES = {  # background top, bottom, headline, subline
    "paper": ((254, 248, 236), (246, 230, 206), (61, 46, 56), (139, 84, 40)),
    "amber": ((247, 176, 104), (227, 128, 51), (61, 30, 22), (92, 45, 18)),
    "dusk": ((52, 49, 92), (30, 28, 58), (250, 240, 222), (233, 200, 150)),
    "sage": ((232, 238, 214), (206, 219, 182), (52, 60, 40), (96, 86, 44)),
}

def clean_island(img):
    """The simulator draws the Dynamic Island into a landscape screenshot: paint it out from what is round it."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    band = a[:, : int(w * 0.06)]
    m = (band.max(axis=2) < 6)
    lab, n = ndimage.label(m)
    if n == 0:
        return img
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    k = int(np.argmax(sizes)) + 1
    if sizes[k - 1] < 2000:
        return img
    mask = np.zeros((h, w), bool)
    mask[:, : band.shape[1]] = lab == k
    mask = ndimage.binary_dilation(mask, iterations=4)
    _, (iy, ix) = ndimage.distance_transform_edt(mask, return_indices=True)
    fill = ndimage.gaussian_filter(a[iy, ix], sigma=(6, 6, 0))
    a[mask] = fill[mask]
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))

def gradient(top, bottom):
    t = np.linspace(0, 1, H)[:, None, None]
    g = np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t
    return Image.fromarray(np.repeat(g, W, axis=1).astype(np.uint8))

def fit_font(path, text, max_w, start):
    size = start
    while size > 20:
        f = ImageFont.truetype(path, size)
        if f.getlength(text) <= max_w:
            return f
        size -= 4
    return ImageFont.truetype(path, size)

os.makedirs(out, exist_ok=True)
for i, shot in enumerate(json.load(open(spec)), 1):
    top, bottom, ink, sub = THEMES[shot.get("theme", "paper")]
    canvas = gradient(top, bottom)
    src = Image.open(f"{raw}/{shot['raw']}.png").convert("RGB")
    if device.startswith(("iphone", "duo")):
        src = clean_island(src)
    # Caption band, then the screen as large as fits beneath it.
    band = int(H * {"ipad13": 0.135, "duoinner": 0.17, "duoouter": 0.17}.get(device, 0.215))
    margin = int(H * 0.045)
    avail_h, avail_w = H - band - margin, W - 2 * margin
    scale = min(avail_h / src.height, avail_w / src.width)
    sw, sh = int(src.width * scale), int(src.height * scale)
    screen = src.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, band
    if device.startswith("duo"):  # a wider screen than the canvas sits in the middle of the space under the caption
        y += (avail_h - sh) // 2
    r = int(min(sw, sh) * 0.035)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), r, fill=255)
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + int(r * 0.6), x + sw, y + sh + int(r * 0.6)), r, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(r * 0.9))
    canvas.paste(Image.new("RGB", (W, H), (40, 20, 10)), (0, 0), shadow)
    canvas.paste(screen, (x, y), mask)
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle((x, y, x + sw - 1, y + sh - 1), r, outline=(255, 255, 255, 150), width=max(3, r // 10))
    canvas.paste(rim, (0, 0), rim)
    d = ImageDraw.Draw(canvas)
    head = fit_font(F + "young-serif-latin-400-normal.ttf", shot["title"], W * 0.86, int(band * 0.42))
    hb = d.textbbox((0, 0), shot["title"], font=head)
    lines = [(shot["title"], head, ink)]
    if shot.get("sub"):
        subf = fit_font(F + "figtree-latin-600-normal.ttf", shot["sub"], W * 0.8, int(band * 0.19))
        lines.append((shot["sub"], subf, sub))
    heights = [d.textbbox((0, 0), t, font=f)[3] - d.textbbox((0, 0), t, font=f)[1] for t, f, _ in lines]
    gap = int(band * 0.07)
    total = sum(heights) + gap * (len(lines) - 1)
    ty = (band - total) // 2 + int(margin * 0.2)
    for (t, f, c), h in zip(lines, heights):
        bb = d.textbbox((0, 0), t, font=f)
        d.text(((W - (bb[2] - bb[0])) // 2 - bb[0], ty - bb[1]), t, font=f, fill=c)
        ty += h + gap
    name = f"{i:02d}_{shot['raw']}.png"
    canvas.convert("RGB").save(f"{out}/{name}", optimize=True)
    print(name, canvas.size)

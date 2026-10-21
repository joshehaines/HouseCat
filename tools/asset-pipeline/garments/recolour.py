"""Brings a body's garment to the colour the garment is on the other bodies (needs numpy, Pillow, SciPy).
Each body's nine layers were painted by their own edit, and some came out another colour: the Persian's life vest
brown, its Christmas jumper and Hawaiian shirt dark, the long-haired slim cat's jumper and pyjamas washed out, the
Siamese's raincoat orange (the overnight outfit scan, 21 Oct). A garment's colour is the middle (in Lab) of its
opaque pixels over all nine layers; the garment's own is the middle of the eight bodies'. A layer whose colour is
further from it than RECOLOUR (or PATTERNED for a printed garment, whose share of print varies) has its pixels moved
by the difference, each as much as it is near the layer's colour (SPREAD), so the painted light and shade stay and a
life vest's black straps or a jumper's white snowflakes keep theirs. Not the Hawaiian shirt: how much of it is
teal and how much flowers differs by body, so its middle colour does not say its colour (moved, the Persian's went mint);
the Persian's, a darker teal, was repainted instead and only its teal (the middle of its teal pixels) moved to the others'.
python recolour.py                    the colours, and what would change
python recolour.py --preview <out>    a sheet of each change: the layer as it is, as it would be, another body's
python recolour.py --apply            writes the masters into assets/outfits/body/ and the app's HEIC copies (0.4)"""
import glob, os, subprocess, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, HERE)
from extract import lab  # noqa: E402
from requests import BODIES, GARMENTS  # noqa: E402

RECOLOUR, PATTERNED, SPREAD = 12.0, 15.0, 22.0
# A picture further than this is made up differently, not coloured differently (a life vest seen side-on is mostly
# its black straps): left as it is.
MOST = 30.0
PRINTED = {'xmasjumper', 'pyjamas', 'hawaiian', 'skeleton'}
LEFT = {'hawaiian'}
SCALE, QUALITY = 0.4, '82'


def rgb(lab_):
    """Lab (D65) back to sRGB 0-255, clipped to the gamut."""
    L, a, b = lab_[..., 0], lab_[..., 1], lab_[..., 2]
    fy = (L + 16) / 116
    fx, fz = fy + a / 500, fy - b / 200
    def inv(f):
        return np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787)
    xyz = np.stack([inv(fx) * 0.9505, inv(fy), inv(fz) * 1.089], -1)
    m = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    c = np.einsum('...c,rc->...r', xyz, m)
    c = np.where(c > 0.0031308, 1.055 * np.clip(c, 0, None) ** (1 / 2.4) - 0.055, 12.92 * c)
    return np.clip(c * 255, 0, 255)


def moved(image, shift, middle):
    """An RGBA layer with its colours moved by `shift` in Lab, each pixel as much as it is near `middle`."""
    im = np.asarray(image.convert('RGBA')).astype(np.float32)
    l = lab(im[..., :3])
    near = np.exp(-0.5 * (np.linalg.norm(l - middle, axis=-1) / SPREAD) ** 2)[..., None]
    return Image.fromarray(np.dstack([rgb(l + near * shift), im[..., 3]]).astype(np.uint8))


def layers(g, b):
    return sorted(glob.glob(f'{REPO}/assets/outfits/body/outfit_{g}_{b}_*.png'))


def colour(files):
    px = []
    for f in files:
        a = np.asarray(Image.open(f).convert('RGBA').resize((200, 200)))
        px.append(lab(a[..., :3][a[..., 3] > 200].astype(np.float32)))
    return np.median(np.concatenate(px), axis=0)


def main(apply, preview=None):
    rows = []
    for g in GARMENTS:
        if g in LEFT:
            continue
        own = np.median(np.array([colour(layers(g, b)) for b in BODIES]), axis=0)
        limit = PATTERNED if g in PRINTED else RECOLOUR
        # Each picture on its own (one view can come out another colour from the rest of its body's: the Persian's
        # three-quarter life vest stayed brown when the body's middle was moved).
        for b in BODIES:
            changed = []
            for f in layers(g, b):
                mid = colour([f])
                off = float(np.linalg.norm(mid - own))
                if off <= limit or off > MOST:
                    continue
                shift = own - mid
                print(f'{os.path.basename(f)[7:-4]}: {off:.0f} from its colour (L {shift[0]:+.0f}, a {shift[1]:+.0f}, b {shift[2]:+.0f})')
                changed.append((f, moved(Image.open(f), shift, mid)))
            if preview and changed:
                other = [f for f in layers(g, next(o for o in BODIES if o != b))]
                rows.append((f'{g} {b}', [Image.open(f) for f, _ in changed[:5]], [m for _, m in changed[:5]], [Image.open(f) for f in other[:5]]))
            if not apply:
                continue
            for f, m in changed:
                m.save(f)
                w, h = Image.open(f).size
                rel = os.path.relpath(f, f'{REPO}/assets')
                subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', QUALITY, '-z', str(max(1, round(h * SCALE))),
                                str(max(1, round(w * SCALE))), f, '--out', f'{REPO}/App/Art/{rel[:-4]}.heic'], capture_output=True, check=True)

    if preview and rows:
        from PIL import ImageDraw
        cell = 120
        sheet = Image.new('RGB', (cell * 15 + 10, cell * len(rows)), (150, 170, 190))
        draw = ImageDraw.Draw(sheet)
        for r, (name, *sets) in enumerate(rows):
            for s_, images in enumerate(sets):
                for i, im in enumerate(images):
                    im = im.convert('RGBA')
                    im.thumbnail((cell - 6, cell - 6))
                    sheet.paste(im, (s_ * (cell * 5 + 5) + i * cell + 3, r * cell + 3), im)
            draw.text((4, r * cell + 2), name, fill=(0, 0, 0))
        sheet.save(preview, quality=85)


if __name__ == '__main__':
    main('--apply' in sys.argv, sys.argv[sys.argv.index('--preview') + 1] if '--preview' in sys.argv else None)

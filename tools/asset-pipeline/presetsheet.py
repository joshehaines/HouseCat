"""Render every catbuilder.json preset (and a body x coat grid) with the reference coat recipe, for QA and the art book.
  python3 presetsheet.py <out.jpg> [pose]      default pose sit_tqfront"""
import json, sys
from PIL import Image, ImageDraw, ImageFont
from tint import render, load_masks, COLOURS, EYES, NOSES

CB = json.load(open('cat/custom/catbuilder.json'))
ROOT = 'cat/custom'


def look_of(p):
    return {'coat': COLOURS[p['coat']], 'pattern': p['pattern'],
            'pattern_colour': COLOURS[p['pattern_colour']] if p['pattern_colour'] else (0, 0, 0),
            'white': p['white'], 'eye_left': EYES[p['eye_left']], 'eye_right': EYES[p['eye_right']],
            'nose': NOSES[p['nose']]}


def pose_rel(p, pose):
    var = []
    if p.get('ears', 'own') != 'own': var.append(p['ears'])
    if p.get('tail', 'own') != 'own': var.append(p['tail'])
    v = ('__' + '_'.join(var)) if var else ''
    return f"poses/cat_{p['body']}_{pose}{v}.png"


def render_preset(p, pose):
    rel = pose_rel(p, pose)
    base = Image.open(f'{ROOT}/base/{rel}')
    return render(base, look_of(p), load_masks(ROOT, rel, p['pattern'], p['white']))


def font(sz):
    for f in ('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/dejavu/DejaVuSans.ttf'):
        try: return ImageFont.truetype(f, sz)
        except OSError: pass
    return ImageFont.load_default()


def sheet(out, items, cell=300, cols=6, bg=(236, 231, 240)):
    rows = (len(items) + cols - 1) // cols
    S = Image.new('RGB', (cols * cell, rows * (cell + 34)), bg); d = ImageDraw.Draw(S); f = font(17)
    for i, (label, im) in enumerate(items):
        t = im.copy(); t.thumbnail((cell - 20, cell - 20))
        x = (i % cols) * cell + (cell - t.width) // 2; y = (i // cols) * (cell + 34) + (cell - t.height) // 2
        S.paste(t, (x, y), t)
        w = d.textlength(label, font=f)
        d.text(((i % cols) * cell + (cell - w) / 2, (i // cols) * (cell + 34) + cell + 4), label, fill=(60, 50, 70), font=f)
    S.save(out, quality=88)


if __name__ == '__main__':
    pose = sys.argv[2] if len(sys.argv) > 2 else 'sit_tqfront'
    sheet(sys.argv[1], [(p['name'], render_preset(p, pose)) for p in CB['presets']])

"""python3 prevgrid.py out.jpg rel1 rel2 ... : tint previews (each rel with a rotating look) for QA."""
import sys, os
from PIL import Image
from tint import render, load_masks, COLOURS as C, EYES as E, NOSES as N
LOOKS = [dict(coat=C['black'], eye_left=E['blue'], eye_right=E['green'], nose=(30, 200, 30)),
         dict(coat=C['ginger'], eye_left=E['green'], eye_right=E['green'], nose=N['brick']),
         dict(coat=C['blue'], eye_left=E['copper'], eye_right=E['copper'], nose=(30, 200, 30)),
         dict(coat=C['cream'], eye_left=E['blue'], eye_right=E['blue'], nose=N['pink'])]
def main(out, rels, pattern=None, white=None, pc=(70, 50, 38), cell=360):
    tiles = []
    for k, rel in enumerate(rels):
        look = dict(LOOKS[k % 4]); look['pattern_colour'] = pc
        base = Image.open('cat/custom/base/' + rel)
        im = render(base, look, load_masks('cat/custom', rel, pattern, white))
        t = Image.new('RGBA', base.size, (226, 222, 232, 255)); t.alpha_composite(im)
        t = t.convert('RGB'); t.thumbnail((cell, cell)); tiles.append(t)
    cols = min(len(tiles), 6); rows = (len(tiles) + cols - 1) // cols
    g = Image.new('RGB', (cols * cell, rows * cell), 'white')
    for i, t in enumerate(tiles): g.paste(t, ((i % cols) * cell, (i // cols) * cell))
    g.save(out, quality=85)
if __name__ == '__main__':
    args = sys.argv[2:]; pat = wh = None
    if args and args[0].startswith('--pattern='): pat = args.pop(0).split('=')[1]
    if args and args[0].startswith('--white='): wh = args.pop(0).split('=')[1]
    main(sys.argv[1], args, pat, wh)

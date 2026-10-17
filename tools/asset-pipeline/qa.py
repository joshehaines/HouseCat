"""QA for the cut: features-mask coverage report + random tinted samples.
  python3 qa.py report        -> sprites that should have eyes/nose but don't
  python3 qa.py sample N out.jpg [seed] [filter]"""
import sys, os, glob, random
import numpy as np
from PIL import Image
import presetsheet as PS
from tint import render, load_masks, COLOURS, EYES, NOSES

C = 'cat/custom'
PATS = ['tabby_mackerel', 'tabby_classic', 'spotted', 'tortie', 'colourpoint', None]
WH = ['white_mitts', 'white_tuxedo', 'white_bicolour', 'white_van', None, None]


def report():
    bad = []
    for f in sorted(glob.glob(f'{C}/base/poses/*.png') + glob.glob(f'{C}/base/expr/*.png') +
                    glob.glob(f'{C}/base/parts/*_head.png') + glob.glob(f'{C}/base/whole/*.png')):
        rel = os.path.relpath(f, f'{C}/base')
        if 'sit_back' in rel or 'tqback' in rel: continue
        want = 2 if ('_front' in rel or '_tqfront' in rel) else 1
        p = f'{C}/masks/features/{rel}'
        if not os.path.exists(p): bad.append((rel, 'no features')); continue
        m = np.asarray(Image.open(p))
        eyes = int((m[..., 0] > 50).any()) + int((m[..., 1] > 50).any()); nose = int((m[..., 2] > 50).sum())
        closed = any(k in rel for k in ('sleep_curl', 'slowblink', 'content', 'sleepy'))
        if (not closed and eyes < want) or nose == 0: bad.append((rel, f'eyes {eyes}/{want} nose {nose}'))
    for b in bad: print(*b)
    print(len(bad), 'flagged')


def sample(n, out, seed=1, flt=''):
    random.seed(seed)
    fs = [f for f in glob.glob(f'{C}/base/**/*.png', recursive=True) if flt in f]
    items = []
    for f in random.sample(fs, min(n, len(fs))):
        rel = os.path.relpath(f, f'{C}/base')
        pat = random.choice(PATS); wh = random.choice(WH)
        coat, pc = random.choice([('ginger', 'red'), ('silver', 'black'), ('cream', 'seal'), ('blue', 'smoke'),
                                  ('black', 'ginger'), ('fawn', 'chocolate')])
        e1 = random.choice(list(EYES)); e2 = e1 if random.random() < 0.7 else random.choice(list(EYES))
        look = {'coat': COLOURS[coat], 'pattern_colour': COLOURS[pc], 'eye_left': EYES[e1], 'eye_right': EYES[e2],
                'nose': NOSES[random.choice(list(NOSES))]}
        im = render(Image.open(f), look, load_masks(C, rel, pat, wh))
        items.append((f"{os.path.basename(rel)[:-4][-26:]}|{(pat or '-')[:7]}|{(wh or '-')[6:]}", im))
    PS.sheet(out, items, cell=280, cols=6)


if __name__ == '__main__':
    if sys.argv[1] == 'report': report()
    else: sample(int(sys.argv[2]), sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 1,
                 sys.argv[5] if len(sys.argv) > 5 else '')

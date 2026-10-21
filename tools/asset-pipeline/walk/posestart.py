"""Start passes for a film that begins from one of the cat's resting paintings rather than the puppet (21 Oct: walking
away, seen from behind at three-quarters, starts from the cat sitting with its back to you, `sit_back`, since there is
no puppet from behind). The painting and each of its masks are framed as renderThePuppetsMovement frames the puppet's
white start frames (1920 x 1080, the standing cat RENDER_HEIGHT tall, feet a seventh up, centred), so filmwalk.py can
carry the masks through the film: `white` on chroma green, `part-.` (the painting's coverage), `ids` (the body's shade
everywhere: the painting has no parts), every pattern and white mask, `features`, and an empty points file. No ears,
tail or head mask (so swapped ears and a bobtail keep to the side view walk) and no torso map (so a body garment does).

    uv run --with pillow python -I tools/asset-pipeline/walk/posestart.py <body> <pose> <view whose scale> <out view> <gait> [breed scale]
    e.g. ... posestart.py short_slim sit_back tqfront tqback walk
writes assets/cat/films/start/<body>/<out view>_<gait>_<pass>_004.png (004: what film.sh expects of a walk).
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..')
CUSTOM = os.path.join(ROOT, 'App', 'Art', 'cat', 'custom')
RENDER_HEIGHT = 780
FRAME = (1920, 1080)
GREEN = (0, 176, 64)
MASKS = ['whiskers', 'tabby_classic', 'tabby_mackerel', 'spotted', 'tortie', 'colourpoint', 'white_bicolour',
         'white_mitts', 'white_tuxedo', 'white_van']
TORSO_SHADE = 40


def main():
    body, pose, scale_view, out_view, gait = sys.argv[1:6]
    breed = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0
    frame_no = {'walk': '004', 'run': '005'}.get(gait, '000')
    rig = json.load(open(os.path.join(ROOT, 'App', 'Art', 'cat', 'rig.json')))
    whole = rig['sets'][body][scale_view]['whole']
    index = json.load(open(os.path.join(CUSTOM, 'index.json')))['files']
    rel = f'poses/cat_{body}_{pose}.png'
    entry = index[rel]
    master = entry['master']
    height = RENDER_HEIGHT * breed
    scale = height / whole[1]
    size = (max(1, round(master[0] * scale)), max(1, round(master[1] * scale)))
    feet_y = FRAME[1] - round(RENDER_HEIGHT / 7)
    at = (FRAME[0] // 2 - size[0] // 2, feet_y - size[1])
    base = Image.open(os.path.join(CUSTOM, 'base', rel + '.jpg')).convert('RGB').resize(size, Image.LANCZOS)
    alpha = Image.open(os.path.join(CUSTOM, 'alpha', rel)).convert('L').resize(size, Image.LANCZOS)
    out = os.path.join(ROOT, 'assets', 'cat', 'films', 'start', body)
    os.makedirs(out, exist_ok=True)
    prefix = os.path.join(out, f'{out_view}_{gait}')

    def save(name, image):
        image.save(f'{prefix}_{name}_{frame_no}.png')

    white = Image.new('RGB', FRAME, GREEN)
    white.paste(base, at, alpha)
    save('white', white)
    coverage = Image.new('L', FRAME, 0)
    coverage.paste(alpha, at)
    save('part-.', coverage)
    ids = Image.new('L', FRAME, 0)
    ids.paste(Image.new('L', size, TORSO_SHADE), at, alpha)
    save('ids', ids)
    features = Image.new('RGB', FRAME, (0, 0, 0))
    if 'features' in entry['masks']:
        f = Image.open(os.path.join(CUSTOM, 'masks', 'features', rel)).convert('RGB').resize(size, Image.LANCZOS)
        features.paste(f, at, alpha)
    save('features', features)
    for mask in MASKS:
        if mask not in entry['masks']:
            continue
        m = Image.open(os.path.join(CUSTOM, 'masks', mask, rel)).convert('L').resize(size, Image.LANCZOS)
        canvas = Image.new('L', FRAME, 0)
        canvas.paste(m, at, alpha)
        save(mask, canvas)
    json.dump({}, open(f'{prefix}_points_{frame_no}.json', 'w'))
    print(f'{body} {pose} as {out_view} {gait}: {size[0]}x{size[1]} at {at}, masks {[m for m in MASKS if m in entry["masks"]]}')


if __name__ == '__main__':
    main()

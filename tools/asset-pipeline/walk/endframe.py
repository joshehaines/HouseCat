"""A resting pose's white painting on chroma green, framed as the puppet's start frames are (renderThePuppetsMovement:
1920 x 1080, the standing cat RENDER_HEIGHT tall, its feet a seventh of that up from the bottom, centred), for a
Kling film that starts from the standing cat and must end exactly on the painting (the sit-down films).

    uv run --with pillow python tools/asset-pipeline/walk/endframe.py <body> <pose> <view> <out.png> [breed scale]

<pose> is the painting's name (sit_side, sit_tqfront, loaf_side ...); <view> the puppet view whose scale it shares
(side, tqfront, front: CatNode.wholeScale, the rig's `whole` height).
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..')
RENDER_HEIGHT = 780
FRAME = (1920, 1080)
GREEN = (0, 176, 64)


def main():
    body, pose, view, out = sys.argv[1:5]
    breed = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
    rig = json.load(open(os.path.join(ROOT, 'App', 'Art', 'cat', 'rig.json')))
    whole = rig['sets'][body][view]['whole']
    height = RENDER_HEIGHT * breed
    scale = height / whole[1]
    painting = Image.open(os.path.join(ROOT, 'assets', 'cat', 'custom', 'base', 'poses', f'cat_{body}_{pose}.png')).convert('RGBA')
    size = (max(1, round(painting.width * scale)), max(1, round(painting.height * scale)))
    painting = painting.resize(size, Image.LANCZOS)
    frame = Image.new('RGBA', FRAME, GREEN + (255,))
    # The render puts the cat's feet a seventh of the unscaled height up, whatever the breed's scale.
    feet_y = FRAME[1] - round(RENDER_HEIGHT / 7)
    frame.alpha_composite(painting, (FRAME[0] // 2 - size[0] // 2, feet_y - size[1]))
    frame.convert('RGB').save(out)
    print(f'{out}: {pose} {size[0]}x{size[1]}, feet at y={feet_y}')


if __name__ == '__main__':
    main()

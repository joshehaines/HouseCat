"""Prototype the living room the way the app builds it (HouseCatGame RoomScene), to set furniture scale and
anchors by eye: tiles projected onto the walls and floor, multiplied by a light map, a window and a door,
then furniture from Content/catalogue.json at grid cells, anchored by the bottom-centre of its footprint.
python3 living_room.py <out.png> [light] [native|fit]      (needs Pillow and numpy)"""
import json, os, sys
import numpy as np
from PIL import Image
from build_room import affine_place, tile, B, R, L, N, WALL_H, UNIT, W, H

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
A = os.path.join(ROOT, 'assets')
CAT = {i['id']: i for i in json.load(open(os.path.join(ROOT, 'Content', 'catalogue.json')))['items']}
MANIFEST = json.load(open(os.path.join(A, 'manifest.json')))['files']
LIGHT = sys.argv[2] if len(sys.argv) > 2 else 'midday'
MODE = sys.argv[3] if len(sys.argv) > 3 else 'native'

# The living room's furniture was painted in a cream reference room at a larger scale than the grey one.
LAYOUT = json.load(open(os.path.join(ROOT, 'assets', 'rooms', 'layout_living_demo.json')))


def P(u, v):
    return (B[0] + R[0] * u + L[0] * v, B[1] + R[1] * u + L[1] * v)


def lit(plane, lm_png):
    lm = np.asarray(Image.open(lm_png).convert('RGB').resize(plane.size, Image.BICUBIC)).astype(float) / 255 * 1.5
    a = np.asarray(plane.convert('RGBA')).astype(float)
    a[..., :3] = np.clip(a[..., :3] * lm, 0, 255)
    return Image.fromarray(a.astype(np.uint8))


def furniture_sprite(iid, facing):
    item = CAT[iid]
    path = os.path.join(A, item['sprites'][facing])
    im = Image.open(path).convert('RGBA')
    w, d = item['footprint']['w'], item['footprint']['d']
    if facing == 'L':
        w, d = d, w
    k = item.get('suggestedScale') or 1.0
    if MODE == 'fit':
        # width of the footprint's diamond on screen, a touch wider for overhang
        span = (w + d) * R[0] * LAYOUT['fitOverhang']
        s = span / im.width * (LAYOUT['scale'].get(iid, 1.0))
    else:
        ref = MANIFEST[item['sprites'][facing]].get('ref_room') or 'grey'
        s = LAYOUT['refScale'][ref] * k * LAYOUT['scale'].get(iid, 1.0)
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS), w, d


def build(out):
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    wall = Image.open(os.path.join(A, 'rooms/walls', LAYOUT['wall'] + '.png'))
    floor = Image.open(os.path.join(A, 'rooms/floors', LAYOUT['floor'] + '.png'))
    lm = lambda part: os.path.join(A, 'rooms/lightmaps', f'lm_{LIGHT}_{part}.png')
    tex = 256
    top = (B[0], B[1] - WALL_H * UNIT)
    plane = tile(wall, N // 2, (WALL_H + 1) // 2, tex * 2).crop((0, 0, N * tex, WALL_H * tex))
    affine_place(canvas, lit(plane, lm('right')), top, (R[0] * N, R[1] * N), (0, WALL_H * UNIT))
    affine_place(canvas, lit(plane, lm('left')), top, (L[0] * N, L[1] * N), (0, WALL_H * UNIT))
    affine_place(canvas, lit(tile(floor, N // 2, N // 2, tex * 2), lm('floor')), B, (R[0] * N, R[1] * N), (L[0] * N, L[1] * N))

    def wall_item(img, along, height, start, up, which):
        vec = R if which == 'R' else L
        o = (B[0] + vec[0] * start, B[1] + vec[1] * start - round(UNIT * up) - round(height * UNIT))
        affine_place(canvas, img, o, (vec[0] * along, vec[1] * along), (0, round(height * UNIT)))

    win = LAYOUT['window']
    w_img = Image.open(os.path.join(A, 'rooms/windows', win['id'] + '.png')).convert('RGBA')
    w_open = Image.open(os.path.join(A, 'rooms/windows', win['id'] + '_opening.png')).convert('L').resize(w_img.size)
    sky = Image.new('RGBA', w_img.size, (150, 200, 240, 255))
    sky.putalpha(w_open)
    wall_item(sky, win['along'], win['height'], win['start'], win['up'], win['wall'])
    wall_item(w_img, win['along'], win['height'], win['start'], win['up'], win['wall'])
    door = LAYOUT['door']
    d_img = Image.open(os.path.join(A, 'rooms/doors', door['id'] + '.png')).convert('RGBA')
    d_open = Image.open(os.path.join(A, 'rooms/doors', door['id'] + '_opening.png')).convert('L').resize(d_img.size)
    beyond = Image.new('RGBA', d_img.size, (120, 104, 130, 255))
    beyond.putalpha(d_open)
    wall_item(beyond, door['along'], door['height'], door['start'], 0, door['wall'])
    wall_item(d_img, door['along'], door['height'], door['start'], 0, door['wall'])

    placed = []
    for p in LAYOUT['items']:
        iid, u, v, facing = p['id'], p['u'], p['v'], p['facing']
        im, w, d = furniture_sprite(iid, facing)
        item = CAT[iid]
        if item['layer'] == 'wall':
            # hung on a wall: bottom-centre at a height above the floor
            vec = R if facing == 'R' else L
            along = u if facing == 'R' else v
            x, y = B[0] + vec[0] * (along + w / 2), B[1] + vec[1] * (along + w / 2) - p.get('up', 2.5) * UNIT
            placed.append((-1e6 + y, im, (round(x - im.width / 2), round(y - im.height))))
            continue
        cx = P(u + w / 2, v + d / 2)[0]
        by = P(u + w, v + d)[1]
        dx, dy = p.get('dx', 0), p.get('dy', 0)
        key = -1e7 if item['decal'] else by
        placed.append((key, im, (round(cx - im.width / 2 + dx), round(by - im.height + dy))))
    cat = Image.open(os.path.join(A, 'cat/poses/plain/cat_short_slim_sit_tqfront.png')).convert('RGBA')
    ch = LAYOUT['catHeight']
    cat = cat.resize((round(cat.width * ch / cat.height), ch), Image.LANCZOS)
    cx, cy = P(*LAYOUT['cat'])
    placed.append((cy, cat, (round(cx - cat.width / 2), round(cy - ch))))
    for _, im, xy in sorted(placed, key=lambda t: t[0]):
        canvas.alpha_composite(im, xy)
    bg = Image.new('RGBA', canvas.size, (236, 232, 240, 255))
    bg.alpha_composite(canvas)
    bg = bg.crop(canvas.getbbox())
    bg.convert('RGB').save(out)
    print(out, bg.size)


if __name__ == '__main__':
    build(sys.argv[1])

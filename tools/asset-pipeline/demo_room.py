"""Composite check: a furnished bedroom built only from the delivered assets, the way the app will build it.
python3 demo_room.py [light]   -> previews/demo_bedroom_<light>.png"""
import json, sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
from build_room import affine_place, tile, lit, B, R, L, N, WALL_H, UNIT, W, H

LIGHT = sys.argv[1] if len(sys.argv) > 1 else 'midday'
WALL = sys.argv[2] if len(sys.argv) > 2 else 'oat_linen'
FLOOR = sys.argv[3] if len(sys.argv) > 3 else 'pale_oak'
OFF = (380, 100)                                  # reference-room coords -> canvas coords
POS = json.load(open('demo_pos_bedroom.json'))
S = 1.435                                         # generation px per reference px

def P(u, v):                                       # floor point in canvas px
    return (B[0] + R[0] * u + L[0] * v, B[1] + R[1] * u + L[1] * v)

def sprite(room, item):
    im = Image.open(f'sprites/{room}/furn_{room}_{item}.png').convert('RGBA')
    return im.resize((round(im.width / S), round(im.height / S)), Image.LANCZOS)

from scales import SUGGESTED_SCALE
def place_known(item, du=0.0, dv=0.0):
    p = POS[item]; im = sprite('bedroom', item)
    k = SUGGESTED_SCALE['bedroom'].get(item.rsplit('_', 1)[0], 1.0)
    x = p['x'] + OFF[0] + R[0] * du + L[0] * dv; y = p['y'] + OFF[1] + R[1] * du + L[1] * dv
    if k != 1.0:                                   # scale about the item's bottom centre
        bx, by = x + im.width / 2, y + im.height
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        x, y = bx - im.width / 2, by - im.height
    return (y + im.height, im, (round(x), round(y)))

def place_at(room, item, u, v, h=None):
    im = sprite(room, item)
    k = SUGGESTED_SCALE.get(room, {}).get(item.rsplit('_', 1)[0], 1.0)
    if k != 1.0: im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    if h: im = im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
    x, y = P(u, v)
    return (y, im, (round(x - im.width / 2), round(y - im.height)))

def shadow_for(canvas, u0, u1, v0, v1, a=90):
    sh = Image.new('RGBA', (1000, 1000), (0, 0, 0, 0)); d = ImageDraw.Draw(sh)
    d.rectangle([u0 * 100, v0 * 100, u1 * 100, v1 * 100], fill=(40, 30, 80, a))
    sh = sh.filter(ImageFilter.GaussianBlur(30))
    affine_place(canvas, sh, B, (R[0] * N, R[1] * N), (L[0] * N, L[1] * N))

def build():
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    wall = Image.open(f'surfaces/walls/wall_bedroom_{WALL}.png').convert('RGB')
    wall2 = Image.open('surfaces/walls/wall_living_sage_panel.png').convert('RGB') if False else Image.open('surfaces/walls/wall_bedroom_lavender_stripe.png').convert('RGB')
    floor = Image.open(f'surfaces/floors/floor_bedroom_{FLOOR}.png').convert('RGB')
    tex = 256; top = (B[0], B[1] - WALL_H * UNIT)
    rw = lit(tile(wall, N // 2, (WALL_H + 1) // 2, tex * 2).crop((0, 0, N * tex, WALL_H * tex)), f'lm_{LIGHT}_right.npy')
    lw = lit(tile(wall, N // 2, (WALL_H + 1) // 2, tex * 2).crop((0, 0, N * tex, WALL_H * tex)), f'lm_{LIGHT}_left.npy')
    fl = lit(tile(floor, N // 2, N // 2, tex * 2), f'lm_{LIGHT}_floor.npy')

    # window on the right wall, the exterior scene behind it
    win = Image.open('surfaces/windows/window_sash.png').convert('RGBA')
    wop = Image.open('surfaces/windows/window_sash_opening.png').convert('L')
    win_w = 2.4; win_h = win_w * UNIT * win.height / win.width / UNIT * 0.62
    terr = Image.open('world/terrain/terr_coast_summer.png').convert('RGBA')
    view = Image.new('RGBA', win.size, (120, 180, 235, 255))
    g = np.linspace(0, 1, win.height)[:, None]
    sky = (np.array([95, 160, 230]) * (1 - g[..., None]) + np.array([200, 225, 245]) * g[..., None]).astype(np.uint8)
    view = Image.fromarray(np.broadcast_to(sky, (win.height, win.width, 3)).copy()).convert('RGBA')
    t = terr.resize((win.width * 2, round(terr.height * win.width * 2 / terr.width)))
    t = t.crop((win.width // 2, t.height - round(win.height * 0.9), win.width // 2 + win.width, t.height))
    view.alpha_composite(t, (0, win.height - t.height))
    view.putalpha(wop.resize(win.size))
    # door on the left wall, the next room behind it
    door = Image.open('surfaces/doors/door_panelled_cream.png').convert('RGBA')
    dop = Image.open('surfaces/doors/door_panelled_cream_opening.png').convert('L')
    nxt = Image.new('RGBA', door.size)
    nw = tile(wall2, 1, 2, door.width).resize((door.width, round(door.height * 0.8)))
    nf = tile(floor, 1, 1, door.width).resize((door.width, door.height - nw.height))
    nxt.paste(nw, (0, 0)); nxt.paste(nf, (0, nw.height))
    nxt = Image.blend(nxt, Image.new('RGBA', door.size, (70, 60, 110, 255)), 0.28)
    nxt.putalpha(dop.resize(door.size))

    def wall_item(img, along, height, start, up, wall):
        vec = R if wall == 'R' else L
        o = (B[0] + vec[0] * start, B[1] + vec[1] * start - round(UNIT * up) - round(height * UNIT))
        affine_place(canvas, img, o, (vec[0] * along, vec[1] * along), (0, round(height * UNIT)))

    canvas_parts = [(rw, 'R'), (lw, 'L')]
    affine_place(canvas, rw, top, (R[0] * N, R[1] * N), (0, WALL_H * UNIT))
    affine_place(canvas, lw, top, (L[0] * N, L[1] * N), (0, WALL_H * UNIT))
    wall_item(view, win_w, 2.6, 6.9, 1.2, 'R'); wall_item(win, win_w, 2.6, 6.9, 1.2, 'R')
    wall_item(nxt, 1.5, 3.5, 0.7, 0, 'L'); wall_item(door, 1.5, 3.5, 0.7, 0, 'L')
    affine_place(canvas, fl, B, (R[0] * N, R[1] * N), (L[0] * N, L[1] * N))

    # soft contact shadows under the big pieces (the app draws these too)
    shadow_for(canvas, 1.0, 5.2, 0.0, 4.4)      # bed
    shadow_for(canvas, 0.0, 1.2, 2.6, 5.6)      # wardrobe
    shadow_for(canvas, 0.0, 1.2, 6.3, 9.3)      # drawers
    shadow_for(canvas, 7.3, 8.5, 0.3, 1.5, a=70)  # cat bed

    items = [
        place_known('bedrug_R'),
        place_known('bed_R'),
        place_known('wardrobe_L'),
        place_known('drawers_L', dv=3.0),
        place_at('bedroom', 'catbed_R', 8.35, 1.45),   # under the window, in the sun, against the wall
        place_known('slippers_R', dv=0.2, du=2.6),
        place_known('curtains_R', du=2.3),
        place_at('bedroom', 'bedside_R', 5.8, 0.55),
        place_at('bedroom', 'laundry_R', 8.6, 4.4),
    ]
    # the cat: about half the sofa's height
    cat = Image.open('cat/cat_short_slim_tqfront_whole.png').convert('RGBA')
    ch = 150; cat = cat.resize((round(cat.width * ch / cat.height), ch), Image.LANCZOS)
    cx, cy = P(5.6, 7.6); items.append((cy, cat, (round(cx - cat.width / 2), round(cy - ch))))
    flat = items[0]                              # the rug is a floor decal: always drawn first
    canvas.alpha_composite(flat[1], flat[2])
    for _, im, xy in sorted(items[1:], key=lambda t: t[0]):
        canvas.alpha_composite(im, xy)
    bb = canvas.getbbox(); out = canvas.crop(bb)
    bg = Image.new('RGBA', out.size, (238, 236, 244, 255)); bg.alpha_composite(out)
    bg.convert('RGB').save(f'previews/demo_bedroom_{LIGHT}_{WALL}.png'); print(bg.size)

if __name__ == '__main__':
    build()

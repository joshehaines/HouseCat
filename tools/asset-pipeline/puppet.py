"""Check the cat puppet rig by eye: assemble the cut-out parts from assets/cat/rig.json and draw them
beside the painted standing reference, plus a strip of walk-cycle frames.
python3 puppet.py <set> <view> <out.png> [walk]    (needs Pillow; run from anywhere)

The rig is the same data the app reads (HouseCatGame CatNode): for each part, its pivot (where it joins
its parent, as a fraction of its own image), the point on the parent it joins at (a fraction of the
parent's image), a draw order and a rest angle. The app animates the angles in code."""
import json, math, os, sys
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RIG = json.load(open(os.path.join(ROOT, 'assets', 'cat', 'rig.json')))


def part_image(body, view, name):
    return Image.open(os.path.join(ROOT, 'assets', 'cat', 'base', body, f'cat_{body}_{view}_{name}.png')).convert('RGBA')


def assemble(body, view, angles=None, offsets=None):
    """Returns (canvas, origin) with every part placed; angles/offsets override per part (degrees / px)."""
    rig = RIG['sets'][body][view]
    parts = rig['parts']
    angles = angles or {}
    offsets = offsets or {}
    imgs = {n: part_image(body, view, n) for n in parts}
    world = {}   # name -> (pivot_x, pivot_y, total_angle) in canvas space

    def place(name):
        if name in world:
            return world[name]
        p = parts[name]
        img = imgs[name]
        ang = p.get('angle', 0) + angles.get(name, 0)
        if p.get('parent'):
            px, py, pang = place(p['parent'])
            parent = parts[p['parent']]
            pimg = imgs[p['parent']]
            # the joint point on the parent, relative to the parent's pivot, rotated with the parent
            jx = (p['at'][0] - parent['pivot'][0]) * pimg.width
            jy = (p['at'][1] - parent['pivot'][1]) * pimg.height
            r = math.radians(pang)
            wx = px + jx * math.cos(r) - jy * math.sin(r)
            wy = py + jx * math.sin(r) + jy * math.cos(r)
            ang += pang
        else:
            wx, wy = 0.0, 0.0
        dx, dy = offsets.get(name, (0, 0))
        world[name] = (wx + dx, wy + dy, ang)
        return world[name]

    for n in parts:
        place(n)
    canvas = Image.new('RGBA', (3000, 3000), (0, 0, 0, 0))
    cx, cy = 1500, 1500
    for n in sorted(parts, key=lambda n: parts[n]['z']):
        img = imgs[n]
        px, py, ang = world[n]
        pv = parts[n]['pivot']
        # rotate the part about its pivot: expand onto a square big enough, pivot at its centre
        side = int(2 * math.hypot(img.width, img.height)) + 4
        holder = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        hx, hy = side // 2 - pv[0] * img.width, side // 2 - pv[1] * img.height
        holder.alpha_composite(img, (int(round(hx)), int(round(hy))))
        rot = holder.rotate(-ang, resample=Image.BICUBIC, center=(side // 2, side // 2))
        canvas.alpha_composite(rot, (int(round(cx + px - side // 2)), int(round(cy + py - side // 2))))
    return canvas.crop(canvas.getbbox())


def walk_angles(rig, t):
    """The same walk cycle as CatNode.walk: legs swing in pairs, the body bobs, the tail sways."""
    w = rig.get('walk', {})
    swing = w.get('legSwing', 22)
    s = math.sin(2 * math.pi * t)
    return {
        'leg_front_near': swing * s, 'leg_back_far': swing * s,
        'leg_front_far': -swing * s, 'leg_back_near': -swing * s,
        'tail_up': w.get('tailSway', 6) * math.sin(2 * math.pi * t + 1.2),
        'head': w.get('headBob', 2) * math.sin(4 * math.pi * t),
    }


if __name__ == '__main__':
    body, view, out = sys.argv[1], sys.argv[2], sys.argv[3]
    walk = len(sys.argv) > 4 and sys.argv[4] == 'walk'
    rig = RIG['sets'][body][view]
    frames = [assemble(body, view)]
    if walk:
        frames += [assemble(body, view, walk_angles(rig, i / 6)) for i in range(6)]
    whole = Image.open(os.path.join(ROOT, 'assets', 'cat', 'base', body, f'cat_{body}_{view}_whole.png')).convert('RGBA')
    h = 420
    tiles = [whole] + frames
    tiles = [t.resize((max(1, round(t.width * h / t.height)), h)) for t in tiles]
    sheet = Image.new('RGBA', (sum(t.width + 30 for t in tiles), h + 20), (238, 234, 226, 255))
    x = 0
    for t in tiles:
        sheet.alpha_composite(t, (x, 10))
        x += t.width + 30
    d = ImageDraw.Draw(sheet)
    d.text((6, 4), 'reference', fill=(90, 80, 100, 255))
    sheet.convert('RGB').save(out)
    print(out, sheet.size)

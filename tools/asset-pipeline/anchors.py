"""Find where animated effects attach on furniture sprites (sprite pixel coords). -> fx/anchors.json"""
import json, glob, os
import numpy as np
from PIL import Image
from scipy import ndimage
D = 'deliver/assets/furniture'
out = {}
def flame_box(path, small=False):
    a = np.asarray(Image.open(path).convert('RGBA')).astype(float)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    if small:   # candle / oil-lamp flame: the brightest yellow-white blob
        m = (r > 238) & (g > 205) & (b > 60) & (r - b > 25) & (al > 200)
    else:
        m = (r > 200) & (g > 110) & (b < 110) & (r - b > 120) & (al > 200)
    m = ndimage.binary_opening(m, iterations=1)
    lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=3))
    if not n: return None
    sizes = ndimage.sum(m, lab, range(1, n + 1)); k = int(np.argmax(sizes)) + 1
    ys, xs = np.where((lab == k) & m)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())
def top_center(path):
    im = Image.open(path); bb = im.getbbox(); return (bb[0] + bb[2]) // 2, bb[1]
FLAME = {'living': ['fireplace'], 'housewarming_pack': ['grandfireplace'], 'pass_housewarming': ['candle'], 'attic': ['oillamp']}
STEAM = {'kitchen': ['kettle'], 'pass_midwinter': ['mulledwine']}
WATER = {'kitchen': ['fountain'], 'garden': ['pond']}
for room, items in FLAME.items():
    for it in items:
        for side in 'RL':
            p = f'{D}/{room}/furn_{room}_{it}_{side}.png'
            if not os.path.exists(p): continue
            bx = flame_box(p, small=it in ('candle', 'oillamp'))
            if bx:
                x0, y0, x1, y1 = bx
                out[f'furniture/{room}/furn_{room}_{it}_{side}.png'] = {'fx': 'fire' if 'fire' in it else 'candle', 'anchor': [(x0 + x1) // 2, y1],
                    'fx_width_px': min(x1 - x0, 55) if it in ('candle', 'oillamp') else x1 - x0, 'note': ('bottom-centre of the painted flame; draw fx/candle frames about 0.6 x fx_width_px wide, additive blend, ~10 fps' if it in ('candle', 'oillamp') else 'bottom-centre of the painted flame; draw fx/fire frames about 1.3 x fx_width_px wide, additive blend, ~10 fps')}
for kind, table in (('steam', STEAM), ('water', WATER)):
    for room, items in table.items():
        for it in items:
            for side in 'RL':
                p = f'{D}/{room}/furn_{room}_{it}_{side}.png'
                if not os.path.exists(p): continue
                x, y = top_center(p)
                out[f'furniture/{room}/furn_{room}_{it}_{side}.png'] = {'fx': kind, 'anchor': [x, y] if kind == 'steam' else None,
                    'note': 'steam: top-centre of the sprite, nudge to the spout by eye' if kind == 'steam' else 'water: ripple/trickle placed by eye on the water surface'}
json.dump(out, open('fx/anchors.json', 'w'), indent=1)
for k, v in out.items(): print(k, v['fx'], v['anchor'], v.get('fx_width_px'))

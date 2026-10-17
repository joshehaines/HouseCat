"""Repair furniture cut-outs whose matte ate part of the object (white or cream pieces against the reference room).
  python3 repair.py prep            -> repair/in/<name>.png (sprite on flat magenta, padded to a model aspect) + repair/meta.json
  python3 repair.py cut <name>      -> keys repair/out/<name>.png back to RGBA, aligns it to the old sprite, writes the
                                       sprite and updates pipeline_state.json (pos/size) so placement is unchanged
The edit itself runs in Higgsfield (gpt_image_2_5) with the prompts in PROMPTS."""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

KEEP = ("Keep everything else exactly the same: the same object, angle, size and position in the frame, the same colours, "
        "lighting and painterly brushwork. Flat, plain pure magenta (#FF00FF) background, no shadow, no floor, no text.")
ITEMS = {
 'study/furn_study_printer_R': "This is a cut-out of a cream home printer whose edges were damaged when it was cut out: the right-hand end "
                               "and the bottom edge are ragged and partly missing, and there is a grey scrap behind it. Repair it into one "
                               "clean, whole printer with smooth complete edges and the paper tray intact; remove the grey scrap.",
 'study/furn_study_printer_L': "This is a cut-out of a cream home printer whose edges were damaged when it was cut out: the bottom-left "
                               "corner and lower edge are ragged and partly missing, and there is a grey scrap behind it. Repair it into "
                               "one clean, whole printer with smooth complete edges; remove the grey scrap.",
 'kitchen/furn_kitchen_catflap_R': "This is a cut-out of a white cat flap set in a wall, seen at an angle. The flap itself has a ragged hole "
                                   "where it was cut out by mistake. Repair it: the flap is one whole piece of smoky, tinted dark-grey "
                                   "translucent plastic filling the frame, with a soft highlight, so nothing behind it shows through.",
 'kitchen/furn_kitchen_catflap_L': "This is a cut-out of a white cat flap set in a wall, seen at an angle. The flap is missing or see-through. "
                                   "Repair it: the flap is one whole piece of smoky, tinted dark-grey translucent plastic filling the frame, "
                                   "with a soft highlight, so nothing behind it shows through.",
 'bedroom/furn_bedroom_bedside_R': "This is a cut-out of a pale wooden bedside table with a lamp. The front-left leg is broken into "
                                   "pieces with gaps, and the left edge of the lampshade is clipped. Repair it: the front-left leg is "
                                   "one complete straight leg reaching the floor like the others, and the lampshade is whole.",
 'living/furn_living_windowseat_R': "This is a cut-out of a long window seat: a cream panelled wooden base with a mustard cushion and two "
                                    "cushions. A band of the cream base under the seat cushion is missing, so the base looks torn. Repair "
                                    "it: the cream panelled base is complete and solid along its whole length, from under the cushion to "
                                    "the floor, with its panels and plinth.",
 'living/furn_living_windowseat_L': "This is a cut-out of a long window seat: a cream panelled wooden base with a mustard cushion and two "
                                    "cushions. At the left-hand end the base is cut away, leaving a gap under the cushion. Repair it: the "
                                    "cream panelled base is complete and solid along its whole length, including the left-hand end.",
 'living/furn_living_box_R': "This is a cut-out of an open cardboard box. The flaps have ragged holes torn in them where the cut-out "
                             "went wrong. Repair it: every flap is whole, solid cardboard with clean edges; the inside of the box is "
                             "shaded cardboard, not holes.",
 'living/furn_living_box_L': "This is a cut-out of an open cardboard box. The back flap has a ragged notch and the inside has a small "
                             "hole where the cut-out went wrong. Repair it: every flap is whole, solid cardboard with clean edges.",
 'living/furn_living_fireplace_R': "This is a cut-out of a cream fireplace with a lit fire. The tiled hearth in front of it is broken: most "
                                   "of it is missing, leaving only its outline. Repair it: a complete, solid hearth of small green and "
                                   "cream tiles lies flat on the floor in front of the fireplace, the full width of the surround, as in "
                                   "a real Victorian fireplace.",
}
FIT = {'furn_kitchen_catflap_R': True, 'furn_kitchen_catflap_L': True}
ASPECTS = {'1:1': 1.0, '4:3': 4 / 3, '3:4': 3 / 4, '3:2': 1.5, '2:3': 2 / 3, '16:9': 16 / 9, '9:16': 9 / 16}
MAG = (255, 0, 255)


def src_path(key):
    p = f'sprites/{key}.png'          # the grey-room re-dos win over the legacy living-room cut-outs (as in deliver.py)
    return p if os.path.exists(p) else f"living/sprites/{key.split('/')[-1]}.png"


def prep():
    os.makedirs('repair/in', exist_ok=True); meta = {}
    for key, desc in ITEMS.items():
        im = Image.open(src_path(key)).convert('RGBA'); w, h = im.size
        m = int(0.14 * max(w, h)) + 8
        cw, ch = w + 2 * m, h + 2 * m
        ar = min(ASPECTS, key=lambda k: abs(np.log(ASPECTS[k] / (cw / ch))))
        r = ASPECTS[ar]
        if cw / ch < r: cw = int(round(ch * r))
        else: ch = int(round(cw / r))
        ox, oy = (cw - w) // 2, (ch - h) // 2
        can = Image.new('RGBA', (cw, ch), MAG + (255,)); can.alpha_composite(im, (ox, oy))
        name = key.split('/')[-1]
        can.convert('RGB').save(f'repair/in/{name}.png')
        meta[name] = {'key': key, 'canvas': [cw, ch], 'origin': [ox, oy], 'size': [w, h], 'aspect': ar,
                      'prompt': desc + " " + KEEP}
    json.dump(meta, open('repair/meta.json', 'w'), indent=1)
    for n, v in meta.items(): print(n, v['canvas'], v['aspect'])


def key_magenta(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    magness = np.minimum(r, b) - g                        # high on magenta, low on everything painted
    bgcore = (magness > 120) & (r > 170) & (b > 170)
    lab, n = ndimage.label(bgcore)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    a = 1 - np.clip((magness - 40) / 80, 0, 1)            # soft edge from how magenta a pixel is
    a = np.where(bg, 0, np.where(ndimage.binary_dilation(bg, iterations=3), a, 1.0))
    # despill: pull the magenta cast out of edge pixels
    edge = (a < 1) & (a > 0)
    rgb = rgb.copy()
    sp = edge[..., None] & (rgb[..., [0]] > rgb[..., [1]]) & (rgb[..., [2]] > rgb[..., [1]])
    neutral = rgb[..., 1:2]
    rgb = np.where(sp, neutral + (rgb - neutral) * 0.35, rgb)
    return rgb, a


def cut(name):
    meta = json.load(open('repair/meta.json'))[name]
    cw, ch = meta['canvas']; ox, oy = meta['origin']; w, h = meta['size']
    out = Image.open(f'repair/out/{name}.png').convert('RGB').resize((cw, ch), Image.LANCZOS)
    rgb = np.asarray(out).astype(np.float32)
    rgb, a = key_magenta(rgb)
    # keep the main object (drop specks)
    lab, n = ndimage.label(a > 0.5)
    if n > 1:
        sz = ndimage.sum(a > 0.5, lab, range(1, n + 1)); keep = np.isin(lab, [i + 1 for i in range(n) if sz[i] > 0.02 * sz.max()])
        a = np.where(ndimage.binary_dilation(keep, iterations=2), a, 0)
    # align to the old sprite (phase correlation of the masks)
    old = np.zeros((ch, cw), np.float32)
    old_a = np.asarray(Image.open(src_path(meta['key'])).convert('RGBA'))[..., 3] / 255.0
    old[oy:oy + h, ox:ox + w] = old_a
    # the model sometimes redraws the object larger: scale it back so its box matches the old sprite's
    # (only when the old outline is trustworthy, i.e. the damage was inside the object, not at its edge)
    if FIT.get(name):
        ys, xs = np.nonzero(a > 0.5); oys, oxs = np.nonzero(old > 0.5)
        nb = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1); ob = (oxs.min(), oys.min(), oxs.max() + 1, oys.max() + 1)
        s = ((ob[2] - ob[0]) / (nb[2] - nb[0]) + (ob[3] - ob[1]) / (nb[3] - nb[1])) / 2
        rgba = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8)).crop(nb)
        rgba = rgba.resize((max(1, round(rgba.width * s)), max(1, round(rgba.height * s))), Image.LANCZOS)
        can = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
        cx = (ob[0] + ob[2]) // 2 - rgba.width // 2; by = ob[3] - rgba.height     # bottom-centre on the old box
        can.paste(rgba, (cx, by))
        arr = np.asarray(can).astype(np.float32); rgb, a = arr[..., :3], arr[..., 3] / 255.0
        print(name, 'rescaled by', round(s, 3))
    F = np.fft.fft2(old) * np.conj(np.fft.fft2(a))
    rr = np.fft.ifft2(F / (np.abs(F) + 1e-9)).real
    dy, dx = np.unravel_index(np.argmax(rr), rr.shape)
    if dy > ch // 2: dy -= ch
    if dx > cw // 2: dx -= cw
    if abs(dy) > 25 or abs(dx) > 25: dy = dx = 0
    a = np.roll(a, (dy, dx), (0, 1)); rgb = np.roll(rgb, (dy, dx), (0, 1))
    # decontaminate soft edges from the nearest solid pixel
    solid = a >= 0.95
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    wgt = np.clip((a - 0.5) / 0.45, 0, 1)[..., None]
    rgb = rgb * wgt + rgb[iy, ix] * (1 - wgt)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8))
    bb = img.getbbox(); img = img.crop(bb)
    iou = float(((a > 0.5) & (old > 0.5)).sum() / max(((a > 0.5) | (old > 0.5)).sum(), 1))
    off = [bb[0] - ox, bb[1] - oy]
    os.makedirs('repair/backup', exist_ok=True)
    bk = f"repair/backup/{name}.png"
    if not os.path.exists(bk): Image.open(src_path(meta['key'])).save(bk)
    img.save(src_path(meta['key']))
    st = json.load(open('pipeline_state.json')); room = meta['key'].split('/')[0]
    k = f"{room}:{name.split(f'furn_{room}_', 1)[1]}"
    if k in st:
        if st[k].get('pos'): st[k]['pos'] = [st[k]['pos'][0] + off[0], st[k]['pos'][1] + off[1]]
        st[k]['size'] = list(img.size); st[k]['repaired'] = 'edit on magenta, 17 Oct (matte had eaten part of it)'
        json.dump(st, open('pipeline_state.json', 'w'), indent=1)
    print(name, 'shift', (dx, dy), 'iou vs old', round(iou, 3), 'new size', img.size, 'old', (w, h), 'offset', off)


if __name__ == '__main__':
    {'prep': prep, 'cut': lambda: cut(sys.argv[2])}[sys.argv[1]]()

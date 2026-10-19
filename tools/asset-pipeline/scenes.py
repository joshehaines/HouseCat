"""Exterior scenes: every house painted into every terrain and season as one picture (decided 17 Oct:
the isometric façades composited on eye-level terrain never sat on the ground). Raised three-quarter
view, 16:9 since the game went landscape, the house centred in the band the app never crops.
Sky flat magenta (keyed to alpha, the sky is drawn in code), glass flat cyan (keyed to a mask, lit in code).

  python3 scenes.py batch <house|all> [start n]   request JSON for generate_image_batch (and batch_scenes_*.json for run.py-style bookkeeping)
  python3 scenes.py record <batchfile> < jobs.json  store job ids in pipeline_state.json under scene:<house>_<biome>_<season>
  python3 scenes.py key <raw.png> <out_dir> <name>   key a downloaded scene into <name>.jpg, <name>_land.png and <name>_glass.png
  python3 scenes.py doors <raw_dir> <scenes.json>    measure each door from its door-open edit into scenes.json
  python3 scenes.py houses <scene_dir> <scenes.json> measure where each house stands into scenes.json (needs numpy, scipy)
"""
import json
import os
import sys

from world import BIOMES, HOUSES, PAINT, SEASON, STYLE_E

STATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pipeline_state.json')
SEASONS = list(SEASON)

SCENE_T = ("Refs: 1 = {house}, the house; 2 = its setting, {biome}, {season}; 3 = palette and brushwork. Paint one game "
           "exterior: this exact house standing in this setting, raised three-quarter view from the front-left (from an upstairs "
           "window across the street, about 25 degrees down): its front and side, a little roof, doorstep, path and the ground in "
           "front; the setting spreads to either side and behind, horizon in the upper fifth. {weather}A wide landscape view: "
           "the house exactly centred, inside the middle 40% of the width and 75% of the height, front door visible, the "
           "setting filling both sides. Window and door glass flat pure cyan "
           "#00FFFF. Sky flat pure magenta #FF00FF, no clouds or sun. Noon light from the upper left. Painterly brushwork, "
           "high-key Mediterranean-pastel palette, violet-blue shadows. No people, cat, cars or text.")


# Per-house corrections learned in production (17 Oct): the houseboat drifted onto dry land, and the
# new-build's balcony glass came out as flat key cyan.
NOTES = {
    'houseboat': "The houseboat floats on calm water that suits the setting (a canal, river, lake or sheltered sea edge), moored beside a towpath or jetty, never on dry land. ",
    'newbuild_balcony': "The balcony balustrades are pale frosted green glass, not cyan; only window and door panes are cyan. ",
}


def state():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def request(house, biome, season, st):
    # The reference carries the design; the prompt only names it (up to its first comma).
    desc = dict(HOUSES)[house].split(',')[0]
    house_job = st.get(f'house:{house}_snow' if season == 'winter' else f'house:{house}', {}).get('job_id')
    terrain_job = st[f'terrain:{biome}_{season}']['job_id']
    weather = NOTES.get(house, "") + ("Snow on the roof, sills and ground. " if season == 'winter' else "")
    prompt = SCENE_T.format(house=desc, biome=BIOMES[biome].split(':')[0], season=SEASON[season].split(':')[0], weather=weather)
    medias = [{"role": "image_references", "value": v} for v in (house_job, terrain_job, STYLE_E)]
    return {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "16:9",
            "prompt": prompt, "medias": medias}


def names(house):
    houses = [h for h, _ in HOUSES] if house == 'all' else [house]
    return [(h, b, s) for h in houses for b in BIOMES for s in SEASONS]


def batch(house, start=0, n=12):
    st = state()
    sel = names(house)[start:start + n]
    reqs = [{"index": start + i, "params": request(h, b, s, st)} for i, (h, b, s) in enumerate(sel)]
    out = {"names": [f"scene:{h}_{b}_{s}" for h, b, s in sel], "requests": reqs}
    json.dump(out, open(f'batch_scenes_{house}_{start}.json', 'w'))
    print(json.dumps(reqs))


def record(batchfile, jobs):
    b = json.load(open(batchfile))
    first = b['requests'][0]['index']
    st = state()
    for j in jobs['jobs']:
        name = b['names'][j['index'] - first]
        st[name] = {'job_id': j.get('job_id'), 'status': j['status'], 'ref': 'scene'}
    json.dump(st, open(STATE, 'w'), indent=1)
    print('recorded', len(jobs['jobs']))


# Key distances (sum of channel differences, 0-3): fully keyed under KEY_EDGE - KEY_RAMP, untouched past KEY_EDGE.
KEY_EDGE = 0.55
KEY_RAMP = 0.3


def key(raw, out_dir, name):
    """Key a scene into <name>.jpg (the painting, sky filled with the nearby land colour so no magenta
    bleeds when it is filtered), <name>_land.png (1 = painting, 0 = sky, soft edge) and <name>_glass.png
    (window glass, lit in code). JPEG plus masks is about a sixth of a keyed PNG."""
    import numpy as np
    from PIL import Image, ImageFilter
    from scipy import ndimage
    img = np.asarray(Image.open(raw).convert('RGB')).astype(np.float32) / 255
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    # Closeness to the key colours: solid for anything near them (the painted key is never pure, e.g.
    # 240,5,251), a soft ramp only across the painterly edge.
    def key(distance):
        return np.clip((KEY_EDGE - distance) / KEY_RAMP, 0, 1)

    magenta = key(np.abs(r - 1) + g + np.abs(b - 1))
    cyan = key(r + np.abs(g - 1) + np.abs(b - 1))
    # Only the sky that reaches the top of the picture is sky: magenta specks in water or snow stay painting.
    labels, count = ndimage.label(magenta > 0)
    if count:
        sky_labels = set(np.unique(labels[0])) - {0}
        stray = (labels > 0) & ~np.isin(labels, list(sky_labels))
        magenta = np.where(stray, 0, magenta)
    sky = Image.fromarray((magenta * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1))
    land = 1 - np.asarray(sky).astype(np.float32) / 255
    # Un-blend the magenta from edge pixels, then fill the sky with the land colour pulled outwards.
    safe = np.maximum(land, 1e-3)[..., None]
    rgb = np.clip((img - np.array([1, 0, 1]) * (1 - land)[..., None]) / safe, 0, 1)
    weight = (land > 0.5).astype(np.float32)
    pulled = np.stack([ndimage.gaussian_filter(rgb[..., c] * weight, 24) for c in range(3)], -1)
    pulled /= np.maximum(ndimage.gaussian_filter(weight, 24), 1e-4)[..., None]
    rgb = np.where((land > 0.5)[..., None], rgb, np.clip(pulled, 0, 1))
    glass = Image.fromarray((cyan * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
    gm = np.asarray(glass).astype(np.float32)[..., None] / 255
    rgb = rgb * (1 - gm) + np.array([0.18, 0.2, 0.26]) * gm
    os.makedirs(out_dir, exist_ok=True)
    Image.fromarray((rgb * 255).astype(np.uint8)).save(os.path.join(out_dir, f'{name}.jpg'), quality=92, subsampling=0)
    Image.fromarray((land * 255).astype(np.uint8)).save(os.path.join(out_dir, f'{name}_land.png'), optimize=True)
    glass.save(os.path.join(out_dir, f'{name}_glass.png'), optimize=True)
    return float((land < 0.5).mean()), float((np.asarray(glass) > 128).mean())


def door(closed, opened):
    """The door's centre as a fraction of the painting (x right, y down): the door-open edit repaints the
    same picture, so the strongest coherent difference between the two is the doorway."""
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    size = 512
    a = np.asarray(Image.open(closed).convert('L').resize((size, size))).astype(np.float32)
    b = np.asarray(Image.open(opened).convert('L').resize((size, size))).astype(np.float32)
    diff = ndimage.gaussian_filter(np.abs(a - b), 6)
    y, x = np.unravel_index(np.argmax(diff), diff.shape)
    return round(float(x) / size, 4), round(float(y) / size, 4)


def doors(raw_dir, scenes_json):
    """Measures every scene that has a door-open edit and writes the points into scenes.json."""
    import glob
    index = json.load(open(scenes_json))
    for opened in sorted(glob.glob(os.path.join(raw_dir, '*_dooropen.png'))):
        name = os.path.basename(opened)[:-len('_dooropen.png')]
        closed = os.path.join(raw_dir, name + '.png')
        if os.path.exists(closed):
            index['doors'][name] = list(door(closed, opened))
    json.dump(index, open(scenes_json, 'w'), indent=1, sort_keys=True)
    print(len(index['doors']), 'doors')


# Where the house stands, from its window glass (the key marks the house's own panes, and now and then a turquoise
# sea, too big to be a window) and its door: the front wall a little past the outer windows on the left, the side
# wall seen on the right, the roof and chimney above the top windows, the step and path below the door. Across in
# the windows' width, up and down in their height; checked by eye on contact sheets (19 Oct).
LEFT_WALL, SIDE_WALL, ROOF, GROUND = 0.2, 0.75, 0.8, 0.45
# A pane is no bigger than this share of the picture's width and height, no smaller than this share of its area,
# and fills at least this much of its own box.
PANE_MOST = (0.12, 0.2)
PANE_LEAST = 0.00015
PANE_FILL = 0.55


def house_box(glass_png, door_xy):
    """The house's box as fractions of the picture, [left, top, right, bottom], or None without glass."""
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    glass = np.array(Image.open(glass_png).convert('L')) > 128
    height, width = glass.shape
    labels, count = ndimage.label(glass)
    if count == 0:
        return None
    door_x = door_xy[0] * width if door_xy else width / 2
    door_y = door_xy[1] * height if door_xy else height * 0.62
    # The house's panes: solid, window-shaped and window-sized patches (a sea's glints are ragged or huge), near the
    # door across and from a storey or two above it to the step.
    keep = np.zeros_like(glass)
    areas = ndimage.sum(glass, labels, range(1, count + 1))
    for index, box in enumerate(ndimage.find_objects(labels), start=1):
        w, h = box[1].stop - box[1].start, box[0].stop - box[0].start
        middle_x, middle_y = (box[1].start + box[1].stop) / 2, (box[0].start + box[0].stop) / 2
        pane = (w < width * PANE_MOST[0] and h < height * PANE_MOST[1] and areas[index - 1] > width * height * PANE_LEAST
                and areas[index - 1] / (w * h) > PANE_FILL and 0.2 < w / h < 5)
        near = abs(middle_x - door_x) < width * 0.13 and door_y - height * 0.5 < middle_y < door_y + height * 0.1
        if pane and near:
            keep |= labels == index
    if not keep.any():
        return None
    ys, xs = np.nonzero(keep & glass)
    left, right, top, bottom = xs.min() / width, xs.max() / width, ys.min() / height, ys.max() / height
    if door_xy:
        left, right = min(left, door_xy[0]), max(right, door_xy[0])
        bottom = max(bottom, door_xy[1])
    span = max(bottom - top, 0.08)
    across = right - left
    return [round(max(0.0, left - across * LEFT_WALL), 4), round(max(0.0, top - span * ROOF), 4),
            round(min(1.0, right + across * SIDE_WALL), 4), round(min(1.0, bottom + span * GROUND), 4)]


def houses(scene_dir, scenes_json):
    """Measures where the house stands in every scene with a glass mask and writes the boxes into scenes.json. A door
    measured outside its house (a stray difference in the door-open edit: two Georgian townhouses) is put back where
    that home's door usually is in its box."""
    import glob
    import statistics
    index = json.load(open(scenes_json))
    index['houses'] = {}
    strays = []
    for glass in sorted(glob.glob(os.path.join(scene_dir, '*_glass.png'))):
        name = os.path.basename(glass)[:-len('_glass.png')]
        if name.endswith('_dooropen'):
            continue
        door = index['doors'].get(name)
        box = house_box(glass, door)
        if door and box and not (box[0] - 0.02 <= door[0] <= box[2] + 0.02 and door[1] < 0.9):
            box = house_box(glass, None)
            strays.append(name)
        elif door and box is None:
            box = house_box(glass, None)
            strays.append(name)
        if box:
            index['houses'][name] = box
    # Where each home's door sits in its box, from the scenes whose doors were measured right.
    def home(name):
        return next(h[0] for h in HOUSES if name.startswith(h[0] + '_'))
    usual = {}
    for name, box in index['houses'].items():
        door = index['doors'].get(name)
        if door and name not in strays:
            usual.setdefault(home(name), []).append(((door[0] - box[0]) / (box[2] - box[0]), (door[1] - box[1]) / (box[3] - box[1])))
    for name in strays:
        box = index['houses'].get(name)
        if not box:
            continue
        fx = statistics.median(p[0] for p in usual[home(name)])
        fy = statistics.median(p[1] for p in usual[home(name)])
        index['doors'][name] = [round(box[0] + fx * (box[2] - box[0]), 4), round(box[1] + fy * (box[3] - box[1]), 4)]
        print('door put back:', name, index['doors'][name])
    json.dump(index, open(scenes_json, 'w'), indent=1, sort_keys=True)
    print(len(index['houses']), 'houses')

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'batch':
        batch(sys.argv[2], *(int(a) for a in sys.argv[3:5]))
    elif cmd == 'record':
        record(sys.argv[2], json.load(sys.stdin))
    elif cmd == 'key':
        print(key(sys.argv[2], sys.argv[3], sys.argv[4]))
    elif cmd == 'doors':
        doors(sys.argv[2], sys.argv[3])
    elif cmd == 'houses':
        houses(sys.argv[2], sys.argv[3])

"""Exterior scenes: every house painted into every terrain and season as one picture (decided 17 Oct:
the isometric façades composited on eye-level terrain never sat on the ground). Raised three-quarter
view, square, the house centred in a safe area that survives a phone-portrait and an iPad-landscape crop.
Sky flat magenta (keyed to alpha, the sky is drawn in code), glass flat cyan (keyed to a mask, lit in code).

  python3 scenes.py batch <house|all> [start n]   request JSON for generate_image_batch (and batch_scenes_*.json for run.py-style bookkeeping)
  python3 scenes.py record <batchfile> < jobs.json  store job ids in pipeline_state.json under scene:<house>_<biome>_<season>
  python3 scenes.py key <raw.png> <out_dir> <name>   key a downloaded scene into <name>.jpg, <name>_land.png and <name>_glass.png
  python3 scenes.py doors <raw_dir> <scenes.json>    measure each door from its door-open edit into scenes.json
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
           "front; the setting spreads to either side and behind, horizon in the upper fifth. {weather}House exactly centred, "
           "inside the middle 45% of the width and 70% of the height, front door visible. Window and door glass flat pure cyan "
           "#00FFFF. Sky flat pure magenta #FF00FF, no clouds or sun. Noon light from the upper left. Painterly brushwork, "
           "high-key Mediterranean-pastel palette, violet-blue shadows. No people, cat, cars or text.")


def state():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def request(house, biome, season, st):
    # The reference carries the design; the prompt only names it (up to its first comma).
    desc = dict(HOUSES)[house].split(',')[0]
    house_job = st.get(f'house:{house}_snow' if season == 'winter' else f'house:{house}', {}).get('job_id')
    terrain_job = st[f'terrain:{biome}_{season}']['job_id']
    weather = "Snow on the roof, sills and ground. " if season == 'winter' else ""
    prompt = SCENE_T.format(house=desc, biome=BIOMES[biome].split(':')[0], season=SEASON[season].split(':')[0], weather=weather)
    medias = [{"role": "image_references", "value": v} for v in (house_job, terrain_job, STYLE_E)]
    return {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "1:1",
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


def key(raw, out_dir, name):
    """Key a scene into <name>.jpg (the painting, sky filled with the nearby land colour so no magenta
    bleeds when it is filtered), <name>_land.png (1 = painting, 0 = sky, soft edge) and <name>_glass.png
    (window glass, lit in code). JPEG plus masks is about a sixth of a keyed PNG."""
    import numpy as np
    from PIL import Image, ImageFilter
    from scipy import ndimage
    img = np.asarray(Image.open(raw).convert('RGB')).astype(np.float32) / 255
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    # Closeness to the pure key colours, tolerant of the painterly edge.
    magenta = np.clip(1 - (np.abs(r - 1) + g + np.abs(b - 1)) / 0.9, 0, 1)
    cyan = np.clip(1 - (r + np.abs(g - 1) + np.abs(b - 1)) / 0.9, 0, 1)
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

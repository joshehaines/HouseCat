#!/usr/bin/env python3
"""Builds App/Art: app-sized copies of the masters the game draws, at the same relative paths as in assets/,
plus App/Art/art.json giving each file's master size so the game can apply scales in master pixels.
The masters are never edited. Standard library plus macOS `sips` only.

Run from the repo root: python3 -I tools/app-assets/build_app_art.py
(then tools/app-assets/build_cat_art.py for the cat builder's sprites in App/Art/cat/custom, which this leaves alone)
"""
import glob
import json
import os
import shutil
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ASSETS = os.path.join(ROOT, 'assets')
OUT = os.path.join(ROOT, 'App', 'Art')

# (glob relative to assets/, downscale factor). Milestone 1: the arrival with the mascot in the living room.
SETS = [
    # The puppet: the short slim body in the views the arrival uses (side, three-quarter front, front).
    ('cat/base/short_slim/cat_short_slim_side_*.png', 0.5),
    ('cat/base/short_slim/cat_short_slim_tqfront_*.png', 0.5),
    ('cat/base/short_slim/cat_short_slim_front_*.png', 0.5),
    # The painted resting poses the puppet hands over to.
    ('cat/poses/plain/cat_short_slim_*.png', 0.6),
    # The light maps, a window and a door.
    # Every room's wallpapers and floors: the house view shows the rooms around the one you are in.
    ('rooms/walls/wall_*.png', 0.25),
    ('rooms/floors/floor_*.png', 0.25),
    ('rooms/lightmaps/lm_*.png', 1.0),
    ('rooms/windows/window_sash*.png', 0.4),
    ('rooms/windows/window_casement*.png', 0.4),
    ('rooms/windows/window_arched*.png', 0.4),
    ('rooms/windows/window_dormer*.png', 0.4),
    ('rooms/doors/door_panelled_cream*.png', 0.4),
    ('furniture/living/furn_living_*.png', 0.6),
    ('furniture/kitchen/furn_kitchen_bowl_*.png', 0.6),
    ('fx/fire/fx_fire_0*.png', 0.5),
    ('fx/reactions/fx_reactions_*.png', 0.5),
    # The painted UI icons for the room's controls, the status and the tray.
    ('ui/icon_*.png', 0.4),
    # The gifts the cat brings, for the room and the book.
    ('gifts/gift_*.png', 0.3),
    # The exterior: the demo home's painted scenes in every biome and season (door closed and open), and every
    # terrain seen through the rooms' windows.
    ('world/scenes/london_terrace_*', 0.75),
    ('world/terrain/terr_*.png', 0.25),
    # The painted weather particles (rain, snow, fog, clouds, leaves, blossom).
    ('world/weather/*.png', 0.5),
    # The world map: the painting and the biome mask under the pin.
    ('world/map/map_painted.png', 1.0),
    ('world/map/map_biome.png', 1.0),
]
DATA = ['cat/rig.json', 'rooms/layout_living_demo.json', 'rooms/houses.json', 'fx/anchors.json', 'fx/fx.json', 'world/scenes/scenes.json',
        'world/map/cities.json', 'world/map/map_biome_legend.json']


def size(path):
    out = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', path], capture_output=True, text=True, check=True).stdout
    vals = [int(line.split(':')[1]) for line in out.splitlines() if 'pixel' in line]
    return vals[0], vals[1]


def preview_sets():
    """The furniture shown in closed rooms (assets/rooms/houses.json roomStyles), both facings."""
    styles = json.load(open(os.path.join(ASSETS, 'rooms', 'houses.json'))).get('roomStyles', {})
    ids = sorted({item['id'] for style in styles.values() for item in style.get('preview', [])})
    return [(f'furniture/{i.split("_", 1)[0]}/furn_{i}_*.png', 0.6) for i in ids if not i.startswith('living_')]


def catalogue_sets():
    """Every piece the player can own without paying money (the free and Bean catalogue), both facings: the
    decorate tray's shop lists them for every room."""
    catalogue = json.load(open(os.path.join(ROOT, 'Content', 'catalogue.json')))
    paths = sorted({path for item in catalogue['items'] if item['pool'] in ('free', 'beans') for path in item['sprites'].values()})
    return [(path, 0.6) for path in paths]


def main():
    # Start clean, except the cat builder's sprites (build_cat_art.py, which needs numpy and scipy).
    keep = os.path.join(OUT, 'cat', 'custom')
    for dirpath, dirnames, filenames in os.walk(OUT, topdown=True):
        if dirpath == keep or dirpath.startswith(keep + os.sep):
            dirnames[:] = []
            continue
        for name in filenames:
            os.remove(os.path.join(dirpath, name))
    manifest = json.load(open(os.path.join(ASSETS, 'manifest.json')))['files']
    index = {}
    seen = set()
    for pattern, factor in SETS + preview_sets() + catalogue_sets():
        if pattern in seen:
            continue
        seen.add(pattern)
        # Wildcards skip the furniture's *_painted.png originals; a file named outright is always taken.
        found = sorted(f for f in glob.glob(os.path.join(ASSETS, pattern))
                       if (not f.endswith('_painted.png') or '*' not in pattern) and f.endswith(('.png', '.jpg')))
        assert found, pattern
        files = [f for f in found if os.path.relpath(f, ASSETS) not in index]
        for src in files:
            rel = os.path.relpath(src, ASSETS)
            dst = os.path.join(OUT, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            w, h = size(src)
            if factor < 1.0:
                fmt = 'jpeg' if src.endswith('.jpg') else 'png'
                quality = ['-s', 'formatOptions', '85'] if fmt == 'jpeg' else []
                subprocess.run(['sips', '-s', 'format', fmt, *quality, '-z', str(max(1, round(h * factor))), str(max(1, round(w * factor))),
                                src, '--out', dst], capture_output=True, check=True)
            else:
                shutil.copyfile(src, dst)
            index[rel] = {"master": [w, h], "scale": factor}
            ref = manifest.get(rel, {}).get('ref_room')
            if ref:  # the reference room a piece of furniture was painted in sets its scale
                index[rel]["ref"] = ref
    for rel in DATA:
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(ASSETS, rel), dst)
    with open(os.path.join(OUT, 'art.json'), 'w') as f:
        json.dump({"note": "Generated by tools/app-assets/build_app_art.py; master = the master's size in pixels, scale = this copy's downscale, ref = the reference room furniture was painted in.",
                   "files": index}, f, indent=1, sort_keys=True)
        f.write('\n')
    total = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(OUT) for n in ns)
    print(f'{len(index)} images into App/Art ({total / 1e6:.1f} MB)')


if __name__ == '__main__':
    main()

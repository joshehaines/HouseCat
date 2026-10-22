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
    # The living room's door, painted in 3D at the wall's angle (tools/asset-pipeline/isodoors.py; Josh, 19 Oct: the
    # flat door_panelled_cream laid on the wall looked strange).
    ('rooms/doors/door_iso_*.png', 0.6),
    ('furniture/living/furn_living_*.png', 0.6),
    ('furniture/kitchen/furn_kitchen_bowl_*.png', 0.6),
    ('fx/fire/fx_fire_0*.png', 0.5),
    ('fx/reactions/fx_reactions_*.png', 0.5),
    # The outfits in every view: worn by the cat (fitted to its face) and shown in the shop (three-quarter front).
    ('outfits/outfit_*.png', 0.5),
    # The body garments, painted onto each body's resting poses and torso views (at the cat sprites' scale).
    ('outfits/body/outfit_*.png', 0.4),
    # The painted UI icons for the room's controls, the status and the tray.
    ('ui/icon_*.png', 0.4),
    # The shop's offer illustrations.
    ('ui/shop/shop_*.png', 0.4),
    # The cat creator's dressing room (the cat stands on its podium) and the fur swatch tinted to each coat colour.
    ('ui/creator/creator_room.jpg', 1.0),
    ('ui/creator/creator_fur_swatch.png', 0.25),
    # The corner the cat sits in on its profile (the sunny window by day, the fireside from dusk) and the paper the
    # profile's and the room menu's panels are printed on.
    ('ui/profile/profile_corner_*.jpg', 1.0),
    ('ui/profile/panel_paper.jpg', 0.5),
    # The gifts the cat brings, for the room and the book.
    ('gifts/gift_*.png', 0.3),
    # The exterior: the demo home's painted scenes in every biome and season (door closed and open), and every
    # terrain seen through the rooms' windows.
    ('world/scenes/london_terrace_*', 0.75),
    # The ladder's first house, run down in Puddlebury, for its cold open and the opening cutscene (docs/LADDER.md).
    ('world/scenes/rundown_terrace_*', 0.75),
    # The homes' room (the house ladder's screen, App/Sources/HomesView.swift).
    ('ui/homes/homes_room.jpg', 0.5),
    ('world/terrain/terr_*.png', 0.25),
    # The ground around the house, per biome.
    ('world/ground/ground_*.png', 0.25),
    # The scenery round the house (Content/outdoors.json), painted on magenta and keyed like the shop pictures.
    ('world/props/*.png', 0.3),
    # The painted weather particles (rain, snow, fog, clouds, leaves, blossom).
    ('world/weather/*.png', 0.5),
    # The widget's window frames, square and wide, one pair per home (their glass is transparent; the masks
    # are not needed). The app copies the home's pair into the App Group for the widget.
    ('widget/widget_*[!s].png', 0.32),
    # The intro's logo (the wordmark the cat curls up on, App/Sources/Intro/AnimatedLogo.swift) and its host, the mascot.
    ('brand/logo/wordmark_on_dark.png', 0.75),
    ('brand/icon/AppIcon_layer2_cat.png', 0.5),
    # The world map: the painting and the biome mask under the pin.
    ('world/map/map_painted.png', 1.0),
    ('world/map/map_biome.png', 1.0),
    # The Games menu (CLAUDE.md "The Games menu"): its tiles and icons, and each game's pictures (Zoomies' four
    # parts of the run and its things, Catapult's eight places, pieces and ledges, the match pieces, the board).
    # tools/app-assets/build_arcade_art.py builds just these.
    ('arcade/ui/tile_*.png', 0.35),
    ('arcade/ui/icon_game_*.png', 0.4),
    ('arcade/match/match_*.png', 0.5),
    ('arcade/row/row_board.png', 0.6),
    ('arcade/run/bg_*.jpg', 1.0),
    ('arcade/run/thing_*.png', 0.6),
    ('arcade/pounce/place_*.jpg', 1.0),
    ('arcade/pounce/piece_*.png', 0.6),
    ('arcade/pounce/ledge_*.png', 0.6),
]
# The intro's example homes (see above) and their size.
# The two the intro flies to (Josh, 20 Oct: the London terrace fully decorated in the rain, a beach house in Bali) are
# painted for it alone and kept in world/intro, out of the homes' own sets.
INTRO_SCENES = ['woodland_cabin_snow_winter', 'mediterranean_rooftop_coast_summer', 'houseboat_city_spring',
                'cottage_countryside_spring', 'mansion_flat_desert_summer', 'london_terrace_decorated_city_autumn',
                'beach_house_tropical_summer']
INTRO_SCALE = 0.75
DATA = ['cat/rig.json', 'rooms/layout_living_demo.json', 'rooms/houses.json', 'fx/anchors.json', 'fx/fx.json', 'world/scenes/scenes.json',
        'world/map/cities.json', 'world/map/map_biome_legend.json', 'outfits/body/variants.json', 'outfits/poses.json']


# Opaque pictures are written as HEIC (half the size of JPEG for the same look); the index maps the master's path
# to the file, so the data and the game keep using the masters' names.
HEIC = ('world/scenes/', 'rooms/walls/', 'rooms/floors/', 'world/ground/', 'world/map/map_painted', 'ui/creator/creator_room', 'ui/homes/homes_room',
        'ui/profile/profile_corner', 'arcade/run/bg_', 'arcade/pounce/place_')
HEIC_QUALITY = '70'
# Cut-outs go in as HEIC with their transparency too (four to seven times smaller than PNG; keeps the app's
# download under 200 MB), at a higher quality for clean edges. Not the cat's sprites and masks, the light maps,
# the widget's frames and icons (read pixel for pixel, or copied for the widget).
HEIC_ALPHA = ('world/props/', 'furniture/', 'outfits/', 'world/terrain/', 'ui/shop/', 'arcade/')
HEIC_ALPHA_QUALITY = '82'
# The house step's home pictures (Josh, 20 Oct: "the which home section needs a re-do"): the chosen home is drawn
# large, about 430 points wide on a phone (720 wide looked soft there). 960 adds 6 MB; where the app has the home's full
# summer scene (the London terrace, a home whose pack has arrived) the step draws that instead, sharp on an iPad too.
PREVIEW_WIDTH = 960
# The iPad's sharper copies (Josh, 19 Oct: "The iPad quality seems poor"). A 13-inch iPad draws the room with about
# 1.3 times a phone's pixels at the home zoom (and pinches in to 2.5 times), so furniture from its 0.6 copy was
# magnified 1.3-2.4 times and looked soft. These get a second, larger copy as iPad-only data sets in
# App/Resources/ArtPad.xcassets: App Store thinning leaves them out of an iPhone's download, and ArtLibrary draws
# them on an iPad (art.json `pad`). (prefix of the master's path, the iPad's scale)
PAD = [
    ('furniture/', 1.0),
]
PAD_CATALOG = os.path.join(ROOT, 'App', 'Resources', 'ArtPad.xcassets')


def heic(rel):
    """Whether a file goes in as HEIC: an opaque picture (not a mask), or a cut-out keeping its transparency."""
    if rel.startswith(HEIC_ALPHA):
        return True
    if not rel.startswith(HEIC):
        return False
    return not rel.endswith(('_land.png', '_glass.png'))


def pad_scale(rel, factor):
    """The iPad's scale for a file that has a sharper copy there, else None."""
    for prefix, scale in PAD:
        if rel.startswith(prefix) and scale > factor:
            return scale
    return None


def write_pad(src, rel, w, h, scale, quality):
    """The iPad's copy of a file, a data set in the iPad's catalog; returns its name."""
    name = os.path.splitext(rel)[0].replace('/', '.')
    folder = os.path.join(PAD_CATALOG, name + '.dataset')
    os.makedirs(folder, exist_ok=True)
    file = os.path.basename(os.path.splitext(rel)[0]) + '.heic'
    resize = ['-z', str(max(1, round(h * scale))), str(max(1, round(w * scale)))] if scale < 1.0 else []
    subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', quality, *resize, src, '--out',
                    os.path.join(folder, file)], capture_output=True, check=True)
    with open(os.path.join(folder, 'Contents.json'), 'w') as f:
        json.dump({"data": [{"filename": file, "idiom": "ipad", "universal-type-identifier": "public.heic"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write('\n')
    return name


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
    """Every piece in the catalogue, both facings: the decorate tray's Bean shop lists the free and Bean pieces
    for every room, the shop shows the paid sets and packs, and an owned one is placed like any other."""
    catalogue = json.load(open(os.path.join(ROOT, 'Content', 'catalogue.json')))
    paths = sorted({path for item in catalogue['items'] for path in item['sprites'].values()})
    return [(path, 0.6) for path in paths if os.path.exists(os.path.join(ASSETS, path))]


def main():
    # Start clean, except the cat builder's sprites (build_cat_art.py, which needs numpy and scipy).
    keep = os.path.join(OUT, 'cat', 'custom')
    for dirpath, dirnames, filenames in os.walk(OUT, topdown=True):
        if dirpath == keep or dirpath.startswith(keep + os.sep):
            dirnames[:] = []
            continue
        for name in filenames:
            os.remove(os.path.join(dirpath, name))
    shutil.rmtree(PAD_CATALOG, ignore_errors=True)
    os.makedirs(PAD_CATALOG)
    with open(os.path.join(PAD_CATALOG, 'Contents.json'), 'w') as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write('\n')
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
            entry = {"master": [w, h], "scale": factor}
            if heic(rel):
                file = os.path.splitext(rel)[0] + '.heic'
                dst = os.path.join(OUT, file)
                quality = HEIC_ALPHA_QUALITY if rel.startswith(HEIC_ALPHA) else HEIC_QUALITY
                subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', quality,
                                '-z', str(max(1, round(h * factor))), str(max(1, round(w * factor))), src, '--out', dst],
                               capture_output=True, check=True)
                entry["file"] = file
                pad = pad_scale(rel, factor)
                if pad:
                    entry["pad"] = {"asset": write_pad(src, rel, w, h, pad, quality), "scale": pad}
            elif factor < 1.0:
                fmt = 'jpeg' if src.endswith('.jpg') else 'png'
                quality = ['-s', 'formatOptions', '85'] if fmt == 'jpeg' else []
                subprocess.run(['sips', '-s', 'format', fmt, *quality, '-z', str(max(1, round(h * factor))), str(max(1, round(w * factor))),
                                src, '--out', dst], capture_output=True, check=True)
            else:
                shutil.copyfile(src, dst)
            index[rel] = entry
            ref = manifest.get(rel, {}).get('ref_room')
            if ref:  # the reference room a piece of furniture was painted in sets its scale
                index[rel]["ref"] = ref
    # A small summer picture of every home in every biome, for the house step (the full exteriors of the
    # homes other than the London terrace come as download packs: tools/app-assets/build_home_packs.py).
    scenes = os.path.join(ASSETS, 'world', 'scenes')
    for name in sorted(os.listdir(scenes)):
        if not name.endswith('_summer.jpg') or '_dooropen' in name:
            continue
        rel = 'world/previews/' + name.replace('_summer.jpg', '.jpg')
        file = os.path.splitext(rel)[0] + '.heic'
        os.makedirs(os.path.dirname(os.path.join(OUT, file)), exist_ok=True)
        w, h = size(os.path.join(scenes, name))
        subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', HEIC_QUALITY, '-Z', str(PREVIEW_WIDTH),
                        os.path.join(scenes, name), '--out', os.path.join(OUT, file)], capture_output=True, check=True)
        index[rel] = {"master": [w, h], "scale": PREVIEW_WIDTH / w, "file": file}
        # Its sky mask, so the picker can put a sky behind it.
        land = rel.replace('.jpg', '_land.png')
        subprocess.run(['sips', '-Z', str(PREVIEW_WIDTH), os.path.join(scenes, name.replace('.jpg', '_land.png')), '--out',
                        os.path.join(OUT, land)], capture_output=True, check=True)
        index[land] = {"master": [w, h], "scale": PREVIEW_WIDTH / w}
    # The intro's tour of homes round the world: a few other homes painted in their places, kept apart under intro/
    # so they never stand in for a player's own home; with their sky masks and window glass.
    for name in INTRO_SCENES:
        for suffix, opaque in (('.jpg', True), ('_land.png', False), ('_glass.png', False)):
            src = os.path.join(scenes, name + suffix)
            if not os.path.exists(src):
                src = os.path.join(ASSETS, 'world', 'intro', name + suffix)
            rel = 'intro/scenes/' + name + suffix
            w, h = size(src)
            dst = os.path.join(OUT, os.path.splitext(rel)[0] + ('.heic' if opaque else '.png'))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            fmt = ['-s', 'format', 'heic', '-s', 'formatOptions', HEIC_QUALITY] if opaque else ['-s', 'format', 'png']
            subprocess.run(['sips', *fmt, '-z', str(round(h * INTRO_SCALE)), str(round(w * INTRO_SCALE)), src, '--out', dst],
                           capture_output=True, check=True)
            index[rel] = {"master": [w, h], "scale": INTRO_SCALE}
            if opaque:
                index[rel]["file"] = os.path.relpath(dst, OUT)
    for rel in DATA:
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(ASSETS, rel), dst)
    with open(os.path.join(OUT, 'art.json'), 'w') as f:
        json.dump({"note": "Generated by tools/app-assets/build_app_art.py; master = the master's size in pixels, scale = this copy's downscale, ref = the reference room furniture was painted in, file = the file when it is not at the master's path (HEIC).",
                   "files": index}, f, indent=1, sort_keys=True)
        f.write('\n')
    total = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(OUT) for n in ns)
    print(f'{len(index)} images into App/Art ({total / 1e6:.1f} MB)')
    pads = sum(os.path.getsize(os.path.join(dp, n)) for dp, _, ns in os.walk(PAD_CATALOG) for n in ns if n.endswith('.heic'))
    print(f'{sum(1 for e in index.values() if "pad" in e)} sharper iPad copies into App/Resources/ArtPad.xcassets ({pads / 1e6:.1f} MB)')


if __name__ == '__main__':
    main()

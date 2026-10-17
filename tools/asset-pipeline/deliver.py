"""Assemble the delivery tree (deliver/assets/...), write assets/manifest.json, and pack ≤29 MB zips for transfer.
python3 deliver.py build   -> deliver/assets + deliver/tools
python3 deliver.py pack    -> deliver/zips/part_NN.zip (stored, no compression)
python3 deliver.py pack cat/custom,manifest.json   -> only those asset paths (+ tools), for an incremental delivery"""
import os, sys, json, shutil, glob, zipfile
from PIL import Image

ROOT = 'deliver'
A = f'{ROOT}/assets'
ROOMS = ['living', 'bedroom', 'kitchen', 'garden', 'study', 'attic', 'pass_housewarming', 'pass_midwinter',
         'pass_firstlight', 'housewarming_pack', 'founders']
SETS = ['short_slim', 'short_chunky', 'long_slim', 'long_chunky']

def put(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst): os.remove(dst)
    try: os.link(src, dst)
    except OSError: shutil.copy2(src, dst)

def build():
    if os.path.exists(ROOT): shutil.rmtree(ROOT)
    state = json.load(open('pipeline_state.json'))
    man = {'version': 1, 'conventions': {}, 'files': {}}

    def rec(dst, **meta):
        try:
            with Image.open(dst) as im: meta.setdefault('px', list(im.size))
        except Exception: pass
        man['files'][os.path.relpath(dst, A)] = meta

    # furniture: legacy living-room cut-outs first, grey-room re-dos override
    for f in sorted(glob.glob('living/sprites/furn_living_*.png')):
        d = f'{A}/furniture/living/{os.path.basename(f)}'; put(f, d)
    for room in ROOMS:
        for f in sorted(glob.glob(f'sprites/{room}/furn_{room}_*.png')):
            d = f'{A}/furniture/{room}/{os.path.basename(f)}'; put(f, d)
    legacy = json.load(open('living/extract_log.json'))
    for d in sorted(glob.glob(f'{A}/furniture/*/*.png')):
        room = d.split('/')[-2]; stem = os.path.basename(d)[:-4]
        item_side = stem[len(f'furn_{room}_'):]; variant = None
        if item_side.endswith('_painted'): item_side, variant = item_side[:-8], 'painted'
        item, side = item_side.rsplit('_', 1)
        st = state.get(f'{room}:{item_side}', {})
        meta = {'class': 'furniture', 'room': room, 'item': item, 'facing': side,
                'job_id': st.get('job_id'), 'ref_room': st.get('ref', 'cream' if room == 'living' else None)}
        from scales import SUGGESTED_SCALE
        if item in SUGGESTED_SCALE.get(room, {}): meta['suggested_scale'] = SUGGESTED_SCALE[room][item]
        if variant: meta['variant'] = 'painted (the glow sprite without suffix is the default)'
        if st.get('pos'): meta['pos_in_ref'] = st['pos']; meta['size_in_ref'] = st.get('size')
        elif room == 'living' and item_side in legacy: meta['pos_in_ref'], meta['size_in_ref'] = legacy[item_side][0], legacy[item_side][1]
        rec(d, **meta)

    # room surfaces
    for kind in ['walls', 'floors', 'windows', 'doors', 'garden_strips']:
        for f in sorted(glob.glob(f'surfaces/{kind}/*.png')):
            d = f'{A}/rooms/{kind}/{os.path.basename(f)}'; put(f, d)
            rec(d, **{'class': f'rooms/{kind}', 'tile': kind in ('walls', 'floors'), 'mask': f.endswith('_opening.png')})
    for f in sorted(glob.glob('lm_*_*.npy') + glob.glob('lm_*_*.png')):
        if f.count('_') < 2: continue
        d = f'{A}/rooms/lightmaps/{os.path.basename(f)}'; put(f, d)
        rec(d, **{'class': 'rooms/lightmap'})
    for f in ['ref_room_grey.png']:
        d = f'{A}/rooms/lightmaps/{f}'; put(f, d); rec(d, **{'class': 'rooms/reference'})

    # world
    for kind in ['houses', 'terrain', 'weather']:
        for f in sorted(glob.glob(f'world/{kind}/*.png')):
            d = f'{A}/world/{kind}/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': f'world/{kind}'})
    for f in ['map_landmask.png', 'map_biome.png', 'map_painted.png', 'map_biome_legend.json']:
        d = f'{A}/world/map/{f}'; put(f, d); rec(d, **{'class': 'world/map'})

    # cat
    for s in SETS:
        for f in sorted(glob.glob(f'cat/cat_{s}_*.png')):
            d = f'{A}/cat/base/{s}/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'cat/base', 'set': s})
    for sub, cls in [('expr', 'cat/expressions'), ('ears_rounded', 'cat/ears_rounded'), ('whiskers', 'cat/whiskers'), ('markings', 'cat/marking_refs')]:
        for f in sorted(glob.glob(f'cat/{sub}/*.png')):
            d = f'{A}/{cls}/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': cls})
    for m in ['tuxedo', 'locket', 'socks']:
        for f in sorted(glob.glob(f'cat/marked/{m}/*.png')):
            d = f'{A}/cat/marked/{m}/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'cat/marked', 'marking': m})

    # cat builder: white bases, pattern / white / feature masks, catbuilder.json (see docs/SPEC.md "Coat recipe")
    for f in sorted(glob.glob('cat/custom/**/*.png', recursive=True)):
        rel = os.path.relpath(f, 'cat/custom'); d = f'{A}/cat/custom/{rel}'; put(f, d)
        parts = rel.split('/')
        if parts[0] == 'base': meta = {'class': 'cat/custom/base', 'kind': parts[1]}
        else: meta = {'class': 'cat/custom/mask', 'mask': parts[1], 'of': 'base/' + '/'.join(parts[2:])}
        rec(d, **meta)
    for f in ['cat/custom/catbuilder.json', 'cat/custom/cut_report.json']:
        put(f, f'{A}/{f}')

    # outfits, gifts, ui, widget, audio
    for f in sorted(glob.glob('outfits/outfit_*.png')):
        d = f'{A}/outfits/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'outfits'})
    for f in sorted(glob.glob('gifts/*.png')):
        d = f'{A}/gifts/gift_{os.path.basename(f)}'; put(f, d)
        rec(d, **{'class': 'gifts', 'category': os.path.basename(f).split('_')[0]})
    for f in sorted(glob.glob('ui/icon_*.png')):
        d = f'{A}/ui/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'ui'})
    for f in sorted(glob.glob('widget/*.png')):
        d = f'{A}/widget/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'widget', 'mask': f.endswith('_glass.png')})
    # brand: app icon layers + logos
    for f in sorted(glob.glob('brand/icon/*.png')):
        d = f'{A}/brand/icon/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'brand/icon', 'alternate': os.path.basename(f).startswith('alt_')})
    for f in sorted(glob.glob('brand/logo/*.png')):
        d = f'{A}/brand/logo/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'brand/logo'})
    # whole-cat poses
    from extra import POSES
    for coat in ['plain', 'tuxedo', 'locket', 'socks']:
        for f in sorted(glob.glob(f'cat/poses/{coat}/*.png')):
            stem = os.path.basename(f)[4:-4]
            pose = next(p for p in POSES if stem.endswith(p)); st = stem[:-len(pose) - 1]
            d = f'{A}/cat/poses/{coat}/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'cat/poses', 'set': st, 'coat': coat, 'pose': pose})
    # motion effects
    for f in sorted(glob.glob('fx/*/*.png')):
        d = f'{A}/fx/{f.split("/")[1]}/{os.path.basename(f)}'; put(f, d); rec(d, **{'class': 'fx', 'effect': f.split('/')[1]})
    for f in ['fx/fx.json', 'fx/anchors.json']:
        put(f, f'{A}/{f}')
    anchors = json.load(open('fx/anchors.json'))
    for k, v in anchors.items():
        if k in man['files']: man['files'][k]['motion_fx'] = v
    put('audio/CREDITS_cat_sounds.json', f'{A}/audio/CREDITS_cat_sounds.json')
    for f in sorted(glob.glob('audio/*.wav')):
        d = f'{A}/audio/{os.path.basename(f)}'; put(f, d)
    am = json.load(open('audio/manifest.json'))
    for k, v in am.items(): man['files'][f'audio/{k}.wav'] = dict(v, **{'class': 'audio'})

    man['conventions'] = {
        'furniture': 'furn_<room>_<item>_<R|L>.png; R = facing the right-hand wall, L = facing the left-hand wall. pos_in_ref/size_in_ref = where the item sat in the 2:1 isometric reference room (grey or cream) it was painted in, in that image\'s pixels; use it to derive the floor anchor.',
        'rooms/walls, rooms/floors': '2048 px seamless tiles (flat, unprojected); project onto the 10x10 corner room in code, then multiply by the light map.',
        'rooms/lightmaps': 'lm_<time>_<left|right|floor>.npy = float32 512x512 multiplier (1.0 = neutral); .png is a preview. Times: morning, midday, evening, overcast, night.',
        'rooms/windows, rooms/doors': '<kind>_<id>.png = frame with transparent opening; <kind>_<id>_opening.png = mask of the opening (white) for the view behind.',
        'world/houses': 'ext_<id>.png façade; ext_<id>_glass.png = window glass mask; _dooropen and _snow are repainted variants (not pixel-aligned: cross-fade).',
        'world/terrain': 'terr_<biome>_<season>.png, transparent sky; draw the sky in code behind it.',
        'world/map': 'Equirectangular 4096x2048: x = (lon+180)/360*W, y = (90-lat)/180*H. map_biome.png is an index image, legend in map_biome_legend.json.',
        'cat/base': 'cat_<set>_<view>_<part>.png; views side|tqfront|front|tqback; parts head, ear_far, ear_near, torso, leg_front_near, leg_front_far, leg_back_near, leg_back_far, tail_up, tail_curl, tail_low; _whole = the standing reference for assembling the puppet.',
        'cat/expressions': 'head_<view>_<expression>.png: whole replacement heads (with ears) for calm, slowblink, content, surprised, sleepy, squint; views tqfront|front|side.',
        'cat/marked': 'Same part names as cat/base, repainted with the marking; swap the whole part set for a marked cat.',
        'outfits': 'outfit_<id>_<view>.png; anchor head items between the ears, neck items at the neck, body items over the torso.',
        'gifts': 'gift_<category>_<item>.png', 'ui': 'icon_<name>.png',
        'widget': 'widget_<id>[_wide].png frame with transparent glass + _glass.png mask; draw sky/weather behind, the cat on the sill.',
        'audio': '44.1 kHz 16-bit WAV. Cat voices and the purr are real recordings (public domain / CC0, from Wikimedia Commons, credited in audio/CREDITS_cat_sounds.json and each manifest entry); UI, ambience, sleep breathing and zoomies are synthesised in code (synth.py). Loops are seamless.',
        'brand/icon': 'AppIcon_1024.png is the flattened icon. For the iOS 26 layered icon (Icon Composer) use AppIcon_layer1_background.png behind AppIcon_layer2_cat.png; the system makes the dark, tinted and clear looks from the layers. alt_AppIcon_* are the other three concepts.',
        'brand/logo': 'logo_<horizontal|stacked>_on_light.png (dark ink) and _on_dark.png (cream ink), transparent backgrounds. The stacked logo is the launch-screen mark.',
        'cat/poses': 'cat_<set>_<pose>.png per coat (plain, tuxedo, locket, socks): whole-cat paintings for the resting poses the puppet cannot make well: sit (side, tqfront, front, back), loaf (side, tqfront), sleep_curl, stretch_side. sit_back is the widget pose (the cat looking out of the window). Use the puppet for moving, these for resting; cross-fade between them.',
        'cat/custom/base': 'The cat builder art, painted WHITE: parts/cat_<body>_<view>_<part>.png (8 bodies: short_slim, short_chunky, long_slim, long_chunky, persian, siamese, mainecoon, sphynx; parts as cat/base), poses/cat_<body>_<pose>[__<ears>|__bobtail|__<ears>_bobtail].png, expr/head_<stdnoear|persian|siamese|mainecoon|sphynx|std>_<view>_<expression>.png (stdnoear = the standard bodies, ears come from the parts), ears/ear_<rounded|folded|tufted|oriental>_<view>_<far|near>.png, tails/bobtail_<view>_<up|curl|low>.png, whole/cat_<breed>_<view>_whole.png (assembly reference for the breeds). Tint in code with the coat recipe; catbuilder.json has the data and presets.',
        'cat/custom/mask': 'masks/<mask>/<same path as the base sprite>: 8-bit greyscale, same size as the sprite. tabby_mackerel, tabby_classic, spotted, tortie, colourpoint: 255 = pattern colour. white_mitts, white_tuxedo, white_bicolour, white_van: 255 = the fur stays white. features (RGB): R = iris of the eye on the image left (the only eye in a side view), G = the other iris, B = nose leather. A missing mask = 0 everywhere.',
        'fx': 'Animated effects. Loops: fire, candle, steam, smoke, water_trickle, water_ripple, butterfly (fx_<name>_NN.png frames in one cell size + a _strip.png). Sprites: robin poses, reaction icons. fx/fx.json has frame counts, cell sizes and anchors; fx/anchors.json (also copied into each furniture entry as motion_fx) says where flames and steam attach on the moving furniture.'}
    json.dump(man, open(f'{A}/manifest.json', 'w'), indent=1)

    # tools
    tools = f'{ROOT}/tools/asset-pipeline'; os.makedirs(tools, exist_ok=True)
    for f in glob.glob('*.py') + ['pipeline_state.json', 'redo.txt', 'nose_hints.json', 'gallery.css']:
        if os.path.exists(f): shutil.copy2(f, f'{tools}/{f}')
    n = len(man['files']); size = sum(os.path.getsize(os.path.join(A, k)) for k in man['files'])
    print(n, 'files', round(size / 1e6), 'MB')

def pack(limit=24e6, only=None):
    """only = list of asset sub-paths for an incremental delivery (e.g. ['cat/custom', 'manifest.json']); tools always."""
    out = f'{ROOT}/zips'; shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
    files = []
    for base, sub in [(f'{ROOT}/assets', 'assets'), (f'{ROOT}/tools', 'tools')]:
        for dp, _, fs in os.walk(base):
            for f in sorted(fs):
                p = os.path.join(dp, f); arc = os.path.join(sub, os.path.relpath(p, base))
                if only and sub == 'assets' and not any(os.path.relpath(p, base).startswith(o) for o in only): continue
                files.append((p, arc))
    files.sort(key=lambda x: x[1])
    parts, cur, size = [], [], 0
    for p, arc in files:
        s = os.path.getsize(p)
        if cur and size + s > limit: parts.append(cur); cur, size = [], 0
        cur.append((p, arc)); size += s
    if cur: parts.append(cur)
    for i, part in enumerate(parts):
        with zipfile.ZipFile(f'{out}/part_{i:02d}.zip', 'w', zipfile.ZIP_STORED) as z:
            for p, arc in part: z.write(p, arc)
    print(len(parts), 'zips')

if __name__ == '__main__':
    if sys.argv[1] == 'pack' and len(sys.argv) > 2: pack(only=sys.argv[2].split(','))
    else: {'build': build, 'pack': pack}[sys.argv[1]]()

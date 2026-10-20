"""The season passes' own furniture sets (Josh, 20 Oct 2026: "less beans and more items ... feel free to design more
items"). Each piece is painted once, facing R, on flat magenta at the grey reference room's 2:1 isometric angle, and
its L is the mirror (ASSETS.md: "Mirroring the R sprite for L is the fallback if a pair jars when rotated", here the
rule, so every pair matches).

  python3 pass_sets.py requests <season> [ids...]   -> JSON requests for generate_image_batch on stdout
  python3 pass_sets.py record <season> [ids...] < jobs.json
                                                    -> records the jobs (jobs_wait's JSON, by index into the ids) in
                                                       pipeline_state.json as pass_<season>:<id>_R
  python3 pass_sets.py urls <season> < lines         -> the same from "<id> <result_url>" lines
  python3 pass_sets.py cut <season> [ids...]        -> downloads, keys, mirrors into assets/furniture/pass_<season>/
                                                       and adds both facings to assets/manifest.json
  python3 pass_sets.py surfaces <season>             -> JSON requests for the season's wallpaper and floor
  python3 pass_sets.py tile <season>                 -> makes them seamless into assets/rooms/walls|floors
  python3 pass_sets.py sheet <season> <out.png>     -> a contact sheet of the set with names, for Josh

Needs Pillow, numpy and scipy: uv run --with numpy --with pillow --with scipy python pass_sets.py ...
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
STATE = os.path.join(HERE, 'pipeline_state.json')
MANIFEST = os.path.join(ROOT, 'assets', 'manifest.json')

GREY = "d8ab3b05-db3b-4ef7-b3c5-5a0cf5d17e07"      # the grey 10 x 10 reference room (the angle)
# The game's own furniture (armchair, log basket, cat tree, radio, fir tree, lamp) on magenta: the brushwork to match.
# Style test E (146f85a0) as the reference painted heavier dabs than the furniture has.
STYLE_FURNITURE = "59241d91-b0da-47d8-8425-94f853553d85"
FLOOR_EXAMPLE = "a32b2400-bb40-4161-aef8-6b1387d96f93"  # Housewarming's moving boxes, painted in the grey room
WALL_EXAMPLE = "cca218b4-fd5e-46ad-ad2e-679b6777744d"   # Midwinter's wreath on the grey room's right wall

PAINT = ("Painted in exactly the same style as the furniture in the second reference image: fine, soft painterly "
         "brushwork with smooth, believable shading and a gently textured surface, a warm, high-key, saturated palette, "
         "warm light from the upper left, soft violet-blue shadows. Not heavy impasto dabs. Slightly stylised and cosy, "
         "never a cartoon.")
FLOOR_T = ("A single object for a cosy painterly cat game: {d}. Seen from exactly the same raised viewpoint as the room in "
           "the first reference image, in a clean 2:1 isometric projection (parallel lines stay parallel, no vanishing "
           "points), turned square to that room with its back towards the right-hand wall, so its front faces the lower "
           "left of the picture (any opening or front faces the lower left too), the way the boxes stand in the third reference image. {size} " + PAINT +
           " Isolated on a flat, solid pure magenta (#FF00FF) background filling the whole picture: do not paint the room, "
           "no floor, no wall, no cast shadow, no rug or mat unless described. Only that one object; no cat, no people, no "
           "text, no labels.")
WALL_T = ("A single object for a cosy painterly cat game: {d}. It hangs flat on the right-hand wall of the room in the first "
          "reference image and is seen from exactly that raised viewpoint in a clean 2:1 isometric projection, lying flat "
          "in the wall's plane and slanted with it, the way the wreath hangs in the third reference image. {size} " + PAINT +
          " Isolated on a flat, solid pure magenta (#FF00FF) background filling the whole picture: do not paint the wall "
          "or the room, no cast shadow. Only that one object; no cat, no people, no text, no labels.")
BIG = "Drawn large, filling about half the height of the picture."
SMALL = "A small object, but drawn large, filling about half the height of the picture, so its detail is clear."

# id: (name, layer, prompt detail, how large to paint it)
SETS = {
    'blackcat': {
        # Free track
        'conkerbowl': ("Conker bowl", 'floor', "a shallow turned-wood bowl heaped with glossy chestnut-brown conkers, a "
                       "couple of their spiky green cases split open beside them", SMALL),
        'pumpkintrio': ("Pumpkin trio", 'floor', "three small pumpkins piled together: a bright orange one, a pale cream "
                        "one and a green-and-cream striped one, with curly stalks", SMALL),
        'yarnbasket': ("Yarn basket", 'floor', "a round wicker basket brimming with balls of wool in rust, mustard and "
                       "plum, one ball trailing a loose strand over the rim", SMALL),
        'ghosttoy': ("Felt ghost", 'floor', "a soft little felt cat toy shaped like a sheet ghost, cream felt with two "
                     "stitched dark eyes and a tiny brass bell, lying on its side", SMALL),
        'applecrate': ("Apple crate", 'floor', "a slatted pale wooden crate full of shiny red and green apples, two "
                       "apples resting on the ground beside it", BIG),
        'lantern': ("Storm lantern", 'floor', "an old brass hurricane lantern with a glass chimney and a lit cream "
                    "candle inside, glowing warm amber", SMALL),
        'leafpile': ("Leaf pile", 'floor', "a soft, loose heap of crunchy autumn leaves in amber, rust, gold and brown, "
                     "a few oak and maple leaves scattered at its edges", BIG),
        'cocoa': ("Hot chocolate tray", 'floor', "a small wooden tray with two steaming mugs of hot chocolate topped with "
                  "pink and white marshmallows and a little plate of ginger biscuits", SMALL),
        'batbunting': ("Bat bunting", 'wall', "a garland swagged in two loops: little black felt bats and orange paper "
                       "autumn leaves strung along a length of natural twine", BIG),
        'candles': ("Candle cluster", 'floor', "five cream pillar candles of different heights standing on a round slate, "
                    "all lit, with soft wax drips", SMALL),
        'toadstool': ("Toadstool stool", 'floor', "a footstool shaped like a big red toadstool with cream spots on its "
                      "cap and a thick cream stalk, a soft padded top", BIG),
        'pumpkinpouffe': ("Pumpkin pouffe", 'floor', "a round chunky-knit pouffe shaped like a pumpkin in burnt orange "
                          "wool, with deep ribbed segments and a little green knitted stalk", BIG),
        'mushroomlamp': ("Toadstool lamp", 'floor', "a little glowing table lamp shaped like a cluster of three toadstools, "
                         "their caps warm orange glass with cream spots, lit softly from inside, on a mossy wooden base",
                         SMALL),
        # Premium track
        'pumpkinbed': ("Pumpkin cat bed", 'floor', "a big round cat bed shaped like a hollowed-out orange pumpkin with a "
                       "wide round opening at the front, a plum velvet cushion inside and a curly green stalk on top", BIG),
        'jackolantern': ("Jack-o'-lantern", 'floor', "a large orange pumpkin with a friendly cat's face carved into it: "
                         "two pointed ears cut along the top, round eyes, a small nose and whiskers, lit warmly from "
                         "inside", SMALL),
        'velvetchair': ("Midnight armchair", 'floor', "a plum velvet wingback armchair with brass studs along the arms "
                        "and a chunky knitted orange throw draped over one arm", BIG),
        'catportrait': ("Black cat portrait", 'wall', "an oil portrait of a regal slim black cat with big round amber eyes "
                        "and no collar, sitting upright against a deep teal background, in an ornate carved gilt frame",
                        BIG),
        'moonlamp': ("Moon lamp", 'floor', "a tall floor lamp: a glowing round paper lantern painted as a pale golden "
                     "full moon with soft craters, hanging from a slim curved brass stand", BIG),
        'catcastle': ("Cardboard castle", 'floor', "a cardboard cat house made like a little castle, with two round "
                      "turrets, a round cat-sized doorway, windows drawn on in black marker and small orange paper "
                      "pennants on the turrets", BIG),
        'spookytree': ("Twisty tree", 'floor', "a cat tree shaped like a gnarled bare autumn tree: a twisted sisal-wrapped "
                       "trunk, two round plum cushioned platforms on its branches and little black felt bats dangling "
                       "from the twigs on strings", BIG),
        'cobwebhammock': ("Cobweb hammock", 'floor', "a cat hammock slung on a low wooden frame, its cream crocheted net "
                          "woven like a cobweb, with a small fuzzy felt spider toy hanging from one corner", BIG),
        'owlclock': ("Owl clock", 'wall', "a carved wooden owl wall clock: the owl's round belly is a cream clock face "
                     "with black hands, big amber glass eyes, a brass pendulum hanging below", BIG),
        'catrug': ("Black cat rug", 'floor', "a round woven rug lying flat on the ground, mustard with a plum border, "
                   "and a curled-up sleeping black cat woven into its middle", BIG),
        'telescope': ("Brass telescope", 'floor', "an old brass telescope on a tall wooden tripod, tilted up towards the "
                      "night sky", BIG),
        'grandclock': ("Midnight clock", 'floor', "a tall grandfather clock in dark walnut with a painted moon-phase dial "
                       "showing a smiling full moon among gold stars, both hands pointing to twelve, a brass pendulum "
                       "behind a glass door", BIG),
        'applebob': ("Apple-bobbing tub", 'floor', "a round wooden half-barrel tub filled with clear water, shiny red "
                     "apples floating in it", BIG),
        'gramophone': ("Gramophone", 'floor', "a wind-up gramophone with a big flared brass horn on a small dark wooden "
                       "cabinet, a black record on the turntable", BIG),
        'ghostlamp': ("Ghost lamp", 'floor', "a small round wooden side table with a lamp on it whose shade is a little "
                      "white sheet ghost with two dark oval eyes, glowing softly from inside", BIG),
        'batcushion': ("Bat cushion", 'floor', "a plump black velvet floor cushion shaped like a friendly bat with its "
                       "wings spread out flat, little felt ears and a plum underside", BIG),
        'rockingchair': ("Rocking chair", 'floor', "a honey-oak rocking chair with spindle back and curved rockers, a "
                         "crocheted granny-square blanket in autumn colours over its seat", BIG),
        'conkertree': ("Conker tree", 'floor', "a young horse-chestnut tree in a big terracotta pot, its broad leaves "
                       "turning gold and rust, a few spiky green conker cases hanging from it", BIG),
        'humbugjar': ("Humbug jar", 'floor', "a tall glass sweet jar with a round lid, full of black-and-white striped "
                      "humbugs and orange toffees", SMALL),
        'catdoorstop': ("Cat doorstop", 'floor', "a cast-iron doorstop shaped like a sitting black cat with round amber "
                        "eyes and a curled tail, no collar", SMALL),
        'pumpkinpatch': ("Pumpkin patch", 'floor', "a long low wooden planter box overflowing with pumpkins, striped "
                         "gourds and curling green vines with big leaves", BIG),
        'haybale': ("Hay bale seat", 'floor', "a neat golden straw hay bale with a red-and-mustard tartan blanket folded "
                    "over one end and a small pumpkin on top", BIG),
        'lanternstring': ("Pumpkin lanterns", 'wall', "a string of little round paper pumpkin lanterns, glowing warm "
                          "orange, swagged in two loops along a dark cord", BIG),
        'booknook': ("Ghost story shelf", 'floor', "a small dark-wood bookshelf with three shelves of old cloth-bound "
                     "storybooks, a carved pumpkin bookend, a candle in a brass holder and a cushioned gap on the bottom "
                     "shelf just big enough for a cat to curl up in", BIG),
    },
    'housewarming': {
        # Free track (with the moving boxes, paint tins and takeaway bag painted on 17 Oct)
        'keysdish': ("New keys", 'floor', "a small ceramic dish holding a bunch of shiny new house keys on a ring with a "
                     "cream luggage tag tied on with ribbon", SMALL),
        'bubblewrap': ("Bubble wrap", 'floor', "a fat roll of bubble wrap, partly unrolled across the ground in a loose "
                       "glossy sheet", BIG),
        'firstcuppa': ("First cuppa", 'floor', "an upturned wooden crate used as a table, with a cream kettle, two "
                       "steaming mugs of tea and a packet of biscuits on it", BIG),
        'floorcushion': ("Floor cushion", 'floor', "a big squashy square floor cushion in mustard corduroy with a "
                         "button in the middle", BIG),
        'sleepingbag': ("Sleeping bag", 'floor', "a teal quilted sleeping bag unrolled flat on the ground with a striped "
                        "pillow at its head, for the first night in a new home", BIG),
        'plantgift': ("Housewarming plant", 'floor', "a leafy cheese plant in a terracotta pot with a big peach ribbon "
                      "bow tied round the pot", BIG),
        'cardstring': ("Housewarming cards", 'wall', "a length of twine pinned up in a gentle swag with little "
                       "illustrated greetings cards and small wooden pegs hanging from it, no words on them", BIG),
        'toolbox': ("Toolbox", 'floor', "an open red metal toolbox with a wooden-handled hammer, a screwdriver and a "
                    "tape measure", SMALL),
        'flatpack': ("Flat-pack box", 'floor', "a long flat cardboard box of flat-pack furniture lying on the ground, "
                     "taped shut, with a little silver hex key on top", BIG),
        'boxtunnel': ("Box tunnel", 'floor', "three cardboard boxes taped end to end into a tunnel with round holes cut "
                      "in the sides, made for a cat", BIG),
        'laundrybag': ("Laundry bag", 'floor', "a big blue-and-white chequered woven laundry bag stuffed full of soft "
                       "things, its zip half open", BIG),
        # Premium track
        'housebed': ("House cat bed", 'floor', "a cat bed shaped like a little house: pale wooden walls, a pitched "
                     "slate-blue roof with a tiny chimney, a round doorway and a cream cushion inside", BIG),
        'velvetsofa': ("Teal velvet sofa", 'floor', "a deep teal velvet two-seater sofa with rounded arms and brass "
                       "legs, a clear plastic cover still wrapped round one arm", BIG),
        'eggchair': ("Hanging egg chair", 'floor', "a woven rattan egg chair hanging from a curved black stand, a plump "
                     "cream cushion inside", BIG),
        'blanketfort': ("Blanket fort", 'floor', "a den made of a patchwork quilt draped over two wooden chairs, fairy "
                        "lights along its edge and cushions just visible inside", BIG),
        'cratetable': ("Crate coffee table", 'floor', "a low coffee table made from four wooden fruit crates with a "
                       "glass top, books and a small plant on it", BIG),
        'arclamp': ("Arc lamp", 'floor', "a tall brass arc floor lamp on a round marble base, its dome shade glowing "
                    "warm", BIG),
        'beanbag': ("Bean bag", 'floor', "a big slouchy bean bag in coral cord, squashed into a comfy dip", BIG),
        'gallerywall': ("Gallery wall", 'wall', "a cluster of six small mismatched picture frames hung close together: "
                        "little landscapes, a sketch of a house and a pressed flower", BIG),
        'leaningmirror': ("Leaning mirror", 'floor', "a tall arched mirror in a thin brass frame, leaning back as if "
                          "against a wall, reflecting soft light", BIG),
        'plantstand': ("Plant stand", 'floor', "a three-tier wooden plant stand with trailing ivy, a fern and a small "
                       "cactus in terracotta pots", BIG),
        'blankettrunk': ("Blanket trunk", 'floor', "a lidded wicker trunk with soft knitted blankets spilling out of its "
                         "half-open lid", BIG),
        'housescratcher': ("House scratcher", 'floor', "a cat scratching post shaped like a tall narrow cottage: a "
                           "sisal-wrapped post as its walls, a little red roof on top as a perch", BIG),
        'bicycle': ("Bicycle", 'floor', "a sage-green vintage bicycle with a wicker basket of flowers on the front, "
                    "standing on its kickstand", BIG),
        'swatchboard': ("Paint swatches", 'wall', "a cork board with little squares of paint colour swatches and fabric "
                        "samples pinned to it in a loose grid", BIG),
        'housecake': ("Housewarming cake", 'floor', "a round iced cake on a tall cake stand, topped with a tiny iced "
                      "house and sugar flowers", SMALL),
        'breadsalt': ("Bread and salt", 'floor', "a round crusty loaf on a wooden board beside a little dish of salt, "
                      "the old housewarming gift", SMALL),
        'recordcrate': ("Record crate", 'floor', "a wooden crate of vinyl records with a small suitcase record player "
                        "open on top of it", BIG),
        'welcomewreath': ("Eucalyptus wreath", 'wall', "a round wreath of silvery eucalyptus and dried cream flowers "
                          "tied with a linen bow", BIG),
        'paperlantern': ("Paper lantern", 'floor', "a big round white paper lantern shade not yet hung, sitting on the "
                         "ground with its cord coiled beside it", BIG),
        'bookstack': ("Unpacked books", 'floor', "a wobbly tower of hardback books with a small brass reading lamp "
                      "balanced on top", BIG),
    },
}


# The master's size in the grey reference room's pixels, where every other piece's master is (the armchair stands 673
# high, the lamp 705, the wall clock 225): ('h', px) or ('w', px). A small piece is kept larger than it stands and drawn
# down by the catalogue's suggestedScale, so it stays sharp on an iPad.
TARGETS = {
    'blackcat': {
        'conkerbowl': ('w', 380), 'pumpkintrio': ('h', 380), 'yarnbasket': ('h', 400), 'ghosttoy': ('w', 360),
        'applecrate': ('h', 460), 'lantern': ('h', 420), 'leafpile': ('w', 600), 'cocoa': ('w', 400),
        'batbunting': ('w', 620), 'candles': ('h', 400), 'toadstool': ('h', 520), 'pumpkinpouffe': ('h', 480),
        'pumpkinbed': ('w', 560), 'jackolantern': ('h', 440), 'velvetchair': ('h', 680), 'catportrait': ('h', 420),
        'moonlamp': ('h', 720), 'catcastle': ('h', 560), 'spookytree': ('h', 690), 'cobwebhammock': ('w', 560),
        'owlclock': ('h', 300), 'catrug': ('w', 600), 'telescope': ('h', 620), 'grandclock': ('h', 800),
        'applebob': ('w', 440), 'gramophone': ('h', 470), 'ghostlamp': ('h', 440), 'mushroomlamp': ('h', 380),
        'batcushion': ('w', 460), 'rockingchair': ('h', 640), 'conkertree': ('h', 740), 'humbugjar': ('h', 360),
        'catdoorstop': ('h', 340), 'pumpkinpatch': ('w', 620), 'haybale': ('w', 520), 'lanternstring': ('w', 640),
        'booknook': ('h', 600),
    },
    'housewarming': {
        'keysdish': ('w', 360), 'bubblewrap': ('w', 560), 'firstcuppa': ('h', 470), 'floorcushion': ('w', 480),
        'sleepingbag': ('w', 640), 'plantgift': ('h', 640), 'cardstring': ('w', 640), 'toolbox': ('w', 400),
        'flatpack': ('w', 620), 'boxtunnel': ('w', 640), 'laundrybag': ('h', 480),
        'housebed': ('h', 560), 'velvetsofa': ('w', 680), 'eggchair': ('h', 760), 'blanketfort': ('w', 680),
        'cratetable': ('w', 560), 'arclamp': ('h', 780), 'beanbag': ('w', 520), 'gallerywall': ('w', 480),
        'leaningmirror': ('h', 700), 'plantstand': ('h', 640), 'blankettrunk': ('w', 500), 'housescratcher': ('h', 680),
        'bicycle': ('w', 640), 'swatchboard': ('w', 420), 'housecake': ('h', 380), 'breadsalt': ('w', 380),
        'recordcrate': ('h', 480), 'welcomewreath': ('w', 300), 'paperlantern': ('w', 440), 'bookstack': ('h', 560),
    },
}


# Pieces lying flat on the floor: their height as a share of their width (a circle on the floor is 2:1, plus its edge).
FLAT = {'blackcat': {'catrug': 0.54}}

# Each season's own wallpaper and floor: surfaces.py's templates and brushwork references, made seamless by tiles.py.
REF_WALL = "71ed0fbb-1478-4c87-b245-0a177ae53aee"    # wall_cream.png tile
REF_FLOOR = "5ccca407-456d-46d7-9a94-4826cda736b8"   # floor_honey.png tile
SURFACES = {
    'blackcat': {
        'wall_pass_blackcat_midnight_bats': ("Midnight bats", "a deep midnight-blue wallpaper with a small, evenly "
                                             "scattered repeating pattern of little cream bats in flight, tiny gold "
                                             "stars and small round golden full moons"),
        'floor_pass_blackcat_conker_parquet': ("Conker parquet", "rich, glossy conker-brown oak parquet blocks laid "
                                               "in a herringbone pattern"),
    },
}


def gp(prompt, refs):
    return {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "1:1", "prompt": prompt,
            "medias": [{"role": "image_references", "value": r} for r in refs]}


def requests(season, ids):
    out = []
    for i, key in enumerate(ids or SETS[season]):
        name, layer, detail, size = SETS[season][key]
        template, example = (WALL_T, WALL_EXAMPLE) if layer == 'wall' else (FLOOR_T, FLOOR_EXAMPLE)
        out.append({"index": i, "params": gp(template.format(d=detail, size=size), [GREY, STYLE_FURNITURE, example])})
    return out


def surface_requests(season):
    from surfaces import WALL_T, FLOOR_T
    out = []
    for i, (sid, (_, detail)) in enumerate(SURFACES[season].items()):
        wall = sid.startswith('wall_')
        p = {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "1:1",
             "prompt": (WALL_T if wall else FLOOR_T).format(d=detail),
             "medias": [{"role": "image_references", "value": REF_WALL if wall else REF_FLOOR}]}
        out.append({"index": i, "params": p})
    return out


def tile(season):
    """Downloads each surface, makes it seamless and puts it in assets/rooms/walls or floors (2048 square)."""
    from tiles import make_seamless
    state = json.load(open(STATE))
    manifest = json.load(open(MANIFEST))
    raw_dir = os.path.join(HERE, 'gen', f'pass_{season}')
    os.makedirs(raw_dir, exist_ok=True)
    for sid in SURFACES[season]:
        entry = state.get(f'surface:{sid}')
        if not entry or not entry.get('url'):
            print(sid, 'no result yet')
            continue
        raw = os.path.join(raw_dir, f'{sid}.png')
        if not os.path.exists(raw):
            subprocess.run(['curl', '-sS', '-o', raw, entry['url']], check=True)
        im = Image.open(raw).convert('RGB')
        im = im.resize((2048, 2048), Image.LANCZOS) if im.size != (2048, 2048) else im
        kind = 'walls' if sid.startswith('wall_') else 'floors'
        rel = f'rooms/{kind}/{sid}.png'
        make_seamless(im).save(os.path.join(ROOT, 'assets', rel))
        manifest['files'][rel] = {'class': f'rooms/{kind}', 'tile': True, 'mask': False, 'px': [2048, 2048],
                                  'job_id': entry['job_id']}
        entry['status'] = 'tiled'
        print(sid)
    json.dump(state, open(STATE, 'w'), indent=1)
    json.dump(manifest, open(MANIFEST, 'w'), indent=1)


def record(season, ids, jobs):
    state = json.load(open(STATE))
    keys = ids or list(SETS[season])
    for job in jobs:
        key = keys[job['index']]
        name = f'surface:{key}' if key.startswith(('wall_', 'floor_')) else f'pass_{season}:{key}_R'
        state[name] = {'job_id': job['job_id'], 'status': job.get('status', 'submitted'),
                                           'ref': 'magenta', **({'url': job['result_url']} if job.get('result_url') else {})}
    json.dump(state, open(STATE, 'w'), indent=1)
    print('recorded', len(jobs))


def key_magenta(a):
    """shopkey.py's key: the flat magenta goes transparent, blends get partial alpha with the key unmixed, spill greyed.
    Two changes for furniture: only colour with both red and blue high counts as the key (shopkey's (r + b) / 2 took a
    toadstool's red cap, which touches the background, for it), and spill is greyed only near the edge, so plum velvet
    keeps its colour."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = np.clip((np.minimum(r, b) - g - 60) / 90, 0, 1)
    lab, _ = ndimage.label(m > 0.5)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    border = np.isin(lab, list(edge))
    keycol = np.median(a[border], axis=0)
    dist = np.sqrt(((a - keycol) ** 2).sum(-1))
    alpha = np.clip((dist - 40) / 80, 0, 1)
    alpha[border] = 0
    alpha = ndimage.gaussian_filter(alpha, 0.6)
    safe = np.maximum(alpha, 0.05)[..., None]
    fg = (a - (1 - safe) * keycol) / safe
    out = np.where(alpha[..., None] < 0.999, np.clip(fg, 0, 255), a)
    mx, mn = out.max(-1), out.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    rr, gg, bb = out[..., 0], out[..., 1], out[..., 2]
    hue = (np.degrees(np.arctan2(np.sqrt(3) * (gg - bb), 2 * rr - gg - bb)) + 360) % 360
    near_edge = ndimage.binary_dilation(alpha < 0.5, iterations=4)
    spill = (hue > 288) & (hue < 328) & (sat > 0.66) & (mx > 90) & (alpha > 0.02) & near_edge
    out = np.where(spill[..., None], out.mean(-1, keepdims=True) * 0.85 + out * 0.15, out)
    # Only the object: specks and stray marks apart from the largest pieces go.
    solid = alpha > 0.5
    lab, n = ndimage.label(ndimage.binary_dilation(solid, iterations=6))
    if n > 1:
        sizes = ndimage.sum(solid, lab, range(1, n + 1))
        keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 0.03 * sizes.max()])
        alpha = np.where(keep, alpha, 0)
    return np.dstack([out, np.clip(alpha * 255, 0, 255)]).astype(np.uint8)


def cut(season, ids):
    state = json.load(open(STATE))
    manifest = json.load(open(MANIFEST))
    room = f'pass_{season}'
    folder = os.path.join(ROOT, 'assets', 'furniture', room)
    raw_dir = os.path.join(HERE, 'gen', room)
    os.makedirs(folder, exist_ok=True)
    os.makedirs(raw_dir, exist_ok=True)
    for key in ids or SETS[season]:
        entry = state.get(f'{room}:{key}_R')
        if not entry or not entry.get('url'):
            print(key, 'no result yet')
            continue
        raw = os.path.join(raw_dir, f'{key}.png')
        if not os.path.exists(raw):
            subprocess.run(['curl', '-sS', '-o', raw, entry['url']], check=True)
        im = Image.fromarray(key_magenta(np.asarray(Image.open(raw).convert('RGB')).astype(np.float32)))
        im = im.crop(im.getbbox())
        side, px = TARGETS[season][key]
        k = px / (im.height if side == 'h' else im.width)
        # Something lying flat on the floor is drawn at the room's 2:1 (the model paints round rugs too tall).
        flat = FLAT.get(season, {}).get(key)
        height = round(im.width * k * flat) if flat else round(im.height * k)
        im = im.resize((max(1, round(im.width * k)), max(1, height)), Image.LANCZOS)
        for facing, picture in (('R', im), ('L', im.transpose(Image.FLIP_LEFT_RIGHT))):
            name = f'furn_{room}_{key}_{facing}.png'
            picture.save(os.path.join(folder, name))
            manifest['files'][f'furniture/{room}/{name}'] = {
                'class': 'furniture', 'room': room, 'item': key, 'facing': facing, 'job_id': entry['job_id'],
                'ref_room': 'grey', 'px': list(picture.size),
                **({'mirror_of': f'furniture/{room}/furn_{room}_{key}_R.png'} if facing == 'L' else {}),
            }
        entry['status'] = 'cut'
        entry['size'] = list(im.size)
        print(key, im.size)
    json.dump(state, open(STATE, 'w'), indent=1)
    json.dump(manifest, open(MANIFEST, 'w'), indent=1)


def sheet(season, out, ids=None, columns=7):
    room = f'pass_{season}'
    keys = ids or list(SETS[season])
    cell, label = 300, 46
    rows = (len(keys) + columns - 1) // columns
    canvas = Image.new('RGB', (columns * cell, rows * (cell + label)), (250, 242, 230))
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype('/System/Library/Fonts/SFNSRounded.ttf', 24)
    except OSError:
        font = ImageFont.load_default()
    for i, key in enumerate(keys):
        x, y = (i % columns) * cell, (i // columns) * (cell + label)
        path = os.path.join(ROOT, 'assets', 'furniture', room, f'furn_{room}_{key}_R.png')
        if os.path.exists(path):
            im = Image.open(path).convert('RGBA')
            im.thumbnail((cell - 30, cell - 30))
            canvas.paste(im, (x + (cell - im.width) // 2, y + (cell - im.height) // 2 + 6), im)
        name = SETS[season][key][0]
        w = draw.textlength(name, font=font)
        draw.text((x + (cell - w) / 2, y + cell + 4), name, fill=(61, 46, 56), font=font)
    canvas.save(out, quality=88)


if __name__ == '__main__':
    command, season = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
    if command == 'requests':
        print(json.dumps(requests(season, rest)))
    elif command == 'record':
        record(season, rest, json.load(sys.stdin)['jobs'])
    elif command == 'urls':
        # "<id> <result_url>" lines (jobs_wait's result_url; the job id is in the URL's name).
        jobs, ids = [], []
        for i, line in enumerate(l for l in sys.stdin.read().splitlines() if l.strip()):
            key, url = line.split()
            ids.append(key)
            jobs.append({'index': i, 'job_id': url.rsplit('_', 1)[1][:-4], 'status': 'completed', 'result_url': url})
        record(season, ids, jobs)
    elif command == 'cut':
        cut(season, rest)
    elif command == 'surfaces':
        print(json.dumps(surface_requests(season)))
    elif command == 'tile':
        tile(season)
    elif command == 'sheet':
        sheet(season, rest[0], rest[1:] or None)

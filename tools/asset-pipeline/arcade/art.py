"""The Games menu and its games (19 Oct 2026; Josh: "build out the games section massively - this needs to be the retention
angle and daily use"): the paintings for the menu's tiles, the runner (Zoomies), the pounce game (Catapult), the match game
(Purrfect Match), four in a row (Cats in a Row) and the daily puzzle. python3 art.py requests <group> prints the Higgsfield
requests (gpt_image_2_5, high, 2k) as sent.

References: style test E (job 146f85a0) for scenes, the master cat plate (job 3553b9b6) wherever Midnight is painted, the
first UI sheet (job 5f71253c) for icons, and the shop's painted tiles (`shop_club`, `shop_starter` on magenta, media
cca85a1b and 4aba412d) for the menu's key art, so the games sit beside the shop's pictures.
"""
import json
import sys

STYLE = ("Painted with visible painterly brushwork in the high-key Mediterranean-pastel palette of the references: saturated, "
         "warm, inviting, slightly stylised painted-animation look, warm key light from the upper left, violet-blue simplified "
         "shadows, a soft warm rim light on edges. ")
CAT = ("The cat is the reference's black cat: slim graceful body, long slim legs, long curling tail, round head a touch large "
       "for the body, big round amber eyes with a white catchlight, small simplified nose, subtle mouth line, both ears upright, "
       "dark navy-brown fur with a warm lit edge; no collar, no bow, no forehead mark. ")
MAGENTA = ("Flat, solid pure magenta (#FF00FF) background filling the frame, no shadow on the background, no pink or magenta "
           "anywhere in the subject itself. No text, no letters, no numbers, no logos.")
TILE = ("Key art for a game's tile in the menu of a cosy painted video game, in the exact painted style and finish of the two "
        "reference pictures (glossy painted objects, chunky readable shapes, a warm glow), the subject large and centred with a "
        "little space around it: ")

TILES = {
    'tile_zoomies': TILE + ("a black cat in a joyful flying gallop seen from the side, running to the right, all four paws off "
                            "the ground, ears back and tail streaming behind, a little puff of dust behind its back paws; ahead "
                            "of it an arc of six small golden fish-shaped cat biscuits floating in the air, and a small grey "
                            "felt toy mouse with a coral nose and a curly string tail scampering in front. " + CAT + STYLE + MAGENTA),
    'tile_catapult': TILE + ("a black cat leaping through the air from the left towards the right, stretched out like a pouncing "
                             "superhero with its front paws reaching forward and its tail streaming behind, aiming at a wobbly "
                             "tower on the right made of two cardboard boxes, a stack of three hardback books and a round biscuit "
                             "tin, with two small grey felt toy mice with coral noses sitting on top of the tower; at the bottom "
                             "left a plump squashy teal cushion it sprang from. " + CAT + STYLE + MAGENTA),
    'tile_match': TILE + ("a small open cardboard box tipped on its side with game pieces tumbling out of it in a joyful heap: a "
                          "glossy blue fish, a coral-red ball of wool yarn, a small grey felt toy mouse, a round golden biscuit "
                          "stamped with a paw print, a bright green sprig of catnip leaves and a soft violet feather, each "
                          "piece chunky, glossy and instantly readable like a puzzle game's tiles. " + STYLE + MAGENTA),
    'tile_row': TILE + ("a chunky honey-oak wooden upright game board standing on two feet, seen straight on and slightly turned, "
                        "with rows of round holes through it, some of the holes filled with round wooden counters: teal-rimmed "
                        "counters painted with a black cat's face and coral-rimmed counters painted with a ginger tabby cat's "
                        "face, four of the black cat counters in a diagonal line glowing softly; one more black cat counter "
                        "dropping in at the top. " + STYLE + MAGENTA),
    'tile_puzzle': TILE + ("a black cat peeking over the top edge of a big square cream paper puzzle card, front paws resting on "
                           "the card's edge, looking out with a pleased expression, a yellow pencil beside its paw; the card shows "
                           "a simple grid of small squares, some filled in plum ink. " + CAT + STYLE + MAGENTA),
}

ZOOMIES_SCENE = ("A concept frame for a side-scrolling endless runner in a cosy painted video game, landscape, seen side on from a "
                 "slightly raised angle: the long hallway of a warm family home running left to right, apricot-cream wallpaper "
                 "with framed pictures and honey wood panelling, honey wooden floorboards with a long striped runner rug along "
                 "it, the floor deep enough to show three running lanes one behind another. A black cat gallops to the right "
                 "along the middle lane, ears back, tail streaming. A line of small golden fish-shaped biscuits floats ahead of "
                 "it in the front lane, a small grey felt toy mouse with a coral nose scampers in the back lane, a wicker "
                 "laundry basket stands in the cat's way further ahead, and further on a low coffee table to slip under; at the "
                 "far right the open back door with a sunny garden beyond. " + CAT + STYLE + "No text, no letters, no interface.")
CATAPULT_SCENE = ("A concept frame for a side-on physics game in a cosy painted video game, landscape, seen side on: a sunny "
                  "London back garden at the rear of a brick terrace, a lawn along the bottom, a brick garden wall and the backs "
                  "of brick terraced houses with chimney pots behind under a soft blue sky. On the left a short carpeted cat "
                  "tree with a plump squashy teal cushion on top, a black cat crouched on the cushion with its bottom wiggling, "
                  "ready to pounce, a faint dotted arc curving up and to the right from it. On the right a wobbly tower on the "
                  "lawn built of cardboard boxes, stacks of hardback books, a wooden plank laid across, round biscuit tins and "
                  "a flower pot, with three small grey felt toy mice with coral noses sitting on its ledges. " + CAT + STYLE +
                  "No text, no letters, no interface.")

MATCH_ITEMS = ['a glossy blue fish', 'a coral-red ball of wool yarn with a loose strand', 'a small grey felt toy mouse with a coral nose and '
               'a curly string tail', 'a round golden biscuit stamped with a paw print', 'a bright green sprig of three catnip leaves',
               'a soft violet feather', 'a small open cardboard box with a black cat\'s ears and big amber eyes peeking over its rim',
               'a glowing round red laser dot with a soft warm halo and a few sparkles', 'a fluffy grey dust bunny ball of fluff',
               'a closed brown cardboard parcel tied with string', 'a closed brown cardboard parcel taped twice with a paw-print tape',
               'a loose tangle of teal wool strands in a rough ring, open in the middle']
MATCH_NAMES = ['fish', 'yarn', 'mouse', 'biscuit', 'catnip', 'feather', 'box', 'laser', 'dust', 'parcel1', 'parcel2', 'tangle']
MATCH_SHEET = ("A sprite sheet of twelve separate tiles for a cosy painted match-three puzzle game, laid out evenly in a 4 by 3 grid "
               "with plenty of empty space around each, every piece the same size in its cell and seen straight on, chunky glossy "
               "and instantly readable at a small size, each a different bold silhouette, in the exact painted finish of the "
               "references: {items}. " + STYLE + MAGENTA)
ROW_BOARD = ("A game board for a cosy painted four-in-a-row game, seen exactly straight on and filling the frame: a chunky upright "
             "board of warm honey-oak wood with rounded corners, a carved rim and a soft painted wood grain, with exactly seven "
             "columns and six rows of large round holes cut straight through it, evenly spaced in a neat grid, each hole showing "
             "flat pure cyan (#00FFFF) through it, a thin bevel round each hole's edge. " + STYLE +
             "Flat, solid pure magenta (#FF00FF) background around the board. No counters, no text, no letters, no numbers.")
ICON_ITEMS = ['an open honey-oak toy chest with a ball of yarn and a feather wand spilling over its edge',
              'a square cream puzzle card with a small grid and a yellow pencil across it',
              'a small golden fish-shaped cat biscuit', 'a small grey felt toy mouse with a coral nose and a string tail',
              'a bright green sprig of catnip leaves', 'a small open cardboard box',
              'a cat\'s feather-wand toy with a teal stick and coloured feathers', 'a brass magnifying glass',
              'a golden trophy cup with a paw print on it', 'two cat heads side by side, one black and one ginger',
              'a plump squashy teal cushion', 'a small wooden sand timer']
ICON_NAMES = ['games', 'puzzle', 'biscuit', 'mouse', 'catnip', 'box', 'wand', 'magnifier', 'trophy', 'two_cats', 'cushion', 'timer']
ICONS = ("A sprite sheet of twelve separate game interface icons in the exact painted style of the reference icon sheet, laid out "
         "evenly in a 4 by 3 grid with plenty of empty space around each, every icon the same size in its cell, simple bold "
         "readable shapes with a soft painted finish: {items}. " + STYLE + MAGENTA)

# Zoomies: four parts of the run, each a wide side-on stage the cat gallops across on three lanes, made to wrap
# left to right (cut.py cross-fades the edges, so they are kept plain).
RUN_BG = ("A wide side-scrolling background for a cosy painted endless-runner video game, landscape panorama, seen side on "
          "from a slightly raised angle like a stage: {scene} The ground fills the lower 45 percent of the picture, deep "
          "enough to show three running lanes one behind another, plain and uncluttered, with nothing standing on it. The "
          "far left and far right quarters are kept plain and similar so the picture can repeat side by side. No animals, "
          "no people, no foreground objects, no text. " + STYLE)
RUN_SCENES = {
    'run_hall': "the long hallway of a warm family home: apricot-cream wallpaper with a faint painted pattern, honey wood "
                "panelling along the bottom of the wall, a few small framed pictures and a wall lamp, honey wooden "
                "floorboards with a long faded striped runner rug along the floor.",
    'run_kitchen': "a sunny country kitchen: pale sage cupboards and a wooden worktop along the back wall with jars, a "
                   "window with gingham curtains, cream metro tiles above the worktop, a warm terracotta tiled floor.",
    'run_garden': "an English back garden on a sunny day: a red brick garden wall with climbing roses and ivy along the "
                  "back, a few shrubs, a soft blue sky above, a wide green lawn with a pale stone path along it.",
    'run_street': "a quiet street of painted terraced houses with colourful front doors and window boxes along the back, "
                  "railings, a wide pavement of pale flagstones in front with a kerb at the very bottom.",
}
RUN_THINGS = ['a neat stack of four hardback books', 'a pair of green wellington boots', 'a low wooden coffee table',
              'a round wicker laundry basket full of folded towels', 'a galvanised metal watering can',
              'a terracotta flower pot with red geraniums', 'a white sheet hanging from a short washing line between two '
              'wooden posts, its bottom edge well above the ground', 'a green wheelie bin',
              'a blue recycling box with paper in it', 'a wooden park bench', 'a parked bicycle with a basket',
              'a striped ironing board standing on its legs']
RUN_NAMES = ['books', 'boots', 'table', 'basket', 'can', 'pot', 'washing', 'bin', 'recycling', 'bench', 'bicycle', 'ironing']
RUN_SHEET = ("A sprite sheet of twelve separate objects for a cosy painted side-scrolling video game, laid out evenly in a 4 by 3 "
             "grid with plenty of empty space around each, every object seen from the side and slightly above (like the floor "
             "in the reference, which they will stand on), each standing upright on its own base, each a similar size in its "
             "cell: {items}. " + STYLE + MAGENTA)

# Catapult: a stage for each place on the map, empty, with flat ground along the bottom for the towers.
PLACE_BG = ("A wide background for a cosy painted side-on physics game, landscape panorama, seen side on at eye level: "
            "{scene} Along the bottom fifth of the picture a wide, flat, level open ground running edge to edge, completely "
            "empty, nothing standing on it. The middle and right of the picture are open and uncluttered so pieces can be "
            "placed there. No animals, no people, no text. " + STYLE)
PLACES = {
    'place_city': "the sunny back garden of a London brick terrace, a lawn along the bottom, a brick garden wall and the "
                  "backs of brick terraced houses with chimney pots behind, under a soft blue sky.",
    'place_coast': "a sunny seaside beach, golden sand along the bottom, a row of pastel beach huts and a calm blue sea "
                   "with a distant lighthouse behind, gulls far off in the sky.",
    'place_countryside': "an English farmyard in summer, a mown grassy yard along the bottom, a red barn, a dry-stone wall "
                         "and rolling green hills with hedgerows behind.",
    'place_mountain': "an alpine meadow high in the mountains, short grass and small stones along the bottom, a wooden "
                      "chalet to one side and snowy peaks and pine slopes behind under a clear sky.",
    'place_forest': "a sunny clearing in a deep green forest, a mossy forest floor along the bottom, tall trees, ferns and "
                    "shafts of sunlight behind.",
    'place_desert': "a warm courtyard in a desert town, smooth sand-coloured flagstones along the bottom, terracotta walls "
                    "with arched doorways, potted palms and a distant dune under a deep blue sky.",
    'place_tropical': "a tropical beach at golden hour, pale sand along the bottom, palm trees, a wooden beach shack with a "
                      "thatched roof and a turquoise lagoon behind.",
    'place_snow': "a snowy winter garden, smooth deep snow along the bottom, snow-covered fir trees and a log cabin with a "
                  "glowing window behind, under a pale winter sky.",
}
POUNCE_THINGS = ['a plain cardboard box seen exactly from the front, square', 'a wide flat cardboard box seen exactly from the '
                 'front, twice as wide as it is tall', 'a red hardback book lying flat, seen exactly from the side, its spine '
                 'facing you', 'a blue hardback book lying flat, seen exactly from the side, its spine facing you',
                 'a green hardback book lying flat, seen exactly from the side, its spine facing you',
                 'a long straight plain wooden plank seen exactly from the side, sixteen times as long as it is thick',
                 'a round biscuit tin seen exactly end-on as a perfect circle, painted with flowers',
                 'a terracotta flower pot seen exactly from the side', 'a plump squashy teal cushion seen exactly from the '
                 'side, three times as wide as it is tall', 'a small grey felt toy mouse with a coral nose seen from the side',
                 'a short carpeted cat tree with a round platform on top, seen from the side',
                 'a small square wooden crate seen exactly from the front']
POUNCE_NAMES = ['box', 'wide', 'book_red', 'book_blue', 'book_green', 'plank', 'tin', 'pot', 'cushion', 'mouse', 'tree', 'crate']
POUNCE_SHEET = ("A sprite sheet of twelve separate objects for a cosy painted side-on physics video game, laid out evenly in a 4 "
                "by 3 grid with plenty of empty space around each, every object seen exactly side on with straight square "
                "edges where it has them (they will be stacked into towers), each a similar size in its cell: {items}. "
                + STYLE + MAGENTA)
LEDGES = ['a short length of red brick garden wall with a stone coping on top', 'a block of grey stone sea wall',
          'a rectangular golden hay bale', 'a flat-topped grey granite boulder', 'a thick fallen mossy log seen from the side',
          'a flat-topped sandstone block', 'a low bamboo deck on short legs', 'a smooth rectangular bank of snow']
LEDGE_NAMES = ['ledge_city', 'ledge_coast', 'ledge_countryside', 'ledge_mountain', 'ledge_forest', 'ledge_desert',
               'ledge_tropical', 'ledge_snow']
LEDGE_SHEET = ("A sprite sheet of eight separate blocks for a cosy painted side-on physics video game, laid out evenly in a 4 by 2 "
               "grid with plenty of empty space around each, each seen exactly side on as a solid rectangular shape with a flat "
               "level top (things will stand on it), each about twice as wide as it is tall: {items}. " + STYLE + MAGENTA)


def requests(group):
    base = {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k"}
    tile_refs = [{"value": "cca85a1b-8493-4050-8fb9-d22489f82c02", "role": "image_references"},
                 {"value": "4aba412d-55ad-481c-ad91-53fa3cd51093", "role": "image_references"}]
    cat_ref = {"value": "3553b9b6-f365-401a-bae2-690ec15397a8", "role": "image_references"}
    style_ref = {"value": "146f85a0-4e76-48fa-8f66-22ca29bbbc5e", "role": "image_references"}
    if group == 'tiles':
        return [{**base, "aspect_ratio": "4:3", "prompt": prompt,
                 "medias": tile_refs + ([cat_ref] if 'black cat' in prompt else [])} for prompt in TILES.values()]
    if group == 'concepts':
        return [{**base, "aspect_ratio": "16:9", "medias": [style_ref, cat_ref], "prompt": p}
                for p in (ZOOMIES_SCENE, CATAPULT_SCENE)]
    if group == 'sheets':
        icon_ref = {"value": "5f71253c-186a-44fe-9616-7991313c4cde", "role": "image_references"}
        listed = lambda items: '; '.join(f'({i + 1}) {item}' for i, item in enumerate(items))
        return [{**base, "aspect_ratio": "4:3", "medias": tile_refs, "prompt": MATCH_SHEET.format(items=listed(MATCH_ITEMS))},
                {**base, "aspect_ratio": "4:3", "medias": tile_refs, "prompt": ROW_BOARD},
                {**base, "aspect_ratio": "4:3", "medias": [icon_ref], "prompt": ICONS.format(items=listed(ICON_ITEMS))}]
    listed = lambda items: '; '.join(f'({i + 1}) {item}' for i, item in enumerate(items))
    if group == 'run':
        return ([{**base, "aspect_ratio": "21:9", "medias": [style_ref], "prompt": RUN_BG.format(scene=scene)}
                 for scene in RUN_SCENES.values()]
                + [{**base, "aspect_ratio": "4:3", "medias": [{"value": "457ece40-c051-408e-988b-96a3b56530b8",
                                                                "role": "image_references"}, tile_refs[0]],
                    "prompt": RUN_SHEET.format(items=listed(RUN_THINGS))}])
    if group == 'places':
        return [{**base, "aspect_ratio": "21:9", "medias": [style_ref, {"value": "5846a10d-1d53-4178-9897-77bdeb4ab4cb",
                                                                     "role": "image_references"}],
                 "prompt": PLACE_BG.format(scene=scene)} for scene in PLACES.values()]
    if group == 'pounce':
        refs = [{"value": "5846a10d-1d53-4178-9897-77bdeb4ab4cb", "role": "image_references"}, tile_refs[0]]
        return [{**base, "aspect_ratio": "4:3", "medias": refs, "prompt": POUNCE_SHEET.format(items=listed(POUNCE_THINGS))},
                {**base, "aspect_ratio": "16:9", "medias": refs, "prompt": LEDGE_SHEET.format(items=listed(LEDGES))}]
    raise SystemExit(f'unknown group {group}')


if __name__ == '__main__':
    print(json.dumps(requests(sys.argv[2]), indent=1))

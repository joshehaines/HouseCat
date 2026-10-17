"""Builds Content/catalogue.json, gifts.json, outfits.json and seasons.json from assets/manifest.json
plus the hand-written tables below (names, affordances, pools, prices, descriptions).

Run from anywhere:  python3 -I tools/content/build_catalogue.py

Conventions
- Item id = <manifest room>_<manifest item>; sprites are manifest paths (relative to assets/), the primary
  (non-"_painted") sprite for each facing.
- motion pivots are fractions of the sprite in image space: (0, 0) = top-left, (1, 1) = bottom-right.
- fx carries the manifest motion_fx: anchor is in sprite pixels for the R sprite, anchorL for the L sprite.
"""
import json
import os
from collections import defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
MANIFEST = os.path.join(ROOT, 'assets', 'manifest.json')
OUT = os.path.join(ROOT, 'Content')


# ---------------------------------------------------------------- motion helpers
def static():
    return {"type": "static"}


def sway(px, py, period):
    return {"type": "sway", "pivot": [px, py], "period": period}


def glow(px, py, period):
    return {"type": "glow", "pivot": [px, py], "period": period}


def spin(px, py, period):
    return {"type": "spin", "pivot": [px, py], "period": period}


def frames(fx, n, period):
    return {"type": "frames", "fx": fx, "frames": n, "period": period}


FIRE = lambda: frames("fire", 8, 0.8)
CANDLE = lambda: frames("candle", 8, 0.8)
STEAM = lambda: frames("steam", 7, 0.7)

# The manifest calls both water effects "water"; fx/fx.json splits them.
WATER_FX = {('kitchen', 'fountain'): 'water_trickle', ('garden', 'pond'): 'water_ripple'}
# Items that need an fx anchor the manifest does not give (placeholder: set by eye in the room view).
EXTRA_FX = {('study', 'mug'): 'steam'}

# ---------------------------------------------------------------- item table
# (room, item): name, footprint (w, d), layer, decal, affordances, capacity, motion, catPose, description
F, W = 'floor', 'wall'
ITEMS = {
    # ---- living (16)
    ('living', 'sofa'): ("Sagging sofa", (3, 1), F, False, ["sit", "sleep"], 2, static(), "loaf_side",
                         "Sags in the middle, which is exactly where the cat sleeps."),
    ('living', 'armchair'): ("Armchair", (1, 1), F, False, ["sit"], 1, static(), "loaf_tqfront",
                             "Your chair, in theory."),
    ('living', 'rug'): ("Wool rug", (3, 2), F, True, ["sleep"], 1, static(), "sleep_curl",
                        "Thick wool. The cat regards it as a mattress with ambitions."),
    ('living', 'lamp'): ("Floor lamp", (1, 1), F, False, ["none"], 0, glow(0.5, 0.15, 6.0), None,
                         "A tall lamp that makes the whole room look kinder."),
    ('living', 'bookcase'): ("Bookshelf", (2, 1), F, False, ["perch"], 1, static(), "loaf_side",
                             "Holds books until the cat decides otherwise."),
    ('living', 'coffee'): ("Coffee table", (2, 1), F, False, ["perch"], 1, static(), "loaf_tqfront",
                           "Low table for mugs, magazines and a cat lying across both."),
    ('living', 'box'): ("Cardboard box", (1, 1), F, False, ["hide"], 1, static(), "loaf_tqfront",
                        "The most popular piece of furniture in the house. It is a box."),
    ('living', 'scratch'): ("Scratching post", (1, 1), F, False, ["scratch"], 1, static(), "stretch_side",
                            "Sisal-wrapped and sacrificial. The sofa is grateful."),
    ('living', 'windowseat'): ("Window-seat cushion", (2, 1), F, False, ["sit", "watch"], 1, static(), "sit_back",
                               "A long mustard cushion by the glass, for watching the street."),
    ('living', 'radiator'): ("Radiator seat", (2, 1), F, False, ["sleep"], 1, glow(0.5, 0.5, 8.0), "loaf_side",
                             "Old cast iron, painted cream, permanently occupied."),
    ('living', 'record'): ("Record player", (2, 1), F, False, ["none"], 0, spin(0.45, 0.3, 1.8), None,
                           "Turns at a steady pace. The cat watches every rotation."),
    ('living', 'plant'): ("Houseplant", (1, 1), F, False, ["bat"], 1, sway(0.5, 0.9, 5.0), None,
                          "A large leafy plant with one leaf already missing."),
    ('living', 'fireplace'): ("Fireplace", (2, 1), F, False, ["sleep"], 1, FIRE(), "sleep_curl",
                              "A small tiled hearth. Whatever sits in front of it becomes a bed."),
    ('living', 'cattree'): ("Cat tree", (1, 1), F, False, ["perch", "sleep"], 2, static(), "sit_tqfront",
                            "Carpeted platforms at several heights, for looking down on you."),
    ('living', 'clock'): ("Wall clock", (1, 1), W, False, ["none"], 0, spin(0.5, 0.5, 60.0), None,
                          "Tells the time. The cat prefers to tell you itself."),
    ('living', 'picture'): ("Picture frame", (1, 1), W, False, ["none"], 0, static(), None,
                            "A framed print. The cat has no opinion. Yet."),
    # ---- bedroom (14)
    ('bedroom', 'bed'): ("Double bed", (2, 3), F, False, ["sleep"], 2, static(), "sleep_curl",
                         "A double bed. You are allotted a third of it."),
    ('bedroom', 'bedside'): ("Bedside table", (1, 1), F, False, ["perch"], 1, static(), "sit_side",
                             "Holds a lamp, a glass of water and, briefly, a cat."),
    ('bedroom', 'wardrobe'): ("Wardrobe", (2, 1), F, False, ["hide"], 1, static(), None,
                              "Two doors, one always slightly open. You know why."),
    ('bedroom', 'laundry'): ("Laundry basket", (1, 1), F, False, ["hide"], 1, static(), "loaf_tqfront",
                             "A wicker basket of clean washing. Was clean."),
    ('bedroom', 'readinglamp'): ("Reading lamp", (1, 1), F, False, ["none"], 0, glow(0.5, 0.2, 6.0), None,
                                 "Brass and green glass. Good light to read by, or nap under."),
    ('bedroom', 'curtains'): ("Curtains", (2, 1), W, False, ["none"], 0, sway(0.5, 0.0, 6.0), None,
                              "Long sage curtains on a brass pole. Climbable, in theory."),
    ('bedroom', 'drawers'): ("Chest of drawers", (2, 1), F, False, ["perch"], 1, static(), "loaf_side",
                             "Three drawers of jumpers and a top made for sitting on."),
    ('bedroom', 'catbed'): ("Cat bed", (1, 1), F, False, ["sleep"], 1, static(), "sleep_curl",
                            "A round plush bed made for the cat, who prefers yours."),
    ('bedroom', 'slippers'): ("Slippers", (1, 1), F, False, ["bat"], 1, static(), None,
                              "Fluffy pink slippers. One of them will go missing."),
    ('bedroom', 'mirror'): ("Oval mirror", (1, 1), W, False, ["watch"], 1, static(), "sit_back",
                            "A tall oval mirror. The cat finds the other cat suspicious."),
    ('bedroom', 'gownhook'): ("Dressing-gown hook", (1, 1), W, False, ["none"], 0, static(), None,
                              "A dressing gown on a brass hook. Smells reassuringly of you."),
    ('bedroom', 'hammock'): ("Cat hammock", (2, 1), F, False, ["sleep"], 1, sway(0.5, 0.1, 4.0), "sleep_curl",
                             "A teal canvas sling for a cat who likes to be held up."),
    ('bedroom', 'alarmclock'): ("Alarm clock", (1, 1), F, False, ["bat"], 1, static(), None,
                                "Twin bells and a loud tick. Due to be knocked off something."),
    ('bedroom', 'bedrug'): ("Bedroom rug", (3, 2), F, True, ["sleep"], 1, static(), "sleep_curl",
                            "A soft sage rug by the bed. The cat lands on it by gravity."),
    # ---- kitchen (14)
    ('kitchen', 'bowl'): ("Food bowl", (1, 1), F, False, ["eat"], 1, static(), None,
                          "The cat's bowl. The most important object in the house."),
    ('kitchen', 'fountain'): ("Water fountain", (1, 1), F, False, ["eat"], 1, frames("water_trickle", 4, 0.5), None,
                              "A trickling fountain, because still water is beneath them."),
    ('kitchen', 'table'): ("Kitchen table", (2, 2), F, False, ["perch"], 1, static(), "sit_tqfront",
                           "A square pine table. Strictly off limits, according to you."),
    ('kitchen', 'chair'): ("Kitchen chair", (1, 1), F, False, ["sit"], 1, static(), "sit_side",
                           "Spindle-backed pine. Warm if you've just got up."),
    ('kitchen', 'fridge'): ("Fridge", (1, 1), F, False, ["none"], 0, glow(0.5, 0.4, 3.0), None,
                            "Rounded, cream and full of things the cat has opinions about."),
    ('kitchen', 'kettle'): ("Kettle", (1, 1), F, False, ["none"], 0, STEAM(), None,
                            "A mint stove-top kettle. Whistles, steams, gets stared at."),
    ('kitchen', 'herbshelf'): ("Herb shelf", (1, 1), W, False, ["none"], 0, sway(0.5, 0.8, 5.0), None,
                               "Three pots of herbs on a little shelf. One has been nibbled."),
    ('kitchen', 'breadbin'): ("Bread bin", (1, 1), F, False, ["hide"], 1, static(), None,
                              "Cream enamel with a wooden lid. Fits a loaf. Fits a cat."),
    ('kitchen', 'fruitbowl'): ("Fruit bowl", (1, 1), F, False, ["bat"], 1, static(), None,
                               "Lemons and oranges, ideal for rolling off things."),
    ('kitchen', 'cooker'): ("Cooker", (1, 1), F, False, ["none"], 0, static(), None,
                            "Four rings and a chrome rail. Off limits, always."),
    ('kitchen', 'catflap'): ("Cat flap", (1, 1), W, False, ["none"], 0, static(), None,
                             "A door within a door. Used entirely at the cat's discretion."),
    ('kitchen', 'radio'): ("Radio", (1, 1), F, False, ["none"], 0, static(), None,
                           "A little cream and mint radio. Plays music, scatters notes."),
    ('kitchen', 'doormat'): ("Door mat", (2, 1), F, True, ["sleep"], 1, static(), "sleep_curl",
                             "Coir, scratchy and inexplicably popular for naps."),
    ('kitchen', 'sink'): ("Sink", (2, 1), F, False, ["perch"], 1, static(), "loaf_tqfront",
                          "A white sink in a pine unit. Apparently also a bed."),
    # ---- garden (12)
    ('garden', 'bench'): ("Garden bench", (2, 1), F, False, ["sit"], 2, static(), "loaf_side",
                          "Weathered oak with room for two. Mostly used by one."),
    ('garden', 'sunpatch'): ("Sunbeam spot", (2, 2), F, True, ["sleep"], 1, glow(0.5, 0.5, 8.0), "stretch_side",
                             "A warm patch of sunlight. Turns up only when the sun does."),
    ('garden', 'birdfeeder'): ("Bird feeder", (1, 1), F, False, ["watch"], 1, frames("robin", 8, 6.0), "sit_back",
                               "Seed on a tall post. Popular with birds and their audience."),
    ('garden', 'flowerpots'): ("Flower pots", (1, 1), F, False, ["none"], 0, sway(0.5, 0.9, 5.0), None,
                               "Three terracotta pots of geraniums, nodding along."),
    ('garden', 'wateringcan'): ("Watering can", (1, 1), F, False, ["none"], 0, static(), None,
                                "A green metal watering can. Mostly decorative."),
    ('garden', 'deckchair'): ("Deck chair", (1, 2), F, False, ["sit"], 1, static(), "loaf_tqfront",
                              "Striped canvas in teal and cream. You'll be lucky to get it."),
    ('garden', 'shed'): ("Garden shed", (2, 2), F, False, ["hide"], 1, static(), None,
                         "A little sage-green shed with a window and many hiding places."),
    ('garden', 'fence'): ("Picket fence", (3, 1), F, False, ["perch"], 1, static(), "sit_side",
                          "A run of white pickets, for walking along smugly."),
    ('garden', 'pond'): ("Pond", (2, 2), F, True, ["watch"], 1, frames("water_ripple", 4, 0.5), "sit_side",
                         "Two water lilies and a great many things worth staring at."),
    ('garden', 'festoon'): ("Festoon lights", (3, 1), W, False, ["none"], 0, glow(0.5, 0.5, 5.0), None,
                            "Round warm bulbs strung in a lazy curve along the wall."),
    ('garden', 'gardenhammock'): ("Rope hammock", (3, 1), F, False, ["sleep"], 1, sway(0.5, 0.2, 4.0), "sleep_curl",
                                  "Strung between two posts. Sways gently under a sleeping cat."),
    ('garden', 'washingline'): ("Washing line", (3, 1), F, False, ["none"], 0, sway(0.5, 0.2, 4.0), None,
                                "Clothes pegged out to dry. One sock is at risk."),
    # ---- study (12)
    ('study', 'desk'): ("Writing desk", (2, 1), F, False, ["perch"], 1, static(), "loaf_side",
                        "Pale oak with one drawer. The cat sits wherever you type."),
    ('study', 'officechair'): ("Office chair", (1, 1), F, False, ["sit"], 1, spin(0.5, 0.6, 8.0), "sit_tqfront",
                               "A mustard swivel chair. Turns when nobody is looking."),
    ('study', 'laptop'): ("Laptop", (1, 1), F, False, ["perch"], 1, glow(0.5, 0.3, 4.0), "loaf_tqfront",
                          "Warm, glowing and the ideal place for a cat to help."),
    ('study', 'bookshelf'): ("Tall bookshelf", (2, 1), F, False, ["perch"], 1, static(), "loaf_side",
                             "Floor-to-ceiling walnut with a small globe on top."),
    ('study', 'papertray'): ("Paper tray", (1, 1), F, False, ["sleep"], 1, static(), "loaf_side",
                             "An in-tray, mostly full of cat."),
    ('study', 'desklamp'): ("Desk lamp", (1, 1), F, False, ["none"], 0, glow(0.5, 0.25, 6.0), None,
                            "Green glass and brass. A soft glow over the paperwork."),
    ('study', 'globe'): ("Globe", (1, 1), F, False, ["none"], 0, spin(0.5, 0.4, 20.0), None,
                         "A vintage globe on a brass stand. Turns with one nudge."),
    ('study', 'filing'): ("Filing cabinet", (1, 1), F, False, ["hide"], 1, static(), None,
                          "Two drawers of paperwork and one very good hiding place."),
    ('study', 'printer'): ("Printer", (1, 1), F, False, ["perch"], 1, static(), "loaf_side",
                           "Prints occasionally, warm always. The cat approves of warm."),
    ('study', 'noticeboard'): ("Noticeboard", (1, 1), W, False, ["none"], 0, static(), None,
                               "Cork, pinned with notes and a postcard. Pins are not toys."),
    ('study', 'mug'): ("Mug of tea", (1, 1), F, False, ["bat"], 1, STEAM(), None,
                       "A large mug of tea, left far too close to the edge."),
    ('study', 'blind'): ("Roller blind", (1, 1), W, False, ["none"], 0, sway(0.5, 0.0, 6.0), None,
                         "A cream roller blind, half drawn and gently swinging."),
    # ---- attic (12)
    ('attic', 'trunk'): ("Old trunk", (2, 1), F, False, ["hide"], 1, static(), "loaf_tqfront",
                         "Leather, brass corners, faded stickers, lid ajar."),
    ('attic', 'dustyarmchair'): ("Dusty armchair", (1, 1), F, False, ["sit"], 1, static(), "loaf_tqfront",
                                 "Faded rose velvet under a half-pulled dust sheet."),
    ('attic', 'skylightpatch'): ("Skylight beam", (2, 2), F, True, ["sleep"], 1, glow(0.5, 0.5, 8.0), "stretch_side",
                                 "A square of sunlight under the skylight. Sunny days only."),
    ('attic', 'boxes'): ("Stacked boxes", (1, 1), F, False, ["perch", "hide"], 1, static(), "sit_tqfront",
                         "Three old boxes, the top one open. A lookout and a den."),
    ('attic', 'rockinghorse'): ("Rocking horse", (2, 1), F, False, ["none"], 0, sway(0.5, 1.0, 3.0), None,
                                "A painted wooden horse that rocks when brushed against."),
    ('attic', 'dummy'): ("Dressmaker's dummy", (1, 1), F, False, ["none"], 0, static(), None,
                         "A dressmaker's dummy. The cat has never trusted it."),
    ('attic', 'telescope'): ("Telescope", (1, 1), F, False, ["watch"], 1, static(), "sit_back",
                             "Brass, on a wooden tripod. Excellent for watching birds."),
    ('attic', 'rolledrug'): ("Rolled rug", (3, 1), F, False, ["sleep"], 1, static(), "loaf_side",
                             "Rolled up and tied with string. Better than unrolled."),
    ('attic', 'oillamp'): ("Oil lamp", (1, 1), F, False, ["none"], 0, CANDLE(), None,
                           "An antique oil lamp, lit, on a little round table."),
    ('attic', 'cobweb'): ("Cobweb corner", (1, 1), W, False, ["bat"], 1, sway(0.5, 0.0, 7.0), None,
                          "A silvery cobweb high in the corner. Someone's favourite."),
    ('attic', 'suitcase'): ("Suitcase", (1, 1), F, False, ["hide"], 1, static(), "loaf_tqfront",
                            "An old leather suitcase. Open it and the cat moves in."),
    ('attic', 'wireless'): ("Old wireless", (1, 1), F, False, ["none"], 0, static(), None,
                            "A big wooden wireless that hums as it warms up."),
    # ---- Housewarming season (8)
    ('pass_housewarming', 'movingboxes'): ("Moving boxes", (1, 1), F, False, ["hide", "perch"], 1, static(), "sit_tqfront",
                                           "Two sealed moving boxes. Not sealed for long."),
    ('pass_housewarming', 'teachest'): ("Tea chest", (1, 1), F, False, ["hide", "perch"], 1, static(), "sit_side",
                                        "A wooden tea chest with stencilled letters. Smells faintly of tea."),
    ('pass_housewarming', 'painttins'): ("Paint tins", (1, 1), F, False, ["bat"], 1, static(), None,
                                         "Sage, mustard and cream. One lid is off. Paws clear, please."),
    ('pass_housewarming', 'stepladder'): ("Step ladder", (1, 1), F, False, ["perch"], 1, static(), "sit_side",
                                          "A wooden step ladder, for pictures, shelves and surveillance."),
    ('pass_housewarming', 'fairylights'): ("Fairy lights", (3, 1), W, False, ["none"], 0, glow(0.5, 0.5, 5.0), None,
                                           "Tiny warm lights draped in two swags along the wall."),
    ('pass_housewarming', 'picnicblanket'): ("Picnic blanket", (3, 2), F, True, ["sleep"], 1, static(), "stretch_side",
                                             "A checked blanket on the floor of a house with no table yet."),
    ('pass_housewarming', 'takeaway'): ("Takeaway bag", (1, 1), F, False, ["hide"], 1, static(), None,
                                        "First-night takeaway. The paper bag is the real prize."),
    ('pass_housewarming', 'candle'): ("Scented candle", (1, 1), F, False, ["none"], 0, CANDLE(), None,
                                      "A scented candle in amber glass. Smells like a new home."),
    # ---- Midwinter season (8)
    ('pass_midwinter', 'knitblanket'): ("Knitted blanket", (2, 1), F, False, ["sleep"], 1, static(), "sleep_curl",
                                        "A chunky cream knit, folded once. It won't stay folded."),
    ('pass_midwinter', 'logbasket'): ("Log basket", (1, 1), F, False, ["perch"], 1, static(), "loaf_side",
                                      "A wicker basket of split logs, ready for the fire."),
    ('pass_midwinter', 'wreath'): ("Wreath", (1, 1), W, False, ["none"], 0, static(), None,
                                   "Fir, berries and a tartan bow, hung at a batting height."),
    ('pass_midwinter', 'mulledwine'): ("Spiced mugs", (1, 1), F, False, ["none"], 0, STEAM(), None,
                                       "Two steaming mugs with orange slices. Not for cats."),
    ('pass_midwinter', 'snowglobe'): ("Snow globe", (1, 1), F, False, ["bat"], 1, static(), None,
                                      "A tiny cottage under glass. Shake it and it snows indoors."),
    ('pass_midwinter', 'firtree'): ("Fir tree", (1, 1), F, False, ["hide", "bat"], 1, glow(0.5, 0.45, 4.0), None,
                                    "A small potted fir with warm lights and very tempting baubles."),
    ('pass_midwinter', 'sledge'): ("Sledge", (1, 1), F, False, ["none"], 0, static(), None,
                                   "A wooden sledge leaning on the wall, waiting for its moment."),
    ('pass_midwinter', 'hotwaterbottle'): ("Hot-water bottle", (1, 1), F, False, ["sleep"], 1, static(), "sleep_curl",
                                           "In a knitted cover. The cat will claim it before you do."),
    # ---- First Light season (8)
    ('pass_firstlight', 'seedtrays'): ("Seed trays", (2, 1), F, False, ["none"], 0, static(), None,
                                       "Seedlings in little pots. Not, despite appearances, a litter tray."),
    ('pass_firstlight', 'birdbox'): ("Bird box", (1, 1), W, False, ["watch"], 1, static(), "sit_back",
                                     "A small wooden bird box. The cat has applied to be a tenant."),
    ('pass_firstlight', 'tulips'): ("Tulip pot", (1, 1), F, False, ["none"], 0, sway(0.5, 0.9, 5.0), None,
                                    "Red and yellow tulips in terracotta. For looking at, not nibbling."),
    ('pass_firstlight', 'pegbag'): ("Peg bag", (1, 1), W, False, ["bat"], 1, sway(0.5, 0.0, 5.0), None,
                                    "A floral peg bag on a hook, full of pegs worth batting about."),
    ('pass_firstlight', 'hamper'): ("Picnic hamper", (1, 1), F, False, ["hide"], 1, static(), "loaf_tqfront",
                                    "A wicker hamper, lid open, contents under review."),
    ('pass_firstlight', 'butterflyjar'): ("Butterfly jar", (1, 1), F, False, ["watch"], 1, frames("butterfly", 8, 0.8), "sit_side",
                                          "A glass jar with a blue butterfly resting on the rim."),
    ('pass_firstlight', 'wellies'): ("Wellies", (1, 1), F, False, ["bat"], 1, static(), None,
                                     "Yellow wellington boots. One of them has a cat in it."),
    ('pass_firstlight', 'daffodils'): ("Daffodil jug", (1, 1), F, False, ["none"], 0, sway(0.5, 0.9, 5.0), None,
                                       "A blue enamel jug of daffodils. Cheerful, and best admired."),
    # ---- Housewarming launch pack (6)
    ('housewarming_pack', 'grandfireplace'): ("Grand fireplace", (2, 1), F, False, ["sleep"], 1, FIRE(), "sleep_curl",
                                              "Marble, a mantel clock and a proper fire. The grandest bed going."),
    ('housewarming_pack', 'hifi'): ("Hi-fi console", (2, 1), F, False, ["perch"], 1, spin(0.4, 0.3, 1.8), "loaf_side",
                                    "Walnut, with a turntable and two speakers. Warm on top."),
    ('housewarming_pack', 'bulbstring'): ("String of bulbs", (3, 1), W, False, ["none"], 0, glow(0.5, 0.5, 5.0), None,
                                          "Big round warm bulbs strung along the wall."),
    ('housewarming_pack', 'welcomemat'): ("Welcome mat", (2, 1), F, True, ["sleep"], 1, static(), "sleep_curl",
                                          "Coir, and it says WELCOME. The cat agrees, selectively."),
    ('housewarming_pack', 'champagne'): ("Ice bucket", (1, 1), F, False, ["none"], 0, static(), None,
                                         "Brass ice bucket on a stand with two glasses. To the new house."),
    ('housewarming_pack', 'houseportrait'): ("House portrait", (1, 1), W, False, ["none"], 0, static(), None,
                                             "A little terraced house in a gilt frame. Home, framed."),
    # ---- Founders' plaque (3)
    ('founders', 'plaque_brass'): ("Founders' plaque, brass", (1, 1), W, False, ["none"], 0, static(), None,
                                   "Polished brass with a cat silhouette and your founder's number."),
    ('founders', 'plaque_slate'): ("Founders' plaque, slate", (1, 1), W, False, ["none"], 0, static(), None,
                                   "Blue-grey slate, brass screws, and your founder's number."),
    ('founders', 'plaque_oak'): ("Founders' plaque, oak", (1, 1), W, False, ["none"], 0, static(), None,
                                 "Carved honey oak with a cat silhouette and your founder's number."),
}

# ---------------------------------------------------------------- pools for the 80 room items
FREE = ['kitchen_bowl', 'living_sofa', 'living_rug', 'living_box', 'living_lamp', 'living_scratch',
        'living_plant', 'living_picture']

# id: (level, beans)
BEANS = {
    # level 1 (8): the first living room plus a bed for the bedroom at level 2; 30-60 so 150 buys 3-4
    'living_clock': (1, 30), 'living_coffee': (1, 35), 'bedroom_catbed': (1, 40), 'living_windowseat': (1, 40),
    'living_bookcase': (1, 45), 'living_armchair': (1, 50), 'bedroom_bed': (1, 60), 'living_cattree': (1, 60),
    # level 3 (8): bedroom and kitchen basics
    'bedroom_bedside': (3, 80), 'kitchen_chair': (3, 80), 'kitchen_radio': (3, 90), 'bedroom_drawers': (3, 120),
    'kitchen_table': (3, 120), 'bedroom_wardrobe': (3, 150), 'kitchen_sink': (3, 150), 'kitchen_cooker': (3, 180),
    # level 6 (8): garden, the way out to it, and the fridge
    'garden_wateringcan': (6, 120), 'garden_fence': (6, 150), 'kitchen_catflap': (6, 150), 'garden_birdfeeder': (6, 180),
    'garden_bench': (6, 200), 'garden_sunpatch': (6, 250), 'kitchen_fridge': (6, 300), 'garden_shed': (6, 350),
    # level 9 (6): study basics plus two attic pieces to have ready for level 12
    'study_officechair': (9, 300), 'study_filing': (9, 350), 'attic_boxes': (9, 350), 'study_desk': (9, 400),
    'study_bookshelf': (9, 500), 'attic_trunk': (9, 600),
}

SETS = [
    # id, name, outfit, wallpaper, floor, items (7)
    ('rainy_london', "Rainy London", 'raincoat', 'wall_study_navy_pinstripe', 'floor_kitchen_slate',
     ['living_radiator', 'kitchen_kettle', 'kitchen_doormat', 'bedroom_curtains', 'bedroom_gownhook',
      'bedroom_laundry', 'study_blind']),
    ('cottagecore', "Cottagecore", 'cardigan', 'wall_bedroom_toile_blue', 'floor_bedroom_rose_carpet',
     ['kitchen_herbshelf', 'kitchen_breadbin', 'garden_flowerpots', 'garden_washingline', 'bedroom_bedrug',
      'attic_dummy', 'attic_rockinghorse']),
    ('midnight', "Midnight", 'pyjamas', 'wall_bedroom_starry_dusk', 'floor_study_dark_parquet',
     ['living_record', 'bedroom_readinglamp', 'bedroom_mirror', 'bedroom_alarmclock', 'bedroom_hammock',
      'attic_telescope', 'attic_cobweb']),
    ('cosy_study', "Cosy Study", 'roundglasses', 'wall_study_antique_map', 'floor_study_green_carpet',
     ['study_desklamp', 'study_globe', 'study_laptop', 'study_mug', 'study_noticeboard', 'study_printer',
      'study_papertray']),
    ('riviera', "Riviera", 'sunglasses', 'wall_kitchen_lemon_print', 'floor_living_terracotta',
     ['garden_deckchair', 'garden_gardenhammock', 'garden_festoon', 'garden_pond', 'kitchen_fountain',
      'kitchen_fruitbowl', 'attic_suitcase']),
    ('cabin', "Cabin", 'beanie', 'wall_attic_pine_planks', 'floor_attic_rough_pine',
     ['living_fireplace', 'attic_dustyarmchair', 'attic_oillamp', 'attic_rolledrug', 'attic_skylightpatch',
      'attic_wireless', 'bedroom_slippers']),
]

# season id -> (folder, free items, paid items, free outfit, paid outfit)
SEASON_ITEMS = {
    'housewarming': ('pass_housewarming', ['movingboxes', 'painttins', 'takeaway'],
                     ['fairylights', 'teachest', 'picnicblanket', 'stepladder', 'candle'], 'antlers', 'santahat'),
    'midwinter': ('pass_midwinter', ['logbasket', 'hotwaterbottle', 'wreath'],
                  ['knitblanket', 'sledge', 'snowglobe', 'mulledwine', 'firtree'], 'scarf', 'fisherman'),
    'firstlight': ('pass_firstlight', ['seedtrays', 'wellies', 'pegbag'],
                   ['tulips', 'birdbox', 'hamper', 'daffodils', 'butterflyjar'], 'bandana', 'flowercrown'),
}

# ---------------------------------------------------------------- surfaces
SURFACE_NAMES = {
    'bluegrey_shiplap': "Blue-grey shiplap", 'toile_blue': "Blue toile", 'picket_sky': "Picket and sky",
    'oak_panel': "Oak panelling", 'checker': "Chequerboard", 'quarry': "Quarry tiles", 'slate': "Slate tiles",
    'encaustic': "Encaustic tiles", 'terracotta': "Terracotta tiles", 'herringbone': "Herringbone",
    'chevron': "Chevron parquet", 'cork': "Cork tiles", 'sisal': "Sisal matting", 'whitewash': "Whitewashed boards",
    'birch': "Birch boards", 'cherry': "Cherry boards", 'green_tiles': "Green tiles", 'tartan': "Tartan",
    'apricot_houses': "Apricot houses", 'primrose_daffodil': "Primrose and daffodil", 'mint_lino': "Mint lino",
    'white_boards': "White boards", 'grey_boards': "Grey boards", 'worn_oak': "Worn oak boards",
    'rough_pine': "Rough pine boards", 'dusty_boards': "Dusty boards", 'pale_oak': "Pale oak boards",
}
# Three of each kind free per room; the rest Beans, a set's, or a season's.
FREE_SURFACES = {
    'living': (['powder_lemon', 'sage_limewash', 'terracotta_damask'], ['walnut_boards', 'sage_carpet', 'herringbone']),
    'bedroom': (['oat_linen', 'lavender_stripe', 'blush_floral'], ['cream_carpet', 'pale_oak', 'white_boards']),
    'kitchen': (['cream_beadboard', 'metro_tiles', 'mint_gingham'], ['checker', 'quarry', 'mint_lino']),
    'garden': (['picket_sky', 'old_brick', 'privet_hedge'], ['lawn', 'gravel', 'flagstones']),
    'study': (['ochre_linen', 'forest_green', 'oak_panel'], ['worn_oak', 'grey_boards', 'cork']),
    'attic': (['rough_plaster', 'whitewashed_brick', 'bluegrey_shiplap'], ['dusty_boards', 'whitewash', 'sisal']),
}
BEAN_SURFACES = {
    'wall_kitchen_terracotta_tiles': 150, 'wall_garden_ivy_trellis': 200, 'wall_garden_drystone': 200,
    'wall_attic_faded_rose': 250, 'floor_bedroom_chevron': 150, 'floor_kitchen_encaustic': 150,
    'floor_garden_decking': 200, 'floor_garden_brick_paving': 200, 'floor_attic_chalk_blue': 250,
}

# ---------------------------------------------------------------- outfits
OUTFITS = {
    # id: name, slot, pool, earnedBy, months
    'beanie': ("Beanie", 'head', 'paid', None, []),
    'flatcap': ("Flat cap", 'head', 'paid', None, []),
    'buckethat': ("Bucket hat", 'head', 'earned', 'referral', []),
    'partyhat': ("Party hat", 'head', 'earned', 'launch_event', []),
    'bandana': ("Blue bandana", 'neck', 'pass-free', None, []),
    'scarf': ("Mustard scarf", 'neck', 'pass-free', None, []),
    'bowtie': ("Green bow tie", 'neck', 'earned', 'streak_100', []),
    'roundglasses': ("Round glasses", 'head', 'paid', None, []),
    'sunglasses': ("Sunglasses", 'head', 'paid', None, []),
    'flowercrown': ("Flower crown", 'head', 'pass-paid', None, []),
    'pumpkinhat': ("Pumpkin hat", 'head', 'paid', None, [10]),
    'santahat': ("Santa hat", 'head', 'pass-paid', None, [12]),
    'antlers': ("Antlers", 'head', 'pass-free', None, [12]),
    'crown': ("Small crown", 'head', 'founders', None, []),
    'fisherman': ("Fisherman's jumper", 'body', 'pass-paid', None, []),
    'raincoat': ("Raincoat", 'body', 'paid', None, []),
    'hoodie': ("Hoodie", 'body', 'earned', 'streak_30', []),
    'xmasjumper': ("Christmas jumper", 'body', 'paid', None, [12]),
    'pyjamas': ("Pyjamas", 'body', 'paid', None, []),
    'cardigan': ("Cardigan", 'body', 'paid', None, []),
    'hawaiian': ("Hawaiian shirt", 'body', 'paid', None, []),
    'lifevest': ("Life jacket", 'body', 'paid', None, []),
    'skeleton': ("Skeleton onesie", 'body', 'paid', None, [10]),
}

# ---------------------------------------------------------------- gifts
# manifest stem after gift_<category>_ : (name, rarity, months, description)
GIFTS = {
    'keepsakes': {
        'acorn': ("Acorn", 'common', [], "Rolls in a perfect circle. I have tested this extensively."),
        'blue_bird_feather': ("Blue feather", 'uncommon', [], "A blue feather. The bird is fine. Probably."),
        'brass_key': ("Brass key", 'legendary', [], "It opens something. I'm not telling you what."),
        'heart_shaped_pebble': ("Heart-shaped pebble", 'uncommon', [], "I chose it for the shape. Read into that what you like."),
        'little_ceramic_fish': ("Ceramic fish", 'rare', [], "The only fish I've ever caught that stayed still."),
        'marble': ("Marble", 'uncommon', [], "Perfectly round. Rolls under everything. A real treasure."),
        'old_coin_with_no_lettering': ("Old coin", 'rare', [], "Worn smooth and heavy for its size. Found it, kept it, gave it."),
        'pearl_earring': ("Pearl earring", 'legendary', [], "Only the one. The other is somewhere you'll never find it."),
        'pressed_flower': ("Pressed flower", 'uncommon', [], "Flattened by me, personally, over one long nap."),
        'sea_glass': ("Sea glass", 'rare', [], "Smoothed by the sea, carried in by me. Equal effort."),
        'small_seashell': ("Small seashell", 'uncommon', [], "Hold it to your ear. It sounds like me purring."),
        'tiny_silver_bell': ("Tiny silver bell", 'rare', [], "It rang whenever I moved. I've removed it from my life."),
    },
    'oddities': {
        'a_single_shoelace': ("Single shoelace", 'common', [], "Just the lace. The shoe was too heavy."),
        'autumn_leaf': ("Crunchy leaf", 'common', [], "Crunched it twice to be sure. Still good."),
        'bottle_cap': ("Bottle cap", 'common', [], "Slides beautifully on a hard floor. Try it."),
        'button': ("Button", 'common', [], "It was on your coat. Now it's on the floor. Progress."),
        'crumpled_receipt_with_no_writing': ("Crumpled paper", 'common', [], "Crumpled to perfection. The crinkle is the whole point."),
        'hair_bobble': ("Hair bobble", 'uncommon', [], "Yours. I'm keeping it in circulation."),
        'odd_stripy_sock': ("Odd stripy sock", 'uncommon', [], "I've kept the other one. You get half."),
        'paper_clip': ("Paper clip", 'common', [], "Bent slightly. My work."),
        'pebble': ("Pebble", 'common', [], "It's grey, it's round and it's yours."),
        'pen_lid': ("Pen lid", 'common', [], "You were looking for this. I was hiding it. We're even."),
        'twig': ("Twig", 'common', [], "A stick of great importance. Do not throw it away."),
        'very_flat_old_toy_mouse': ("Very flat toy mouse", 'legendary', [], "My oldest friend. Loved flat. Handle with respect."),
    },
    'seasonal': {
        'candy_cane': ("Candy cane", 'uncommon', [12], "Stripy and hooked. It was on the tree until recently."),
        'cherry_blossom_twig': ("Blossom twig", 'uncommon', [4, 5], "Pink petals on a twig. I only shook off half of them."),
        'chocolate_coin_in_gold_foil_with_no_lettering': ("Chocolate coin", 'rare', [12], "Gold foil, chocolate inside. Not for cats. For you."),
        'conker': ("Conker", 'common', [9, 10], "Shiny, brown and bats beautifully across the floor."),
        'daffodil_head': ("Daffodil head", 'common', [2, 3], "Just the flower part. I've edited it for you."),
        'easter_egg': ("Easter egg", 'uncommon', [3, 4], "Rolled it all the way here. Didn't eat it. Wasn't allowed."),
        'holly_sprig': ("Holly sprig", 'common', [12], "Prickly, festive and mine for about a minute."),
        'mini_pumpkin': ("Mini pumpkin", 'common', [10], "Small, orange and heavy. I pushed it all the way."),
        'pine_cone': ("Pine cone", 'common', [11, 12], "Scaly, crunchy, excellent for batting under furniture."),
        'snowflake_ornament': ("Snowflake ornament", 'rare', [1, 2], "Came off the tree with a little help. It sparkles."),
        'sparkler': ("Sparkler", 'common', [11], "Unlit, obviously. I just like the look of it."),
        'tiny_paper_lantern': ("Paper lantern", 'common', [6, 7, 8], "Light as a whisker. Swings when I bat it."),
    },
    'toys': {
        'ball_of_wool': ("Ball of wool", 'common', [], "Was a ball. Is now a long line through the house."),
        'bottle_cap_spinner': ("Bottle-cap spinner", 'common', [], "Spins, wobbles, falls over. Like me after zoomies."),
        'catnip_fish': ("Catnip fish", 'rare', [], "Smells incredible. I've only licked it a few hundred times."),
        'cork': ("Cork", 'common', [], "Bounces wrong in the best possible way."),
        'crinkle_ball': ("Crinkle ball", 'common', [], "Makes a noise every time I touch it. Perfect."),
        'feather_wand_tip': ("Feather wand tip", 'uncommon', [], "I caught it. The wand is still out there."),
        'jingle_ball': ("Jingle ball", 'uncommon', [], "Jingles loudly, usually at three in the morning."),
        'little_knitted_bird': ("Knitted bird", 'legendary', [], "Someone made this with love. I've added my own."),
        'ping_pong_ball': ("Ping-pong ball", 'common', [], "The fastest thing in the house, after me."),
        'ribbon_bow': ("Ribbon bow", 'uncommon', [], "Off a present. The present can manage without it."),
        'spring_coil': ("Spring coil", 'common', [], "Boings, then hides under the sofa. A worthy opponent."),
        'toy_mouse_in_grey_felt': ("Grey felt mouse", 'uncommon', [], "Caught it fair and square. It never stood a chance."),
    },
    'treats': {
        'butter_curl': ("Butter curl", 'common', [], "Borrowed from the dish. I only licked the edge."),
        'cat_treat_pouch': ("Treat pouch", 'common', [], "My treats, for you to open. For me. Now, ideally."),
        'chicken_nugget': ("Chicken nugget", 'common', [], "A nugget of chicken, rescued from the floor."),
        'dollop_of_cream_on_a_saucer': ("Saucer of cream", 'rare', [], "Carried a whole saucer without spilling. Mostly."),
        'fish_shaped_biscuit': ("Fish biscuit", 'common', [], "A biscuit shaped like a fish. Two of my favourite things."),
        'prawn': ("Prawn", 'rare', [], "A whole prawn. I resisted for very nearly a second."),
        'salmon_flake': ("Salmon flake", 'uncommon', [], "Sharing this is the hardest thing I've ever done."),
        'sardine': ("Sardine", 'uncommon', [], "One sardine, slightly licked. A big gesture."),
        'single_cornflake': ("Single cornflake", 'common', [], "One cornflake. Crunchy. Thoughtful."),
        'slice_of_ham': ("Slice of ham", 'uncommon', [], "Ham. For you. This is what love looks like."),
        'small_cube_of_cheese': ("Cube of cheese", 'common', [], "Cheese. I don't know where it came from either."),
        'tuna_tin_lid': ("Tuna tin lid", 'common', [], "Smells of tuna, licked clean. Mind the edge."),
    },
}

# ---------------------------------------------------------------- seasons
SEASONS = [
    ('housewarming', "Housewarming", "Moving in: boxes, tea chests and the first night in a new home.",
     '2026-12-07', '2027-01-04'),
    ('midwinter', "Midwinter", "Deep winter indoors: knitted blankets, log baskets and long evenings.",
     '2027-01-04', '2027-02-01'),
    ('firstlight', "First Light", "The first spring mornings: seedlings, wellies and the birds coming back.",
     '2027-02-01', '2027-03-01'),
]
FREE_TRACK = {5: 'item0', 10: 'item1', 15: 'item2', 20: 'outfit'}
FREE_BEANS = {1: 20, 2: 20, 3: 25, 4: 25, 6: 30, 7: 30, 8: 30, 9: 35, 11: 35, 12: 40, 13: 40, 14: 40,
              16: 45, 17: 45, 18: 50, 19: 50}
PAID_TRACK = {1: 'item0', 3: 'wall', 6: 'item1', 9: 'floor', 12: 'item2', 15: 'item3', 18: 'item4', 20: 'outfit'}
PAID_BEANS = {2: 40, 4: 40, 5: 50, 7: 50, 8: 60, 10: 60, 11: 70, 13: 70, 14: 80, 16: 80, 17: 90, 19: 100}


def main():
    manifest = json.load(open(MANIFEST))['files']

    # ---- furniture from the manifest
    sprites = defaultdict(dict)
    meta = {}
    for path, v in manifest.items():
        if v.get('class') != 'furniture':
            continue
        key = (v['room'], v['item'])
        if v.get('variant') or path.endswith('_painted.png'):
            continue  # use the primary sprite; _painted duplicates are kept as art alternatives only
        sprites[key][v['facing']] = path
        meta.setdefault(key, {})[v['facing']] = v
    assert set(sprites) == set(ITEMS), (set(sprites) ^ set(ITEMS))

    room_items = {f"{r}_{i}" for (r, i) in ITEMS if r in ('living', 'bedroom', 'kitchen', 'garden', 'study', 'attic')}
    set_of = {}
    for sid, _, _, _, _, its in SETS:
        for it in its:
            assert it not in set_of, it
            set_of[it] = sid
    assert not (set(FREE) & set(BEANS)) and not (set(FREE) & set(set_of)) and not (set(BEANS) & set(set_of))
    assert set(FREE) | set(BEANS) | set(set_of) == room_items, room_items - (set(FREE) | set(BEANS) | set(set_of))

    season_pool = {}
    for sid, (folder, free, paid, _, _) in SEASON_ITEMS.items():
        for it in free:
            season_pool[f"{folder}_{it}"] = ('pass-free', folder)
        for it in paid:
            season_pool[f"{folder}_{it}"] = ('pass-paid', folder)

    items = []
    order = ['living', 'bedroom', 'kitchen', 'garden', 'study', 'attic', 'pass_housewarming', 'pass_midwinter',
             'pass_firstlight', 'housewarming_pack', 'founders']
    for key in sorted(ITEMS, key=lambda k: (order.index(k[0]), list(ITEMS).index(k))):
        room, item = key
        iid = f"{room}_{item}"
        name, (w, d), layer, decal, aff, cap, motion, pose, desc = ITEMS[key]
        mR, mL = meta[key]['R'], meta[key]['L']
        scale = mR.get('suggested_scale')
        fx = None
        if mR.get('motion_fx'):
            fxname = WATER_FX.get(key, mR['motion_fx']['fx'])
            aR, aL = mR['motion_fx'].get('anchor'), mL['motion_fx'].get('anchor')
            if aR is None:  # water: the manifest says "placed by eye"; start at the sprite centre
                aR = [mR['px'][0] // 2, mR['px'][1] // 2]
                aL = [mL['px'][0] // 2, mL['px'][1] // 2]
            fx = {"fx": fxname, "anchor": aR, "anchorL": aL}
        elif key in EXTRA_FX:  # top-centre, same convention as the kettle's steam; nudge by eye
            fx = {"fx": EXTRA_FX[key], "anchor": [mR['px'][0] // 2, 0], "anchorL": [mL['px'][0] // 2, 0]}

        pool, level, beans, sku, set_id = None, 1, None, None, None
        if iid in FREE:
            pool = 'free'
        elif iid in BEANS:
            pool = 'beans'
            level, beans = BEANS[iid]
        elif iid in set_of:
            pool, set_id = 'set', set_of[iid]
            sku = f"housecat.set.{set_id}"
        elif iid in season_pool:
            pool, set_id = season_pool[iid]
        elif room == 'housewarming_pack':
            pool, set_id, sku = 'housewarming', 'housewarming_pack', 'housecat.season.housewarming'
        elif room == 'founders':
            pool, set_id, sku = 'founders', 'founders', 'housecat.founders'
        else:
            raise SystemExit(f"no pool for {iid}")

        items.append({
            "id": iid, "name": name, "set": set_id, "room": room,
            "footprint": {"w": w, "d": d}, "layer": layer, "decal": decal,
            "affordances": aff, "capacity": cap, "motion": motion,
            "pool": pool, "level": level, "beans": beans, "sku": sku,
            "description": desc, "catPose": pose,
            "sprites": {"R": sprites[key]['R'], "L": sprites[key]['L']},
            "suggestedScale": scale, "fx": fx,
        })

    # ---- surfaces
    set_surface = {}
    for sid, _, _, wall, floor, _ in SETS:
        set_surface[wall] = sid
        set_surface[floor] = sid
    surfaces = []
    for path, v in sorted(manifest.items()):
        if v.get('class') not in ('rooms/walls', 'rooms/floors'):
            continue
        stem = os.path.basename(path)[:-4]
        kind = 'wall' if stem.startswith('wall_') else 'floor'
        rest = stem.split('_', 1)[1]
        if rest.startswith('pass_'):
            folder = '_'.join(rest.split('_')[:2])
            label = rest[len(folder) + 1:]
            room, pool, beans, set_id = folder, 'pass-paid', None, folder
        else:
            room, label = rest.split('_', 1)
            free_walls, free_floors = FREE_SURFACES[room]
            if label in (free_walls if kind == 'wall' else free_floors):
                pool, beans, set_id = 'free', None, None
            elif stem in set_surface:
                pool, beans, set_id = 'set', None, set_surface[stem]
            elif stem in BEAN_SURFACES:
                pool, beans, set_id = 'beans', BEAN_SURFACES[stem], None
            else:
                raise SystemExit(f"no pool for surface {stem}")
        name = SURFACE_NAMES.get(label, label.replace('_', ' ').capitalize())
        surfaces.append({"id": stem, "kind": kind, "room": room, "name": name, "pool": pool,
                         "beans": beans, "set": set_id, "sprite": path})

    sets = [{"id": sid, "name": name, "sku": f"housecat.set.{sid}", "bundleSku": f"housecat.bundle.{sid}",
             "bundleBeans": 300, "outfit": outfit, "wallpaper": wall, "floor": floor}
            for sid, name, outfit, wall, floor, _ in SETS]

    write('catalogue.json', {"version": 1, "sets": sets, "items": items, "surfaces": surfaces})

    # ---- outfits
    views_of = defaultdict(dict)
    for path, v in manifest.items():
        if v.get('class') != 'outfits':
            continue
        stem = os.path.basename(path)[:-4]          # outfit_<id>_<view>
        oid, view = stem[len('outfit_'):].rsplit('_', 1)
        views_of[oid][view] = path
    assert set(views_of) == set(OUTFITS), set(views_of) ^ set(OUTFITS)
    view_order = ['front', 'side', 'tqback', 'tqfront']
    outfits = []
    for oid, (name, slot, pool, earned, months) in OUTFITS.items():
        views = [x for x in view_order if x in views_of[oid]]
        sku = None
        if pool == 'paid':
            sku = f"housecat.outfit.{oid}"
        elif pool == 'founders':
            sku = 'housecat.founders'
        outfits.append({"id": oid, "name": name, "slot": slot, "views": views, "pool": pool, "sku": sku,
                        "earnedBy": earned, "months": months,
                        "sprites": {x: views_of[oid][x] for x in views}})
    write('outfits.json', {"version": 1, "outfits": outfits})

    # ---- gifts
    gifts = []
    seen = set()
    for path, v in sorted(manifest.items()):
        if v.get('class') != 'gifts':
            continue
        stem = os.path.basename(path)[:-4]           # gift_<category>_<item>
        cat = v['category']
        item = stem[len(f"gift_{cat}_"):]
        name, rarity, months, desc = GIFTS[cat][item]
        seen.add((cat, item))
        gifts.append({"id": f"{cat}_{item}", "name": name, "category": cat, "rarity": rarity,
                      "description": desc, "months": months, "sprite": path})
    assert seen == {(c, i) for c in GIFTS for i in GIFTS[c]}
    write('gifts.json', {"version": 1, "gifts": gifts})

    # ---- seasons
    surf_ids = {s['id']: s for s in surfaces}
    seasons = []
    for sid, name, theme, start, end in SEASONS:
        folder, free, paid, free_outfit, paid_outfit = SEASON_ITEMS[sid]
        wall = next(s['id'] for s in surfaces if s['room'] == folder and s['kind'] == 'wall')
        floor = next(s['id'] for s in surfaces if s['room'] == folder and s['kind'] == 'floor')
        assert wall in surf_ids and floor in surf_ids

        def reward(slot, items_, outfit):
            if slot.startswith('item'):
                return "item", f"{folder}_{items_[int(slot[4:])]}", None
            if slot == 'outfit':
                return "outfit", outfit, None
            if slot == 'wall':
                return "surface", wall, None
            if slot == 'floor':
                return "surface", floor, None
            raise ValueError(slot)

        free_track, paid_track = [], []
        for t in range(1, 21):
            if t in FREE_TRACK:
                k, i, a = reward(FREE_TRACK[t], free, free_outfit)
            else:
                k, i, a = "beans", None, FREE_BEANS[t]
            free_track.append({"tier": t, "kind": k, "id": i, "amount": a})
            if t in PAID_TRACK:
                k, i, a = reward(PAID_TRACK[t], paid, paid_outfit)
            else:
                k, i, a = "beans", None, PAID_BEANS[t]
            paid_track.append({"tier": t, "kind": k, "id": i, "amount": a})
        seasons.append({"id": sid, "name": name, "theme": theme, "startAt": start, "endAt": end,
                        "provisional": True, "sku": f"housecat.pass.{sid}",
                        "freeTrack": free_track, "paidTrack": paid_track})
    write('seasons.json', {"version": 1, "seasonLengthDays": 28, "tiers": 20, "seasons": seasons})


def write(name, obj):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print('wrote', os.path.join('Content', name))


if __name__ == '__main__':
    main()

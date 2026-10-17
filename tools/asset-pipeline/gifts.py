"""Gifts (60) and UI icons (30) as sprite sheets of 8 / 10 on magenta. python3 gifts.py gifts|ui"""
import json, sys

GIFTS = {
 'toys': ['toy mouse in grey felt', 'jingle ball', 'feather wand tip', 'crinkle ball', 'ball of wool', 'cork',
          'catnip fish', 'spring coil', 'ping-pong ball', 'little knitted bird', 'ribbon bow', 'bottle-cap spinner'],
 'treats': ['sardine', 'prawn', 'small cube of cheese', 'dollop of cream on a saucer', 'fish-shaped biscuit', 'slice of ham',
            'cat treat pouch', 'chicken nugget', 'salmon flake', 'butter curl', 'tuna tin lid', 'single cornflake'],
 'oddities': ['odd stripy sock', 'bottle cap', 'autumn leaf', 'very flat old toy mouse', 'hair bobble', 'paper clip',
              'button', 'twig', 'pebble', 'crumpled receipt with no writing', 'a single shoelace', 'pen lid'],
 'keepsakes': ['brass key', 'small seashell', 'pressed flower', 'marble', 'tiny silver bell', 'heart-shaped pebble',
               'old coin with no lettering', 'pearl earring', 'acorn', 'blue bird feather', 'little ceramic fish', 'sea glass'],
 'seasonal': ['conker', 'mini pumpkin', 'snowflake ornament', 'candy cane', 'Easter egg', 'daffodil head',
              'sparkler (unlit)', 'holly sprig', 'chocolate coin in gold foil with no lettering', 'tiny paper lantern',
              'pine cone', 'cherry blossom twig'],
}
UI = ['bean coin (a little golden-brown coin shaped like a cat toe bean)', 'XP star', 'trust heart with a paw print',
      'streak paw print with a small flame', 'season pass ticket', 'objectives clipboard with a tick', 'shop bag',
      'gift box with a ribbon', 'collection book', 'settings cog', 'feed bowl', 'petting hand', 'play laser dot',
      'nap moon', 'decorate paintbrush', 'map pin', 'weather sun and cloud', 'camera for photos', 'share arrow',
      'group of three paw prints', 'padlock', 'level-up arrow', 'clock', 'calendar', 'bell for notifications',
      'house', 'sofa for furniture', 'wallpaper roll', 'floorboards', 'cat face']
STYLE = ("Painted with visible painterly brushwork in a high-key Mediterranean-pastel palette, warm light from the upper left, "
         "violet-blue simplified shadows, a soft warm rim light, slightly stylised game-icon look. ")
GIFT_T = ("A sprite sheet of eight separate small objects that a cat brings home as gifts, laid out evenly in a 4 by 2 grid with "
          "plenty of empty space around each, every object the same size in its cell, each seen from slightly above at a "
          "three-quarter angle: {items}. " + STYLE + "Flat, solid pure magenta (#FF00FF) background, no shadows on the "
          "background, no text, no labels, no numbers, no logos.")
UI_T = ("A sprite sheet of ten separate game interface icons, laid out evenly in a 5 by 2 grid with plenty of empty space "
        "around each, every icon the same size in its cell, simple bold readable shapes with a soft painted finish: {items}. "
        + STYLE + "No pink or magenta anywhere in the icons themselves (hearts are warm red, the laser dot is bright red). Flat, solid pure magenta (#FF00FF) background, no shadows on the background, no text, no letters, no numbers, no labels.")

def reqs(kind):
    out = []
    if kind == 'gifts':
        allg = [(c, g) for c, gs in GIFTS.items() for g in gs]
        for i in range(0, 60, 8):
            chunk = allg[i:i + 8]
            items = '; '.join(f'({k+1}) {g}' for k, (_, g) in enumerate(chunk))
            out.append((f"gifts:sheet{i//8}", {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "16:9" if len(chunk) == 8 else "1:1",
                        "prompt": GIFT_T.replace('eight', {8: 'eight', 4: 'four'}[len(chunk)]).replace('4 by 2', '4 by 2' if len(chunk) == 8 else '2 by 2').format(items=items)}, [c + '_' + g for c, g in chunk]))
    if kind == 'ui':
        for i in range(0, 30, 10):
            chunk = UI[i:i + 10]
            items = '; '.join(f'({k+1}) {g}' for k, g in enumerate(chunk))
            out.append((f"ui:sheet{i//10}", {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "16:9",
                        "prompt": UI_T.format(items=items)}, chunk))
    return out

def slug(s):
    import re
    s = s.split(' (')[0]
    return re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')

if __name__ == '__main__':
    kind = sys.argv[1]
    sel = reqs(kind)
    json.dump({"names": [s[0] for s in sel], "requests": [{"index": i, "params": p} for i, (_, p, _) in enumerate(sel)], "ref": "surface",
               "items": {s[0]: [slug(x) for x in s[2]] for s in sel}}, open(f'batch_{kind}.json', 'w'), indent=1)
    print(json.dumps([{"index": i, "params": p} for i, (_, p, _) in enumerate(sel)]))

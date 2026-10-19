"""The cat creator's art (19 Oct; Josh: "a design wardrobe kind of creation"): the dressing room the cat stands in, the
drawers' icons and the fur swatch. python3 creator.py requests | cut <raw folder> <out folder>

requests: prints the Higgsfield requests (gpt_image_2_5, high, 2k), as sent. The rooms reference style test E (job
146f85a0), the icons and fur the first UI sheet (job 5f71253c) so they match the game's icons.
cut: keys the raws (room_a.png, icons_a.png, icons_b.png, fur.png in the raw folder) into the files for assets/ui:
icon_creator_<name>.png from the first sheet (the tail from the second, whose curl reads better than the first's
question mark), creator/creator_fur_swatch.png, and creator/creator_room.jpg (the room, opaque). Run with
uv run --with numpy --with pillow --with scipy --with opencv-python-headless python creator.py cut <raw> <out>
"""
import json
import os
import sys

STYLE = ("Painted with visible painterly brushwork in a high-key Mediterranean-pastel palette, warm light from the upper left, "
         "violet-blue simplified shadows, a soft warm rim light, slightly stylised game-icon look. ")
ROOM_A = ("A painted backdrop for a cosy video game: a cat's dressing room, seen straight on from a cat's eye height, with no cat, "
          "no animals and no people in it. Centre left, about 40 percent across from the left edge and in the lower half: a round "
          "low podium for a cat to stand on, a plump round dais in deep teal velvet with a thin brass trim, its top flat, empty and "
          "clearly visible, standing on a round woven rug. Right behind the podium: a big antique wardrobe in warm honey oak with "
          "both doors flung wide open; inside, small knitted jumpers, scarves, a little yellow raincoat and tiny hats hang on wooden "
          "hangers from a brass rail, and below them three drawers stand half open, spilling balls of wool yarn, ribbons and folded "
          "fabric swatches. To the left of the wardrobe, a tall oval standing mirror in a carved wooden frame catching soft light, "
          "reflecting only the room. To the right, a calm softly lit wall with a dressmaker's dummy, a shelf of round hat boxes and "
          "a potted plant, kept simple and uncluttered. Honey wooden floorboards, warm cream wallpaper with a faint stripe. Warm "
          "sunlight key from the upper left through an unseen window, violet-blue simplified shadows, a soft warm rim light on "
          "edges. Painted with visible painterly brushwork in the high-key Mediterranean-pastel palette of the reference: "
          "saturated, warm, inviting, slightly stylised painted-animation look. Plenty of empty space above the podium. No text, "
          "no letters, no logos.")
ICONS = ['a wooden clothes hanger with a small blank paper tag', "a coiled tailor's tape measure, cream with brown markings",
         'three small skeins of wool yarn in ginger, slate grey and cream', 'a folded square of fabric printed with brown tabby stripes',
         'a pair of small white knitted mittens', 'two glass marbles side by side, one amber and one blue, like cat eyes',
         "a cat's small rounded-triangle nose in soft coral with long fine whiskers fanning out on both sides",
         'a soft headband with two pointed grey felt cat ears', 'a fluffy ginger cat tail with tabby rings curled into a question-mark shape',
         'a small cupcake with one lit candle', 'a blank round brass name tag on a short brown leather cord', 'a pair of wooden dice']
NAMES = ['hanger', 'tape_measure', 'yarn', 'tabby_fabric', 'mittens', 'marbles', 'nose_whiskers', 'cat_ears', 'tail', 'cupcake',
         'name_tag', 'dice']
ICONS_T = ("A sprite sheet of twelve separate game interface icons in the exact painted style of the reference icon sheet, laid out "
           "evenly in a 4 by 3 grid with plenty of empty space around each, every icon the same size in its cell, simple bold "
           "readable shapes with a soft painted finish: {items}. " + STYLE + "No pink or magenta anywhere in the icons themselves. "
           "Flat, solid pure magenta (#FF00FF) background, no shadows on the background, no text, no letters, no numbers, no labels.")
FUR = ("One single round swatch of soft pure white cat fur, like a plump round fur pompom or a fabric sample disc seen from the front, "
       "filling the middle of the picture: soft white fur with a little visible strand texture, cool grey-violet shading at the "
       "lower right, a warm rim light at the upper left edge, painted with visible painterly brushwork in a slightly stylised "
       "game-icon look matching the reference. The fur is white and very light grey only, no other colours. Flat, solid pure "
       "magenta (#FF00FF) background, no shadows on the background, no text.")


def requests():
    base = {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k"}
    items = '; '.join(f'({i + 1}) {item}' for i, item in enumerate(ICONS))
    return [
        {**base, "aspect_ratio": "16:9", "medias": [{"value": "146f85a0-4e76-48fa-8f66-22ca29bbbc5e", "role": "image_references"}], "prompt": ROOM_A},
        {**base, "aspect_ratio": "4:3", "medias": [{"value": "5f71253c-186a-44fe-9616-7991313c4cde", "role": "image_references"}], "prompt": ICONS_T.format(items=items)},
        {**base, "aspect_ratio": "1:1", "medias": [{"value": "5f71253c-186a-44fe-9616-7991313c4cde", "role": "image_references"}], "prompt": FUR},
    ]


def cut(raw, out):
    import subprocess
    import numpy as np
    from PIL import Image
    import post
    os.makedirs(os.path.join(out, 'creator'), exist_ok=True)
    sheet = [f'icon_creator_{n}' for n in NAMES]
    post.cut_sheet(os.path.join(raw, 'icons_a.png'), out, sheet, merge=40)
    # The second sheet's tail: its mittens and tail run together there, so it is cut from its own corner.
    a = np.asarray(Image.open(os.path.join(raw, 'icons_b.png')).convert('RGB')).astype(np.float32)[1100:1700, 60:560]
    alpha = post.magenta_alpha(a)
    y0, y1, x0, x1, _ = max(post.components(alpha, 0.01, 10), key=lambda b: b[4])
    y0, x0, y1, x1 = max(0, y0 - 12), max(0, x0 - 12), min(a.shape[0], y1 + 12), min(a.shape[1], x1 + 12)
    post.save_rgba(post.despill(a, alpha)[y0:y1, x0:x1], alpha[y0:y1, x0:x1], os.path.join(out, 'icon_creator_tail.png'))
    post.cut_sheet(os.path.join(raw, 'fur.png'), os.path.join(out, 'creator'), ['creator_fur_swatch'])
    subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '92', os.path.join(raw, 'room_a.png'),
                    '--out', os.path.join(out, 'creator', 'creator_room.jpg')], check=True, capture_output=True)


if __name__ == '__main__':
    if sys.argv[1] == 'requests':
        print(json.dumps(requests(), indent=1))
    else:
        cut(sys.argv[2], sys.argv[3])

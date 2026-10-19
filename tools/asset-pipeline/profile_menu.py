"""The cat's profile and the room menu, redrawn (19 Oct; Josh: "the menu UI needs a full re-design as well to suit the app
more", "a plain white background right now and the qualities etc are a mess"): the corner the cat sits in on its profile,
twelve icons for its ways, and the paper the panels are printed on. python3 profile_menu.py requests | cut <raw> <out>

requests: prints the Higgsfield requests (gpt_image_2_5, high, 2k), as sent. The two corners reference style test E (job
146f85a0) and the dressing room (job 94a19400); the icons the first UI sheet (job 5f71253c) so they match the game's
icons; the paper style test E.
cut: keys the raws (corner_sun.png, corner_fire.png, ways.png, paper.png in the raw folder) into the files for assets/ui:
icon_way_<name>.png from the sheet, profile/profile_corner_sun.jpg and profile/profile_corner_fire.jpg (opaque), and
profile/panel_paper.jpg (lightened towards the game's cream). Run with
uv run --with numpy --with pillow --with scipy --with opencv-python-headless python profile_menu.py cut <raw> <out>
"""
import json
import os
import sys

STYLE = ("Painted with visible painterly brushwork in the high-key Mediterranean-pastel palette of the references: saturated, "
         "warm, inviting, slightly stylised painted-animation look. ")
CORNER_SUN = ("A painted backdrop for a cosy video game: the sunny corner of a warm home where a pet cat has its portrait taken, seen "
              "straight on from a cat's eye height, with no cat, no animals and no people in it. Left of centre, about 28 percent "
              "across from the left edge and in the lower half: a plump round cushion in warm mustard-gold velvet with thin brass "
              "piping, its top flat, empty and clearly visible, resting on a low round honey-oak stand on a round woven rug. Behind "
              "the cushion, a tall arched window with soft sheer cream curtains tied back, warm afternoon sunlight pouring in and "
              "falling in a soft patch across the floor, a glimpse of pale blue sky and soft garden greenery through the glass, a "
              "trailing potted plant on the sill. The right half of the picture is a calm, softly lit wall of warm apricot-cream "
              "wallpaper with a faint painted pattern above honey wood panelling, kept simple and uncluttered with plenty of empty "
              "space. Honey wooden floorboards. Warm sunlight key from the upper left, violet-blue simplified shadows, a soft warm "
              "rim light on edges. " + STYLE + "Plenty of empty space above the cushion. No text, no letters, no logos.")
CORNER_FIRE = ("A painted backdrop for a cosy video game: the fireside corner of a warm home where a pet cat has its portrait taken, "
               "seen straight on from a cat's eye height, with no cat, no animals and no people in it. Left of centre, about 28 "
               "percent across from the left edge and in the lower half: a plump round cushion in deep teal velvet with thin brass "
               "piping, its top flat, empty and clearly visible, on a round braided rug in warm terracotta and cream. Behind it, a "
               "small painted brick fireplace with a soft amber fire glowing, a mantelpiece with a little clock, a candle and a "
               "trailing plant, a framed painting of a sunny landscape above it. The right half of the picture is a calm, softly lit "
               "wall of warm dusky-rose and cream striped wallpaper above honey wood panelling, kept simple and uncluttered with "
               "plenty of empty space, a tall bookshelf just at the far right edge. Honey wooden floorboards. Warm firelight and "
               "lamplight from the left, violet-blue simplified shadows, a soft warm rim light on edges. " + STYLE +
               "Plenty of empty space above the cushion. No text, no letters, no logos.")
WAYS = ['a tall carpeted cat tree with a round platform high at the top', 'a plump round soft cushion with a little tassel, in teal',
        'an open cardboard box with its flaps up', 'a warm round golden sun with soft short rays',
        'a small arched window with cream curtains tied back and blue sky in the panes',
        'a small robin bird with a red-orange breast perched on a twig', 'a pair of cosy knitted slippers in oatmeal and teal',
        'a plump round crusty bread loaf', 'a rounded speech bubble in cream with three small dots inside',
        'a swirled cinnamon bun with icing', 'half a golden sun rising over a small green hill',
        'a small round brown owl sitting on a pale yellow crescent moon']
# In the sheet's reading order. The ways they stand for: `CatIdentity` Spot, Quirk and Hours (CatProfileView `WayIcon`).
NAMES = ['cat_tree', 'cushion', 'box', 'sun', 'window', 'robin', 'slippers', 'loaf', 'chatter', 'bun', 'sunrise', 'owl']
WAYS_T = ("A sprite sheet of twelve separate game interface icons in the exact painted style of the reference icon sheet, laid out "
          "evenly in a 4 by 3 grid with plenty of empty space around each, every icon the same size in its cell, simple bold readable "
          "shapes with a soft painted finish: {items}. Painted with visible painterly brushwork in a high-key Mediterranean-pastel "
          "palette, warm light from the upper left, violet-blue simplified shadows, a soft warm rim light, slightly stylised game-icon "
          "look. No pink or magenta anywhere in the icons themselves. Flat, solid pure magenta (#FF00FF) background, no shadows on "
          "the background, no text, no letters, no numbers, no labels.")
PAPER = ("A flat, evenly lit square of warm cream artist's paper filling the whole frame edge to edge, seen straight on: very subtle "
         "painterly mottling and a fine soft fibrous grain in cream, ivory and the faintest apricot, like a hand-made watercolour "
         "card under warm light. No objects, no border, no frame, no vignette, no shadows, no folds, no stains, no text. An even "
         "tone across the whole picture so it can sit quietly behind interface text in a cosy painted video game, matching the "
         "warm palette of the reference.")
# Accepted 19 Oct 2026 (docs/art-log.md).
JOBS = {'corner_sun': 'e8a7e018-9e66-4e04-8259-6af06ceb2e8d', 'corner_fire': '17c81ec7-1962-457b-878d-86146e6e83d7',
        'ways': '75cad1c1-71c0-4311-9d6c-5d21bf7e2043', 'paper': 'bbd705a4-0d7e-449b-97fa-075e78675511'}


def requests():
    base = {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k"}
    rooms = [{"value": "146f85a0-4e76-48fa-8f66-22ca29bbbc5e", "role": "image_references"},
             {"value": "94a19400-a2fd-4a60-a948-dd017f0945dd", "role": "image_references"}]
    items = '; '.join(f'({i + 1}) {item}' for i, item in enumerate(WAYS))
    return [
        {**base, "aspect_ratio": "16:9", "medias": rooms, "prompt": CORNER_SUN},
        {**base, "aspect_ratio": "16:9", "medias": rooms, "prompt": CORNER_FIRE},
        {**base, "aspect_ratio": "4:3", "medias": [{"value": "5f71253c-186a-44fe-9616-7991313c4cde", "role": "image_references"}],
         "prompt": WAYS_T.format(items=items)},
        {**base, "aspect_ratio": "1:1", "medias": rooms[:1], "prompt": PAPER},
    ]


def cut(raw, out):
    import subprocess
    import numpy as np
    from PIL import Image
    import post
    os.makedirs(os.path.join(out, 'profile'), exist_ok=True)
    post.cut_sheet(os.path.join(raw, 'ways.png'), out, [f'icon_way_{n}' for n in NAMES])
    for corner in ('corner_sun', 'corner_fire'):
        subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '90', os.path.join(raw, f'{corner}.png'),
                        '--out', os.path.join(out, 'profile', f'profile_{corner}.jpg')], check=True, capture_output=True)
    # The paper, half way to the game's cream (Theme.cream) so text on it reads as on the other cards, at 1024 px.
    paper = np.asarray(Image.open(os.path.join(raw, 'paper.png')).convert('RGB').resize((1024, 1024), Image.LANCZOS)).astype(np.float32)
    cream = np.array([254, 247, 236], dtype=np.float32)
    paper = paper * 0.5 + cream * 0.5
    Image.fromarray(paper.clip(0, 255).astype(np.uint8)).save(os.path.join(out, 'profile', 'panel_paper.jpg'), quality=90)


if __name__ == '__main__':
    if sys.argv[1] == 'requests':
        print(json.dumps(requests(), indent=1))
    else:
        cut(sys.argv[2], sys.argv[3])

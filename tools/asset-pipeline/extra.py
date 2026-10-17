"""Second round: app icon + logo, cat pose sheets, motion FX. python3 extra.py <kind> -> req_<kind>.json + batch_<kind>.json
kinds: icon, logo, poses, fx"""
import json, sys
from cat import SETS, IDENT, MARK, MASTER

TURN = {'short_slim': '438f4f24-1e9c-47bb-96b3-0c2f3ed77603', 'short_chunky': '679f6b4c-d14a-4a83-8d42-853a0ac72abc',
        'long_slim': '0e6ff9e9-38e2-434c-9ab8-761bb243c9e2', 'long_chunky': '8d0fb7fa-da04-4c25-bcea-e24241b666d5'}
MARKREF = {'tuxedo': '436f2183-27b1-486c-9802-9ab8013f3d56', 'locket': '5187da2d-c665-4a8c-8bba-a55e97cceca4',
           'socks': '7f62ac62-fdab-4c4b-b467-c315f8932c4d'}
STYLE_E = '146f85a0-4e76-48fa-8f66-22ca29bbbc5e'
PAINT = ("Painted with visible painterly brushwork in a high-key Mediterranean-pastel palette, warm light from the upper left, "
         "violet-blue simplified shadows, a soft warm rim light.")

def gp(prompt, ar, refs=()):
    p = {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": ar, "prompt": prompt}
    if refs: p["medias"] = [{"role": "image_references", "value": r} for r in refs]
    return p

POSES = ["sit_side", "sit_tqfront", "sit_front", "sit_back", "loaf_side", "loaf_tqfront", "sleep_curl", "stretch_side"]
POSE_T = ("Pose sheet of the exact black cat from the reference image ({body}){marks}. Eight separate full-body poses laid out in "
          "a 4 by 2 grid with clear empty space between them, all at the same scale, nothing touching or overlapping. "
          "Top row, left to right: (1) sitting upright, side view facing left, tail wrapped round the front paws; (2) sitting "
          "upright, three-quarter front view facing the lower left; (3) sitting upright, front view facing the viewer; (4) "
          "sitting upright seen from directly behind, looking away as if out of a window, both ears up, tail curled round on "
          "the ground. Bottom row, left to right: (5) the 'loaf': lying down with all four paws tucked under the body, side "
          "view facing left, eyes half closed; (6) the loaf in three-quarter front view; (7) fast asleep curled into a round "
          "ball, nose tucked into the tail, eyes closed, seen from slightly above; (8) a long lazy stretch, front legs reaching "
          "forward and bottom up, side view facing left. " + IDENT + " {bg}")
BG_CREAM = "Flat, plain pale cream background like the master plate, no ground, no cast shadow, no text, no labels."
BG_GREY = "Flat, plain mid-grey background, no ground, no cast shadow, no text, no labels."

ICON_T = ("Square app icon artwork for a cosy virtual-pet game called HouseCat, full bleed edge to edge, no rounded corners, "
          "no border, no text, no letters. {idea} The black cat is the exact cat from the reference image: a round head a touch "
          "large for the body, big round amber eyes with a white catchlight, upright ears, dark navy-brown fur with a warm lit "
          "rim. Bold, simple, instantly readable at small size: one big clear shape, few details, strong contrast between the "
          "dark cat and a bright background. " + PAINT)
ICONS = {
 'house_window': "The cat's head and shoulders fill the lower two thirds, looking straight out at the viewer, framed by the "
                 "simple outline of a cream house with a pitched roof against a clear warm-blue sky.",
 'sill_peek': "The cat's head peeks up over the bottom edge as if over a window sill, huge amber eyes, ears up, against a "
              "glowing sunrise sky in apricot and sky blue.",
 'round_window': "The cat sits upright inside a round window of a terracotta-roofed house, seen from outside, the window "
                 "glowing warm amber behind its dark silhouette, sky-blue background.",
 'roof_curl': "The cat sits on the ridge of a little house's terracotta roof, tail curled round, under a big pale sun, "
              "sky-blue background, the house simplified to two bold shapes.",
}

LOGO_T = ("Logo lockup for a cosy virtual-pet game: {layout} The wordmark reads exactly \"HouseCat\" (one word, capital H and "
          "capital C), set in a warm, characterful rounded serif with soft ink edges, dark navy-brown (#2a2630). The mark is "
          "the black cat from the reference image simplified to a bold, flat-ish painted emblem: round head, big amber eyes, "
          "upright ears, sitting inside a simple house outline with a pitched roof. Flat, solid pure white background, "
          "nothing else, no tagline, no other text.")
LOGOS = {
 'horizontal': "the mark on the left, the wordmark to its right, vertically centred.",
 'stacked': "the mark on top, the wordmark centred underneath.",
}

FX = {
 'fire': ("Animation sprite sheet: eight frames of a small cosy hearth fire, flames only (no fireplace, no grate), in one row, "
          "evenly spaced, the same size and base line in every frame, the flames flickering through one smooth looping cycle. "
          "Bright yellow core, orange and red tips, painterly brushwork. Solid pure black background, nothing else.", "16:9"),
 'candle': ("Animation sprite sheet: eight frames of a single small candle flame, flame only (no candle, no wick), in one row, "
            "evenly spaced, same size and base point, gently flickering through one smooth looping cycle; warm yellow-white core, "
            "amber edge, soft glow. Painterly. Solid pure black background, nothing else.", "16:9"),
 'steam': ("Animation sprite sheet: eight frames of a soft wisp of rising steam, white and pale grey, in one row, evenly spaced, "
           "the same base point in every frame, the wisp curling upward and fading through one smooth looping cycle. Painterly, "
           "soft edges. Solid pure black background, nothing else.", "16:9"),
 'water': ("Sprite sheet on a solid pure black background: eight separate small elements of sparkling clear water in one row, "
           "evenly spaced: four frames of a small arcing trickle of water from a pet water fountain, then four frames of an "
           "expanding ring ripple seen from above at an isometric angle. Bright highlights, pale aqua, painterly.", "16:9"),
 'robin': ("Animation sprite sheet of a European robin (orange-red breast, olive-brown back), eight separate poses in a 4 by 2 "
           "grid with clear space between them, all the same scale: perched side view, pecking down, head tilted, hopping, wings "
           "raised taking off, flying wings up, flying wings down, fluffed up perched. Painterly, warm light from the upper left. "
           "Flat, solid pure magenta (#FF00FF) background, no shadow, no text.", "16:9"),
 'butterfly': ("Animation sprite sheet of a small pale-blue butterfly, eight frames in one row, evenly spaced, same size, "
               "seen from slightly above, wings beating through one smooth looping flap cycle from fully open to closed and "
               "back. Painterly. Flat, solid pure magenta (#FF00FF) background, no shadow, no text.", "16:9"),
 'reactions': ("Sprite sheet of eight separate little reaction icons that float above a cat in a game, in a 4 by 2 grid with clear "
               "space between them, the same size: (1) a warm red heart, (2) the letters Zzz drifting upward, (3) a single "
               "music note, (4) a pair of music notes, (5) a four-pointed sparkle star, (6) a question mark, (7) an exclamation "
               "mark, (8) a small paw print. Soft painterly finish, warm cream and amber with a dark navy outline. No pink or "
               "magenta in the icons. Flat, solid pure magenta (#FF00FF) background, no shadow.", "16:9"),
 'smoke': ("Animation sprite sheet: eight frames of a soft puff of chimney smoke, pale grey and white, in one row, evenly spaced, "
           "the same base point, drifting up and to the right and fading through one smooth looping cycle. Painterly, soft "
           "edges. Solid pure black background, nothing else.", "16:9"),
}

def reqs(kind):
    out = []
    if kind == 'icon':
        out = [(f'icon:concept_{k}', gp(ICON_T.format(idea=v), '1:1', [MASTER, STYLE_E])) for k, v in ICONS.items()]
    if kind == 'logo':
        out = [(f'logo:{k}', gp(LOGO_T.format(layout=v), '16:9' if k == 'horizontal' else '1:1', [MASTER])) for k, v in LOGOS.items()]
    if kind == 'poses':
        for s in SETS:
            out.append((f'pose:{s}_plain', gp(POSE_T.format(body=SETS[s], marks='', bg=BG_CREAM), '16:9', [TURN[s]])))
        for m, d in MARK.items():
            for s in SETS:
                marks = (f", with {d}; take the white markings exactly from the second reference image and the body shape "
                         f"from the first")
                out.append((f'pose:{s}_{m}', gp(POSE_T.format(body=SETS[s], marks=marks, bg=BG_GREY), '16:9', [TURN[s], MARKREF[m]])))
    if kind == 'fx':
        out = [(f'fx:{k}', gp(p, ar)) for k, (p, ar) in FX.items()]
    return out

if __name__ == '__main__':
    kind = sys.argv[1]; sel = reqs(kind)
    json.dump({"names": [n for n, _ in sel], "requests": [{"index": i, "params": p} for i, (_, p) in enumerate(sel)], "ref": "surface"},
              open(f'batch_{kind}.json', 'w'))
    json.dump([{"index": i, "params": p} for i, (_, p) in enumerate(sel)], open(f'req_{kind}.json', 'w'))
    print(len(sel), [n for n, _ in sel])

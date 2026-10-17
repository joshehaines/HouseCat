"""World manifest: light maps, garden boundary strips, weather sprites, cobweb, map textures, exteriors,
terrains, widget window frames. python3 world.py <kind> <start> <n>"""
import json, sys

GREY = "d8ab3b05-db3b-4ef7-b3c5-5a0cf5d17e07"     # grey 10x10 reference room
STYLE_E = "146f85a0-4e76-48fa-8f66-22ca29bbbc5e"  # style test E (palette and brushwork)
PAINT = "Painted with visible painterly brushwork in a high-key Mediterranean-pastel palette, warm light from the upper left, violet-blue simplified shadows."

def gp(prompt, ar, refs=None):
    p = {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": ar, "prompt": prompt}
    if refs: p["medias"] = [{"role": "image_references", "value": r} for r in refs]
    return p

LIGHT = [
 ('morning', "cool fresh morning light; a soft slanted patch of pale sunlight falls across the right wall and the floor from a window out of view on the left; gentle blue-violet shadows"),
 ('midday', "bright high midday light; a crisp warm rectangle of sunlight on the floor near the left wall; soft violet shadows in the corner"),
 ('evening', "low golden evening sun; long warm amber streaks of light across the floor and up the right wall; deep violet shadows"),
 ('overcast', "soft overcast daylight, even and slightly cool, no sun patches, gentle darkening into the corner"),
 ('night', "night, lit only by a warm table lamp out of view near the front of the room; a warm pool of light on the floor, dim warm walls fading to deep blue-violet in the far corner"),
]
LIGHT_T = ("Use the reference image: an empty isometric room corner in a clean 2:1 isometric projection. Repaint the SAME room "
           "with identical geometry and framing, but every surface is plain matte white plaster: white walls and a plain white "
           "floor with no boards and no texture, so that only light and shadow show. Lighting: {d}. Nothing in the room: no "
           "objects, no windows or doors drawn, no furniture, no text. Soft painterly brushwork.")

STRIPS = [
 ('brick_wall', "a low old red-brick garden wall with a cream stone coping, about two fifths of the image height", ),
 ('picket_fence', "a white wooden picket fence with pointed pales, about a third of the image height"),
 ('privet_hedge', "a neatly clipped green privet hedge with a flat top, about three fifths of the image height"),
 ('rose_trellis', "a pale wooden trellis with climbing pink roses on top of a low brick wall, about two thirds of the image height"),
 ('drystone_wall', "a honey-coloured dry stone wall with an uneven top, about two fifths of the image height"),
]
STRIP_T = ("A seamless horizontally repeating strip of {d}, seen perfectly straight-on, flat, no perspective, filling the full "
           "width edge to edge so it tiles left to right, standing along the bottom edge of the image. Everything above it is "
           "flat, solid pure magenta (#FF00FF): no sky, no clouds, no trees. " + PAINT + " No text.")

MISC = [
 ('weather_sheet', "3:2", "A sprite sheet on a flat, solid pure magenta (#FF00FF) background showing six separate weather particles, evenly "
  "spaced in a 3 by 2 grid with plenty of space around each: a single raindrop, a single six-armed snowflake, a single falling "
  "orange autumn leaf, a single pink blossom petal, a small soft white cloud puff, a soft pale wisp of fog. " + PAINT + " No text, no labels."),
 ('cobweb', "1:1", "A delicate cobweb spanning a corner, fine silvery-white threads with a few tiny glinting dust motes, seen "
  "straight-on and isolated on a flat, solid pure black background. Soft painterly brushwork. No spider, no wall, no text."),
 ('map_sea', "1:1", "A seamless repeating painted sea texture for a stylised world map, seen from directly above: soft turquoise and "
  "cornflower blue water with gentle painterly wave strokes, filling the square edge to edge, tiling without seams. "
  "High-key Mediterranean-pastel palette, visible painterly brushwork. No land, no boats, no text."),
 ('map_land', "1:1", "A seamless repeating painted land texture for a stylised world map, seen from directly above: soft sage and "
  "leaf green with gentle painterly dabs suggesting fields, filling the square edge to edge, tiling without seams. "
  "High-key Mediterranean-pastel palette, visible painterly brushwork. No roads, no buildings, no text."),
]

HOUSES = [
 ('london_terrace', "a London Victorian terraced house in yellow London stock brick with a cobalt-blue front door, white sash windows and a small front step, its neighbours cut away cleanly at either side"),
 ('mansion_flat', "a red-brick Edwardian mansion block, three storeys, with white stone bands, a grand arched entrance door and bay windows"),
 ('cottage', "a whitewashed country cottage with a thatched roof, a sage-green stable door and roses round the door"),
 ('georgian_townhouse', "a tall cream stucco Georgian townhouse with black railings, a navy six-panel front door and a fanlight"),
 ('newbuild_balcony', "a modern new-build block of flats in pale brick with glass balconies, three storeys, a simple glazed entrance door"),
 ('houseboat', "a painted canal houseboat in teal and red with little round windows and a front hatch door, sitting on a narrow strip of calm water"),
 ('mediterranean_rooftop', "a pastel-pink Mediterranean rooftop flat with a terracotta roof terrace, teal shutters and potted lemon trees"),
 ('woodland_cabin', "a small honey-coloured log cabin with a stone chimney, a porch and a green front door"),
]
HOUSE_T = ("A painterly game illustration of {d}, seen from "
           "above and to the front-left in a clean 2:1 isometric projection (parallel lines stay parallel, no vanishing "
           "points), the front door on the left-facing façade, standing on its own small flat patch of ground with a doorstep "
           "and a short path. Isolated on a flat, solid pure magenta (#FF00FF) background: no sky, no other buildings, no trees "
           "behind it. Every pane of window glass is flat, solid pure cyan (#00FFFF) with no reflections. Bright noon light from "
           "the upper left. " + PAINT + " No people, no cat, no text, no signs.")

BIOMES = {
 'city': "a city street scene: low skyline of varied rooftops, chimneys and a church spire in the distance, a tree-lined pavement in front",
 'coast': "a seaside: a calm turquoise sea and a pale sandy shore with dune grass, a distant headland",
 'countryside': "rolling countryside: patchwork fields, hedgerows, a few round trees and gentle hills",
 'mountain': "mountains: alpine meadow in front, pine trees and tall rocky peaks behind",
 'forest': "a forest edge: a clearing in front of tall mixed woodland, ferns and a soft path",
 'desert': "a desert: warm sand dunes, a few palms and rocky mesas in the distance",
 'tropical': "a tropical shore: lush palms, broad-leaved jungle and a turquoise lagoon",
 'snow': "a snowy northern landscape: snow-covered ground, dark spruce trees and distant white hills",
}
SEASON = {
 'spring': "in spring: fresh bright greens, blossom on the trees, wildflowers",
 'summer': "in high summer: rich greens, full leaves, bright warm colour",
 'autumn': "in autumn: amber, rust and gold leaves, some bare branches, fallen leaves",
 'winter': "in winter: bare trees, frost and a light covering of snow, muted cool colours",
}
TERR_T = ("A wide painted landscape backdrop at noon, eye level, the horizon a little below the middle: {b}, {s}. The ground "
          "in the lower centre is open and flat, where a house will be placed later, with nothing standing there. The whole sky "
          "area above the land is flat, solid pure magenta (#FF00FF): no sky colour, no clouds, no sun. " + PAINT +
          " No buildings in the foreground, no people, no animals, no text.")

WIDGET = [
 ('sash', "a cream-painted sash window"), ('casement', "a sage-green cottage casement window with small panes"),
 ('arched', "a round-topped arched white window"), ('picture', "a wide modern window with a slim charcoal frame"),
 ('porthole', "a round brass porthole in a teal painted wall"), ('shuttered', "a cream window with open teal shutters"),
 ('cabin', "a rustic log-framed cabin window"), ('bay', "a deep bay window with a cushioned window seat"),
]
WIDGET_T = ("Seen straight-on from inside a cosy room: {d} with a deep, wide wooden window sill in front of it, big enough for a "
            "cat to sit on, and a little of the painted wall around it. Every pane of glass is flat, solid pure cyan (#00FFFF): "
            "nothing seen through it, no reflections. The sill is empty. " + PAINT + " No cat, no plants, no curtains, no text.")

def reqs(kind):
    if kind == 'light':
        return [(f"light:{i}", gp(LIGHT_T.format(d=d), "4:3", [GREY])) for i, d in LIGHT]
    if kind == 'strips':
        return [(f"strip:{i}", gp(STRIP_T.format(d=d), "16:9")) for i, d in STRIPS]
    if kind == 'misc':
        return [(f"misc:{i}", gp(p, ar)) for i, ar, p in MISC]
    if kind == 'houses':
        return [(f"house:{i}", gp(HOUSE_T.format(d=d), "1:1")) for i, d in HOUSES]
    if kind == 'terrain':
        return [(f"terrain:{b}_{s}", gp(TERR_T.format(b=bd, s=sd), "16:9")) for b, bd in BIOMES.items() for s, sd in SEASON.items()]
    if kind == 'widget':
        return [(f"widget:{i}", gp(WIDGET_T.format(d=d), "1:1")) for i, d in WIDGET]
    if kind == 'widget_wide':
        return [(f"widget:{i}_wide", gp(WIDGET_T.format(d="a wide landscape-format version of " + d.replace('a ', '', 1) +
                 ", the window filling most of the width", ), "16:9")) for i, d in WIDGET]

if __name__ == '__main__':
    kind = sys.argv[1]; start = int(sys.argv[2]); n = int(sys.argv[3])
    sel = reqs(kind)[start:start + n]
    names = [s[0] for s in sel]
    requests = [{"index": i, "params": p} for i, (_, p) in enumerate(sel)]
    json.dump({"names": names, "requests": requests, "ref": "surface"}, open(f'batch_{kind}_{start}.json', 'w'))
    print(json.dumps(requests))

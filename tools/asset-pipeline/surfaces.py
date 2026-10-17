"""Surface manifest: wallpapers, floors, windows, doors. Emits batch JSON like manifest.py.
python3 surfaces.py <kind> <start> <n>     kind = walls | floors | windows | doors"""
import json, sys

REF_WALL = "71ed0fbb-1478-4c87-b245-0a177ae53aee"    # wall_cream.png tile (brushwork reference)
REF_FLOOR = "5ccca407-456d-46d7-9a94-4826cda736b8"   # floor_honey.png tile

WALLS = [
 # room, id, description   (living cream + mint already exist as wall_cream / wall_mint)
 ('living', 'terracotta_damask', "a dusty terracotta wallpaper with a subtle tone-on-tone damask pattern"),
 ('living', 'powder_lemon', "a pale powder-blue wallpaper with small scattered hand-painted lemon sprigs"),
 ('living', 'sage_limewash', "warm sage-green limewash plaster with soft mottled brush texture"),
 ('bedroom', 'blush_floral', "a blush-pink wallpaper with tiny scattered cream flowers"),
 ('bedroom', 'lavender_stripe', "pale lavender and cream vertical pinstripes"),
 ('bedroom', 'toile_blue', "a cream toile wallpaper with simple pastoral trees and cottages in soft blue line work"),
 ('bedroom', 'starry_dusk', "a deep dusk-blue wallpaper with small scattered gold stars"),
 ('bedroom', 'oat_linen', "warm oatmeal linen-textured plaster"),
 ('kitchen', 'metro_tiles', "white glazed metro tiles in a brick bond with pale grey grout lines"),
 ('kitchen', 'mint_gingham', "a mint-green and cream gingham check"),
 ('kitchen', 'lemon_print', "a cream wallpaper with scattered painted lemons and leaves"),
 ('kitchen', 'terracotta_tiles', "small square hand-made terracotta wall tiles with cream grout"),
 ('kitchen', 'cream_beadboard', "cream painted tongue-and-groove beadboard running vertically"),
 ('garden', 'old_brick', "an old warm red-brown brick wall in a stretcher bond"),
 ('garden', 'picket_sky', "a white wooden picket fence of vertical pales with soft blue sky showing between the pales"),
 ('garden', 'privet_hedge', "a dense clipped green privet hedge"),
 ('garden', 'ivy_trellis', "a pale wooden diamond trellis covered with ivy against a cream wall"),
 ('garden', 'drystone', "a honey-coloured dry stone wall"),
 ('study', 'forest_green', "a deep forest-green painted wall with subtle brush texture"),
 ('study', 'navy_pinstripe', "a navy wallpaper with fine gold vertical pinstripes"),
 ('study', 'oak_panel', "warm oak wall panelling in tall rectangular raised panels"),
 ('study', 'antique_map', "a faded antique map wallpaper in sepia and pale blue, coastlines only, no letters or words"),
 ('study', 'ochre_linen', "an ochre-yellow linen-textured plaster"),
 ('attic', 'pine_planks', "bare horizontal pine planks with knots and soft grain"),
 ('attic', 'whitewashed_brick', "whitewashed brick with a little warm brick showing through"),
 ('attic', 'faded_rose', "a faded, sun-bleached rose floral wallpaper"),
 ('attic', 'rough_plaster', "rough cream plaster with a few fine hairline cracks"),
 ('attic', 'bluegrey_shiplap', "blue-grey painted horizontal shiplap boards"),
 ('pass_housewarming', 'apricot_houses', "a warm apricot wallpaper with a small repeating pattern of tiny cream houses"),
 ('pass_midwinter', 'tartan', "a red and forest-green tartan with fine gold lines"),
 ('pass_firstlight', 'primrose_daffodil', "a primrose-yellow wallpaper with tiny scattered daffodils"),
]
FLOORS = [
 ('living', 'herringbone', "honey oak parquet blocks in a herringbone pattern"),
 ('living', 'terracotta', "large square terracotta floor tiles with cream grout"),
 ('living', 'sage_carpet', "a soft sage-green wool carpet"),
 ('living', 'walnut_boards', "dark walnut floorboards running straight up and down"),
 ('bedroom', 'pale_oak', "pale whitewashed oak floorboards running straight up and down"),
 ('bedroom', 'cream_carpet', "a thick cream wool carpet"),
 ('bedroom', 'white_boards', "white painted floorboards running straight up and down"),
 ('bedroom', 'rose_carpet', "a dusty-rose wool carpet"),
 ('bedroom', 'chevron', "pale oak chevron parquet"),
 ('kitchen', 'checker', "black and cream checkerboard floor tiles laid square to the edges"),
 ('kitchen', 'quarry', "red quarry floor tiles with cream grout"),
 ('kitchen', 'encaustic', "blue and white patterned encaustic floor tiles"),
 ('kitchen', 'mint_lino', "pale mint marbled linoleum"),
 ('kitchen', 'slate', "grey-blue slate flagstones laid in a grid"),
 ('garden', 'lawn', "a short-cut green lawn"),
 ('garden', 'flagstones', "irregular sandstone flagstone paving with thin lines of grass between"),
 ('garden', 'gravel', "pale golden gravel"),
 ('garden', 'decking', "weathered honey-grey wooden decking boards running straight up and down"),
 ('garden', 'brick_paving', "red brick paving in a basketweave pattern"),
 ('study', 'dark_parquet', "dark oak parquet blocks laid square to the edges"),
 ('study', 'green_carpet', "a deep green wool carpet"),
 ('study', 'worn_oak', "worn mid-oak floorboards running straight up and down"),
 ('study', 'cork', "warm cork floor tiles"),
 ('study', 'grey_boards', "soft grey painted floorboards running straight up and down"),
 ('attic', 'rough_pine', "rough wide pine floorboards with nail heads, running straight up and down"),
 ('attic', 'chalk_blue', "chalky blue-grey painted floorboards running straight up and down"),
 ('attic', 'sisal', "natural woven sisal matting"),
 ('attic', 'dusty_boards', "dusty bare floorboards running straight up and down"),
 ('attic', 'whitewash', "whitewashed floorboards running straight up and down"),
 ('pass_housewarming', 'birch', "pale birch floorboards running straight up and down"),
 ('pass_midwinter', 'cherry', "dark cherry floorboards running straight up and down"),
 ('pass_firstlight', 'green_tiles', "pale green and cream square tiles in a checker"),
]
WINDOWS = [
 ('sash', "a tall cream-painted two-pane sash window with a deep sill"),
 ('casement', "a sage-green cottage casement window with small square panes and a wooden sill"),
 ('arched', "a tall round-topped arched window in white-painted wood with glazing bars"),
 ('picture', "a wide modern picture window with a slim charcoal frame and a single large pane"),
 ('porthole', "a round brass porthole window with rivets"),
 ('shuttered', "a Mediterranean window with a cream frame and open teal louvred shutters either side"),
 ('cabin', "a rustic cabin window framed in rough honey-coloured logs with four panes"),
 ('dormer', "a small square attic window in weathered wood with a cross of glazing bars"),
]
DOORS = [
 ('panelled_cream', "a cream four-panel interior door with a brass knob"),
 ('georgian_navy', "a navy six-panel Georgian door with a brass knob and a fanlight above"),
 ('cottage_sage', "a sage-green cottage plank door with black iron hinges and a latch"),
 ('arched_oak', "a round-topped arched oak plank door with iron studs"),
 ('glazed_garden', "a white-painted glazed garden door with small panes"),
 ('stable_blue', "a powder-blue stable door split into a top and bottom half"),
 ('modern_white', "a plain modern white flush door with a slim brass handle"),
 ('barn_slider', "a honey-coloured wooden barn door that slides sideways on a black rail above the opening"),
]

WALL_T = ("Use the reference image only for its painterly brushwork and paint texture. Paint a NEW seamless repeating "
          "wall texture: {d}. Perfectly flat and straight-on, filling the entire square edge to edge, the pattern continuing "
          "off every edge so it tiles without seams. No border, no frame, no room, no perspective, no shadows, no objects, "
          "no text. Even, soft, flat lighting. High-key Mediterranean-pastel palette, visible painterly brushwork.")
FLOOR_T = ("Use the reference image only for its painterly brushwork and paint texture. Paint a NEW seamless repeating "
           "floor texture seen from directly above: {d}. Perfectly flat and straight-on, lines square to the image edges, "
           "filling the entire square edge to edge, the pattern continuing off every edge so it tiles without seams. No "
           "border, no frame, no perspective, no shadows, no objects, no text. Even, soft, flat lighting. High-key "
           "Mediterranean-pastel palette, visible painterly brushwork.")
OPEN_T = ("{d}, seen perfectly straight-on from the front, flat, no perspective, centred, filling most of the image, on a "
          "flat pure magenta (#FF00FF) background. {fill} Painted with visible painterly brushwork in a high-key "
          "Mediterranean-pastel palette, warm light from the upper left. No wall around it, no curtains, no plants, no text.")
WIN_FILL = "Every glass pane is filled with flat, solid pure cyan (#00FFFF): no reflections, no sky, nothing seen through it."
DOOR_FILL = ("The door stands wide open, swung inward to the left, and the empty doorway opening behind it is filled with flat, "
             "solid pure cyan (#00FFFF). Any glass in the door is also flat pure cyan.")

def reqs(kind):
    out = []
    if kind == 'walls':
        for room, iid, d in WALLS:
            out.append((f"wall:{room}_{iid}", {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "1:1",
                        "prompt": WALL_T.format(d=d), "medias": [{"role": "image_references", "value": REF_WALL}]}))
    if kind == 'floors':
        for room, iid, d in FLOORS:
            out.append((f"floor:{room}_{iid}", {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "1:1",
                        "prompt": FLOOR_T.format(d=d), "medias": [{"role": "image_references", "value": REF_FLOOR}]}))
    if kind == 'windows':
        for iid, d in WINDOWS:
            out.append((f"window:{iid}", {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "3:4",
                        "prompt": OPEN_T.format(d=d[0].upper() + d[1:], fill=WIN_FILL)}))
    if kind == 'doors':
        for iid, d in DOORS:
            out.append((f"door:{iid}", {"model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "3:4",
                        "prompt": OPEN_T.format(d=d[0].upper() + d[1:], fill=DOOR_FILL)}))
    return out

if __name__ == '__main__':
    kind = sys.argv[1]; start = int(sys.argv[2]); n = int(sys.argv[3])
    sel = reqs(kind)[start:start + n]
    names = [s[0] for s in sel]
    requests = [{"index": i, "params": p} for i, (_, p) in enumerate(sel)]
    json.dump({"names": names, "requests": requests, "ref": "surface"}, open(f'batch_{kind}_{start}.json', 'w'))
    print(json.dumps(requests))

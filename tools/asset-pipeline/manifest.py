"""Furniture generation manifest for HouseCat. Each item: id, room, description, placement
(wall | floor | hung). Emits batch request JSON for generate_image_batch."""
import json, sys

REF_CREAM = "36f386b7-ba74-47bb-9a65-09c5afa31525"   # skirting-free cream 10x10 reference room (media id)
REF = "d8ab3b05-db3b-4ef7-b3c5-5a0cf5d17e07"         # neutral grey reference room: pale and dark items both cut cleanly

PRE = ("Use the reference image: an empty isometric room corner with two plain mid-grey walls and a darker grey "
       "wooden floor, in a clean 2:1 isometric projection. Paint the SAME grey room, identical in every way, with "
       "exactly ONE object added: ")
POST = (" Drawn in exactly the same isometric projection as the room, parallel lines stay parallel, scaled for a room "
        "ten paces wide. The object is painted with visible painterly brushwork in a high-key Mediterranean-pastel "
        "palette, lit by warm light from the upper left. The walls and floor stay exactly as in the reference: no cast "
        "shadows, no light patches, no reflections or colour bounce on the walls or floor, only a small soft contact "
        "shadow directly under the object. Nothing else added: no cat, no other furniture, no text.")

PLACE = {
    'wall':  {'R': "standing on the floor with its back flat against the RIGHT wall, about a third of the way along the wall from the corner.",
              'L': "standing on the floor with its back flat against the LEFT wall, about a third of the way along the wall from the corner."},
    'floor': {'R': "standing on the floor in the middle of the room, its front facing the lower left and its long side parallel to the RIGHT wall.",
              'L': "standing on the floor in the middle of the room, its front facing the lower right and its long side parallel to the LEFT wall."},
    'hung':  {'R': "hanging flat on the RIGHT wall at eye height, about a third of the way along the wall from the corner, foreshortened with the wall.",
              'L': "hanging flat on the LEFT wall at eye height, about a third of the way along the wall from the corner, foreshortened with the wall."},
    'low':   {'R': "set low in the RIGHT wall at floor level, about a third of the way along the wall from the corner, foreshortened with the wall.",
              'L': "set low in the LEFT wall at floor level, about a third of the way along the wall from the corner, foreshortened with the wall."},
}

ITEMS = {
 'living': [
  ('windowseat','wall',"a low cream wooden window-seat bench with a long mustard velvet cushion and two small patterned pillows,"),
  ('radiator','wall',"an old cast-iron radiator painted cream with a folded cloth resting on top,"),
  ('record','wall',"a record player on a low teak sideboard with a few record sleeves leaning against its side,"),
  ('plant','floor',"a large monstera plant in a terracotta pot,"),
  ('fireplace','wall',"a small Victorian fireplace with a cream painted wooden surround, a tiled hearth and a small lit fire inside, set flush against the wall,"),
 ],
 'bedroom': [
  ('bed','wall',"a double bed with a pale oak headboard, white sheets and a rumpled mustard blanket, headboard against the wall,"),
  ('bedside','wall',"a small bedside table in pale oak with one drawer and a little lamp on top,"),
  ('wardrobe','wall',"a tall cream painted wardrobe with two doors, one slightly ajar,"),
  ('laundry','floor',"a woven wicker laundry basket with a few clothes spilling over the rim,"),
  ('readinglamp','floor',"a small brass reading lamp on a slim stand with a green glass shade, switched on,"),
  ('curtains','hung',"a pair of long sage-green curtains on a brass pole, hanging flat against the wall with no window behind them,"),
  ('drawers','wall',"a chest of three drawers in pale oak with brass handles,"),
  ('catbed','floor',"a round plush cat bed in oatmeal with a cream cushion,"),
  ('slippers','floor',"a pair of fluffy pale-pink slippers,"),
  ('mirror','hung',"a tall oval mirror in a thin brass frame,"),
  ('gownhook','hung',"a cream dressing gown hanging on a small brass wall hook,"),
  ('hammock','wall',"a cat hammock in teal canvas slung on a pale wooden frame,"),
  ('alarmclock','floor',"a small round brass alarm clock with twin bells, on the floor,"),
  ('bedrug','floor',"a rectangular rug in soft sage green with a cream border, lying flat,"),
 ],
 'kitchen': [
  ('bowl','floor',"a ceramic cat food bowl in teal on a small cream mat,"),
  ('fountain','floor',"a small white ceramic cat water fountain with a gentle trickle,"),
  ('table','floor',"a small square kitchen table in pale pine,"),
  ('chair','floor',"a pale pine kitchen chair with a spindle back,"),
  ('fridge','wall',"a cream retro-style fridge with rounded corners and a chrome handle,"),
  ('kettle','floor',"a mint-green stove-top kettle standing on the floor,"),
  ('herbshelf','hung',"a small wooden wall shelf with three potted herbs,"),
  ('breadbin','floor',"a cream enamel bread bin with a wooden lid, on the floor,"),
  ('fruitbowl','floor',"a wide ceramic fruit bowl with lemons and oranges, on the floor,"),
  ('cooker','wall',"a cream enamel cooker with four hob rings and a chrome rail,"),
  ('catflap','low',"a small white cat flap with a clear flap,"),
  ('radio','floor',"a small vintage radio in cream and mint, on the floor,"),
  ('doormat','floor',"a coir door mat with a single dark stripe, lying flat,"),
  ('sink','wall',"a white ceramic sink set in a pale pine unit with a brass tap,"),
 ],
 'garden': [
  ('bench','wall',"a weathered honey-oak garden bench,"),
  ('sunpatch','floor',"a soft warm oval patch of sunlight on the floor and nothing else,"),
  ('birdfeeder','floor',"a wooden bird feeder on a tall post with a little seed tray,"),
  ('flowerpots','floor',"a cluster of three terracotta flower pots with red geraniums,"),
  ('wateringcan','floor',"a green metal watering can,"),
  ('deckchair','floor',"a striped canvas deck chair in teal and cream,"),
  ('shed','wall',"a small wooden garden shed painted sage green with a little window,"),
  ('fence','wall',"a run of low white wooden picket fence,"),
  ('pond','floor',"a small round garden pond ringed with warm sandstone, two water lilies floating on it, lying flat on the floor,"),
  ('festoon','hung',"a string of warm festoon lights hung in a gentle curve along the wall,"),
  ('gardenhammock','floor',"a cream rope hammock slung between two short wooden posts,"),
  ('washingline','floor',"a washing line strung between two posts with a few bright clothes pegged on it,"),
 ],
 'study': [
  ('desk','wall',"a pale oak writing desk with a drawer and a few papers on top,"),
  ('officechair','floor',"a mid-century office chair in mustard fabric on a chrome swivel base,"),
  ('laptop','floor',"an open laptop in pale cream with a softly glowing screen, on the floor,"),
  ('bookshelf','wall',"a tall wide bookshelf in dark walnut packed with books with a small globe on top,"),
  ('papertray','floor',"a wooden in-tray stacked with paper, on the floor,"),
  ('desklamp','floor',"a green bankers desk lamp with a brass stem, its shade glowing softly but casting no pool of light, on the floor,"),
  ('globe','floor',"a vintage globe on a brass stand,"),
  ('filing','wall',"a two-drawer filing cabinet painted sage green,"),
  ('printer','floor',"a small white printer with a sheet of paper coming out, on the floor,"),
  ('noticeboard','hung',"a cork noticeboard in a pine frame pinned with notes and a postcard,"),
  ('mug','floor',"a large cream mug of tea, on the floor,"),
  ('blind','hung',"a cream roller blind half drawn, hanging flat on the wall,"),
 ],
 'attic': [
  ('trunk','wall',"an old leather travel trunk with brass corners and faded stickers,"),
  ('dustyarmchair','wall',"an old wingback armchair in faded rose velvet with a dust sheet half pulled off it,"),
  ('skylightpatch','floor',"a soft rectangular patch of sunlight on the floor and nothing else,"),
  ('boxes','wall',"a stack of three old cardboard boxes, the top one open,"),
  ('rockinghorse','floor',"a vintage painted wooden rocking horse,"),
  ('dummy','floor',"a dressmaker's dummy on a wooden tripod stand,"),
  ('telescope','floor',"a brass telescope on a wooden tripod,"),
  ('rolledrug','floor',"a rolled-up patterned rug tied with string, lying on the floor,"),
  ('oillamp','floor',"an antique oil lamp with a glass chimney, lit, on a small round table,"),
  ('cobweb','hung',"a delicate silvery-white cobweb with a few dust motes, high on the wall,"),
  ('suitcase','floor',"an old brown leather suitcase,"),
  ('wireless','floor',"a large old wooden wireless radio,"),
 ],
 'pass_housewarming': [
  ('movingboxes','floor',"a stack of two sealed moving boxes with marker-pen labels,"),
  ('teachest','floor',"a wooden tea chest with stencilled lettering,"),
  ('painttins','floor',"three paint tins in sage, mustard and cream, one open with a brush resting on it,"),
  ('stepladder','floor',"a wooden step ladder,"),
  ('fairylights','hung',"a string of tiny warm fairy lights draped in two swags along the wall,"),
  ('picnicblanket','floor',"a red and cream checked picnic blanket spread flat on the floor,"),
  ('takeaway','floor',"a brown paper takeaway bag with a receipt stapled to it,"),
  ('candle','floor',"a lit scented candle in an amber glass jar, on the floor,"),
 ],
 'pass_midwinter': [
  ('knitblanket','floor',"a chunky cream knitted blanket folded on the floor,"),
  ('logbasket','floor',"a wicker basket full of split logs,"),
  ('wreath','hung',"a fir wreath with red berries and a tartan bow,"),
  ('mulledwine','floor',"two mugs of mulled wine with orange slices, on the floor,"),
  ('snowglobe','floor',"a snow globe with a tiny red-roofed cottage inside, on a dark wooden base, on the floor,"),
  ('firtree','floor',"a small decorated fir tree in a pot with warm lights and baubles,"),
  ('sledge','wall',"a wooden sledge leaning against the wall,"),
  ('hotwaterbottle','floor',"a hot-water bottle in a red knitted cover, on the floor,"),
 ],
 'pass_firstlight': [
  ('seedtrays','floor',"a wooden tray of seedlings in little pots,"),
  ('birdbox','hung',"a small wooden bird box,"),
  ('tulips','floor',"a terracotta pot of red and yellow tulips,"),
  ('pegbag','hung',"a floral peg bag hanging on a hook,"),
  ('hamper','floor',"a wicker picnic hamper with the lid open and a bottle inside,"),
  ('butterflyjar','floor',"a glass jar with a blue butterfly resting on its rim,"),
  ('wellies','floor',"a pair of yellow wellington boots,"),
  ('daffodils','floor',"a blue enamel jug of daffodils,"),
 ],
 'housewarming_pack': [
  ('grandfireplace','wall',"a grand marble fireplace with a lit fire and a mantel clock, set flush against the wall,"),
  ('hifi','wall',"a walnut hi-fi console with a record player and two speakers,"),
  ('bulbstring','hung',"a string of large round warm bulbs along the wall,"),
  ('welcomemat','floor',"a coir doormat with the word WELCOME in black, lying flat,"),
  ('champagne','floor',"a brass champagne bucket on a stand with a bottle and two glasses,"),
  ('houseportrait','hung',"a framed painting of a little terraced house in a gold frame,"),
 ],
 'founders': [
  ('plaque_brass','hung',"a small rectangular polished brass plaque with four screws, engraved with a sitting cat silhouette on the left and a smooth blank area on the right with no numbers or letters,"),
  ('plaque_slate','hung',"a small rectangular blue-grey slate plaque with four brass screws, engraved with a sitting cat silhouette in cream on the left and a smooth blank area on the right with no numbers or letters,"),
  ('plaque_oak','hung',"a small rectangular honey oak plaque with four brass screws, carved with a sitting cat silhouette on the left and a smooth blank area on the right with no numbers or letters,"),
 ],
}

def requests_for(room, side_filter=None, only=None):
    """only: optional list of '<item>_<side>' names to restrict to (re-dos)."""
    reqs = []
    for i, (iid, place, desc) in enumerate(ITEMS[room]):
        for side in ('R', 'L'):
            if side_filter and side != side_filter: continue
            if only is not None and f"{iid}_{side}" not in only: continue
            prompt = PRE + desc + " " + PLACE[place][side] + POST
            reqs.append({"index": len(reqs), "name": f"{room}:{iid}_{side}", "params": {
                "model": "gpt_image_2_5", "quality": "high", "resolution": "2k", "aspect_ratio": "4:3",
                "prompt": prompt, "medias": [{"role": "image_references", "value": REF}]}})
    return reqs

def write_batch(tag, reqs):
    names = [r.pop('name') for r in reqs]
    for i, r in enumerate(reqs): r['index'] = i
    json.dump({"names": names, "requests": reqs, "ref": reqs[0]['params']['medias'][0]['value']}, open(f'batch_{tag}.json', 'w'))
    print(json.dumps(reqs))

if __name__ == '__main__':
    if sys.argv[1] == 'redo':            # python3 manifest.py redo <tag> room:item_side room:item_side ...
        tag = sys.argv[2]; reqs = []
        for spec in sys.argv[3:]:
            room, name = spec.split(':'); reqs += requests_for(room, only=[name])
        write_batch(tag, reqs)
    else:
        room = sys.argv[1]; start = int(sys.argv[2]); n = int(sys.argv[3])
        write_batch(f'{room}_{start}', requests_for(room)[start:start + n])

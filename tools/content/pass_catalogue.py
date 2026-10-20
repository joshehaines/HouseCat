#!/usr/bin/env python3
"""Puts a season pass's own set into Content/catalogue.json (Josh, 20 Oct 2026: "less beans and more items ... feel
free to design more items"): each piece painted by tools/asset-pipeline/pass_sets.py, in the catalogue section
`pass_<season>`, in the pool of the track build_seasons.py lays it on (pass-free or pass-paid), never sold; and the
season's own wallpaper and floor. Replaces the season's entries if they are there already, and leaves every other
entry as it is.

Run from the repo root: python3 -I tools/content/pass_catalogue.py blackcat
"""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1].parent
CATALOGUE = ROOT / "Content" / "catalogue.json"
sys.path.insert(0, str(ROOT / "tools" / "content"))
import build_seasons  # noqa: E402

STATIC = {"type": "static"}
GLOW = {"type": "glow", "pivot": [0.5, 0.5], "period": 5.0}
SWAY = {"type": "sway", "pivot": [0.5, 0.0], "period": 6.0}

# id: (name, layer, footprint w x d, affordances, cat pose, how the cat uses it, motion, suggested scale, line)
PIECES = {
    'blackcat': {
        'conkerbowl': ("Conker bowl", 'floor', (1, 1), ['bat'], None, None, STATIC, 0.32,
                       "This year's conkers. One will end up under the sofa."),
        'pumpkintrio': ("Pumpkin trio", 'floor', (1, 1), ['none'], None, None, STATIC, 0.42,
                        "Three small pumpkins: orange, cream and striped."),
        'yarnbasket': ("Yarn basket", 'floor', (1, 1), ['bat'], None, None, STATIC, 0.42,
                       "Wool in autumn colours. It will not stay wound for long."),
        'ghosttoy': ("Felt ghost", 'floor', (1, 1), ['bat'], None, None, STATIC, 0.3,
                     "A felt ghost with a bell inside. Very brave when batted."),
        'applecrate': ("Apple crate", 'floor', (1, 1), ['perch'], 'sit_tqfront', None, STATIC, 0.55,
                       "Red and green apples, still smelling of the orchard."),
        'lantern': ("Storm lantern", 'floor', (1, 1), ['none'], None, None, GLOW, 0.42,
                    "A brass lantern for long October evenings."),
        'leafpile': ("Leaf pile", 'floor', (1, 1), ['hide', 'sleep'], 'sleep_curl', None, STATIC, 0.75,
                     "A heap of crunchy leaves. Best jumped into."),
        'cocoa': ("Hot chocolate tray", 'floor', (1, 1), ['none'], None, None, STATIC, 0.34,
                  "Two mugs of hot chocolate, marshmallows and ginger biscuits."),
        'candles': ("Candle cluster", 'floor', (1, 1), ['none'], None, None, GLOW, 0.38,
                    "Five candles on a slate, for lamplit evenings."),
        'batbunting': ("Bat bunting", 'wall', (2, 1), ['bat'], None, None, SWAY, 0.9,
                       "Felt bats and paper leaves on a string."),
        'mushroomlamp': ("Toadstool lamp", 'floor', (1, 1), ['none'], None, None, GLOW, 0.4,
                         "Three glowing toadstools on a mossy log."),
        'pumpkinpouffe': ("Pumpkin pouffe", 'floor', (1, 1), ['sit', 'sleep'], 'sleep_curl', None, STATIC, 0.55,
                          "A knitted pumpkin, just the size for curling up on."),
        'toadstool': ("Toadstool stool", 'floor', (1, 1), ['sit', 'perch'], 'sit_tqfront', None, STATIC, 0.55,
                      "A spotted toadstool to sit on. Not for eating."),
        'pumpkinbed': ("Pumpkin cat bed", 'floor', (1, 1), ['sleep'], 'sleep_curl', None, STATIC, 0.65,
                       "A pumpkin with a velvet cushion inside. Slept on, mostly."),
        'jackolantern': ("Jack-o'-lantern", 'floor', (1, 1), ['watch'], 'sit_tqfront', 'front', GLOW, 0.5,
                         "Carved with a cat's face. It looks a bit like someone."),
        'velvetchair': ("Midnight armchair", 'floor', (1, 1), ['sit', 'sleep'], 'sleep_curl', None, STATIC, None,
                        "Plum velvet, brass studs and a knitted throw."),
        'catportrait': ("Black cat portrait", 'wall', (1, 1), ['none'], None, None, STATIC, 0.9,
                        "A very distinguished ancestor, in oils."),
        'moonlamp': ("Moon lamp", 'floor', (1, 1), ['none'], None, None, GLOW, None,
                     "A paper full moon on a brass stand."),
        'catcastle': ("Cardboard castle", 'floor', (1, 1), ['hide', 'perch'], 'sit_tqfront', None, STATIC, 0.8,
                      "Two turrets, one door, one ruler."),
        'spookytree': ("Twisty tree", 'floor', (1, 1), ['perch', 'sleep', 'scratch'], 'sit_tqfront', None, STATIC, None,
                       "A gnarled cat tree with felt bats in its branches."),
        'cobwebhammock': ("Cobweb hammock", 'floor', (2, 1), ['sleep'], 'sleep_curl', None, STATIC, 0.85,
                          "A crocheted cobweb to nap in. The spider is felt."),
        'owlclock': ("Owl clock", 'wall', (1, 1), ['none'], None, None, STATIC, 0.85,
                     "A wooden owl that keeps the time."),
        'catrug': ("Black cat rug", 'floor', (2, 2), ['sleep'], 'sleep_curl', None, STATIC, None,
                   "A woven rug with a sleeping cat in the middle. Now two."),
        'telescope': ("Brass telescope", 'floor', (1, 1), ['watch'], 'sit_back', 'front', STATIC, None,
                      "For long clear nights and passing owls."),
        'grandclock': ("Midnight clock", 'floor', (1, 1), ['none'], None, None, STATIC, None,
                       "A grandfather clock with a smiling moon on its face."),
        'applebob': ("Apple-bobbing tub", 'floor', (1, 1), ['watch'], 'sit_side', 'front', STATIC, 0.75,
                     "Apples bobbing in a tub. Watched, never bobbed for."),
        'gramophone': ("Gramophone", 'floor', (1, 1), ['none'], None, None, STATIC, 0.85,
                       "A wind-up gramophone with a big brass horn."),
        'ghostlamp': ("Ghost lamp", 'floor', (1, 1), ['none'], None, None, GLOW, 0.75,
                      "A little sheet ghost glowing on a side table."),
        'batcushion': ("Bat cushion", 'floor', (1, 1), ['sleep'], 'sleep_curl', None, STATIC, 0.75,
                       "A velvet bat with its wings spread, for napping on."),
        'rockingchair': ("Rocking chair", 'floor', (1, 1), ['sit', 'sleep'], 'sleep_curl', None, STATIC, None,
                         "Honey oak and a granny-square blanket."),
        'conkertree': ("Conker tree", 'floor', (1, 1), ['hide', 'bat'], None, None, STATIC, None,
                       "A young horse chestnut in a pot, turning gold."),
        'humbugjar': ("Humbug jar", 'floor', (1, 1), ['none'], None, None, STATIC, 0.4,
                      "Humbugs and toffees in a tall glass jar."),
        'catdoorstop': ("Cat doorstop", 'floor', (1, 1), ['none'], None, None, STATIC, 0.4,
                        "A cast-iron cat that holds the door. Never moves."),
        'pumpkinpatch': ("Pumpkin patch", 'floor', (2, 1), ['hide'], None, None, STATIC, 0.85,
                         "Pumpkins and gourds in a long planter."),
        'haybale': ("Hay bale seat", 'floor', (2, 1), ['sit', 'perch', 'sleep'], 'sleep_curl', None, STATIC, 0.8,
                    "A hay bale with a tartan blanket and a small pumpkin."),
        'lanternstring': ("Pumpkin lanterns", 'wall', (3, 1), ['none'], None, None, GLOW, None,
                          "Paper pumpkin lanterns on a string."),
        'booknook': ("Ghost story shelf", 'floor', (1, 1), ['sleep', 'hide'], 'sleep_curl', None, STATIC, None,
                     "Old storybooks and a gap on the bottom shelf, cat-sized."),
    },
    'housewarming': {
        'keysdish': ("New keys", 'floor', (1, 1), ['none'], None, None, STATIC, 0.3,
                     "The keys to a new front door, on a peach ribbon."),
        'bubblewrap': ("Bubble wrap", 'floor', (2, 1), ['bat', 'sleep'], 'sleep_curl', None, STATIC, 0.8,
                       "Pop. Pop. Pop. Best enjoyed lying on."),
        'firstcuppa': ("First cuppa", 'floor', (1, 1), ['none'], None, None, STATIC, 0.75,
                       "The kettle was in the first box opened."),
        'floorcushion': ("Floor cushion", 'floor', (1, 1), ['sit', 'sleep'], 'sleep_curl', None, STATIC, 0.7,
                         "Mustard cord. Somewhere to sit till the sofa comes."),
        'sleepingbag': ("Sleeping bag", 'floor', (2, 1), ['sleep'], 'sleep_curl', None, STATIC, 0.9,
                        "For the first night, before the bed is built."),
        'plantgift': ("Housewarming plant", 'floor', (1, 1), ['hide'], None, None, STATIC, 0.85,
                      "A cheese plant with a bow on. From the neighbours."),
        'cardstring': ("Housewarming cards", 'wall', (2, 1), ['none'], None, None, SWAY, 0.9,
                       "Cards from friends, pegged on a string."),
        'toolbox': ("Toolbox", 'floor', (1, 1), ['none'], None, None, STATIC, 0.4,
                    "A hammer, a screwdriver and a tape measure."),
        'flatpack': ("Flat-pack box", 'floor', (2, 1), ['sit', 'sleep'], 'sleep_curl', None, STATIC, 0.85,
                     "A bookcase, eventually. A cat bed, for now."),
        'boxtunnel': ("Box tunnel", 'floor', (2, 1), ['hide'], None, None, STATIC, 0.85,
                      "Three boxes taped into a tunnel. Built for one."),
        'laundrybag': ("Laundry bag", 'floor', (1, 1), ['hide'], None, None, STATIC, 0.6,
                       "Blue-and-white check, full of soft things."),
        'housebed': ("House cat bed", 'floor', (1, 1), ['sleep'], 'sleep_curl', None, STATIC, 0.7,
                     "A little house with a roof, a chimney and a cushion."),
        'velvetsofa': ("Teal velvet sofa", 'floor', (2, 1), ['sit', 'sleep'], 'sleep_curl', None, STATIC, None,
                       "Brand new. The plastic is still on one arm."),
        'eggchair': ("Hanging egg chair", 'floor', (1, 1), ['sleep'], 'sleep_curl', None, STATIC, None,
                     "A rattan egg to curl up and swing in."),
        'blanketfort': ("Blanket fort", 'floor', (2, 1), ['hide', 'sleep'], 'sleep_curl', None, STATIC, None,
                        "A quilt over two chairs, and fairy lights."),
        'cratetable': ("Crate coffee table", 'floor', (2, 1), ['perch'], 'sit_tqfront', None, STATIC, 0.85,
                       "Four fruit crates and a sheet of glass."),
        'arclamp': ("Arc lamp", 'floor', (1, 1), ['none'], None, None, GLOW, None,
                    "A brass arc with a glowing dome."),
        'beanbag': ("Bean bag", 'floor', (1, 1), ['sleep'], 'sleep_curl', None, STATIC, 0.75,
                    "Coral cord, squashed into a perfect dip."),
        'gallerywall': ("Gallery wall", 'wall', (1, 1), ['none'], None, None, STATIC, 0.8,
                        "Six little frames, hung close together."),
        'leaningmirror': ("Leaning mirror", 'floor', (1, 1), ['watch'], 'sit_back', 'front', STATIC, None,
                          "A tall arched mirror. Someone in it looks familiar."),
        'plantstand': ("Plant stand", 'floor', (1, 1), ['none'], None, None, STATIC, None,
                       "Ivy, a fern and a cactus on three tiers."),
        'blankettrunk': ("Blanket trunk", 'floor', (1, 1), ['sleep', 'hide'], 'sleep_curl', None, STATIC, 0.8,
                         "A wicker trunk of blankets, its lid half open."),
        'housescratcher': ("House scratcher", 'floor', (1, 1), ['scratch'], 'stretch_side', None, STATIC, None,
                           "A cottage to scratch, with a roof on top."),
        'bicycle': ("Bicycle", 'floor', (2, 1), ['none'], None, None, STATIC, None,
                    "Sage green, with a basket of flowers."),
        'swatchboard': ("Paint swatches", 'wall', (1, 1), ['none'], None, None, STATIC, 0.85,
                        "Which colour for the hall? Still deciding."),
        'housecake': ("Housewarming cake", 'floor', (1, 1), ['none'], None, None, STATIC, 0.4,
                      "Iced, with a tiny house on top."),
        'breadsalt': ("Bread and salt", 'floor', (1, 1), ['none'], None, None, STATIC, 0.4,
                      "The old housewarming gift, so a home never goes without."),
        'recordcrate': ("Record crate", 'floor', (1, 1), ['none'], None, None, STATIC, 0.8,
                        "A crate of records and a suitcase record player."),
        'welcomewreath': ("Eucalyptus wreath", 'wall', (1, 1), ['none'], None, None, STATIC, 0.7,
                          "Silver eucalyptus and a linen bow."),
        'paperlantern': ("Paper lantern", 'floor', (1, 1), ['bat'], None, None, STATIC, 0.6,
                         "Waiting to be hung. Being batted instead."),
        'bookstack': ("Unpacked books", 'floor', (1, 1), ['none'], None, None, STATIC, 0.85,
                      "A tower of books, a lamp on top. Unpacking can wait."),
    },
}
SURFACES = {
    'blackcat': [('wall_pass_blackcat_midnight_bats', 'wall', "Midnight bats"),
                 ('floor_pass_blackcat_conker_parquet', 'floor', "Conker parquet")],
}


def main(season: str) -> None:
    data = json.loads(CATALOGUE.read_text())
    room = f'pass_{season}'
    seasons = {s['id']: s for s in build_seasons.SEASONS}
    free = set(seasons[season]['free'])
    entries = []
    for key, (name, layer, (w, d), affordances, pose, use, motion, scale, line) in PIECES[season].items():
        iid = f'{room}_{key}'
        entry = {
            "id": iid, "name": name, "set": room, "room": room, "footprint": {"w": w, "d": d}, "layer": layer,
            "decal": key == 'catrug', "affordances": affordances,
            "capacity": 0 if affordances == ['none'] else (2 if 'perch' in affordances and key == 'spookytree' else 1),
            "motion": motion, "pool": 'pass-free' if iid in free else 'pass-paid', "level": 1, "beans": None,
            "sku": None, "description": line, "catPose": pose,
            "sprites": {"R": f"furniture/{room}/furn_{iid}_R.png", "L": f"furniture/{room}/furn_{iid}_L.png"},
            "suggestedScale": scale, "fx": None,
        }
        if use:
            entry["catUse"] = use
        entries.append(entry)
    # Only the pieces defined here are replaced: a season's earlier ones (Housewarming's eight of 17 Oct) stay.
    ids = {entry["id"] for entry in entries}
    items = [i for i in data['items'] if i['id'] not in ids]
    # After the season's earlier pieces, else after the other passes' sets (before the Housewarming pack).
    own = [n for n, i in enumerate(items) if i['room'] == room]
    at = (own[-1] if own else max(n for n, i in enumerate(items) if i['room'].startswith('pass_'))) + 1
    data['items'] = items[:at] + entries + items[at:]
    defined = {sid for sid, _, _ in SURFACES.get(season, [])}
    surfaces = [s for s in data['surfaces'] if s['id'] not in defined]
    for sid, kind, name in SURFACES.get(season, []):
        surfaces.append({"id": sid, "kind": kind, "room": room, "name": name, "pool": "pass-paid", "beans": None,
                         "set": None, "sprite": f"rooms/{kind}s/{sid}.png"})
    data['surfaces'] = surfaces
    CATALOGUE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    # The manifest carries each piece's suggested scale too (ContentValidationTests checks they agree).
    manifest_path = ROOT / "assets" / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    for entry in entries:
        for sprite in entry["sprites"].values():
            record = manifest["files"][sprite]
            record.pop("suggested_scale", None)
            if entry["suggestedScale"] is not None:
                record["suggested_scale"] = entry["suggestedScale"]
    manifest_path.write_text(json.dumps(manifest, indent=1))
    print(f"{len(entries)} pieces and {len(SURFACES.get(season, []))} surfaces for {room}")


if __name__ == "__main__":
    main(sys.argv[1])

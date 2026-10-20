#!/usr/bin/env python3
"""Writes Content/seasons.json: the seasons and their two tracks (the season pass, Josh 19 Oct 2026: the game's main
progression, a free track and a premium one, a season always running).

Thirty tiers, a box on each: the free track's twenty, the premium track's thirty. Josh, 20 Oct: "the boxes need to be
better and I think we need more content in them ... less beans and more items". So a box holds an item where it can,
some hold two items or an item with bonus Beans, and Beans alone fill only a few boxes (free: six, 225 Beans, plus
bonus Beans on tiers 10 and 20, about 300; premium: four, 325, plus bonus Beans on five boxes, about 545; they were
565 and 1,525). Every season lays its tracks out on the same template (FREE and PREMIUM below): its own pieces in
order, its wallpaper on premium tier 4 and floor on 16, a bonus outfit on premium 12 (and a second on 22 if it has one),
its own outfit at the top of each track.

Each reward carries a rarity, shown on its box with its word and diamonds: Beans are common, an outfit legendary, a
wallpaper or floor rare, and a piece what RARITY says (uncommon if not listed).

A season whose own set is not painted yet (Midwinter, First Light) borrows pieces from the shop to fill its boxes, so no
season falls back to Beans; check_content.py warns about each one until it is replaced. Black Cat and Housewarming
have their own (tools/asset-pipeline/pass_sets.py, tools/content/pass_catalogue.py).

Seasons sit on HouseCatCore's SeasonCalendar (December is always Midwinter); slots after the last one here run a
season again (SeasonSchedule), so the pass never stops. Black Cat (5 Oct - 2 Nov 2026) comes before the launch season
so the pass is there for TestFlight and App Review.

Run from the repo root: python3 -I tools/content/build_seasons.py
"""
from __future__ import annotations

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Content" / "seasons.json"

TIERS = 30
FREE_TIERS = 20
LAUNCH = "2026-11-02"

# The template. 'piece' takes the season's next piece, 'outfit' its own outfit for the track, 'bonus'/'bonus2' its
# bonus outfits (a piece if it has none), 'wall'/'floor' its surfaces; a number is Beans, alone or beside an item.
FREE = {
    1: ['piece'], 2: [25], 3: ['piece'], 4: ['piece'], 5: ['piece'], 6: [30], 7: ['piece'], 8: ['piece'], 9: [35],
    10: ['bonus', 25], 11: ['piece'], 12: [40], 13: ['piece'], 14: ['piece', 'piece'], 15: [45], 16: ['piece'],
    17: ['piece'], 18: [50], 19: ['piece'], 20: ['outfit', 50],
}
PREMIUM = {
    1: ['piece'], 2: ['piece'], 3: ['piece', 30], 4: ['wall'], 5: ['piece'], 6: ['piece'], 7: [60], 8: ['piece'],
    9: ['piece', 40], 10: ['piece', 'piece'], 11: ['piece'], 12: ['bonus'], 13: ['piece'], 14: [75],
    15: ['piece', 50], 16: ['floor'], 17: ['piece'], 18: ['piece', 40], 19: ['piece'], 20: ['piece', 'piece'],
    21: [90], 22: ['bonus2'], 23: ['piece'], 24: ['piece', 60], 25: ['piece'], 26: ['piece'], 27: [100],
    28: ['piece'], 29: ['piece', 'piece'], 30: ['outfit'],
}
FREE_PIECES = sum(slot.count('piece') for slot in FREE.values())          # 13 (one more with no free bonus outfit)
PREMIUM_PIECES = sum(slot.count('piece') for slot in PREMIUM.values())    # 24 (one more with no second bonus outfit)

# How special each piece is (uncommon if not listed): the season's grand pieces legendary, furniture and the bigger
# things rare, the little extras common.
RARITY = {
    'pass_blackcat_pumpkinbed': 'legendary', 'pass_blackcat_catcastle': 'legendary',
    'pass_blackcat_spookytree': 'legendary',
    **{f'pass_blackcat_{k}': 'rare' for k in (
        'jackolantern', 'velvetchair', 'catportrait', 'cobwebhammock', 'moonlamp', 'catrug', 'rockingchair', 'booknook',
        'telescope', 'grandclock', 'gramophone', 'pumpkinpatch', 'toadstool', 'pumpkinpouffe', 'leafpile')},
    **{f'pass_blackcat_{k}': 'common' for k in ('pumpkintrio', 'applecrate', 'yarnbasket', 'humbugjar')},
    'pass_housewarming_housebed': 'legendary', 'pass_housewarming_eggchair': 'legendary',
    'pass_housewarming_blanketfort': 'legendary',
    **{f'pass_housewarming_{k}': 'rare' for k in (
        'fairylights', 'teachest', 'picnicblanket', 'velvetsofa', 'gallerywall', 'recordcrate', 'leaningmirror',
        'bicycle', 'arclamp', 'plantgift', 'sleepingbag', 'boxtunnel', 'cratetable', 'housescratcher')},
    **{f'pass_housewarming_{k}': 'common' for k in ('movingboxes', 'painttins', 'takeaway', 'laundrybag', 'breadsalt')},
    'pass_midwinter_firtree': 'legendary', 'pass_midwinter_knitblanket': 'rare', 'pass_midwinter_sledge': 'rare',
    'pass_firstlight_birdbox': 'rare', 'pass_firstlight_hamper': 'rare',
}


def bc(*keys: str) -> list[str]:
    return [f'pass_blackcat_{k}' for k in keys]


def hw(*keys: str) -> list[str]:
    return [f'pass_housewarming_{k}' for k in keys]


# id, name, theme, start, end (exclusive), Christmas, free pieces (in order), the free track's outfit, premium pieces
# (in order; the first is the season's signature piece on tier 1), wallpaper, floor, bonus outfits, the season's own
# outfit, and pieces it borrows from the shop until its own set is painted.
SEASONS = [
    dict(id="blackcat", name="Black Cat",
         theme="Midnight's own month: lamplight, conkers and Black Cat Day on 27 October.",
         start="2026-10-05", end="2026-11-02", christmas=False,
         free=bc('conkerbowl', 'pumpkintrio', 'yarnbasket', 'ghosttoy', 'applecrate', 'lantern', 'leafpile', 'cocoa',
                 'candles', 'batbunting', 'mushroomlamp', 'pumpkinpouffe', 'toadstool'),
         free_outfit="bellcollar", free_bonus=["toadstoolhat"],
         premium=bc('pumpkinbed', 'ghostlamp', 'batcushion', 'jackolantern', 'humbugjar', 'velvetchair', 'owlclock',
                    'catportrait', 'catdoorstop', 'cobwebhammock', 'lanternstring', 'catcastle', 'rockingchair',
                    'conkertree', 'applebob', 'moonlamp', 'catrug', 'gramophone', 'haybale', 'pumpkinpatch',
                    'spookytree', 'booknook', 'telescope', 'grandclock'),
         wall="wall_pass_blackcat_midnight_bats", floor="floor_pass_blackcat_conker_parquet",
         bonus=["pumpkinhat", "batheadband"], outfit="skeleton"),
    dict(id="housewarming", name="Housewarming",
         theme="Moving in: boxes, tea chests and the first night in a new home.",
         start="2026-11-02", end="2026-12-01", christmas=False,
         free=hw('keysdish', 'movingboxes', 'bubblewrap', 'firstcuppa', 'painttins', 'floorcushion', 'plantgift',
                 'toolbox', 'takeaway', 'cardstring', 'flatpack', 'sleepingbag', 'laundrybag', 'boxtunnel'),
         free_outfit="scarf",
         premium=hw('housebed', 'candle', 'beanbag', 'fairylights', 'breadsalt', 'velvetsofa', 'swatchboard',
                    'gallerywall', 'housecake', 'teachest', 'plantstand', 'eggchair', 'recordcrate', 'leaningmirror',
                    'welcomewreath', 'picnicblanket', 'paperlantern', 'cratetable', 'stepladder', 'blankettrunk',
                    'blanketfort', 'bookstack', 'bicycle', 'arclamp', 'housescratcher'),
         wall="wall_pass_housewarming_apricot_houses", floor="floor_pass_housewarming_birch", bonus=["flatcap"],
         outfit="crown"),
    dict(id="midwinter", name="Midwinter",
         theme="Christmas, every December: the fir tree, the wreath and long evenings in.",
         start="2026-12-01", end="2026-12-29", christmas=True,
         free=['pass_midwinter_logbasket', 'bedroom_slippers', 'study_mug', 'pass_midwinter_hotwaterbottle',
               'kitchen_kettle', 'attic_oillamp', 'pass_midwinter_wreath', 'bedroom_readinglamp', 'kitchen_breadbin',
               'attic_suitcase', 'bedroom_alarmclock', 'kitchen_fruitbowl', 'bedroom_laundry', 'attic_cobweb'],
         free_outfit="antlers",
         premium=['pass_midwinter_firtree', 'living_record', 'attic_wireless', 'pass_midwinter_snowglobe',
                  'garden_festoon', 'attic_rockinghorse', 'living_radiator', 'pass_midwinter_knitblanket',
                  'bedroom_hammock', 'attic_dustyarmchair', 'bedroom_bedrug', 'living_fireplace', 'study_globe',
                  'pass_midwinter_sledge', 'attic_rolledrug', 'bedroom_mirror', 'kitchen_herbshelf', 'study_desklamp',
                  'attic_telescope', 'study_noticeboard', 'bedroom_curtains', 'kitchen_fountain', 'study_blind',
                  'garden_deckchair', 'garden_gardenhammock'],
         wall="wall_pass_midwinter_tartan", floor="floor_pass_midwinter_cherry", bonus=["xmasjumper"],
         outfit="santahat"),
    dict(id="firstlight", name="First Light",
         theme="The first light of the new year: seedlings on the sill and wellies by the door.",
         start="2026-12-29", end="2027-01-26", christmas=False,
         free=['pass_firstlight_seedtrays', 'garden_flowerpots', 'kitchen_herbshelf', 'pass_firstlight_wellies',
               'study_mug', 'kitchen_fruitbowl', 'pass_firstlight_pegbag', 'bedroom_slippers', 'kitchen_kettle',
               'bedroom_readinglamp', 'kitchen_breadbin', 'bedroom_alarmclock', 'kitchen_doormat', 'garden_wateringcan'],
         free_outfit="bandana",
         premium=['pass_firstlight_tulips', 'garden_washingline', 'garden_deckchair', 'pass_firstlight_birdbox',
                  'study_globe', 'bedroom_curtains', 'garden_pond', 'pass_firstlight_hamper', 'garden_gardenhammock',
                  'kitchen_fountain', 'pass_firstlight_butterflyjar', 'bedroom_hammock', 'study_desklamp',
                  'pass_firstlight_daffodils', 'garden_festoon', 'study_blind', 'bedroom_mirror', 'attic_telescope',
                  'living_radiator', 'attic_rolledrug', 'living_record', 'bedroom_bedrug', 'study_noticeboard',
                  'attic_wireless', 'attic_rockinghorse'],
         wall="wall_pass_firstlight_primrose_daffodil", floor="floor_pass_firstlight_green_tiles", bonus=["froghat"],
         outfit="flowercrown"),
]


def reward(tier: int, kind: str, id_: str | None = None, amount: int | None = None) -> dict:
    if kind == 'beans':
        rarity = 'common'
    elif kind == 'outfit':
        rarity = 'legendary'
    elif kind == 'surface':
        rarity = 'rare'
    else:
        rarity = RARITY.get(id_, 'uncommon')
    return {"tier": tier, "kind": kind, "id": id_, "amount": amount, "rarity": rarity}


def lay_out(template: dict, season: dict, pieces: list[str], outfit: str, bonus: list[str]) -> list[dict]:
    pieces = list(pieces)
    bonus = list(bonus)
    out = []
    for tier, slots in sorted(template.items()):
        for slot in slots:
            if isinstance(slot, int):
                out.append(reward(tier, 'beans', amount=slot))
            elif slot == 'outfit':
                out.append(reward(tier, 'outfit', outfit))
            elif slot in ('bonus', 'bonus2') and bonus:
                out.append(reward(tier, 'outfit', bonus.pop(0)))
            elif slot in ('wall', 'floor'):
                out.append(reward(tier, 'surface', season[slot]))
            else:
                # A piece (or a bonus outfit's place in a season with only one): the season's next piece.
                if not pieces:
                    raise SystemExit(f"{season['id']}: out of pieces at tier {tier}")
                out.append(reward(tier, 'item', pieces.pop(0)))
    if pieces:
        raise SystemExit(f"{season['id']}: {len(pieces)} pieces left over: {pieces}")
    return out


def main() -> None:
    seasons = []
    for s in SEASONS:
        free = lay_out(FREE, s, s['free'], s['free_outfit'], s.get('free_bonus', []))
        premium = lay_out(PREMIUM, s, s['premium'], s['outfit'], s.get('bonus', []))
        seasons.append({
            "id": s['id'], "name": s['name'], "theme": s['theme'], "startAt": s['start'], "endAt": s['end'],
            "provisional": True, "christmas": s['christmas'], "sku": f"housecat.pass.{s['id']}",
            "freeTrack": free, "paidTrack": premium,
        })
    data = {"version": 3, "seasonLengthDays": 28, "tiers": TIERS, "freeTiers": FREE_TIERS, "launchAt": LAUNCH,
            "seasons": seasons}
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    for s in seasons:
        for track in ('freeTrack', 'paidTrack'):
            rewards = s[track]
            beans = sum(r['amount'] or 0 for r in rewards if r['kind'] == 'beans')
            items = sum(1 for r in rewards if r['kind'] != 'beans')
            print(f"{s['id']:13s} {track:9s} {items:2d} items, {beans:4d} Beans")


if __name__ == "__main__":
    main()

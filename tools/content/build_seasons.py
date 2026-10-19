#!/usr/bin/env python3
"""Writes Content/seasons.json: the seasons and their two tracks (the season pass, Josh 19 Oct 2026: the game's main
progression, a free track and a premium one, a season always running).

Thirty tiers. The free track has a reward on each of the first twenty (Beans, a piece of the season's furniture on
5, 10 and 15, its free outfit on 20). The premium track has one on every tier to thirty: the season's signature
piece on 1, its wallpaper on 4, pieces on 8, 18, 22 and 26, a second outfit on 12, its floor on 15 and its own
outfit on 30, Beans in between rising from 40 to 110. A season short of a piece gets Beans there instead.

Seasons sit on HouseCatCore's SeasonCalendar (December is always Midwinter); slots after the last one here run a
season again (SeasonSchedule), so the pass never stops. Black Cat (5 Oct - 2 Nov 2026) comes before the launch
season so the pass is there for TestFlight and App Review; it has no paintings of its own, so its pieces come from
the Bean shop and its outfits are October's.

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

FREE_SLOTS = {5: "piece0", 10: "piece1", 15: "piece2", 20: "outfit"}
FREE_BEANS = {1: 20, 2: 20, 3: 25, 4: 25, 6: 30, 7: 30, 8: 35, 9: 35, 11: 35, 12: 40, 13: 40, 14: 40,
              16: 45, 17: 45, 18: 50, 19: 50}
PREMIUM_SLOTS = {1: "piece0", 4: "wall", 8: "piece1", 12: "bonus", 15: "floor", 18: "piece2", 22: "piece3",
                 26: "piece4", 30: "outfit"}


def premium_beans(tier: int) -> int:
    """40 at tier 1 rising to 110 at tier 30, in fives."""
    return 40 + 5 * ((tier - 1) * 14 // 29)


# id, name, theme, start, end (exclusive), Christmas, free pieces, free outfit, premium pieces, wall, floor,
# second outfit, the season's own outfit.
SEASONS = [
    dict(id="blackcat", name="Black Cat",
         theme="Midnight's own month: lamplight, conkers and Black Cat Day on 27 October.",
         start="2026-10-05", end="2026-11-02", christmas=False,
         free=["living_clock", "kitchen_radio", "living_bookcase"], free_outfit="bellcollar",
         premium=["living_cattree", "living_windowseat", "bedroom_catbed", "garden_sunpatch", "kitchen_catflap"],
         wall="wall_living_mint_stripe", floor="floor_living_honey_boards", bonus="pumpkinhat", outfit="skeleton"),
    dict(id="housewarming", name="Housewarming",
         theme="Moving in: boxes, tea chests and the first night in a new home.",
         start="2026-11-02", end="2026-12-01", christmas=False,
         free=["pass_housewarming_movingboxes", "pass_housewarming_painttins", "pass_housewarming_takeaway"],
         free_outfit="scarf",
         premium=["pass_housewarming_fairylights", "pass_housewarming_teachest", "pass_housewarming_picnicblanket",
                  "pass_housewarming_stepladder", "pass_housewarming_candle"],
         wall="wall_pass_housewarming_apricot_houses", floor="floor_pass_housewarming_birch", bonus="flatcap",
         outfit="crown"),
    dict(id="midwinter", name="Midwinter",
         theme="Christmas, every December: the fir tree, the wreath and long evenings in.",
         start="2026-12-01", end="2026-12-29", christmas=True,
         free=["pass_midwinter_logbasket", "pass_midwinter_hotwaterbottle", "pass_midwinter_wreath"],
         free_outfit="antlers",
         premium=["pass_midwinter_knitblanket", "pass_midwinter_snowglobe", "pass_midwinter_sledge",
                  "pass_midwinter_firtree"],
         wall="wall_pass_midwinter_tartan", floor="floor_pass_midwinter_cherry", bonus="xmasjumper",
         outfit="santahat"),
    dict(id="firstlight", name="First Light",
         theme="The first light of the new year: seedlings on the sill and wellies by the door.",
         start="2026-12-29", end="2027-01-26", christmas=False,
         free=["pass_firstlight_seedtrays", "pass_firstlight_wellies", "pass_firstlight_pegbag"],
         free_outfit="bandana",
         premium=["pass_firstlight_tulips", "pass_firstlight_birdbox", "pass_firstlight_hamper",
                  "pass_firstlight_butterflyjar", "pass_firstlight_daffodils"],
         wall="wall_pass_firstlight_primrose_daffodil", floor="floor_pass_firstlight_green_tiles", bonus="froghat",
         outfit="flowercrown"),
]


def reward(tier: int, kind: str, id_: str | None = None, amount: int | None = None) -> dict:
    return {"tier": tier, "kind": kind, "id": id_, "amount": amount}


def slot_reward(tier: int, slot: str, season: dict, pieces: list[str], outfit: str, beans: int) -> dict:
    if slot.startswith("piece"):
        index = int(slot[5:])
        return reward(tier, "item", pieces[index]) if index < len(pieces) else reward(tier, "beans", amount=beans)
    if slot == "outfit":
        return reward(tier, "outfit", outfit)
    if slot == "bonus":
        return reward(tier, "outfit", season["bonus"])
    if slot in ("wall", "floor"):
        return reward(tier, "surface", season[slot])
    raise ValueError(slot)


def main() -> None:
    seasons = []
    for s in SEASONS:
        free = [slot_reward(t, FREE_SLOTS[t], s, s["free"], s["free_outfit"], 0) if t in FREE_SLOTS
                else reward(t, "beans", amount=FREE_BEANS[t]) for t in range(1, FREE_TIERS + 1)]
        premium = [slot_reward(t, PREMIUM_SLOTS[t], s, s["premium"], s["outfit"], premium_beans(t)) if t in PREMIUM_SLOTS
                   else reward(t, "beans", amount=premium_beans(t)) for t in range(1, TIERS + 1)]
        seasons.append({
            "id": s["id"], "name": s["name"], "theme": s["theme"], "startAt": s["start"], "endAt": s["end"],
            "provisional": True, "christmas": s["christmas"], "sku": f"housecat.pass.{s['id']}",
            "freeTrack": free, "paidTrack": premium,
        })
    data = {"version": 2, "seasonLengthDays": 28, "tiers": TIERS, "freeTiers": FREE_TIERS, "launchAt": LAUNCH,
            "seasons": seasons}
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    for s in seasons:
        beans = sum(r["amount"] or 0 for r in s["paidTrack"] if r["kind"] == "beans")
        free_beans = sum(r["amount"] or 0 for r in s["freeTrack"] if r["kind"] == "beans")
        print(f"{s['id']}: free {free_beans} Beans, premium {beans} Beans")


if __name__ == "__main__":
    main()

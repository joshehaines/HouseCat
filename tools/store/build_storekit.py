#!/usr/bin/env python3
"""Builds Store/HouseCat.storekit, the local StoreKit configuration for the
simulator and the StoreKit tests, from the content files.

It mirrors StoreCatalog.swift (Packages/HouseCatStore): every launch product
in SPEC.md "Monetisation and the shop" with the right type, the Cat Club
subscription group with the 7-day free trial as an introductory offer on the
yearly plan, non-renewing season passes and consumable gifts. No rare looks.
A test checks the two agree.

Run from the repo root: python3 -I tools/store/build_storekit.py
"""
from __future__ import annotations

import json
import pathlib
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTENT = ROOT / "Content"
OUT = ROOT / "Store" / "HouseCat.storekit"
LOCALE = "en_GB"


def internal_id(product_id: str) -> str:
    """A stable numeric id per product, so regenerating changes nothing."""
    return str(6_700_000_000 + zlib.crc32(product_id.encode()) % 99_999_999)


def localisation(name: str, description: str) -> list:
    return [{"description": description, "displayName": name, "locale": LOCALE}]


def product(product_id: str, kind: str, price: str, name: str, description: str, family: bool = False) -> dict:
    return {
        "displayPrice": price,
        "familyShareable": family,
        "internalID": internal_id(product_id),
        "localizations": localisation(name, description),
        "productID": product_id,
        "referenceName": name,
        "type": kind,
    }


def main() -> None:
    outfits = json.loads((CONTENT / "outfits.json").read_text())["outfits"]
    catalogue = json.loads((CONTENT / "catalogue.json").read_text())
    seasons = json.loads((CONTENT / "seasons.json").read_text())["seasons"]
    sets = catalogue["sets"]

    products = []
    for outfit in outfits:
        if outfit["pool"] == "paid":
            products.append(product(f"housecat.outfit.{outfit['id']}", "NonConsumable", "0.99", outfit["name"],
                                    f"The {outfit['name'].lower()}, for any cat, kept forever."))
    for s in sets:
        products.append(product(f"housecat.set.{s['id']}", "NonConsumable", "2.99", s["name"],
                                f"The {s['name']} set: seven pieces, a wallpaper and a floor."))
        products.append(product(f"housecat.bundle.{s['id']}", "NonConsumable", "4.99", f"{s['name']} Bundle",
                                f"The {s['name']} set, its outfit and {s['bundleBeans']} Beans."))
    for slot in (2, 3, 4):
        products.append(product(f"housecat.cat.slot{slot}", "NonConsumable", "4.99", "Adopt a Cat",
                                "Another cat for the house, built your way, with its own personality."))
    products += [
        product("housecat.starter", "NonConsumable", "1.99", "Starter Pack", "An outfit, a furniture set and 500 Beans. Once only."),
        product("housecat.season.housewarming", "NonConsumable", "4.99", "Housewarming Pack",
                "A grand fireplace, a hi-fi, string lights, a welcome mat and more, with 300 Beans."),
        product("housecat.lifetime", "NonConsumable", "39.99", "Forever Home", "Everything in Cat Club, forever."),
        product("housecat.founders", "NonConsumable", "29.99", "Founders' Pack",
                "A numbered plaque for the house, an exclusive outfit and Cat Club forever."),
        product("housecat.gift.club.yearly", "Consumable", "19.99", "Gift: Cat Club Yearly", "A year of Cat Club for a friend."),
        product("housecat.gift.cat", "Consumable", "4.99", "Gift: Adopt a Cat", "Another cat for a friend's house."),
    ]
    for s in sets:
        products.append(product(f"housecat.gift.set.{s['id']}", "Consumable", "2.99", f"Gift: {s['name']}",
                                f"The {s['name']} set for a friend."))
    products.append(product("housecat.gift.pass", "Consumable", "4.99", "Gift: Season Pass", "This season's paid track for a friend."))

    passes = [
        product(f"housecat.pass.{season['id']}", "NonRenewingSubscription", "4.99", f"{season['name']} Pass",
                f"The {season['name']} paid track, {season['startAt']} to {season['endAt']}. Everything earned is kept.")
        for season in seasons
    ]

    group_id = internal_id("housecat.club")
    def subscription(product_id: str, price: str, name: str, period: str, offer: dict | None) -> dict:
        entry = product(product_id, "RecurringSubscription", price, name,
                        "Monthly outfit, an extra cat, +20% Beans, rooms at half the Beans and every season pass.", family=True)
        entry.update({
            "adHocOffers": [],
            "codeOffers": [],
            "groupNumber": 1,
            "introductoryOffer": offer,
            "recurringSubscriptionPeriod": period,
            "subscriptionGroupID": group_id,
            "winbackOffers": [],
        })
        return entry

    trial = {"internalID": internal_id("housecat.club.yearly.trial"), "numberOfPeriods": 1, "paymentMode": "free",
             "subscriptionPeriod": "P1W"}
    configuration = {
        "identifier": "8C1A7E52",
        "nonRenewingSubscriptions": passes,
        "products": products,
        "settings": {"_failTransactionsEnabled": False, "_locale": LOCALE, "_storefront": "GBR", "_storeKitErrors": []},
        "subscriptionGroups": [{
            "id": group_id,
            "localizations": [],
            "name": "Cat Club",
            "subscriptions": [
                subscription("housecat.club.monthly", "2.99", "Cat Club Monthly", "P1M", None),
                subscription("housecat.club.yearly", "19.99", "Cat Club Yearly", "P1Y", trial),
            ],
        }],
        "version": {"major": 4, "minor": 0},
    }
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(configuration, indent=2, sort_keys=True) + "\n")
    count = len(products) + len(passes) + 2
    print(f"Wrote {OUT.relative_to(ROOT)}: {count} products")


if __name__ == "__main__":
    main()

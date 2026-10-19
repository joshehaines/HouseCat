#!/usr/bin/env python3
"""Builds Store/HouseCat.storekit, the local StoreKit configuration for the
simulator and the StoreKit tests, from the content files.

It mirrors StoreCatalog.swift (Packages/HouseCatStore): consumable Bean packs
and the once-only starter, a non-consumable per room look (Content/bundles.json),
a non-consumable premium pass per season (Content/seasons.json; Josh, 19 Oct:
the pass is the main thing sold), and the Cat Club subscription group with the
7-day free trial as an introductory offer on the yearly plan. A test checks the
two agree.

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
    bundles = json.loads((CONTENT / "bundles.json").read_text())["bundles"]
    seasons = json.loads((CONTENT / "seasons.json").read_text())["seasons"]
    # The Bean packs and the starter offer: keep in step with StoreCatalog.beanPacks and Tuning.Beans.
    packs = [("housecat.beans.handful", 500, "0.99", "A handful of Beans"), ("housecat.beans.pouch", 1200, "1.99", "A pouch of Beans"),
             ("housecat.beans.jar", 2600, "3.99", "A jar of Beans"), ("housecat.beans.sack", 7000, "9.99", "A sack of Beans"),
             ("housecat.beans.barrel", 15000, "19.99", "A barrel of Beans")]

    products = [product(pid, "Consumable", price, name, f"{beans:,} Beans for furniture, outfits, rooms and presents.")
                for pid, beans, price, name in packs]
    products.append(product("housecat.starter", "NonConsumable", "1.99", "Starter Beans", "2,000 Beans to get you going. Once only."))
    for b in bundles:
        products.append(product(b["sku"], "NonConsumable", b["price"], b["name"], b["blurb"][:55]))
    # Each season's premium pass: keep the price in step with StoreCatalog.passPriceGBP, the name with passDisplayName.
    for s in seasons:
        name, description = f"{s['name']} Premium Pass", f"The {s['name']} season's 30 premium rewards."
        assert len(name) <= 35 and len(description) <= 55, s["id"]
        products.append(product(s["sku"], "NonConsumable", "2.99", name, description))
    passes = []

    group_id = internal_id("housecat.club")
    def subscription(product_id: str, price: str, name: str, period: str, offer: dict | None) -> dict:
        entry = product(product_id, "RecurringSubscription", price, name,
                        "+20% Beans, rooms for half the Beans, free moves and every season's paid track.", family=True)
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

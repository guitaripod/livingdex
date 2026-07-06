#!/usr/bin/env python3
"""Idempotent creation of Living Dex's consumable credit-pack IAPs in ASC.

The mako backend already defines the packs (migrations/014_seed_livingdex.sql):
product id = com.guitaripod.livingdex.credits.<pack_id>, mapped to a credit
amount. This script creates the matching App Store consumables — each with an
en-US localization and a USD base price — so RevenueCat can surface live pricing
and the in-app credit store stops showing blank prices. Skips anything whose
productId already exists, so it is safe to re-run.

Pro (the subscription) is the primary monetization; these packs are the
non-subscriber / whale fallback, priced to stay clearly worse value than a month
of unlimited Pro so they nudge toward the sub.

NOTE (OPERATIONS.md): the FIRST product submission for an app with zero approved
products needs a one-time web-UI selection on the version; and each IAP needs a
review screenshot before it can be submitted. This script creates + prices the
products; screenshots and final submission ride the version review.

Usage: python3 scripts/asc-products.py
"""
import os
import sys

sys.path.insert(0, os.path.expanduser("~/Dev/operator/lib"))
import asc  # noqa: E402

APP = "6787688416"
PREFIX = "com.guitaripod.livingdex"

# (pack_id, App Store reference name, display name, description, USD price)
# Credits/prices mirror mako's credit_packs seed; a Sonnet cloud ID ~= 3 credits.
PACKS = [
    ("starter", "Credits Starter 100", "Starter · 100 Credits", "About 30 cloud identifications.", 2.99),
    ("regular", "Credits Regular 400", "Regular · 400 Credits", "A season of discovery — about 130 IDs.", 9.99),
    ("propack", "Credits Explorer 1200", "Explorer · 1200 Credits", "For the relentless collector — ~400 IDs.", 24.99),
    ("science", "Credits Naturalist 2600", "Naturalist · 2600 Credits", "Identify everything — about 860 IDs.", 49.99),
]


def closest_point(points, target):
    best, bestd = None, 1e18
    for p in points:
        try:
            price = float(p["attributes"].get("customerPrice"))
        except (TypeError, ValueError):
            continue
        d = abs(price - target)
        if d < bestd:
            best, bestd = p, d
    return best


def existing_iaps():
    return asc.paged(f"/v1/apps/{APP}/inAppPurchasesV2", **{"limit": "200"})


def try_(label, fn):
    try:
        fn()
        return True
    except Exception as e:
        print(f"    ! {label}: {str(e)[:180]}")
        return False


def ensure_iap(product_id, ref, display, description, price):
    by_pid = {i["attributes"]["productId"]: i for i in existing_iaps()}
    if product_id in by_pid:
        iap_id = by_pid[product_id]["id"]
        print(f"  ✓ exists {product_id} — ensuring price")
    else:
        r = asc.post("/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
            "name": ref, "productId": product_id, "inAppPurchaseType": "CONSUMABLE",
            "familySharable": False},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        iap_id = r["data"]["id"]
        try_("localization", lambda: asc.post("/v1/inAppPurchaseLocalizations", {"data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"locale": "en-US", "name": display, "description": description},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))
        print(f"  + created {product_id} (CONSUMABLE, ${price})")
    pts = asc.paged(f"/v2/inAppPurchases/{iap_id}/pricePoints", **{"filter[territory]": "USA", "limit": "200"})
    pt = closest_point(pts, price)
    if pt:
        try_("price", lambda: asc.post("/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${p}",
                "attributes": {"startDate": None},
                "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pt["id"]}}}}]}))
    else:
        print("    ! no USA price point found")
    return iap_id


def main():
    print("Living Dex consumable credit packs:")
    for pack_id, ref, display, description, price in PACKS:
        ensure_iap(f"{PREFIX}.credits.{pack_id}", ref, display, description, price)
    print("DONE")


if __name__ == "__main__":
    main()

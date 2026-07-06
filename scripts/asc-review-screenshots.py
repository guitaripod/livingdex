#!/usr/bin/env python3
"""Attach an App Review screenshot to every Living Dex consumable IAP.

IAPs sit in MISSING_METADATA — and are therefore NOT returned by StoreKit, so the
in-app credit store shows blank prices — until they carry a review screenshot.
Uses a credit-store screenshot for all of them. Same reserve → PUT → commit flow
as listing screenshots. Idempotent (skips any IAP that already has one).

Usage: python3 scripts/asc-review-screenshots.py [image.png]
"""
import hashlib
import os
import sys

import requests

sys.path.insert(0, os.path.expanduser("~/Dev/operator/lib"))
import asc  # noqa: E402

APP = "6787688416"
IMG = sys.argv[1] if len(sys.argv) > 1 else "/tmp/iap_review.png"


def upload(iap_id):
    data = open(IMG, "rb").read()
    reserve = asc.post("/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots",
        "attributes": {"fileSize": len(data), "fileName": "credit-store.png"},
        "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})
    sid = reserve["data"]["id"]
    for op in reserve["data"]["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        requests.request(op["method"], op["url"], headers=headers,
                         data=data[op["offset"]:op["offset"] + op["length"]], timeout=120).raise_for_status()
    asc.patch(f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def main():
    for i in asc.paged(f"/v1/apps/{APP}/inAppPurchasesV2", **{"limit": "50"}):
        iid, pid = i["id"], i["attributes"]["productId"]
        if asc.get(f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot").get("data"):
            print(f"  ✓ {pid} already has a review screenshot")
            continue
        upload(iid)
        print(f"  + {pid}")
    print("DONE")


if __name__ == "__main__":
    main()

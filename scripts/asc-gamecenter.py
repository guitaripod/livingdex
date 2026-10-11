#!/usr/bin/env python3
"""Idempotent Game Center provisioner for Living Dex, driven through the `asc` CLI.

Mirrors LivingDex/GameCenter/Achievements.swift, which is the source of truth: an
achievement added there is added here in the same change. Ensures the app's
gameCenterDetail, every achievement and the species leaderboard with their en-US
localizations, SF-Symbol artwork on the app's emerald gradient, and the
gameCenterAppVersion for the editable App Store version so Game Center rides the
next review submission. Nothing is submitted for review and no release objects
are created.

Run `source ~/.config/midgar/credentials.env` first; without it `asc` blocks on the
keychain. Rendering needs `swift` (AppKit SF Symbols) and Pillow.

Usage: python3 scripts/asc-gamecenter.py [--no-images]
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image

APP_ID = "6787688416"
PREFIX = "com.guitaripod.livingdex."
ICON_SIDE = 1024
SETTLED_STATES = ("COMPLETE", "UPLOAD_COMPLETE")

ACHIEVEMENTS = [
    ("ach.first_catch", "camera.fill", "", "First Catch", 5,
     "Collect your very first species.",
     "Your Living Dex has begun. One down, millions to go."),
    ("ach.species_10", "leaf.fill", "10", "Ten Species", 10,
     "Collect 10 different species.",
     "Ten species in the book. You are getting the hang of this."),
    ("ach.species_50", "tree.fill", "50", "Fifty Species", 25,
     "Collect 50 different species.",
     "Fifty species. Your Dex is starting to look like a real field guide."),
    ("ach.species_100", "books.vertical.fill", "100", "Centurion", 50,
     "Collect 100 different species.",
     "One hundred species. Nature should be asking you for tips."),
    ("ach.all_realms", "globe.europe.africa.fill", "", "All Realms", 25,
     "Catch an animal, a plant and a fungus.",
     "Animal, plant and fungus: all three realms are in your Dex."),
    ("ach.first_rare", "sparkles", "", "Rare Find", 15,
     "Find your first Rare or better species.",
     "A Rare find. Not everyone spots one of those."),
    ("ach.first_legendary", "crown.fill", "", "Legendary Find", 40,
     "Find your first Legendary species.",
     "A Legendary find. Go tell somebody, they will not believe you."),
    ("ach.streak_7", "flame.fill", "7", "Week Streak", 25,
     "Catch something every day for 7 days in a row.",
     "Seven days in a row. The wild never sleeps and neither do you."),
]

LEADERBOARDS = [
    ("lb.species", "trophy.fill", "", "Species Collected", "species", "species"),
]

SWIFT_RENDERER = r'''
import AppKit
import Foundation

struct Entry: Decodable {
    let slug: String
    let symbol: String
    let tier: String
}

let arguments = CommandLine.arguments
let entries = try JSONDecoder().decode(
    [Entry].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let outDir = URL(fileURLWithPath: arguments[2])
let side: CGFloat = 1024

func hex(_ value: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

for entry in entries {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    NSGradient(starting: hex(0x34D399), ending: hex(0x0F766E))?
        .draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: -90)

    let hasTier = !entry.tier.isEmpty
    let configuration = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else {
        FileHandle.standardError.write(Data("missing symbol: \(entry.symbol)\n".utf8))
        exit(1)
    }
    let bound: CGFloat = hasTier ? 480 : 560
    let scale = min(bound / max(symbol.size.width, symbol.size.height), 8)
    let drawSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    let centerY: CGFloat = hasTier ? side * 0.57 : side / 2
    symbol.draw(
        in: NSRect(
            x: (side - drawSize.width) / 2, y: centerY - drawSize.height / 2,
            width: drawSize.width, height: drawSize.height),
        from: .zero, operation: .sourceOver, fraction: 1)

    if hasTier {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 150, weight: .heavy),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: entry.tier, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (side - size.width) / 2, y: side * 0.1))
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("render failed: \(entry.slug)\n".utf8))
        exit(1)
    }
    try png.write(to: outDir.appendingPathComponent("\(entry.slug).png"))
}
'''


def asc(*args):
    """Run an `asc` subcommand and return its parsed JSON output."""
    result = subprocess.run(
        ["asc", *args], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if result.returncode != 0:
        sys.exit(f"asc {' '.join(args)} failed:\n{result.stdout}{result.stderr}")
    text = result.stdout.strip()
    return json.loads(text.splitlines()[-1]) if text else {}


def rows(*args):
    """Return the `data` rows of a list command, following pages when it supports them."""
    paginated = args[:2] != ("game-center", "details")
    return asc(*args, *(["--paginate"] if paginated else [])).get("data", [])


def ensure_detail():
    """Return the app's gameCenterDetail id, creating it when missing."""
    found = rows("game-center", "details", "list", "--app", APP_ID)
    if found:
        print(f"gameCenterDetail: {found[0]['id']}")
        return found[0]["id"]
    made = asc("game-center", "details", "create", "--app", APP_ID)["data"]["id"]
    print(f"gameCenterDetail: created {made}")
    return made


def ensure_achievements():
    """Create missing achievements and en-US localizations; return slug -> localization id."""
    have = {
        r["attributes"]["vendorIdentifier"]: r["id"]
        for r in rows("game-center", "achievements", "list", "--app", APP_ID)}
    locs = {}
    for slug, _, _, name, points, before, after in ACHIEVEMENTS:
        vendor = PREFIX + slug
        if vendor not in have:
            have[vendor] = asc(
                "game-center", "achievements", "create", "--app", APP_ID,
                "--reference-name", name, "--vendor-id", vendor,
                "--points", str(points))["data"]["id"]
            print(f"achievement: created {vendor}")
        existing = {
            r["attributes"]["locale"]: r["id"]
            for r in rows(
                "game-center", "achievements", "localizations", "list",
                "--achievement-id", have[vendor])}
        if "en-US" not in existing:
            existing["en-US"] = asc(
                "game-center", "achievements", "localizations", "create",
                "--achievement-id", have[vendor], "--locale", "en-US", "--name", name,
                "--before-earned-description", before,
                "--after-earned-description", after)["data"]["id"]
            print(f"achievement: localized {vendor}")
        locs[slug] = existing["en-US"]
    return locs


def ensure_leaderboards():
    """Create missing leaderboards and en-US localizations; return slug -> localization id."""
    have = {
        r["attributes"]["vendorIdentifier"]: r["id"]
        for r in rows("game-center", "leaderboards", "list", "--app", APP_ID)}
    locs = {}
    for slug, _, _, name, singular, plural in LEADERBOARDS:
        vendor = PREFIX + slug
        if vendor not in have:
            have[vendor] = asc(
                "game-center", "leaderboards", "create", "--app", APP_ID,
                "--reference-name", name, "--vendor-id", vendor,
                "--formatter", "INTEGER", "--sort", "DESC",
                "--submission-type", "BEST_SCORE")["data"]["id"]
            print(f"leaderboard: created {vendor}")
        existing = {
            r["attributes"]["locale"]: r["id"]
            for r in rows(
                "game-center", "leaderboards", "localizations", "list",
                "--leaderboard-id", have[vendor])}
        if "en-US" not in existing:
            existing["en-US"] = asc(
                "game-center", "leaderboards", "localizations", "create",
                "--leaderboard-id", have[vendor], "--locale", "en-US", "--name", name,
                "--formatter-suffix-singular", singular,
                "--formatter-suffix", plural)["data"]["id"]
            print(f"leaderboard: localized {vendor}")
        locs[slug] = existing["en-US"]
    return locs


def render_icons(out_dir):
    """Render every catalog entry to a flat 1024x1024 RGB PNG in `out_dir`."""
    catalog = [
        {"slug": entry[0], "symbol": entry[1], "tier": entry[2]}
        for entry in ACHIEVEMENTS + LEADERBOARDS]
    spec = os.path.join(out_dir, "catalog.json")
    renderer = os.path.join(out_dir, "render.swift")
    with open(spec, "w") as handle:
        json.dump(catalog, handle)
    with open(renderer, "w") as handle:
        handle.write(SWIFT_RENDERER)
    subprocess.run(["swift", renderer, spec, out_dir], check=True)
    for entry in catalog:
        path = os.path.join(out_dir, f"{entry['slug']}.png")
        with Image.open(path) as raw:
            flat = raw.convert("RGB")
        if flat.size != (ICON_SIDE, ICON_SIDE):
            flat = flat.resize((ICON_SIDE, ICON_SIDE), Image.LANCZOS)
        flat.save(path, "PNG")


def image_state(kind, loc_id):
    """Return (image id, delivery state) for a localization's image, or (None, None)."""
    result = subprocess.run(
        ["asc", "game-center", kind, "localizations", "image", "view", "--id", loc_id],
        capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if result.returncode != 0 or not result.stdout.strip():
        return None, None
    data = json.loads(result.stdout.strip().splitlines()[-1]).get("data")
    if not data:
        return None, None
    delivery = data.get("attributes", {}).get("assetDeliveryState") or {}
    return data["id"], delivery.get("state")


def ensure_image(kind, loc_id, path, slug):
    """Upload `path` to a localization unless a settled image is already there."""
    image_id, state = image_state(kind, loc_id)
    if state in SETTLED_STATES:
        return
    if image_id:
        asc("game-center", kind, "images", "delete", "--id", image_id, "--confirm")
        print(f"image: discarded stale {slug} ({state})")
    asc("game-center", kind, "images", "upload",
        "--localization-id", loc_id, "--file", path)
    print(f"image: uploaded {slug}")


def push_images(achievement_locs, leaderboard_locs):
    """Render the artwork into a temp dir, upload it, and clean up."""
    with tempfile.TemporaryDirectory(prefix="livingdex-gc-") as out_dir:
        render_icons(out_dir)
        for slug, loc_id in achievement_locs.items():
            ensure_image("achievements", loc_id, os.path.join(out_dir, f"{slug}.png"), slug)
        for slug, loc_id in leaderboard_locs.items():
            ensure_image("leaderboards", loc_id, os.path.join(out_dir, f"{slug}.png"), slug)


def editable_version_id():
    """Return the id of the iOS App Store version still in PREPARE_FOR_SUBMISSION."""
    found = rows(
        "versions", "list", "--app", APP_ID, "--platform", "IOS",
        "--state", "PREPARE_FOR_SUBMISSION")
    if not found:
        sys.exit("no editable iOS App Store version to enable Game Center on")
    return found[0]["id"]


def ensure_app_version():
    """Make sure the editable App Store version has an enabled gameCenterAppVersion."""
    version_id = editable_version_id()
    for row in rows("game-center", "app-versions", "list", "--app", APP_ID):
        linked = asc("game-center", "app-versions", "app-store-version", "view",
                     "--id", row["id"])["data"]["id"]
        if linked != version_id:
            continue
        if row["attributes"].get("enabled") is not True:
            asc("game-center", "app-versions", "update", "--id", row["id"],
                "--enabled", "true")
            print(f"gameCenterAppVersion: enabled {row['id']}")
        else:
            print(f"gameCenterAppVersion: {row['id']} already enabled")
        return
    made = asc("game-center", "app-versions", "create",
               "--app-store-version-id", version_id)["data"]["id"]
    print(f"gameCenterAppVersion: created {made}")
    asc("game-center", "app-versions", "update", "--id", made, "--enabled", "true")


def main():
    total = sum(entry[4] for entry in ACHIEVEMENTS)
    assert total <= 1000, f"achievement points {total} exceed Game Center's 1000 budget"
    ensure_detail()
    achievement_locs = ensure_achievements()
    leaderboard_locs = ensure_leaderboards()
    if "--no-images" not in sys.argv:
        push_images(achievement_locs, leaderboard_locs)
    ensure_app_version()
    print(f"OK: {len(achievement_locs)} achievements ({total} points), "
          f"{len(leaderboard_locs)} leaderboards")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Composes the App Store screenshots: raw simulator captures -> `frames` bezel ->
realm-illustration backdrop, headline, sub-caption and shadow.
Usage: compose_screenshots.py RAW_DIR OUT_DIR [LOCALE]

LOCALE is an App Store locale (default en-US); its captions come from marketing/captions.json and its
typeface from FACES. RAW_DIR holds the phone captures (field, starter, reveal, caught, nearby, guide, card, profile .png at
1320x2868, from scripts/capture-demo-screens.sh) and cards/<name>.png, the trading cards rendered
by the `sharecards` demo route. The bezel always comes from the `frames` CLI; this script only
adds the artwork background, captions and shadow around the framed result.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

CANVAS = (1320, 2868)
FONTS = Path("/System/Library/Fonts")
FACES = {
    "default": {"heavy": (FONTS / "Avenir Next.ttc", 8), "medium": (FONTS / "Avenir Next.ttc", 5)},
    "ja": {"heavy": (FONTS / "ヒラギノ角ゴシック W8.ttc", 0), "medium": (FONTS / "ヒラギノ角ゴシック W5.ttc", 0)},
    "ko": {"heavy": (FONTS / "AppleSDGothicNeo.ttc", 14), "medium": (FONTS / "AppleSDGothicNeo.ttc", 2)},
    "zh-Hans": {"heavy": (FONTS / "Hiragino Sans GB.ttc", 2), "medium": (FONTS / "Hiragino Sans GB.ttc", 0)},
    "zh-Hant": {"heavy": (FONTS / "STHeiti Medium.ttc", 0), "medium": (FONTS / "STHeiti Light.ttc", 0)},
}
MARKETING = Path(__file__).resolve().parent
ART_DIR = MARKETING.parent / "Resources/Assets.xcassets"

PHONE_SHOTS = [
    ("field", "animals", (255, 176, 70)),
    ("starter", "fungi", (60, 214, 170)),
    ("reveal", "animals", (255, 140, 40)),
    ("caught", "plants", (110, 220, 120)),
    ("nearby", "fungi", (70, 200, 200)),
    ("guide", "protists", (80, 190, 230)),
    ("card", "animals", (230, 160, 70)),
]
CARD_SHOT = ("cards", "plants", (150, 120, 230))
PROFILE_SHOT = ("profile", "protists", (60, 200, 150))
ORDER = [
    "field", "starter", "reveal", "caught", "nearby", "guide", "card", "cards", "profile",
]


def font(face: tuple[Path, int], size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(face[0]), size, index=face[1])


def captions(locale: str) -> dict:
    """The headline lines and sub-caption of every shot in the locale, from marketing/captions.json."""
    table = json.loads((MARKETING / "captions.json").read_text(encoding="utf-8"))
    return table[locale]


def frame(raw: Path, out_dir: Path) -> Path:
    result = subprocess.run(
        ["frames", "-c", "Silver", "-o", str(out_dir), "--json", str(raw)],
        check=True, capture_output=True, text=True)
    return Path(json.loads(result.stdout)["output"])


def backdrop(realm: str, tint: tuple[int, int, int]) -> Image.Image:
    """The realm's illustration, enlarged to fill the canvas, softened, darkened and washed in the
    shot's accent so each screenshot has its own colour but all share one family."""
    art = Image.open(ART_DIR / f"realm-{realm}.imageset" / f"{realm}.jpg").convert("RGB")
    scale = CANVAS[1] / art.height
    art = art.resize((round(art.width * scale), CANVAS[1]), Image.LANCZOS)
    left = (art.width - CANVAS[0]) // 2
    art = art.crop((left, 0, left + CANVAS[0], CANVAS[1])).filter(ImageFilter.GaussianBlur(5))
    art = ImageEnhance.Brightness(art).enhance(0.52)
    fade = Image.linear_gradient("L").rotate(180).resize(CANVAS)
    strength = fade.point(lambda v: round(255 * (0.55 * (v / 255) ** 1.4 + 0.10)))
    wash = ImageChops.multiply(Image.new("RGB", CANVAS, tint), Image.merge("RGB", [strength] * 3))
    return ImageChops.screen(art, wash)


def fitted(text_lines: list[str], face: tuple[Path, int], size: int, width: int) -> ImageFont.FreeTypeFont:
    """The largest font up to `size` whose widest line fits in `width`."""
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    chosen = font(face, size)
    while max(probe.textlength(line, font=chosen) for line in text_lines) > width and chosen.size > 40:
        chosen = font(face, chosen.size - 2)
    return chosen


def caption(canvas: Image.Image, text: dict, faces: dict) -> int:
    lines, sub = text["headline"], text["sub"]
    draw = ImageDraw.Draw(canvas)
    head = fitted(lines, faces["heavy"], 134, CANVAS[0] - 150)
    y = 150
    for line in lines:
        width = draw.textlength(line, font=head)
        draw.text(((CANVAS[0] - width) / 2 + 3, y + 5), line, font=head, fill=(0, 0, 0, 120))
        draw.text(((CANVAS[0] - width) / 2, y), line, font=head, fill=(255, 255, 255))
        y += round(head.size * 1.13)
    small = fitted([sub], faces["medium"], 54, CANVAS[0] - 140)
    width = draw.textlength(sub, font=small)
    draw.text(((CANVAS[0] - width) / 2, y + 22), sub, font=small, fill=(255, 255, 255, 215))
    return y + 22 + small.size


def drop_shadow(canvas: Image.Image, layer: Image.Image, position: tuple[int, int], blur: int = 46, alpha: int = 150) -> Image.Image:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    silhouette = Image.new("RGBA", layer.size, (0, 0, 0, alpha))
    shadow.paste(silhouette, (position[0], position[1] + 36), layer.getchannel("A"))
    return Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(blur)))


def compose_phone(raw: Path, spec: tuple, text: dict, faces: dict, out: Path, work: Path) -> None:
    _, realm, tint = spec
    canvas = backdrop(realm, tint).convert("RGBA")
    bottom = caption(canvas, text, faces)
    framed = Image.open(frame(raw, work)).convert("RGBA")
    top = bottom + 70
    scale = min(1110 / framed.width, (CANVAS[1] - top - 40) / framed.height)
    framed = framed.resize((round(framed.width * scale), round(framed.height * scale)), Image.LANCZOS)
    x = (CANVAS[0] - framed.width) // 2
    canvas = drop_shadow(canvas, framed, (x, top))
    canvas.alpha_composite(framed, (x, top))
    canvas.convert("RGB").save(out, optimize=True)


def rounded_card(path: Path, width: int, angle: float) -> Image.Image:
    card = Image.open(path).convert("RGBA")
    card = card.resize((width, round(card.height * width / card.width)), Image.LANCZOS)
    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *card.size), radius=round(width * 0.04), fill=255)
    card.putalpha(mask)
    return card.rotate(angle, resample=Image.BICUBIC, expand=True)


def compose_cards(raw_dir: Path, spec: tuple, text: dict, faces: dict, out: Path) -> None:
    """Three trading cards fanned like a hand, the legendary one in front."""
    _, realm, tint = spec
    canvas = backdrop(realm, tint).convert("RGBA")
    bottom = caption(canvas, text, faces)
    centre = CANVAS[0] // 2
    stack = [("fly-agaric", -9.0, 700, (centre - 185, bottom + 560)),
             ("european-robin", 8.0, 700, (centre + 185, bottom + 540)),
             ("golden-eagle", -2.0, 960, (centre, CANVAS[1] - 760))]
    for name, angle, width, (cx, cy) in stack:
        card = rounded_card(raw_dir / "cards" / f"{name}.png", width, angle)
        position = (cx - card.width // 2, cy - card.height // 2)
        canvas = drop_shadow(canvas, card, position, blur=40, alpha=170)
        canvas.alpha_composite(card, position)
    canvas.convert("RGB").save(out, optimize=True)


def main() -> None:
    raw_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    locale = sys.argv[3] if len(sys.argv) > 3 else "en-US"
    text = captions(locale)
    faces = FACES.get(locale, FACES["default"])
    out_dir.mkdir(parents=True, exist_ok=True)
    specs = {s[0]: s for s in PHONE_SHOTS + [PROFILE_SHOT]}
    with tempfile.TemporaryDirectory() as work:
        for index, name in enumerate(ORDER, start=1):
            out = out_dir / f"{index:02d}-{name}.png"
            if name == "cards":
                compose_cards(raw_dir, CARD_SHOT, text[name], faces, out)
            else:
                compose_phone(raw_dir / f"{name}.png", specs[name], text[name], faces, out, Path(work))
            print(f"composed {out.name}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Composes the App Store screenshots: raw simulator captures -> `frames` bezel ->
brand gradient, headline and shadow. Usage: compose_screenshots.py RAW_DIR OUT_DIR

RAW_DIR holds field/reveal/caught/nearby/card/profile .png captured at 1320x2868
(scripts/capture-demo-screens.sh). The bezel always comes from the `frames` CLI;
this script only adds background, caption and shadow around the framed result.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CANVAS = (1320, 2868)
FONT = ("/System/Library/Fonts/Avenir Next.ttc", 8)
SHOTS = [
    ("field", ["Point at", "anything alive"]),
    ("reveal", ["Every catch", "is a card"]),
    ("caught", ["Build your", "Dex"]),
    ("nearby", ["Find what lives", "near you"]),
    ("card", ["Learn what", "you found"]),
    ("profile", ["Level up", "outdoors"]),
]
TOP, BOTTOM = (22, 196, 138), (9, 70, 66)


def frame(raw: Path, out_dir: Path) -> Path:
    result = subprocess.run(
        ["frames", "-c", "Silver", "-o", str(out_dir), "--json", str(raw)],
        check=True, capture_output=True, text=True)
    return Path(json.loads(result.stdout)["output"])


def gradient() -> Image.Image:
    base = Image.new("RGB", CANVAS)
    pixels = base.load()
    width, height = CANVAS
    for y in range(height):
        t = y / (height - 1)
        row = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(width):
            pixels[x, y] = row
    glow = Image.new("RGB", CANVAS, (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-300, -500, 1620, 700), fill=(40, 120, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    return Image.blend(base, Image.composite(glow, base, glow.convert("L")), 0.35)


def compose(raw: Path, lines: list[str], out: Path, work: Path) -> None:
    canvas = gradient()
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT[0], 128, index=FONT[1])
    y = 150
    for line in lines:
        width = draw.textlength(line, font=font)
        draw.text(((CANVAS[0] - width) / 2, y), line, font=font, fill=(255, 255, 255))
        y += 150

    framed = Image.open(frame(raw, work)).convert("RGBA")
    scale = 1110 / framed.width
    framed = framed.resize((round(framed.width * scale), round(framed.height * scale)), Image.LANCZOS)
    x, top = (CANVAS[0] - framed.width) // 2, 560

    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    silhouette = Image.new("RGBA", framed.size, (0, 0, 0, 150))
    shadow.paste(silhouette, (x, top + 36), framed.getchannel("A"))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(46)))
    canvas.alpha_composite(framed, (x, top))
    canvas.convert("RGB").save(out, optimize=True)


def main() -> None:
    raw_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        for index, (name, lines) in enumerate(SHOTS, start=1):
            compose(raw_dir / f"{name}.png", lines, out_dir / f"{index}-{name}.png", Path(work))
            print(f"composed {index}-{name}.png")


if __name__ == "__main__":
    main()

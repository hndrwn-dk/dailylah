"""Static share images (Open Graph, 1200x630 PNG) for the "Living in <town>" pages.

A dev script, run by hand when a town is added or the design changes; the PNGs are committed.
It is not run in CI or on Vercel, and the data push job never touches the images.

    python3 -m venv /tmp/og && /tmp/og/bin/pip install pillow==11.3.0
    # Fonts (SIL Open Font License, copies in web/fonts/*-OFL.txt), from github.com/google/fonts:
    #   ofl/barlowcondensed/BarlowCondensed-Bold.ttf
    #   ofl/plusjakartasans/PlusJakartaSans[wght].ttf
    /tmp/og/bin/python scripts/build_og_images.py --fonts <folder with both .ttf files>

Each image shows the town name, "Commute & HDB prices" and the DailyLah wordmark on the LED
board of the site, and no numbers, so it only changes when a town or the design does.
Writes web/og/where-to-live/<town id>.png (only when the bytes changed) and deletes images of
towns that are no longer in web/data/where-to-live.json. The fonts are not committed.
"""

import argparse
import io
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "web" / "data" / "where-to-live.json"
WORDMARK = ROOT / "web" / "brand" / "wordmark.png"
OUT = ROOT / "web" / "og" / "where-to-live"
TOWN_ID = re.compile(r"[a-z0-9-]+")  # as backend/app/where_to_live_pages.py and web/vercel.json

W, H = 1200, 630
# Brand colours from web/where-to-live/app.css (light theme).
PAPER, INK, MIST = "#E8F3F6", "#0F1618", "#50646A"
BOARD, LED, LED_DIM = "#101719", "#FFB627", "#B9C7CB"
BOARD_BOX = (64, 232, 1136, 566)  # left, top, right, bottom
SHADOW = 12  # the offset ink shadow of the site's cards
PAD = 56  # inside the board


def fonts(folder: Path) -> dict[str, Path]:
    found = {
        "display": folder / "BarlowCondensed-Bold.ttf",
        "body": folder / "PlusJakartaSans[wght].ttf",
    }
    missing = [str(p) for p in found.values() if not p.is_file()]
    if missing:
        sys.exit("Missing font file(s): " + ", ".join(missing))
    return found


def body_font(path: Path, size: int, weight: str) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(path), size)
    font.set_variation_by_name(weight)
    return font


def fit(path: Path, text: str, width: int, start: int, smallest: int) -> ImageFont.FreeTypeFont:
    """The largest size from start down to smallest at which text fits in width."""
    size = start
    while size > smallest:
        font = ImageFont.truetype(str(path), size)
        if font.getlength(text) <= width:
            return font
        size -= 4
    return ImageFont.truetype(str(path), smallest)


def image(name: str, faces: dict[str, Path], wordmark: Image.Image) -> bytes:
    im = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(im)

    mark = wordmark.resize((216, round(216 * wordmark.height / wordmark.width)), Image.LANCZOS)
    im.paste(mark, (64, 40), mark)
    site = body_font(faces["body"], 30, b"SemiBold")
    draw.text((1136, 120), "dailylah.sg/where-to-live", font=site, fill=MIST, anchor="rm")

    left, top, right, bottom = BOARD_BOX
    draw.rounded_rectangle(
        (left + SHADOW, top + SHADOW, right + SHADOW, bottom + SHADOW), 28, fill=INK
    )
    draw.rounded_rectangle(BOARD_BOX, 28, fill=BOARD, outline=INK, width=4)

    label = body_font(faces["body"], 30, b"Bold")
    draw.text((left + PAD, top + 52), "LIVING IN", font=label, fill=LED_DIM, anchor="ls")
    town = fit(faces["display"], name, right - left - 2 * PAD, 150, 72)
    draw.text((left + PAD, top + 200), name, font=town, fill=LED, anchor="ls")
    sub = body_font(faces["body"], 42, b"SemiBold")
    draw.text(
        (left + PAD, bottom - 52), "Commute & HDB prices", font=sub, fill=LED_DIM, anchor="ls"
    )

    buf = io.BytesIO()
    im.quantize(colors=64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(
        buf, "PNG", optimize=True
    )
    return buf.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--fonts", type=Path, required=True, help="folder with both .ttf files")
    args = parser.parse_args()
    faces = fonts(args.fonts)
    towns = json.loads(DATA.read_text())["towns"]
    wordmark = Image.open(WORDMARK).convert("RGBA")
    OUT.mkdir(parents=True, exist_ok=True)
    counts = {"written": 0, "unchanged": 0, "removed": 0}
    keep = set()
    for town in towns:
        tid = town["id"]
        if not (isinstance(tid, str) and TOWN_ID.fullmatch(tid)):
            sys.exit(f"bad town id: {tid!r}")
        path = OUT / f"{tid}.png"
        keep.add(path)
        png = image(str(town["name"]), faces, wordmark)
        if path.is_file() and path.read_bytes() == png:
            counts["unchanged"] += 1
            continue
        path.write_bytes(png)
        counts["written"] += 1
    for old in OUT.glob("*.png"):
        if old not in keep:
            old.unlink()
            counts["removed"] += 1
    print(f"og images: {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

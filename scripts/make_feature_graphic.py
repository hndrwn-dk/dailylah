"""Play Store assets.

Usage: python3 scripts/make_feature_graphic.py
Writes app/assets/store/play-icon-512.png (512x512, full square; Play rounds it) and
docs/feature_design/feature-graphic-1024x500.png.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import make_icon  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JAKARTA = os.path.join(ROOT, "app/assets/fonts/PlusJakartaSans-Variable.ttf")
BARLOW = os.path.join(ROOT, "app/assets/fonts/BarlowCondensed-Bold.ttf")
make_icon.FONT = JAKARTA

INK = (15, 22, 24)
PAPER = (232, 243, 246)
CARD = (244, 251, 254)
TEAL = (14, 148, 136)
AMBER = (237, 173, 43)
BOARD = (16, 23, 25)
LED = (255, 182, 39)
LED_DIM = (185, 199, 203)
LINES = {"TE": (157, 91, 37), "DT": (0, 94, 196), "EW": (0, 150, 69), "NS": (212, 46, 18), "CC": (250, 158, 13)}

S = 2  # supersample


def jak(size, weight=800):
    f = ImageFont.truetype(JAKARTA, size * S)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def bar(size):
    return ImageFont.truetype(BARLOW, size * S)


def sticker(d, box, fill, radius=18, shadow=7, stroke=4):
    x0, y0, x1, y1 = [v * S for v in box]
    d.rounded_rectangle([x0 + shadow * S, y0 + shadow * S, x1 + shadow * S, y1 + shadow * S], radius * S, fill=INK)
    d.rounded_rectangle([x0, y0, x1, y1], radius * S, fill=fill, outline=INK, width=stroke * S)


def text(d, xy, s, font, fill):
    d.text((xy[0] * S, xy[1] * S), s, font=font, fill=fill)


def feature():
    W, H = 1024, 500
    im = Image.new("RGB", (W * S, H * S), PAPER)
    d = ImageDraw.Draw(im)

    # Left: mark and promise.
    mark = make_icon.sticker(330, with_bg=False)
    mark = mark.crop(mark.getbbox())
    mark = mark.resize((int(mark.width * 0.9 * S), int(mark.height * 0.9 * S)), Image.LANCZOS)
    im.paste(mark, (64 * S, 70 * S), mark)
    text(d, (66, 268), "Know before", jak(44), INK)
    text(d, (66, 320), "you go lah.", jak(44), INK)
    text(d, (68, 400), "Buses, MRT, rain, haze and your HDB block.", jak(19, 500), (80, 100, 106))
    text(d, (68, 428), "Free. No account. Stays on your phone.", jak(19, 500), (80, 100, 106))

    # Right: three stickers with the app's signatures.
    # 1. Bus stop LED board.
    sticker(d, (560, 60, 960, 210), BOARD, radius=16)
    rows = [("36", "Arr", "then 7 min"), ("16", "4 min", "then 12 min")]
    for i, (svc, eta, nxt) in enumerate(rows):
        y = 78 + i * 64
        text(d, (586, y), svc, bar(46), LED)
        text(d, (680, y), eta, bar(46), LED)
        text(d, (796, y + 18), nxt, bar(24), LED_DIM)  # one column for every row

    # 2. MRT station chips.
    sticker(d, (560, 240, 790, 330), CARD, radius=16)
    x = 584
    for code in ("TE26", "DT17"):
        f = bar(30)
        w = d.textlength(code, font=f) / S + 26
        col = LINES[code[:2]]
        d.rounded_rectangle([x * S, 262 * S, (x + w) * S, 306 * S], 22 * S, fill=col, outline=INK, width=3 * S)
        text(d, (x + 13, 264), code, f, (255, 255, 255))
        x += w + 12

    # 3. Painted block number.
    # A made-up block number, not anyone's real home.
    sticker(d, (820, 240, 960, 440), CARD, radius=16)
    text(d, (842, 252), "BLK", bar(24), INK)
    text(d, (838, 270), "123", bar(96), INK)
    d.rectangle([842 * S, 404 * S, 940 * S, 414 * S], fill=TEAL)

    # 4. Rain pill.
    sticker(d, (560, 360, 790, 440), AMBER, radius=16)
    text(d, (584, 382), "Bring an umbrella", jak(20), INK)

    return im.resize((W, H), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "app/assets/store"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "docs/feature_design"), exist_ok=True)
    icon = make_icon.sticker(512).convert("RGB")  # full square, no transparency
    icon.save(os.path.join(ROOT, "app/assets/store/play-icon-512.png"))
    feature().save(os.path.join(ROOT, "docs/feature_design/feature-graphic-1024x500.png"))
    print("ok")

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


MINT = (207, 237, 234)
GREY = (80, 100, 106)


def chip(d, x, y, label):
    f = jak(15, 700)
    w = d.textlength(label, font=f) / S + 24
    d.rounded_rectangle([x * S, y * S, (x + w) * S, (y + 30) * S], 15 * S, fill=CARD, outline=INK, width=2 * S)
    text(d, (x + 12, y + 5), label, f, INK)
    return x + w + 8


def bell(d, x, y, s=22):
    X = lambda v: v * S  # noqa: E731
    d.pieslice([X(x), X(y), X(x + s), X(y + s * 1.3)], 180, 360, fill=INK)
    d.rectangle([X(x), X(y + s * 0.62), X(x + s), X(y + s * 0.9)], fill=INK)
    d.rectangle([X(x - 3), X(y + s * 0.86), X(x + s + 3), X(y + s * 0.98)], fill=INK)
    d.ellipse([X(x + s / 2 - 4), X(y + s * 0.98), X(x + s / 2 + 4), X(y + s * 1.16)], fill=INK)


def feature():
    """Feature graphic (Oct 2026): live buses, Wake me, History spend and park facilities."""
    W, H = 1024, 500
    im = Image.new("RGB", (W * S, H * S), PAPER)
    d = ImageDraw.Draw(im)

    # Left: mark and promise.
    mark = make_icon.sticker(330, with_bg=False)
    mark = mark.crop(mark.getbbox())
    mark = mark.resize((int(mark.width * 0.9 * S), int(mark.height * 0.9 * S)), Image.LANCZOS)
    im.paste(mark, (64 * S, 46 * S), mark)
    text(d, (66, 236), "Know before", jak(44), INK)
    text(d, (66, 288), "you go lah.", jak(44), INK)
    for i, line in enumerate(
        [
            "Bus coming? Wake me at my stop.",
            "Park got toilet? Hawker closed ah?",
            "Spent how much on MRT? Alamak...",
        ]
    ):
        text(d, (68, 366 + i * 28), line, jak(19, 500), GREY)

    # Right: the app's stickers.
    # 1. Bus stop LED board.
    sticker(d, (540, 44, 976, 176), BOARD, radius=16)
    for i, (svc, eta, nxt) in enumerate([("43", "1 min", "then 16 min"), ("135", "3 min", "then 17 min")]):
        y = 58 + i * 58
        text(d, (564, y), svc, bar(44), LED)
        text(d, (668, y), eta, bar(44), LED)
        text(d, (800, y + 16), nxt, bar(24), LED_DIM)

    # 2. Wake me at my stop.
    sticker(d, (540, 198, 976, 256), MINT, radius=16, shadow=6)
    bell(d, 562, 212)
    text(d, (600, 211), "Next stop: Marine Pde.", jak(19), INK)
    text(d, (600, 233), "Get ready to alight.", jak(14, 600), GREY)

    # 3. History: spend this week (made-up numbers).
    sticker(d, (540, 280, 744, 444), CARD, radius=16)
    text(d, (560, 294), "THIS WEEK", bar(22), GREY)
    text(d, (558, 314), "$18.40", bar(70), INK)
    text(d, (560, 394), "9 trips · 2 parkings", jak(14, 600), GREY)
    d.rectangle([560 * S, 420 * S, 724 * S, 428 * S], fill=TEAL)

    # 4. Parks: good time to go, with facility chips.
    sticker(d, (768, 280, 976, 444), AMBER, radius=16)
    text(d, (788, 294), "Good time", jak(22), INK)
    text(d, (788, 322), "for the park", jak(22), INK)
    chip(d, 788, 362, "Playground")
    x = chip(d, 788, 400, "Toilet")
    chip(d, x, 400, "BBQ")

    return im.resize((W, H), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "app/assets/store"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "docs/feature_design"), exist_ok=True)
    icon = make_icon.sticker(512).convert("RGB")  # full square, no transparency
    icon.save(os.path.join(ROOT, "app/assets/store/play-icon-512.png"))
    feature().save(os.path.join(ROOT, "docs/feature_design/feature-graphic-1024x500.png"))
    print("ok")

"""Google Play phone screenshots: caption band + the rendered screen, 1080 x 1920 (9:16).

Usage: python3 scripts/frame_screenshots.py app/test_store/goldens docs/store/screenshots
The screens come from app/test_store (flutter test test_store --update-goldens).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JAKARTA = os.path.join(ROOT, "app/assets/fonts/PlusJakartaSans-Variable.ttf")

INK = (15, 22, 24)
TEAL = (14, 148, 136)
DEEP = (8, 60, 55)
W, H, BAND = 1080, 1920, 295

CAPTIONS = {
    "01-today": ("Your morning, in one card", "Weather, buses and MRT for the trip to work"),
    "02-wake": ("Live buses. Wake me at my stop.", "Buzzes before your stop, even with the screen off"),
    "03-planb": ("MRT down? Plan B ready.", "Buses first when your line is disrupted"),
    "04-parks": ("Parks near you", "Toilets, playgrounds and a good time to go"),
    "05-home": ("All about your HDB block", "Upgrading works, schools, clinics and prices"),
    "06-history": ("Where your transport money goes", "MRT, bus and HDB parking costs, estimated for you"),
    "07-weekend": ("Weekend sorted", "Parks, museums and events near home"),
    "08-eat": ("Hawker closed ah?", "Cleaning days and the nearest one that is open"),
}


def font(size, weight):
    f = ImageFont.truetype(JAKARTA, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def fit(d, text, size, weight, width):
    while size > 20:
        f = font(size, weight)
        if d.textlength(text, font=f) <= width:
            return f
        size -= 2
    return font(size, weight)


def frame(src, title, sub):
    shot = Image.open(src).convert("RGB")
    shot = shot.resize((W, int(shot.height * W / shot.width)), Image.LANCZOS)
    im = Image.new("RGB", (W, H), TEAL)
    d = ImageDraw.Draw(im)
    tf = fit(d, title, 66, 800, W - 120)
    sf = fit(d, sub, 34, 600, W - 120)
    d.text((60, 78), title, font=tf, fill=INK)
    d.text((60, 178), sub, font=sf, fill=DEEP)
    im.paste(shot.crop((0, 0, W, H - BAND)), (0, BAND))
    d.rectangle([0, BAND - 6, W, BAND], fill=INK)  # sticker edge
    return im


if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for name, (title, sub) in CAPTIONS.items():
        path = os.path.join(src, f"{name}.png")
        if not os.path.exists(path):
            print("missing", path)
            continue
        frame(path, title, sub).save(os.path.join(out, f"{name}.png"))
        print("ok", name)

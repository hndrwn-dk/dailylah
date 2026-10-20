import sys
# Usage: python3 scripts/make_icon.py app/assets/fonts/PlusJakartaSans-Variable.ttf <out_dir>
# Writes mipmap-*/ic_launcher*.png, a 512 px Play Store icon and a preview.
from PIL import Image, ImageDraw, ImageFont

FONT = sys.argv[1]
INK = (15, 22, 24, 255)
TEAL = (14, 148, 136, 255)
CARD = (244, 251, 254, 255)
AMBER = (237, 173, 43, 255)

def font(size, weight=800):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception as e:
        print("variation failed", e)
    return f

def sticker(size, with_bg=True, mono=False):
    """Draw the mark on a size x size canvas. Mark spans the central ~62%."""
    S = 4  # supersample
    W = size * S
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if with_bg:
        d.rectangle([0, 0, W, W], fill=TEAL)
    u = W / 108.0  # adaptive icon units
    stroke = round(3.2 * u)
    shadow = round(3.6 * u)
    ink = (255, 255, 255, 255) if mono else INK
    # sun behind the sticker, top right
    cx, cy, r = 74 * u, 33 * u, 13 * u
    if not mono:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER, outline=ink, width=stroke)
    # sticker plate
    x0, y0, x1, y1 = 21 * u, 39 * u, 85 * u, 75 * u
    rad = 9 * u
    if not mono:
        d.rounded_rectangle([x0 + shadow, y0 + shadow, x1 + shadow, y1 + shadow], rad, fill=INK)
        d.rounded_rectangle([x0, y0, x1, y1], rad, fill=CARD, outline=ink, width=stroke)
    else:
        d.rounded_rectangle([x0, y0, x1, y1], rad, outline=ink, width=stroke)
    # word
    f = font(round(29 * u))
    text = "lah"
    bbox = d.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (x0 + x1) / 2 - tw / 2 - bbox[0]
    ty = (y0 + y1) / 2 - th / 2 - bbox[1] - 0.5 * u
    d.text((tx, ty), text, font=f, fill=ink, stroke_width=round(0.7 * u), stroke_fill=ink)
    return im.resize((size, size), Image.LANCZOS)

def rounded(im, radius_frac=0.22):
    size = im.size[0]
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * radius_frac), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out

if __name__ == "__main__":
    out = sys.argv[2]
    import os
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, k in dens.items():
        dirp = os.path.join(out, f"mipmap-{name}")
        os.makedirs(dirp, exist_ok=True)
        legacy = rounded(sticker(int(48 * k) * 4).resize((int(48 * k),) * 2, Image.LANCZOS))
        legacy.save(os.path.join(dirp, "ic_launcher.png"))
        fg = sticker(int(108 * k), with_bg=False)
        fg.save(os.path.join(dirp, "ic_launcher_foreground.png"))
        mono = sticker(int(108 * k), with_bg=False, mono=True)
        mono.save(os.path.join(dirp, "ic_launcher_monochrome.png"))
    rounded(sticker(512)).save(os.path.join(out, "play_store_512.png"))
    sticker(1024).save(os.path.join(out, "icon_1024.png"))
    # preview: adaptive circle mask + rounded square
    prev = Image.new("RGBA", (760, 300), (232, 243, 246, 255))
    sq = rounded(sticker(240))
    prev.paste(sq, (30, 30), sq)
    circ = sticker(240)
    m = Image.new("L", (240, 240), 0); ImageDraw.Draw(m).ellipse([0, 0, 239, 239], fill=255)
    prev.paste(circ, (290, 30), m)
    small = rounded(sticker(96))
    prev.paste(small, (570, 30), small)
    small2 = rounded(sticker(48))
    prev.paste(small2, (690, 30), small2)
    prev.save(os.path.join(out, "preview.png"))

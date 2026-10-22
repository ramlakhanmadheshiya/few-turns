"""Few Turns store art: the Play Store phone screenshots and the website's images,
composed from the raw screens tests/capture.gd renders.

Each screenshot is a calm cream page (the Path chapter's colours) with a short
headline (one *accent* word, in the icon's coral), a quiet line under it, and the
real game screen on a floating card. Run from the game folder:

  godot --path . res://tests/capture.tscn -- build/store/raw --store
  .venv/bin/python -I tools/store_art.py

Writes store/screenshots/0N_*.png (1080 x 1920) and web/images/*.jpg (the game page
on the studio site shows those).
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "build", "store", "raw")
OUT = os.path.join(ROOT, "store", "screenshots")
WEB = os.path.join(ROOT, "web", "images")
FONT = os.path.join(ROOT, "assets", "fonts", "Outfit-Variable.ttf")
W, H = 1080, 1920
TOP, BOTTOM = (255, 244, 232), (255, 211, 194)
INK = (45, 42, 74)
MUTED = (45, 42, 74, 150)
ACCENT = (232, 96, 63)

SHOTS = [
    {"name": "01_lay", "raw": "raw_laid", "caption": "Lay a few *turns*.", "sub": "Tap a cell for an arrow, swipe to point it"},
    {"name": "02_roll", "raw": "raw_rolling", "caption": "Press Go. Roll *home*.", "sub": "Take every red dot on the way"},
    {"name": "03_fewest", "raw": "raw_room", "caption": "Not one turn *spare*.", "sub": "Each room gives the fewest arrows that work"},
    {"name": "04_ideas", "grid": ["raw_ch3", "raw_ch5", "raw_ch6", "raw_ch9"], "labels": ["Bank", "Spin", "Shift", "Pair"],
     "caption": "One new *idea* a chapter.", "sub": "Bends, spinners, portals, two orbs and more"},
    {"name": "05_hint", "raw": "raw_hint", "caption": "Stuck? See the *way*.", "sub": "A hint outlines every arrow"},
    {"name": "06_chapters", "raw": "raw_chapters", "caption": "*360* calm rooms.", "sub": "Nine chapters, forty rooms each"},
    {"name": "07_result", "raw": "raw_result", "caption": "First try, *three* stars.", "sub": "Share the run you found"},
    {"name": "08_home", "raw": "raw_home", "caption": "Think at your own *pace*.", "sub": "No timers  ·  plays offline  ·  daily hints"},
]

# The website's images (shown on the game's studio page).
WEB_IMAGES = {"home": "raw_home", "path": "raw_laid", "rolling": "raw_rolling", "bank": "raw_ch3",
              "pair": "raw_ch9", "result": "raw_result", "chapters": "raw_chapters"}


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def caption(img, text, sub, y=120):
    """The headline: words in ink, the *starred* one in coral, centred."""
    d = ImageDraw.Draw(img, "RGBA")
    f = font(84, 600)
    parts = []
    for i, chunk in enumerate(text.split("*")):
        if chunk:
            parts.append((chunk, ACCENT if i % 2 == 1 else INK))
    total = sum(d.textlength(p, font=f) for p, _ in parts)
    x = (img.width - total) / 2
    for p, col in parts:
        d.text((x, y), p, font=f, fill=col)
        x += d.textlength(p, font=f)
    fs = font(40, 400)
    tw = d.textlength(sub, font=fs)
    d.text(((img.width - tw) / 2, y + 112), sub, font=fs, fill=MUTED)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def card(page, screen, box, radius=48):
    """Pastes a screen into box (x, y, w, h) on a soft shadow."""
    x, y, w, h = box
    shot = screen.resize((w, h), Image.LANCZOS)
    shadow = Image.new("RGBA", page.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 24, x + w, y + h + 24], radius, fill=(45, 42, 74, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    page.paste(shadow, (0, 0), shadow)
    r = rounded(shot, radius)
    page.paste(r, (x, y), r)


def load(name):
    return Image.open(os.path.join(RAW, name + ".png")).convert("RGB")


def screen_only(im):
    """The game without the test ad strip at the bottom."""
    # The banner slot is the bottom ~10% on these captures; keep the app above it.
    return im.crop((0, 0, im.width, int(im.height * 0.887)))


def compose(spec):
    page = gradient(W, H).convert("RGBA")
    caption(page, spec["caption"], spec["sub"])
    if "grid" in spec:
        cw, ch = 440, 690
        gap = 40
        x0 = (W - 2 * cw - gap) // 2
        y0 = 340
        d = ImageDraw.Draw(page, "RGBA")
        fl = font(38, 600)
        for i, name in enumerate(spec["grid"]):
            x = x0 + (i % 2) * (cw + gap)
            y = y0 + (i // 2) * (ch + 100)
            card(page, screen_only(load(name)).crop((0, 0, 1080, 1440)), (x, y, cw, int(cw * 1440 / 1080)), 36)
            label = spec["labels"][i]
            tw = d.textlength(label, font=fl)
            d.text((x + (cw - tw) / 2, y + int(cw * 1440 / 1080) + 22), label, font=fl, fill=INK)
    else:
        sc = screen_only(load(spec["raw"]))
        h = 1500
        w = int(h * sc.width / sc.height)
        card(page, sc, ((W - w) // 2, 360, w, h))
    return page.convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(WEB, exist_ok=True)
    for spec in SHOTS:
        compose(spec).save(os.path.join(OUT, spec["name"] + ".png"), optimize=True)
        print("store", spec["name"])
    for name, raw_name in WEB_IMAGES.items():
        im = screen_only(load(raw_name)).resize((562, int(562 * 1703 / 1080)), Image.LANCZOS)
        im = im.crop((0, 0, 562, 1000)) if im.height > 1000 else im
        im.save(os.path.join(WEB, name + ".jpg"), quality=86, optimize=True)
        print("web", name)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""OneMuastFall's own art for the Aurora dashboard on the Xbox 360, drawn
from scratch (no game art): an angular fighting robot in silhouette over an
arena floor grid, a spark of impact, and the name. Writes assets/aurora/ at
Aurora's asset sizes:

  icon.png        64 x 64     the title's icon
  banner.png     420 x 96     the banner in the game list
  boxart.png     900 x 600    the cover (back, spine, front)
  background.png 1280 x 720   the background behind the game's details

  python3 tools/make_aurora_art.py [--font PATH]

The lettering uses a heavy sans font (default: Inter Black Italic, SIL Open
Font License); only the rendered pictures are kept, not the font.
"""
import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parent.parent / "assets" / "aurora"
SS = 4  # drawn at 4x, then scaled down for smooth edges

TOP = (8, 6, 18)
BOTTOM = (34, 16, 46)
GRID = (40, 90, 190)
STEEL = (150, 160, 178)
STEEL_DARK = (58, 62, 78)
RIM = (120, 200, 255)
HOT = (255, 120, 30)
HOT_CORE = (255, 236, 160)


def backdrop(w, h, horizon=0.62):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    # arena floor: a perspective grid below the horizon
    hy = int(h * horizon)
    d.rectangle([0, hy, w, h], fill=(10, 14, 40))
    vx = w / 2
    for k in range(-24, 25):
        x0 = vx + k * w / 16
        d.line([(vx + k * w / 160, hy), (x0, h)], fill=GRID, width=max(1, w // 400))
    y = hy
    step = (h - hy) / 40
    while y < h:
        d.line([(0, int(y)), (w, int(y))], fill=GRID, width=max(1, w // 500))
        step *= 1.18
        y += step
    # glow at the horizon
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w * 0.1, hy - h * 0.08, w * 0.9, hy + h * 0.08], fill=(70, 40, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.05))
    return Image.blend(img, Image.composite(glow, img, glow.convert("L")), 0.6)


def robot(d, cx, base, s, fill=STEEL, dark=STEEL_DARK, rim=RIM):
    """An angular robot in a fighting stance, feet at (cx, base), `s` tall."""
    u = s / 100.0

    def P(pts):
        return [(cx + x * u, base - y * u) for x, y in pts]

    # back leg, back arm (darker)
    d.polygon(P([(-6, 46), (-22, 24), (-30, 0), (-20, 0), (-12, 22), (2, 42)]), fill=dark)
    d.polygon(P([(-10, 84), (-30, 74), (-40, 62), (-34, 58), (-24, 66), (-8, 74)]), fill=dark)
    # torso and hips
    d.polygon(P([(-14, 92), (16, 94), (20, 70), (12, 48), (-8, 46), (-18, 66)]), fill=fill)
    d.polygon(P([(-10, 50), (12, 50), (10, 40), (-8, 40)]), fill=dark)
    # head: a wedge with a visor
    d.polygon(P([(-4, 94), (12, 96), (16, 106), (2, 110), (-6, 102)]), fill=fill)
    d.polygon(P([(4, 101), (15, 103), (14, 106), (4, 104)]), fill=HOT)
    # front leg, bent forward
    d.polygon(P([(4, 42), (22, 22), (34, 0), (46, 0), (30, 26), (14, 46)]), fill=fill)
    # front arm, punching
    d.polygon(P([(12, 88), (34, 82), (56, 84), (58, 76), (34, 72), (10, 76)]), fill=fill)
    d.polygon(P([(56, 88), (66, 86), (68, 74), (56, 72)]), fill=fill)
    # rim light along the top edges
    w = max(1, int(s / 60))
    d.line(P([(-14, 92), (16, 94)]), fill=rim, width=w)
    d.line(P([(12, 88), (34, 82), (56, 84), (66, 86)]), fill=rim, width=w)
    d.line(P([(-4, 94), (12, 96), (16, 106)]), fill=rim, width=w)
    return cx + 66 * u, base - 80 * u   # the fist


def spark(img, x, y, r, seed=3):
    rnd = random.Random(seed)
    layer = Image.new("RGB", img.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(14):
        a = i / 14 * 2 * math.pi + rnd.uniform(-0.15, 0.15)
        ln = r * rnd.uniform(0.6, 1.4)
        w = r * 0.12
        pts = [(x + math.cos(a) * ln, y + math.sin(a) * ln),
               (x + math.cos(a + 1.57) * w, y + math.sin(a + 1.57) * w),
               (x - math.cos(a + 1.57) * w, y - math.sin(a + 1.57) * w)]
        d.polygon(pts, fill=HOT)
    d.ellipse([x - r * 0.35, y - r * 0.35, x + r * 0.35, y + r * 0.35], fill=HOT_CORE)
    soft = layer.filter(ImageFilter.GaussianBlur(r * 0.15))
    mask = Image.eval(layer.convert("L"), lambda v: min(255, v * 2))
    out = Image.composite(layer, img, mask)
    return Image.blend(out, Image.composite(soft, out, soft.convert("L")), 0.5)


def font(path, size):
    return ImageFont.truetype(str(path), size)


def lettering(img, text, x, y, size, fontpath, color=(240, 240, 250), anchor="la", shadow=True):
    d = ImageDraw.Draw(img)
    f = font(fontpath, size)
    if shadow:
        for dx, dy in ((size // 18, size // 18), (size // 12, size // 12)):
            d.text((x + dx, y + dy), text, font=f, fill=(0, 0, 0), anchor=anchor)
    # a steel gradient: draw the text as a mask and fill it
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text((x, y), text, font=f, fill=255, anchor=anchor)
    bbox = mask.getbbox()
    if not bbox:
        return
    grad = Image.new("RGB", img.size, color)
    gd = ImageDraw.Draw(grad)
    for yy in range(bbox[1], bbox[3] + 1):
        t = (yy - bbox[1]) / max(1, bbox[3] - bbox[1])
        c = (int(255 - 90 * t), int(250 - 120 * t), int(255 - 60 * t)) if t < 0.55 else \
            (int(200 + 55 * (t - 0.55)), int(120 - 60 * (t - 0.55)), int(60))
        gd.line([(bbox[0], yy), (bbox[2], yy)], fill=c)
    img.paste(grad, (0, 0), mask)


def scene(w, h, fontpath, title=True, robot_scale=0.62, robot_x=0.3, text_x=None):
    W, H = w * SS, h * SS
    img = backdrop(W, H)
    d = ImageDraw.Draw(img)
    base = H * 0.9
    fx, fy = robot(d, W * robot_x, base, H * robot_scale)
    img = spark(img, fx + H * 0.03, fy, H * robot_scale * 0.22)
    if title:
        tx = W * (text_x if text_x is not None else 0.52)
        lettering(img, "ONE MUST FALL", tx, H * 0.2, int(H * 0.095), fontpath)
        lettering(img, "2097", tx + H * 0.01, H * 0.32, int(H * 0.15), fontpath)
        lettering(img, "OneMuastFall  -  a Lua recompilation", tx + H * 0.01, H * 0.53, int(H * 0.045), fontpath,
                  color=(170, 200, 255), shadow=False)
    return img.resize((w, h), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", default="/usr/share/fonts/opentype/inter/Inter-BlackItalic.otf")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    scene(1280, 720, a.font, robot_scale=0.6, robot_x=0.2, text_x=0.5).save(OUT / "background.png")

    # banner: the name across, a small robot at the left
    W, H = 420 * SS, 96 * SS
    b = backdrop(W, H, horizon=0.7)
    fx, fy = robot(ImageDraw.Draw(b), W * 0.09, H * 0.98, H * 0.9)
    b = spark(b, fx + H * 0.04, fy, H * 0.2)
    lettering(b, "ONE MUST FALL 2097", W * 0.25, H * 0.16, int(H * 0.3), a.font)
    lettering(b, "OneMuastFall", W * 0.255, H * 0.6, int(H * 0.2), a.font, color=(170, 200, 255), shadow=False)
    b.resize((420, 96), Image.LANCZOS).save(OUT / "banner.png")

    # icon: the robot and the spark, no text
    S = 64 * SS
    i = backdrop(S, S, horizon=0.72)
    fx, fy = robot(ImageDraw.Draw(i), S * 0.28, S * 0.97, S * 0.82)
    i = spark(i, fx + S * 0.02, fy, S * 0.16)
    i.resize((64, 64), Image.LANCZOS).save(OUT / "icon.png")

    # box art: back | spine | front
    box = Image.new("RGB", (900, 600))
    front = scene(420, 600, a.font, title=False, robot_scale=0.5, robot_x=0.28)
    fl = front.resize((420 * SS, 600 * SS))
    lettering(fl, "ONE MUST", 420 * SS * 0.5, 600 * SS * 0.06, int(600 * SS * 0.085), a.font, anchor="ma")
    lettering(fl, "FALL 2097", 420 * SS * 0.5, 600 * SS * 0.15, int(600 * SS * 0.085), a.font, anchor="ma")
    lettering(fl, "OneMuastFall", 420 * SS * 0.5, 600 * SS * 0.26, int(600 * SS * 0.04), a.font, anchor="ma",
              color=(170, 200, 255), shadow=False)
    box.paste(fl.resize((420, 600), Image.LANCZOS), (480, 0))
    spine = backdrop(60, 600, horizon=1.0)
    sp = Image.new("RGB", (600 * SS, 60 * SS))
    sp.paste(backdrop(600 * SS, 60 * SS, horizon=1.0))
    lettering(sp, "ONE MUST FALL 2097  -  OneMuastFall", 300 * SS, 30 * SS, int(60 * SS * 0.42), a.font, anchor="mm")
    spine = sp.resize((600, 60), Image.LANCZOS).rotate(-90, expand=True)
    box.paste(spine, (420, 0))
    back = backdrop(420, 600, horizon=0.75)
    bd = ImageDraw.Draw(back)
    small = font(a.font, 22)
    lines = ["Eleven robots.", "Five arenas.", "One must fall.", "",
             "Plays from your own copy", "of the 1994 original", "(freeware)."]
    for k, line in enumerate(lines):
        bd.text((40, 80 + k * 34), line, font=small, fill=(220, 225, 240))
    box.paste(back, (0, 0))
    box.save(OUT / "boxart.png")
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))


if __name__ == "__main__":
    main()

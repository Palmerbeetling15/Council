#!/usr/bin/env python3
"""
Council app icon generator (theme-parameterized).

Concept: a council of minds — three advisor orbs in an equilateral triad around a faint
round-table ring, on a premium squircle. Matches the in-app AdvisorOrbs motif.

Usage:
  python3 scripts/make_icon.py <theme> [--preview]
    <theme>     dark | light | lightblue | ink   (default: dark)
    --preview   write a single 512px preview to scripts/preview_<theme>.png
                (default, no flag: write the full .appiconset + docs/icon.png)
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

# ---------------- themes ----------------
THEMES = {
    # dark: deep navy squircle, glowing light orbs (the original)
    "dark": {
        "bg": [(0x16, 0x1d, 0x33), (0x05, 0x07, 0x0e)],
        "orb": {"hi": (240, 246, 255), "mid": (164, 190, 234), "edge": (72, 96, 158)},
        "spec": False,
        "accent": "glow", "accent_color": (132, 166, 236), "accent_alpha": 95,
        "ring": (196, 214, 248, 64),
        "haze": (70, 104, 180), "haze_alpha": 0.7,
        "dropshadow": (0, 0, 0, 110),
    },
    # light: soft off-white → cool-gray squircle, deep indigo glossy orbs
    "light": {
        "bg": [(0xFF, 0xFF, 0xFF), (0xE6, 0xEB, 0xF5)],
        "orb": {"hi": (150, 170, 220), "mid": (52, 70, 140), "edge": (22, 30, 60)},
        "spec": True,
        "accent": "shadow", "accent_color": (30, 40, 80), "accent_alpha": 78,
        "ring": (44, 60, 110, 42),
        "haze": None,
        "dropshadow": (40, 52, 84, 80),
    },
    # lightblue: white → pale blue squircle, vivid brand-blue orbs
    "lightblue": {
        "bg": [(0xFF, 0xFF, 0xFF), (0xE7, 0xEF, 0xFB)],
        "orb": {"hi": (200, 222, 255), "mid": (56, 108, 224), "edge": (26, 52, 128)},
        "spec": True,
        "accent": "shadow", "accent_color": (40, 78, 168), "accent_alpha": 66,
        "ring": (70, 112, 212, 48),
        "haze": None,
        "dropshadow": (40, 60, 110, 78),
    },
    # ink: near-white squircle, near-black monochrome orbs (minimal)
    "ink": {
        "bg": [(0xFF, 0xFF, 0xFF), (0xEC, 0xEE, 0xF1)],
        "orb": {"hi": (150, 154, 162), "mid": (40, 43, 50), "edge": (12, 13, 16)},
        "spec": True,
        "accent": "shadow", "accent_color": (20, 22, 28), "accent_alpha": 74,
        "ring": (30, 33, 40, 40),
        "haze": None,
        "dropshadow": (30, 33, 40, 82),
    },
}

theme_name = next((a for a in sys.argv[1:] if not a.startswith("-")), "dark")
PREVIEW = "--preview" in sys.argv
T = THEMES[theme_name]

SS = 3
BASE = 1024
S = BASE * SS
OUT = os.path.join(os.path.dirname(__file__), "..", "Council",
                   "Assets.xcassets", "AppIcon.appiconset")

def lerp(a, b, t): return a + (b - a) * t
def lerp_col(c1, c2, t): return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))
def smoothstep(a, b, x):
    if x <= a: return 0.0
    if x >= b: return 1.0
    t = (x - a) / (b - a)
    return t * t * (3 - 2 * t)

# ---------- squircle body ----------
body = int(0.812 * BASE) * SS
radius = int(0.2237 * (body / SS)) * SS
margin_x = (S - body) // 2
margin_top = int(0.085 * BASE) * SS

bg = Image.new("RGBA", (body, body), (0, 0, 0, 0))
bd = ImageDraw.Draw(bg)
TOP, BOT = T["bg"]
for y in range(body):
    t = y / (body - 1)
    bd.line([(0, y), (body, y)], fill=lerp_col(TOP, BOT, t * t * (3 - 2 * t)) + (255,))

# optional cool top haze (dark theme depth)
if T["haze"]:
    glow = Image.new("L", (body, body), 0)
    gd = ImageDraw.Draw(glow)
    gcx, gcy, gr = body // 2, int(body * 0.28), int(body * 0.62)
    for i in range(gr, 0, -2):
        gd.ellipse([gcx - i, gcy - i, gcx + i, gcy + i], fill=int(80 * (1 - i / gr)))
    glow = glow.filter(ImageFilter.GaussianBlur(body * 0.05)).point(lambda a: int(a * T["haze_alpha"]))
    hz = Image.new("RGBA", (body, body), T["haze"] + (0,)); hz.putalpha(glow)
    bg = Image.alpha_composite(bg, hz)

# round-table ring
ring = Image.new("RGBA", (body, body), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
ccx, ccy, R = body // 2, int(body * 0.515), int(body * 0.305)
rd.ellipse([ccx - R, ccy - R, ccx + R, ccy + R], outline=T["ring"], width=max(1, int(body * 0.0058)))
ring = ring.filter(ImageFilter.GaussianBlur(body * 0.0015))
bg = Image.alpha_composite(bg, ring)

# ---------- advisor orb sprite ----------
HI, MID, EDGE = T["orb"]["hi"], T["orb"]["mid"], T["orb"]["edge"]
def make_orb(diam):
    img = Image.new("RGBA", (diam, diam), (0, 0, 0, 0))
    px = img.load()
    r = diam / 2.0
    hlx, hly = r - 0.34 * r, r - 0.34 * r
    for y in range(diam):
        for x in range(diam):
            dx, dy = x - r, y - r
            d = math.sqrt(dx * dx + dy * dy)
            if d > r:
                continue
            t = d / r
            hd = math.sqrt((x - hlx) ** 2 + (y - hly) ** 2) / (1.55 * r)
            col = lerp_col(HI, MID, min(hd, 1.0))
            col = lerp_col(col, EDGE, smoothstep(0.80, 1.0, t))
            if T["spec"] and hd < 0.20:                       # glossy specular hotspot
                col = lerp_col(col, (255, 255, 255), (0.20 - hd) / 0.20 * 0.55)
            a = 255 if t < 0.985 else int(255 * (1 - (t - 0.985) / 0.015))
            px[x, y] = col + (max(0, min(255, a)),)
    return img

orb_d = int(body * 0.224)
orb = make_orb(orb_d)

# accent sprite: a soft glow (dark theme) or a drop shadow (light themes)
acc = Image.new("RGBA", (orb_d, orb_d), (0, 0, 0, 0))
ImageDraw.Draw(acc).ellipse([orb_d * 0.16, orb_d * 0.16, orb_d * 0.84, orb_d * 0.84],
                            fill=T["accent_color"] + (T["accent_alpha"],))
scale = 1.5 if T["accent"] == "glow" else 1.35
acc = acc.resize((int(orb_d * scale), int(orb_d * scale))).filter(ImageFilter.GaussianBlur(orb_d * 0.13))
acc_dy = 0 if T["accent"] == "glow" else int(orb_d * 0.10)     # shadows sit just below the orb

cx, cy, tr = body / 2.0, body * 0.505, body * 0.158
centers = [(cx + tr * math.cos(math.radians(a)), cy - tr * math.sin(math.radians(a)))
           for a in (90, 210, 330)]
for (ox, oy) in centers:
    bg.alpha_composite(acc, (int(ox - acc.width / 2), int(oy - acc.height / 2 + acc_dy)))
for (ox, oy) in centers:
    bg.alpha_composite(orb, (int(ox - orb_d / 2), int(oy - orb_d / 2)))

# clip to squircle
mask = Image.new("L", (body, body), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, body - 1, body - 1], radius=radius, fill=255)
bg.putalpha(mask)

# compose onto full canvas with drop shadow
canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    [margin_x, margin_top + int(0.018 * BASE) * SS, margin_x + body, margin_top + body + int(0.018 * BASE) * SS],
    radius=radius, fill=T["dropshadow"])
shadow = shadow.filter(ImageFilter.GaussianBlur(0.030 * BASE * SS))
canvas = Image.alpha_composite(canvas, shadow)
canvas.alpha_composite(bg, (margin_x, margin_top))
master = canvas.resize((BASE, BASE), Image.LANCZOS)

# ---------- output ----------
if PREVIEW:
    p = os.path.join(os.path.dirname(__file__), f"preview_{theme_name}.png")
    master.resize((512, 512), Image.LANCZOS).save(p)
    print("preview →", os.path.normpath(p))
else:
    DOCS = os.path.join(os.path.dirname(__file__), "..", "docs")
    os.makedirs(DOCS, exist_ok=True)
    master.save(os.path.join(DOCS, "icon.png"))
    specs = [(16, "1x"), (16, "2x"), (32, "1x"), (32, "2x"), (128, "1x"), (128, "2x"),
             (256, "1x"), (256, "2x"), (512, "1x"), (512, "2x")]
    images = []
    for pt, sc in specs:
        px = pt * (2 if sc == "2x" else 1)
        fn = f"icon_{pt}{'@2x' if sc == '2x' else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, fn))
        images.append('    {\n      "filename" : "%s",\n      "idiom" : "mac",\n      "scale" : "%s",\n      "size" : "%dx%d"\n    }' % (fn, sc, pt, pt))
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n' + ',\n'.join(images) +
                '\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    print(f"wrote '{theme_name}' icon → appiconset + docs/icon.png")

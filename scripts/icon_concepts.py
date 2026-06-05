#!/usr/bin/env python3
"""
Council icon — "Gems" concept: three glossy orbs linked into a triangle/network on a
deep gradient squircle. Palette-parameterized so we can audition orb colors.

  python3 scripts/icon_concepts.py                 # contact sheet of all palettes → scripts/palettes.png
  python3 scripts/icon_concepts.py one <palette>   # single 512 preview → scripts/concept_<palette>.png
  python3 scripts/icon_concepts.py finalize <pal>  # write full .appiconset + docs/icon.png
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

SS = 3
BASE = 1024
S = BASE * SS
HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "Council", "Assets.xcassets", "AppIcon.appiconset")

body = int(0.812 * BASE) * SS
radius = int(0.2237 * (body / SS)) * SS
mx = (S - body) // 2
mt = int(0.085 * BASE) * SS

# orb color palettes (each = three "mid" base colors; hi/edge are derived)
PALETTES = {
    "cool":   [(50, 120, 252), (158, 86, 248), (34, 205, 226)],   # blue / violet / cyan (current)
    "warm":   [(255, 112, 92), (255, 176, 64), (240, 92, 168)],   # coral / amber / pink
    "jewel":  [(38, 200, 140), (64, 118, 250), (170, 92, 240)],   # emerald / sapphire / amethyst
    "sunset": [(255, 96, 150), (255, 140, 62), (255, 202, 74)],   # pink / orange / gold
    "models": [(232, 122, 92), (36, 190, 150), (74, 120, 240)],   # Claude-coral / GPT-green / Gemini-blue
    "violet": [(120, 92, 242), (170, 86, 240), (210, 92, 224)],   # indigo / violet / magenta
    # --- summer ---
    "summer":   [(255, 111, 97), (38, 205, 196), (255, 198, 64)],   # coral / turquoise / sun-yellow (beach)
    "tropical": [(255, 92, 150), (40, 208, 214), (154, 214, 74)],   # pink / aqua / lime
    "citrus":   [(255, 138, 56), (255, 100, 116), (255, 206, 74)],  # orange / watermelon / yellow
    "lagoon":   [(36, 200, 196), (255, 122, 100), (86, 168, 255)],  # turquoise / coral / sky
    # --- more directions (good as glowing orbs on black) ---
    "ice":      [(120, 180, 255), (110, 230, 235), (170, 160, 255)],  # icy blue / cyan / periwinkle (cool, premium)
    "neon":     [(0, 200, 255), (255, 44, 180), (124, 255, 92)],      # electric cyan / magenta / acid green (cyber)
    "ember":    [(255, 72, 60), (255, 150, 40), (255, 212, 72)],      # red / orange / gold (fire)
    "ocean":    [(40, 120, 255), (28, 200, 212), (96, 156, 250)],     # blue / teal / azure (cool, unified)
    "candy":    [(255, 105, 180), (150, 110, 255), (90, 200, 255)],   # pink / purple / sky (playful)
}

# background squircle presets (top, bottom, connecting-line rgba, metallic sheen?)
BGS = {
    "indigo":   dict(top=(54, 42, 142), bot=(10, 9, 30),    line=(208, 216, 250, 200), sheen=False, glow=115),
    "lead":     dict(top=(178, 184, 196), bot=(104, 110, 124), line=(58, 64, 80, 210), sheen=True, glow=100),   # gunmetal
    "graphite": dict(top=(104, 108, 118), bot=(44, 47, 55),  line=(166, 172, 186, 195), sheen=True, glow=110),  # darker gray
    "white":    dict(top=(255, 255, 255), bot=(235, 238, 244), line=(70, 76, 92, 205), sheen=False, glow=85),   # clean white
    "black":    dict(top=(18, 18, 24), bot=(2, 2, 5), line=None, sheen=False, glow=160),                        # black, glowing orbs, no lines
}

def lerp(a, b, t): return a + (b - a) * t
def lcol(c1, c2, t): return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))
def smoothstep(a, b, x):
    if x <= a: return 0.0
    if x >= b: return 1.0
    t = (x - a) / (b - a); return t * t * (3 - 2 * t)
def shades(base):
    return lcol(base, (255, 255, 255), 0.60), base, tuple(int(c * 0.30) for c in base)

def squircle_mask(size, rad):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=rad, fill=255)
    return m

def diag_grad(size, top, bot):
    big = int(size * 1.5)
    g = Image.new("RGB", (big, big)); d = ImageDraw.Draw(g)
    for y in range(big):
        d.line([(0, y), (big, y)], fill=lcol(top, bot, (y / (big - 1)) ** 0.9))
    g = g.rotate(-35, resample=Image.BICUBIC, expand=False)
    off = (big - size) // 2
    return g.crop((off, off, off + size, off + size))

def orb(diam, hi, mid, edge):
    img = Image.new("RGBA", (diam, diam), (0, 0, 0, 0)); px = img.load(); r = diam / 2
    hlx, hly = r - 0.36 * r, r - 0.36 * r
    for y in range(diam):
        for x in range(diam):
            dx, dy = x - r, y - r; d = math.hypot(dx, dy)
            if d > r: continue
            t = d / r
            hd = math.hypot(x - hlx, y - hly) / (1.5 * r)
            c = lcol(hi, mid, min(hd, 1.0)); c = lcol(c, edge, smoothstep(0.78, 1.0, t))
            if hd < 0.22: c = lcol(c, (255, 255, 255), (0.22 - hd) / 0.22 * 0.72)
            a = 255 if t < 0.987 else int(255 * (1 - (t - 0.987) / 0.013))
            px[x, y] = c + (max(0, min(255, a)),)
    return img

def gems_body(palette, bgname="lead", tr_f=0.212, od_f=0.198, lw_f=0.0135):
    B = BGS[bgname]
    bg = diag_grad(body, B["top"], B["bot"]).convert("RGBA")
    if B["sheen"]:
        s = Image.new("L", (body, body), 0)
        ImageDraw.Draw(s).ellipse([-body * 0.30, -body * 0.55, body * 0.95, body * 0.42], fill=90)
        sh = Image.new("RGBA", (body, body), (255, 255, 255, 0))
        sh.putalpha(s.filter(ImageFilter.GaussianBlur(body * 0.12)))
        bg = Image.alpha_composite(bg, sh)
    bg.putalpha(squircle_mask(body, radius))
    if B["line"] is None:           # no connectors → cluster the orbs tighter, like the in-app hero
        tr_f, od_f = 0.156, 0.238
    od = int(body * od_f); tr = body * tr_f
    cx, cy = body / 2, body * 0.505
    cen = [(cx + tr * math.cos(math.radians(a)), cy - tr * math.sin(math.radians(a))) for a in (90, 210, 330)]
    cols = [shades(b) for b in palette]
    for (ox, oy), (hi, mid, edge) in zip(cen, cols):
        g = Image.new("RGBA", (body, body), (0, 0, 0, 0))
        gr = od * (0.66 if B["line"] is None else 0.62)
        ImageDraw.Draw(g).ellipse([ox - gr, oy - gr, ox + gr, oy + gr], fill=mid + (B["glow"],))
        bg.alpha_composite(g.filter(ImageFilter.GaussianBlur(od * 0.18)))
    if B["line"] is not None:
        lines = Image.new("RGBA", (body, body), (0, 0, 0, 0)); ld = ImageDraw.Draw(lines)
        for i in range(3):
            ld.line([cen[i], cen[(i + 1) % 3]], fill=B["line"], width=max(1, int(body * lw_f)))
        bg.alpha_composite(lines.filter(ImageFilter.GaussianBlur(body * 0.013)))
        bg.alpha_composite(lines)
    for (ox, oy), (hi, mid, edge) in zip(cen, cols):
        sh = Image.new("RGBA", (body, body), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([ox - od * 0.48, oy - od * 0.30, ox + od * 0.48, oy + od * 0.62], fill=(0, 0, 0, 120))
        bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(od * 0.09)))
        bg.alpha_composite(orb(od, hi, mid, edge), (int(ox - od / 2), int(oy - od / 2)))
    return bg

def compose(body_img):
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0)); o = int(0.018 * BASE) * SS
    ImageDraw.Draw(sh).rounded_rectangle([mx, mt + o, mx + body, mt + body + o], radius=radius, fill=(0, 0, 0, 125))
    sh = sh.filter(ImageFilter.GaussianBlur(0.03 * BASE * SS))
    canvas = Image.alpha_composite(canvas, sh)
    canvas.alpha_composite(body_img, (mx, mt))
    return canvas.resize((BASE, BASE), Image.LANCZOS)

def emit_iconset(master):
    DOCS = os.path.join(HERE, "..", "docs"); os.makedirs(DOCS, exist_ok=True)
    master.save(os.path.join(DOCS, "icon.png"))
    specs = [(16, "1x"), (16, "2x"), (32, "1x"), (32, "2x"), (128, "1x"), (128, "2x"),
             (256, "1x"), (256, "2x"), (512, "1x"), (512, "2x")]
    imgs = []
    for pt, sc in specs:
        px = pt * (2 if sc == "2x" else 1)
        fn = f"icon_{pt}{'@2x' if sc == '2x' else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, fn))
        imgs.append('    {\n      "filename" : "%s",\n      "idiom" : "mac",\n      "scale" : "%s",\n      "size" : "%dx%d"\n    }' % (fn, sc, pt, pt))
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n' + ',\n'.join(imgs) + '\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')

cmd = sys.argv[1] if len(sys.argv) > 1 else "sheet"
if cmd == "finalize":
    name = sys.argv[2] if len(sys.argv) > 2 else "cool"
    bgn = sys.argv[3] if len(sys.argv) > 3 else "lead"
    emit_iconset(compose(gems_body(PALETTES[name], bgn)))
    print(f"wrote 'gems/{name}' on '{bgn}' → appiconset + docs/icon.png")
elif cmd == "one":
    name = sys.argv[2]; bgn = sys.argv[3] if len(sys.argv) > 3 else "lead"
    compose(gems_body(PALETTES[name], bgn)).resize((512, 512), Image.LANCZOS).save(os.path.join(HERE, f"concept_{name}.png"))
    print(f"preview → scripts/concept_{name}.png")
else:
    names = sys.argv[2:] if len(sys.argv) > 2 else ["cool", "jewel", "models", "ice", "neon", "ember", "ocean", "sunset"]
    tile = 300; cols = 2 if len(names) <= 4 else (3 if len(names) <= 6 else 4); pad = 24
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile + (cols + 1) * pad, rows * tile + (rows + 1) * pad), (236, 237, 242))
    for i, name in enumerate(names):
        ic = compose(gems_body(PALETTES[name], "black")).resize((tile, tile), Image.LANCZOS)
        r, c = divmod(i, cols)
        sheet.paste(ic, (pad + c * (tile + pad), pad + r * (tile + pad)), ic)
    sheet.save(os.path.join(HERE, "palettes.png"))
    print("contact sheet → scripts/palettes.png  (order:", ", ".join(names) + ")")

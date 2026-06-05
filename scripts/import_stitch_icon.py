#!/usr/bin/env python3
"""
Turn a Stitch-exported icon PNG (squircle on a white canvas) into a clean macOS
.appiconset: flood-fill the white surround to transparent (follows the squircle's
own edge, keeps the orbs), then re-frame with native margins + a soft drop shadow.

  python3 scripts/import_stitch_icon.py /path/to/screen.png
"""
import sys, os
from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Desktop/stitch-icon/screen.png")
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "Council", "Assets.xcassets", "AppIcon.appiconset")
DOCS = os.path.join(ROOT, "docs")

src = Image.open(SRC).convert("RGB")
W, H = src.size

# 1) flood-fill the white background from the four corners → transparent
ff = src.copy()
for seed in [(1, 1), (W - 2, 1), (1, H - 2), (W - 2, H - 2)]:
    ImageDraw.floodfill(ff, seed, (255, 0, 255), thresh=72)
fp = ff.load()
alpha = Image.new("L", (W, H), 255)
ap = alpha.load()
for y in range(H):
    for x in range(W):
        if fp[x, y] == (255, 0, 255):
            ap[x, y] = 0
alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))      # soft anti-aliased edge
cut = src.convert("RGBA")
cut.putalpha(alpha)

# 2) crop to the squircle (bbox from the alpha, so the white RGB doesn't fool it), square it
bbox = alpha.getbbox()
sq = cut.crop(bbox)
w, h = sq.size
s = max(w, h)
sqsq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
sqsq.paste(sq, ((s - w) // 2, (s - h) // 2), sq)

# 3) re-frame onto 1024 with native margin + soft drop shadow
BASE = 1024
body = int(0.84 * BASE)
sqr = sqsq.resize((body, body), Image.LANCZOS)
mg = (BASE - body) // 2
canvas = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
sh = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
off = int(0.016 * BASE)
ImageDraw.Draw(sh).rounded_rectangle(
    [mg, mg + off, mg + body, mg + body + off], radius=int(0.225 * body), fill=(0, 0, 0, 120))
sh = sh.filter(ImageFilter.GaussianBlur(0.028 * BASE))
canvas = Image.alpha_composite(canvas, sh)
canvas.alpha_composite(sqr, (mg, mg))
master = canvas

# preview over light gray (so I can eyeball it) + the real transparent master
prev = Image.new("RGB", (BASE, BASE), (228, 230, 235))
prev.paste(master, (0, 0), master)
prev.save(os.path.join(os.path.dirname(__file__), "stitch_preview.png"))

# 4) emit iconset + docs/icon.png
os.makedirs(DOCS, exist_ok=True)
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
print("imported Stitch icon → appiconset + docs/icon.png  (preview: scripts/stitch_preview.png)")

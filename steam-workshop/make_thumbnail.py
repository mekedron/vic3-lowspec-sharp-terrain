#!/usr/bin/env python3
"""Build thumbnail.png.

Without arguments: a title card. With two screenshots of the same view, vanilla Low
first and the mod second (same resolution, e.g. 5120x1440):

    steam-workshop/make_thumbnail.py before.png after.png [x y w h]

the same window is cropped out of both and stacked as BEFORE / AFTER under the title.
The crop defaults to the middle of the screen at 2:1 and must avoid the HUD.
"""
import pathlib, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
S, BAND = 1024, 190
GOLD, CREAM, DARK = (222, 190, 120), (248, 242, 230), (14, 12, 10)


def title(d):
    for text, size, y, col in (("SHARP TERRAIN", 92, 22, CREAM), ("VICTORIA 3 · LOW SHADER QUALITY", 40, 128, GOLD)):
        f = ImageFont.truetype(FB, size)
        d.text(((S - d.textlength(text, font=f)) / 2, y), text, font=f, fill=col)


def label(d, y, text):
    f = ImageFont.truetype(FB, 64)
    w = d.textlength(text, font=f)
    d.rectangle([26, y, 26 + w + 44, y + 90], fill=DARK)
    d.text((48, y + 10), text, font=f, fill=CREAM)


def main():
    out = Image.new("RGB", (S, S), DARK)
    d = ImageDraw.Draw(out)
    if len(sys.argv) >= 3:
        a, b = (Image.open(p).convert("RGB") for p in sys.argv[1:3])
        if len(sys.argv) == 7:
            x, y, w, h = map(int, sys.argv[3:7])
        else:
            h = a.height // 2
            w = h * 2 * (S) // (S - BAND)
            x, y = (a.width - w) // 2, (a.height - h) // 2
        half = (S - BAND) // 2
        for i, im in enumerate((a, b)):
            out.paste(im.crop((x, y, x + w, y + h)).resize((S, half), Image.LANCZOS), (0, BAND + i * half))
        d.line([0, BAND + half, S, BAND + half], fill=GOLD, width=4)
        label(d, BAND + half - 120, "BEFORE")
        label(d, S - 120, "AFTER")
    else:
        f = ImageFont.truetype(FB, 46)
        for i, line in enumerate(("ground textures per pixel", "relief shading", "no Medium/High cost")):
            d.text(((S - d.textlength(line, font=f)) / 2, 420 + i * 90), line, font=f, fill=CREAM)
    d.line([0, BAND - 6, S, BAND - 6], fill=GOLD, width=4)
    title(d)
    out = out.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    out.save(ROOT / "thumbnail.png", optimize=True)


if __name__ == "__main__":
    main()

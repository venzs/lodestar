#!/usr/bin/env python3
"""Render the Lodestar navigation arrow (Lodestar_Guide/Textures/Arrow.tga).

A kite-shaped arrow pointing up, light body with a soft top-to-bottom shade and a dark outline so it
reads on any background; the addon tints it with SetVertexColor. 256x256, 32-bit uncompressed TGA
(power-of-two, alpha), rendered at 4x and downsampled for clean edges.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 256
SS = 4
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Lodestar_Guide", "Textures", "Arrow.tga")


def kite(s, inset=0.0):
    """Arrow outline in a box of side s, shrunk by `inset` pixels toward the centroid."""
    tip = (s * 0.5, s * 0.06)
    right = (s * 0.86, s * 0.86)
    notch = (s * 0.5, s * 0.66)
    left = (s * 0.14, s * 0.86)
    pts = [tip, right, notch, left]
    if inset:
        cx = s * 0.5
        cy = s * 0.60
        out = []
        for x, y in pts:
            dx, dy = x - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5 or 1
            out.append((x - dx / d * inset, y - dy / d * inset))
        pts = out
    return pts


def render():
    s = SIZE * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # soft shadow
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + 3 * SS, y + 4 * SS) for x, y in kite(s)], fill=(0, 0, 0, 140))
    shadow = shadow.filter(ImageFilter.GaussianBlur(3 * SS))
    img.alpha_composite(shadow)
    # outline (dark), then body (vertical gradient), then a highlight ridge down the middle
    draw.polygon(kite(s), fill=(18, 22, 28, 255))
    body = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(body)
    for y in range(s):
        t = y / s
        c = int(250 - 70 * t)
        bdraw.line([(0, y), (s, y)], fill=(c, c, c, 255))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).polygon(kite(s, inset=7 * SS), fill=255)
    img.paste(body, (0, 0), mask)
    # left half slightly darker to suggest a fold
    fold = Image.new("L", (s, s), 0)
    ImageDraw.Draw(fold).polygon([kite(s, inset=7 * SS)[0], kite(s, inset=7 * SS)[2], kite(s, inset=7 * SS)[3]], fill=255)
    dark = Image.new("RGBA", (s, s), (0, 0, 0, 55))
    img.paste(Image.alpha_composite(img, dark), (0, 0), fold)
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    return out


def main():
    img = render()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, format="TGA")
    # also a PNG preview next to the script for eyeballing
    img.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "arrow_preview.png"))
    print("wrote", os.path.normpath(OUT), img.size)


if __name__ == "__main__":
    sys.exit(main())

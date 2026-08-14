"""Generate the Mise app icon: a minimal "M" monogram on an indigo badge.

Produces:
  assets/icon/app_icon.png           1024x1024 full-bleed gradient master
  assets/icon/app_icon_foreground.png 1024x1024 transparent "M" (Android adaptive)

Requires Pillow. Run from the project root:  python scripts/generate_icon.py
"""

import os
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
FONT_PATH = r"C:\Windows\Fonts\segoeuib.ttf"
TOP = (99, 102, 241)      # #6366F1
BOTTOM = (67, 56, 202)    # #4338CA
WHITE = (255, 255, 255, 255)


def vertical_gradient(w: int, h: int) -> Image.Image:
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        r = round(TOP[0] + (BOTTOM[0] - TOP[0]) * t)
        g = round(TOP[1] + (BOTTOM[1] - TOP[1]) * t)
        b = round(TOP[2] + (BOTTOM[2] - TOP[2]) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))
    return img


def draw_letter(img: Image.Image, size: int) -> None:
    font = ImageFont.truetype(FONT_PATH, size)
    bbox = font.getbbox("M")
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    x = (SIZE - w) // 2 - bbox[0]
    y = (SIZE - h) // 2 - bbox[1]
    ImageDraw.Draw(img).text((x, y), "M", font=font, fill=WHITE)


def main() -> None:
    out = os.path.join("assets", "icon")
    os.makedirs(out, exist_ok=True)

    master = vertical_gradient(SIZE, SIZE)
    draw_letter(master, 640)
    master.save(os.path.join(out, "app_icon.png"))

    # Android adaptive foreground: transparent with "M" in the safe zone.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_letter(fg, 500)
    fg.save(os.path.join(out, "app_icon_foreground.png"))

    print(f"Wrote app_icon.png and app_icon_foreground.png to {out}")


if __name__ == "__main__":
    main()
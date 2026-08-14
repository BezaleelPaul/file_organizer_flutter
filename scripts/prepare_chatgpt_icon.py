"""Prepare the user-supplied ChatGPT icon as the Mise master.

- Trims the black rounded corners, centers the badge on a fresh 1024 canvas
- Writes assets/icon/app_icon.png            (full-bleed master, RGB)
- Writes assets/icon/app_icon_foreground.png (transparent, badge in adaptive safe zone)

Requires Pillow. Run from project root:  python scripts/prepare_chatgpt_icon.py
"""

import os
from PIL import Image

SRC = r"ChatGPT Image Aug 15, 2026, 12_05_26 AM.png"
SIZE = 1024
BG_THRESHOLD = 60  # pixels darker than this (summed RGB) are the black frame


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    px = im.load()
    w, h = im.size

    # Row representative badge color = average of non-black pixels in that row.
    row_color = []
    for y in range(h):
        rs = gs = bs = n = 0
        for x in range(w):
            r, g, b = px[x, y][:3]
            if r + g + b > BG_THRESHOLD:
                rs += r
                gs += g
                bs += b
                n += 1
        row_color.append((rs // n, gs // n, bs // n) if n else (112, 131, 250))

    # Fill black rounded corners with the row's badge gradient color.
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            if r + g + b <= BG_THRESHOLD:
                px[x, y] = row_color[y]

    top_edge = px[w // 2, 8]
    print("top badge color:", top_edge, "hex: #%02X%02X%02X" % top_edge[:3])

    master = im.resize((SIZE, SIZE), Image.LANCZOS)
    out = os.path.join("assets", "icon")
    os.makedirs(out, exist_ok=True)
    master.save(os.path.join(out, "app_icon.png"))

    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fg_size = int(SIZE * 0.66)
    small = master.resize((fg_size, fg_size), Image.LANCZOS)
    fg.paste(small, ((SIZE - fg_size) // 2, (SIZE - fg_size) // 2))
    fg.save(os.path.join(out, "app_icon_foreground.png"))

    print("wrote assets/icon/app_icon.png and app_icon_foreground.png")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""
Generate macOS app icon for NotchDrop.
Produces a dark rounded-square background with a white tray + downward arrow icon.
"""

import json
import os
from PIL import Image, ImageDraw

OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "NotchDrop", "Assets.xcassets", "AppIcon.appiconset",
)

BG_COLOR = (28, 28, 30)       # #1C1C1E
ICON_COLOR = (255, 255, 255)  # white


def draw_icon(size: int) -> Image.Image:
    """Draw the NotchDrop icon at the given pixel size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- rounded-rectangle background ---
    corner = size * 0.22
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=corner, fill=BG_COLOR)

    # --- tray / inbox icon with downward arrow ---
    # All coordinates are proportional to `size`.
    s = size  # shorthand
    lw = max(2, round(s * 0.045))  # line width

    # The tray is an open-top box sitting in the lower portion of the icon.
    # Tray dimensions (centred horizontally)
    tray_left   = s * 0.22
    tray_right  = s * 0.78
    tray_top    = s * 0.48
    tray_bottom = s * 0.72
    notch_depth = s * 0.07   # small notch/lip on each side of the tray opening

    # Draw the tray outline:
    #   left wall  -> bottom-left corner -> bottom-right corner -> right wall
    #   with small horizontal lips (notches) at the top of each wall
    tray_points = [
        # left lip (horizontal part at top of left wall)
        (tray_left, tray_top),
        (tray_left, tray_top + notch_depth),
        (tray_left + notch_depth, tray_top + notch_depth),
        # down the inner left wall to bottom
        (tray_left + notch_depth, tray_bottom),
        # across the bottom (with slight rounding via rectangle later)
        (tray_right - notch_depth, tray_bottom),
        # up the inner right wall
        (tray_right - notch_depth, tray_top + notch_depth),
        (tray_right, tray_top + notch_depth),
        (tray_right, tray_top),
    ]
    draw.line(tray_points, fill=ICON_COLOR, width=lw, joint="curve")

    # --- downward arrow above the tray ---
    arrow_cx = s * 0.50            # centre x
    arrow_top = s * 0.22           # top of the shaft
    arrow_tip = tray_top - s*0.03  # tip just above tray opening
    head_half = s * 0.10           # half-width of the arrowhead

    # shaft
    draw.line([(arrow_cx, arrow_top), (arrow_cx, arrow_tip)],
              fill=ICON_COLOR, width=lw)

    # arrowhead (two angled lines forming a "V")
    head_top_y = arrow_tip - s * 0.10
    draw.line([(arrow_cx - head_half, head_top_y), (arrow_cx, arrow_tip)],
              fill=ICON_COLOR, width=lw)
    draw.line([(arrow_cx + head_half, head_top_y), (arrow_cx, arrow_tip)],
              fill=ICON_COLOR, width=lw)

    return img


# macOS icon catalogue: (point size, scale) -> pixel size
ICON_SPECS = [
    ("16x16",   "1x",  16),
    ("16x16",   "2x",  32),
    ("32x32",   "1x",  32),
    ("32x32",   "2x",  64),
    ("128x128", "1x",  128),
    ("128x128", "2x",  256),
    ("256x256", "1x",  256),
    ("256x256", "2x",  512),
    ("512x512", "1x",  512),
    ("512x512", "2x",  1024),
]


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # We only need to render each unique pixel size once, then reuse.
    cache: dict[int, Image.Image] = {}
    images_json = []

    for point_size, scale, px in ICON_SPECS:
        if px not in cache:
            cache[px] = draw_icon(px)
            print(f"  rendered {px}x{px}")

        filename = f"icon_{px}x{px}.png"
        cache[px].save(os.path.join(OUTPUT_DIR, filename), "PNG")
        print(f"  saved {filename}  ({point_size} @{scale})")

        images_json.append({
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": point_size,
        })

    # Write Contents.json
    contents = {
        "images": images_json,
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }
    contents_path = os.path.join(OUTPUT_DIR, "Contents.json")
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")
    print(f"\n  wrote {contents_path}")
    print("Done.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate fork-specific app icon with trans flag themed banner.

Takes the AppIcon-Debug icons (which have an orange "DEV" banner) and:
1. Recolors the banner to trans flag gradient (light blue → pink → white → pink → blue)
2. Replaces the "DEV" text with "LAB"

Trans flag colors:
  Light blue: #5BCEFA (91, 206, 250)
  Pink:       #F5A9B8 (245, 169, 184)
  White:      #FFFFFF (255, 255, 255)

This creates a visually distinct build from upstream cmux for lab testing.
"""
import os
import json
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(REPO, "Assets.xcassets", "AppIcon-Debug.appiconset")
DST_DIR = os.path.join(REPO, "Assets.xcassets", "AppIcon-Fork.appiconset")

# Trans flag colors
TRANS_BLUE = (91, 206, 250)
TRANS_PINK = (245, 169, 184)
TRANS_WHITE = (255, 255, 255)

SIZES = [
    ("16.png", 16),
    ("16@2x.png", 32),
    ("32.png", 32),
    ("32@2x.png", 64),
    ("128.png", 128),
    ("128@2x.png", 256),
    ("256.png", 256),
    ("256@2x.png", 512),
    ("512.png", 512),
    ("512@2x.png", 1024),
]


def lerp_color(c1, c2, t):
    """Linearly interpolate between two RGB tuples."""
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def trans_gradient_color(y_frac):
    """Return the trans flag color at a given vertical fraction (0=top, 1=bottom).

    The flag has 5 horizontal stripes:
      0.0 - 0.2: light blue
      0.2 - 0.4: pink
      0.4 - 0.6: white
      0.6 - 0.8: pink
      0.8 - 1.0: light blue
    We use smooth blending between stripes.
    """
    if y_frac <= 0.1:
        return TRANS_BLUE
    elif y_frac <= 0.2:
        return lerp_color(TRANS_BLUE, TRANS_PINK, (y_frac - 0.1) / 0.1)
    elif y_frac <= 0.3:
        return TRANS_PINK
    elif y_frac <= 0.4:
        return lerp_color(TRANS_PINK, TRANS_WHITE, (y_frac - 0.3) / 0.1)
    elif y_frac <= 0.6:
        return TRANS_WHITE
    elif y_frac <= 0.7:
        return lerp_color(TRANS_WHITE, TRANS_PINK, (y_frac - 0.6) / 0.1)
    elif y_frac <= 0.8:
        return TRANS_PINK
    elif y_frac <= 0.9:
        return lerp_color(TRANS_PINK, TRANS_BLUE, (y_frac - 0.8) / 0.1)
    else:
        return TRANS_BLUE


def recolor_banner(img: Image.Image) -> Image.Image:
    """Recolor the orange banner to trans gradient and replace DEV with LAB."""
    img = img.convert("RGBA")
    w, h = img.size
    pixels = img.load()

    # The banner occupies roughly the bottom 18% of the icon.
    banner_y = int(h * 0.82)
    banner_h = h - banner_y

    # Pass 1: Recolor orange pixels to trans gradient.
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            # Detect orange: high R, moderate G, very low B
            if r > 180 and g < 180 and b < 100 and r > g and r - b > 100:
                orange_strength = min(r / 255.0, 1.0)
                # Map y position within banner to trans gradient
                if y >= banner_y:
                    frac = (y - banner_y) / max(banner_h, 1)
                else:
                    frac = 0.0
                tc = trans_gradient_color(frac)
                nr = int(tc[0] * orange_strength)
                ng = int(tc[1] * orange_strength)
                nb = int(tc[2] * orange_strength)
                pixels[x, y] = (nr, ng, nb, a)

    # Pass 2: Replace the "DEV" text with "LAB".
    text_pixels = []
    for y in range(banner_y, h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r > 220 and g > 220 and b > 220 and a > 200:
                text_pixels.append((x, y))

    if text_pixels:
        min_x = min(p[0] for p in text_pixels)
        max_x = max(p[0] for p in text_pixels)
        min_y = min(p[1] for p in text_pixels)
        max_y = max(p[1] for p in text_pixels)

        pad = max(2, int(h * 0.005))
        min_x = max(0, min_x - pad)
        max_x = min(w - 1, max_x + pad)
        min_y = max(banner_y, min_y - pad)
        max_y = min(h - 1, max_y + pad)

        # Fill text area with gradient
        draw = ImageDraw.Draw(img)
        for y in range(min_y, max_y + 1):
            frac = (y - banner_y) / max(banner_h, 1)
            c = trans_gradient_color(frac)
            draw.line([(min_x, y), (max_x, y)], fill=(*c, 255))

        # Draw "LAB" centered in the banner
        text = "LAB"
        text_area_h = max_y - min_y
        font_size = max(int(text_area_h * 0.85), 6)

        font = None
        for font_path in [
            "/System/Library/Fonts/SFCompact-Bold.otf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]:
            if os.path.exists(font_path):
                try:
                    font = ImageFont.truetype(font_path, font_size)
                    break
                except Exception:
                    continue
        if font is None:
            font = ImageFont.load_default()

        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        tx = (w - tw) // 2
        ty = banner_y + (banner_h - th) // 2 - bbox[1]

        # Dark text for readability against the light trans gradient
        draw.text((tx, ty), text, fill=(40, 40, 60, 255), font=font)

    return img


def main():
    os.makedirs(DST_DIR, exist_ok=True)

    for filename, pixel_size in SIZES:
        src_path = os.path.join(SRC_DIR, filename)
        dst_path = os.path.join(DST_DIR, filename)

        if not os.path.exists(src_path):
            print(f"  SKIP {filename} (source not found)")
            continue

        img = Image.open(src_path)
        if img.size != (pixel_size, pixel_size):
            img = img.resize((pixel_size, pixel_size), Image.LANCZOS)

        result = recolor_banner(img)
        result.save(dst_path, "PNG")
        print(f"  {filename} ({pixel_size}x{pixel_size})")

    # Write Contents.json
    contents = {
        "images": [
            {"filename": f, "idiom": "mac", "scale": s, "size": sz}
            for f, s, sz in [
                ("16.png", "1x", "16x16"),
                ("16@2x.png", "2x", "16x16"),
                ("32.png", "1x", "32x32"),
                ("32@2x.png", "2x", "32x32"),
                ("128.png", "1x", "128x128"),
                ("128@2x.png", "2x", "128x128"),
                ("256.png", "1x", "256x256"),
                ("256@2x.png", "2x", "256x256"),
                ("512.png", "1x", "512x512"),
                ("512@2x.png", "2x", "512x512"),
            ]
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(DST_DIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)

    print(f"\nGenerated {len(SIZES)} icons in {DST_DIR}")


if __name__ == "__main__":
    main()

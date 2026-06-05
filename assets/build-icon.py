#!/usr/bin/env python3
"""
Rebuild NudgeAI's AppIcon.icns from assets/NudgeAIIcon.png.

The source PNG is full-bleed (no alpha). macOS app icons need transparent
corners so the OS renders them as proper rounded squircles in the Dock and
Finder. This script:

  1. Resizes the source to 1024x1024.
  2. Applies a "squircle" alpha mask (continuous rounded rectangle with the
     same corner curvature Apple uses for app icons — exponent ~5, radius
     such that the inscribed shape is the macOS app-icon silhouette).
  3. Emits every iconset variant (16, 32, 128, 256, 512 with @2x) into
     assets/AppIcon.iconset/.
  4. Runs `iconutil --convert icns` to produce assets/AppIcon.icns.

Run from anywhere; paths are resolved relative to this file.
"""

import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "NudgeAIIcon.png"
ICONSET = HERE / "AppIcon.iconset"
ICNS = HERE / "AppIcon.icns"

# Apple's app-icon shape is a "squircle" — a superellipse with a continuous-
# curvature corner. Exponent ~5 matches Apple's macOS app icon template
# closely enough that the rendered Dock icon is visually indistinguishable
# from a native-shaped icon. Radius is the full half-width — the squircle
# is inscribed in the 1024x1024 canvas.
SQUIRCLE_EXPONENT = 5.0
CANVAS = 1024

ICON_SIZES = [
    ("16x16",    16),
    ("16x16@2x", 32),
    ("32x32",    32),
    ("32x32@2x", 64),
    ("128x128",  128),
    ("128x128@2x", 256),
    ("256x256",  256),
    ("256x256@2x", 512),
    ("512x512",  512),
    ("512x512@2x", 1024),
]


def build_squircle_mask(size: int, exponent: float) -> Image.Image:
    """Return an L-mode mask of a centered squircle at the given canvas size.

    Pixel is inside the shape when |x/r|^n + |y/r|^n <= 1 (origin at center).
    We supersample by 4x and downsample to get smooth edges.
    """
    ss = 4
    big = size * ss
    mask = Image.new("L", (big, big), 0)
    px = mask.load()
    r = big / 2.0
    for y in range(big):
        ny = (y + 0.5 - r) / r
        ay = abs(ny) ** exponent
        if ay > 1.0:
            continue
        # Solve |x/r|^n <= 1 - ay → |x| <= r * (1 - ay)^(1/n)
        bound = r * (1.0 - ay) ** (1.0 / exponent)
        x_min = int(r - bound)
        x_max = int(r + bound)
        for x in range(max(0, x_min), min(big, x_max + 1)):
            px[x, y] = 255
    return mask.resize((size, size), Image.LANCZOS)


def main() -> int:
    if not SOURCE.exists():
        print(f"Source PNG missing: {SOURCE}", file=sys.stderr)
        return 1

    src = Image.open(SOURCE).convert("RGBA")
    if src.size != (CANVAS, CANVAS):
        src = src.resize((CANVAS, CANVAS), Image.LANCZOS)

    mask = build_squircle_mask(CANVAS, SQUIRCLE_EXPONENT)
    masked = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    masked.paste(src, (0, 0), mask=mask)

    ICONSET.mkdir(exist_ok=True)
    for name, px in ICON_SIZES:
        out = ICONSET / f"icon_{name}.png"
        masked.resize((px, px), Image.LANCZOS).save(out, "PNG", optimize=True)
        print(f"  wrote {out.name} ({px}x{px})")

    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(
        ["iconutil", "--convert", "icns", str(ICONSET), "-o", str(ICNS)],
        check=True,
    )
    print(f"  wrote {ICNS.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

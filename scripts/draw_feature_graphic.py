"""Draws the Play Store feature graphic into store/feature-graphic.png.

    python scripts/draw_feature_graphic.py

Google's spec: exactly 1024x500, PNG or JPEG, no alpha. It is shown
cropped on some surfaces and scaled down small on others, so everything
that has to be read sits inside a centred safe area and nothing but the
background touches the edges.

The mark is the launcher icon's, drawn by draw_icon.py, so the two cannot
drift apart: this script imports it rather than redrawing it.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Run from anywhere: draw_icon.py sits beside this file, not on the path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from draw_icon import BRAND, WHITE, draw_mark  # noqa: E402

W, H = 1024, 500
SCALE = 3  # drawn large and scaled down, so the edges are smooth
OUT = Path(__file__).resolve().parent.parent / "store"

TITLE = "Moneyora"
TAGLINE = "A budget built from how you really spend"
FOOTER = "Offline  ·  No account  ·  No ads"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """Roboto if this machine has it, DejaVu otherwise, and never crash."""
    names = (
        ["Roboto-Bold.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"]
        if bold
        else ["Roboto-Regular.ttf", "arial.ttf", "DejaVuSans.ttf"]
    )
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def main() -> None:
    big = Image.new("RGB", (W * SCALE, H * SCALE), BRAND[:3])
    draw = ImageDraw.Draw(big)

    # A lighter band behind the mark, so the left side has some depth
    # rather than reading as a flat rectangle with text on it.
    draw.ellipse(
        [-90 * SCALE, -170 * SCALE, 430 * SCALE, 560 * SCALE],
        fill=(0x4A, 0x5C, 0xC4),
    )

    # The coin. draw_mark centres on a single coordinate, so it is drawn
    # into its own square layer and that layer is placed.
    coin = Image.new("RGBA", (300 * SCALE, 300 * SCALE), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(coin), 150 * SCALE, 110 * SCALE)
    big.paste(coin, (20 * SCALE, 100 * SCALE), coin)

    left = 360 * SCALE
    draw.text((left, 150 * SCALE), TITLE, font=font(86 * SCALE, True), fill=WHITE[:3])
    draw.text(
        (left, 258 * SCALE),
        TAGLINE,
        font=font(34 * SCALE),
        fill=(0xDC, 0xE1, 0xF7),
    )
    draw.text(
        (left, 330 * SCALE),
        FOOTER,
        font=font(27 * SCALE),
        fill=(0xB6, 0xC1, 0xEE),
    )

    OUT.mkdir(parents=True, exist_ok=True)
    big.resize((W, H), Image.LANCZOS).save(OUT / "feature-graphic.png")
    print(f"wrote {OUT / 'feature-graphic.png'}  {W}x{H}")


if __name__ == "__main__":
    main()

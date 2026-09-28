"""Draws Moneyora's launcher icon masters into assets/icons/.

    python scripts/draw_icon.py
    dart run flutter_launcher_icons

The mark is three rising bars inside a coin: money, and a plan for it.
White on the brand indigo, AppColors.light.brand (E-01). Drawn at four
times the size and scaled down, so the edges are smooth.

- icon.png            1024 px, the full icon (iOS, legacy Android).
- icon_foreground.png 1024 px, transparent, for Android's adaptive icon.
                      flutter_launcher_icons insets it by 16%, which puts
                      the mark at 46% of the canvas: inside the 61% safe
                      circle, so no launcher's mask clips it.
- ic_stat_moneyora.png  Android's notification small icon, written straight
                      into android/app/src/main/res/drawable-*dpi/. Android
                      draws only its alpha channel, so it is the mark alone,
                      white on transparent: the launcher icon there would be
                      a white square.
"""

from pathlib import Path

from PIL import Image, ImageDraw

BRAND = (0x3F, 0x51, 0xB5, 255)
WHITE = (255, 255, 255, 255)
SIZE = 1024
SCALE = 4
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icons"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
# 24 dp at each density.
SMALL_ICON = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}


def draw_mark(draw: ImageDraw.ImageDraw, centre: float, radius: float) -> None:
    """The coin ring and its three bars, centred, [radius] to the ring's edge."""
    ring = radius * 0.13
    draw.ellipse(
        [centre - radius, centre - radius, centre + radius, centre + radius],
        outline=WHITE,
        width=round(ring),
    )
    inner = radius - ring
    bar = inner * 0.30
    gap = inner * 0.12
    base = centre + inner * 0.50
    heights = (inner * 0.50, inner * 0.78, inner * 1.05)
    left = centre - (3 * bar + 2 * gap) / 2
    for i, h in enumerate(heights):
        x = left + i * (bar + gap)
        draw.rounded_rectangle(
            [x, base - h, x + bar, base], radius=bar * 0.3, fill=WHITE
        )


def render(background: bool, mark_radius: float) -> Image.Image:
    big = SIZE * SCALE
    img = Image.new("RGBA", (big, big), BRAND if background else (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(img), big / 2, mark_radius * SCALE)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # iOS rounds the corners itself and refuses an alpha channel.
    render(True, SIZE * 0.34).convert("RGB").save(OUT / "icon.png")
    # The same mark: the adaptive icon's 16% inset is what keeps it safe.
    render(False, SIZE * 0.34).save(OUT / "icon_foreground.png")
    # Material's 24 dp status-bar icon keeps a 2 dp margin: radius 10 of 12.
    small = render(False, SIZE * 0.42)
    for density, px in SMALL_ICON.items():
        folder = RES / f"drawable-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        small.resize((px, px), Image.LANCZOS).save(folder / "ic_stat_moneyora.png")


if __name__ == "__main__":
    main()

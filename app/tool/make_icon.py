"""Draws the app icon: three friends on the app's coral.

Run from app/: uv run --with pillow python tool/make_icon.py
(uv lives with the backend; any Python with Pillow works). Then:
dart run flutter_launcher_icons
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
CORAL = (255, 122, 89, 255)
WHITE = (255, 255, 255, 255)
CREAM = (255, 226, 214, 255)
OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"


def person(draw: ImageDraw.ImageDraw, cx: float, top: float, scale: float, color) -> None:
    """A head and rounded shoulders; ``top`` is the top of the head."""
    head = 150 * scale
    draw.ellipse((cx - head / 2, top, cx + head / 2, top + head), fill=color)
    body_w, body_h = 290 * scale, 230 * scale
    body_top = top + head + 22 * scale
    draw.rounded_rectangle(
        (cx - body_w / 2, body_top, cx + body_w / 2, body_top + body_h),
        radius=body_w / 2 * 0.9,
        fill=color,
    )


def friends(draw: ImageDraw.ImageDraw, scale: float = 1.0) -> None:
    """Three figures, the middle one in front, centred in the canvas."""
    c = SIZE / 2
    # Sides first (behind), then the middle one.
    person(draw, c - 235 * scale, c - 150 * scale, 0.82 * scale, CREAM)
    person(draw, c + 235 * scale, c - 150 * scale, 0.82 * scale, CREAM)
    # A coral outline separates the middle figure from the others.
    person(draw, c, c - 212 * scale, 1.14 * scale, CORAL)
    person(draw, c, c - 200 * scale, 1.0 * scale, WHITE)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # The full icon (iOS, web, legacy Android): coral with rounded corners
    # left to each platform's mask.
    icon = Image.new("RGBA", (SIZE, SIZE), CORAL)
    friends(ImageDraw.Draw(icon))
    icon.save(OUT / "icon.png")
    # Adaptive icon foreground: transparent, the figures inside the central
    # safe zone (66% of the canvas).
    foreground = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    friends(ImageDraw.Draw(foreground), scale=0.72)
    foreground.save(OUT / "foreground.png")
    print("wrote", OUT / "icon.png", OUT / "foreground.png")


if __name__ == "__main__":
    main()

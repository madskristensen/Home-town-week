#!/usr/bin/env python3
"""Render Open Graph cards from the city map SVGs.

Social apps do not use the header SVG. Each city gets a 1200x630 PNG of
that same map and pin, used when a city or issue has no photo. The front
page card is a cream sheet with a handful of those marks.

Run from the repo root:

    python3 script/render-og-images.py
"""

import re
import subprocess
from pathlib import Path

from PIL import Image, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CITIES_YML = ROOT / "_data" / "cities.yml"
MAP_DIR = ROOT / "assets" / "images" / "cities"
OUT_DIR = ROOT / "assets" / "images" / "og"
HOME_OUT = ROOT / "assets" / "images" / "og-image.png"

W, H = 1200, 630
PAPER = "#f4efe6"
FOREST = "#1e4636"
GOLD = "#c6a15a"
GOLD_INK = "#7a5c12"
MUTED = "#4d5c54"

SERIF = "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
SANS_BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

# A few Eastside cities on the front-page card.
HOME_MARKS = [
    ("wa", "bellevue", "Bellevue"),
    ("wa", "kirkland", "Kirkland"),
    ("wa", "redmond", "Redmond"),
    ("wa", "issaquah", "Issaquah"),
]


def xml_escape(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def load_cities():
    cities = []
    current = None
    for line in CITIES_YML.read_text().splitlines():
        if line.startswith("- id: "):
            if current:
                cities.append(current)
            current = {"id": line.split(": ", 1)[1].strip()}
        elif current and line.startswith("  name: "):
            current["name"] = line.split(": ", 1)[1].strip().strip('"')
        elif current and line.startswith("  state: "):
            current["state"] = line.split(": ", 1)[1].strip()
    if current:
        cities.append(current)
    return cities


def map_inner(state, city_id):
    raw = (MAP_DIR / state / f"{city_id}.svg").read_text()
    view = re.search(r'viewBox="([^"]+)"', raw)
    if not view:
        raise SystemExit(f"missing viewBox for {state}/{city_id}")
    inner = re.sub(r"^.*?<svg[^>]*>", "", raw, count=1, flags=re.S)
    inner = re.sub(r"</svg>\s*$", "", inner)
    return view.group(1), inner.strip()


def nested_map(state, city_id, x, y, width, height, stroke=None):
    view, inner = map_inner(state, city_id)
    if stroke:
        inner = inner.replace('stroke-width="2.4"', f'stroke-width="{stroke}"')
    return (
        f'<svg x="{x}" y="{y}" width="{width}" height="{height}" '
        f'viewBox="{view}" overflow="visible">{inner}</svg>'
    )


def text_width(text, font_path, size):
    font = ImageFont.truetype(font_path, size)
    return font.getlength(text)


def city_card(city):
    name = city["name"]
    # One line when it fits the right-hand column. The longest name
    # (Bainbridge Island) still fits at 64px.
    size = 72
    if text_width(name, SERIF, size) > 520:
        size = 60
    name_w = text_width(name, SERIF, size)
    # Keep the name clear of the right edge.
    text_x = 568
    if text_x + name_w > 1144:
        text_x = 1144 - name_w

    kicker_y = 248
    name_y = 336
    line_y = 392

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <rect width="{W}" height="{H}" fill="{PAPER}"/>
  <circle cx="160" cy="40" r="260" fill="{GOLD}" opacity="0.16"/>
  <rect x="56" y="56" width="476" height="518" rx="40" fill="{FOREST}"/>
  <rect x="56" y="56" width="476" height="518" rx="40" fill="none" stroke="{GOLD}" stroke-width="3"/>
  {nested_map(city["state"], city["id"], 92, 96, 404, 438)}
  <text x="{text_x}" y="{kicker_y}" fill="{GOLD_INK}" font-family="Liberation Sans" font-weight="700" font-size="18" letter-spacing="1.1">EASTSIDE FAMILY CALENDAR</text>
  <text x="{text_x}" y="{name_y}" fill="{FOREST}" font-family="Liberation Serif" font-weight="700" font-size="{size}">{xml_escape(name)}</text>
  <text x="{text_x}" y="{line_y}" fill="{MUTED}" font-family="Liberation Sans" font-size="30">Family events</text>
</svg>
'''


def home_card():
    # Two rows of two Eastside city marks on the right.
    tile = 168
    gap_x = 18
    gap_y = 14
    label_h = 26
    cols = 2
    grid_w = cols * tile + (cols - 1) * gap_x
    origin_x = W - 56 - grid_w
    origin_y = 128
    rows = [HOME_MARKS[:2], HOME_MARKS[2:]]
    tiles = []
    for row, marks in enumerate(rows):
        for col, (state, city_id, label) in enumerate(marks):
            x = origin_x + col * (tile + gap_x)
            y = origin_y + row * (tile + label_h + gap_y)
            inset = 18
            tiles.append(
                f'<rect x="{x}" y="{y}" width="{tile}" height="{tile}" rx="28" fill="{FOREST}"/>'
            )
            tiles.append(
                nested_map(state, city_id, x + inset, y + inset, tile - inset * 2, tile - inset * 2, stroke="3.4")
            )
            label_size = 18 if text_width(label, SANS, 18) < tile - 4 else 15
            tiles.append(
                f'<text x="{x + tile / 2}" y="{y + tile + 24}" text-anchor="middle" '
                f'fill="{MUTED}" font-family="Liberation Sans" font-size="{label_size}">{xml_escape(label)}</text>'
            )
    marks = "\n  ".join(tiles)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <rect width="{W}" height="{H}" fill="{PAPER}"/>
  <circle cx="120" cy="0" r="280" fill="{GOLD}" opacity="0.18"/>
  <circle cx="40" cy="630" r="180" fill="{FOREST}" opacity="0.05"/>
  <text x="64" y="150" fill="{GOLD_INK}" font-family="Liberation Sans" font-weight="700" font-size="22" letter-spacing="2.2">FAMILY EVENTS</text>
  <text x="64" y="236" fill="{FOREST}" font-family="Liberation Serif" font-weight="700" font-size="64">Eastside</text>
  <text x="64" y="310" fill="{FOREST}" font-family="Liberation Serif" font-weight="700" font-size="64">Family</text>
  <text x="64" y="384" fill="{FOREST}" font-family="Liberation Serif" font-weight="700" font-size="64">Calendar</text>
  <rect x="68" y="414" width="112" height="6" rx="3" fill="{GOLD}"/>
  <text x="64" y="478" fill="{MUTED}" font-family="Liberation Sans" font-size="26">Upcoming events on the Eastside.</text>
  {marks}
</svg>
'''


def rasterize(svg, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(dest), "-"],
        input=svg.encode(),
        check=True,
    )
    # Flat color cards compress well. Keep the type crisp.
    subprocess.run(
        ["pngquant", "--force", "--quality", "80-95", "--skip-if-larger", "--output", str(dest), str(dest)],
        check=False,
    )
    subprocess.run(["optipng", "-quiet", "-o2", str(dest)], check=True)


def main():
    cities = load_cities()
    expected = {
        "bellevue",
        "bothell",
        "issaquah",
        "kenmore",
        "kirkland",
        "maple-valley",
        "mercer-island",
        "redmond",
        "renton",
        "sammamish",
        "woodinville",
    }
    found = {city["id"] for city in cities}
    if found != expected:
        raise SystemExit(f"expected the Eastside city list, found {sorted(found)}")
    for city in cities:
        svg_path = MAP_DIR / city["state"] / f"{city['id']}.svg"
        if not svg_path.exists():
            raise SystemExit(f"missing map {svg_path}")
        rasterize(city_card(city), OUT_DIR / city["state"] / f"{city['id']}.png")
        print(f"og {city['state']}/{city['id']}")
    rasterize(home_card(), HOME_OUT)
    print(f"og home -> {HOME_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render the home page share image from the Eastside map.

The Pages workflow runs this before Jekyll. It reads
_includes/eastside-map.html, so a change to the lakes, roads, or city
labels shows up on the next deploy. The PNG is not committed.

Needs rsvg-convert (librsvg2-bin) and the Liberation fonts.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import ImageFont

ROOT = Path(__file__).resolve().parents[1]
MAP_INCLUDE = ROOT / "_includes" / "eastside-map.html"
DEFAULT_OUT = ROOT / "assets" / "images" / "og-home.png"

W, H = 1200, 630

# Site palette from assets/css/site.css. Inlined because the rasterizer
# does not load the stylesheet.
PAGE = "#f4efe6"
SHEET = "#fffdf9"
INK = "#1a2822"
TEXT = "#24332c"
MUTED = "#3f5148"
FOREST = "#1e4636"
GOLD = "#c6a15a"
GOLD_LINE = "#a6843f"
FOOTHILLS = "#d7e3d4"
WATER = "#c5d5de"
WATER_LINE = "#8eabb8"

SERIF_BOLD = "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf"
SERIF = "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf"
SANS_BOLD = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

# Larger than the live map so names survive a thumbnail. Pins and
# geography stay where the include drew them. A few labels shift so the
# bigger type does not sit on a neighbor.
CITY_SIZE = 24
ROAD_SIZE = 16
WATER_SIZE = 13
LABEL_NUDGE = {
    # East along SR-520, clear of the Lake Washington name.
    "520": (34, -16),
    # Lower in the lake, clear of Bellevue.
    "Lake Sammamish": (28, 34),
    # Just above the city name, which stays over its pin.
    "Snoqualmie River": (0, -10),
    # Below the Snoqualmie name.
    "Issaquah": (4, 22),
    # A little air beside Bothell.
    "Kenmore": (-8, 0),
}

TITLE = ["Eastside Family", "Calendar"]
TITLE_SIZE = 58
SUBTITLE = ["Family events in 15 Eastside towns,", "updated daily."]
SUBTITLE_SIZE = 26


def xml_escape(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def extract_map():
    raw = MAP_INCLUDE.read_text()
    raw = re.sub(
        r"\{%-?\s*comment\s*-?%\}.*?\{%-?\s*endcomment\s*-?%\}",
        "",
        raw,
        flags=re.S,
    )
    match = re.search(r"<svg\b([^>]*)>(.*)</svg>", raw, flags=re.S)
    if not match:
        raise SystemExit("eastside-map.html has no svg")
    view = re.search(r'viewBox="([^"]+)"', match.group(1))
    if not view:
        raise SystemExit("eastside map has no viewBox")
    inner = match.group(2)
    inner = re.sub(r"</?a\b[^>]*>", "", inner)
    inner = re.sub(r'<circle class="city-hit"[^>]*/>', "", inner)
    inner = inner.replace('r="6.5"', 'r="8"')
    return [float(part) for part in view.group(1).split()], inner.strip()


def nudge_labels(inner):
    def shift(match):
        cls = match.group(1)
        x = float(match.group(2))
        y = float(match.group(3))
        anchor = match.group(4) or ""
        text = match.group(5)
        dx, dy = LABEL_NUDGE.get(text, (0, 0))
        anchor_attr = f' text-anchor="{anchor}"' if anchor else ""
        return (
            f'<text class="{cls}" x="{x + dx:.1f}" y="{y + dy:.1f}"'
            f"{anchor_attr}>{text}</text>"
        )

    pattern = re.compile(
        r'<text class="([^"]+)" x="([^"]+)" y="([^"]+)"'
        r'(?: text-anchor="([^"]+)")?>([^<]+)</text>'
    )
    return pattern.sub(shift, inner)


def label_boxes(inner):
    sizes = {
        "city-label": CITY_SIZE,
        "road-label": ROAD_SIZE,
        "water-label": WATER_SIZE,
    }
    pattern = re.compile(
        r'<text class="([^"]+)" x="([^"]+)" y="([^"]+)"'
        r'(?: text-anchor="([^"]+)")?>([^<]+)</text>'
    )
    boxes = []
    for cls, x, y, anchor, text in pattern.findall(inner):
        size = sizes.get(cls, CITY_SIZE)
        font = ImageFont.truetype(SANS_BOLD, size)
        width = font.getlength(text)
        ascent, descent = font.getmetrics()
        x = float(x)
        y = float(y)
        anchor = anchor or "start"
        if anchor == "end":
            left = x - width
        elif anchor == "middle":
            left = x - width / 2
        else:
            left = x
        top = y - ascent
        boxes.append((left, top, left + width, top + ascent + descent, text))
    return boxes


def map_viewbox(base, boxes):
    min_x, min_y, width, height = base
    max_x = min_x + width
    max_y = min_y + height
    for left, top, right, bottom, _text in boxes:
        min_x = min(min_x, left - 12)
        min_y = min(min_y, top - 8)
        max_x = max(max_x, right + 12)
        max_y = max(max_y, bottom + 8)
    return min_x, min_y, max_x - min_x, max_y - min_y


def report_overlaps(boxes):
    for i, a in enumerate(boxes):
        for b in boxes[i + 1 :]:
            gap = 1.5
            if a[2] < b[0] + gap or b[2] < a[0] + gap:
                continue
            if a[3] < b[1] + gap or b[3] < a[1] + gap:
                continue
            print(f"label overlap: {a[4]} and {b[4]}", file=sys.stderr)


def map_style():
    return f"""
    .foothills {{ fill: {FOOTHILLS}; }}
    .water {{
      fill: {WATER};
      stroke: {WATER_LINE};
      stroke-width: 1.6;
      stroke-linejoin: round;
    }}
    .river {{
      fill: none;
      stroke: {WATER_LINE};
      stroke-width: 3.8;
      stroke-linecap: round;
      stroke-linejoin: round;
    }}
    .island {{
      fill: {PAGE};
      stroke: {WATER_LINE};
      stroke-width: 1.6;
      stroke-linejoin: round;
    }}
    .road {{
      fill: none;
      stroke: {GOLD_LINE};
      stroke-width: 2.8;
      stroke-linecap: round;
      stroke-linejoin: round;
    }}
    .water-label, .road-label, .city-label {{
      font-family: "Liberation Sans", sans-serif;
      font-weight: 700;
      stroke: {PAGE};
      paint-order: stroke fill;
      stroke-linejoin: round;
    }}
    .water-label {{
      fill: {MUTED};
      font-size: {WATER_SIZE}px;
      stroke-width: 4px;
      letter-spacing: 0.02em;
    }}
    .road-label {{
      fill: {FOREST};
      font-size: {ROAD_SIZE}px;
      stroke-width: 4px;
    }}
    .city-pin {{
      fill: {FOREST};
      stroke: {SHEET};
      stroke-width: 2.6;
    }}
    .city-label {{
      fill: {INK};
      font-size: {CITY_SIZE}px;
      stroke-width: 6px;
    }}
    """


def card_svg():
    base, inner = extract_map()
    inner = nudge_labels(inner)
    boxes = label_boxes(inner)
    report_overlaps(boxes)
    vb = map_viewbox(base, boxes)

    # Leave the left side for the title. The map keeps its own shape.
    margin_right = 28
    margin_y = 26
    text_reserve = 500
    avail_w = W - text_reserve - margin_right
    avail_h = H - margin_y * 2
    scale = min(avail_w / vb[2], avail_h / vb[3])
    map_w = vb[2] * scale
    map_h = vb[3] * scale
    map_x = W - margin_right - map_w
    map_y = (H - map_h) / 2

    title_font = ImageFont.truetype(SERIF_BOLD, TITLE_SIZE)
    sub_font = ImageFont.truetype(SERIF, SUBTITLE_SIZE)
    title_ascent, title_descent = title_font.getmetrics()
    sub_ascent, sub_descent = sub_font.getmetrics()
    title_gap = 70
    rule_gap = 26
    rule_h = 4
    sub_gap = 34
    sub_line = 34
    block_top_ascent = title_ascent
    block_height = (
        block_top_ascent
        + title_gap
        + title_descent
        + rule_gap
        + rule_h
        + sub_gap
        + sub_ascent
        + sub_line
        + sub_descent
    )
    # Optical center: a little above the middle, with room under the last line.
    block_top = (H - block_height) / 2 - 6
    title_y = block_top + title_ascent
    rule_y = title_y + title_gap + title_descent + rule_gap
    sub_y = rule_y + rule_h + sub_gap + sub_ascent
    text_x = 68
    rule_w = 92

    title_lines = "\n".join(
        f'<text x="{text_x}" y="{title_y + i * title_gap:.1f}" '
        f'fill="{INK}" font-family="Liberation Serif" font-weight="700" '
        f'font-size="{TITLE_SIZE}" letter-spacing="-1.4">{xml_escape(line)}</text>'
        for i, line in enumerate(TITLE)
    )
    sub_lines = "\n".join(
        f'<text x="{text_x}" y="{sub_y + i * sub_line:.1f}" '
        f'fill="{TEXT}" font-family="Liberation Serif" font-weight="400" '
        f'font-size="{SUBTITLE_SIZE}">{xml_escape(line)}</text>'
        for i, line in enumerate(SUBTITLE)
    )

    vx, vy, vw, vh = vb
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <title>Eastside Family Calendar</title>
  <rect width="{W}" height="{H}" fill="{PAGE}"/>
  {title_lines}
  <rect x="{text_x}" y="{rule_y:.1f}" width="{rule_w}" height="{rule_h}" rx="2" fill="{GOLD}"/>
  {sub_lines}
  <svg x="{map_x:.2f}" y="{map_y:.2f}" width="{map_w:.2f}" height="{map_h:.2f}" viewBox="{vx:.2f} {vy:.2f} {vw:.2f} {vh:.2f}">
    <style type="text/css"><![CDATA[{map_style()}]]></style>
    {inner}
  </svg>
</svg>
'''


def rasterize(svg, dest):
    if not shutil.which("rsvg-convert"):
        raise SystemExit("rsvg-convert is not installed")
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(dest), "-"],
        input=svg.encode(),
        check=True,
    )
    if shutil.which("optipng"):
        subprocess.run(["optipng", "-quiet", "-o2", str(dest)], check=False)


def main():
    dest = DEFAULT_OUT
    if len(sys.argv) == 3 and sys.argv[1] == "--out":
        dest = Path(sys.argv[2])
    elif len(sys.argv) != 1:
        raise SystemExit("usage: render-home-og.py [--out PATH]")
    svg = card_svg()
    rasterize(svg, dest)
    print(f"home og -> {dest}")


if __name__ == "__main__":
    main()

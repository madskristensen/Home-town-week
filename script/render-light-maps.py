#!/usr/bin/env python3
"""Draw one static map per town for the Christmas lights section.

The Pages workflow runs this before Jekyll. It reads
_data/holiday_lights.yml, fetches streets and water from OpenStreetMap,
and writes assets/maps/lights/{city}.svg. Pins are numbered in the same
order as the list on the page: town name, then display name.

The page credits "Map data OpenStreetMap contributors". There is no
interactive map library and no geolocation in the browser.
"""

import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
LIGHTS = ROOT / "_data" / "holiday_lights.yml"
CITIES = ROOT / "_data" / "cities.yml"
OUT_DIR = ROOT / "assets" / "maps" / "lights"

VIEW_W = 800
MIN_H = 420
MAX_H = 860
PAD = 36

LAND = "#efe6d4"
RULE = "#d9ccb8"
WATER = "#c5d4ce"
RIVER = "#a9c0b8"
FOREST = "#1e4636"
PIN_INK = "#f7f1e6"

# Narrower maps keep local streets. A town whose displays are far apart
# keeps the main roads so the file stays small.
ROAD_STYLE = {
    "living_street": ("#d4c6b0", 1.15),
    "residential": ("#d4c6b0", 1.15),
    "unclassified": ("#c9b89e", 1.4),
    "tertiary": ("#c0ad90", 1.75),
    "tertiary_link": ("#c0ad90", 1.55),
    "secondary": ("#b09a78", 2.25),
    "secondary_link": ("#b09a78", 1.9),
    "primary": ("#9c8464", 2.9),
    "primary_link": ("#9c8464", 2.3),
    "trunk": ("#8c7354", 3.3),
    "trunk_link": ("#8c7354", 2.5),
    "motorway": ("#7d6548", 3.7),
    "motorway_link": ("#7d6548", 2.7),
}

ROAD_RANK = {name: index for index, name in enumerate(ROAD_STYLE)}

USER_AGENT = (
    "EastsideFamilyCalendar/1.0 (christmas light maps; https://eastsidecalendar.com)"
)
ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)


def mercator(lat, lng):
    lat_r = math.radians(max(min(lat, 85.0), -85.0))
    return math.radians(lng), math.log(math.tan(math.pi / 4 + lat_r / 2))


def unmercator(x, y):
    lng = math.degrees(x)
    lat = math.degrees(2 * math.atan(math.exp(y)) - math.pi / 2)
    return lat, lng


def load_towns():
    cities = {
        row["id"]: row["name"]
        for row in yaml.safe_load(CITIES.read_text())
        if isinstance(row, dict) and row.get("id") and row.get("name")
    }
    towns = {}
    for row in yaml.safe_load(LIGHTS.read_text()) or []:
        if not isinstance(row, dict):
            continue
        city_id = str(row.get("city") or "").strip()
        name = str(row.get("name") or "").strip()
        try:
            lat = float(row.get("lat"))
            lng = float(row.get("lng"))
        except (TypeError, ValueError):
            print(f"skip {name or city_id}: missing lat/lng", file=sys.stderr)
            continue
        if not city_id or city_id not in cities or not name:
            continue
        if not (45.0 <= lat <= 49.5 and -125.0 <= lng <= -116.0):
            print(f"skip {name}: lat/lng outside Washington", file=sys.stderr)
            continue
        towns.setdefault(city_id, []).append(
            {"name": name, "city": cities[city_id], "lat": lat, "lng": lng}
        )
    ordered = []
    for city_id, pins in towns.items():
        pins.sort(key=lambda pin: pin["name"])
        for number, pin in enumerate(pins, start=1):
            pin["number"] = number
        ordered.append((city_id, pins))
    ordered.sort(key=lambda item: item[1][0]["city"])
    return ordered


def fit(pins):
    pts = [mercator(pin["lat"], pin["lng"]) for pin in pins]
    xs = [pt[0] for pt in pts]
    ys = [pt[1] for pt in pts]
    # A single pin still shows the surrounding blocks. Mercator y grows
    # faster than longitude at this latitude, so the two minimums match
    # on the ground.
    span_x = max(max(xs) - min(xs), math.radians(0.016))
    span_y = max(max(ys) - min(ys), math.radians(0.012) / math.cos(math.radians(47.6)))
    span_x *= 1.32
    span_y *= 1.32
    content_w = VIEW_W - 2 * PAD
    view_h = 2 * PAD + content_w * (span_y / span_x)
    if view_h < MIN_H:
        view_h = MIN_H
        span_y = span_x * (view_h - 2 * PAD) / content_w
    elif view_h > MAX_H:
        view_h = MAX_H
        span_x = span_y * content_w / (view_h - 2 * PAD)
    view_h = int(round(view_h))
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    south, west = unmercator(cx - span_x / 2, cy - span_y / 2)
    north, east = unmercator(cx + span_x / 2, cy + span_y / 2)
    return {
        "cx": cx,
        "cy": cy,
        "span_x": span_x,
        "span_y": span_y,
        "south": south,
        "west": west,
        "north": north,
        "east": east,
        "view_h": view_h,
    }


def project(lat, lng, frame):
    view_h = frame["view_h"]
    x, y = mercator(lat, lng)
    px = PAD + (x - (frame["cx"] - frame["span_x"] / 2)) / frame["span_x"] * (VIEW_W - 2 * PAD)
    py = PAD + ((frame["cy"] + frame["span_y"] / 2) - y) / frame["span_y"] * (view_h - 2 * PAD)
    return px, py


def overpass(query):
    data = urllib.parse.urlencode({"data": query}).encode()
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    last = None
    for endpoint in ENDPOINTS:
        for attempt in range(2):
            try:
                req = urllib.request.Request(endpoint, data=data, headers=headers)
                with urllib.request.urlopen(req, timeout=90) as resp:
                    return json.load(resp)
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
                last = exc
                time.sleep(4 * (attempt + 1))
    raise RuntimeError(f"OpenStreetMap request failed: {last}")


def fetch_features(frame):
    south = frame["south"]
    west = frame["west"]
    north = frame["north"]
    east = frame["east"]
    residential = max(north - south, east - west) < 0.055
    roads = (
        "motorway|motorway_link|trunk|trunk_link|primary|primary_link|"
        "secondary|secondary_link|tertiary|tertiary_link|unclassified"
    )
    if residential:
        roads += "|residential|living_street"
    box = f"{south:.6f},{west:.6f},{north:.6f},{east:.6f}"
    query = f"""
[out:json][timeout:45];
(
  way["highway"~"^({roads})$"]({box});
  way["natural"="water"]({box});
  way["water"~"^(river|lake|pond|reservoir|canal)$"]({box});
  way["waterway"~"^(river|canal)$"]({box});
  relation["natural"="water"]({box});
);
out geom;
"""
    payload = overpass(query)
    return payload.get("elements") or []


def geometry(element):
    pts = []
    for node in element.get("geometry") or []:
        lat = node.get("lat")
        lng = node.get("lon")
        if lat is None or lng is None:
            continue
        pts.append((float(lat), float(lng)))
    return pts


def in_frame(lat, lng, frame, margin=0.004):
    return (
        frame["south"] - margin <= lat <= frame["north"] + margin
        and frame["west"] - margin <= lng <= frame["east"] + margin
    )


def clip_parts(coords, frame):
    parts = []
    current = []
    for lat, lng in coords:
        if in_frame(lat, lng, frame):
            current.append((lat, lng))
        elif current:
            if len(current) >= 2:
                parts.append(current)
            current = []
    if len(current) >= 2:
        parts.append(current)
    return parts


def rdp(points, epsilon):
    if len(points) < 3:
        return points
    start = points[0]
    end = points[-1]
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    norm = math.hypot(dx, dy) or 1
    farthest = 0
    index = 0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        dist = abs(dy * px - dx * py + end[0] * start[1] - end[1] * start[0]) / norm
        if dist > farthest:
            farthest = dist
            index = i
    if farthest > epsilon:
        left = rdp(points[: index + 1], epsilon)
        right = rdp(points[index:], epsilon)
        return left[:-1] + right
    return [start, end]


def path_of(coords, frame, epsilon=2.1):
    pixels = [project(lat, lng, frame) for lat, lng in coords]
    pixels = rdp(pixels, epsilon)
    if len(pixels) < 2:
        return ""
    xs = [pt[0] for pt in pixels]
    ys = [pt[1] for pt in pixels]
    if max(xs) - min(xs) < 8 and max(ys) - min(ys) < 8:
        return ""
    commands = [f"M{pixels[0][0]:.0f} {pixels[0][1]:.0f}"]
    commands.extend(f"L{x:.0f} {y:.0f}" for x, y in pixels[1:])
    return " ".join(commands)


def closed(coords):
    if len(coords) < 4:
        return False
    return math.hypot(coords[0][0] - coords[-1][0], coords[0][1] - coords[-1][1]) < 0.0004


def xml(text):
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def render(city_id, pins, elements, frame):
    waters = []
    rivers = []
    roads = []
    for element in elements:
        if element.get("type") == "relation":
            for member in element.get("members") or []:
                if member.get("type") != "way":
                    continue
                coords = geometry(member)
                for part in clip_parts(coords, frame):
                    waters.append(part)
            continue
        tags = element.get("tags") or {}
        coords = geometry(element)
        if not coords:
            continue
        highway = tags.get("highway")
        if highway in ROAD_STYLE:
            for part in clip_parts(coords, frame):
                roads.append((ROAD_RANK[highway], highway, part))
            continue
        if tags.get("waterway") in {"river", "canal"} and "natural" not in tags and "water" not in tags:
            for part in clip_parts(coords, frame):
                rivers.append(part)
            continue
        for part in clip_parts(coords, frame):
            waters.append(part)

    roads.sort(key=lambda item: item[0])
    view_h = frame["view_h"]
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {VIEW_W} {view_h}" width="{VIEW_W}" height="{view_h}" role="img">',
        f"<title>{xml(pins[0]['city'])} Christmas lights</title>",
        "<desc>Map data OpenStreetMap contributors</desc>",
        f'<rect width="{VIEW_W}" height="{view_h}" fill="{LAND}"/>',
        f'<clipPath id="frame"><rect width="{VIEW_W}" height="{view_h}"/></clipPath>',
        '<g clip-path="url(#frame)" fill="none" stroke-linecap="round" stroke-linejoin="round">',
    ]
    for part in waters:
        d = path_of(part, frame)
        if not d:
            continue
        fill = WATER if closed(part) else "none"
        stroke = "none" if closed(part) else RIVER
        width = 0 if closed(part) else 1.6
        parts.append(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>')
    for part in rivers:
        d = path_of(part, frame)
        if d:
            parts.append(f'<path d="{d}" fill="none" stroke="{RIVER}" stroke-width="1.6"/>')
    for _rank, highway, part in roads:
        d = path_of(part, frame)
        if not d:
            continue
        color, width = ROAD_STYLE[highway]
        parts.append(f'<path d="{d}" stroke="{color}" stroke-width="{width}"/>')
    parts.append("</g>")
    parts.append(
        f'<rect x="0.5" y="0.5" width="{VIEW_W - 1}" height="{view_h - 1}" fill="none" stroke="{RULE}" stroke-width="1"/>'
    )
    placed = []
    for pin in pins:
        x, y = project(pin["lat"], pin["lng"], frame)
        x = min(max(x, PAD), VIEW_W - PAD)
        y = min(max(y, PAD), view_h - PAD)
        for other_x, other_y in placed:
            dx = x - other_x
            dy = y - other_y
            dist = math.hypot(dx, dy) or 0.01
            if dist < 34:
                x += (dx / dist) * (34 - dist)
                y += (dy / dist) * (34 - dist)
        x = min(max(x, PAD), VIEW_W - PAD)
        y = min(max(y, PAD), view_h - PAD)
        placed.append((x, y))
        number = pin["number"]
        parts.append(
            f'<g class="pin">'
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="13" fill="{FOREST}" stroke="{PIN_INK}" stroke-width="2"/>'
            f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="middle" dominant-baseline="central" '
            f'fill="{PIN_INK}" font-family="Georgia, Palatino, serif" font-size="14" font-weight="700">{number}</text>'
            f"</g>"
        )
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def main():
    towns = load_towns()
    if not towns:
        print("No Christmas light displays to map.", file=sys.stderr)
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    written = set()
    manifest = {}
    for index, (city_id, pins) in enumerate(towns):
        if index:
            time.sleep(1)
        dest = OUT_DIR / f"{city_id}.svg"
        frame = fit(pins)
        try:
            elements = fetch_features(frame)
            svg = render(city_id, pins, elements, frame)
        except Exception as exc:
            if dest.exists():
                print(f"keep {dest.name}: {exc}", file=sys.stderr)
                written.add(dest)
                manifest[city_id] = {"width": VIEW_W, "height": frame["view_h"]}
                continue
            print(f"fail {city_id}: {exc}", file=sys.stderr)
            return 1
        dest.write_text(svg)
        written.add(dest)
        manifest[city_id] = {"width": VIEW_W, "height": frame["view_h"]}
        print(
            f"{dest.relative_to(ROOT)} {dest.stat().st_size} bytes, "
            f"{len(pins)} pins, {VIEW_W}x{frame['view_h']}"
        )
    manifest_path = ROOT / "_data" / "light_maps.yml"
    lines = []
    for city_id, size in manifest.items():
        lines.append(f"{city_id}:")
        lines.append(f"  width: {size['width']}")
        lines.append(f"  height: {size['height']}")
    manifest_path.write_text("\n".join(lines) + "\n")
    for old in OUT_DIR.glob("*.svg"):
        if old not in written:
            old.unlink()
            print(f"removed {old.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

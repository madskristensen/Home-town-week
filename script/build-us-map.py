#!/usr/bin/env python3
"""Build the home-page US map from the us-atlas Albers states file.

The Census Bureau state outlines are public domain. us-atlas (ISC) ships
them already projected, with Alaska and Hawaii inset. This writes
_data/us_map.json. The home page highlights a state only when
_data/cities.yml has a city there.

    python3 script/build-us-map.py
"""

import json
import math
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "_data" / "us_map.json"
SOURCE = "https://cdn.jsdelivr.net/npm/us-atlas@3.0.1/states-albers-10m.json"

# Keep about a pixel of error on the ~1000px map.
EPSILON = 0.85
PAD = 8

FIPS = {
    "01": "al", "02": "ak", "04": "az", "05": "ar", "06": "ca", "08": "co",
    "09": "ct", "10": "de", "11": "dc", "12": "fl", "13": "ga", "15": "hi",
    "16": "id", "17": "il", "18": "in", "19": "ia", "20": "ks", "21": "ky",
    "22": "la", "23": "me", "24": "md", "25": "ma", "26": "mi", "27": "mn",
    "28": "ms", "29": "mo", "30": "mt", "31": "ne", "32": "nv", "33": "nh",
    "34": "nj", "35": "nm", "36": "ny", "37": "nc", "38": "nd", "39": "oh",
    "40": "ok", "41": "or", "42": "pa", "44": "ri", "45": "sc", "46": "sd",
    "47": "tn", "48": "tx", "49": "ut", "50": "vt", "51": "va", "53": "wa",
    "54": "wv", "55": "wi", "56": "wy",
}


def decode_arc(data, scale, translate, idx):
    rev = idx < 0
    arc = data["arcs"][~idx if rev else idx]
    x = y = 0
    pts = []
    for dx, dy in arc:
        x += dx
        y += dy
        pts.append((x * scale[0] + translate[0], y * scale[1] + translate[1]))
    if rev:
        pts.reverse()
    return pts


def stitch(data, scale, translate, indexes):
    pts = []
    for i, idx in enumerate(indexes):
        part = decode_arc(data, scale, translate, idx)
        if i:
            part = part[1:]
        pts.extend(part)
    return pts


def polygons(geom):
    groups = geom["arcs"]
    if geom["type"] == "Polygon":
        groups = [groups]
    return groups


def perp_dist(p, a, b):
    x, y = p
    x1, y1 = a
    x2, y2 = b
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(x - x1, y - y1)
    t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)
    t = max(0, min(1, t))
    return math.hypot(x - (x1 + t * dx), y - (y1 + t * dy))


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    keep = {0, len(pts) - 1}
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        max_d = -1
        idx = None
        for k in range(i + 1, j):
            d = perp_dist(pts[k], pts[i], pts[j])
            if d > max_d:
                max_d = d
                idx = k
        if idx is not None and max_d > eps:
            keep.add(idx)
            stack.append((i, idx))
            stack.append((idx, j))
    return [pts[i] for i in sorted(keep)]


def ring_area(pts):
    area = 0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return area / 2


def centroid(pts):
    area = ring_area(pts)
    if abs(area) < 1:
        n = len(pts) or 1
        return sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n
    cx = cy = 0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        cross = x1 * y2 - x2 * y1
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    return cx / (6 * area), cy / (6 * area)


def close_enough(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1]) < 0.05


def simplify_ring(pts):
    if len(pts) >= 2 and close_enough(pts[0], pts[-1]):
        pts = pts[:-1]
    if len(pts) < 3:
        return None
    simple = rdp(pts, EPSILON)
    if len(simple) < 3:
        return None
    # Drop specks that disappear at display size. Keep lakes and real islands.
    xs = [p[0] for p in simple]
    ys = [p[1] for p in simple]
    if max(xs) - min(xs) < 3.5 and max(ys) - min(ys) < 3.5:
        return None
    if not close_enough(simple[0], simple[-1]):
        simple = simple + [simple[0]]
    return simple


def path_for(rings, ox, oy):
    parts = []
    for ring in rings:
        cmds = []
        for i, (x, y) in enumerate(ring):
            px = round(x - ox, 1)
            py = round(y - oy, 1)
            cmds.append(("M" if i == 0 else "L") + f"{px:.1f} {py:.1f}")
        cmds.append("Z")
        parts.append(" ".join(cmds))
    return " ".join(parts)


def main():
    raw = urllib.request.urlopen(SOURCE, timeout=30).read()
    data = json.loads(raw)
    scale = data["transform"]["scale"]
    translate = data["transform"]["translate"]

    built = []
    for geom in data["objects"]["states"]["geometries"]:
        code = FIPS.get(geom["id"])
        if not code:
            raise SystemExit(f"unknown FIPS {geom['id']}")
        rings = []
        areas = []
        for group in polygons(geom):
            for indexes in group:
                ring = simplify_ring(stitch(data, scale, translate, indexes))
                if not ring:
                    continue
                rings.append(ring)
                areas.append(abs(ring_area(ring[:-1])))
        if not rings:
            raise SystemExit(f"no rings for {code}")
        big = rings[areas.index(max(areas))]
        lx, ly = centroid(big[:-1])
        built.append({
            "code": code,
            "name": geom["properties"]["name"],
            "rings": rings,
            "lx": lx,
            "ly": ly,
        })

    xs, ys = [], []
    for state in built:
        for ring in state["rings"]:
            for x, y in ring:
                xs.append(x)
                ys.append(y)
    ox = min(xs) - PAD
    oy = min(ys) - PAD
    width = math.ceil(max(xs) - ox + PAD)
    height = math.ceil(max(ys) - oy + PAD)

    states = []
    for state in sorted(built, key=lambda s: s["code"]):
        states.append({
            "code": state["code"],
            "name": state["name"],
            "d": path_for(state["rings"], ox, oy),
            "lx": round(state["lx"] - ox, 1),
            "ly": round(state["ly"] - oy, 1),
        })

    payload = {
        "view_box": f"0 0 {width} {height}",
        "states": states,
    }
    OUT.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
    points = sum(item["d"].count("L") + item["d"].count("M") for item in states)
    print(f"wrote {OUT.relative_to(ROOT)} states={len(states)} points={points} bytes={OUT.stat().st_size} viewBox={payload['view_box']}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Minify Leaflet's stylesheet and drop rules this site never uses.

Source is assets/leaflet/leaflet.full.css. The build writes
assets/leaflet/leaflet.css. Kept: popup, tooltip-top, zoom control,
attribution, panes, tiles, and zoom animation. Marker clusters are
styled in map.css, not here.
"""

import sys
from pathlib import Path

try:
    import rcssmin
except ImportError:
    sys.exit("rcssmin is required: python3 -m pip install rcssmin")

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "leaflet" / "leaflet.full.css"
DEST = ROOT / "assets" / "leaflet" / "leaflet.css"

# A selector is dropped when it only exists for a feature the maps do not use.
DROP_BITS = (
    "leaflet-control-layers",
    "leaflet-control-scale",
    "leaflet-oldie",
    ".lvml",
    "leaflet-vml",
    "leaflet-image-layer",
    "leaflet-zoom-box",
    "leaflet-tooltip-bottom",
    "leaflet-tooltip-left",
    "leaflet-tooltip-right",
    "leaflet-default-icon-path",
    "leaflet-marker-shadow",
    "leaflet-shadow-pane",
    "leaflet-overlay-pane",
    "leaflet-crosshair",
    "leaflet-dragging",
    "leaflet-marker-draggable",
    "leaflet-retina",
    "leaflet-safari",
    "leaflet-popup-tip-container",
    "leaflet-pane > svg",
    "leaflet-pane>svg",
    "leaflet-pane > canvas",
    "leaflet-pane>canvas",
    "leaflet-map-pane canvas",
    "leaflet-map-pane>canvas",
)


def split_rules(css):
    rules = []
    i = 0
    n = len(css)
    while i < n:
        while i < n and css[i].isspace():
            i += 1
        if i >= n:
            break
        if css.startswith("/*", i):
            end = css.find("*/", i)
            if end < 0:
                break
            i = end + 2
            continue
        start = i
        depth = 0
        while i < n:
            if css[i] == "{":
                depth += 1
            elif css[i] == "}":
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            i += 1
        rules.append(css[start:i].strip())
    return rules


def drop_selector(selector):
    compact = " ".join(selector.split())
    return any(bit in compact for bit in DROP_BITS)


def trim_rule(rule):
    if rule.startswith("@media") or rule.startswith("@supports") or rule.startswith("@keyframes"):
        head, body = rule.split("{", 1)
        body = body[:-1]
        kept = []
        for inner in split_rules(body):
            trimmed = trim_rule(inner)
            if trimmed:
                kept.append(trimmed)
        if not kept:
            return ""
        return head.strip() + "{" + "".join(kept) + "}"
    if "{" not in rule:
        return ""
    sel, body = rule.split("{", 1)
    parts = []
    for piece in sel.split(","):
        if piece.strip() and not drop_selector(piece):
            parts.append(piece.strip())
    if not parts:
        return ""
    return ",".join(parts) + "{" + body[:-1].strip() + "}"


def main():
    if not SRC.is_file():
        sys.exit(f"missing {SRC}")
    raw = SRC.read_text(encoding="utf-8")
    kept = [trim_rule(rule) for rule in split_rules(raw)]
    kept = [rule for rule in kept if rule]
    trimmed = "\n".join(kept) + "\n"
    mini = rcssmin.cssmin(trimmed).strip()
    note = (
        "/* Trimmed Leaflet CSS: popup, tooltip-top, zoom, attribution, "
        "panes, tiles, and zoom animation. Unused controls and marker images are omitted. */\n"
    )
    DEST.write_text(note + mini + "\n", encoding="utf-8")
    print(f"leaflet\t{DEST.name}\t{len(raw)}\t{DEST.stat().st_size}")


if __name__ == "__main__":
    main()

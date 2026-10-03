#!/usr/bin/env python3
"""Minify the stylesheets and publish one shared screen file.

Reads _css/*.css. site.css and print.css are written as
assets/css/<name>.<hash>.css and recorded in _data/css.yml. The small
per-layout files are minified into _data/css_inline.json so the head can
inline them. A page then has one render-blocking stylesheet, and site.css
stays the file every page can cache. Run this before the site is read.
"""

import hashlib
import json
import sys
from pathlib import Path

try:
    import rcssmin
except ImportError:
    sys.exit("rcssmin is required: python3 -m pip install rcssmin")

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "_css"
DEST = ROOT / "assets" / "css"
DATA = ROOT / "_data" / "css.yml"
LINKED = ("site", "print")
INLINE = ("home", "city", "seasonal", "feature", "map", "map_halloween", "playgrounds", "nav_preview")
INLINE_DATA = ROOT / "_data" / "css_inline.json"


def minify(name):
    source = SRC / f"{name}.css"
    if not source.is_file():
        sys.exit(f"missing stylesheet {source}")
    raw = source.read_text(encoding="utf-8")
    mini = rcssmin.cssmin(raw)
    if not mini.endswith("\n"):
        mini += "\n"
    if mini.count("\n") != 1 or len(mini) > len(raw):
        sys.exit(f"{name}.css was not minified before fingerprinting")
    if "</style" in mini.lower():
        sys.exit(f"{name}.css cannot be inlined")
    return mini


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for old in DEST.glob("*.css"):
        old.unlink()

    lines = []
    for name in LINKED:
        mini = minify(name)
        digest = hashlib.sha256(mini.encode("utf-8")).hexdigest()[:10]
        filename = f"{name}.{digest}.css"
        (DEST / filename).write_text(mini, encoding="utf-8")
        public = f"/assets/css/{filename}"
        lines.append(f"{name}: {public}")
        print(f"{name}\t{public}\t{len(mini)}")

    inlined = {}
    for name in INLINE:
        mini = minify(name).rstrip("\n")
        inlined[name] = mini
        print(f"{name}\tinline\t{len(mini)}")

    DATA.write_text("\n".join(lines) + "\n", encoding="utf-8")
    INLINE_DATA.write_text(json.dumps(inlined, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    main()

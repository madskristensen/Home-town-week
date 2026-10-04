#!/usr/bin/env python3
"""Warn when a master photo is wider than the cap. Does not fail the build.

Card masters stay at about 1600px on the long side. City heroes may
go to 2000px. The Pages log shows a warning. Nothing is rewritten.

    python3 script/check-master-cap.py
"""

import os
import re
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

IMAGE_ROOT = os.path.join("assets", "images")
SKIP_TOP = {"cities", "og", "share"}
SKIP_NAMES = {"logo.png", "apple-touch-icon.png", "favicon.png"}
CARD_CAP = 1600
HERO_CAP = 2000
VARIANT_RE = re.compile(r"-(?:400|640|800|960|1200|1280|1600)$")


def hero_paths():
    path = os.path.join("_data", "cities.yml")
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    found = set()
    for block in re.finditer(r"\n  hero:\n(?:    .+\n)+", text):
        match = re.search(r"image:\s*(\S+)", block.group(0))
        if not match:
            continue
        found.add(match.group(1).strip().strip("\"'").lstrip("/"))
    return found


def main():
    heroes = hero_paths()
    warned = 0
    for dirpath, dirnames, filenames in os.walk(IMAGE_ROOT):
        dirnames[:] = [name for name in dirnames if name not in SKIP_TOP]
        rel_dir = os.path.relpath(dirpath, IMAGE_ROOT)
        if rel_dir == ".":
            continue
        for name in filenames:
            if name in SKIP_NAMES or name.startswith("icon-"):
                continue
            stem, ext = os.path.splitext(name)
            if ext.lower() not in {".webp", ".jpg", ".jpeg", ".png"}:
                continue
            if VARIANT_RE.search(stem):
                continue
            path = os.path.join(dirpath, name)
            rel = path.replace(os.sep, "/")
            cap = HERO_CAP if rel in heroes else CARD_CAP
            try:
                width, height = Image.open(path).size
            except Exception as exc:
                print("::warning file=%s::Could not read master: %s" % (rel, exc))
                warned += 1
                continue
            long_side = max(width, height)
            if long_side <= cap:
                continue
            print(
                "::warning file=%s::Master is %dpx on the long side. The cap is %dpx."
                % (rel, long_side, cap)
            )
            warned += 1
    if warned:
        print("%d master(s) over the cap." % warned)
    else:
        print("masters are within the cap")


if __name__ == "__main__":
    main()

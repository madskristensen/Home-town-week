#!/usr/bin/env python3
"""Fail when a referenced photo is missing its fixed variant files.

Card photos need name-400.avif, name-640.avif, and name-640.jpg beside
the master. City heroes also need name-800.avif, name-1200.avif, and
name-1600.avif. The card template builds those names directly, so a
missing file would be a broken image.

    python3 script/check-image-variants.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP = {
    ".git",
    "_site",
    "vendor",
    "node_modules",
    ".image-cache",
    ".share-cache",
}
TEXT_EXT = {".md", ".html", ".yml", ".yaml", ".rb", ".js", ".mjs", ".json"}
PATH_RE = re.compile(r"/?assets/images/[A-Za-z0-9_./-]+\.(?:webp|jpe?g|png)", re.I)
VARIANT_RE = re.compile(r"-(?:400|640|800|960|1200|1280|1600)\.(?:avif|jpe?g)$", re.I)
SKIP_TOP = {"cities", "og", "share"}
SKIP_NAMES = {"logo.png", "apple-touch-icon.png", "favicon.png", "og-home.png"}
CARD = ("400.avif", "640.avif", "640.jpg")
HERO_EXTRA = ("800.avif", "1200.avif", "1600.avif")


def hero_paths():
    text = (ROOT / "_data" / "cities.yml").read_text(encoding="utf-8")
    found = set()
    for block in re.finditer(r"\n  hero:\n(?:    .+\n)+", text):
        match = re.search(r"image:\s*(\S+)", block.group(0))
        if not match:
            continue
        found.add(match.group(1).strip().strip("\"'").lstrip("/"))
    return found


def referenced_paths():
    found = set()
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_EXT:
            continue
        if any(part in SKIP for part in path.relative_to(ROOT).parts):
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for match in PATH_RE.findall(text):
            rel = match.lstrip("/")
            name = rel.rsplit("/", 1)[-1]
            top = rel.split("/")[2] if rel.startswith("assets/images/") else ""
            if top in SKIP_TOP or name in SKIP_NAMES or name.startswith("icon-"):
                continue
            if VARIANT_RE.search(name):
                continue
            found.add(rel)
    return found


def required_names(rel, heroes):
    stem = rel.rsplit(".", 1)[0]
    names = ["%s-%s" % (stem, spec) for spec in CARD]
    if rel in heroes:
        names.extend("%s-%s" % (stem, spec) for spec in HERO_EXTRA)
    return names


def main():
    heroes = hero_paths()
    missing = []
    refs = referenced_paths()
    if not refs:
        sys.exit("no referenced photos found")
    for rel in sorted(refs):
        master = ROOT / rel
        if not master.is_file():
            missing.append("%s (master missing)" % rel)
            continue
        for name in required_names(rel, heroes):
            if not (ROOT / name).is_file():
                missing.append(name)
    if missing:
        print("missing image variants:")
        for name in missing:
            print("  %s" % name)
        sys.exit(1)
    print("image variants ok (%d photos)" % len(refs))


if __name__ == "__main__":
    main()

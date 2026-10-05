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
import re
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
INLINE = (
    "home",
    "city",
    "seasonal",
    "feature",
    "map",
    "map_halloween",
    "playgrounds",
    "camps",
    "no_school",
    "partner",
    "suggest",
    "check",
)
INLINE_DATA = ROOT / "_data" / "css_inline.json"
NS_DEFAULT = "lwsd"


def district_slugs():
    text = (ROOT / "_data" / "no_school_days.yml").read_text(encoding="utf-8")
    return re.findall(r"(?m)^    slug: ([a-z0-9-]+)\s*$", text)


def district_block(kind):
    slugs = district_slugs()
    if NS_DEFAULT not in slugs:
        sys.exit(f"no-school default {NS_DEFAULT} is not a district slug")
    if kind == "show":
        parts = [
            f'html:not([data-ns]) .ns-one[data-d="{NS_DEFAULT}"]',
            f'html:not([data-ns]) .ns-line[data-d="{NS_DEFAULT}"]',
            f'html:not([data-ns]) .ns-weekly[data-d="{NS_DEFAULT}"]',
        ]
        for slug in slugs:
            parts.extend(
                [
                    f'html[data-ns="{slug}"] .ns-one[data-d="{slug}"]',
                    f'html[data-ns="{slug}"] .ns-line[data-d="{slug}"]',
                    f'html[data-ns="{slug}"] .ns-weekly[data-d="{slug}"]',
                ]
            )
        body = "  display: block;"
    else:
        parts = [f'html:not([data-ns]) .ns-day:has(.ns-one[data-d="{NS_DEFAULT}"])']
        parts.extend(
            f'html[data-ns="{slug}"] .ns-day:has(.ns-one[data-d="{slug}"])' for slug in slugs
        )
        body = "  background: color-mix(in srgb, var(--ink) 8%, var(--sheet));"
    return ",\n".join(parts) + " {\n" + body + "\n}"


def expand_districts(raw):
    raw = raw.replace("/* @ns-show */", district_block("show"))
    raw = raw.replace("/* @ns-days */", district_block("days"))
    if "/* @ns-" in raw:
        sys.exit("no-school.css still has a district marker")
    return raw


def minify(name):
    source = SRC / f"{name}.css"
    if name == "no_school":
        source = SRC / "no-school.css"
    if not source.is_file():
        sys.exit(f"missing stylesheet {source}")
    raw = source.read_text(encoding="utf-8")
    if name == "no_school":
        raw = expand_districts(raw)
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
    fingerprint_js()


def fingerprint_js():
    """Publish _js sources as assets/js/<name>.<hash>.js.

    The source stays in _js so Jekyll does not also copy the unhashed file.
    page.js is the shared behavior file (service worker, filters, menus).
    """
    sources = (
        ("event-share.js", "event_share"),
        ("page.js", "page"),
    )
    dest_dir = ROOT / "assets" / "js"
    dest_dir.mkdir(parents=True, exist_ok=True)
    lines = []
    for filename, key in sources:
        source = ROOT / "_js" / filename
        if not source.is_file():
            sys.exit(f"missing script {source}")
        raw = source.read_text(encoding="utf-8")
        if not raw.endswith("\n"):
            raw += "\n"
        digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:10]
        stem = filename[:-3]
        for old in dest_dir.glob(f"{stem}.*.js"):
            old.unlink()
        hashed = f"{stem}.{digest}.js"
        (dest_dir / hashed).write_text(raw, encoding="utf-8")
        public = f"/assets/js/{hashed}"
        lines.append(f"{key}: {public}")
        print(f"{stem}\t{public}\t{len(raw)}")
    (ROOT / "_data" / "js.yml").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

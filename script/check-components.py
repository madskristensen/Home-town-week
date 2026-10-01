#!/usr/bin/env python3
"""Fail the build when shared component markup is copied outside its include."""

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

# Literal markup that has to stay in one include. COMPONENTS.md may name it.
RULES = (
    ('class="event-card', "_includes/event-card.html"),
    ("weekend-card", "_includes/event-card.html"),
    ("event-card--tile", "_includes/event-card.html"),
    ('class="event-photo"', "_includes/event-photo.html"),
    ('class="weekend-photo"', "_includes/event-photo.html"),
    ('class="page-intro"', "_includes/page-intro.html"),
    ('class="empty-suggest', "_includes/empty-suggest.html"),
    ('class="lights-feature', "_includes/lights-feature.html"),
    ('class="map-frame"', "_includes/map-frame.html"),
    ('class="filter-chip"', "_includes/filter-chip.html"),
)

# The bare word, not the class markup. Include calls are handled separately.
BARE_EVENT_CARD = "event-card"
BARE_ALLOW = {
    "_includes/event-card.html",
    "_includes/pwa.html",
    "README.md",
    "COMPONENTS.md",
}


def rel(path):
    return path.relative_to(ROOT).as_posix()


def scan_roots():
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".html", ".md"}:
            continue
        if any(part in SKIP for part in path.relative_to(ROOT).parts):
            continue
        yield path


def include_call(line):
    """A reference to the partial filename is not copied markup."""
    return "event-card.html" in line


def main():
    failures = []
    for path in scan_roots():
        name = rel(path)
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        for needle, owner in RULES:
            if name in {owner, "COMPONENTS.md"}:
                continue
            for number, line in enumerate(lines, 1):
                if needle in line:
                    failures.append(f"{name}:{number}: {needle} belongs in {owner}")
        if name in BARE_ALLOW or BARE_EVENT_CARD not in text:
            continue
        for number, line in enumerate(lines, 1):
            if BARE_EVENT_CARD not in line or include_call(line):
                continue
            # Class markup is already reported above.
            if 'class="event-card' in line or "event-card--tile" in line:
                continue
            failures.append(
                f"{name}:{number}: event-card belongs in _includes/event-card.html, "
                "_includes/pwa.html, README.md, or COMPONENTS.md"
            )

    if failures:
        print("Shared component markup is outside its include:", file=sys.stderr)
        for item in failures:
            print(item, file=sys.stderr)
        return 1

    print("Shared component markup stays in its includes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

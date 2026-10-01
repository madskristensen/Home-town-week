#!/usr/bin/env python3
"""Fail the build when shared component markup is copied outside its include.

Also fails when a tag pill would show a price or All ages. Free is the
only cost pill. A price and All ages are plain text on the card.

    python3 script/check-components.py
    python3 script/check-components.py --rendered _site
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


# A pill that shows money. "$12", "$ 12", or a cents amount such as 33.95.
PRICE_PILL = re.compile(r"\$\s?\d|\b\d+\.\d{2}\b")
TAG_LIST = re.compile(r"<ul\s+class=\"?event-tags\"?>(.*?)</ul>", re.I | re.S)
TAG_ITEM = re.compile(r"<li\b[^>]*>(.*?)</li>", re.I | re.S)
TAG_LINE = re.compile(r"^  tags:\s*(.*)$")
TAG_ITEM_LINE = re.compile(r"^    - (.+)$")


def strip_markup(value):
    text = re.sub(r"<[^>]+>", "", value)
    return (
        text.replace("&amp;", "&")
        .replace("&#36;", "$")
        .replace("&dollar;", "$")
        .replace("&nbsp;", " ")
        .strip()
    )


def pill_forbidden(label):
    text = " ".join(label.split())
    if not text:
        return False
    if "$" in text or PRICE_PILL.search(text):
        return True
    return text.casefold() == "all ages"


def yaml_tag_values(text):
    """Tag list items. The cost field is allowed to hold a price."""
    values = []
    pending = False
    for line in text.splitlines():
        match = TAG_LINE.match(line)
        if match:
            rest = match.group(1).strip()
            pending = rest in {"", "|", ">"}
            if rest.startswith("["):
                inner = rest.split("#", 1)[0].strip().strip("[]")
                for part in inner.split(","):
                    values.append(part.strip().strip("'\""))
                pending = False
            continue
        if not pending:
            continue
        item = TAG_ITEM_LINE.match(line)
        if item:
            values.append(item.group(1).split("#", 1)[0].strip().strip("'\""))
            continue
        if line.startswith("  ") and not line.startswith("    "):
            pending = False
    return values


def check_tag_rules():
    """Source rules that run before Jekyll, plus a scan of event tag lists."""
    failures = []
    tags = (ROOT / "_includes/event-tags.html").read_text(encoding="utf-8")
    card = (ROOT / "_includes/event-card.html").read_text(encoding="utf-8")
    labels = (ROOT / "_plugins/event_labels.rb").read_text(encoding="utf-8")
    if 'contains "$"' in tags or "contains '$'" in tags:
        failures.append(
            "_includes/event-tags.html: a cost pill is only for Free, never a price"
        )
    if re.search(r"<li>\s*All ages\s*</li>", tags) or 'or tag_ages == "All ages"' in tags:
        failures.append("_includes/event-tags.html: All ages is plain text, not a tag pill")
    if 'ev_cost contains "$"' in card or 'ev_ages == "All ages"' in card:
        failures.append(
            "_includes/event-card.html: data-cost is only Free, and All ages is not a tag"
        )
    cost_label = re.search(r"def cost_label\(event\).*?\n    def ", labels, re.S)
    body = cost_label.group(0) if cost_label else ""
    if "return cost if cost.match?" in body:
        failures.append(
            "_plugins/event_labels.rb: cost_label must return Free or nothing, never a price"
        )
    for path in (ROOT / "_data").glob("*_events.yml"):
        for value in yaml_tag_values(path.read_text(encoding="utf-8")):
            if pill_forbidden(value):
                failures.append(
                    f"{path.relative_to(ROOT).as_posix()}: tag {value!r} is a price or All ages"
                )
    return failures


def check_rendered(site):
    """Fail when a built tag pill contains a price or All ages."""
    root = Path(site)
    if not root.is_dir():
        return [f"{site}: built site is missing, so tag pills were not checked"]
    failures = []
    for path in root.rglob("*.html"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for group in TAG_LIST.finditer(text):
            for item in TAG_ITEM.finditer(group.group(1)):
                label = strip_markup(item.group(1))
                if pill_forbidden(label):
                    failures.append(f"{path}: tag pill {label!r}")
    return failures


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--rendered":
        site = sys.argv[2] if len(sys.argv) >= 3 else "_site"
        failures = check_rendered(site)
        if failures:
            print("A tag pill shows a price or All ages:", file=sys.stderr)
            for item in failures:
                print(item, file=sys.stderr)
            return 1
        print("Rendered tag pills have no price and no All ages.")
        return 0

    failures = []
    failures.extend(check_tag_rules())
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
        print("Shared component or tag-pill check failed:", file=sys.stderr)
        for item in failures:
            print(item, file=sys.stderr)
        return 1

    print("Shared component markup stays in its includes.")
    print("Tag pills are Free, ages, setting, and flags. Prices and All ages are text.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

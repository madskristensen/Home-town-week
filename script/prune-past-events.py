#!/usr/bin/env python3
"""Delete events whose last day is before today in America/Los_Angeles.

City pages and _data/{city}_events.yml are the source. This script edits
those files. It does not hide anything in the browser. A city page that
loses every event keeps its front matter; the layout then says none are
listed. Files that lose nothing are left byte for byte.

    python3 script/prune-past-events.py
    python3 script/prune-past-events.py --dry-run
    python3 script/prune-past-events.py --today 2026-10-05 --dry-run
"""

import argparse
import re
import sys
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import yaml

ROOT = Path(__file__).resolve().parents[1]
ZONE = ZoneInfo("America/Los_Angeles")
DATE_RE = re.compile(
    r"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})\b",
    re.I,
)
WHEN_RE = re.compile(r'<p class="event-when">(.*?)</p>', re.I | re.S)
MONTHS = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}


def today_in_pacific():
    return datetime.now(ZONE).date()


def as_date(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    text = str(value).strip()
    if len(text) < 10:
        return None
    try:
        return date.fromisoformat(text[:10])
    except ValueError:
        return None


def infer_date(month, day, today):
    options = []
    for year in (today.year - 1, today.year, today.year + 1):
        try:
            options.append(date(year, month, int(day)))
        except ValueError:
            continue
    if not options:
        return None
    # Closest calendar day. On a tie, keep the later one so a live event stays.
    return min(options, key=lambda item: (abs((item - today).days), 0 if item >= today else 1))


def dates_in_when(when_text, today):
    found = []
    for mon, day in DATE_RE.findall(when_text or ""):
        month = MONTHS.get(mon.lower()[:3])
        if not month:
            continue
        parsed = infer_date(month, day, today)
        if parsed:
            found.append(parsed)
    return found


def event_is_past(last_day, today):
    return last_day is not None and last_day < today


def split_front_matter(text):
    if not text.startswith("---\n"):
        return None
    rest = text[4:]
    fence = rest.find("\n---")
    if fence < 0:
        return None
    close = fence + len("\n---\n")
    if not rest.startswith("\n---\n", fence) and not rest.startswith("\n---\r\n", fence):
        # Closing fence with no trailing newline.
        match = re.match(r"\n---[ \t]*$", rest[fence:])
        if not match:
            return None
        close = fence + match.end()
    prefix = text[: 4 + close]
    body = text[4 + close :]
    return prefix, body


def split_markdown_events(body):
    lines = body.splitlines(keepends=True)
    prelude = []
    events = []
    index = 0
    while index < len(lines) and not re.match(r"###[ \t]", lines[index]):
        prelude.append(lines[index])
        index += 1
    while index < len(lines):
        if not re.match(r"###[ \t]", lines[index]):
            if events:
                events[-1].append(lines[index])
            else:
                prelude.append(lines[index])
            index += 1
            continue
        block = [lines[index]]
        index += 1
        while index < len(lines) and not re.match(r"###[ \t]", lines[index]):
            block.append(lines[index])
            index += 1
        events.append(block)
    return prelude, events


def markdown_last_day(block, today):
    text = "".join(block)
    match = WHEN_RE.search(text)
    if not match:
        return None
    when_text = re.sub(r"\s+", " ", match.group(1))
    found = dates_in_when(when_text, today)
    if not found:
        return None
    return max(found)


def prune_markdown(path, today, dry_run):
    original = path.read_text(encoding="utf-8")
    split = split_front_matter(original)
    if split is None:
        return 0
    prefix, body = split
    if "\nlayout: city\n" not in prefix and not prefix.startswith("---\nlayout: city\n"):
        return 0
    prelude, events = split_markdown_events(body)
    if not events:
        return 0
    kept = []
    removed = 0
    for block in events:
        last_day = markdown_last_day(block, today)
        if event_is_past(last_day, today):
            removed += 1
            continue
        kept.append(block)
    if removed == 0:
        return 0
    parts = []
    prelude_text = "".join(prelude).strip("\n")
    if prelude_text:
        parts.append(prelude_text)
    for block in kept:
        parts.append("".join(block).strip("\n"))
    rebuilt = "\n\n".join(parts)
    if rebuilt:
        rebuilt += "\n"
    updated = prefix + ("\n" if rebuilt else "") + rebuilt
    if updated != original and not dry_run:
        path.write_text(updated, encoding="utf-8")
    return removed


def split_yaml_events(text):
    lines = text.splitlines(keepends=True)
    header = []
    blocks = []
    current = None
    started = False
    for line in lines:
        if line.startswith("- "):
            started = True
            if current is not None:
                blocks.append(current)
            current = [line]
            continue
        if current is not None and (line.startswith(" ") or line.strip() == ""):
            current.append(line)
            continue
        if current is not None:
            blocks.append(current)
            current = None
        if not started:
            header.append(line)
        else:
            header.append(line)
    if current is not None:
        blocks.append(current)
    return header, blocks


def yaml_last_day(block):
    loaded = yaml.safe_load("".join(block))
    if isinstance(loaded, list):
        event = loaded[0] if loaded else None
    else:
        event = loaded
    if not isinstance(event, dict):
        return None
    start = as_date(event.get("start"))
    end = as_date(event.get("end"))
    days = [item for item in (start, end) if item]
    if not days:
        return None
    return max(days)


def prune_yaml(path, today, dry_run):
    original = path.read_text(encoding="utf-8")
    header, blocks = split_yaml_events(original)
    if not blocks:
        return 0
    kept = []
    removed = 0
    for block in blocks:
        last_day = yaml_last_day(block)
        if event_is_past(last_day, today):
            removed += 1
            continue
        kept.append(block)
    if removed == 0:
        return 0
    header_text = "".join(header)
    if kept:
        body = "".join("".join(block).rstrip("\n") + "\n" for block in kept)
        updated = header_text + body
    else:
        if header_text and not header_text.endswith("\n"):
            header_text += "\n"
        updated = header_text + "[]\n"
    if updated != original and not dry_run:
        path.write_text(updated, encoding="utf-8")
    return removed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--today", help="Override the Pacific date, YYYY-MM-DD.")
    parser.add_argument("--dry-run", action="store_true", help="Report removals without writing.")
    parser.add_argument("--root", type=Path, help="Repository root. Defaults to the repo.")
    args = parser.parse_args()
    root = args.root.resolve() if args.root else ROOT
    if args.today:
        today = date.fromisoformat(args.today)
    else:
        today = today_in_pacific()

    removed_pages = 0
    removed_rows = 0
    touched = []
    for path in sorted(root.glob("*/*/index.md")):
        count = prune_markdown(path, today, args.dry_run)
        if count:
            removed_pages += count
            touched.append(f"{path.relative_to(root)}: {count} event{'s' if count != 1 else ''}")
    for path in sorted((root / "_data").glob("*_events.yml")):
        count = prune_yaml(path, today, args.dry_run)
        if count:
            removed_rows += count
            touched.append(f"{path.relative_to(root)}: {count} row{'s' if count != 1 else ''}")

    print(f"Pacific date: {today.isoformat()}")
    if not touched:
        print("No past events.")
        return 0
    for line in touched:
        print(line)
    print(f"Removed {removed_pages} page events and {removed_rows} data rows.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"prune-past-events: {exc}", file=sys.stderr)
        sys.exit(1)

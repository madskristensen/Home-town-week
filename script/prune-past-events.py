#!/usr/bin/env python3
"""Delete events whose last day is before today in America/Los_Angeles.

_data/{city}_events.yml is the source. This script deletes a row whose
last day is before today. When that row carries the card text, the text
moves to the next row that shares its card id. It also edits
_data/book_ahead.yml: a row comes off when its last day is before today,
or when sold_out is true. It does not hide anything in the browser. A
city page is not edited. When a data file has no rows left, the layout
says none are listed. Files that lose nothing are left byte for byte.

    python3 script/prune-past-events.py
    python3 script/prune-past-events.py --dry-run
    python3 script/prune-past-events.py --today 2026-10-05 --dry-run
"""

import argparse
import re
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import yaml

ROOT = Path(__file__).resolve().parents[1]
ZONE = ZoneInfo("America/Los_Angeles")
DATE_RE = re.compile(
    r"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2})(?:\s*,\s*(\d{4}))?",
    re.I,
)
YEAR_RE = re.compile(r"\b(20\d{2})\b")
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


def infer_date(month, day, year, today):
    """An explicit year is that year.

    A bare month and day uses this year, unless that day is more than 45
    days behind today. Then it is next year, so a January line written in
    December stays ahead. A day from the last month and a half stays this
    year and can be pruned.
    """
    try:
        day_n = int(day)
        if year:
            return date(int(year), month, day_n)
        this = date(today.year, month, day_n)
    except ValueError:
        return None
    if this < today - timedelta(days=45):
        try:
            return date(today.year + 1, month, day_n)
        except ValueError:
            return None
    return this


def dates_in_when(when_text, today):
    text = when_text or ""
    found = []
    bare = []
    for mon, day, year in DATE_RE.findall(text):
        month = MONTHS.get(mon.lower()[:3])
        if not month:
            continue
        if year:
            parsed = infer_date(month, day, year, today)
            if parsed:
                found.append(parsed)
        else:
            bare.append((month, int(day)))
    years = {item.year for item in found}
    line_years = {int(item) for item in YEAR_RE.findall(text)}
    shared_year = None
    if len(years) == 1:
        shared_year = next(iter(years))
    elif len(line_years) == 1:
        shared_year = next(iter(line_years))
    for month, day in bare:
        parsed = infer_date(month, day, shared_year, today)
        if parsed:
            found.append(parsed)
    return found


def event_is_past(last_day, today):
    return last_day is not None and last_day < today


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


DISPLAY_KEYS = {
    "order",
    "heading_id",
    "title",
    "when",
    "place_line",
    "blurbs",
    "links",
    "photo",
    "description",
    "hub_blurb",
}


def card_id_of(block):
    match = re.search(r'(?m)^  card:\s*"?([^"\n]+)"?\s*$', "".join(block))
    return match.group(1).strip() if match else ""


def split_display(block):
    kept = []
    moving = []
    index = 0
    while index < len(block):
        line = block[index]
        match = re.match(r"^  ([A-Za-z0-9_]+):", line)
        if match and match.group(1) in DISPLAY_KEYS:
            chunk = [line]
            index += 1
            while index < len(block) and not re.match(r"^  [A-Za-z0-9_]+:", block[index]):
                chunk.append(block[index])
                index += 1
            moving.extend(chunk)
        else:
            kept.append(line)
            index += 1
    return kept, moving


def prune_yaml(path, today, dry_run):
    original = path.read_text(encoding="utf-8")
    header, blocks = split_yaml_events(original)
    if not blocks:
        return 0
    kept = []
    removed = 0
    pending = {}
    for block in blocks:
        last_day = yaml_last_day(block)
        if event_is_past(last_day, today):
            removed += 1
            _kept_lines, moving = split_display(block)
            card = card_id_of(block)
            if card and moving:
                pending.setdefault(card, []).extend(moving)
            continue
        card = card_id_of(block)
        if card and card in pending and not any(line.startswith("  when:") for line in block):
            block = block[:]
            while block and block[-1].strip() == "":
                block.pop()
            block.extend(pending.pop(card))
            block.append("")
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


def book_row_drops(block, today):
    loaded = yaml.safe_load("".join(block))
    if isinstance(loaded, list):
        event = loaded[0] if loaded else None
    else:
        event = loaded
    if not isinstance(event, dict):
        return False
    flag = event.get("sold_out")
    if flag is True or str(flag).strip().lower() == "true":
        return True
    return event_is_past(yaml_last_day(block), today)


def prune_book_ahead(path, today, dry_run):
    if not path.is_file():
        return 0
    original = path.read_text(encoding="utf-8")
    header, blocks = split_yaml_events(original)
    if not blocks:
        return 0
    kept = []
    removed = 0
    for block in blocks:
        if book_row_drops(block, today):
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


def self_test():
    today = date(2026, 10, 1)
    # No year in October: next May, not last May.
    assert infer_date(5, 21, None, today) == date(2027, 5, 21)
    assert infer_date(5, 21, 2027, today) == date(2027, 5, 21)
    assert infer_date(9, 30, 2026, today) == date(2026, 9, 30)
    when = "Fri Jan 8 through Sat Jan 16, 2027"
    found = dates_in_when(when, today)
    assert date(2027, 1, 8) in found and date(2027, 1, 16) in found, found
    past = dates_in_when("Wed Sep 30", today)
    assert past == [date(2026, 9, 30)], past
    print("prune-past-events self-test ok")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--today", help="Override the Pacific date, YYYY-MM-DD.")
    parser.add_argument("--dry-run", action="store_true", help="Report removals without writing.")
    parser.add_argument("--self-test", action="store_true", help="Check year handling and exit.")
    parser.add_argument("--root", type=Path, help="Repository root. Defaults to the repo.")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = args.root.resolve() if args.root else ROOT
    if args.today:
        today = date.fromisoformat(args.today)
    else:
        today = today_in_pacific()

    removed_rows = 0
    touched = []
    for path in sorted((root / "_data").glob("*_events.yml")):
        count = prune_yaml(path, today, args.dry_run)
        if count:
            removed_rows += count
            touched.append(f"{path.relative_to(root)}: {count} row{'s' if count != 1 else ''}")
    book_path = root / "_data" / "book_ahead.yml"
    book_count = prune_book_ahead(book_path, today, args.dry_run)
    if book_count:
        removed_rows += book_count
        touched.append(f"{book_path.relative_to(root)}: {book_count} row{'s' if book_count != 1 else ''}")

    print(f"Pacific date: {today.isoformat()}")
    if not touched:
        print("No past events.")
        return 0
    for line in touched:
        print(line)
    print(f"Removed {removed_rows} data rows.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"prune-past-events: {exc}", file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Delete events whose last day is before today in America/Los_Angeles.

City pages and _data/{city}_events.yml are the source. This script edits
those files. It also edits _data/book_ahead.yml: a row comes off when its
last day is before today, or when sold_out is true. It does not hide
anything in the browser. A city page that loses every event keeps its
front matter; the layout then says none are listed. Files that lose
nothing are left byte for byte.

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


def normalize_name(text):
    import unicodedata

    raw = unicodedata.normalize("NFD", text or "")
    raw = "".join(ch for ch in raw if unicodedata.category(ch) != "Mn")
    raw = raw.lower().replace("&", " and ")
    return re.sub(r"[^a-z0-9]+", " ", raw).strip()


def name_score(left, right):
    if not left or not right:
        return 0
    if left == right:
        return 100
    shorter, longer = sorted((left, right), key=len)
    if longer.startswith(shorter + " ") and (
        len(shorter) >= 8 or (" " not in shorter and len(shorter) >= 7)
    ):
        return 90
    return 0


def yaml_rows_for_page(page_path):
    data_path = page_path.parents[1] / "_data" / f"{page_path.parent.name}_events.yml"
    if page_path.parent.name == "worth-the-drive":
        data_path = page_path.parents[1] / "_data" / "worth_the_drive_events.yml"
    if not data_path.is_file():
        return []
    loaded = yaml.safe_load(data_path.read_text(encoding="utf-8"))
    if not isinstance(loaded, list):
        return []
    return [row for row in loaded if isinstance(row, dict)]


def matching_yaml_last_day(heading, rows):
    key = normalize_name(heading)
    days = []
    for row in rows:
        if name_score(key, normalize_name(row.get("name"))) < 90:
            continue
        start = as_date(row.get("start"))
        end = as_date(row.get("end"))
        days.extend(item for item in (start, end) if item)
    if not days:
        return None
    return max(days)


def markdown_last_day(block, today, rows=None):
    text = "".join(block)
    heading = ""
    for line in block:
        match = re.match(r"###[ \t]+(.+?)\s*$", line)
        if match:
            heading = match.group(1).strip()
            break
    when = WHEN_RE.search(text)
    when_text = re.sub(r"\s+", " ", when.group(1)) if when else ""
    # An explicit year in the date line is that year, not a guess.
    if YEAR_RE.search(when_text):
        found = dates_in_when(when_text, today)
        return max(found) if found else None
    yaml_day = matching_yaml_last_day(heading, rows or [])
    if yaml_day:
        return yaml_day
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
    rows = yaml_rows_for_page(path)
    kept = []
    removed = 0
    for block in events:
        last_day = markdown_last_day(block, today, rows)
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

    removed_pages = 0
    removed_rows = 0
    touched = []
    for path in sorted(root.glob("*/index.md")):
        count = prune_markdown(path, today, args.dry_run)
        if count:
            removed_pages += count
            touched.append(f"{path.relative_to(root)}: {count} event{'s' if count != 1 else ''}")
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
    print(f"Removed {removed_pages} page events and {removed_rows} data rows.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"prune-past-events: {exc}", file=sys.stderr)
        sys.exit(1)

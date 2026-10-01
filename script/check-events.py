#!/usr/bin/env python3
"""Check event records before the site builds.

Schema, dates, page/data match, and em dashes fail the build when they are
not already listed in script/event-check-baseline.txt. Adult-only wording
and same-day near-duplicate names are warnings.

    python3 script/check-events.py
    python3 script/check-events.py --write-baseline
"""

import re
import sys
import unicodedata
from datetime import date, datetime
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "_data"
BASELINE = ROOT / "script" / "event-check-baseline.txt"
AGES = {"toddlers", "kids", "teens", "all ages"}
SETTINGS = {"indoor", "outdoor"}
EM_DASH = "\u2014"
ISO_RE = re.compile(
    r"\A\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?)?\Z"
)
DENY_RE = re.compile(
    r"oktoberfest|parent lab|caregiver support|\bsail fitness\b|"
    r"english conversation|talk time|ales for als|"
    r"not a kids|adult concert|adult board game|for adults\.",
    re.I,
)


def normalize(text):
    raw = unicodedata.normalize("NFD", text or "")
    raw = "".join(ch for ch in raw if unicodedata.category(ch) != "Mn")
    raw = raw.lower().replace("&", " and ")
    return re.sub(r"[^a-z0-9]+", " ", raw).strip()


def match_score(left, right):
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


def as_datetime(value):
    if isinstance(value, datetime):
        return value
    text = str(value).strip()
    if "T" not in text and " " not in text[10:]:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def headings(path):
    heads = []
    current = None
    for line in path.read_text(encoding="utf-8").splitlines(keepends=True):
        match = re.match(r"###[ \t]+(.+?)\s*$", line)
        if match:
            if current:
                heads.append(current)
            current = {"text": match.group(1).strip(), "body": ""}
        elif current:
            current["body"] += line
    if current:
        heads.append(current)
    return heads


def load_rows(path):
    loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    if loaded is None:
        return []
    if not isinstance(loaded, list):
        raise SystemExit(f"{path}: expected a list of events")
    return [row for row in loaded if isinstance(row, dict)]


def city_ids():
    found = []
    for path in sorted(ROOT.glob("*/index.md")):
        city = path.parent.name
        if (DATA / f"{city}_events.yml").exists():
            found.append(city)
    return found


def check_row(path, event, errors):
    name = str(event.get("name") or "").strip()
    where = f"{path.name}: {name or '(unnamed)'}"
    for key in ("name", "start", "place", "same_as"):
        if not str(event.get(key) or "").strip():
            errors.append(("required", where, f"missing {key}"))
    start = event.get("start")
    if start not in (None, "") and not ISO_RE.match(str(start).strip()):
        errors.append(("date", where, f"start is not ISO: {start}"))
    end = event.get("end")
    if end not in (None, ""):
        if not ISO_RE.match(str(end).strip()):
            errors.append(("date", where, f"end is not ISO: {end}"))
        else:
            start_d = as_date(start)
            end_d = as_date(end)
            if start_d and end_d and end_d < start_d:
                errors.append(("date", where, "end is before start"))
            start_t = as_datetime(start)
            end_t = as_datetime(end)
            if start_t and end_t and end_t < start_t:
                errors.append(("date", where, "end time is before start"))
    cost = str(event.get("cost") or "").strip()
    if cost and cost.lower() != "free" and not cost.startswith("$"):
        errors.append(("cost", where, f"cost must be Free or $...: {cost}"))
    ages = str(event.get("ages") or "").strip()
    if ages and ages.lower() not in AGES:
        errors.append(("ages", where, f"ages not a label: {ages}"))
    setting = str(event.get("setting") or "").strip()
    if setting and setting.lower() not in SETTINGS:
        errors.append(("setting", where, f"setting not Indoor or Outdoor: {setting}"))
    same = str(event.get("same_as") or "").strip()
    if same and not re.match(r"https?://", same):
        errors.append(("source", where, "source is not an http link"))


def check_pages(errors):
    for city in city_ids():
        page = ROOT / city / "index.md"
        rows = load_rows(DATA / f"{city}_events.yml")
        row_keys = [normalize(row.get("name")) for row in rows]
        page_keys = []
        for heading in headings(page):
            page_keys.append(normalize(heading["text"]))
            if not re.search(r'class="event-when"', heading["body"]):
                errors.append(("page", f"{city}/index.md: {heading['text']}", "missing date line"))
            if not re.search(r"\]\(https?://", heading["body"]):
                errors.append(("page", f"{city}/index.md: {heading['text']}", "missing source link"))
            best = max((match_score(normalize(heading["text"]), key) for key in row_keys), default=0)
            if best < 90:
                errors.append(("match", f"{city}/index.md: {heading['text']}", "no matching data row"))
        for row in rows:
            best = max((match_score(normalize(row.get("name")), key) for key in page_keys), default=0)
            if best < 90:
                errors.append(("orphan", f"{city}: {row.get('name')}", "no matching city-page event"))


def check_emdash(errors):
    paths = list(ROOT.glob("*/index.md"))
    paths += list((ROOT / "_data").glob("*.yml"))
    paths += list((ROOT / "_includes").glob("*.html"))
    paths += list((ROOT / "_layouts").glob("*.html"))
    for path in paths:
        text = path.read_text(encoding="utf-8")
        if EM_DASH in text:
            errors.append(("emdash", str(path.relative_to(ROOT)), "contains an em dash"))


def warn_content():
    warnings = []
    for city in city_ids():
        page = ROOT / city / "index.md"
        for heading in headings(page):
            blob = f"{heading['text']} {heading['body']}"
            if DENY_RE.search(blob):
                warnings.append(f"denylist\t{city}/index.md: {heading['text']}")
        rows = load_rows(DATA / f"{city}_events.yml")
        for index, left in enumerate(rows):
            left_name = normalize(left.get("name"))
            left_start = str(left.get("start") or "")
            left_day = left_start[:10]
            for right in rows[index + 1 :]:
                right_start = str(right.get("start") or "")
                if right_start[:10] != left_day or not left_day:
                    continue
                right_name = normalize(right.get("name"))
                if left_name == right_name and left_start != right_start:
                    continue
                same_instant = left_start[:16] == right_start[:16]
                close = match_score(left_name, right_name) >= 90
                if left_name == right_name and left_start == right_start:
                    warnings.append(
                        f"duplicate\t{city} {left_day}: {left.get('name')}"
                    )
                elif close and same_instant:
                    warnings.append(
                        f"duplicate\t{city} {left_day}: {left.get('name')} ~ {right.get('name')}"
                    )
    return warnings


def error_id(code, where, detail):
    return f"{code}\t{where}\t{detail}"


def load_baseline():
    if not BASELINE.is_file():
        return set()
    found = set()
    for line in BASELINE.read_text(encoding="utf-8").splitlines():
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        found.add(text)
    return found


def main():
    write = "--write-baseline" in sys.argv
    errors = []
    for path in sorted(DATA.glob("*_events.yml")):
        for event in load_rows(path):
            check_row(path, event, errors)
    check_pages(errors)
    check_emdash(errors)
    warnings = warn_content()
    for line in warnings:
        print(f"WARNING\t{line}")
    baseline = load_baseline()
    fresh = []
    known = []
    for code, where, detail in errors:
        item = error_id(code, where, detail)
        if item in baseline:
            known.append(item)
        else:
            fresh.append(item)
    if write:
        lines = ["# Existing event-check errors. New errors fail the build.", ""]
        lines.extend(sorted(error_id(code, where, detail) for code, where, detail in errors))
        BASELINE.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"Wrote {len(errors)} baselined errors.")
        return 0
    for item in fresh:
        print(f"ERROR\t{item}")
    print(
        f"check-events: {len(fresh)} new errors, {len(known)} baselined, {len(warnings)} warnings"
    )
    return 1 if fresh else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"check-events: {exc}", file=sys.stderr)
        sys.exit(1)

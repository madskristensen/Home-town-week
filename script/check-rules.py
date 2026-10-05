#!/usr/bin/env python3
"""Check Python copies of the shared rules against test/fixtures/rules.json.

Name scores match EventCalendar.match_score. A bare month and day rolls
to next year only when it is more than 45 days behind, same as
parse_when_text. Indoor and outdoor labels match EventLabels.
"""

import importlib.util
import json
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "script" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


match_score = load("check_events", "check-events.py").match_score
infer_date = load("prune_past_events", "prune-past-events.py").infer_date
infer_setting = load("apply_venue_settings", "apply-venue-settings.py").infer_setting

RULES = json.loads((ROOT / "test" / "fixtures" / "rules.json").read_text(encoding="utf-8"))
MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}


def year_from_text(text, today):
    parts = text.split()
    month = MONTHS[parts[0].lower()[:3]]
    day = int(parts[1])
    return infer_date(month, day, None, today)


def main():
    for row in RULES["match_score"]:
        score = match_score(row["left"], row["right"])
        if score != row["score"]:
            raise SystemExit(f"match {row['left']!r} / {row['right']!r}: {score} != {row['score']}")
    for row in RULES["year"]:
        today = date.fromisoformat(row["today"])
        parsed = year_from_text(row["text"], today)
        if parsed is None or parsed.isoformat() != row["iso"]:
            raise SystemExit(f"year {row['text']} on {row['today']}: {parsed}")
        if parsed < today - timedelta(days=45):
            raise SystemExit(f"year {row['text']} stayed more than 45 days behind")
    zone = ZoneInfo("America/Los_Angeles")
    for row in RULES["dst"]:
        moment = datetime.fromisoformat(row["utc"]).replace(tzinfo=timezone.utc)
        hours = int(moment.astimezone(zone).utcoffset().total_seconds() // 3600)
        if hours != row["offset"]:
            raise SystemExit(f"dst {row['utc']}: zoneinfo {hours} != {row['offset']}")
    for row in RULES["settings"]:
        label = infer_setting(row["name"], row["place"], row["blurb"], row["tags"], row["same_as"])
        if label != row["label"]:
            raise SystemExit(f"setting {row['name']!r}: {label!r} != {row['label']!r}")
    print(f"shared rules ok ({len(RULES['match_score'])} names, {len(RULES['year'])} years, {len(RULES['dst'])} dst, {len(RULES['settings'])} settings)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

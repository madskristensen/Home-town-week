#!/usr/bin/env python3
"""Fail the build when a city subscription feed is missing or invalid.

Reads _site/calendar/{city}.ics and checks it with the icalendar parser.
Also checks CRLF line endings and the 75-octet fold limit.
"""

import sys
from pathlib import Path

import yaml
from icalendar import Calendar

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "_site" / "calendar"
CITIES = ROOT / "_data" / "cities.yml"
REQUIRED = (
    "BEGIN:VCALENDAR",
    "X-WR-CALNAME:",
    "X-WR-TIMEZONE:America/Los_Angeles",
    "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
    "X-PUBLISHED-TTL:PT6H",
    "BEGIN:VTIMEZONE",
    "TZID:America/Los_Angeles",
    "END:VCALENDAR",
)


def city_ids():
    rows = yaml.safe_load(CITIES.read_text(encoding="utf-8"))
    return [row["id"] for row in rows if isinstance(row, dict) and row.get("id")]


def main():
    if not SITE.is_dir():
        print(f"{SITE}: calendar feeds were not built", file=sys.stderr)
        return 1

    failures = []
    counts = []
    expected = city_ids()
    found = sorted(path.name for path in SITE.glob("*.ics"))
    wanted = sorted(f"{city}.ics" for city in expected)
    if found != wanted:
        failures.append(f"feeds are {found}, expected {wanted}")

    for city in expected:
        path = SITE / f"{city}.ics"
        if not path.is_file():
            continue
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        if b"\n" in raw.replace(b"\r\n", b""):
            failures.append(f"{path.name}: line endings must be CRLF")
        for number, line in enumerate(text.split("\r\n"), 1):
            if len(line.encode("utf-8")) > 75:
                failures.append(f"{path.name}:{number}: line is longer than 75 octets")
                break
        for token in REQUIRED:
            if token not in text:
                failures.append(f"{path.name}: missing {token}")
        if f"X-WR-CALNAME:Eastside Family Calendar:" not in text:
            failures.append(f"{path.name}: calendar name is missing")
        try:
            cal = Calendar.from_ical(raw)
        except Exception as error:
            failures.append(f"{path.name}: {error}")
            continue
        events = 0
        uids = set()
        for component in cal.walk("VEVENT"):
            events += 1
            uid = str(component.get("uid") or "")
            if not uid.endswith("@eastsidecalendar.com"):
                failures.append(f"{path.name}: UID {uid} is not stable")
            if uid in uids:
                failures.append(f"{path.name}: duplicate UID {uid}")
            uids.add(uid)
            if not component.get("dtstamp"):
                failures.append(f"{path.name}: {uid} has no DTSTAMP")
            if not component.get("summary"):
                failures.append(f"{path.name}: {uid} has no SUMMARY")
            start = component.get("dtstart")
            if start is None:
                failures.append(f"{path.name}: {uid} has no DTSTART")
                continue
            params = getattr(start, "params", {})
            value = str(params.get("value") or "")
            tzid = str(params.get("tzid") or "")
            if value == "DATE":
                continue
            if tzid != "America/Los_Angeles":
                failures.append(f"{path.name}: {uid} DTSTART is not America/Los_Angeles or all-day")
        counts.append(f"{city}\t{events}")

    if failures:
        print("Calendar feed check failed:", file=sys.stderr)
        for item in failures:
            print(item, file=sys.stderr)
        return 1

    print("City calendar feeds are valid.")
    for line in counts:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())

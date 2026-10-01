#!/usr/bin/env python3
"""Warn when a stable district calendar link points at a new PDF.

Reads _data/no_school_days.yml. A district is checked when `stable` is set,
or when `source` is a Finalsite resource-manager link. The downloaded file
name is compared with `pdf`. This always exits 0. A warning is the flag.
It does not fail the site build.

    python3 script/check-district-calendars.py
"""

import sys
import urllib.request
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "_data" / "no_school_days.yml"
MARKER = "/fs/resource-manager/"


def stable_url(district):
    stable = str(district.get("stable") or "").strip()
    source = str(district.get("source") or "").strip()
    if stable:
        return stable
    if MARKER in source:
        return source
    return ""


def final_name(url):
    request = urllib.request.Request(url, method="GET", headers={"User-Agent": "EastsideFamilyCalendar/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        final = response.geturl()
        kind = response.headers.get("Content-Type", "")
    name = final.rstrip("/").rsplit("/", 1)[-1]
    return name, kind, final


def main():
    payload = yaml.safe_load(DATA.read_text(encoding="utf-8")) or {}
    warnings = 0
    for district in payload.get("districts") or []:
        if not isinstance(district, dict):
            continue
        label = district.get("id") or district.get("title") or "district"
        url = stable_url(district)
        if not url:
            continue
        expected = str(district.get("pdf") or "").strip()
        try:
            name, kind, final = final_name(url)
        except Exception as error:
            warnings += 1
            print(f"WARNING: {label} calendar link failed: {error}")
            continue
        if "pdf" not in kind.lower() and not name.lower().endswith(".pdf"):
            warnings += 1
            print(f"WARNING: {label} calendar link is not a PDF ({kind}): {final}")
            continue
        if expected and name != expected:
            warnings += 1
            print(f"WARNING: {label} calendar PDF changed from {expected} to {name}")
            continue
        print(f"ok: {label} {name}")
    if warnings:
        print(f"{warnings} district calendar warning(s). The build is not failed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

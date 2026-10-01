#!/usr/bin/env python3
"""Reject events that resolve outside Washington or outside the Eastside.

The 15 cities, Fall City, Covington, and the enclaves in _data/event_area.yml are
allowed on city files. Worth the Drive towns and venues are allowed too.
A price, a street number, and a direction such as Ave NE are not a place
check. An AllEvents city index is not an event address.

Unresolved events are logged and left in place. A failed fetch does not
fail the build when the place already looks local.

    python3 script/check-event-areas.py
    python3 script/check-event-areas.py --remove
    python3 script/check-event-areas.py --dry-run
    python3 script/check-event-areas.py --self-test
"""

import argparse
import json
import re
import sys
import urllib.request
from html import unescape
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "_data"
AREA_PATH = DATA / "event_area.yml"

FOREIGN_WORDS = re.compile(
    r"\b(?:Oregon|Ohio|Nebraska|Quebec|Ontario|British Columbia|Alberta|Canada)\b",
    re.I,
)
# NE is also a street direction ("NE Marymoor Way"). It counts as Nebraska
# only with a ZIP, a following comma, or the end of the address.
COMMA_STATE = re.compile(
    r",\s*(?:OR|OH|ID|CA|QC|BC|ON|AB|NY|TX|CO|MT|AZ|NV|UT|FL)\b",
)
COMMA_NE = re.compile(r",\s*NE(?=\s+\d{5}\b|\s*,|\s*$)")
STATE_ZIP = re.compile(
    r"\b(?:OR|OH|NE|ID|CA|QC|BC|ON|AB|NY|TX|CO|MT|AZ|NV|UT|FL)\s+\d{5}(?:-\d{4})?\b",
)
CA_POSTAL = re.compile(
    r"\b[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z][ -]?\d[ABCEGHJ-NPRSTV-Z]\d\b",
    re.I,
)
WA_ZIP = re.compile(r"\b(?:WA|Washington)\s+(\d{5})\b", re.I)
BARE_ZIP = re.compile(r"\b(9[89]\d{3})(?:-\d{4})?\b")
AGG_EVENT = re.compile(
    r"https?://(?:www\.)?(?:allevents\.in/[^/\s]+/[^/\s]+/\d+|eventbrite\.com/e/)",
    re.I,
)
CITY_INDEX = re.compile(r"https?://(?:www\.)?allevents\.in/[a-z0-9-]+/?$", re.I)
JSON_LD = re.compile(
    r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
    re.I | re.S,
)
TITLE_RE = re.compile(r"<title>(.*?)</title>", re.I | re.S)


def load_area():
    data = yaml.safe_load(AREA_PATH.read_text(encoding="utf-8")) or {}
    drive = data.get("worth_the_drive") or {}
    return {
        "cities": [str(item) for item in data.get("cities") or []],
        "also_local": [str(item) for item in data.get("also_local") or []],
        "towns": [str(item) for item in drive.get("towns") or []],
        "venues": [str(item) for item in drive.get("venues") or []],
        "zips": {str(item) for item in data.get("eastside_zips") or []},
        "washington": data.get("washington_box") or {},
        "service": data.get("service_box") or {},
    }


def phrase_in(hay, phrase):
    text = phrase.strip().lower()
    if not text or not hay:
        return False
    return re.search(rf"(?<![a-z0-9]){re.escape(text)}(?![a-z0-9])", hay.lower()) is not None


def any_phrase(hay, phrases):
    return any(phrase_in(hay, phrase) for phrase in phrases)


def in_box(lat, lon, box):
    if lat is None or lon is None or not box:
        return False
    lat_range = box.get("lat") or []
    lon_range = box.get("lon") or []
    if len(lat_range) != 2 or len(lon_range) != 2:
        return False
    return lat_range[0] <= lat <= lat_range[1] and lon_range[0] <= lon <= lon_range[1]


def as_float(value):
    if value is None or value == "":
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number == 0:
        return None
    return number


def offline_reason(text):
    """A confident out-of-area marker in text the editor wrote or a page title."""
    if not text:
        return None
    if CA_POSTAL.search(text):
        return "Canadian postal code"
    if FOREIGN_WORDS.search(text):
        word = FOREIGN_WORDS.search(text).group(0)
        return f"outside Washington ({word})"
    if STATE_ZIP.search(text):
        return f"outside Washington ({STATE_ZIP.search(text).group(0)})"
    if COMMA_NE.search(text):
        return f"outside Washington ({COMMA_NE.search(text).group(0).strip()})"
    if COMMA_STATE.search(text):
        return f"outside Washington ({COMMA_STATE.search(text).group(0).strip()})"
    return None


def is_us(country):
    value = (country or "").strip().lower()
    return value in {"us", "usa", "united states", "united states of america"}


def is_wa(region):
    value = (region or "").strip().lower().replace(".", "")
    return value in {"wa", "washington", "us-wa"}


def allowed_place(area, text, is_wtd):
    if any_phrase(text, area["cities"]) or any_phrase(text, area["also_local"]):
        return True
    if any_phrase(text, area["venues"]):
        return True
    if is_wtd and any_phrase(text, area["towns"]):
        return True
    return False


def zip_reason(area, text, is_wtd, town):
    found = set(WA_ZIP.findall(text or ""))
    found.update(BARE_ZIP.findall(text or ""))
    for code in sorted(found):
        if code in area["zips"]:
            continue
        if is_wtd and any_phrase(town or "", area["towns"]):
            continue
        if any_phrase(text or "", area["venues"]):
            continue
        return f"ZIP {code} is outside the Eastside"
    return None


def format_address(loc):
    parts = [
        loc.get("name") or "",
        loc.get("street") or "",
        loc.get("locality") or "",
        loc.get("region") or "",
        loc.get("postal") or "",
        loc.get("country") or "",
    ]
    seen = []
    for part in parts:
        text = " ".join(str(part).split())
        if text and text not in seen:
            seen.append(text)
    return ", ".join(seen)


def location_reason(area, loc, is_wtd):
    formatted = format_address(loc)
    title = loc.get("title") or ""
    blob = f"{formatted} {title}"
    marker = offline_reason(blob)
    if marker:
        return marker, formatted or title
    country = loc.get("country") or ""
    if country and not is_us(country):
        return f"country {country}", formatted
    region = loc.get("region") or ""
    if region and not is_wa(region):
        return f"region {region}", formatted
    postal = str(loc.get("postal") or "")
    if CA_POSTAL.search(postal):
        return "Canadian postal code", formatted
    lat = as_float(loc.get("lat"))
    lon = as_float(loc.get("lon"))
    if lat is not None and lon is not None and not in_box(lat, lon, area["washington"]):
        return "coordinates outside Washington", formatted
    place_text = " ".join(
        [
            loc.get("locality") or "",
            loc.get("name") or "",
            loc.get("street") or "",
            title,
        ]
    )
    if allowed_place(area, place_text, is_wtd):
        return None, formatted
    if lat is not None and lon is not None and not in_box(lat, lon, area["service"]):
        return "coordinates outside the Eastside and Worth the Drive", formatted
    locality = (loc.get("locality") or "").strip()
    if locality:
        return f"{locality} is outside the 15 cities and Worth the Drive", formatted
    if title.strip() or formatted.strip():
        # A title with no city and no foreign marker is not a resolved address.
        return None, formatted
    return None, ""


def parse_address(location):
    if isinstance(location, list):
        location = location[0] if location else {}
    if isinstance(location, str):
        return {"street": location}
    if not isinstance(location, dict):
        return {}
    address = location.get("address") or {}
    if isinstance(address, str):
        address = {"streetAddress": address}
    if not isinstance(address, dict):
        address = {}
    geo = location.get("geo") or {}
    if isinstance(geo, list):
        geo = geo[0] if geo else {}
    if not isinstance(geo, dict):
        geo = {}
    return {
        "name": str(location.get("name") or ""),
        "street": str(address.get("streetAddress") or ""),
        "locality": str(address.get("addressLocality") or ""),
        "region": str(address.get("addressRegion") or ""),
        "postal": str(address.get("postalCode") or ""),
        "country": str(address.get("addressCountry") or ""),
        "lat": geo.get("latitude"),
        "lon": geo.get("longitude"),
    }


def iter_nodes(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from iter_nodes(value)
    elif isinstance(node, list):
        for item in node:
            yield from iter_nodes(item)


def event_locations(html):
    found = []
    for match in JSON_LD.finditer(html or ""):
        body = unescape(match.group(1)).strip()
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            continue
        for node in iter_nodes(data):
            kind = node.get("@type")
            kinds = kind if isinstance(kind, list) else [kind]
            if not any(item and "Event" in str(item) for item in kinds):
                continue
            location = node.get("location")
            if location:
                found.append(parse_address(location))
    return found


def page_title(html):
    match = TITLE_RE.search(html or "")
    if not match:
        return ""
    return " ".join(unescape(match.group(1)).split())


class Fetcher:
    def __init__(self):
        self.cache = {}

    def html(self, url):
        if url in self.cache:
            return self.cache[url]
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0 (compatible; EastsideCalendar/1.0)"},
        )
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                text = response.read(900_000).decode("utf-8", "replace")
        except Exception:
            text = None
        self.cache[url] = text
        return text

    def resolve(self, url):
        if not url or CITY_INDEX.match(url) or not AGG_EVENT.search(url):
            return "skip", None
        html = self.html(url)
        if html is None:
            return "failed", None
        title = page_title(html)
        locations = event_locations(html)
        if not locations:
            return "title", {"title": title, "street": title}
        # Prefer a Washington address when the page lists more than one.
        local = [item for item in locations if is_wa(item.get("region") or "")]
        chosen = local[0] if local else locations[0]
        chosen = dict(chosen)
        chosen["title"] = title
        return "ok", chosen


def split_front_matter(text):
    if not text.startswith("---\n"):
        return None
    rest = text[4:]
    fence = rest.find("\n---")
    if fence < 0:
        return None
    close = fence + len("\n---\n")
    if not rest.startswith("\n---\n", fence) and not rest.startswith("\n---\r\n", fence):
        match = re.match(r"\n---[ \t]*$", rest[fence:])
        if not match:
            return None
        close = fence + match.end()
    return text[: 4 + close], text[4 + close :]


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
        header.append(line)
    if current is not None:
        blocks.append(current)
    return header, blocks


def load_yaml_event(block):
    loaded = yaml.safe_load("".join(block))
    if isinstance(loaded, list):
        loaded = loaded[0] if loaded else None
    if not isinstance(loaded, dict):
        return None
    return loaded


def markdown_event(block):
    text = "".join(block)
    heading = ""
    for line in block:
        match = re.match(r"###[ \t]+(.*)", line)
        if match:
            heading = match.group(1).strip()
            break
    place = ""
    place_match = re.search(r'<p class="event-place">(.*?)</p>', text, re.I | re.S)
    if place_match:
        place = re.sub(r"<[^>]+>", "", place_match.group(1))
        place = " ".join(place.split())
    urls = re.findall(r"\((https?://[^)\s]+)\)", text)
    same_as = ""
    for url in urls:
        if AGG_EVENT.search(url):
            same_as = url
            break
    if not same_as and urls:
        same_as = urls[0]
    return {"name": heading, "place": place, "town": "", "blurb": "", "same_as": same_as}


def looks_local(area, event, is_wtd):
    place = str(event.get("place") or "").strip()
    if not place or offline_reason(place):
        return False
    if zip_reason(area, place, is_wtd, str(event.get("town") or "")):
        return False
    return True


def judge(area, event, is_wtd, fetcher):
    name = str(event.get("name") or "").strip()
    place = str(event.get("place") or "")
    town = str(event.get("town") or "")
    blurb = str(event.get("blurb") or "")
    same_as = str(event.get("same_as") or "").strip()
    written = " ".join([name, place, town, blurb])
    marker = offline_reason(written)
    if marker:
        return "reject", marker, written.strip()
    code = zip_reason(area, f"{place} {town}", is_wtd, town)
    if code:
        return "reject", code, place.strip() or town
    if is_wtd and town and not any_phrase(town, area["towns"]) and not any_phrase(town, area["cities"]):
        return "reject", f"town {town} is outside Worth the Drive", town

    if AGG_EVENT.search(same_as) and not CITY_INDEX.match(same_as):
        status, loc = fetcher.resolve(same_as)
        if status == "failed":
            if looks_local(area, event, is_wtd):
                return "unresolved", "fetch failed; place looks local", place.strip()
            return "unresolved", "fetch failed; address not resolved", ""
        if loc:
            reason, formatted = location_reason(area, loc, is_wtd)
            if reason:
                return "reject", reason, formatted
            if formatted or (loc.get("title") or "").strip():
                return "keep", "", formatted or loc.get("title") or ""
        if looks_local(area, event, is_wtd):
            return "unresolved", "address not on the page; place looks local", place.strip()
        return "unresolved", "address not resolved", ""
    return "keep", "", place.strip()


def rel(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def check_yaml(path, area, fetcher, remove, dry_run):
    is_wtd = path.name == "worth_the_drive_events.yml"
    original = path.read_text(encoding="utf-8")
    header, blocks = split_yaml_events(original)
    kept = []
    notes = []
    for block in blocks:
        try:
            event = load_yaml_event(block)
        except yaml.YAMLError:
            event = None
        if not event or not event.get("name"):
            kept.append(block)
            continue
        status, reason, where = judge(area, event, is_wtd, fetcher)
        if status == "reject":
            notes.append(("reject", rel(path), event["name"], reason, where))
            continue
        if status == "unresolved":
            notes.append(("unresolved", rel(path), event["name"], reason, where))
        kept.append(block)
    if remove and len(kept) != len(blocks) and not dry_run:
        updated = "".join(header) + "".join("".join(block) for block in kept)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
    return notes


def check_markdown(path, area, fetcher, remove, dry_run):
    original = path.read_text(encoding="utf-8")
    split = split_front_matter(original)
    if split is None:
        return []
    prefix, body = split
    if "\nlayout: city\n" not in prefix and not prefix.startswith("---\nlayout: city\n"):
        return []
    prelude, events = split_markdown_events(body)
    if not events:
        return []
    kept = []
    notes = []
    for block in events:
        event = markdown_event(block)
        if not event.get("name"):
            kept.append(block)
            continue
        status, reason, where = judge(area, event, False, fetcher)
        if status == "reject":
            notes.append(("reject", rel(path), event["name"], reason, where))
            continue
        if status == "unresolved":
            notes.append(("unresolved", rel(path), event["name"], reason, where))
        kept.append(block)
    if remove and len(kept) != len(events) and not dry_run:
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
        if updated != original:
            path.write_text(updated, encoding="utf-8")
    return notes


def self_test():
    area = load_area()
    assert offline_reason("32610 NE 32nd Street") is None
    assert offline_reason("500 Bellevue Way NE, suite 310") is None
    assert offline_reason("Ave NE") is None
    assert offline_reason(
        "Audubon Bird Loop at Marymoor Park, NE Marymoor Way, Redmond, WA 98052"
    ) is None
    assert offline_reason("Marymoor Park, Redmond") is None
    assert offline_reason("Seattle Miles for Melanoma 5K") is None
    assert offline_reason("Bellevue, NE 68005")
    assert offline_reason("Kirkland, QC, Canada")
    assert offline_reason("General Duffy's Annex, Redmond, OR")
    assert offline_reason("Central Park, Bellevue, Ohio")
    assert offline_reason("H9J 2R6")
    assert offline_reason("3344 Rue Jean-Yves, Kirkland, QC H9J 2R6, Canada")
    assert CITY_INDEX.match("https://allevents.in/redmond")
    assert not CITY_INDEX.match(
        "https://allevents.in/redmond/lakeview-in-redmond/3300030343280622"
    )
    assert AGG_EVENT.search(
        "https://allevents.in/kirkland/mtl-open-powered-by-legend-pickleball-tournoi-de-double-mixte-1003/200030656936923"
    )
    assert in_box(47.659, -122.109, area["service"])
    assert in_box(47.304, -122.532, area["service"])
    assert not in_box(45.441, -73.886, area["washington"])
    assert not in_box(44.272, -121.174, area["washington"])
    assert not in_box(41.14, -95.93, area["washington"])
    assert zip_reason(area, "Bellevue, WA 98004", False, "") is None
    assert zip_reason(area, "14509 SE Newport Way Bellevue, WA 98006", False, "") is None
    assert zip_reason(area, "32610 NE 32nd Street", False, "") is None
    assert zip_reason(area, "Redmond WA 98052", False, "") is None
    assert zip_reason(area, "Auburn, WA 98001", True, "Auburn") is None
    assert zip_reason(area, "Seattle, WA 98103", False, "")
    reason, _where = location_reason(
        area,
        {
            "locality": "Kirkland",
            "region": "QC",
            "country": "CA",
            "street": "3300 Rue Jean-Yves",
            "postal": "H9J 2R6",
            "lat": "45.44117",
            "lon": "-73.88665",
        },
        False,
    )
    assert reason
    reason, _where = location_reason(
        area,
        {
            "name": "Marymoor Park",
            "locality": "Redmond",
            "region": "WA",
            "country": "US",
            "lat": "47.6592",
            "lon": "-122.109",
        },
        False,
    )
    assert reason is None
    reason, _where = location_reason(
        area,
        {
            "name": "Emerald Downs",
            "locality": "Auburn",
            "region": "WA",
            "country": "US",
            "street": "2300 Ron Crockett Drive, Auburn, WA 98001",
        },
        True,
    )
    assert reason is None
    assert allowed_place(area, "Marymoor Park, Redmond", False)
    assert not allowed_place(area, "Showbox, Seattle", False)
    print("event area self-test passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--remove", action="store_true", help="Delete rejected events.")
    parser.add_argument("--dry-run", action="store_true", help="With --remove, do not write.")
    parser.add_argument("--self-test", action="store_true", help="Run offline checks and exit.")
    parser.add_argument("--verbose", action="store_true", help="Also print unresolved rows.")
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    area = load_area()
    fetcher = Fetcher()
    notes = []
    for path in sorted(ROOT.glob("*/index.md")):
        notes.extend(check_markdown(path, area, fetcher, args.remove, args.dry_run))
    for path in sorted(DATA.glob("*_events.yml")):
        notes.extend(check_yaml(path, area, fetcher, args.remove, args.dry_run))

    rejects = [note for note in notes if note[0] == "reject"]
    unresolved = [note for note in notes if note[0] == "unresolved"]
    for kind, path, name, reason, where in rejects:
        action = "would remove" if args.remove and args.dry_run else "removed" if args.remove else "out of area"
        place = f" @ {where}" if where else ""
        print(f"{action}: {path}: {name}: {reason}{place}")
    if args.verbose:
        for kind, path, name, reason, where in unresolved:
            place = f" @ {where}" if where else ""
            print(f"unresolved: {path}: {name}: {reason}{place}")
    print(
        f"Checked event areas. Rejected {len(rejects)}. Unresolved {len(unresolved)}."
    )
    if rejects and not args.remove:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Merge upcoming events from structured city sources into {city}_events.yml.

Reads `_data/cities.yml`. A source is crawled only when `format` is ical,
rss, libcal, bibliocommons, or allevents. The request uses `feed_url` when
that field is set, and `url` otherwise. iCal and RSS are parsed directly.
LibCal, BiblioCommons, and AllEvents use a short adapter and can miss events.

New rows use the same fields as the hand-kept lists: name, start, end,
place, same_as. Existing rows are left in place. A row already stored for
the same name and calendar day is not added again. Events whose last day
is before today in America/Los_Angeles are not added. The daily prune
script still removes expired rows from the city pages.

    python3 script/crawl-structured-events.py --dry-run
    python3 script/crawl-structured-events.py --city redmond
    python3 script/crawl-structured-events.py --self-test
"""

import argparse
import html
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import yaml

ROOT = Path(__file__).resolve().parents[1]
ZONE = ZoneInfo("America/Los_Angeles")
USER_AGENT = "EastsideFamilyCalendar/1.0 (+https://hometownweek.com; structured-feed-crawl)"
STRUCTURED = {"ical", "rss", "libcal", "bibliocommons", "allevents"}
HORIZON_DAYS = 45
MAX_PER_SOURCE = 30
MAX_BC_PAGES = 6
BC_PAGE_SIZE = 50
HEADER = (
    "# Upcoming events for this city, earliest first.\n"
    "# Delete an event after it ends. Do not group these by week.\n"
)
WEEKDAY = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}
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
    "sept": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}
BRANCH_STOPWORDS = {
    "island",
    "city",
    "park",
    "creek",
    "lake",
    "fort",
    "beach",
    "hills",
    "heights",
    "north",
    "south",
    "east",
    "west",
    "the",
    "and",
    "valley",
    "harbor",
    "centre",
    "center",
    "downtown",
    "public",
    "library",
    "county",
}


class FetchError(Exception):
    pass


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


def format_local(value, all_day=False):
    if isinstance(value, date) and not isinstance(value, datetime):
        return value.isoformat()
    if all_day:
        if value.tzinfo is None:
            return value.date().isoformat()
        return value.astimezone(ZONE).date().isoformat()
    moment = value if value.tzinfo else value.replace(tzinfo=ZONE)
    local = moment.astimezone(ZONE)
    stamp = local.strftime("%Y-%m-%dT%H:%M:%S%z")
    return stamp[:-2] + ":" + stamp[-2:]


def clean_text(value, limit):
    text = html.unescape(str(value or ""))
    text = re.sub(r"<[^>]*>", " ", text)
    text = re.sub(r"<[^>]*$", "", text)
    text = text.replace("\u2014", " - ").replace("\u2013", " - ")
    text = re.sub(r"\s+", " ", text).strip(" \t-")
    if len(text) > limit:
        text = text[: limit - 1].rstrip() + "..."
    return text


def yaml_quote(value):
    text = str(value).replace("\\", "\\\\").replace('"', '\\"')
    text = text.replace("\n", " ").replace("\r", " ")
    return f'"{text}"'


def norm_name(value):
    return re.sub(r"\s+", " ", str(value or "")).strip().casefold()


def in_window(start_value, end_value, today, horizon):
    start_day = as_date(start_value)
    if start_day is None:
        return False
    end_day = as_date(end_value) or start_day
    last = max(start_day, end_day)
    return last >= today and start_day <= horizon


def fetch(url, timeout=25, limit=5_000_000):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/calendar, application/rss+xml, application/atom+xml, application/xml, application/json, text/html;q=0.5, */*;q=0.2",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read(limit + 1)
            if len(body) > limit:
                raise FetchError(f"response larger than {limit} bytes")
            ctype = response.headers.get("Content-Type", "")
            return body, ctype, response.geturl()
    except urllib.error.HTTPError as exc:
        raise FetchError(f"HTTP {exc.code} {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise FetchError(f"request failed: {exc.reason}") from exc
    except TimeoutError as exc:
        raise FetchError("timed out") from exc


def local_name(tag):
    if tag is None:
        return ""
    text = str(tag)
    if text.startswith("{"):
        return text.split("}", 1)[1]
    return text


def unfold_ical(text):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = []
    for line in text.split("\n"):
        if lines and line.startswith((" ", "\t")):
            lines[-1] += line[1:]
        else:
            lines.append(line)
    return lines


def unescape_ical(value):
    output = []
    index = 0
    while index < len(value):
        if value[index] == "\\" and index + 1 < len(value):
            nxt = value[index + 1]
            if nxt in ("n", "N"):
                output.append("\n")
            elif nxt == ",":
                output.append(",")
            elif nxt == ";":
                output.append(";")
            elif nxt == "\\":
                output.append("\\")
            else:
                output.append(nxt)
            index += 2
            continue
        output.append(value[index])
        index += 1
    return "".join(output)


def parse_prop(line):
    if ":" not in line:
        return None
    head, value = line.split(":", 1)
    parts = head.split(";")
    params = {}
    for part in parts[1:]:
        if "=" not in part:
            continue
        key, raw = part.split("=", 1)
        params[key.upper()] = raw.strip().strip('"')
    return parts[0].upper(), params, unescape_ical(value)


def parse_ical_dt(value, params):
    raw = value.strip()
    kind = params.get("VALUE", "").upper()
    if kind == "DATE" or re.fullmatch(r"\d{8}", raw):
        return datetime.strptime(raw[:8], "%Y%m%d").date(), True
    zulu = raw.endswith("Z")
    if zulu:
        raw = raw[:-1]
    if "T" not in raw:
        return datetime.strptime(raw[:8], "%Y%m%d").date(), True
    moment = datetime.strptime(raw[:15], "%Y%m%dT%H%M%S")
    if zulu:
        return moment.replace(tzinfo=timezone.utc), False
    tzid = params.get("TZID")
    if tzid:
        try:
            return moment.replace(tzinfo=ZoneInfo(tzid)), False
        except Exception:
            return moment.replace(tzinfo=ZONE), False
    return moment.replace(tzinfo=ZONE), False


def parse_byday(token):
    match = re.fullmatch(r"([+-]?\d+)?([A-Z]{2})", token.strip().upper())
    if not match or match.group(2) not in WEEKDAY:
        return None
    ordinal = int(match.group(1)) if match.group(1) else None
    return ordinal, WEEKDAY[match.group(2)]


def nth_weekday(year, month, weekday, ordinal):
    if ordinal is None or ordinal == 0:
        return None
    if ordinal > 0:
        cursor = date(year, month, 1)
        shift = (weekday - cursor.weekday()) % 7
        cursor = cursor + timedelta(days=shift + 7 * (ordinal - 1))
        if cursor.month != month:
            return None
        return cursor
    if month == 12:
        cursor = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        cursor = date(year, month + 1, 1) - timedelta(days=1)
    shift = (cursor.weekday() - weekday) % 7
    cursor = cursor - timedelta(days=shift + 7 * (-ordinal - 1))
    if cursor.month != month:
        return None
    return cursor


def week_start(day, wkst):
    return day - timedelta(days=(day.weekday() - wkst) % 7)


def rule_dates(start_day, rule, until_day, horizon):
    freq = rule.get("FREQ", "").upper()
    interval = int(rule.get("INTERVAL") or 1)
    if interval < 1:
        interval = 1
    byday = [parse_byday(part) for part in rule.get("BYDAY", "").split(",") if part]
    byday = [item for item in byday if item]
    bymonth = set()
    if rule.get("BYMONTH"):
        for part in rule["BYMONTH"].split(","):
            if part.strip().isdigit():
                bymonth.add(int(part))
    found = []
    seen = set()

    def add(day):
        if day is None or day < start_day or day in seen:
            return
        if until_day and day > until_day:
            return
        if day > horizon + timedelta(days=370):
            return
        seen.add(day)
        found.append(day)

    add(start_day)
    if freq == "DAILY":
        cursor = start_day
        for _ in range(500):
            cursor = cursor + timedelta(days=interval)
            if until_day and cursor > until_day:
                break
            if cursor > horizon:
                break
            add(cursor)
    elif freq == "WEEKLY":
        wkst = WEEKDAY.get((rule.get("WKST") or "SU").upper(), 6)
        days = [item[1] for item in byday if item[0] is None] or [start_day.weekday()]
        base = week_start(start_day, wkst)
        for step in range(0, 520):
            start_of_week = base + timedelta(days=7 * interval * step)
            if start_of_week > horizon + timedelta(days=7):
                break
            for weekday in days:
                cand = start_of_week + timedelta(days=(weekday - wkst) % 7)
                if until_day and cand > until_day:
                    continue
                if cand > horizon:
                    continue
                add(cand)
    elif freq in ("MONTHLY", "YEARLY"):
        months = bymonth or ({start_day.month} if freq == "YEARLY" else set(range(1, 13)))
        year, month = start_day.year, start_day.month
        for _ in range(480):
            if date(year, month, 1) > horizon + timedelta(days=32):
                break
            if month in months or (freq == "MONTHLY" and (not bymonth or month in bymonth)):
                if freq == "YEARLY" and bymonth and month not in bymonth:
                    pass
                else:
                    if byday:
                        for ordinal, weekday in byday:
                            if ordinal is None:
                                if start_day.day <= 28:
                                    try:
                                        cand = date(year, month, start_day.day)
                                    except ValueError:
                                        cand = None
                                    if cand and cand.weekday() == weekday:
                                        add(cand)
                            else:
                                add(nth_weekday(year, month, weekday, ordinal))
                    else:
                        day_num = start_day.day
                        try:
                            add(date(year, month, day_num))
                        except ValueError:
                            pass
            if freq == "YEARLY" and not bymonth and not byday:
                year += interval
                month = start_day.month
                continue
            month += interval if freq == "MONTHLY" else 1
            while month > 12:
                month -= 12
                year += 1
    found.sort()
    return found


def iter_vevents(lines):
    index = 0
    while index < len(lines):
        if lines[index].strip() == "BEGIN:VEVENT":
            chunk = []
            index += 1
            depth = 1
            while index < len(lines):
                line = lines[index]
                if line.startswith("BEGIN:"):
                    depth += 1
                elif line.startswith("END:"):
                    depth -= 1
                    if depth == 0:
                        break
                elif depth == 1:
                    chunk.append(line)
                index += 1
            yield chunk
        index += 1


def event_props(chunk):
    props = []
    for line in chunk:
        parsed = parse_prop(line)
        if parsed:
            props.append(parsed)
    return props


def absolute_url(candidate, base):
    text = (candidate or "").strip()
    if text.startswith("//"):
        text = "https:" + text
    if text.startswith("http://") or text.startswith("https://"):
        return text.split()[0].rstrip(").,>")
    if text.startswith("/") and base:
        parts = urllib.parse.urlsplit(base)
        return urllib.parse.urlunsplit((parts.scheme or "https", parts.netloc, text, "", ""))
    return ""


def first_http(text, base):
    for match in re.findall(r"https?://[^\s<>'\"]+", text or ""):
        url = absolute_url(match, base)
        if url and "iCalendar.aspx" not in url:
            return url
    return ""


def parse_ical(body, source_url, today, horizon, city_name=None):
    text = body.decode("utf-8", "replace")
    if "BEGIN:VCALENDAR" not in text.upper() and "BEGIN:VEVENT" not in text.upper():
        raise FetchError("response was not an iCal calendar")
    events = []
    for chunk in iter_vevents(unfold_ical(text)):
        props = event_props(chunk)
        status = ""
        summary = ""
        location = ""
        description = ""
        url_value = ""
        start = None
        end = None
        start_all_day = False
        end_all_day = False
        rules = []
        exdates = []
        for name, params, value in props:
            if name == "STATUS":
                status = value.strip().upper()
            elif name == "SUMMARY" and not summary:
                summary = value
            elif name == "LOCATION" and not location:
                location = value
            elif name == "DESCRIPTION" and not description:
                description = value
            elif name == "URL" and not url_value:
                url_value = value.strip()
            elif name == "DTSTART" and start is None:
                start, start_all_day = parse_ical_dt(value, params)
            elif name == "DTEND" and end is None:
                end, end_all_day = parse_ical_dt(value, params)
            elif name == "RRULE":
                rule = {}
                for piece in value.split(";"):
                    if "=" in piece:
                        key, raw = piece.split("=", 1)
                        rule[key.upper()] = raw
                if rule.get("FREQ"):
                    rules.append(rule)
            elif name == "EXDATE":
                for piece in value.split(","):
                    try:
                        exdates.append(parse_ical_dt(piece, params)[0])
                    except ValueError:
                        continue
        if status == "CANCELLED" or start is None:
            continue
        name = clean_text(summary, 180)
        if not name:
            continue
        link = first_http(description, source_url) or absolute_url(url_value, source_url)
        if link and "iCalendar.aspx" in link:
            link = ""
        place = clean_text(location, 200)
        occurrences = [(start, end)]
        if rules:
            start_day = start if isinstance(start, date) and not isinstance(start, datetime) else start.astimezone(ZONE).date()
            until_day = None
            count_limit = None
            generated = {start_day}
            for rule in rules:
                until_value = rule.get("UNTIL")
                if until_value:
                    until_parsed, _ = parse_ical_dt(until_value, {"TZID": "UTC"} if until_value.endswith("Z") else {})
                    until_day = until_parsed if isinstance(until_parsed, date) and not isinstance(until_parsed, datetime) else until_parsed.astimezone(ZONE).date()
                if rule.get("COUNT", "").isdigit():
                    count_limit = int(rule["COUNT"])
                for day in rule_dates(start_day, rule, until_day, horizon):
                    generated.add(day)
            ordered = sorted(generated)
            if count_limit:
                ordered = ordered[:count_limit]
            excluded = set()
            for item in exdates:
                if isinstance(item, datetime):
                    excluded.add(item.astimezone(ZONE).date())
                else:
                    excluded.add(item)
            occurrences = []
            for day in ordered:
                if day in excluded:
                    continue
                if start_all_day:
                    occ_start = day
                    occ_end = None
                    if end is not None and end_all_day:
                        span = (end - start).days - 1
                        if span > 0:
                            occ_end = day + timedelta(days=span)
                    occurrences.append((occ_start, occ_end))
                else:
                    local = start.astimezone(ZONE)
                    occ_start = datetime(day.year, day.month, day.day, local.hour, local.minute, local.second, tzinfo=ZONE)
                    occ_end = None
                    if end is not None and not end_all_day:
                        delta = end - start
                        occ_end = occ_start + delta
                    occurrences.append((occ_start, occ_end))
        for occ_start, occ_end in occurrences:
            if start_all_day and isinstance(occ_end, date) and not isinstance(occ_end, datetime):
                pass
            record_end = occ_end
            if start_all_day and end_all_day and isinstance(end, date) and not isinstance(end, datetime) and not rules:
                inclusive = end - timedelta(days=1)
                record_end = inclusive if inclusive > occ_start else None
            start_text = format_local(occ_start, start_all_day)
            end_text = ""
            if record_end is not None:
                end_all = start_all_day or (isinstance(record_end, date) and not isinstance(record_end, datetime))
                end_text = format_local(record_end, end_all and start_all_day)
                if end_text == start_text:
                    end_text = ""
            if not in_window(start_text, end_text, today, horizon):
                continue
            events.append(
                {
                    "name": name,
                    "start": start_text,
                    "end": end_text,
                    "place": place,
                    "same_as": link or source_url,
                }
            )
    return dedupe_cap(apply_city_filter(events, city_name))


def apply_city_filter(events, city_name):
    if not city_name:
        return events
    pattern = city_pattern(city_name)
    matched = []
    for event in events:
        blob = f"{event.get('name', '')} {event.get('place', '')}".casefold().replace("\u2019", "'")
        if pattern.search(blob):
            matched.append(event)
    return matched or events


def dedupe_cap(events):
    kept = []
    seen = set()
    for event in sorted(events, key=lambda item: (item.get("start") or "", item.get("name") or "")):
        key = (norm_name(event.get("name")), event.get("start"))
        if not key[0] or key in seen:
            continue
        seen.add(key)
        kept.append(event)
        if len(kept) >= MAX_PER_SOURCE:
            break
    return kept


def strip_tags(value):
    text = re.sub(r"<br\s*/?>", "\n", value or "", flags=re.I)
    text = re.sub(r"</(p|div|li|h\d|tr)>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    return html.unescape(text)


def field_block(page, field_name):
    match = re.search(rf"field--name-{re.escape(field_name)}", page)
    if not match:
        return ""
    rest = page[match.end():]
    cut = re.search(r"<[^>]*field--name-", rest)
    chunk = rest[: cut.start()] if cut else rest[:1500]
    if ">" in chunk:
        chunk = chunk.split(">", 1)[1]
    text = re.sub(r"\s+", " ", strip_tags(chunk)).strip()
    text = re.sub(
        r"^(Location|Description|Canceled|All Day Event|Event Registration)\s+",
        "",
        text,
        flags=re.I,
    )
    return text.strip()


def parse_clock(value):
    match = re.search(r"(\d{1,2})(?::(\d{2}))?\s*([ap]m)?", value or "", re.I)
    if not match:
        return None
    hour = int(match.group(1))
    minute = int(match.group(2) or 0)
    meridiem = (match.group(3) or "").lower()
    if meridiem == "pm" and hour < 12:
        hour += 12
    if meridiem == "am" and hour == 12:
        hour = 0
    if not meridiem and hour > 23:
        return None
    if hour > 23 or minute > 59:
        return None
    return hour, minute


def parse_time_range(value):
    text = (value or "").replace("a.m.", "am").replace("p.m.", "pm")
    text = text.replace("\u2013", "-").replace("\u2014", "-")
    parts = re.split(r"\s+(?:-|to)\s+", text, maxsplit=1, flags=re.I)
    start = parse_clock(parts[0]) if parts else None
    end = parse_clock(parts[1]) if len(parts) > 1 else None
    return start, end


def parse_human_date(value, today):
    text = value or ""
    match = re.search(
        r"\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,)?\s+(\d{4})\b",
        text,
    )
    if not match:
        match = re.search(
            r"\b(\d{1,2})\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})\b",
            text,
        )
        if match:
            month = MONTHS.get(match.group(2).lower()[:4], MONTHS.get(match.group(2).lower()[:3]))
            day = int(match.group(1))
            year = int(match.group(3))
        else:
            loose = re.search(r"\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b", text)
            if not loose:
                return None
            month = MONTHS.get(loose.group(1).lower()[:4], MONTHS.get(loose.group(1).lower()[:3]))
            if not month:
                return None
            day = int(loose.group(2))
            year = today.year
            try:
                guessed = date(year, month, day)
            except ValueError:
                return None
            if guessed < today - timedelta(days=14):
                try:
                    guessed = date(year + 1, month, day)
                except ValueError:
                    return None
            return guessed
    else:
        month = MONTHS.get(match.group(1).lower()[:4], MONTHS.get(match.group(1).lower()[:3]))
        day = int(match.group(2))
        year = int(match.group(3))
    if not month:
        return None
    try:
        return date(year, month, day)
    except ValueError:
        return None


def combine(day, clock):
    if clock is None:
        return format_local(day, True)
    return format_local(datetime(day.year, day.month, day.day, clock[0], clock[1], tzinfo=ZONE))


def child_text(node, name):
    for element in node.iter():
        if local_name(element.tag) != name:
            continue
        if element.text and element.text.strip():
            return element.text.strip()
        href = element.attrib.get("href")
        if href:
            return href.strip()
    return ""


def month_number(token):
    key = token.lower().rstrip(".")
    return MONTHS.get(key[:4], MONTHS.get(key[:3]))


def leading_span(plain, today):
    """Read a date or date range from the start of an event blurb.

    Squarespace and similar calendars put 'October 2 - 25, 2026' or
    'October 10, 2026 @ 3pm' in the first line. A date buried later in
    a news story is ignored.
    """
    text = re.sub(r"\s+", " ", plain or "").strip()
    if not text:
        return None
    head = text[:160]
    month = r"([A-Za-z]{3,9})\.?"
    ranged = re.match(
        rf"{month}\s+(\d{{1,2}})(?:st|nd|rd|th)?\s*-\s*(?:{month}\s+)?(\d{{1,2}})(?:st|nd|rd|th)?(?:,?\s+(\d{{4}}))?",
        head,
        re.I,
    )
    if ranged:
        start_month = month_number(ranged.group(1))
        end_month = month_number(ranged.group(3)) if ranged.group(3) else start_month
        if start_month and end_month:
            start_day = int(ranged.group(2))
            end_day = int(ranged.group(4))
            year = int(ranged.group(5)) if ranged.group(5) else None
            start_year = year or today.year
            end_year = start_year
            if end_month < start_month:
                end_year += 1
            try:
                start = date(start_year, start_month, start_day)
                end = date(end_year, end_month, end_day)
            except (ValueError, TypeError):
                return None
            if end < start:
                return None
            return start.isoformat(), end.isoformat() if end != start else ""
    single = re.match(
        rf"{month}\s+(\d{{1,2}})(?:st|nd|rd|th)?,\s+(\d{{4}})(?:\s*@\s*(\d{{1,2}}(?::\d{{2}})?\s*[ap]m))?",
        head,
        re.I,
    )
    if not single:
        return None
    start_month = month_number(single.group(1))
    if not start_month:
        return None
    try:
        day = date(int(single.group(3)), start_month, int(single.group(2)))
    except ValueError:
        return None
    clock = parse_clock(single.group(4)) if single.group(4) else None
    return combine(day, clock), ""


def parse_rss_item(item, source_url, today, horizon, prose_dates):
    title = clean_text(strip_tags(child_text(item, "title")), 180)
    if not title:
        return []
    link = absolute_url(child_text(item, "link"), source_url) or source_url
    description_raw = ""
    for element in item.iter():
        if local_name(element.tag) == "description" and element.text:
            description_raw = element.text
            break
    description = html.unescape(description_raw or "")
    canceled = field_block(description, "field-canceled").casefold()
    if canceled == "on" or canceled.endswith(" on"):
        return []
    place = ""
    start_text = ""
    end_text = ""
    lib_date = child_text(item, "date")
    lib_start = child_text(item, "start")
    lib_end = child_text(item, "end")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", lib_date or ""):
        day = date.fromisoformat(lib_date)
        all_day = lib_start in ("", "00:00:00") and lib_end in ("", "23:59:59", "00:00:00")
        if all_day:
            start_text = day.isoformat()
        else:
            start_clock = parse_clock(lib_start)
            end_clock = parse_clock(lib_end)
            start_text = combine(day, start_clock)
            if end_clock and not (end_clock == (23, 59) or end_clock == (0, 0)):
                end_text = combine(day, end_clock)
        place = clean_text(strip_tags(child_text(item, "location")), 200)
    if not start_text:
        for element in item.iter():
            lname = local_name(element.tag).lower().replace("_", "")
            if lname in ("startdate", "dtstart", "eventstart", "starttime") and element.text:
                parsed = parse_machine_datetime(element.text.strip(), today)
                if parsed:
                    start_text = parsed
            if lname in ("enddate", "dtend", "eventend", "endtime") and element.text:
                parsed = parse_machine_datetime(element.text.strip(), today)
                if parsed:
                    end_text = parsed
    if not start_text:
        date_text = field_block(description, "field-event-dates")
        time_text = field_block(description, "field-event-time")
        day = parse_human_date(date_text, today) if date_text else None
        if day:
            start_clock, end_clock = parse_time_range(time_text)
            start_text = combine(day, start_clock)
            if end_clock:
                end_text = combine(day, end_clock)
            place = clean_text(field_block(description, "field-address") or field_block(description, "field-location"), 200)
    if not start_text:
        span = leading_span(strip_tags(description), today)
        if span:
            start_text, end_text = span
    records = []
    if start_text:
        records.append((start_text, end_text, place))
    elif prose_dates:
        plain = strip_tags(description)
        dated = re.findall(
            r"Date:\s*([A-Za-z0-9, ]+?)(?:\s+-\s+|\s+)(\d{1,2}:\d{2}\s*[AP]M)?",
            plain,
            re.I,
        )
        if dated:
            for date_part, time_part in dated[:4]:
                day = parse_human_date(date_part, today)
                if not day:
                    continue
                clock = parse_clock(time_part) if time_part else None
                records.append((combine(day, clock), "", ""))
        else:
            day = parse_human_date(plain, today)
            if day:
                range_match = re.search(
                    r"(\d{1,2}(?::\d{2})?\s*[ap]m)\s*[-to]+\s*(\d{1,2}(?::\d{2})?\s*[ap]m)",
                    plain,
                    re.I,
                )
                start_clock, end_clock = parse_time_range(range_match.group(0)) if range_match else (None, None)
                end_value = combine(day, end_clock) if end_clock else ""
                records.append((combine(day, start_clock), end_value, ""))
        venue = re.search(r"Venue:\s*(.+)", plain)
        if venue:
            place = clean_text(venue.group(1), 200)
    kept = []
    for start_value, end_value, item_place in records:
        if not in_window(start_value, end_value, today, horizon):
            continue
        kept.append(
            {
                "name": title,
                "start": start_value,
                "end": end_value,
                "place": item_place or place,
                "same_as": link,
            }
        )
    return kept


def parse_machine_datetime(value, today):
    text = value.strip().replace("Z", "+00:00")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        return text
    try:
        if re.fullmatch(r"\d{8}T\d{6}Z?", value.strip()):
            parsed, all_day = parse_ical_dt(value.strip(), {})
            return format_local(parsed, all_day)
        moment = datetime.fromisoformat(text)
    except ValueError:
        day = parse_human_date(value, today)
        clock = parse_clock(value)
        if day:
            return combine(day, clock)
        return ""
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=ZONE)
    return format_local(moment)


def parse_rss(body, source_url, today, horizon, prose_dates=False, city_name=None):
    try:
        root = ET.fromstring(body)
    except ET.ParseError as exc:
        raise FetchError(f"XML parse failed: {exc}") from exc
    items = [node for node in root.iter() if local_name(node.tag) in ("item", "entry")]
    if not items and b"<rss" not in body[:500].lower() and b"<feed" not in body[:500].lower():
        raise FetchError("response was not an RSS or Atom feed")
    events = []
    for item in items:
        events.extend(parse_rss_item(item, source_url, today, horizon, prose_dates))
    return dedupe_cap(apply_city_filter(events, city_name))


def unique(values):
    seen = set()
    ordered = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def libcal_candidates(page_url, page_html):
    parsed = urllib.parse.urlsplit(page_url)
    host = parsed.netloc
    cids = re.findall(r"[?&]cid=(\d+)", page_url + " " + (page_html or ""))
    urls = []
    for cid in unique(cids):
        urls.append(f"https://{host}/ical_subscribe.php?cid={cid}")
    for href in re.findall(r'href=["\']([^"\']+)["\']', page_html or "", re.I):
        lowered = href.lower()
        if "ical" in lowered or "rss.php" in lowered or lowered.endswith(".ics"):
            urls.append(urllib.parse.urljoin(page_url, href))
    for cid in unique(cids):
        urls.append(f"https://{host}/rss.php?cid={cid}")
    return unique(urls)


def looks_like_ical(body):
    head = body[:200].lstrip().upper()
    return head.startswith(b"BEGIN:VCALENDAR") or b"BEGIN:VCALENDAR" in body[:400].upper()


def looks_like_feed(body, ctype):
    head = body[:400].lower()
    return b"<rss" in head or b"<feed" in head or "xml" in ctype.lower() or "rss" in ctype.lower()


def parse_libcal(fetch_url, today, horizon, city_name=None):
    body, ctype, final = fetch(fetch_url)
    if looks_like_ical(body) or "text/calendar" in ctype.lower():
        return parse_ical(body, final, today, horizon, city_name)
    if looks_like_feed(body, ctype):
        return parse_rss(body, final, today, horizon, prose_dates=False, city_name=city_name)
    page = body.decode("utf-8", "replace")
    errors = []
    for candidate in libcal_candidates(final, page):
        try:
            nested, nested_type, nested_final = fetch(candidate)
        except FetchError as exc:
            errors.append(f"{candidate} ({exc})")
            continue
        try:
            if looks_like_ical(nested) or "calendar" in nested_type.lower():
                return parse_ical(nested, nested_final, today, horizon, city_name)
            if looks_like_feed(nested, nested_type):
                return parse_rss(nested, nested_final, today, horizon, prose_dates=False, city_name=city_name)
        except FetchError as exc:
            errors.append(f"{candidate} ({exc})")
    detail = "; ".join(errors[:3]) if errors else "no iCal or RSS link on the calendar page"
    raise FetchError(f"LibCal feed not found: {detail}")


def city_pattern(city_name):
    name = city_name.casefold().replace("\u2019", "'").replace("`", "'")
    phrase = re.escape(name).replace(r"\ ", r"\s+")
    return re.compile(rf"(?<![a-z0-9]){phrase}(?![a-z0-9])")


def matching_branches(locations, city_name):
    city = city_name.casefold()
    matched = []
    for loc_id, loc in locations.items():
        name = str(loc.get("name") or "").casefold()
        if not name:
            continue
        if city in name or name == city or (len(name) >= 5 and name in city):
            matched.append(str(loc_id))
    if matched:
        return unique(matched)
    for token in re.findall(r"[a-z0-9']+", city):
        if len(token) < 6 or token in BRANCH_STOPWORDS:
            continue
        for loc_id, loc in locations.items():
            if token in str(loc.get("name") or "").casefold():
                matched.append(str(loc_id))
    return unique(matched)


def parse_bibliocommons(source_url, city_name, today, horizon, cache):
    host = urllib.parse.urlsplit(source_url).netloc
    slug = host.split(".")[0]
    if not slug:
        raise FetchError("BiblioCommons host had no library slug")
    if slug not in cache:
        loc_body, _, _ = fetch(
            f"https://gateway.bibliocommons.com/v2/libraries/{urllib.parse.quote(slug)}/locations?limit=80"
        )
        try:
            loc_payload = json.loads(loc_body)
        except json.JSONDecodeError as exc:
            raise FetchError(f"BiblioCommons locations were not JSON: {exc}") from exc
        locations = (loc_payload.get("entities") or {}).get("locations") or {}
        events = []
        merged_locations = dict(locations)
        for page in range(1, MAX_BC_PAGES + 1):
            event_url = (
                f"https://gateway.bibliocommons.com/v2/libraries/{urllib.parse.quote(slug)}"
                f"/events?limit={BC_PAGE_SIZE}&page={page}"
            )
            event_body, _, _ = fetch(event_url)
            try:
                payload = json.loads(event_body)
            except json.JSONDecodeError as exc:
                raise FetchError(f"BiblioCommons events were not JSON: {exc}") from exc
            merged_locations.update((payload.get("entities") or {}).get("locations") or {})
            entities = (payload.get("entities") or {}).get("events") or {}
            events.extend(entities.values())
            pages = ((payload.get("events") or {}).get("pagination") or {}).get("pages") or 1
            if page >= pages:
                break
        cache[slug] = (merged_locations, events)
    locations, events = cache[slug]
    branch_ids = set(matching_branches(locations, city_name))
    if not branch_ids:
        raise FetchError(f"no BiblioCommons branch name matched {city_name}")
    names = {str(loc_id): str(loc.get("name") or "") for loc_id, loc in locations.items()}
    use_v2 = "/v2/" in source_url
    found = []
    for event in events:
        definition = event.get("definition") or {}
        if definition.get("isCancelled"):
            continue
        branch = str(definition.get("branchLocationId") or "")
        if branch not in branch_ids:
            continue
        title = clean_text(definition.get("title"), 180)
        start_raw = definition.get("start") or ""
        if not title or not start_raw:
            continue
        start_text = parse_machine_datetime(start_raw, today)
        end_text = parse_machine_datetime(definition.get("end") or "", today) if definition.get("end") else ""
        if not in_window(start_text, end_text, today, horizon):
            continue
        details = clean_text(definition.get("locationDetails") or "", 80)
        branch_name = names.get(branch, "")
        place = clean_text(", ".join(part for part in (branch_name, details) if part), 200)
        event_id = event.get("id") or ""
        path = f"/v2/events/{event_id}" if use_v2 else f"/events/{event_id}"
        same = f"https://{host}{path}" if event_id else source_url
        found.append(
            {
                "name": title,
                "start": start_text,
                "end": end_text,
                "place": place,
                "same_as": same,
            }
        )
    return dedupe_cap(found)


def allevents_rss_url(source_url):
    parts = urllib.parse.urlsplit(source_url)
    path = parts.path.rstrip("/")
    if path.lower().endswith("/rss"):
        return source_url
    return urllib.parse.urlunsplit((parts.scheme or "https", parts.netloc, path + "/RSS", "", ""))


def parse_allevents(source_url, city_name, today, horizon):
    feed_url = allevents_rss_url(source_url)
    body, _, final = fetch(feed_url)
    events = parse_rss(body, final, today, horizon, prose_dates=True)
    pattern = city_pattern(city_name)
    # The RSS item title and description were flattened into name/place.
    # Filter with a second pass over the raw feed so a nearby-city concert drops.
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        return events
    allowed_links = set()
    for item in root.iter():
        if local_name(item.tag) not in ("item", "entry"):
            continue
        blob = " ".join(
            strip_tags(element.text or "")
            for element in item.iter()
            if element.text and local_name(element.tag) in ("title", "description", "summary")
        )
        if pattern.search(blob.casefold().replace("\u2019", "'")):
            link = absolute_url(child_text(item, "link"), final)
            if link:
                allowed_links.add(link)
    if not allowed_links:
        return []
    return [event for event in events if event.get("same_as") in allowed_links]


def crawl_source(source, city_name, today, horizon, cache):
    fmt = (source.get("format") or "").strip()
    target = (source.get("feed_url") or source.get("url") or "").strip()
    if not target:
        raise FetchError("source has no url")
    if fmt == "ical":
        body, ctype, final = fetch(target)
        if not looks_like_ical(body) and "calendar" not in ctype.lower() and b"BEGIN:VEVENT" not in body[:2000].upper():
            raise FetchError(f"response was not an iCal calendar ({ctype or 'no content type'})")
        return parse_ical(body, source.get("url") or final, today, horizon)
    if fmt == "rss":
        body, _, final = fetch(target)
        return parse_rss(body, source.get("url") or final, today, horizon, prose_dates=False)
    if fmt == "libcal":
        return parse_libcal(target, today, horizon, city_name)
    if fmt == "bibliocommons":
        return parse_bibliocommons(source.get("url") or target, city_name, today, horizon, cache)
    if fmt == "allevents":
        return parse_allevents(source.get("url") or target, city_name, today, horizon)
    raise FetchError(f"unsupported format {fmt}")


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


def render_event(event):
    lines = [f"- name: {yaml_quote(event['name'])}", f"  start: {yaml_quote(event['start'])}"]
    if event.get("end"):
        lines.append(f"  end: {yaml_quote(event['end'])}")
    if event.get("place"):
        lines.append(f"  place: {yaml_quote(event['place'])}")
    if event.get("same_as"):
        lines.append(f"  same_as: {yaml_quote(event['same_as'])}")
    return "\n".join(lines) + "\n"


def merge_city_events(path, additions, dry_run):
    original = path.read_text(encoding="utf-8") if path.exists() else HEADER
    header, blocks = split_yaml_events(original)
    existing = []
    existing_days = set()
    for block in blocks:
        loaded = yaml.safe_load("".join(block))
        event = loaded[0] if isinstance(loaded, list) else loaded
        if not isinstance(event, dict):
            existing.append(({"start": "9999", "name": ""}, "".join(block).rstrip() + "\n"))
            continue
        existing.append((event, "".join(block).rstrip() + "\n"))
        existing_days.add((norm_name(event.get("name")), str(event.get("start") or "")[:10]))
    fresh = []
    for event in additions:
        key = (norm_name(event.get("name")), str(event.get("start") or "")[:10])
        if key in existing_days:
            continue
        existing_days.add(key)
        fresh.append(event)
    if not fresh:
        return 0
    combined = [(event, raw, False) for event, raw in existing]
    combined.extend((event, render_event(event), True) for event in fresh)
    combined.sort(key=lambda item: (str(item[0].get("start") or "9999"), str(item[0].get("name") or "")))
    header_text = "".join(header)
    if not header_text.strip():
        header_text = HEADER
    if not header_text.endswith("\n"):
        header_text += "\n"
    updated = header_text + "".join(raw for _, raw, _ in combined)
    if updated != original and not dry_run:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(updated, encoding="utf-8")
    return len(fresh)


def load_cities(root):
    path = root / "_data" / "cities.yml"
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise FetchError("cities.yml did not contain a city list")
    return data


def crawl(root, today, city_ids, dry_run):
    horizon = today + timedelta(days=HORIZON_DAYS)
    cities = load_cities(root)
    failures = []
    notes = []
    added = []
    added_rows = 0
    attempted = 0
    cache = {}
    for city in cities:
        city_id = str(city.get("id") or "")
        if city_ids and city_id not in city_ids:
            continue
        city_name = str(city.get("name") or city_id)
        collected = []
        for source in city.get("sources") or []:
            fmt = str(source.get("format") or "").strip()
            if fmt not in STRUCTURED:
                continue
            attempted += 1
            target = source.get("feed_url") or source.get("url")
            label = f"{city_id} | {source.get('name')} | {fmt} | {target}"
            try:
                events = crawl_source(source, city_name, today, horizon, cache)
            except Exception as exc:
                message = str(exc).replace("\n", " ")
                failures.append((city_id, source.get("name"), target, message))
                print(f"FAIL {label} | {message}")
                print(f"::warning title=feed crawl::{city_id} {source.get('name')} {target} {message}")
                continue
            print(f"OK   {label} | {len(events)} events")
            if fmt == "bibliocommons":
                notes.append(
                    f"{city_id} bibliocommons is a partial scan of the first {MAX_BC_PAGES * BC_PAGE_SIZE} gateway rows"
                )
            if not events:
                notes.append(f"{label} | 0 dated events kept")
            collected.extend(events)
        if not collected:
            continue
        path = root / "_data" / f"{city_id}_events.yml"
        count = merge_city_events(path, collected, dry_run)
        if count:
            added_rows += count
            added.append(f"{path.relative_to(root)}: {count} new")
            print(f"ADD  {city_id}: {count} new rows")
    print(f"Pacific date: {today.isoformat()}")
    print(f"Window through: {horizon.isoformat()}")
    print(f"Structured sources tried: {attempted}")
    print(f"Failed sources: {len(failures)}")
    if notes:
        print("Notes:")
        for line in notes:
            print(f"- {line}")
    if failures:
        print("Failures:")
        for city_id, name, url, message in failures:
            print(f"- {city_id} | {name} | {url} | {message}")
    if added:
        verb = "Would add" if dry_run else "Added"
        print(f"{verb} {added_rows} rows.")
        for line in added:
            print(line)
    else:
        print("No event file changes.")
    if dry_run:
        print("Dry run. No files written.")
    if attempted and len(failures) == attempted:
        return 1
    return 0


def self_test():
    today = date(2026, 9, 28)
    horizon = today + timedelta(days=HORIZON_DAYS)
    ical = """BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Story Hour
DTSTART;TZID=America/Los_Angeles:20261001T183000
DTEND;TZID=America/Los_Angeles:20261001T200000
DESCRIPTION: https://example.com/events/story
LOCATION: - Eagle Harbor Books
END:VEVENT
BEGIN:VEVENT
SUMMARY:Cancelled Show
STATUS:CANCELLED
DTSTART;TZID=America/Los_Angeles:20261002T180000
DTEND;TZID=America/Los_Angeles:20261002T190000
END:VEVENT
BEGIN:VEVENT
SUMMARY:Mercer Island Farmers Market
DTSTART;TZID=America/Los_Angeles:20260830T100000
DTEND;TZID=America/Los_Angeles:20260830T120000
RRULE:FREQ=WEEKLY;UNTIL=20261012T135959Z;INTERVAL=1;BYDAY=SU
LOCATION:Mercer Island
END:VEVENT
END:VCALENDAR
""".replace("\n", "\r\n")
    events = parse_ical(ical.encode(), "https://example.com/calendar", today, horizon)
    by_name = {}
    for event in events:
        by_name.setdefault(event["name"], []).append(event["start"])
    assert by_name["Story Hour"] == ["2026-10-01T18:30:00-07:00"], by_name
    assert events[0]["end"] == "2026-10-01T20:00:00-07:00"
    assert events[0]["place"] == "Eagle Harbor Books"
    assert events[0]["same_as"] == "https://example.com/events/story"
    assert "Cancelled Show" not in by_name
    assert by_name["Mercer Island Farmers Market"] == [
        "2026-10-04T10:00:00-07:00",
        "2026-10-11T10:00:00-07:00",
    ], by_name

    rss = b"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"><channel>
<item>
  <title>Beginner Workout</title>
  <link>https://bellevuewa.gov/events/workout</link>
  <description><![CDATA[
    <div class="field field--name-field-event-dates field--type-daterange field__item">September 30 2026</div>
    <div class="field field--name-field-event-time field--type-time-range field__item">3:00 PM - 4:00 PM</div>
    <div class="field field--name-field-address field--type-address field--label-inline">
      <div class="field__label">Location</div>
      <div class="field__item">South Bellevue Community Center, 14509 SE Newport Way</div>
    </div>
    <div class="field field--name-field-canceled field--type-boolean"><div class="field__item">Off</div></div>
  ]]></description>
</item>
<item>
  <title>No Date Here</title>
  <link>https://example.com/news</link>
  <description>A blog post.</description>
</item>
</channel></rss>
"""
    rss_events = parse_rss(rss, "https://bellevuewa.gov/calendar", today, horizon)
    assert len(rss_events) == 1, rss_events
    assert rss_events[0]["start"] == "2026-09-30T15:00:00-07:00"
    assert rss_events[0]["end"] == "2026-09-30T16:00:00-07:00"
    assert rss_events[0]["place"].startswith("South Bellevue"), rss_events[0]["place"]
    assert "field--" not in rss_events[0]["place"]

    span = leading_span("October 2 - 25, 2026 Based on a memoir.", today)
    assert span == ("2026-10-02", "2026-10-25"), span
    timed = leading_span("October 10, 2026 @ 3pm Now in its third season.", today)
    assert timed == ("2026-10-10T15:00:00-07:00", ""), timed
    assert leading_span("The market opens October 2, 2026.", today) is None

    libcal = b"""<?xml version="1.0"?>
<rss xmlns:libcal="https://libcal.com/rss_xmlns.php"><channel><item>
<title>Whatcomics 2026</title>
<link>https://wcls.libcal.com/event/16907830</link>
<libcal:date>2026-10-31</libcal:date>
<libcal:start>00:00:00</libcal:start>
<libcal:end>23:59:59</libcal:end>
</item></channel></rss>
"""
    lib_events = parse_rss(libcal, "https://wcls.libcal.com/", today, horizon)
    assert lib_events[0]["start"] == "2026-10-31", lib_events
    assert lib_events[0]["same_as"].endswith("/16907830")

    assert allevents_rss_url("https://allevents.in/bellevue") == "https://allevents.in/bellevue/RSS"
    assert city_pattern("Bellevue").search("at the bellevue library")
    assert not city_pattern("Bellevue").search("vancouver, bc")

    from tempfile import TemporaryDirectory

    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        data = root / "_data"
        data.mkdir()
        existing = data / "demo_events.yml"
        existing.write_text(
            HEADER
            + '- name: "Story Hour"\n'
            + '  start: "2026-10-01T18:30:00-07:00"\n'
            + '  place: "Library"\n'
            + '  same_as: "https://example.com/old"\n',
            encoding="utf-8",
        )
        added = merge_city_events(
            existing,
            [
                {
                    "name": "Story Hour",
                    "start": "2026-10-01T18:30:00-07:00",
                    "end": "",
                    "place": "Other",
                    "same_as": "https://example.com/new",
                },
                {
                    "name": "Farmers Market",
                    "start": "2026-10-04T10:00:00-07:00",
                    "end": "2026-10-04T12:00:00-07:00",
                    "place": "Town Square",
                    "same_as": "https://example.com/market",
                },
            ],
            dry_run=False,
        )
        assert added == 1, added
        text = existing.read_text(encoding="utf-8")
        assert "https://example.com/old" in text
        assert "Farmers Market" in text
        assert text.index("Story Hour") < text.index("Farmers Market")
    print("self-test ok")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--city", action="append", help="Limit to this city id. Repeatable.")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and report without writing.")
    parser.add_argument("--today", help="Override the Pacific date, YYYY-MM-DD.")
    parser.add_argument("--root", type=Path, help="Repository root. Defaults to the repo.")
    parser.add_argument("--self-test", action="store_true", help="Run parser checks and exit.")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = args.root.resolve() if args.root else ROOT
    if args.today:
        today = date.fromisoformat(args.today)
    else:
        today = today_in_pacific()
    city_ids = set(args.city or [])
    return crawl(root, today, city_ids, args.dry_run)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"crawl-structured-events: {exc}", file=sys.stderr)
        sys.exit(1)

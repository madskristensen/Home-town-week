#!/usr/bin/env python3
"""Fill a blank setting from the venue, and other labels the page states.

Theaters, libraries, performance centers, museums, and community centers
are Indoor. Parks, farms, trails, beaches, and streets are Outdoor. The
longest phrase wins. A hike, stroll, parade, or planting stays Outdoor.

Free, Toddlers, Sign-up needed, Drop-off, and Sensory-friendly are written
only when the city page or the event blurb says so. A price and All ages
are not added. An existing label is left as it is.

    python3 script/apply-venue-settings.py
    python3 script/apply-venue-settings.py --dry-run
"""

import argparse
import html
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "_data"
RULES = yaml.safe_load((DATA / "venue_settings.yml").read_text()) or {}
INDOOR = [item.lower() for item in RULES.get("indoor") or []]
OUTDOOR = [item.lower() for item in RULES.get("outdoor") or []]
ACTIVITY = [item.lower() for item in RULES.get("outdoor_activity") or []]

TODDLER_RE = re.compile(
    r"ages?\s*(0|1|2|3|4)\s*(to|–|-)\s*5\b|"
    r"ages?\s*(0|1|2|3)\s*(to|–|-|and)\s*(2|3|4)\b|"
    r"ages?\s*1\s+to\s+3\b|"
    r"newborns?\s+to\s+(?:5|12\s+months|18\s+months)|"
    r"under\s+5|"
    r"\bpreschool\b|"
    r"\bfor babies\b|\bbabies and toddlers\b|\bbaby and toddler\b|\btoddlers?\b|"
    r"\b18\s+months\b|"
    r"lap[\s-]?sit|"
    r"baby story\s*time|"
    r"little children|"
    r"pre-?walking|"
    r"ages?\s*2\s+to\s+5|ages?\s*3\s*[–-]\s*5",
    re.I,
)
PRICE_RE = re.compile(r"\$\s?\d")
FREE_RE = re.compile(r"\bfree\b|\bwaives\b", re.I)
NOT_FREE_RE = re.compile(
    r"feel free|free parking|parking is free|garages is free|"
    r"free snacks|snacks are free|cocoa is free|"
    r"free santa photos|santa photos|"
    r"free (?:photos|cocoa|samples|coffee|water)\b|"
    r"free and reduced(?:\s+admission)?|"
    r"ages?\s+\d+\s+and\s+under\s+are\s+free|"
    r"adults are free|free for (?:overnight )?guests",
    re.I,
)
NO_SIGNUP_RE = re.compile(
    r"no registration|registration is not required|registration not required|"
    r"no advance registration|no tickets|not a ticket|walk-?up|"
    r"(?:do not|don't|does not) need (?:a )?tickets?",
    re.I,
)
SIGNUP_RE = re.compile(
    r"\bregister\b|\bregistration\b|\bsold out\b|\btickets?\b|\bsign[\s-]?ups?\b|"
    r"\bsession is full\b|\bsession full\b",
    re.I,
)
SENSORY_RE = re.compile(r"sensory-friendly|low-sensory", re.I)
DROPOFF_RE = re.compile(r"\bdrop-?off\b|parents' night", re.I)
FREE_VENUES = ("library", "community center", "meeting room", "programming space", "programming room", "makerspace")


def contains_phrase(hay, phrase):
    if not phrase or not hay:
        return False
    if phrase == "street" and re.search(
        r"\d(?:st|nd|rd|th)?\s+(?:\w+\s+){0,3}street\b", hay
    ):
        return False
    return re.search(rf"(?<![a-z0-9]){re.escape(phrase)}(?![a-z0-9])", hay) is not None


def activity_outdoor(name, blurb, tags):
    """A hike or parade the event is, not a pumpkin patch mentioned in a plot."""
    tag_set = {str(tag).lower() for tag in (tags or [])}
    if tag_set & {"parade", "pumpkin-patch", "corn-maze"}:
        return True
    name_l = (name or "").lower()
    if any(contains_phrase(name_l, phrase) for phrase in ACTIVITY):
        return True
    if not ACTIVITY or not blurb:
        return False
    phrases = "|".join(re.escape(phrase) for phrase in ACTIVITY if phrase)
    pattern = re.compile(
        rf"\b(?:a|an)\s+(?:[\w-]+\s+){{0,3}}(?:{phrases})\b",
        re.I,
    )
    return pattern.search(blurb) is not None


def infer_setting(name, place, blurb, tags=None, same_as=""):
    if activity_outdoor(name, blurb, tags):
        return "Outdoor"
    name_l = (name or "").lower()
    hay = f"{name_l} {(place or '').lower()}"
    best_len = 0
    best = ""
    for label, phrases in (("Indoor", INDOOR), ("Outdoor", OUTDOOR)):
        for phrase in phrases:
            if contains_phrase(hay, phrase) and len(phrase) > best_len:
                best_len = len(phrase)
                best = label
    if best:
        return best
    if "kcls.bibliocommons" in (same_as or "").lower():
        return "Indoor"
    return ""


def confirmed_free(name, place, blurb, cost, same_as=""):
    if cost not in (None, "", False):
        return False
    text = f"{name or ''} {place or ''} {blurb or ''}"
    if PRICE_RE.search(text):
        return False
    cleaned = NOT_FREE_RE.sub(" ", text)
    if FREE_RE.search(cleaned):
        return True
    hay = f"{name or ''} {place or ''}".lower()
    if any(contains_phrase(hay, phrase) for phrase in FREE_VENUES):
        return True
    if "kcls.bibliocommons" in (same_as or "").lower():
        return True
    return False


def confirmed_toddlers(ages, blurb):
    if ages not in (None, "", False):
        return False
    text = blurb or ""
    if re.search(r"\ball ages\b", text, re.I):
        return False
    # A price exception is not the audience. "Babies are not admitted" is not either.
    text = re.sub(
        r"ages?\s+\d+\s*(?:to|–|-|and)\s+\d+\s+are\s+free",
        " ",
        text,
        flags=re.I,
    )
    text = re.sub(
        r"(?:children|kids|ages?|babies)\s+under\s+\d+\s+(?:are|is)\s+free",
        " ",
        text,
        flags=re.I,
    )
    text = re.sub(r"babies in arms", " ", text, flags=re.I)
    if re.search(r"preschool\s+and\s+elementary|elementary", text, re.I):
        if not re.search(r"baby story\s*time|lap[\s-]?sit|\btoddlers?\b|under\s+5", text, re.I):
            return False
    # Ages 5 and up is Kids, not Toddlers. A baby story time still counts.
    if re.search(r"ages?\s*5\s+and\s+(?:older|up)|ages?\s*5\s+to\s+1|ages?\s*5\s*\+", text, re.I):
        if not re.search(r"baby story\s*time|\btoddlers?\b|under\s+5|preschool|lap[\s-]?sit", text, re.I):
            return False
    return bool(TODDLER_RE.search(text))


def tags_say_free(tags, cost, text):
    if cost not in (None, "", False):
        return False
    if not any(str(tag).strip().lower() == "free" for tag in (tags or [])):
        return False
    return not PRICE_RE.search(text or "")


def confirmed_signup(signup, blurb, name=""):
    if signup in (True, "true", "True"):
        return False
    text = f"{name or ''} {blurb or ''}"
    text = re.sub(r"optional[^.]{0,80}\btickets?\b", " ", text, flags=re.I)
    text = re.sub(
        r"volunteers?.{0,80}sign[\s-]?ups?|sign[\s-]?ups?.{0,40}volunteers?",
        " ",
        text,
        flags=re.I,
    )
    if NO_SIGNUP_RE.search(text):
        return False
    return bool(SIGNUP_RE.search(text))


def confirmed_sensory(sensory, blurb):
    if sensory in (True, "true", "True"):
        return False
    return bool(SENSORY_RE.search(blurb or ""))


def confirmed_dropoff(event, blurb):
    if event.get("drop_off") in (True, "true", "True"):
        return False
    name = (event.get("name") or "").lower()
    tags = [str(tag).lower() for tag in (event.get("tags") or [])]
    if "camp" in tags or re.search(r"\bcamp?s?\b", name):
        return False
    return bool(DROPOFF_RE.search(blurb or ""))


def city_pages():
    found = {}
    for path in ROOT.glob("*/index.md"):
        city = path.parent.name
        if not (DATA / f"{city}_events.yml").exists():
            continue
        text = path.read_text()
        parts = re.split(r"(?m)^### ", text)
        rows = []
        for part in parts[1:]:
            lines = part.split("\n", 1)
            name = lines[0].strip()
            body = lines[1] if len(lines) > 1 else ""
            place = ""
            match = re.search(r'<p class="event-place">(.*?)</p>', body, re.S)
            if match:
                place = re.sub(r"<[^>]+>", " ", match.group(1))
                place = re.sub(r"\s+", " ", place).strip()
            links = " ".join(re.findall(r"\((https?://[^)]+)\)", body))
            plain = re.sub(r"\{%.*?%\}", " ", body, flags=re.S)
            plain = re.sub(r"<[^>]+>", " ", plain)
            plain = re.sub(r"\[([^\]]+)\]\([^)]+\)", r" \1 ", plain)
            plain = re.sub(r"\s+", " ", plain).strip()
            rows.append({"name": name, "place": place, "blurb": plain, "links": links})
        found[city] = rows
    return found


def norm_name(name):
    text = html.unescape(name or "").replace("\u2019", "'")
    return re.sub(r"\s+", " ", text).strip().lower()


def blurb_queues(rows):
    queues = {}
    for row in rows:
        queues.setdefault(norm_name(row["name"]), []).append(row)
    return queues


def lookup_page(queues, rows, name):
    key = norm_name(name)
    bucket = queues.get(key) or []
    if bucket:
        return bucket.pop(0)
    hits = []
    seen = set()
    for row in rows:
        row_key = norm_name(row["name"])
        if not row_key or row_key == key:
            continue
        if row_key in key or key in row_key:
            if row_key not in seen:
                seen.add(row_key)
                hits.append(row)
    if len(hits) == 1:
        return hits[0]
    return {"name": name, "place": "", "blurb": ""}


def yaml_quote(value):
    return '"' + str(value).replace('"', '\\"') + '"'


def insert_fields(block, fields):
    """Insert label lines after the name line. fields is an ordered list of (key, value)."""
    if not fields:
        return block
    lines = block.splitlines(keepends=True)
    insert_at = 1
    for index, line in enumerate(lines):
        if index == 0:
            continue
        stripped = line.strip()
        if stripped.startswith("cost:") or stripped.startswith("ages:") or stripped.startswith("setting:"):
            insert_at = index + 1
            continue
        break
    extra = []
    for key, value in fields:
        if value is True:
            extra.append(f"  {key}: true\n")
        else:
            extra.append(f"  {key}: {yaml_quote(value)}\n")
    lines[insert_at:insert_at] = extra
    return "".join(lines)


def split_documents(text):
    lines = text.splitlines(keepends=True)
    header = []
    blocks = []
    current = []
    for line in lines:
        if line.startswith("- ") and current:
            blocks.append("".join(current))
            current = [line]
        elif line.startswith("- ") and not current:
            if header or True:
                current = [line]
        else:
            if current:
                current.append(line)
            else:
                header.append(line)
    if current:
        blocks.append("".join(current))
    return "".join(header), blocks


def event_name(block):
    match = re.search(r'name:\s*"([^"]*)"', block)
    if match:
        return match.group(1)
    match = re.search(r"name:\s*'([^']*)'", block)
    if match:
        return match.group(1)
    match = re.search(r"name:\s*(.+)", block)
    return match.group(1).strip() if match else ""


def has_key(block, key):
    return re.search(rf"(?m)^  {key}:", block) is not None


def current_setting(block):
    match = re.search(r"(?m)^  setting:\s*(.+?)\s*$", block)
    if not match:
        return ""
    return match.group(1).strip().strip('"').strip("'")


def replace_setting(block, value):
    return re.sub(
        r"(?m)^  setting:\s*.+$",
        f"  setting: {yaml_quote(value)}",
        block,
        count=1,
    )


def bare_city(place, city):
    text = re.sub(r"\s+", " ", (place or "").strip().lower())
    city_name = city.replace("-", " ")
    if text in {city_name, city, ""}:
        return True
    return re.fullmatch(rf"{re.escape(city_name)}(?:\s+wa)?(?:\s+\d{{5}})?", text) is not None


def process_file(path, pages, dry_run):
    text = path.read_text()
    header, blocks = split_documents(text)
    city = path.name.replace("_events.yml", "")
    rows = pages.get(city, [])
    queues = blurb_queues(rows)
    changed = 0
    new_blocks = []
    for block in blocks:
        name = event_name(block)
        page = lookup_page(queues, rows, name)
        try:
            event = yaml.safe_load(block)
        except yaml.YAMLError:
            new_blocks.append(block)
            continue
        if isinstance(event, list):
            event = event[0] if event else {}
        if not isinstance(event, dict):
            new_blocks.append(block)
            continue
        place = event.get("place") or ""
        page_place = page.get("place") or ""
        # A bare town name is not a venue. The city page place line is.
        if page_place and bare_city(place, city):
            place = page_place
        blurb = " ".join(
            part for part in (event.get("blurb") or "", page.get("blurb") or "") if part
        )
        tags = event.get("tags")
        same_as = event.get("same_as") or ""
        fields = []
        rewritten = False
        setting = infer_setting(event.get("name") or "", place, blurb, tags, same_as)
        if (
            setting == "Outdoor"
            and activity_outdoor(event.get("name") or "", blurb, tags)
            and current_setting(block) == "Indoor"
        ):
            block = replace_setting(block, "Outdoor")
            rewritten = True
        elif setting and not has_key(block, "setting"):
            fields.append(("setting", setting))
        if not has_key(block, "cost") and (
            confirmed_free(event.get("name"), place, blurb, event.get("cost"), same_as)
            or tags_say_free(tags, event.get("cost"), f"{event.get('name') or ''} {blurb}")
        ):
            fields.append(("cost", "Free"))
        if not has_key(block, "ages") and confirmed_toddlers(event.get("ages"), blurb):
            fields.append(("ages", "Toddlers"))
        signup_blurb = blurb
        if re.search(r"tickets?", page.get("links") or "", re.I):
            signup_blurb = f"{blurb} tickets"
        if not has_key(block, "signup") and confirmed_signup(
            event.get("signup"), signup_blurb, event.get("name")
        ):
            fields.append(("signup", True))
        if not has_key(block, "sensory") and confirmed_sensory(event.get("sensory"), blurb):
            fields.append(("sensory", True))
        if not has_key(block, "drop_off") and confirmed_dropoff(event, blurb):
            fields.append(("drop_off", True))
        if fields or rewritten:
            changed += 1
            if dry_run:
                added = ", ".join(f"{key}={value}" for key, value in fields)
                flip = " setting=Outdoor" if rewritten else ""
                print(f"  {name}: {added}{flip}")
            if fields:
                block = insert_fields(block, fields)
        new_blocks.append(block)
    if changed and not dry_run:
        path.write_text(header + "".join(new_blocks))
    return changed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    pages = city_pages()
    total = 0
    for path in sorted(DATA.glob("*_events.yml")):
        count = process_file(path, pages, args.dry_run)
        if count:
            print(f"{path.name}: {count}")
        total += count
    print(f"{'would update' if args.dry_run else 'updated'} {total} events")


if __name__ == "__main__":
    main()

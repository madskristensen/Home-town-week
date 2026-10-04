#!/usr/bin/env python3
"""Check built pages against Google's event, article, and site markup rules.

One JSON-LD graph per page. Events need name, startDate, endDate, and a
Place with an address. Timed dates need a UTC offset. Date-only events
stay dates. A timed event with no end clock ends two hours later, or on
a later date when only that date is known. isAccessibleForFree is set
only when the price is 0. Every event needs an organizer. An offer is
present only for a known price: 0 for free, or the lowest number for a
paid price, with USD, InStock, a URL, and validFrom. An unknown price
has no offers object. Performer is optional. Warnings do not fail the
build. Missing required fields do.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "_site"
SCRIPT = re.compile(
    r"<script\b[^>]*type=[\"']?application/ld\+json[\"']?[^>]*>(.*?)</script>",
    re.IGNORECASE | re.DOTALL,
)
TIMED = re.compile(r"T\d{2}:\d{2}")
OFFSET = re.compile(r"T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\Z")
DATE_ONLY = re.compile(r"\A\d{4}-\d{2}-\d{2}\Z")
VALID_FROM = re.compile(r"\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\Z")

errors = []
warnings = []


def add(bucket, path, message):
    bucket.append(f"{path}: {message}")


def load(path):
    html = path.read_text(encoding="utf-8", errors="replace")
    blocks = SCRIPT.findall(html)
    return html, blocks


def graph_of(blocks, rel):
    if len(blocks) != 1:
        add(errors, rel, f"{len(blocks)} JSON-LD blocks, expected 1")
        return None
    try:
        data = json.loads(blocks[0])
    except json.JSONDecodeError as err:
        add(errors, rel, f"invalid JSON-LD ({err})")
        return None
    graph = data.get("@graph")
    if not isinstance(graph, list):
        add(errors, rel, "JSON-LD is not one @graph")
        return None
    return graph


def types(node):
    raw = node.get("@type")
    if isinstance(raw, list):
        return raw
    return [raw] if raw else []


def find_type(graph, name):
    return [node for node in graph if isinstance(node, dict) and name in types(node)]


def check_sitewide(graph, rel):
    websites = find_type(graph, "WebSite")
    orgs = find_type(graph, "Organization")
    if not websites:
        add(errors, rel, "missing WebSite")
    if not orgs:
        add(errors, rel, "missing Organization")
        return
    logo = orgs[0].get("logo") or {}
    url = logo.get("url") if isinstance(logo, dict) else logo
    if not url:
        add(errors, rel, "Organization has no logo")
    width = logo.get("width") if isinstance(logo, dict) else None
    if width and int(width) < 112:
        add(errors, rel, f"logo width {width} is under 112")


def check_event(node, rel, index):
    name = node.get("name") or f"event {index}"
    label = f"Event {name!r}"
    if not node.get("name"):
        add(errors, rel, f"{label} missing name")
    start = node.get("startDate") or ""
    if not start:
        add(errors, rel, f"{label} missing startDate")
    elif TIMED.search(start):
        if not OFFSET.search(start):
            add(errors, rel, f"{label} timed startDate has no UTC offset: {start}")
        if "T00:00:00" in start:
            add(errors, rel, f"{label} startDate is midnight: {start}")
    elif not DATE_ONLY.search(start):
        add(errors, rel, f"{label} startDate is not a date or offset time: {start}")
    end = node.get("endDate") or ""
    if not end:
        add(errors, rel, f"{label} missing endDate")
    elif TIMED.search(end):
        if not OFFSET.search(end):
            add(errors, rel, f"{label} timed endDate has no UTC offset: {end}")
        if "T23:59:59" in end or "T00:00:00" in end:
            add(errors, rel, f"{label} endDate uses a placeholder clock: {end}")
        if TIMED.search(start) and end <= start:
            add(errors, rel, f"{label} endDate is not after startDate: {end}")
    elif not DATE_ONLY.search(end):
        add(errors, rel, f"{label} endDate is not a date or offset time: {end}")
    elif TIMED.search(start) and end <= start[:10]:
        add(errors, rel, f"{label} date-only endDate is not after the start day: {end}")
    elif DATE_ONLY.search(start) and end < start:
        add(errors, rel, f"{label} endDate is before startDate: {end}")
    location = node.get("location") or {}
    if location.get("@type") != "Place":
        add(errors, rel, f"{label} location is not a Place")
    elif not location.get("name"):
        add(errors, rel, f"{label} missing location.name")
    address = location.get("address") if isinstance(location, dict) else None
    if not isinstance(address, dict) or address.get("@type") != "PostalAddress":
        add(errors, rel, f"{label} missing PostalAddress")
    else:
        if not address.get("addressLocality"):
            add(errors, rel, f"{label} missing addressLocality")
        if not address.get("addressRegion"):
            add(errors, rel, f"{label} missing addressRegion")
        if not address.get("addressCountry"):
            add(errors, rel, f"{label} missing addressCountry")
        if not address.get("streetAddress"):
            add(warnings, rel, f"{label} has no streetAddress")
        if not address.get("postalCode"):
            add(warnings, rel, f"{label} has no postalCode")
    if location.get("name") and node.get("name") and location.get("name") == node.get("name"):
        add(warnings, rel, f"{label} location.name repeats the event name")
    status = node.get("eventStatus") or ""
    if status != "https://schema.org/EventScheduled":
        add(errors, rel, f"{label} eventStatus is {status or 'missing'}")
    mode = node.get("eventAttendanceMode") or ""
    if mode != "https://schema.org/OfflineEventAttendanceMode":
        add(errors, rel, f"{label} eventAttendanceMode is {mode or 'missing'}")
    url = node.get("url") or ""
    if not url.startswith("http"):
        add(errors, rel, f"{label} url is not the source: {url or 'missing'}")
    if not node.get("description"):
        add(errors, rel, f"{label} has no description")
    if not node.get("image"):
        add(warnings, rel, f"{label} has no image")
    elif not isinstance(node.get("image"), list):
        add(warnings, rel, f"{label} image is not a list of URLs")
    organizer = node.get("organizer") or {}
    if not isinstance(organizer, dict) or organizer.get("@type") != "Organization":
        add(errors, rel, f"{label} organizer is not an Organization")
    elif not organizer.get("name") or not str(organizer.get("url") or "").startswith("http"):
        add(errors, rel, f"{label} organizer is missing a name or url")
    performer = node.get("performer")
    if performer is not None:
        if not isinstance(performer, dict) or not performer.get("name"):
            add(errors, rel, f"{label} performer has no name")
        elif performer.get("@type") not in ("Person", "PerformingGroup", "MusicGroup"):
            add(errors, rel, f"{label} performer type is {performer.get('@type') or 'missing'}")
    free = node.get("isAccessibleForFree")
    raw_offer = node.get("offers")
    if free is False:
        add(errors, rel, f"{label} sets isAccessibleForFree false")
    if raw_offer is None:
        if free is True:
            add(errors, rel, f"{label} is free but has no offers")
        return
    if not isinstance(raw_offer, dict) or not raw_offer:
        add(errors, rel, f"{label} offers is empty")
        return
    offer = raw_offer
    price = offer.get("price")
    has_price = "price" in offer
    if free is True and price not in (0, 0.0, "0"):
        add(errors, rel, f"{label} is free but offer price is {price!r}")
    if price in (0, 0.0, "0") and free is not True:
        add(errors, rel, f"{label} price is 0 without isAccessibleForFree")
    if not str(offer.get("url") or "").startswith("http"):
        add(errors, rel, f"{label} offer url is not the source page")
    if "InStock" not in str(offer.get("availability")):
        add(errors, rel, f"{label} offer availability is not InStock")
    valid_from = offer.get("validFrom") or ""
    if not VALID_FROM.search(valid_from):
        add(errors, rel, f"{label} offer validFrom needs an offset: {valid_from or 'missing'}")
    elif "T00:00:00" in valid_from:
        add(errors, rel, f"{label} offer validFrom is midnight: {valid_from}")
    if not has_price:
        add(errors, rel, f"{label} offer is missing price")
    elif offer.get("priceCurrency") != "USD":
        add(errors, rel, f"{label} offer currency is not USD")
    elif not isinstance(price, (int, float)) or isinstance(price, bool):
        add(errors, rel, f"{label} offer price is not a number: {price!r}")


def check_article(graph, rel):
    articles = find_type(graph, "Article")
    if not articles:
        add(errors, rel, "missing Article")
        return
    article = articles[0]
    for field in ("headline", "image", "datePublished", "author"):
        if not article.get(field):
            add(errors, rel, f"Article missing {field}")
    headline = article.get("headline") or ""
    if len(headline) > 110:
        add(errors, rel, f"headline is {len(headline)} characters")
    author = article.get("author") or {}
    if isinstance(author, dict) and not author.get("name"):
        add(errors, rel, "Article author has no name")
    publisher = article.get("publisher") or {}
    logo = publisher.get("logo") if isinstance(publisher, dict) else None
    logo_url = logo.get("url") if isinstance(logo, dict) else None
    if not logo_url:
        add(errors, rel, "Article publisher has no logo")
    if not article.get("dateModified"):
        add(warnings, rel, "Article has no dateModified")


def check_breadcrumb(graph, rel):
    crumbs = find_type(graph, "BreadcrumbList")
    if not crumbs:
        add(errors, rel, "missing BreadcrumbList")
        return
    items = crumbs[0].get("itemListElement") or []
    if len(items) < 2:
        add(errors, rel, "BreadcrumbList has fewer than 2 items")
    for item in items:
        if not item.get("name") or not item.get("item") or not item.get("position"):
            add(errors, rel, "BreadcrumbList item is missing name, item, or position")


def city_ids():
    ids = []
    for line in (ROOT / "_data" / "cities.yml").read_text(encoding="utf-8").splitlines():
        if line.startswith("- id: "):
            ids.append(line.split(":", 1)[1].strip())
    return ids


CITY_IDS = city_ids()
EVENT_HUBS = (
    "fall/index.html",
    "christmas/index.html",
    "easter/index.html",
    "spring-break/index.html",
    "fourth/index.html",
    "diwali/index.html",
    "rainy-day/index.html",
    "worth-the-drive/index.html",
    "this-weekend/index.html",
    "articles/free-things-to-do/index.html",
    "articles/toddler-friendly-outings/index.html",
)


def wants_events(rel):
    if rel in EVENT_HUBS:
        return True
    parts = rel.split("/")
    return len(parts) == 2 and parts[1] == "index.html" and parts[0] in CITY_IDS


def wants_breadcrumb(rel):
    if rel in ("index.html", "404.html"):
        return False
    if rel.startswith("articles/"):
        return True
    if wants_events(rel):
        return True
    extras = (
        "playgrounds/", "farmers-markets/", "book-ahead/", "no-school-days/",
        "summer-camps/",
        "fall/decorations/", "fall/bucket-list/", "christmas/lights/",
    )
    return any(rel.startswith(item) for item in extras)


def wants_article(rel):
    return rel.startswith("articles/") and rel not in ("articles/index.html",)


def main():
    pages = sorted(SITE.rglob("*.html"))
    if not pages:
        sys.exit("no built HTML; run jekyll build first")
    samples = []
    for path in pages:
        rel = str(path.relative_to(SITE))
        if rel.startswith("assets/"):
            continue
        _html, blocks = load(path)
        if rel == "404.html":
            if blocks:
                add(errors, rel, "404 should not emit JSON-LD")
            continue
        if rel == "font-preview.html":
            if blocks:
                add(errors, rel, "font preview should not emit JSON-LD")
            continue
        graph = graph_of(blocks, rel)
        if not graph:
            continue
        if rel == "index.html":
            check_sitewide(graph, rel)
        elif find_type(graph, "WebSite") or (
            find_type(graph, "Organization")
            and any(
                isinstance(node.get("logo"), dict)
                for node in find_type(graph, "Organization")
            )
        ):
            add(warnings, rel, "WebSite or Organization logo belongs on the home page")
        events = find_type(graph, "Event")
        if wants_events(rel):
            if not events:
                add(warnings, rel, "no Event nodes")
            for index, event in enumerate(events, 1):
                check_event(event, rel, index)
            if events:
                samples.append((rel, len(events)))
        elif events:
            add(warnings, rel, f"{len(events)} Event nodes on a page that is not an event list")
        if wants_breadcrumb(rel):
            check_breadcrumb(graph, rel)
        if wants_article(rel):
            check_article(graph, rel)
        micro = path.read_text(encoding="utf-8", errors="replace").lower()
        if "itemtype=\"https://schema.org/event\"" in micro or "itemtype='https://schema.org/event'" in micro:
            add(errors, rel, "still has Event microdata")

    print(f"Checked {len(pages)} HTML files.")
    if samples:
        print("Event pages:")
        for rel, count in samples:
            if rel in (
                "kirkland/index.html",
                "this-weekend/index.html",
                "fall/index.html",
                "articles/free-things-to-do/index.html",
            ) or rel.endswith("bellevue/index.html"):
                print(f"  {rel}: {count} events")
    if warnings:
        print(f"\nWarnings ({len(warnings)}):")
        for line in warnings[:80]:
            print(f"  {line}")
        if len(warnings) > 80:
            print(f"  ... {len(warnings) - 80} more")
    if errors:
        print(f"\nErrors ({len(errors)}):")
        for line in errors[:80]:
            print(f"  {line}")
        if len(errors) > 80:
            print(f"  ... {len(errors) - 80} more")
        sys.exit(1)
    print("\nRequired Google fields passed.")


if __name__ == "__main__":
    main()

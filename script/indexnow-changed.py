#!/usr/bin/env python3
"""Tell IndexNow about URLs whose source files changed in this push.

The whole sitemap is not submitted. A city page or that city's data file
also refreshes the home page, This weekend, and the seasonal hubs, because
those pages list the same events.

    BEFORE=abc SHA=def INDEXNOW_KEY=... python3 script/indexnow-changed.py
"""

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = "https://www.eastsidecalendar.com"
HUBS = [
    "/",
    "/this-weekend/",
    "/worth-the-drive/",
    "/fall/",
    "/christmas/",
    "/easter/",
    "/spring-break/",
    "/fourth/",
    "/diwali/",
    "/rainy-day/",
]
SHARED_PREFIXES = (
    "_includes/",
    "_layouts/",
    "_plugins/",
    "_css/",
    "_sass/",
    "assets/css/",
    "assets/js/",
)


def git_diff(before, sha):
    if before and set(before) != {"0"}:
        spec = [before, sha or "HEAD"]
    else:
        spec = ["HEAD~1", "HEAD"]
    result = subprocess.run(
        ["git", "diff", "--name-only", *spec],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr.strip() or "git diff failed", file=sys.stderr)
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def content_pages():
    urls = {f"{SITE}/", f"{SITE}/this-weekend/", f"{SITE}/worth-the-drive/", f"{SITE}/playgrounds/"}
    for path in ROOT.glob("*/index.md"):
        urls.add(f"{SITE}/{path.parent.name}/")
    for hub in HUBS:
        urls.add(f"{SITE}{hub}")
    return sorted(urls)


def urls_for(paths):
    found = set()
    shared = False
    for path in paths:
        # Temporary wordmark preview. Do not submit it.
        if path == "font-preview.html":
            continue
        if path.startswith(SHARED_PREFIXES) or path in {"README.md", "AGENTS.md"}:
            if path.startswith(SHARED_PREFIXES):
                shared = True
            continue
        if path == "index.md":
            found.add(f"{SITE}/")
            continue
        if path.endswith("/index.md"):
            city = path.split("/", 1)[0]
            found.add(f"{SITE}/{city}/")
            if (ROOT / "_data" / f"{city}_events.yml").exists() or city in {
                "this-weekend",
                "worth-the-drive",
                "playgrounds",
            }:
                for hub in HUBS:
                    found.add(f"{SITE}{hub}")
            continue
        if path == "_data/farmers_markets.yml":
            found.add(f"{SITE}/farmers-markets/")
            continue
        if path == "_data/book_ahead.yml":
            found.add(f"{SITE}/book-ahead/")
            continue
        if path == "_data/no_school_days.yml":
            found.add(f"{SITE}/no-school-days/")
            continue
        if path == "_data/summer_camps.yml":
            found.add(f"{SITE}/summer-camps/")
            continue
        if path.startswith("_data/") and path.endswith("_events.yml"):
            city = Path(path).name.replace("_events.yml", "")
            if city == "worth_the_drive":
                found.add(f"{SITE}/worth-the-drive/")
            else:
                found.add(f"{SITE}/{city}/")
            for hub in HUBS:
                found.add(f"{SITE}{hub}")
            continue
        if path.endswith(".md"):
            slug = path[:-3]
            if slug.endswith("/index"):
                slug = slug[: -len("/index")]
            found.add(f"{SITE}/{slug}/")
    if shared:
        return content_pages()
    return sorted(found)


def submit(urls, key):
    if not urls:
        print("IndexNow: no content URLs changed.")
        return 0
    payload = {
        "host": "www.eastsidecalendar.com",
        "key": key,
        "keyLocation": f"{SITE}/{key}.txt",
        "urlList": urls[:10000],
    }
    request = urllib.request.Request(
        "https://api.indexnow.org/indexnow",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        print(f"IndexNow: submitted {len(payload['urlList'])} URLs, HTTP {response.status}")
    return 0


def main():
    key = os.environ.get("INDEXNOW_KEY", "").strip()
    if not key:
        print("IndexNow: INDEXNOW_KEY is not set.")
        return 0
    paths = git_diff(os.environ.get("BEFORE", "").strip(), os.environ.get("SHA", "").strip())
    urls = urls_for(paths)
    for url in urls:
        print(url)
    return submit(urls, key)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"indexnow-changed: {exc}", file=sys.stderr)
        sys.exit(1)

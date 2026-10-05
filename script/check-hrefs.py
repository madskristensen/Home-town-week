#!/usr/bin/env python3
"""Fail the build when a published href is not a link this site allows.

Allowed: http(s), a relative URL, a fragment, mailto, tel, or webcal.
"""

import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "_site"


class HrefCheck(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.bad = []

    def handle_starttag(self, tag, attrs):
        self._check(tag, attrs)

    def handle_startendtag(self, tag, attrs):
        self._check(tag, attrs)

    def _check(self, tag, attrs):
        for key, value in attrs:
            if key.lower() != "href":
                continue
            text = "" if value is None else value.strip()
            if allowed(text):
                continue
            shown = text if text else "(empty)"
            self.bad.append(f"<{tag}> {shown}")


def allowed(text):
    if not text or any(ch.isspace() for ch in text):
        return False
    if text.startswith("//"):
        return False
    lowered = text.lower()
    if lowered.startswith(("https://", "http://", "mailto:", "tel:", "webcal:")):
        return True
    if text.startswith(("#", "/", "?", "./", "../")):
        return True
    return ":" not in text.split("/", 1)[0]


def main():
    site = SITE
    if not site.is_dir():
        sys.exit(f"missing {site}")
    errors = []
    for path in sorted(site.rglob("*.html")):
        parser = HrefCheck()
        try:
            parser.feed(path.read_text(encoding="utf-8", errors="replace"))
        except Exception as exc:
            errors.append(f"{path.relative_to(site)}: {exc}")
            continue
        for item in parser.bad:
            errors.append(f"{path.relative_to(site)}: {item}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(f"{len(errors)} href(s) are not http(s), relative, #, mailto, tel, or webcal")
    print(f"Checked hrefs in {sum(1 for _ in site.rglob('*.html'))} HTML files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

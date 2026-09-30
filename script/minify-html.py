#!/usr/bin/env python3
"""Minify built HTML, inline scripts, and JSON-LD.

Jekyll writes pretty-printed pages. This runs after the build, compacts
every application/ld+json block (it must stay valid JSON), then minifies
markup and inline JavaScript. SVG, pre, and textarea contents are left
to the minifier, which keeps them well-formed.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

try:
    import minify_html
except ImportError:
    sys.exit("minify-html is required: python3 -m pip install minify-html")

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "_site"
JSON_LD = re.compile(
    r"<script\b([^>]*type=[\"']application/ld\+json[\"'][^>]*)>(.*?)</script>",
    re.IGNORECASE | re.DOTALL,
)
SCRIPT = re.compile(r"<script\b([^>]*)>(.*?)</script>", re.IGNORECASE | re.DOTALL)


def compact_jsonld(html, path):
    def repl(match):
        attrs, body = match.group(1), match.group(2)
        try:
            data = json.loads(body)
        except json.JSONDecodeError as err:
            sys.exit(f"{path}: invalid JSON-LD ({err})")
        compact = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
        return f'<script{attrs}>{compact}</script>'

    return JSON_LD.sub(repl, html)


def check(html, path):
    head, sep, _rest = html.partition("<body")
    if sep and "ld+json" in head.lower():
        sys.exit(f"{path}: JSON-LD is still in the head")
    blocks = list(JSON_LD.finditer(html))
    unquoted = list(
        re.finditer(
            r"<script\b([^>]*type=application/ld\+json[^>]*)>(.*?)</script>",
            html,
            re.IGNORECASE | re.DOTALL,
        )
    )
    found = blocks or unquoted
    if "ld+json" in html.lower() and not found:
        sys.exit(f"{path}: JSON-LD present but not parseable after minify")
    for match in found:
        body = match.group(2)
        try:
            json.loads(body)
        except json.JSONDecodeError as err:
            sys.exit(f"{path}: minified JSON-LD is invalid ({err})")
        if "\n" in body:
            sys.exit(f"{path}: JSON-LD is still pretty-printed")
    if sep:
        if "</body>" not in html.lower():
            sys.exit(f"{path}: missing </body>")
        end = html.lower().rfind("</body>")
        last = html.lower().rfind("ld+json")
        if last != -1 and last > end:
            sys.exit(f"{path}: JSON-LD sits after </body>")
        if last != -1:
            between = html[html.lower().rfind("</script>", 0, end) + len("</script>"):end]
            if between.strip():
                sys.exit(f"{path}: content between JSON-LD and </body>: {between[:80]!r}")
    for index, match in enumerate(SCRIPT.finditer(html)):
        attrs, body = match.group(1), match.group(2)
        if "ld+json" in attrs or not body.strip():
            continue
        probe = Path(f"/tmp/minify-check-{index}.js")
        probe.write_text(body, encoding="utf-8")
        result = subprocess.run(
            ["node", "--check", str(probe)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            sys.exit(f"{path}: inline script {index} failed to parse\n{result.stderr}")


def main():
    if not SITE.is_dir():
        sys.exit(f"missing build directory {SITE}")
    pages = sorted(SITE.rglob("*.html"))
    if not pages:
        sys.exit("no HTML files to minify")
    report = []
    for path in pages:
        original = path.read_text(encoding="utf-8")
        compacted = compact_jsonld(original, path.relative_to(SITE))
        minified = minify_html.minify(
            compacted,
            minify_js=True,
            minify_css=True,
            keep_closing_tags=True,
            keep_html_and_head_opening_tags=True,
        )
        check(minified, path.relative_to(SITE))
        if not minified.endswith("\n"):
            minified += "\n"
        path.write_text(minified, encoding="utf-8")
        rel = path.relative_to(SITE).as_posix()
        if rel in {"index.html", "bellevue/index.html", "fall/index.html", "about/index.html"}:
            report.append(f"{rel}\t{len(original)}\t{len(minified)}")
    print(f"minified {len(pages)} html files")
    for line in report:
        print(line)


if __name__ == "__main__":
    main()

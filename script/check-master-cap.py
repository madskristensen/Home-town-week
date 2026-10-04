#!/usr/bin/env python3
"""Warn when a newly committed master is wider than the cap.

Existing originals are left as they are. Nothing is rewritten, and
the build still passes. Pages sets BEFORE to github.event.before.
Only masters added or modified since that commit are checked. The
card cap is 1600px on the long side. A city hero may be 2000px.

    BEFORE=<sha> python3 script/check-master-cap.py
"""

import os
import re
import subprocess
import sys

IMAGE_ROOT = "assets/images"
SKIP_TOP = {"cities", "og", "share"}
SKIP_NAMES = {"logo.png", "apple-touch-icon.png", "favicon.png"}
CARD_CAP = 1600
HERO_CAP = 2000
VARIANT_RE = re.compile(r"-(?:400|640|800|960|1200|1280|1600)$")
SHA_RE = re.compile(r"[0-9a-fA-F]{40}")


def hero_paths():
    path = os.path.join("_data", "cities.yml")
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    found = set()
    for block in re.finditer(r"\n  hero:\n(?:    .+\n)+", text):
        match = re.search(r"image:\s*(\S+)", block.group(0))
        if not match:
            continue
        found.add(match.group(1).strip().strip("\"'").lstrip("/"))
    return found


def is_master(path):
    path = path.replace(os.sep, "/")
    if not path.startswith(IMAGE_ROOT + "/"):
        return False
    parts = path.split("/")
    if len(parts) < 3 or parts[2] in SKIP_TOP:
        return False
    name = parts[-1]
    if name in SKIP_NAMES or name.startswith("icon-"):
        return False
    stem, ext = os.path.splitext(name)
    if ext.lower() not in {".webp", ".jpg", ".jpeg", ".png"}:
        return False
    if VARIANT_RE.search(stem):
        return False
    return True


def changed_masters(before):
    """Return new master paths, or None when there is no push range."""
    if not before or set(before) <= {"0"}:
        return None
    if not SHA_RE.fullmatch(before):
        print("::warning::BEFORE is not a commit. Existing masters were left as they are.")
        return None
    result = subprocess.run(
        [
            "git",
            "diff",
            "--name-only",
            "--diff-filter=AM",
            before,
            "HEAD",
            "--",
            IMAGE_ROOT,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        print(
            "::warning::Could not list new masters (%s). Existing masters were left as they are."
            % detail
        )
        return None
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def report(paths):
    from PIL import Image

    heroes = hero_paths()
    warned = 0
    for path in paths:
        if not is_master(path) or not os.path.isfile(path):
            continue
        rel = path.replace(os.sep, "/")
        cap = HERO_CAP if rel in heroes else CARD_CAP
        try:
            width, height = Image.open(path).size
        except Exception as exc:
            print("::warning file=%s::Could not read master: %s" % (rel, exc))
            warned += 1
            continue
        long_side = max(width, height)
        if long_side <= cap:
            continue
        print(
            "::warning file=%s::New master is %dpx on the long side. The cap is %dpx. Run python3 script/cap-master.py %s"
            % (rel, long_side, cap, rel)
        )
        warned += 1
    return warned


def main():
    before = os.environ.get("BEFORE", "").strip()
    changed = changed_masters(before)
    if changed is None:
        print("no push range; existing masters left as they are")
        return
    masters = [path for path in changed if is_master(path)]
    if not masters:
        print("no new masters in this push")
        return
    warned = report(masters)
    if warned:
        print("%d new master(s) over the cap." % warned)
    else:
        print("new masters are within the cap")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Minify the stylesheets and publish one fingerprinted file per source.

Reads _css/*.css, writes assets/css/<name>.<hash>.css, and records the
public paths in _data/css.yml. Jekyll links those paths from the head.
Run this before the site is read so the hashed files are static files.
"""

import hashlib
import sys
from pathlib import Path

try:
    import rcssmin
except ImportError:
    sys.exit("rcssmin is required: python3 -m pip install rcssmin")

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "_css"
DEST = ROOT / "assets" / "css"
DATA = ROOT / "_data" / "css.yml"
NAMES = ("site", "home", "city", "seasonal", "lights", "guide")


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for old in DEST.glob("*.css"):
        old.unlink()

    lines = []
    for name in NAMES:
        source = SRC / f"{name}.css"
        if not source.is_file():
            sys.exit(f"missing stylesheet {source}")
        mini = rcssmin.cssmin(source.read_text(encoding="utf-8"))
        if not mini.endswith("\n"):
            mini += "\n"
        digest = hashlib.sha256(mini.encode("utf-8")).hexdigest()[:10]
        filename = f"{name}.{digest}.css"
        (DEST / filename).write_text(mini, encoding="utf-8")
        public = f"/assets/css/{filename}"
        lines.append(f"{name}: {public}")
        print(f"{name}\t{public}\t{len(mini)}")

    DATA.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

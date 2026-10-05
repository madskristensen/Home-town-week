#!/usr/bin/env python3
"""Cap and compress masters added or changed in one push.

Does not walk the library. BEFORE is the commit before the push
(github.event.before). JPEG and PNG become WebP. Width is capped at
1600px, or 2000px for a city hero. A file already within the cap and
already WebP is left byte for byte. Photos outside the push range
are not opened.

    BEFORE=<sha> python3 script/optimize-new-images.py
"""

import io
import os
import re
import subprocess
import sys

IMAGE_ROOT = "assets/images"
SKIP_TOP = {"cities", "og", "share"}
SKIP_NAMES = {"logo.png", "apple-touch-icon.png", "favicon.png", "og-home.png"}
SKIP_WALK = {"_site", "node_modules", "vendor", "assets"}
TEXT_EXT = {".md", ".html", ".yml", ".yaml", ".rb", ".js", ".mjs", ".json", ".py"}
CARD_CAP = 1600
HERO_CAP = 2000
WEBP_QUALITY = 82
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
    if len(parts) < 4 or parts[2] in SKIP_TOP:
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


def is_hero(path, heroes):
    path = path.replace(os.sep, "/")
    stem, _ext = os.path.splitext(path)
    for ext in (".webp", ".jpg", ".jpeg", ".png"):
        if stem + ext in heroes or path in heroes:
            return True
    return False


def changed_paths(before):
    """Return changed image paths, or None when there is no push range."""
    if not before or set(before) <= {"0"}:
        return None
    if not SHA_RE.fullmatch(before):
        print("BEFORE is not a commit. Existing masters were left as they are.")
        return None
    result = subprocess.run(
        [
            "git",
            "diff",
            "--name-only",
            "--diff-filter=AMR",
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
            "Could not list new masters (%s). Existing masters were left as they are."
            % detail
        )
        return None
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def replace_refs(text, old, new):
    pattern = re.compile(re.escape(old) + r"(?!\w)")
    return pattern.sub(new, text)


def rewrite_tree(old, new):
    old = old.replace(os.sep, "/")
    new = new.replace(os.sep, "/")
    if old == new:
        return []
    changed = []
    for dirpath, dirnames, filenames in os.walk("."):
        dirnames[:] = [
            name
            for name in dirnames
            if not name.startswith(".") and name not in SKIP_WALK
        ]
        for name in filenames:
            if os.path.splitext(name)[1].lower() not in TEXT_EXT:
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as handle:
                try:
                    text = handle.read()
                except UnicodeError:
                    continue
            updated = replace_refs(text, old, new)
            if updated == text:
                continue
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(updated)
            changed.append(path.replace(os.sep, "/"))
    return changed


def save_webp(image):
    if image.mode == "P":
        image = image.convert("RGBA" if "transparency" in image.info else "RGB")
    elif image.mode not in ("RGB", "RGBA"):
        bands = image.getbands()
        image = image.convert("RGBA" if bands and "A" in bands else "RGB")
    extra = {}
    icc = image.info.get("icc_profile")
    if icc:
        extra["icc_profile"] = icc
    buffer = io.BytesIO()
    image.save(buffer, "WEBP", quality=WEBP_QUALITY, method=6, **extra)
    return buffer.getvalue()


def cap_width(image, cap):
    if image.width <= cap:
        return image, False
    height = max(1, round(image.height * cap / image.width))
    from PIL import Image

    resized = image.resize((cap, height), Image.Resampling.LANCZOS)
    icc = image.info.get("icc_profile")
    if icc:
        resized.info["icc_profile"] = icc
    return resized, True


def process_path(path, heroes):
    """Optimize one master. Returns a short status, or raises."""
    from PIL import Image, ImageOps

    path = path.replace(os.sep, "/")
    if not is_master(path) or not os.path.isfile(path):
        return "skipped"
    ext = os.path.splitext(path)[1].lower()
    cap = HERO_CAP if is_hero(path, heroes) else CARD_CAP
    before = os.path.getsize(path)
    with Image.open(path) as image:
        image = ImageOps.exif_transpose(image)
        image.load()
        if getattr(image, "n_frames", 1) > 1:
            print("skip %s (animated)" % path)
            return "skipped"
        original_width = image.width
        image, resized = cap_width(image, cap)
        data = save_webp(image)
    dest = path if ext == ".webp" else os.path.splitext(path)[0] + ".webp"
    if dest != path and os.path.exists(dest):
        print("skip %s (%s already exists)" % (path, dest))
        return "skipped"
    if dest == path and not resized and len(data) >= before:
        print("left %s as is (%dpx wide, cap %d)" % (path, original_width, cap))
        return "unchanged"
    folder = os.path.dirname(dest) or "."
    tmp = os.path.join(folder, ".%s.opt-tmp" % os.path.basename(dest))
    try:
        with open(tmp, "wb") as handle:
            handle.write(data)
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    if dest != path:
        os.remove(path)
        refs = rewrite_tree(path, dest)
        for ref in refs:
            print("updated %s" % ref)
    print(
        "optimized %s -> %s (%dpx wide, cap %d, %d -> %d bytes)"
        % (path, dest, min(original_width, cap), cap, before, len(data))
    )
    return "optimized"


def main():
    try:
        import PIL  # noqa: F401
    except ImportError:
        sys.exit("Pillow is required: pip install Pillow")
    before = os.environ.get("BEFORE", "").strip()
    changed = changed_paths(before)
    if changed is None:
        print("no push range; existing masters left as they are")
        return
    masters = [path for path in changed if is_master(path)]
    if not masters:
        print("no new masters in this push")
        return
    heroes = hero_paths()
    failed = False
    optimized = 0
    for path in masters:
        try:
            status = process_path(path, heroes)
        except Exception as exc:
            print("skip %s (%s)" % (path, exc))
            failed = True
            continue
        if status == "optimized":
            optimized += 1
    print("%d master(s) optimized." % optimized)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()

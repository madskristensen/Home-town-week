#!/usr/bin/env python3
"""Cap one new master photo. Does not scan the tree.

Pass the new file. A card photo is scaled so the long side is at
most 1600px. A city hero listed in _data/cities.yml may be 2000px.
The file stays WebP, JPEG, or PNG. A file already within the cap is
left byte for byte. Existing photos are not revisited unless you
pass that path yourself.

    python3 script/cap-master.py assets/images/kirkland/new-photo.webp
"""

import os
import re
import sys

CARD_CAP = 1600
HERO_CAP = 2000
IMAGE_ROOT = "assets/images"
SKIP_TOP = {"cities", "og", "share"}
VARIANT_RE = re.compile(r"-(?:400|640|800|960|1200|1280|1600)$")
WEBP_QUALITY = 82
JPEG_QUALITY = 85


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


def repo_path(raw):
    root = os.path.abspath(".")
    absolute = os.path.abspath(raw)
    if os.path.commonpath([root, absolute]) != root:
        return None
    return os.path.relpath(absolute, root).replace(os.sep, "/")


def reject_reason(path):
    if path is None or not path.startswith(IMAGE_ROOT + "/"):
        return "not under assets/images"
    parts = path.split("/")
    if len(parts) < 3 or parts[2] in SKIP_TOP:
        return "not a photo master"
    name = parts[-1]
    if name.startswith("icon-"):
        return "not a photo master"
    stem, ext = os.path.splitext(name)
    if ext.lower() not in {".webp", ".jpg", ".jpeg", ".png"}:
        return "not a WebP, JPEG, or PNG"
    if VARIANT_RE.search(stem):
        return "generated variant"
    return None


def target_size(image, cap):
    if image.width >= image.height:
        width = cap
        height = max(1, round(image.height * cap / image.width))
    else:
        height = cap
        width = max(1, round(image.width * cap / image.height))
    return width, height


def save_image(image, dest, ext):
    from PIL import Image

    icc = image.info.get("icc_profile")
    extra = {"icc_profile": icc} if icc else {}
    if ext == ".webp":
        if image.mode not in ("RGB", "RGBA"):
            image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
        image.save(dest, "WEBP", quality=WEBP_QUALITY, method=6, **extra)
        return
    if ext in {".jpg", ".jpeg"}:
        image.convert("RGB").save(
            dest,
            "JPEG",
            quality=JPEG_QUALITY,
            optimize=True,
            progressive=True,
            **extra,
        )
        return
    if image.mode not in ("RGB", "RGBA"):
        image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
    image.save(dest, "PNG", optimize=True, **extra)


def cap_file(path, heroes):
    from PIL import Image, ImageOps

    ext = os.path.splitext(path)[1].lower()
    cap = HERO_CAP if path in heroes else CARD_CAP
    before = os.path.getsize(path)
    with Image.open(path) as image:
        image = ImageOps.exif_transpose(image)
        image.load()
        long_side = max(image.width, image.height)
        if long_side <= cap:
            print("left %s as is (%dpx, cap %d)" % (path, long_side, cap))
            return True
        width, height = target_size(image, cap)
        resized = image.resize((width, height), Image.Resampling.LANCZOS)
        icc = image.info.get("icc_profile")
        if icc:
            resized.info["icc_profile"] = icc
    folder = os.path.dirname(path) or "."
    tmp = os.path.join(folder, ".%s.cap-tmp" % os.path.basename(path))
    try:
        save_image(resized, tmp, ext)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    after = os.path.getsize(path)
    print(
        "capped %s %dpx -> %dpx (%d -> %d bytes)"
        % (path, long_side, max(width, height), before, after)
    )
    return True


def main(argv):
    if len(argv) < 2:
        sys.exit("Pass the new photo path. This script does not scan the tree.")
    try:
        import PIL  # noqa: F401
    except ImportError:
        sys.exit("Pillow is required: pip install Pillow")
    heroes = hero_paths()
    failed = False
    for raw in argv[1:]:
        path = repo_path(raw)
        if path and os.path.isdir(path):
            print("skip directory %s; pass the new file" % path)
            failed = True
            continue
        reason = reject_reason(path)
        if reason or not path or not os.path.isfile(path):
            print("skip %s (%s)" % (raw, reason or "missing file"))
            failed = True
            continue
        try:
            cap_file(path, heroes)
        except Exception as exc:
            print("skip %s (%s)" % (path, exc))
            failed = True
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv)

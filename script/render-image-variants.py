#!/usr/bin/env python3
"""Build AVIF, WebP, and JPEG widths for local photos.

The Pages workflow runs this. It is not part of the daily content edit.
A content change adds one source image and a path. This step writes the
widths next to that file, and _data/image_variants.yml so the picture
helper can list only files that exist.

Widths are 400, 640, 800, 1200, and 1600, and never wider than the source.
A 640-wide card file that comes out over its budget is encoded again at
a lower quality until it fits or the floor is reached. Wide hero AVIF
files have their own budget. Outputs live in .image-cache so Actions can
restore them. The cache only matches this encoder id, so a budget change
encodes again. A source that fails to encode is left out of the manifest.
The helper then uses the original file, and this script still exits 0.
"""

import hashlib
import json
import os
import shutil
import sys

WIDTHS = (400, 640, 800, 1200, 1600)
IMAGE_ROOT = os.path.join("assets", "images")
CACHE_ROOT = ".image-cache"
CACHE_OUT = os.path.join(CACHE_ROOT, "out")
CACHE_META = os.path.join(CACHE_ROOT, "meta")
MANIFEST = os.path.join("_data", "image_variants.yml")
SKIP_TOP = {"cities", "og"}
SOURCE_EXT = {".webp", ".jpg", ".jpeg", ".png"}
AVIF_QUALITY = 50
WEBP_QUALITY = 68
JPEG_QUALITY = 75
# Card files are requested at 640. Hero files at 1200 and 1600 cover a
# 44rem picture on a 2x screen. The floor keeps a detailed photo from
# being crushed when the budget is tight.
ENCODER_ID = "budget-640-avif60-jpeg80-hero220"
AVIF_CARD_QUALITIES = (50, 46, 42, 38, 34)
JPEG_CARD_QUALITIES = (75, 64, 55, 48, 40, 34)
AVIF_HERO_QUALITIES = (50, 44, 38, 32)


def source_files():
    found = []
    for dirpath, dirnames, filenames in os.walk(IMAGE_ROOT):
        dirnames[:] = [name for name in dirnames if name not in SKIP_TOP]
        rel_dir = os.path.relpath(dirpath, IMAGE_ROOT)
        if rel_dir == ".":
            continue
        top = rel_dir.split(os.sep)[0]
        if top in SKIP_TOP:
            continue
        for name in filenames:
            stem, ext = os.path.splitext(name)
            if ext.lower() not in SOURCE_EXT:
                continue
            if stem.endswith(tuple("-%d" % width for width in WIDTHS)):
                continue
            found.append(os.path.join(dirpath, name))
    found.sort()
    return found


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fingerprint():
    lines = [
        "widths %s avif %s webp %s jpeg %s %s"
        % (
            ",".join(str(width) for width in WIDTHS),
            AVIF_QUALITY,
            WEBP_QUALITY,
            JPEG_QUALITY,
            ENCODER_ID,
        )
    ]
    for path in source_files():
        rel = path.replace(os.sep, "/")
        lines.append("%s %s" % (rel, file_sha256(path)))
    payload = "\n".join(lines).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def rel_key(path):
    rel = os.path.relpath(path, IMAGE_ROOT).replace(os.sep, "/")
    return os.path.splitext(rel)[0]


def meta_path(key):
    return os.path.join(CACHE_META, key + ".json")


def variant_name(stem, width, ext):
    return "%s-%d%s" % (stem, width, ext)


def read_record(path):
    """Return a hash-matched cache record whose listed files are on disk.

    A new width can be missing. Callers that need every width use
    cached_record.
    """
    key = rel_key(path)
    meta = meta_path(key)
    if not os.path.exists(meta):
        return None
    try:
        with open(meta, encoding="utf-8") as handle:
            record = json.load(handle)
    except (OSError, ValueError):
        return None
    if record.get("hash") != file_sha256(path):
        return None
    if record.get("encoder") != ENCODER_ID:
        return None
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.dirname(path)
    for fmt, ext in (("avif", ".avif"), ("webp", ".webp"), ("jpeg", ".jpg")):
        for width in record.get(fmt) or []:
            cached = os.path.join(CACHE_OUT, folder, variant_name(stem, width, ext))
            if not os.path.exists(cached):
                return None
    return record


def widths_complete(record):
    src_w = int(record.get("width") or 0)
    expected = [width for width in WIDTHS if width <= src_w]
    for fmt in ("avif", "webp", "jpeg"):
        got = [int(width) for width in (record.get(fmt) or [])]
        if got != expected:
            return False
    return True


def cached_record(path):
    record = read_record(path)
    if not record or not widths_complete(record):
        return None
    return record


def cache_complete():
    files = source_files()
    if not files:
        return True
    return all(cached_record(path) for path in files)


def copy_record(path, record):
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    for fmt, ext in (("avif", ".avif"), ("webp", ".webp"), ("jpeg", ".jpg")):
        for width in record.get(fmt) or []:
            name = variant_name(stem, width, ext)
            src = os.path.join(CACHE_OUT, folder, name)
            dest = os.path.join(folder, name)
            if os.path.exists(src):
                shutil.copy2(src, dest)


def write_manifest(records):
    os.makedirs("_data", exist_ok=True)
    # The picture helper looks up the parent folder and the filename.
    # A city photo is bellevue/kelsey-creek. A pool photo is
    # hubs/fall/orchard, so the folder is fall and the stem is orchard.
    # Splitting only on the first slash would file that under hubs and
    # the helper would not find a srcset.
    nested = {}
    seen = {}
    for key in sorted(records):
        parts = key.split("/")
        if len(parts) < 2:
            continue
        folder, stem = parts[-2], parts[-1]
        slot = "%s/%s" % (folder, stem)
        prior = seen.get(slot)
        if prior and prior != key:
            print("variant key collision %s from %s and %s" % (slot, prior, key))
        seen[slot] = key
        nested.setdefault(folder, {})[stem] = records[key]
    count = 0
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        handle.write("# Generated by script/render-image-variants.py during the Pages build.\n")
        handle.write("# Do not edit. Do not commit. Missing entries fall back to the source file.\n")
        for folder in sorted(nested):
            handle.write("%s:\n" % folder)
            for stem in sorted(nested[folder]):
                record = nested[folder][stem]
                count += 1
                handle.write("  %s:\n" % stem)
                handle.write("    width: %d\n" % int(record["width"]))
                handle.write("    height: %d\n" % int(record["height"]))
                if record.get("fallback"):
                    handle.write("    fallback: %d\n" % int(record["fallback"]))
                for fmt in ("avif", "webp", "jpeg"):
                    widths = record.get(fmt) or []
                    if not widths:
                        continue
                    handle.write("    %s:\n" % fmt)
                    for width in widths:
                        handle.write("      - %d\n" % int(width))
    return count


def publish_from_cache():
    records = {}
    for path in source_files():
        record = cached_record(path)
        if not record:
            continue
        copy_record(path, record)
        records[rel_key(path)] = record
    count = write_manifest(records)
    print("Restored %d image(s) from cache." % count)


def open_image(path):
    from PIL import Image, ImageOps

    image = ImageOps.exif_transpose(Image.open(path))
    image.load()
    return image


def qualities_for(kind, width):
    if kind == "avif" and width <= 640:
        return AVIF_CARD_QUALITIES
    if kind == "jpeg" and width <= 640:
        return JPEG_CARD_QUALITIES
    if kind == "avif" and width >= 1200:
        return AVIF_HERO_QUALITIES
    if kind == "jpeg":
        return (JPEG_QUALITY,)
    if kind == "webp":
        return (WEBP_QUALITY,)
    return (AVIF_QUALITY,)


def byte_budget(kind, width):
    if kind == "avif" and width <= 640:
        return 60 * 1024
    if kind == "jpeg" and width <= 640:
        return 80 * 1024
    if kind == "avif" and width >= 1200:
        return 220 * 1024
    return None


def save_variant(image, dest, kind, quality):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if kind == "jpeg":
        flat = image.convert("RGB")
        flat.save(dest, "JPEG", quality=quality, optimize=True, progressive=True)
        return
    if kind == "webp":
        image.save(dest, "WEBP", quality=quality, method=4)
        return
    image.save(dest, "AVIF", quality=quality)


def save_within_budget(image, dest, kind, width):
    budget = byte_budget(kind, width)
    for quality in qualities_for(kind, width):
        save_variant(image, dest, kind, quality)
        if budget is None or os.path.getsize(dest) <= budget:
            return quality
    return qualities_for(kind, width)[-1]


def encode(path):
    key = rel_key(path)
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.dirname(path)
    try:
        image = open_image(path)
    except Exception as exc:
        print("  skip %s: %s" % (path, exc))
        return None
    src_w, src_h = image.size
    widths = [width for width in WIDTHS if width <= src_w]
    prior = read_record(path)
    if prior:
        record = prior
        record["width"] = src_w
        record["height"] = src_h
    else:
        record = {
            "hash": file_sha256(path),
            "encoder": ENCODER_ID,
            "width": src_w,
            "height": src_h,
            "avif": [],
            "webp": [],
            "jpeg": [],
        }
    record["encoder"] = ENCODER_ID
    if not widths:
        print("  %s is %dpx, narrower than 400. Original only." % (path, src_w))
        return None
    if image.mode not in ("RGB", "RGBA"):
        image = image.convert("RGB")
    from PIL import Image

    resample = Image.Resampling.LANCZOS
    frames = {}
    for width in widths:
        height = max(1, round(src_h * width / src_w))
        frames[width] = image.resize((width, height), resample) if width != src_w else image
    for kind, ext, field in (
        ("avif", ".avif", "avif"),
        ("webp", ".webp", "webp"),
        ("jpeg", ".jpg", "jpeg"),
    ):
        have = set(int(width) for width in (record.get(field) or []))
        built = []
        for width in widths:
            name = variant_name(stem, width, ext)
            cached = os.path.join(CACHE_OUT, folder, name)
            dest = os.path.join(folder, name)
            if width in have and os.path.exists(cached):
                os.makedirs(folder, exist_ok=True)
                shutil.copy2(cached, dest)
                built.append(width)
                continue
            try:
                save_within_budget(frames[width], cached, kind, width)
                os.makedirs(folder, exist_ok=True)
                shutil.copy2(cached, dest)
            except Exception as exc:
                print("  skip %s: %s" % (name, exc))
                continue
            built.append(width)
            print("  %s (%dK)" % (os.path.join(folder, name), os.path.getsize(dest) // 1024))
        record[field] = built
    if not (record["avif"] or record["webp"] or record["jpeg"]):
        return None
    jpeg_widths = record["jpeg"]
    if jpeg_widths:
        record["fallback"] = 800 if 800 in jpeg_widths else jpeg_widths[-1]
    os.makedirs(os.path.dirname(meta_path(key)), exist_ok=True)
    with open(meta_path(key), "w", encoding="utf-8") as handle:
        json.dump(record, handle)
    return record


def generate():
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("Pillow is not installed. Serving original images.")
        write_manifest({})
        return
    records = {}
    for path in source_files():
        existing = cached_record(path)
        if existing:
            copy_record(path, existing)
            records[rel_key(path)] = existing
            print("cached %s" % path)
            continue
        print(path)
        record = encode(path)
        if record:
            records[rel_key(path)] = record
    count = write_manifest(records)
    print("Manifest lists %d image(s)." % count)


def main():
    if "--fingerprint" in sys.argv:
        print(fingerprint())
        return
    if "--check-cache" in sys.argv:
        sys.exit(0 if cache_complete() else 1)
    if "--from-cache" in sys.argv:
        publish_from_cache()
        return
    generate()


if __name__ == "__main__":
    main()

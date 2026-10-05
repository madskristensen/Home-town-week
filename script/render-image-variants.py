#!/usr/bin/env python3
"""Build the fixed AVIF and JPEG names during the Pages deploy.

Every card photo gets name-400.avif, name-640.avif, and name-640.jpg.
Every city hero also gets name-800.avif, name-1200.avif, and
name-1600.avif. A master narrower than a target is scaled up so the
width in the filename is the pixel width. A master longer than 1600px,
or 2000px for a city hero, is capped in the cache and copied over the
file Jekyll published to _site. The repo original is not changed.
Nothing here is committed. Actions caches .image-cache on a hash of
the masters and this encoder.

    python3 script/render-image-variants.py --fingerprint
    python3 script/render-image-variants.py --check-cache
    python3 script/render-image-variants.py --from-cache
    python3 script/render-image-variants.py
    python3 script/render-image-variants.py --publish-site

A referenced photo that cannot be encoded fails the build.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

IMAGE_ROOT = os.path.join("assets", "images")
CACHE_ROOT = ".image-cache"
CACHE_OUT = os.path.join(CACHE_ROOT, "out")
CACHE_META = os.path.join(CACHE_ROOT, "meta")
CACHE_MASTERS = os.path.join(CACHE_ROOT, "masters")
SKIP_TOP = {"cities", "og", "share"}
SKIP_NAMES = {"logo.png", "apple-touch-icon.png", "favicon.png"}
SOURCE_EXT = {".webp", ".jpg", ".jpeg", ".png"}
CARD_AVIF = (400, 640)
HERO_AVIF = (400, 640, 800, 1200, 1600)
JPEG_WIDTH = 640
AVIF_QUALITY = 60
JPEG_QUALITY = 75
CARD_MASTER_CAP = 1600
HERO_MASTER_CAP = 2000
MASTER_WEBP_QUALITY = 82
MASTER_JPEG_QUALITY = 85
ENCODER_ID = "fixed-card-400-640-jpg640-hero-800-1200-1600"
VARIANT_RE = re.compile(r"-(?:400|640|800|960|1200|1280|1600)$")


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


def is_hero(path, heroes):
    return path.replace(os.sep, "/") in heroes


def avif_widths(path, heroes):
    if is_hero(path, heroes):
        return HERO_AVIF
    return CARD_AVIF


def source_files():
    found = []
    for dirpath, dirnames, filenames in os.walk(IMAGE_ROOT):
        dirnames[:] = [name for name in dirnames if name not in SKIP_TOP]
        rel_dir = os.path.relpath(dirpath, IMAGE_ROOT)
        if rel_dir == ".":
            continue
        for name in filenames:
            if name in SKIP_NAMES or name.startswith("icon-"):
                continue
            stem, ext = os.path.splitext(name)
            if ext.lower() not in SOURCE_EXT:
                continue
            if VARIANT_RE.search(stem):
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
    lines = ["encoder %s avif %s jpeg %s" % (ENCODER_ID, AVIF_QUALITY, JPEG_QUALITY)]
    for path in source_files():
        lines.append("%s %s" % (path.replace(os.sep, "/"), file_sha256(path)))
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
    for fmt, ext in (("avif", ".avif"), ("jpeg", ".jpg")):
        for width in record.get(fmt) or []:
            cached = os.path.join(CACHE_OUT, folder, variant_name(stem, int(width), ext))
            if not os.path.exists(cached):
                return None
    return record


def widths_complete(path, record, heroes):
    avif = [int(width) for width in (record.get("avif") or [])]
    jpeg = [int(width) for width in (record.get("jpeg") or [])]
    return avif == list(avif_widths(path, heroes)) and jpeg == [JPEG_WIDTH]


def cached_record(path, heroes):
    record = read_record(path)
    if not record or not widths_complete(path, record, heroes):
        return None
    return record


def cache_complete(heroes):
    files = source_files()
    if not files:
        return True
    return all(cached_record(path, heroes) for path in files)


def copy_record(path, record):
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    for fmt, ext in (("avif", ".avif"), ("jpeg", ".jpg")):
        for width in record.get(fmt) or []:
            name = variant_name(stem, int(width), ext)
            src = os.path.join(CACHE_OUT, folder, name)
            dest = os.path.join(folder, name)
            if os.path.exists(src):
                shutil.copy2(src, dest)


def open_image(path):
    from PIL import Image, ImageOps

    image = ImageOps.exif_transpose(Image.open(path))
    image.load()
    if image.mode not in ("RGB", "RGBA"):
        image = image.convert("RGB")
    return image


def frame_at(image, width):
    from PIL import Image

    if width == image.width:
        return image
    height = max(1, round(image.height * width / image.width))
    return image.resize((width, height), Image.Resampling.LANCZOS)


def save_variant(image, dest, kind):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if kind == "jpeg":
        image.convert("RGB").save(
            dest, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True
        )
        return
    image.convert("RGB").save(dest, "AVIF", quality=AVIF_QUALITY)


def encode(path, heroes):
    key = rel_key(path)
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.dirname(path)
    image = open_image(path)
    widths = list(avif_widths(path, heroes))
    record = {
        "hash": file_sha256(path),
        "encoder": ENCODER_ID,
        "width": image.width,
        "height": image.height,
        "avif": [],
        "jpeg": [],
    }
    built = []
    for width in widths:
        name = variant_name(stem, width, ".avif")
        cached = os.path.join(CACHE_OUT, folder, name)
        dest = os.path.join(folder, name)
        save_variant(frame_at(image, width), cached, "avif")
        os.makedirs(folder, exist_ok=True)
        shutil.copy2(cached, dest)
        built.append(width)
        print("  %s (%dK)" % (dest, os.path.getsize(dest) // 1024))
    record["avif"] = built
    name = variant_name(stem, JPEG_WIDTH, ".jpg")
    cached = os.path.join(CACHE_OUT, folder, name)
    dest = os.path.join(folder, name)
    save_variant(frame_at(image, JPEG_WIDTH), cached, "jpeg")
    shutil.copy2(cached, dest)
    record["jpeg"] = [JPEG_WIDTH]
    print("  %s (%dK)" % (dest, os.path.getsize(dest) // 1024))
    os.makedirs(os.path.dirname(meta_path(key)), exist_ok=True)
    with open(meta_path(key), "w", encoding="utf-8") as handle:
        json.dump(record, handle)
    return record


def require_variants():
    script = os.path.join("script", "check-image-variants.py")
    result = subprocess.call([sys.executable, script])
    if result != 0:
        sys.exit(result)


def master_cap(path, heroes):
    if is_hero(path, heroes):
        return HERO_MASTER_CAP
    return CARD_MASTER_CAP


def capped_cache_path(path):
    return os.path.join(CACHE_MASTERS, path)


def master_long_side(path):
    from PIL import Image, ImageOps

    with Image.open(path) as image:
        exif = image.getexif()
        orientation = exif.get(274) if exif else None
        if orientation and orientation != 1:
            image = ImageOps.exif_transpose(image)
        return max(image.width, image.height)


def oriented_image(path):
    from PIL import Image, ImageOps

    image = ImageOps.exif_transpose(Image.open(path))
    image.load()
    return image


def frame_within(image, cap):
    from PIL import Image

    long_side = max(image.width, image.height)
    if long_side <= cap:
        return image
    if image.width >= image.height:
        width = cap
        height = max(1, round(image.height * cap / image.width))
    else:
        height = cap
        width = max(1, round(image.width * cap / image.height))
    return image.resize((width, height), Image.Resampling.LANCZOS)


def save_master(image, dest, ext):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if ext in {".jpg", ".jpeg"}:
        image.convert("RGB").save(
            dest, "JPEG", quality=MASTER_JPEG_QUALITY, optimize=True, progressive=True
        )
        return
    if ext == ".webp":
        if image.mode not in ("RGB", "RGBA"):
            bands = image.getbands()
            image = image.convert("RGBA" if bands and "A" in bands else "RGB")
        image.save(dest, "WEBP", quality=MASTER_WEBP_QUALITY, method=6)
        return
    if image.mode == "P":
        image = image.convert("RGBA" if "transparency" in image.info else "RGB")
    elif image.mode not in ("RGB", "RGBA"):
        bands = image.getbands()
        image = image.convert("RGBA" if bands and "A" in bands else "RGB")
    image.save(dest, "PNG", optimize=True)


def drop_capped(path):
    cached = capped_cache_path(path)
    for extra in (cached, cached + ".sha256"):
        if os.path.exists(extra):
            os.remove(extra)


def capped_stamp(path, cap):
    return "%s %d" % (file_sha256(path), cap)


def capped_current(path, cap):
    cached = capped_cache_path(path)
    stamp = cached + ".sha256"
    if not os.path.exists(cached) or not os.path.exists(stamp):
        return False
    with open(stamp, encoding="utf-8") as handle:
        return handle.read().strip() == capped_stamp(path, cap)


def write_capped(path, heroes):
    """Write a capped copy into the cache. Does not touch the repo file."""
    cap = master_cap(path, heroes)
    ext = os.path.splitext(path)[1].lower()
    dest = capped_cache_path(path)
    tmp = dest + ".tmp"
    try:
        image = oriented_image(path)
        try:
            resized = frame_within(image, cap)
            long_side = max(resized.width, resized.height)
            save_master(resized, tmp, ext)
        finally:
            image.close()
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    with open(dest + ".sha256", "w", encoding="utf-8") as handle:
        handle.write(capped_stamp(path, cap))
    print("capped master %s -> cache (%dpx, cap %d)" % (path, long_side, cap))


def ensure_capped_masters(heroes):
    capped = 0
    for path in source_files():
        cap = master_cap(path, heroes)
        long_side = master_long_side(path)
        if long_side <= cap:
            drop_capped(path)
            continue
        if not capped_current(path, cap):
            write_capped(path, heroes)
        capped += 1
    if capped:
        print("%d capped master(s) in cache." % capped)
    else:
        print("no oversized masters")
    return capped


def publish_site(heroes):
    if not os.path.isdir("_site"):
        sys.exit("_site is missing, so capped masters were not published")
    ensure_capped_masters(heroes)
    copied = 0
    for path in source_files():
        cached = capped_cache_path(path)
        if not os.path.exists(cached):
            continue
        dest = os.path.join("_site", path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(cached, dest)
        source_hash = file_sha256(path)
        published_hash = file_sha256(dest)
        if published_hash == source_hash:
            sys.exit("capped master matches the repo file for %s" % path)
        copied += 1
        print("published %s" % dest)
    print("Published %d capped master(s) to _site." % copied)


def publish_from_cache(heroes):
    for path in source_files():
        record = cached_record(path, heroes)
        if not record:
            sys.exit("image cache is missing %s" % path)
        copy_record(path, record)
    print("Restored %d image(s) from cache." % len(source_files()))
    ensure_capped_masters(heroes)
    require_variants()


def generate(heroes):
    try:
        import PIL  # noqa: F401
        import pillow_avif  # noqa: F401
    except ImportError:
        sys.exit("Pillow and pillow-avif-plugin are required")
    failed = []
    for path in source_files():
        existing = cached_record(path, heroes)
        if existing:
            copy_record(path, existing)
            print("cached %s" % path)
            continue
        print(path)
        try:
            encode(path, heroes)
        except Exception as exc:
            print("  failed %s: %s" % (path, exc))
            failed.append(path)
    if failed:
        sys.exit("could not encode %d photo(s)" % len(failed))
    try:
        ensure_capped_masters(heroes)
    except Exception as exc:
        sys.exit("could not cap masters: %s" % exc)
    require_variants()


def main():
    heroes = hero_paths()
    if "--fingerprint" in sys.argv:
        print(fingerprint())
        return
    if "--check-cache" in sys.argv:
        sys.exit(0 if cache_complete(heroes) else 1)
    if "--from-cache" in sys.argv:
        publish_from_cache(heroes)
        return
    if "--publish-site" in sys.argv:
        publish_site(heroes)
        return
    generate(heroes)


if __name__ == "__main__":
    main()

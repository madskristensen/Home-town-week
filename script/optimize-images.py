#!/usr/bin/env python3
"""Resize photo masters and commit the AVIF widths templates use.

A master wider than 1600px is scaled down. A city hero may be 2000px.
The script then writes AVIF at 400, 640, 800, 1200, and 1600, never
wider than the master, plus the one JPEG the card uses as its fallback.
Files that already match the stamp are left untouched.

  python3 script/optimize-images.py --all
  python3 script/optimize-images.py --missing
  python3 script/optimize-images.py --check
  python3 script/optimize-images.py --since <git-rev>
"""

import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGE_ROOT = "assets/images"
STAMP_PATH = os.path.join("_data", "image_optimize.json")
CARD_MAX = 1600
HERO_MAX = 2000
SKIP_TOP = {"cities", "og", "share"}
SKIP_NAMES = {"logo.png", "apple-touch-icon.png", "favicon.png"}
# A master this heavy per pixel is worth a high-quality recompress.
BLOAT_BPP = 0.45


def load_encoder():
    path = os.path.join(ROOT, "script", "render-image-variants.py")
    spec = importlib.util.spec_from_file_location("render_image_variants", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def variant_widths():
    return (400, 640, 800, 1200, 1600)


def is_variant_name(name):
    stem, _ext = os.path.splitext(name)
    return stem.endswith(tuple("-%d" % width for width in variant_widths()))


def is_source(path):
    rel = path.replace(os.sep, "/")
    if not rel.startswith(IMAGE_ROOT + "/"):
        return False
    rest = rel[len(IMAGE_ROOT) + 1:]
    top = rest.split("/")[0]
    if top in SKIP_TOP:
        return False
    name = os.path.basename(rest)
    if name in SKIP_NAMES or name.startswith("icon-"):
        return False
    if is_variant_name(name):
        return False
    ext = os.path.splitext(name)[1].lower()
    return ext in {".jpg", ".jpeg", ".png", ".webp"}


def source_files():
    found = []
    for dirpath, dirnames, filenames in os.walk(IMAGE_ROOT):
        dirnames[:] = [name for name in dirnames if name not in SKIP_TOP]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if is_source(path.replace(os.sep, "/")):
                found.append(path)
    found.sort()
    return found


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
        raw = match.group(1).strip().strip('"').strip("'")
        found.add(raw.lstrip("/"))
    return found


def max_width_for(path, heroes):
    rel = path.replace(os.sep, "/")
    if rel in heroes or rel.lstrip("./") in heroes:
        return HERO_MAX
    return CARD_MAX


def load_stamp():
    if not os.path.exists(STAMP_PATH):
        return {}
    try:
        with open(STAMP_PATH, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {}
    images = data.get("images")
    return images if isinstance(images, dict) else {}


def save_stamp(images, encoder_id):
    os.makedirs("_data", exist_ok=True)
    payload = {
        "encoder": encoder_id,
        "card_max": CARD_MAX,
        "hero_max": HERO_MAX,
        "images": {key: images[key] for key in sorted(images)},
    }
    with open(STAMP_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def variant_path(path, width, ext):
    folder = os.path.dirname(path)
    stem = os.path.splitext(os.path.basename(path))[0]
    return os.path.join(folder, "%s-%d%s" % (stem, width, ext))


def outputs_present(path, info):
    for width in info.get("avif") or []:
        if not os.path.exists(variant_path(path, int(width), ".avif")):
            return False
    for width in info.get("jpeg") or []:
        if not os.path.exists(variant_path(path, int(width), ".jpg")):
            return False
    return True


def up_to_date(path, info, encoder_id):
    if not info or info.get("encoder") != encoder_id:
        return False
    if info.get("hash") != file_sha256(path):
        return False
    return outputs_present(path, info)


def jpeg_fallback(source_width):
    choices = [width for width in variant_widths() if width <= source_width]
    if not choices:
        return None
    if 800 in choices:
        return 800
    return choices[-1]


def save_master(image, path, resized):
    ext = os.path.splitext(path)[1].lower()
    temp = path + ".optimizing"
    if ext in {".jpg", ".jpeg"}:
        image.convert("RGB").save(temp, "JPEG", quality=85, optimize=True, progressive=True)
    elif ext == ".webp":
        image.save(temp, "WEBP", quality=84, method=6)
    elif ext == ".png":
        image.save(temp, "PNG", optimize=True)
    else:
        return False
    new_size = os.path.getsize(temp)
    old_size = os.path.getsize(path)
    if resized or new_size < old_size * 0.6:
        os.replace(temp, path)
        return True
    os.remove(temp)
    return False


def remove_outputs(path, info):
    widths = set()
    for key in ("avif", "jpeg"):
        for width in (info or {}).get(key) or []:
            widths.add(int(width))
    widths.update(variant_widths())
    for width in widths:
        for ext in (".avif", ".jpg"):
            target = variant_path(path, width, ext)
            if os.path.exists(target):
                os.remove(target)


def prepare_image(path, heroes):
    from PIL import Image, ImageOps

    before = os.path.getsize(path)
    image = ImageOps.exif_transpose(Image.open(path))
    image.load()
    src_w, src_h = image.size
    limit = max_width_for(path, heroes)
    resized = src_w > limit
    if resized:
        height = max(1, round(src_h * limit / src_w))
        image = image.resize((limit, height), Image.Resampling.LANCZOS)
    bpp = before / float(src_w * src_h)
    if resized or bpp > BLOAT_BPP:
        save_master(image, path, resized)
    if image.mode not in ("RGB", "RGBA"):
        image = image.convert("RGB")
    return image, before, os.path.getsize(path)


def build_variants(riv, path, image):
    from PIL import Image

    src_w, src_h = image.size
    widths = [width for width in riv.WIDTHS if width <= src_w]
    frames = {}
    for width in widths:
        height = max(1, round(src_h * width / src_w))
        if width == src_w:
            frames[width] = image
        else:
            frames[width] = image.resize((width, height), Image.Resampling.LANCZOS)
    avif = []
    for width in widths:
        dest = variant_path(path, width, ".avif")
        riv.save_within_budget(frames[width], dest, "avif", width)
        avif.append(width)
        print("  %s (%dK)" % (dest, os.path.getsize(dest) // 1024))
    fallback = jpeg_fallback(src_w)
    jpeg = []
    if fallback:
        dest = variant_path(path, fallback, ".jpg")
        riv.save_within_budget(frames[fallback], dest, "jpeg", fallback)
        jpeg.append(fallback)
        print("  %s (%dK)" % (dest, os.path.getsize(dest) // 1024))
    # Drop widths we no longer generate so an old 1600 file does not linger
    # after a master gets narrower.
    keep_avif = set(avif)
    keep_jpeg = set(jpeg)
    for width in riv.WIDTHS:
        if width not in keep_avif:
            stale = variant_path(path, width, ".avif")
            if os.path.exists(stale):
                os.remove(stale)
        if width not in keep_jpeg:
            stale = variant_path(path, width, ".jpg")
            if os.path.exists(stale) and width in (400, 640, 800):
                os.remove(stale)
    return {
        "width": src_w,
        "height": src_h,
        "avif": avif,
        "jpeg": jpeg,
        "fallback": fallback,
    }


def stamp_entry(path, built, encoder_id):
    entry = {
        "hash": file_sha256(path),
        "encoder": encoder_id,
        "width": built["width"],
        "height": built["height"],
        "avif": built["avif"],
        "jpeg": built["jpeg"],
    }
    if built.get("fallback"):
        entry["fallback"] = built["fallback"]
    return entry


def record_for(path, info):
    record = {
        "width": info["width"],
        "height": info["height"],
        "avif": info.get("avif") or [],
        "webp": [],
        "jpeg": info.get("jpeg") or [],
    }
    if info.get("fallback"):
        record["fallback"] = info["fallback"]
    return record


def write_records(riv, images):
    records = {}
    for path in sorted(images):
        records[riv.rel_key(path)] = record_for(path, images[path])
    count = riv.write_manifest(records)
    print("Manifest lists %d image(s)." % count)


def process(paths, images, riv, heroes, force):
    encoder_id = riv.ENCODER_ID
    resized_bytes = 0
    master_before = 0
    master_after = 0
    changed = 0
    skipped = 0
    for path in paths:
        info = images.get(path.replace(os.sep, "/")) or images.get(path)
        key = path.replace(os.sep, "/")
        if not os.path.exists(path):
            if key in images:
                remove_outputs(path, images[key])
                del images[key]
                changed += 1
                print("removed %s" % key)
            continue
        if not force and up_to_date(path, images.get(key), encoder_id):
            skipped += 1
            continue
        print(path)
        image, before, after_master = prepare_image(path, heroes)
        built = build_variants(riv, path, image)
        images[key] = stamp_entry(path, built, encoder_id)
        master_before += before
        master_after += os.path.getsize(path)
        resized_bytes += before - os.path.getsize(path)
        changed += 1
    return {
        "changed": changed,
        "skipped": skipped,
        "master_before": master_before,
        "master_after": master_after,
        "master_saved": resized_bytes,
    }


def check(images, encoder_id):
    missing = []
    for path in source_files():
        key = path.replace(os.sep, "/")
        if not up_to_date(path, images.get(key), encoder_id):
            missing.append(key)
    return missing


def since_paths(rev):
    if not rev or set(rev) <= {"0"}:
        return None
    try:
        out = subprocess.check_output(
            ["git", "diff", "--name-only", rev, "HEAD", "--", IMAGE_ROOT],
            text=True,
        )
    except subprocess.CalledProcessError:
        return None
    paths = []
    for line in out.splitlines():
        rel = line.strip()
        if is_source(rel):
            paths.append(rel)
        elif rel.startswith(IMAGE_ROOT + "/") and not os.path.exists(rel):
            paths.append(rel)
    return paths


def main():
    os.chdir(ROOT)
    riv = load_encoder()
    images = load_stamp()
    if "--check" in sys.argv:
        missing = check(images, riv.ENCODER_ID)
        if missing:
            print("%d photo(s) need optimize." % len(missing))
            sys.exit(1)
        print("Optimized photos are current (%d)." % len(source_files()))
        return
    heroes = hero_paths()
    force = False
    if "--all" in sys.argv:
        paths = source_files()
    elif "--missing" in sys.argv:
        paths = check(images, riv.ENCODER_ID)
    elif "--since" in sys.argv:
        index = sys.argv.index("--since")
        rev = sys.argv[index + 1] if index + 1 < len(sys.argv) else ""
        paths = since_paths(rev)
        if paths is None:
            paths = source_files()
    else:
        print("Pass --all, --missing, --check, or --since <rev>.")
        sys.exit(2)
    if not paths:
        print("No photos to optimize.")
        return
    stats = process(paths, images, riv, heroes, force)
    if stats["changed"]:
        save_stamp(images, riv.ENCODER_ID)
        write_records(riv, images)
    print(
        "Changed %d, skipped %d, master bytes %d -> %d (saved %d)."
        % (
            stats["changed"],
            stats["skipped"],
            stats["master_before"],
            stats["master_after"],
            stats["master_saved"],
        )
    )


if __name__ == "__main__":
    main()

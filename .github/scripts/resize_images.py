#!/usr/bin/env python3
"""Generate the same AVIF and JPEG names for every photo.

Every card photo gets name-400.avif, name-640.avif, and name-640.jpg.
Every city hero gets those plus name-800.avif, name-1200.avif, and
name-1600.avif. The pixel width matches the number in the filename,
so a master that is already smaller is scaled up. The original stays
in git. There is no WebP tier and no extra width for one photo.

Safe to re-run. Outputs are rebuilt when the source content changes
(sha256 of the original), not when mtime says the source is newer.
GitHub Actions checkout gives every file the same (or newer) mtime, so
comparing timestamps would skip a swapped photo and leave stale AVIFs.
"""

import os
import io
import re
import sys
import glob
import hashlib
import struct

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

try:
    # Registers the AVIF plugin on Pillow builds that lack it. Recent
    # Pillow has AVIF built in, so a missing plugin is not an error.
    import pillow_avif  # noqa: F401
except ImportError:
    pass

IMAGE_ROOT = os.path.join("assets", "images")
DATA_FILE = os.path.join("_data", "image_variants.yml")
SKIP_TOP = {"cities", "og", "share"}
SKIP_NAMES = {"logo.png", "apple-touch-icon.png", "favicon.png"}

# Cards ask for 400 and 640. Heroes also ask for the wider steps.
# A width equal to the master is written once, as the full-size AVIF.
CARD_WIDTHS = (400, 640)
HERO_WIDTHS = (800, 1200, 1600)
JPEG_FALLBACK = 640

# The only generated tier. Quality 60 measured indistinguishable at 1:1
# against our previous WebP output while running noticeably smaller.
AVIF_QUALITY = 60
JPEG_QUALITY = 75

# name-640.avif. Real photos such as station-16.webp are not variants.
VARIANT_RE = re.compile(
    r"-(?:400|640|800|960|1200|1280|1600)$"
)


def hero_paths():
    """City hero masters. Everything else is a card photo."""
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
        raw = match.group(1).strip().strip('"').strip("'").lstrip("/")
        found.add(raw)
    return found


def is_variant(stem):
    return bool(VARIANT_RE.search(stem))


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
    stem, ext = os.path.splitext(name)
    if ext.lower() not in (".webp", ".jpg", ".jpeg", ".png"):
        return False
    if is_variant(stem):
        return False
    return True


def source_files():
    found = []
    for dirpath, dirnames, filenames in os.walk(IMAGE_ROOT):
        dirnames[:] = [name for name in dirnames if name not in SKIP_TOP]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if is_source(path):
                found.append(path)
    found.sort()
    return found


def file_sha256(path):
    with open(path, "rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def load_source_hashes(path):
    """Read source_hash values from a previous manifest, if any.

    The file is tiny and we write it ourselves, so a line scan is enough
    and we do not need a YAML library in CI. Keys are folder/stem because
    the same filename shows up under more than one city.
    """
    hashes = {}
    if not os.path.exists(path):
        return hashes
    folder = None
    stem = None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            if re.match(r"^\S[^:]*:\s*$", line):
                folder = line.split(":", 1)[0]
                stem = None
            elif folder and re.match(r"^  \S[^:]*:\s*$", line):
                stem = line.strip().split(":", 1)[0]
            elif stem and line.strip().startswith("source_hash:"):
                hashes["%s/%s" % (folder, stem)] = line.split(":", 1)[1].strip()
    return hashes


def variant_current(out, source_changed):
    """Keep an existing file only when the source bytes have not changed.

    A missing stored hash is treated as unknown, not as a change, so the
    first run after this logic lands can record hashes without rewriting
    every variant. A swapped photo still rebuilds: either its hash no
    longer matches, or the stale files were deleted so they are missing.
    """
    return os.path.exists(out) and not source_changed


def widths_for(path, heroes):
    """The fixed set. Cards and heroes do not get a custom list."""
    rel = path.replace(os.sep, "/")
    if rel in heroes:
        return list(CARD_WIDTHS) + [width for width in HERO_WIDTHS if width not in CARD_WIDTHS]
    return list(CARD_WIDTHS)


def frame_at(im, width):
    if width == im.width:
        return im
    height = max(1, round(im.height * width / im.width))
    return im.resize((width, height), Image.LANCZOS)


def remove_stale(path, keep_avif, keep_jpeg):
    folder = os.path.dirname(path)
    stem = os.path.splitext(os.path.basename(path))[0]
    prefix = stem + "-"
    if not os.path.isdir(folder):
        return
    for name in os.listdir(folder):
        if not name.startswith(prefix):
            continue
        rest = name[len(prefix):]
        match = re.match(r"(\d+)\.(avif|jpe?g)$", rest)
        if not match:
            continue
        width = int(match.group(1))
        ext = match.group(2)
        if ext == "avif" and width not in keep_avif:
            os.remove(os.path.join(folder, name))
        elif ext in ("jpg", "jpeg") and width not in keep_jpeg:
            os.remove(os.path.join(folder, name))


def build(path, heroes, prev_hash=None):
    """Write the fixed set for one original. Return None when a file is missing."""
    stem, _ext = os.path.splitext(os.path.basename(path))
    if is_variant(stem):
        return None

    try:
        im = Image.open(path)
        im.load()
    except Exception as exc:
        print("  unreadable %s: %s" % (path, exc))
        return None

    im = im.convert("RGB")
    src_hash = file_sha256(path)
    # None != hash would look like a change and rewrite every AVIF on
    # the first run. Only a known previous hash that differs counts.
    source_changed = prev_hash is not None and prev_hash != src_hash
    out_dir = os.path.dirname(path)
    widths = widths_for(path, heroes)

    for width in widths:
        out = os.path.join(out_dir, "%s-%d.avif" % (stem, width))
        if variant_current(out, source_changed):
            continue
        try:
            frame_at(im, width).save(out, "AVIF", quality=AVIF_QUALITY)
        except Exception as exc:
            print("  avif failed %s: %s" % (os.path.basename(out), exc))
            continue
        print("  wrote %s (%dK)" % (os.path.basename(out), os.path.getsize(out) // 1024))

    jpg = os.path.join(out_dir, "%s-%d.jpg" % (stem, JPEG_FALLBACK))
    if not variant_current(jpg, source_changed):
        try:
            frame_at(im, JPEG_FALLBACK).save(
                jpg, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True
            )
            print("  wrote %s (%dK)" % (os.path.basename(jpg), os.path.getsize(jpg) // 1024))
        except Exception as exc:
            print("  jpeg failed %s: %s" % (os.path.basename(jpg), exc))

    remove_stale(path, set(widths), {JPEG_FALLBACK})
    missing = []
    for width in widths:
        name = "%s-%d.avif" % (stem, width)
        if not os.path.exists(os.path.join(out_dir, name)):
            missing.append(name)
    if not os.path.exists(jpg):
        missing.append(os.path.basename(jpg))
    if missing:
        print("  missing %s" % ", ".join(missing))
        return None
    return {
        "width": im.width,
        "height": im.height,
        "source_hash": src_hash,
    }


def strip_webp_metadata(path):
    """Drop EXIF/ICC/XMP from a WebP without touching the image data.

    This is the one genuinely lossless win available on WebP. We rebuild
    the RIFF container keeping only the image chunks, so the compressed
    VP8 payload is copied byte for byte and never re-encoded. A phone
    export carrying EXIF and a Display P3 profile sheds about 6%.

    Ours are already clean, so this normally does nothing. It matters
    when someone uploads a WebP straight from a camera or an editor.
    """
    meta = {b"EXIF", b"XMP ", b"ICCP"}

    with open(path, "rb") as handle:
        data = handle.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return 0

    chunks, off = [], 12
    while off + 8 <= len(data):
        cid = data[off:off + 4]
        size = struct.unpack("<I", data[off + 4:off + 8])[0]
        end = off + 8 + size + (size & 1)
        chunks.append((cid, data[off:end]))
        off = end

    if not any(cid in meta for cid, _raw in chunks):
        return 0

    ids = {cid for cid, _raw in chunks}
    # Animation needs VP8X to survive and its frame layout is a different
    # problem, so leave those alone rather than risk corrupting them.
    if b"ANIM" in ids or b"ANMF" in ids:
        return 0

    kept = [(cid, raw) for cid, raw in chunks if cid not in meta]

    # VP8X exists to advertise optional features in a leading 10 byte
    # chunk. Having stripped ICC and EXIF we must clear those flag bits,
    # or a decoder will look for chunks that are no longer there. With
    # no features left the extended form is pointless, so drop VP8X and
    # emit the plain single-chunk file a simple decoder expects.
    has_alpha = b"ALPH" in ids
    if not has_alpha:
        kept = [(cid, raw) for cid, raw in kept if cid != b"VP8X"]

    if any(cid == b"VP8X" for cid, _raw in kept):
        # Alpha still needs the extended form. Rewrite the flags,
        # keeping only the alpha bit (0x10).
        rebuilt = []
        for cid, raw in kept:
            if cid == b"VP8X":
                payload = bytearray(raw[8:8 + 10])
                payload[0] &= 0x10
                rebuilt.append((cid, raw[:8] + bytes(payload)))
            else:
                rebuilt.append((cid, raw))
        kept = rebuilt

    body = b"".join(raw for _cid, raw in kept)
    out = b"RIFF" + struct.pack("<I", len(body) + 4) + b"WEBP" + body
    if len(out) >= len(data):
        return 0

    # Never write a file we cannot read back.
    try:
        Image.open(io.BytesIO(out)).load()
    except Exception as exc:
        print("  skip strip on %s: %s" % (os.path.basename(path), exc))
        return 0

    with open(path, "wb") as handle:
        handle.write(out)
    return len(data) - len(out)


def optimise_pngs():
    """Losslessly shrink the PNGs we ship.

    optimize=True retries zlib settings and picks the smallest. Pixels are
    untouched, so this is safe for icons where any artefact would show. It
    does not always win (tiny files can grow when the filter table costs
    more than it saves), so we only keep a result that is actually smaller.
    """
    print("Optimising PNGs...")
    for path in sorted(glob.glob(os.path.join(IMAGE_ROOT, "*.png"))):
        before = os.path.getsize(path)
        im = Image.open(path)
        buf = io.BytesIO()
        # Preserve transparency: favicons are RGBA and must stay that way.
        im.save(buf, "PNG", optimize=True)
        after = buf.tell()
        if after < before:
            with open(path, "wb") as handle:
                handle.write(buf.getvalue())
            print("  %s: %dK -> %dK (%d%% smaller)" % (
                os.path.basename(path),
                before // 1024,
                after // 1024,
                (before - after) * 100 // before,
            ))


def write_manifest(records):
    """Folder then filename, matching the picture helper's lookup."""
    nested = {}
    seen = {}
    for key in sorted(records):
        parts = key.split("/")
        if len(parts) < 2:
            continue
        # A hub photo is hubs/fall/orchard, so the helper's folder is fall.
        folder, stem = parts[-2], parts[-1]
        slot = "%s/%s" % (folder, stem)
        prior = seen.get(slot)
        if prior and prior != key:
            print("variant key collision %s from %s and %s" % (slot, prior, key))
        seen[slot] = key
        nested.setdefault(folder, {})[stem] = records[key]

    os.makedirs("_data", exist_ok=True)
    with open(DATA_FILE, "w", encoding="utf-8") as handle:
        handle.write("# Generated by .github/scripts/resize_images.py. Do not edit.\n")
        handle.write("# source_hash: sha256 of the original. Variants rebuild when\n")
        handle.write("# it changes, because checkout mtimes are not trustworthy.\n")
        handle.write("# Filenames are fixed. Cards are name-400.avif, name-640.avif,\n")
        handle.write("# and name-640.jpg. Heroes add 800, 1200, and 1600 AVIF.\n")
        for folder in sorted(nested):
            handle.write("%s:\n" % folder)
            for stem in sorted(nested[folder]):
                record = nested[folder][stem]
                handle.write("  %s:\n" % stem)
                handle.write("    width: %d\n" % record["width"])
                handle.write("    height: %d\n" % record["height"])
                handle.write("    source_hash: %s\n" % record["source_hash"])
    return len(records)


def main():
    heroes = hero_paths()
    print("Stripping WebP metadata...")
    for path in source_files():
        if not path.lower().endswith(".webp"):
            continue
        saved = strip_webp_metadata(path)
        if saved:
            print("  %s: %d bytes of metadata removed" % (
                os.path.basename(path), saved
            ))

    prev = load_source_hashes(DATA_FILE)
    records = {}
    failed = []
    print("Generating variants...")
    for path in source_files():
        rel = os.path.splitext(path.replace(os.sep, "/"))[0]
        rel = rel[len(IMAGE_ROOT) + 1:]
        folder, stem = rel.rsplit("/", 1) if "/" in rel else ("", rel)
        # The manifest key is the parent folder, not hubs/.
        key = "%s/%s" % (folder.split("/")[-1], stem)
        record = build(path, heroes, prev.get(key))
        if record:
            records[rel] = record
        else:
            failed.append(path)

    if failed:
        sys.exit("required variants missing for %d photo(s)" % len(failed))

    count = write_manifest(records)
    print("\nWrote %s with %d image(s).\n" % (DATA_FILE, count))
    optimise_pngs()


if __name__ == "__main__":
    main()

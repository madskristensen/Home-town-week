#!/usr/bin/env python3
"""Review photo and suggestion uploads from the submit API.

Uses the az CLI (signed in with `az login`). The storage connection string
is read from az at run time; no key is kept in the repo.

  python3 script/pending-submissions.py list
  python3 script/pending-submissions.py download [--dest /workspace/submissions]
  python3 script/pending-submissions.py move <id> processed|rejected
  python3 script/pending-submissions.py delete <id>

<id> is the uuid in the blob name. move and delete act on every blob with
that id (the image and its JSON).
"""
import argparse
import json
import os
import subprocess
import sys

ACCOUNT = "eastsidecalsubmit"
GROUP = "Default-Web-NorthCentralUS"
CONTAINER = "submissions"


def az(*args):
    out = subprocess.run(["az", *args, "-o", "json"], check=True, capture_output=True, text=True).stdout
    return json.loads(out) if out.strip() else None


def conn():
    value = os.environ.get("SUBMIT_STORAGE")
    if value:
        return value
    return az("storage", "account", "show-connection-string", "-n", ACCOUNT, "-g", GROUP)["connectionString"]


def blobs(cs, prefix="pending/"):
    rows = az("storage", "blob", "list", "-c", CONTAINER, "--prefix", prefix, "--num-results", "*",
              "--connection-string", cs, "--query", "[].name") or []
    return sorted(rows)


def by_id(cs, ident):
    return [name for name in blobs(cs) if os.path.basename(name).startswith(ident)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    dl = sub.add_parser("download")
    dl.add_argument("--dest", default="/workspace/submissions")
    mv = sub.add_parser("move")
    mv.add_argument("id")
    mv.add_argument("to", choices=["processed", "rejected"])
    rm = sub.add_parser("delete")
    rm.add_argument("id")
    args = parser.parse_args()
    cs = conn()

    if args.cmd == "list":
        names = blobs(cs)
        for name in names:
            print(name)
        print(f"{len([n for n in names if n.endswith('.json')])} pending")
        return

    if args.cmd == "download":
        for name in blobs(cs):
            path = os.path.join(args.dest, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            az("storage", "blob", "download", "-c", CONTAINER, "-n", name, "-f", path,
               "--connection-string", cs, "--overwrite", "--no-progress")
            print(path)
        return

    names = by_id(cs, args.id)
    if not names:
        sys.exit(f"No pending blobs for {args.id}")
    for name in names:
        if args.cmd == "move":
            dest = args.to + "/" + name[len("pending/"):]
            az("storage", "blob", "copy", "start", "--destination-container", CONTAINER, "-b", dest,
               "--source-container", CONTAINER, "--source-blob", name, "--connection-string", cs)
            print(f"{name} -> {dest}")
        az("storage", "blob", "delete", "-c", CONTAINER, "-n", name, "--connection-string", cs)
        if args.cmd == "delete":
            print(f"deleted {name}")


if __name__ == "__main__":
    main()

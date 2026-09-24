#!/usr/bin/env python3
"""Create a milestone card by hand (manual mode).

    create-milestone.py <project_root> --title T [--description D]

Runs `brd add --title T [--description D]` (argv array, no shell) with the
project root as the working directory, since brd resolves the project from it.
The description is left out when empty. Prints one JSON line:
{"ok": true, "id": "<card id>"} or {"ok": false, "error": "..."}.
Exit 0 ok, 1 refused/failed, 2 usage error.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

USAGE = "usage: create-milestone.py <project_root> --title T [--description D]"


def parse_args(argv):
    if not argv or argv[0].startswith("--"):
        return None
    root, title, desc = argv[0], None, ""
    rest = argv[1:]
    i = 0
    while i < len(rest):
        if rest[i] in ("--title", "--description") and i + 1 < len(rest):
            if rest[i] == "--title":
                title = rest[i + 1]
            else:
                desc = rest[i + 1]
            i += 2
        else:
            return None
    if title is None:
        return None
    return root, title, desc


def card_id(out):
    """brd prints a JSON card; accept {"id": ...} or {"card": {"id": ...}}."""
    try:
        data = json.loads(out)
    except ValueError:
        return None
    if isinstance(data, dict):
        if isinstance(data.get("card"), dict):
            data = data["card"]
        value = data.get("id")
        if isinstance(value, (str, int)) and str(value):
            return str(value)
    return None


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return emit({"ok": False, "error": USAGE}, 2)
    root, title, desc = parsed
    title, desc = title.strip(), desc.strip()
    if not os.path.isdir(root):
        return emit({"ok": False, "error": "Project folder not found."}, 1)
    if not title:
        return emit({"ok": False, "error": "A milestone needs a title."}, 1)
    brd = shutil.which("brd")
    if brd is None:
        return emit({"ok": False, "error": "brd is not installed."}, 1)
    cmd = [brd, "add", "--title", title]
    if desc:
        cmd += ["--description", desc]
    try:
        proc = subprocess.run(cmd, cwd=root, capture_output=True, text=True,
                              stdin=subprocess.DEVNULL, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        return emit({"ok": False, "error": "Could not run brd: " + str(e)}, 1)
    if proc.returncode != 0:
        msg = (proc.stderr.strip() or proc.stdout.strip() or "brd failed.")
        return emit({"ok": False, "error": msg}, 1)
    new_id = card_id(proc.stdout)
    if new_id is None:
        return emit({"ok": False, "error": "brd created a card but its id could not be read."}, 1)
    return emit({"ok": True, "id": new_id})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

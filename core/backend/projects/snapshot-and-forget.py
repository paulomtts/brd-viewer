#!/usr/bin/env python3
"""Save a snapshot of a brd project, then `brd forget` it.

    snapshot-and-forget.py <root_path> [name]

The snapshot comes first and is mandatory: if nothing can be saved, the
project is NOT forgotten. It lands in $OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR (default
~/Snapshots/omarchy-project-manager; the old BRD_VIEWER_SNAPSHOT_DIR still works) as <name>-<UTC timestamp>/ holding

  tree.json      `brd tree` output, the format `brd import` restores from
  project.db     a raw copy of the project's database, only when `brd tree`
                 could not run (e.g. the project directory is gone)
  project.json   name, path and time
  RESTORE.txt    how to bring it back

Prints one JSON line -- {"ok": true, "snapshot": dir} or {"ok": false,
"error": message} -- and exits 0 or non-zero accordingly.
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

TIMEOUT_SECONDS = 30
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402


def fail(message, code=1):
    return emit({"ok": False, "error": message}, code)


def project_db_path(root_path):
    spec = importlib.util.spec_from_file_location("resolve_db_path", os.path.join(HERE, "resolve-db-path.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.project_db_path(root_path)


def run_brd(args, cwd=None):
    try:
        proc = subprocess.run(["brd", *args], cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    except FileNotFoundError:
        return None, "brd was not found on PATH"
    except subprocess.TimeoutExpired:
        return None, "brd timed out"
    return proc, ""


def brd_ok(proc):
    if proc is None or proc.returncode != 0:
        return False
    try:
        return json.loads(proc.stdout).get("ok") is True
    except ValueError:
        return False


def brd_error(proc, fallback):
    if proc is None:
        return fallback
    try:
        return str(json.loads(proc.stdout)["error"]["message"])
    except (ValueError, KeyError, TypeError):
        return (proc.stderr or proc.stdout or fallback).strip() or fallback


def snapshot_base():
    return (os.environ.get("OMARCHY_PROJECT_MANAGER_SNAPSHOT_DIR") or os.environ.get("BRD_VIEWER_SNAPSHOT_DIR")
            or os.path.expanduser("~/Snapshots/omarchy-project-manager"))


def make_snapshot_dir(name):
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-.") or "project"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    os.makedirs(snapshot_base(), exist_ok=True)
    suffix = 0
    while True:
        leaf = "%s-%s" % (safe, stamp) + ("-%d" % suffix if suffix else "")
        path = os.path.join(snapshot_base(), leaf)
        try:
            os.mkdir(path)
            return path
        except FileExistsError:
            suffix += 1


def restore_text(root_path, snapshot, has_tree, db_dest):
    lines = ["Restore the brd project %s" % root_path, ""]
    lines.append('  mkdir -p "%s"   # only if the directory no longer exists' % root_path)
    lines.append('  cd "%s"' % root_path)
    lines.append("  brd init")
    if has_tree:
        lines.append('  brd import "%s"' % os.path.join(snapshot, "tree.json"))
    else:
        lines.append('  cp "%s" "%s"' % (os.path.join(snapshot, "project.db"), db_dest))
    return "\n".join(lines) + "\n"


def main(argv):
    if not argv or not argv[0]:
        return fail("usage: snapshot-and-forget.py <root_path> [name]", 2)
    root_path = argv[0]
    name = argv[1] if len(argv) > 1 and argv[1] else os.path.basename(os.path.normpath(root_path))

    tree_text = None
    if os.path.isdir(root_path):
        proc, _ = run_brd(["tree"], cwd=root_path)
        if brd_ok(proc):
            tree_text = proc.stdout

    db_source = None
    if tree_text is None:
        candidate = project_db_path(root_path)
        if candidate is not None and os.path.isfile(candidate):
            db_source = str(candidate)

    if tree_text is None and db_source is None:
        return fail("could not snapshot the project, so it was not removed")

    snapshot = make_snapshot_dir(name)
    try:
        if tree_text is not None:
            with open(os.path.join(snapshot, "tree.json"), "w", encoding="utf-8") as f:
                f.write(tree_text)
        else:
            shutil.copyfile(db_source, os.path.join(snapshot, "project.db"))
        db_dest = project_db_path(root_path)
        with open(os.path.join(snapshot, "project.json"), "w", encoding="utf-8") as f:
            json.dump({"name": name, "root_path": root_path,
                       "saved_at": datetime.now(timezone.utc).isoformat()}, f, indent=2)
        with open(os.path.join(snapshot, "RESTORE.txt"), "w", encoding="utf-8") as f:
            f.write(restore_text(root_path, snapshot, tree_text is not None, db_dest))
    except OSError as e:
        shutil.rmtree(snapshot, ignore_errors=True)
        return fail("could not write the snapshot (%s), so the project was not removed" % e)

    proc, problem = run_brd(["forget", root_path])
    if not brd_ok(proc):
        return fail("%s (a snapshot was saved to %s)" % (brd_error(proc, problem or "brd forget failed"), snapshot))
    return emit({"ok": True, "snapshot": snapshot}, 0)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

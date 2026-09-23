#!/usr/bin/env python3
"""Print the on-disk path of a brd project's SQLite database, without
touching it.

Replicates brd's own paths.project_db_path() hashing -- sha256 of the
project's resolved absolute path -- purely so Panel.qml can watch that
path for changes and know when to re-fetch `brd tree`. This script never
opens or reads the database; see brd/src/brd/paths.py for the original.
"""
import hashlib
import os
import sys
from pathlib import Path


def project_db_path(root_path):
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        base = Path(xdg)
    elif os.environ.get("HOME"):
        base = Path(os.environ["HOME"]) / ".local" / "share"
    else:
        return None
    digest = hashlib.sha256(str(Path(root_path).resolve()).encode()).hexdigest()
    return base / "brd" / "projects" / f"{digest}.db"


def main():
    if len(sys.argv) != 2 or sys.argv[1] == "":
        return 1
    path = project_db_path(sys.argv[1])
    if path is None:
        return 1
    print(str(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Remembers which brd project the panel was last showing.

    viewer-state.py get
    viewer-state.py set-project <root_path>

State lives in ${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/state.json
(`get` also reads the old brd-viewer/state.json until a new one is written). QML
cannot write files, hence this helper. Prints one JSON line. `get` never fails
(a missing or corrupt file just means no stored project); `set-project` writes
atomically and keeps any other keys already in the file.
"""
import json
import os
import sys
import tempfile


def state_base():
    return os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")


def state_path():
    return os.path.join(state_base(), "omarchy-project-manager", "state.json")


def legacy_state_path():
    return os.path.join(state_base(), "brd-viewer", "state.json")


def load():
    for path in (state_path(), legacy_state_path()):
        if not os.path.exists(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}
    return {}


def emit(payload, code):
    print(json.dumps(payload))
    return code


def cmd_get():
    last = load().get("last_project")
    return emit({"last_project": last if isinstance(last, str) and last else None}, 0)


def cmd_set_project(root_path):
    data = load()
    data["last_project"] = root_path
    path = state_path()
    directory = os.path.dirname(path)
    tmp = None
    try:
        os.makedirs(directory, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".state-", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except OSError as e:
        if tmp and os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass
        return emit({"ok": False, "error": str(e)}, 1)
    return emit({"ok": True}, 0)


def main(argv):
    if argv[:1] == ["get"] and len(argv) == 1:
        return cmd_get()
    if argv[:1] == ["set-project"] and len(argv) == 2 and argv[1]:
        return cmd_set_project(argv[1])
    return emit({"ok": False, "error": "usage: viewer-state.py get | set-project <root_path>"}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

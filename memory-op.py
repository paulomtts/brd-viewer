#!/usr/bin/env python3
"""Save, create or delete one Claude Code memory note.

    memory-op.py <save|create|delete> <memory_dir> <file> [content]

<memory_dir> must be a real directory named "memory"; <file> a plain lower-case
".md" name other than MEMORY.md. Before anything changes, the note (if it
exists) and MEMORY.md are copied to
<cache>/brd-viewer/memory-backups/<project dir name>/<UTC timestamp>/ (cache =
XDG_CACHE_HOME or ~/.cache); if that fails, nothing is changed. save and create
keep MEMORY.md's line for the note in sync (rewritten in place, or appended);
delete removes only that note's lines. Writes are atomic and keep the files'
modes and the index's line-ending style.
Prints one JSON line: {"ok": true, "backup": "<dir or empty>"} or
{"ok": false, "error": "..."}.
"""
import json
import os
import shutil
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import memory_lib as lib  # noqa: E402

OPS = ("save", "create", "delete")


def emit(payload, code=0):
    print(json.dumps(payload))
    return code


def make_backup(memory_dir, files):
    """Copy `files` (names inside memory_dir that exist) into a fresh backup
    directory and return its path; "" when there is nothing to copy."""
    if not files:
        return ""
    project = os.path.basename(os.path.dirname(os.path.abspath(memory_dir))) or "unknown"
    base = os.path.join(lib.cache_root(), "brd-viewer", "memory-backups", project)
    try:
        os.makedirs(base, exist_ok=True)
        for _ in range(5):
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
            dest = os.path.join(base, stamp)
            try:
                os.mkdir(dest)
                break
            except FileExistsError:
                continue
        else:
            raise OSError("no free backup directory")
        for name, real in files:
            shutil.copy2(real, os.path.join(dest, name))
    except OSError:
        raise lib.Refused("Could not write a backup, so nothing was changed.")
    return dest


def main(argv):
    if len(argv) < 3 or argv[0] not in OPS or (argv[0] != "delete" and len(argv) < 4):
        return emit({"ok": False, "error": "usage: memory-op.py <save|create|delete> <memory_dir> <file> [content]"}, 2)
    op, memory_dir, name = argv[0], argv[1], argv[2]
    try:
        lib.check_filename(name)
        data = lib.check_content(argv[3]) if op != "delete" else None
        content = argv[3] if op != "delete" else None

        if os.path.basename(os.path.normpath(memory_dir)) != "memory":
            raise lib.Refused("That is not a memory directory.")
        exists = os.path.lexists(memory_dir)
        if exists and (os.path.islink(memory_dir) or not os.path.isdir(memory_dir)):
            raise lib.Refused("That is not a memory directory.")
        if not exists and (op != "create" or not os.path.isdir(os.path.dirname(os.path.abspath(memory_dir)))):
            raise lib.Refused("This project has no memory directory.")
        memory_real = os.path.realpath(memory_dir)

        full = os.path.join(memory_dir, name)
        note_real = os.path.realpath(full)
        if op == "create":
            if os.path.lexists(full):
                raise lib.Refused("A note with that file name already exists.")
        else:
            if not (os.path.isfile(note_real) and lib.inside(memory_real, note_real)):
                raise lib.Refused("Note not found.")

        index_full = os.path.join(memory_dir, lib.MEMORY_INDEX)
        index_real = os.path.realpath(index_full)
        index_exists = os.path.lexists(index_full)
        if index_exists and not (os.path.isfile(index_real) and lib.inside(memory_real, index_real)):
            raise lib.Refused("MEMORY.md is not a regular file inside the memory directory.")
        try:
            index_text = open(index_real, "rb").read().decode("utf-8") if index_exists else ""
        except (OSError, UnicodeDecodeError):
            raise lib.Refused("MEMORY.md could not be read as text.")

        if op == "delete":
            new_index = lib.index_without_note(index_text, name)
        else:
            new_index = lib.index_with_note(index_text, name, content)

        to_back_up = []
        if op != "create":
            to_back_up.append((name, note_real))
        if index_exists:
            to_back_up.append((lib.MEMORY_INDEX, index_real))
        backup = make_backup(memory_dir, to_back_up)

        if not exists:
            os.mkdir(memory_dir)
            memory_real = os.path.realpath(memory_dir)
            note_real = os.path.join(memory_real, name)
            index_real = os.path.join(memory_real, lib.MEMORY_INDEX)

        if op == "delete":
            if new_index is not None:
                lib.write_atomic(index_real, new_index.encode("utf-8"))
            os.remove(full)
        else:
            old = open(note_real, "rb").read() if op == "save" else None
            lib.write_atomic(note_real, data)
            try:
                lib.write_atomic(index_real, new_index.encode("utf-8"))
            except OSError:
                if old is None:
                    os.remove(note_real)
                else:
                    lib.write_atomic(note_real, old)
                raise
        return emit({"ok": True, "backup": backup})
    except lib.Refused as e:
        return emit({"ok": False, "error": str(e)}, 1)
    except OSError as e:
        return emit({"ok": False, "error": "Could not write the memory: " + (e.strerror or "I/O error")}, 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

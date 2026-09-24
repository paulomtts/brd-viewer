#!/usr/bin/env python3
"""List a project's Claude Code memory notes.

    list-memories.py <root_path>

Prints one JSON line: {"ok": true, "found": bool, "memory_dir": str, "notes":
[{"file", "name", "description", "type", "size", "indexed"}]}. The project's
directory under ~/.claude/projects (override: CLAUDE_PROJECTS_DIR) is found by
the slug Claude derives from the path, else by a session transcript that
recorded the path as its working directory. Notes are the *.md files directly
in <project>/memory except MEMORY.md; symlinks resolving outside that directory
are skipped. name/description come from the note's frontmatter, else from its
MEMORY.md line, else the file name. Sorted by type (user, feedback, project,
reference, other) then name; at most 500.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import memory_lib as lib  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402
from common.safe_paths import inside  # noqa: E402

MAX_NOTES = 500
ORDER = lib.TYPES + ["other"]


def main(argv):
    if not argv or not argv[0]:
        return emit({"ok": False, "error": "usage: list-memories.py <root_path>"}, 2)
    project_dir = lib.find_project_dir(argv[0])
    if project_dir is None:
        return emit({"ok": True, "found": False, "memory_dir": "", "notes": []})
    memory_dir = os.path.join(project_dir, "memory")
    root_real = os.path.realpath(lib.projects_root())
    memory_real = os.path.realpath(memory_dir)
    if not (os.path.isdir(memory_real) and inside(root_real, memory_real)):
        return emit({"ok": True, "found": False, "memory_dir": memory_dir, "notes": []})

    index = {}
    index_path = os.path.realpath(os.path.join(memory_dir, lib.MEMORY_INDEX))
    if os.path.isfile(index_path) and inside(memory_real, index_path):
        index = lib.index_targets(lib.read_head(index_path, 1024 * 1024))

    notes = []
    for name in sorted(os.listdir(memory_dir)):
        if not name.endswith(".md") or name == lib.MEMORY_INDEX:
            continue
        real = os.path.realpath(os.path.join(memory_dir, name))
        if not (os.path.isfile(real) and inside(memory_real, real)):
            continue
        front = lib.frontmatter_of(lib.read_head(real))
        title, hook = index.get(name, ("", ""))
        notes.append({
            "file": name,
            "name": front.get("name") or title or name[:-3],
            "description": front.get("description") or hook,
            "type": lib.note_type(front.get("type")),
            "size": os.path.getsize(real),
            "indexed": name in index,
        })
    notes.sort(key=lambda n: (ORDER.index(n["type"]), n["name"].lower(), n["file"]))
    return emit({"ok": True, "found": True, "memory_dir": memory_dir, "notes": notes[:MAX_NOTES]})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""List a brd project's Markdown documents.

    list-docs.py <root_path>

Prints one JSON line: {"ok": true, "docs": [{"path", "title", "size"}, ...],
"truncated": bool} or {"ok": false, "error": "..."}. A document is the root
README.md or any *.md under docs/. Only regular files whose resolved path lies
inside the resolved project root are listed; symlinked directories are never
followed and hidden directories are skipped.
"""
import json
import os
import sys

MAX_ENTRIES = 500
TITLE_SCAN_BYTES = 65536


def emit(payload, code=0):
    print(json.dumps(payload))
    return code


def inside(root_real, path_real):
    return path_real == root_real or path_real.startswith(root_real + os.sep)


def title_of(path, fallback):
    try:
        with open(path, "rb") as f:
            head = f.read(TITLE_SCAN_BYTES)
    except OSError:
        return fallback
    for line in head.decode("utf-8", errors="replace").splitlines():
        if line.startswith("# "):
            text = line[2:].strip()
            if text:
                return text
    return fallback


def candidates(root, root_real):
    found = []
    if os.path.isfile(os.path.join(root, "README.md")):
        found.append("README.md")
    docs = os.path.join(root, "docs")
    if os.path.isdir(docs) and inside(root_real, os.path.realpath(docs)):
        for dirpath, dirnames, filenames in os.walk(docs, followlinks=False):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            for name in filenames:
                if name.lower().endswith(".md"):
                    rel = os.path.relpath(os.path.join(dirpath, name), root)
                    found.append(rel.replace(os.sep, "/"))
    return found


def main(argv):
    if not argv or not argv[0]:
        return emit({"ok": False, "error": "usage: list-docs.py <root_path>"}, 2)
    root = argv[0]
    if not os.path.isdir(root):
        return emit({"ok": True, "docs": [], "truncated": False})
    root_real = os.path.realpath(root)

    docs = []
    for rel in candidates(root, root_real):
        full = os.path.join(root, rel)
        real = os.path.realpath(full)
        if not (os.path.isfile(real) and inside(root_real, real) and os.access(real, os.R_OK)):
            continue
        stem = os.path.splitext(os.path.basename(rel))[0]
        docs.append({"path": rel, "title": title_of(real, stem), "size": os.path.getsize(real)})

    docs.sort(key=lambda d: (d["path"] != "README.md", d["path"].lower()))
    truncated = len(docs) > MAX_ENTRIES
    return emit({"ok": True, "docs": docs[:MAX_ENTRIES], "truncated": truncated})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

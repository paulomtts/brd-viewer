#!/usr/bin/env python3
"""List a brd project's Markdown documents.

    list-docs.py <root_path>

Prints one JSON line: {"ok": true, "docs": [{"path", "title", "size",
"category"}, ...], "truncated": bool} or {"ok": false, "error": "..."}. A
document is any *.md under docs/architecture/, docs/specs/,
docs/superpowers/specs/ or docs/audits/; its category is `architecture`,
`specs` (both spec folders) or `audits`. Nothing else is listed, not even the
root README.md. Only regular files whose resolved path lies inside the
resolved project root are listed; symlinked directories are never followed and
hidden directories are skipped. Results are grouped by category (in the order
below), then by path.
"""
import json
import os
import sys

MAX_ENTRIES = 500
TITLE_SCAN_BYTES = 65536

# (category, folders relative to the project root), in display order.
CATEGORIES = [
    ("architecture", ["docs/architecture"]),
    ("specs", ["docs/specs", "docs/superpowers/specs"]),
    ("audits", ["docs/audits"]),
]


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
    """(category, relative path) for every *.md under the category folders."""
    found = []
    for category, folders in CATEGORIES:
        for folder in folders:
            base = os.path.join(root, *folder.split("/"))
            if not (os.path.isdir(base) and inside(root_real, os.path.realpath(base))):
                continue
            for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
                dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
                for name in filenames:
                    if name.lower().endswith(".md"):
                        rel = os.path.relpath(os.path.join(dirpath, name), root)
                        found.append((category, rel.replace(os.sep, "/")))
    return found


def main(argv):
    if not argv or not argv[0]:
        return emit({"ok": False, "error": "usage: list-docs.py <root_path>"}, 2)
    root = argv[0]
    if not os.path.isdir(root):
        return emit({"ok": True, "docs": [], "truncated": False})
    root_real = os.path.realpath(root)

    docs = []
    for category, rel in candidates(root, root_real):
        full = os.path.join(root, rel)
        real = os.path.realpath(full)
        if not (os.path.isfile(real) and inside(root_real, real) and os.access(real, os.R_OK)):
            continue
        stem = os.path.splitext(os.path.basename(rel))[0]
        docs.append({"path": rel, "title": title_of(real, stem), "size": os.path.getsize(real),
                     "category": category})

    order = {name: index for index, (name, _) in enumerate(CATEGORIES)}
    docs.sort(key=lambda d: (order[d["category"]], d["path"].lower()))
    truncated = len(docs) > MAX_ENTRIES
    return emit({"ok": True, "docs": docs[:MAX_ENTRIES], "truncated": truncated})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

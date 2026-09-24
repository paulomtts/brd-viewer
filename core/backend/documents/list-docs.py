#!/usr/bin/env python3
"""List a brd project's Markdown documents.

    list-docs.py <root_path>

Prints one JSON line: {"ok": true, "docs": [{"path", "title", "size",
"category"}, ...], "truncated": bool} or {"ok": false, "error": "..."}. A
document is any *.md under docs/. Its category is the value of a `tag:` line in
the file's YAML frontmatter (`architecture`, `spec`, `standards`, `audit`;
case-insensitive, singular or plural), else the default for its folder
(docs/architecture, docs/specs + docs/superpowers/specs, docs/standards,
docs/audits), else `other`. Only regular files whose resolved path lies inside
the resolved project root are listed; symlinked directories are never followed
and hidden directories are skipped. Results are grouped by category (in the
order below), then by path.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import frontmatter  # noqa: E402
from common.json_line import emit  # noqa: E402
from common.safe_paths import inside  # noqa: E402

MAX_ENTRIES = 500
HEAD_BYTES = 65536

CATEGORY_ORDER = ["architecture", "specs", "standards", "audits", "other"]

# Default category by folder prefix (relative to the project root).
FOLDER_DEFAULTS = [
    ("docs/architecture/", "architecture"),
    ("docs/specs/", "specs"),
    ("docs/superpowers/specs/", "specs"),
    ("docs/standards/", "standards"),
    ("docs/audits/", "audits"),
]

TAG_ALIASES = {
    "architecture": "architecture",
    "spec": "specs", "specs": "specs",
    "standard": "standards", "standards": "standards",
    "audit": "audits", "audits": "audits",
}


def read_head(path):
    try:
        with open(path, "rb") as f:
            return f.read(HEAD_BYTES).decode("utf-8", errors="replace")
    except OSError:
        return ""


def tag_of(front):
    value = frontmatter.value(front, "tag")
    return None if value is None else TAG_ALIASES.get(value.lower())


def title_of(body, fallback):
    for line in body:
        if line.startswith("# "):
            text = line[2:].strip()
            if text:
                return text
    return fallback


def folder_default(rel):
    for prefix, category in FOLDER_DEFAULTS:
        if rel.startswith(prefix):
            return category
    return "other"


def candidates(root, root_real):
    """Relative path of every *.md under docs/."""
    base = os.path.join(root, "docs")
    if not (os.path.isdir(base) and inside(root_real, os.path.realpath(base))):
        return []
    found = []
    for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
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
        front, body = frontmatter.split(read_head(real))
        docs.append({"path": rel, "title": title_of(body, stem), "size": os.path.getsize(real),
                     "category": tag_of(front) or folder_default(rel)})

    order = {name: index for index, name in enumerate(CATEGORY_ORDER)}
    docs.sort(key=lambda d: (order[d["category"]], d["path"].lower()))
    truncated = len(docs) > MAX_ENTRIES
    return emit({"ok": True, "docs": docs[:MAX_ENTRIES], "truncated": truncated})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

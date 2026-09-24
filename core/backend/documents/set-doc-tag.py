#!/usr/bin/env python3
"""Set or clear a document's type tag.

    set-doc-tag.py <root_path> <doc_path> <tag>

<doc_path> is relative to the project and must be a Markdown file under docs/.
<tag> is architecture, spec(s), standard(s) or audit(s), or `default` to remove
the tag so the folder decides. Only the `tag:` line of the leading YAML
frontmatter is touched (the block is created, or removed once it is empty);
every other byte, the line-ending style and the file mode are preserved. The
file is replaced atomically, and left alone when nothing would change.
Prints one JSON line: {"ok": true, "changed": bool} or {"ok": false, "error"}.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import frontmatter  # noqa: E402
from common.atomic_write import write_atomic  # noqa: E402
from common.json_line import emit  # noqa: E402
from common.safe_paths import contained_file  # noqa: E402

MAX_BYTES = 1024 * 1024
CANONICAL = {
    "architecture": "architecture",
    "spec": "spec", "specs": "spec",
    "standard": "standard", "standards": "standard",
    "audit": "audit", "audits": "audit",
}


class Refused(Exception):
    pass


def resolve(root, rel):
    if not os.path.isdir(root):
        raise Refused("Project folder not found.")
    parts = rel.split("/")
    if (not rel or rel.startswith("/") or ".." in parts or parts[0] != "docs"
            or not rel.lower().endswith(".md")):
        raise Refused("Only Markdown documents under docs/ can be tagged.")
    real = contained_file(root, rel)
    if real is None:
        raise Refused("Document not found in this project.")
    return real


def main(argv):
    if len(argv) != 3 or not argv[0]:
        return emit({"ok": False, "error": "usage: set-doc-tag.py <root_path> <doc_path> <tag>"}, 2)
    root, rel, raw_tag = argv
    value = raw_tag.strip().lower()
    if value == "default":
        tag = None
    elif value in CANONICAL:
        tag = CANONICAL[value]
    else:
        return emit({"ok": False, "error": "Unknown document type."}, 2)
    try:
        real = resolve(root, rel)
        if os.path.getsize(real) > MAX_BYTES:
            raise Refused("This document is too large to edit.")
        with open(real, "rb") as f:
            raw = f.read()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            raise Refused("This document is not valid UTF-8 text.")
        updated = frontmatter.set_key(text, "tag", tag)
        if updated == text:
            return emit({"ok": True, "changed": False})
        write_atomic(real, updated.encode("utf-8"))
        return emit({"ok": True, "changed": True})
    except Refused as e:
        return emit({"ok": False, "error": str(e)}, 1)
    except OSError as e:
        return emit({"ok": False, "error": "Could not write the document: " + (e.strerror or "I/O error")}, 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

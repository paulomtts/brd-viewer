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
import json
import os
import shutil
import sys
import tempfile

MAX_BYTES = 1024 * 1024
CANONICAL = {
    "architecture": "architecture",
    "spec": "spec", "specs": "spec",
    "standard": "standard", "standards": "standard",
    "audit": "audit", "audits": "audit",
}


class Refused(Exception):
    pass


def emit(payload, code=0):
    print(json.dumps(payload))
    return code


def inside(root_real, path_real):
    return path_real == root_real or path_real.startswith(root_real + os.sep)


def resolve(root, rel):
    if not os.path.isdir(root):
        raise Refused("Project folder not found.")
    parts = rel.split("/")
    if (not rel or rel.startswith("/") or ".." in parts or parts[0] != "docs"
            or not rel.lower().endswith(".md")):
        raise Refused("Only Markdown documents under docs/ can be tagged.")
    root_real = os.path.realpath(root)
    real = os.path.realpath(os.path.join(root, rel))
    if not (inside(root_real, real) and os.path.isfile(real)):
        raise Refused("Document not found in this project.")
    return real


def is_tag_line(line):
    key, sep, _ = line.partition(":")
    return bool(sep) and key.strip().lower() == "tag"


def edit(text, tag):
    """text with its tag set (canonical name) or removed (tag is None)."""
    first = text.find("\n")
    newline = "\r\n" if first > 0 and text[first - 1] == "\r" else "\n"
    lines = text.splitlines(keepends=True)
    close = None
    if lines and lines[0].rstrip("\r\n").strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].rstrip("\r\n").strip() == "---":
                close = i
                break

    if close is None:
        if tag is None:
            return text
        return "---" + newline + "tag: " + tag + newline + "---" + newline + text

    front = lines[1:close]
    kept, placed = [], False
    for line in front:
        if is_tag_line(line.rstrip("\r\n")):
            if tag is not None and not placed:
                kept.append("tag: " + tag + newline)
                placed = True
            continue
        kept.append(line)
    if tag is not None and not placed:
        kept.append("tag: " + tag + newline)
    if tag is None and not "".join(kept).strip():
        return "".join(lines[close + 1:])
    return "".join([lines[0]] + kept + lines[close:])


def write_atomic(real, data):
    directory = os.path.dirname(real)
    fd, tmp = tempfile.mkstemp(prefix=".tag-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        shutil.copymode(real, tmp)
        os.replace(tmp, real)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


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
        updated = edit(text, tag)
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

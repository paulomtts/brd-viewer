"""Shared rules for Claude Code's on-disk memory layout, used by
list-memories.py and memory-op.py.

A project's memory lives at ~/.claude/projects/<slug>/memory/: a MEMORY.md
index plus one Markdown note per memory. Nothing here prints; the scripts own
all I/O reporting.
"""
import json
import os
import re
import tempfile

MEMORY_INDEX = "MEMORY.md"
MAX_NOTE_BYTES = 65536
HEAD_BYTES = 65536
TYPES = ["user", "feedback", "project", "reference"]

INDEX_LINE_RE = re.compile(r"^-\s*\[([^\]]+)\]\(([^)]+)\)\s*(.*)$")

_TRANSCRIPT_DIRS = 1000
_TRANSCRIPTS_PER_DIR = 5
_TRANSCRIPT_BYTES = 32768
_TRANSCRIPT_LINES = 50


class Refused(Exception):
    pass


def projects_root():
    return os.environ.get("CLAUDE_PROJECTS_DIR") or os.path.expanduser("~/.claude/projects")


def cache_root():
    return os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")


def inside(root_real, path_real):
    return path_real == root_real or path_real.startswith(root_real + os.sep)


def slug_of(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def normalize_href(href):
    href = href.strip()
    return href[2:] if href.startswith("./") else href


def parse_link(line):
    """(title, raw href, hook) for a MEMORY.md note link line, else None."""
    m = INDEX_LINE_RE.match(line.rstrip("\r"))
    if not m:
        return None
    return m.group(1).strip(), m.group(2), m.group(3).strip().lstrip("—–- ").strip()


def index_link(line):
    """(title, normalised file, hook) for a note link line, else None."""
    link = parse_link(line)
    return (link[0], normalize_href(link[1]), link[2]) if link else None


def read_head(path, limit=HEAD_BYTES):
    try:
        with open(path, "rb") as f:
            return f.read(limit).decode("utf-8", errors="replace")
    except OSError:
        return ""


def _unquote(value):
    v = value.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v


def frontmatter_of(text):
    """{name, description, type} from a leading ---...--- block, {} when there
    is none or it never closes. `type` may sit at top level or, as Claude
    Code writes it, indented under `metadata:`; top level wins."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}
    close = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            close = i
            break
    if close is None:
        return {}
    fields, nested, in_meta = {}, "", False
    for raw in lines[1:close]:
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, sep, value = line.strip().partition(":")
        if not sep:
            continue
        key = key.strip().lower()
        if line[0] not in " \t":
            in_meta = key == "metadata" and value.strip() == ""
            if key in ("name", "description", "type"):
                fields[key] = _unquote(value)
        elif in_meta and key == "type":
            nested = _unquote(value)
    if not fields.get("type") and nested:
        fields["type"] = nested
    return fields


def note_type(value):
    value = (value or "").strip().lower()
    return value if value in TYPES else "other"


# --- locating a project's memory ---------------------------------------

def _transcript_cwds(project_dir):
    try:
        names = sorted(n for n in os.listdir(project_dir) if n.endswith(".jsonl"))
    except OSError:
        return
    for name in names[:_TRANSCRIPTS_PER_DIR]:
        try:
            with open(os.path.join(project_dir, name), "rb") as f:
                head = f.read(_TRANSCRIPT_BYTES).decode("utf-8", errors="replace")
        except OSError:
            continue
        for line in head.splitlines()[:_TRANSCRIPT_LINES]:
            try:
                cwd = json.loads(line).get("cwd")
            except (ValueError, AttributeError):
                continue
            if isinstance(cwd, str):
                yield cwd


def find_project_dir(root_path):
    """The Claude project directory for a project path, or None. First by the
    slug Claude derives from the path, then by a session transcript that
    recorded exactly this path as its working directory."""
    root = projects_root()
    if not os.path.isdir(root):
        return None
    wanted = os.path.normpath(root_path)
    paths = [wanted]
    real = os.path.realpath(wanted)
    if real != wanted:
        paths.append(real)
    for path in paths:
        candidate = os.path.join(root, slug_of(path))
        if os.path.isdir(candidate):
            return candidate
    try:
        entries = sorted(os.listdir(root))[:_TRANSCRIPT_DIRS]
    except OSError:
        return None
    for entry in entries:
        candidate = os.path.join(root, entry)
        if not os.path.isdir(candidate):
            continue
        for cwd in _transcript_cwds(candidate):
            if os.path.normpath(cwd) in paths:
                return candidate
    return None


# --- MEMORY.md ----------------------------------------------------------

def index_targets(text):
    """{normalised file: (title, hook)} for every note link in an index."""
    found = {}
    for line in text.split("\n"):
        link = index_link(line)
        if link and link[1] not in found:
            found[link[1]] = (link[0], link[2])
    return found


def _newline_of(text):
    first = text.find("\n")
    return "\r\n" if first > 0 and text[first - 1] == "\r" else "\n"


def _clean_title(title, stem):
    title = re.sub(r"[\[\]\r\n]+", " ", title or "").strip()
    return title or stem


def _clean_hook(hook):
    return re.sub(r"[\r\n]+", " ", hook or "").strip()


def _link_line(title, href, hook):
    return "- [" + title + "](" + href + ")" + (" — " + hook if hook else "")


def index_with_note(text, filename, content):
    """MEMORY.md text with this note's line rewritten in place (original href
    spelling kept) or appended, for a note whose new content is `content`."""
    front = frontmatter_of(content)
    stem = filename[:-3]
    title = _clean_title(front.get("name"), stem)
    hook = _clean_hook(front.get("description"))
    newline = _newline_of(text)
    pieces = text.split("\n")
    changed = False
    for i, piece in enumerate(pieces):
        link = parse_link(piece)
        if link and normalize_href(link[1]) == filename:
            tail = "\r" if piece.endswith("\r") else ""
            pieces[i] = _link_line(title, link[1].strip(), hook) + tail
            changed = True
    if changed:
        return "\n".join(pieces)
    line = _link_line(title, filename, hook)
    if text == "":
        return line + newline
    if not text.endswith("\n"):
        text += newline
    return text + line + newline


def index_without_note(text, filename):
    """MEMORY.md text minus the link lines pointing at `filename`, or None
    when it had none."""
    pieces = text.split("\n")
    kept = []
    for piece in pieces:
        link = parse_link(piece)
        if link and normalize_href(link[1]) == filename:
            continue
        kept.append(piece)
    return None if len(kept) == len(pieces) else "\n".join(kept)


# --- validation ---------------------------------------------------------

def check_filename(name):
    if (not isinstance(name, str) or name in ("", ".", "..") or "/" in name or "\x00" in name
            or not name.endswith(".md") or name == MEMORY_INDEX):
        raise Refused("That is not a valid memory note file name.")
    return name


def check_content(content):
    """The note's bytes, or Refused."""
    if not isinstance(content, str) or "\x00" in content:
        raise Refused("The note text is not valid.")
    try:
        data = content.encode("utf-8")
    except UnicodeEncodeError:
        raise Refused("The note text is not valid UTF-8.")
    if len(data) > MAX_NOTE_BYTES:
        raise Refused("The note is too large (over 64 KB).")
    return data


# --- writing ------------------------------------------------------------

def write_atomic(real_path, data, mode=None):
    """Replace (or create) a file atomically. An existing file keeps its mode;
    a new one gets `mode` (default 0o644)."""
    directory = os.path.dirname(real_path)
    existing = os.stat(real_path).st_mode & 0o777 if os.path.exists(real_path) else None
    fd, tmp = tempfile.mkstemp(prefix=".mem-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(tmp, existing if existing is not None else (mode if mode is not None else 0o644))
        os.replace(tmp, real_path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

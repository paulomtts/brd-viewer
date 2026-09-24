def split(text):
    """(front_lines, body_lines). No closed leading --- block means no front."""
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[1:i], lines[i + 1:]
    return [], lines


def _is_key(line, key):
    name, sep, _ = line.partition(":")
    return bool(sep) and name.strip().lower() == key.lower()


def value(front_lines, key):
    """Value of `key` (case-insensitive), quotes and trailing # comment stripped."""
    for line in front_lines:
        if _is_key(line, key):
            return line.partition(":")[2].split("#", 1)[0].strip().strip("\"'").strip()
    return None


def set_key(text, key, val):
    """text with `key` set to val, or removed when val is None. Keeps the newline style."""
    first = text.find("\n")
    newline = "\r\n" if first > 0 and text[first - 1] == "\r" else "\n"
    lines = text.splitlines(keepends=True)
    close = None
    if lines and lines[0].rstrip("\r\n").strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].rstrip("\r\n").strip() == "---":
                close = i
                break

    entry = None if val is None else key + ": " + val + newline
    if close is None:
        if entry is None:
            return text
        return "---" + newline + entry + "---" + newline + text

    kept, placed = [], False
    for line in lines[1:close]:
        if _is_key(line.rstrip("\r\n"), key):
            if entry is not None and not placed:
                kept.append(entry)
                placed = True
            continue
        kept.append(line)
    if entry is not None and not placed:
        kept.append(entry)
    if entry is None and not "".join(kept).strip():
        return "".join(lines[close + 1:])
    return "".join([lines[0]] + kept + lines[close:])

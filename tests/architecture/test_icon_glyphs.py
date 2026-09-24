"""Every icon glyph the plugin draws must exist in an installed Nerd Font.

The shell paints `iconText` (and every other glyph we write) with
`Style.font.family`, which resolves to the system monospace -- a Nerd Font.
A code point that only exists in the separate "Font Awesome Free" font renders
as a missing-glyph box, which is invisible to the QML tests. So: scan every
`.qml` under `ui/` and `vendor/` for private-use code points (written either as
a literal character or as `\\uXXXX` escapes, surrogate pairs included) and ask
fontconfig whether some installed Nerd Font family covers each one.
"""
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIRS = ["ui", "vendor"]

ESCAPE_RE = re.compile(r"\\u([0-9a-fA-F]{4})")


def code_points(text):
    """Every code point of `text` with `\\uXXXX` escapes expanded and surrogate pairs joined."""
    expanded = ESCAPE_RE.sub(lambda m: chr(int(m.group(1), 16)), text)
    out = []
    i = 0
    while i < len(expanded):
        cp = ord(expanded[i])
        nxt = ord(expanded[i + 1]) if i + 1 < len(expanded) else 0
        if 0xD800 <= cp <= 0xDBFF and 0xDC00 <= nxt <= 0xDFFF:
            out.append(0x10000 + ((cp - 0xD800) << 10) + (nxt - 0xDC00))
            i += 2
            continue
        out.append(cp)
        i += 1
    return out


def is_glyph(cp):
    """A private-use code point: the planes every icon font puts its glyphs in."""
    return 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0xFFFFD or 0x100000 <= cp <= 0x10FFFD


def glyphs_of(text):
    return sorted({cp for cp in code_points(text) if is_glyph(cp)})


def qml_sources():
    return sorted(p for top in SOURCE_DIRS for p in (ROOT / top).rglob("*.qml"))


def nerd_font_families(charset):
    """The installed "Nerd Font" families covering `charset` (a hex code point, no 0x)."""
    out = subprocess.run(["fc-list", ":charset=%s" % charset, "family"],
                         capture_output=True, text=True, check=False).stdout
    return [line for line in out.splitlines() if "Nerd Font" in line]


def test_the_code_point_decoder_handles_escapes_literals_and_surrogate_pairs():
    assert glyphs_of(r'iconText: ""') == [0xF021]
    assert glyphs_of('iconText: ""') == [0xF021]
    # The Material Design brain, outside the BMP, written as its surrogate pair.
    assert glyphs_of(r'iconText: "󰧑"') == [0xF09D1]
    assert glyphs_of('iconText: "\U000F09D1"') == [0xF09D1]
    assert glyphs_of('text: "Board ‹ ›"') == []


def test_every_icon_glyph_in_the_sources_exists_in_an_installed_nerd_font():
    if shutil.which("fc-list") is None:
        pytest.skip("fontconfig is not available here")
    if not nerd_font_families("f021"):
        pytest.skip("no Nerd Font is installed here")
    missing = []
    for path in qml_sources():
        for cp in glyphs_of(path.read_text()):
            if not nerd_font_families("%x" % cp):
                missing.append("%s: U+%04X" % (path.relative_to(ROOT).as_posix(), cp))
    assert missing == []


def test_the_sources_actually_carry_the_glyphs_this_guard_is_for():
    found = {cp for path in qml_sources() for cp in glyphs_of(path.read_text())}
    assert 0xF021 in found, "the toolbar's refresh icon"
    assert 0xF0DB in found, "the sidebar's Board icon"

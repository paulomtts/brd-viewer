"""set-doc-tag.py: rewrites only the `tag:` line of a document's frontmatter."""
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "core", "backend", "documents")
SCRIPT = os.path.join(HERE, "set-doc-tag.py")
LIST = os.path.join(HERE, "list-docs.py")


def run(*args):
    proc = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def make(tmp_path, rel="docs/specs/a.md", text="# A\nbody\n"):
    f = tmp_path / rel
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_bytes(text.encode())
    return f


def category(tmp_path, rel):
    out = subprocess.run([sys.executable, LIST, str(tmp_path)], capture_output=True, text=True).stdout
    return {d["path"]: d["category"] for d in json.loads(out)["docs"]}[rel]


def test_a_document_without_frontmatter_gets_one(tmp_path):
    f = make(tmp_path)
    code, result = run(str(tmp_path), "docs/specs/a.md", "standards")
    assert code == 0 and result == {"ok": True, "changed": True}
    assert f.read_text() == "---\ntag: standard\n---\n# A\nbody\n"
    assert category(tmp_path, "docs/specs/a.md") == "standards"


def test_an_existing_tag_line_is_replaced_and_everything_else_is_kept(tmp_path):
    f = make(tmp_path, text="---\ntitle: Foo\ntag: spec\nowner: me\n---\n# A\n\nbody  \n")
    run(str(tmp_path), "docs/specs/a.md", "audits")
    assert f.read_text() == "---\ntitle: Foo\ntag: audit\nowner: me\n---\n# A\n\nbody  \n"


def test_frontmatter_without_a_tag_gets_one_before_the_closing_fence(tmp_path):
    f = make(tmp_path, text="---\ntitle: Foo\n---\n# A\n")
    run(str(tmp_path), "docs/specs/a.md", "architecture")
    assert f.read_text() == "---\ntitle: Foo\ntag: architecture\n---\n# A\n"


def test_the_tag_key_is_matched_case_insensitively_and_duplicates_collapse(tmp_path):
    f = make(tmp_path, text="---\nTag: spec\ntag: audit\n---\n# A\n")
    run(str(tmp_path), "docs/specs/a.md", "standards")
    assert f.read_text() == "---\ntag: standard\n---\n# A\n"


def test_clearing_removes_only_the_tag_line(tmp_path):
    f = make(tmp_path, text="---\ntitle: Foo\ntag: spec\n---\n# A\n")
    code, result = run(str(tmp_path), "docs/specs/a.md", "default")
    assert result == {"ok": True, "changed": True}
    assert f.read_text() == "---\ntitle: Foo\n---\n# A\n"


def test_clearing_the_only_key_removes_the_whole_block(tmp_path):
    f = make(tmp_path, text="---\ntag: spec\n---\n# A\nbody\n")
    run(str(tmp_path), "docs/specs/a.md", "default")
    assert f.read_text() == "# A\nbody\n"


def test_clearing_a_document_without_a_tag_changes_nothing(tmp_path):
    f = make(tmp_path)
    before = f.stat().st_mtime_ns
    code, result = run(str(tmp_path), "docs/specs/a.md", "default")
    assert result == {"ok": True, "changed": False}
    assert f.read_text() == "# A\nbody\n" and f.stat().st_mtime_ns == before


def test_setting_the_same_tag_does_not_rewrite_the_file(tmp_path):
    f = make(tmp_path, text="---\ntag: spec\n---\n# A\n")
    before = f.stat().st_mtime_ns
    assert run(str(tmp_path), "docs/specs/a.md", "specs")[1] == {"ok": True, "changed": False}
    assert f.stat().st_mtime_ns == before


def test_crlf_line_endings_are_preserved(tmp_path):
    f = make(tmp_path, text="---\r\ntitle: Foo\r\n---\r\n# A\r\n")
    run(str(tmp_path), "docs/specs/a.md", "spec")
    assert f.read_bytes() == b"---\r\ntitle: Foo\r\ntag: spec\r\n---\r\n# A\r\n"
    g = make(tmp_path, "docs/specs/b.md", "# B\r\nbody\r\n")
    run(str(tmp_path), "docs/specs/b.md", "spec")
    assert g.read_bytes() == b"---\r\ntag: spec\r\n---\r\n# B\r\nbody\r\n"


def test_a_leading_dashes_line_that_is_not_frontmatter_is_not_treated_as_such(tmp_path):
    f = make(tmp_path, text="---\ntag: spec\nnever closed\n")
    run(str(tmp_path), "docs/specs/a.md", "audit")
    assert f.read_text() == "---\ntag: audit\n---\n---\ntag: spec\nnever closed\n"


def test_permissions_are_kept_and_no_temp_files_are_left(tmp_path):
    f = make(tmp_path)
    os.chmod(f, 0o640)
    run(str(tmp_path), "docs/specs/a.md", "audit")
    assert (f.stat().st_mode & 0o777) == 0o640
    assert [p.name for p in f.parent.iterdir()] == ["a.md"]


def test_a_symlinked_document_inside_the_project_keeps_its_link(tmp_path):
    real = make(tmp_path, "docs/specs/real.md")
    os.symlink(real, tmp_path / "docs" / "specs" / "alias.md")
    run(str(tmp_path), "docs/specs/alias.md", "audit")
    assert (tmp_path / "docs" / "specs" / "alias.md").is_symlink()
    assert real.read_text().startswith("---\ntag: audit\n---\n")


def test_a_symlink_escaping_the_project_is_refused(tmp_path):
    outside = tmp_path / "outside.md"
    outside.write_text("# secret\n")
    proj = tmp_path / "proj"
    (proj / "docs").mkdir(parents=True)
    os.symlink(outside, proj / "docs" / "leak.md")
    code, result = run(str(proj), "docs/leak.md", "audit")
    assert code != 0 and result["ok"] is False
    assert outside.read_text() == "# secret\n"


def test_paths_outside_docs_or_not_markdown_are_refused(tmp_path):
    make(tmp_path, "README.md")
    make(tmp_path, "docs/notes.txt")
    make(tmp_path, "src/x.md")
    for rel in ["README.md", "docs/notes.txt", "src/x.md", "../x.md", "docs/../README.md",
                "/etc/passwd", "docs/missing.md", "docs", ""]:
        code, result = run(str(tmp_path), rel, "audit")
        assert code != 0 and result["ok"] is False, rel
    assert (tmp_path / "README.md").read_text() == "# A\nbody\n"


def test_unknown_tags_and_missing_arguments_are_refused(tmp_path):
    f = make(tmp_path)
    for tag in ["banana", "other", ""]:
        code, result = run(str(tmp_path), "docs/specs/a.md", tag)
        assert code != 0 and result["ok"] is False, tag
    assert run(str(tmp_path))[0] == 2
    assert f.read_text() == "# A\nbody\n"


def test_binary_and_oversized_documents_are_refused_untouched(tmp_path):
    f = make(tmp_path, "docs/bin.md")
    f.write_bytes(b"\xff\xfe\x00# nope\x80")
    assert run(str(tmp_path), "docs/bin.md", "audit")[1]["ok"] is False
    assert f.read_bytes() == b"\xff\xfe\x00# nope\x80"
    big = make(tmp_path, "docs/big.md", "x" * (1024 * 1024 + 1))
    assert run(str(tmp_path), "docs/big.md", "audit")[1]["ok"] is False
    assert len(big.read_bytes()) == 1024 * 1024 + 1


def test_a_read_only_directory_fails_cleanly(tmp_path):
    f = make(tmp_path)
    os.chmod(f.parent, 0o555)
    try:
        code, result = run(str(tmp_path), "docs/specs/a.md", "audit")
    finally:
        os.chmod(f.parent, 0o755)
    if os.geteuid() != 0:
        assert code != 0 and result["ok"] is False
        assert f.read_text() == "# A\nbody\n"

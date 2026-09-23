"""list-docs.py over throwaway project trees."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "list-docs.py")


def run(*args):
    proc = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def write(path, text="# T\n"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def paths(result):
    return [d["path"] for d in result["docs"]]


def test_missing_project_directory_is_an_empty_list(tmp_path):
    code, result = run(str(tmp_path / "nope"))
    assert code == 0 and result == {"ok": True, "docs": [], "truncated": False}


def test_project_without_docs_is_an_empty_list(tmp_path):
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "notes.md").write_text("# not under docs")
    assert run(str(tmp_path))[1]["docs"] == []


def test_readme_comes_first_then_docs_in_case_insensitive_order(tmp_path):
    write(tmp_path / "README.md", "# Readme title\n")
    write(tmp_path / "docs" / "b.md")
    write(tmp_path / "docs" / "A.md")
    write(tmp_path / "docs" / "sub" / "c.md")
    assert paths(run(str(tmp_path))[1]) == ["README.md", "docs/A.md", "docs/b.md", "docs/sub/c.md"]


def test_titles_come_from_the_first_h1_else_the_file_name(tmp_path):
    write(tmp_path / "docs" / "with-title.md", "intro\n\n# The Title\nbody\n")
    write(tmp_path / "docs" / "plain.md", "no heading here\n")
    write(tmp_path / "docs" / "empty-h1.md", "# \nbody\n")
    by_path = {d["path"]: d["title"] for d in run(str(tmp_path))[1]["docs"]}
    assert by_path["docs/with-title.md"] == "The Title"
    assert by_path["docs/plain.md"] == "plain"
    assert by_path["docs/empty-h1.md"] == "empty-h1"


def test_size_is_reported(tmp_path):
    write(tmp_path / "docs" / "a.md", "# T\n12345")
    assert run(str(tmp_path))[1]["docs"][0]["size"] == len("# T\n12345")


def test_extension_is_case_insensitive_and_other_files_are_ignored(tmp_path):
    write(tmp_path / "docs" / "UP.MD")
    write(tmp_path / "docs" / "notes.txt")
    write(tmp_path / "docs" / "img.png", "x")
    assert paths(run(str(tmp_path))[1]) == ["docs/UP.MD"]


def test_hidden_directories_are_skipped(tmp_path):
    write(tmp_path / "docs" / ".secret" / "x.md")
    write(tmp_path / "docs" / "ok.md")
    assert paths(run(str(tmp_path))[1]) == ["docs/ok.md"]


def test_paths_with_spaces_work(tmp_path):
    write(tmp_path / "docs" / "my notes" / "big plan.md")
    assert paths(run(str(tmp_path))[1]) == ["docs/my notes/big plan.md"]


def test_a_symlinked_file_that_escapes_the_project_is_skipped(tmp_path):
    outside = tmp_path / "outside.md"
    outside.write_text("# secret")
    proj = tmp_path / "proj"
    write(proj / "docs" / "ok.md")
    os.symlink(outside, proj / "docs" / "leak.md")
    assert paths(run(str(proj))[1]) == ["docs/ok.md"]


def test_a_symlinked_directory_is_not_followed(tmp_path):
    other = tmp_path / "other"
    write(other / "x.md")
    proj = tmp_path / "proj"
    write(proj / "docs" / "ok.md")
    os.symlink(other, proj / "docs" / "linked")
    assert paths(run(str(proj))[1]) == ["docs/ok.md"]


def test_a_docs_directory_symlinked_outside_is_ignored(tmp_path):
    other = tmp_path / "other"
    write(other / "x.md")
    proj = tmp_path / "proj"
    proj.mkdir()
    os.symlink(other, proj / "docs")
    assert run(str(proj))[1]["docs"] == []


def test_a_symlinked_file_staying_inside_the_project_is_listed(tmp_path):
    proj = tmp_path / "proj"
    write(proj / "docs" / "real.md")
    os.symlink(proj / "docs" / "real.md", proj / "docs" / "alias.md")
    assert paths(run(str(proj))[1]) == ["docs/alias.md", "docs/real.md"]


def test_the_list_is_capped_and_flagged(tmp_path):
    for i in range(505):
        write(tmp_path / "docs" / ("d%04d.md" % i), "x")
    result = run(str(tmp_path))[1]
    assert len(result["docs"]) == 500 and result["truncated"] is True


def test_exactly_the_cap_is_not_truncated(tmp_path):
    for i in range(500):
        write(tmp_path / "docs" / ("d%04d.md" % i), "x")
    result = run(str(tmp_path))[1]
    assert len(result["docs"]) == 500 and result["truncated"] is False


def test_binary_and_empty_files_do_not_crash(tmp_path):
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "bin.md").write_bytes(b"\xff\xfe\x00# nope\x80")
    (tmp_path / "docs" / "empty.md").write_bytes(b"")
    result = run(str(tmp_path))[1]
    assert sorted(paths(result)) == ["docs/bin.md", "docs/empty.md"]


def test_requires_a_path(tmp_path):
    code, result = run()
    assert code == 2 and result["ok"] is False

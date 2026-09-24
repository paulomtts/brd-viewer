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


def cats(result):
    return {d["path"]: d["category"] for d in result["docs"]}


SPECS = "docs/specs"


def test_missing_project_directory_is_an_empty_list(tmp_path):
    code, result = run(str(tmp_path / "nope"))
    assert code == 0 and result == {"ok": True, "docs": [], "truncated": False}


def test_only_the_four_documentation_folders_are_listed(tmp_path):
    write(tmp_path / "README.md", "# Readme")
    write(tmp_path / "src" / "notes.md")
    write(tmp_path / "docs" / "loose.md")
    write(tmp_path / "docs" / "notes" / "n.md")
    write(tmp_path / "docs" / "superpowers" / "plans" / "plan.md")
    assert run(str(tmp_path))[1]["docs"] == []


def test_each_folder_maps_to_its_category(tmp_path):
    write(tmp_path / "docs" / "architecture" / "a.md")
    write(tmp_path / "docs" / "specs" / "s.md")
    write(tmp_path / "docs" / "superpowers" / "specs" / "ss.md")
    write(tmp_path / "docs" / "audits" / "u.md")
    assert cats(run(str(tmp_path))[1]) == {
        "docs/architecture/a.md": "architecture",
        "docs/specs/s.md": "specs",
        "docs/superpowers/specs/ss.md": "specs",
        "docs/audits/u.md": "audits",
    }


def test_both_spec_folders_share_the_specs_category_and_sort_by_path(tmp_path):
    write(tmp_path / "docs" / "superpowers" / "specs" / "b.md")
    write(tmp_path / "docs" / "specs" / "z.md")
    write(tmp_path / "docs" / "specs" / "A.md")
    result = run(str(tmp_path))[1]
    assert paths(result) == ["docs/specs/A.md", "docs/specs/z.md", "docs/superpowers/specs/b.md"]
    assert set(cats(result).values()) == {"specs"}


def test_results_are_grouped_by_category_then_path(tmp_path):
    write(tmp_path / "docs" / "audits" / "a.md")
    write(tmp_path / "docs" / "specs" / "b.md")
    write(tmp_path / "docs" / "architecture" / "c.md")
    write(tmp_path / "docs" / "architecture" / "B.md")
    assert paths(run(str(tmp_path))[1]) == [
        "docs/architecture/B.md", "docs/architecture/c.md", "docs/specs/b.md", "docs/audits/a.md"]


def test_nested_folders_are_searched(tmp_path):
    write(tmp_path / "docs" / "architecture" / "deep" / "er" / "x.md")
    assert paths(run(str(tmp_path))[1]) == ["docs/architecture/deep/er/x.md"]


def test_titles_come_from_the_first_h1_else_the_file_name(tmp_path):
    write(tmp_path / SPECS / "with-title.md", "intro\n\n# The Title\nbody\n")
    write(tmp_path / SPECS / "plain.md", "no heading here\n")
    write(tmp_path / SPECS / "empty-h1.md", "# \nbody\n")
    by_path = {d["path"]: d["title"] for d in run(str(tmp_path))[1]["docs"]}
    assert by_path[SPECS + "/with-title.md"] == "The Title"
    assert by_path[SPECS + "/plain.md"] == "plain"
    assert by_path[SPECS + "/empty-h1.md"] == "empty-h1"


def test_size_is_reported(tmp_path):
    write(tmp_path / SPECS / "a.md", "# T\n12345")
    assert run(str(tmp_path))[1]["docs"][0]["size"] == len("# T\n12345")


def test_extension_is_case_insensitive_and_other_files_are_ignored(tmp_path):
    write(tmp_path / SPECS / "UP.MD")
    write(tmp_path / SPECS / "notes.txt")
    write(tmp_path / SPECS / "img.png", "x")
    assert paths(run(str(tmp_path))[1]) == [SPECS + "/UP.MD"]


def test_hidden_directories_are_skipped(tmp_path):
    write(tmp_path / SPECS / ".secret" / "x.md")
    write(tmp_path / SPECS / "ok.md")
    assert paths(run(str(tmp_path))[1]) == [SPECS + "/ok.md"]


def test_paths_with_spaces_work(tmp_path):
    write(tmp_path / "docs" / "audits" / "my notes" / "big plan.md")
    assert paths(run(str(tmp_path))[1]) == ["docs/audits/my notes/big plan.md"]


def test_a_symlinked_file_that_escapes_the_project_is_skipped(tmp_path):
    outside = tmp_path / "outside.md"
    outside.write_text("# secret")
    proj = tmp_path / "proj"
    write(proj / SPECS / "ok.md")
    os.symlink(outside, proj / SPECS / "leak.md")
    assert paths(run(str(proj))[1]) == [SPECS + "/ok.md"]


def test_a_symlinked_directory_is_not_followed(tmp_path):
    other = tmp_path / "other"
    write(other / "x.md")
    proj = tmp_path / "proj"
    write(proj / SPECS / "ok.md")
    os.symlink(other, proj / SPECS / "linked")
    assert paths(run(str(proj))[1]) == [SPECS + "/ok.md"]


def test_a_category_folder_symlinked_outside_is_ignored(tmp_path):
    other = tmp_path / "other"
    write(other / "x.md")
    proj = tmp_path / "proj"
    (proj / "docs").mkdir(parents=True)
    os.symlink(other, proj / "docs" / "audits")
    write(proj / SPECS / "ok.md")
    assert paths(run(str(proj))[1]) == [SPECS + "/ok.md"]


def test_the_docs_folder_itself_symlinked_outside_is_ignored(tmp_path):
    other = tmp_path / "other"
    write(other / "specs" / "x.md")
    proj = tmp_path / "proj"
    proj.mkdir()
    os.symlink(other, proj / "docs")
    assert run(str(proj))[1]["docs"] == []


def test_a_symlinked_file_staying_inside_the_project_is_listed(tmp_path):
    proj = tmp_path / "proj"
    write(proj / SPECS / "real.md")
    os.symlink(proj / SPECS / "real.md", proj / SPECS / "alias.md")
    assert paths(run(str(proj))[1]) == [SPECS + "/alias.md", SPECS + "/real.md"]


def test_the_list_is_capped_and_flagged(tmp_path):
    for i in range(505):
        write(tmp_path / SPECS / ("d%04d.md" % i), "x")
    result = run(str(tmp_path))[1]
    assert len(result["docs"]) == 500 and result["truncated"] is True


def test_exactly_the_cap_is_not_truncated(tmp_path):
    for i in range(500):
        write(tmp_path / SPECS / ("d%04d.md" % i), "x")
    result = run(str(tmp_path))[1]
    assert len(result["docs"]) == 500 and result["truncated"] is False


def test_binary_and_empty_files_do_not_crash(tmp_path):
    (tmp_path / SPECS).mkdir(parents=True)
    (tmp_path / SPECS / "bin.md").write_bytes(b"\xff\xfe\x00# nope\x80")
    (tmp_path / SPECS / "empty.md").write_bytes(b"")
    result = run(str(tmp_path))[1]
    assert sorted(paths(result)) == [SPECS + "/bin.md", SPECS + "/empty.md"]


def test_requires_a_path(tmp_path):
    code, result = run()
    assert code == 2 and result["ok"] is False

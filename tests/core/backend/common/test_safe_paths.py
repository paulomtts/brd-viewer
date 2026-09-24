import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), *[".."] * 4, "core", "backend"))
from common import safe_paths


def test_inside_accepts_the_root_and_its_descendants_only():
    assert safe_paths.inside("/a/b", "/a/b")
    assert safe_paths.inside("/a/b", "/a/b/c/d")
    assert not safe_paths.inside("/a/b", "/a/bc")
    assert not safe_paths.inside("/a/b", "/a")


def test_contained_file_returns_the_real_path_of_a_regular_file(tmp_path):
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "x.md").write_text("hi")
    assert safe_paths.contained_file(str(tmp_path), "docs/x.md") == os.path.realpath(tmp_path / "docs" / "x.md")


def test_contained_file_rejects_missing_directories_and_traversal(tmp_path):
    (tmp_path / "root").mkdir()
    (tmp_path / "root" / "d").mkdir()
    (tmp_path / "secret.md").write_text("no")
    root = str(tmp_path / "root")
    assert safe_paths.contained_file(root, "nope.md") is None
    assert safe_paths.contained_file(root, "d") is None
    assert safe_paths.contained_file(root, "../secret.md") is None
    assert safe_paths.contained_file(str(tmp_path / "missing"), "x.md") is None


def test_contained_file_rejects_symlinks_that_escape_the_root(tmp_path):
    (tmp_path / "root").mkdir()
    (tmp_path / "secret.md").write_text("no")
    os.symlink(tmp_path / "secret.md", tmp_path / "root" / "link.md")
    assert safe_paths.contained_file(str(tmp_path / "root"), "link.md") is None


def test_contained_file_follows_a_symlink_that_stays_inside(tmp_path):
    (tmp_path / "a.md").write_text("x")
    os.symlink(tmp_path / "a.md", tmp_path / "b.md")
    assert safe_paths.contained_file(str(tmp_path), "b.md") == os.path.realpath(tmp_path / "a.md")

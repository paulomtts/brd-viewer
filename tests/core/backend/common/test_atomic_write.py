import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), *[".."] * 4, "core", "backend"))
import pytest
from common import atomic_write


def mode(p):
    return os.stat(p).st_mode & 0o777


def test_write_atomic_replaces_content_and_keeps_the_existing_mode(tmp_path):
    p = tmp_path / "f.md"
    p.write_text("old")
    os.chmod(p, 0o600)
    atomic_write.write_atomic(str(p), b"new", 0o644)
    assert p.read_bytes() == b"new"
    assert mode(p) == 0o600
    assert os.listdir(tmp_path) == ["f.md"]


def test_write_atomic_creates_new_files_with_default_or_given_mode(tmp_path):
    atomic_write.write_atomic(str(tmp_path / "a"), b"1")
    atomic_write.write_atomic(str(tmp_path / "b"), b"2", 0o640)
    assert mode(tmp_path / "a") == 0o644
    assert mode(tmp_path / "b") == 0o640
    assert sorted(os.listdir(tmp_path)) == ["a", "b"]


def test_write_atomic_leaves_no_temp_file_when_it_fails(tmp_path):
    with pytest.raises(OSError):
        atomic_write.write_atomic(str(tmp_path / "missing" / "f"), b"x")
    assert os.listdir(tmp_path) == []


def test_write_new_creates_the_file_with_the_given_mode(tmp_path):
    atomic_write.write_new(str(tmp_path / "n.md"), b"hello")
    atomic_write.write_new(str(tmp_path / "m.md"), b"x", 0o600)
    assert (tmp_path / "n.md").read_bytes() == b"hello"
    assert mode(tmp_path / "n.md") == 0o644
    assert mode(tmp_path / "m.md") == 0o600
    assert sorted(os.listdir(tmp_path)) == ["m.md", "n.md"]


def test_write_new_loses_a_race_with_file_exists_error(tmp_path):
    p = tmp_path / "n.md"
    p.write_text("winner")
    with pytest.raises(FileExistsError):
        atomic_write.write_new(str(p), b"loser")
    assert p.read_text() == "winner"
    assert os.listdir(tmp_path) == ["n.md"]


def test_write_new_never_exposes_a_partial_file(tmp_path, monkeypatch):
    p = str(tmp_path / "n.md")
    seen = []
    real_link = os.link

    def spying_link(src, dst):
        seen.append(os.path.exists(dst))
        with open(src, "rb") as f:
            seen.append(f.read())
        real_link(src, dst)

    monkeypatch.setattr(os, "link", spying_link)
    atomic_write.write_new(p, b"complete")
    assert seen == [False, b"complete"]

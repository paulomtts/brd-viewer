"""memory-op.py: save / create / delete a Claude memory note with a mandatory backup."""
import json
import os
import re
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
import memory_lib  # noqa: E402

SCRIPT = os.path.join(HERE, "memory-op.py")

OLD = "---\nname: Old\ndescription: old hook\n---\nold body\n"
NEW = "---\nname: New name\ndescription: new hook\n---\nnew body\n"


def run(tmp_path, *args, cache=None):
    env = dict(os.environ, XDG_CACHE_HOME=str(cache if cache is not None else tmp_path / "cache"),
               CLAUDE_PROJECTS_DIR=str(tmp_path / "projects"))
    proc = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True, env=env)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def memory(tmp_path):
    d = tmp_path / "proj" / "memory"
    d.mkdir(parents=True, exist_ok=True)
    return d


def put(path, text):
    path.write_bytes(text.encode("utf-8"))
    return path


def ok(tmp_path, *args):
    code, result = run(tmp_path, *args)
    assert code == 0 and result["ok"] is True, result
    return result


def refused(tmp_path, *args):
    code, result = run(tmp_path, *args)
    assert code != 0 and result["ok"] is False, result
    return result


def names(directory):
    return sorted(p.name for p in directory.iterdir())


def backups(tmp_path):
    root = tmp_path / "cache" / "omarchy-project-manager" / "memory-backups"
    return sorted(root.glob("*/*")) if root.exists() else []


# --- save ---------------------------------------------------------------

def test_save_replaces_the_note_and_rewrites_only_its_index_line(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    index = "# Memory\n- [Old](a.md) — old hook\n- [B](b.md) — other\nprose line\n"
    put(m / "MEMORY.md", index)
    result = ok(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "a.md").read_bytes() == NEW.encode()
    assert (m / "MEMORY.md").read_text() == "# Memory\n- [New name](a.md) — new hook\n- [B](b.md) — other\nprose line\n"
    backup = result["backup"]
    assert open(os.path.join(backup, "a.md")).read() == OLD
    assert open(os.path.join(backup, "MEMORY.md")).read() == index


def test_save_keeps_the_original_href_spelling(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "- [Old](./a.md) — old hook\n")
    ok(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "MEMORY.md").read_text() == "- [New name](./a.md) — new hook\n"


def test_save_without_a_description_writes_a_bare_link(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "- [Old](a.md) — old hook\n")
    ok(tmp_path, "save", str(m), "a.md", "---\nname: Just a name\n---\nbody\n")
    assert (m / "MEMORY.md").read_text() == "- [Just a name](a.md)\n"


def test_save_without_a_name_uses_the_file_stem(tmp_path):
    m = memory(tmp_path)
    put(m / "some_note.md", OLD)
    put(m / "MEMORY.md", "")
    ok(tmp_path, "save", str(m), "some_note.md", "plain text\n")
    assert (m / "MEMORY.md").read_text() == "- [some_note](some_note.md)\n"


def test_save_appends_a_line_when_the_note_was_not_indexed(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "# Memory\n")
    ok(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "MEMORY.md").read_text() == "# Memory\n- [New name](a.md) — new hook\n"


def test_appending_to_an_index_without_a_final_newline_adds_one(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "# Memory")
    ok(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "MEMORY.md").read_text() == "# Memory\n- [New name](a.md) — new hook\n"


def test_save_creates_the_index_when_missing(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    result = ok(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "MEMORY.md").read_text() == "- [New name](a.md) — new hook\n"
    assert os.listdir(result["backup"]) == ["a.md"]


def test_a_crlf_index_keeps_its_line_endings(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "# M\r\n- [Old](a.md) — h\r\n- [B](b.md)\r\n")
    ok(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "MEMORY.md").read_bytes() == b"# M\r\n- [New name](a.md) \xe2\x80\x94 new hook\r\n- [B](b.md)\r\n"
    put(m / "c.md", OLD)
    ok(tmp_path, "save", str(m), "c.md", NEW)
    assert (m / "MEMORY.md").read_bytes().endswith(b"\r\n- [New name](c.md) \xe2\x80\x94 new hook\r\n")


def test_brackets_and_newlines_cannot_break_the_index_line(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    ok(tmp_path, "save", str(m), "a.md", "---\nname: We [really] mean it\ndescription: x\n---\n")
    line = (m / "MEMORY.md").read_text().strip()
    assert memory_lib.index_link(line) is not None and "\n" not in line


def test_setting_the_same_content_still_keeps_a_valid_index(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", NEW)
    put(m / "MEMORY.md", "- [New name](a.md) — new hook\n")
    ok(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "MEMORY.md").read_text() == "- [New name](a.md) — new hook\n"


def test_save_keeps_the_notes_permissions_and_leaves_no_temp_files(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    os.chmod(m / "a.md", 0o640)
    ok(tmp_path, "save", str(m), "a.md", NEW)
    assert ((m / "a.md").stat().st_mode & 0o777) == 0o640
    assert names(m) == ["MEMORY.md", "a.md"]


def test_save_through_an_alias_inside_the_dir_keeps_the_link(tmp_path):
    m = memory(tmp_path)
    put(m / "real.md", OLD)
    os.symlink(m / "real.md", m / "alias.md")
    ok(tmp_path, "save", str(m), "alias.md", NEW)
    assert (m / "alias.md").is_symlink()
    assert (m / "real.md").read_bytes() == NEW.encode()


def test_save_accepts_multibyte_text_and_the_exact_size_limit(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    ok(tmp_path, "save", str(m), "a.md", "é" * 32768)
    assert len((m / "a.md").read_bytes()) == 65536


# --- create -------------------------------------------------------------

def test_create_writes_the_note_and_appends_to_the_index(tmp_path):
    m = memory(tmp_path)
    index = "# Memory\n- [B](b.md) — other\n"
    put(m / "MEMORY.md", index)
    result = ok(tmp_path, "create", str(m), "new.md", NEW)
    assert (m / "new.md").read_bytes() == NEW.encode()
    assert ((m / "new.md").stat().st_mode & 0o777) == 0o644
    assert (m / "MEMORY.md").read_text() == index + "- [New name](new.md) — new hook\n"
    assert os.listdir(result["backup"]) == ["MEMORY.md"]
    assert names(m) == ["MEMORY.md", "new.md"]


def test_create_in_an_empty_memory_dir_has_nothing_to_back_up(tmp_path):
    m = memory(tmp_path)
    result = ok(tmp_path, "create", str(m), "first.md", NEW)
    assert result["backup"] == ""
    assert (m / "MEMORY.md").read_text() == "- [New name](first.md) — new hook\n"
    assert backups(tmp_path) == []


def test_create_makes_the_memory_dir_when_the_project_dir_exists(tmp_path):
    (tmp_path / "proj").mkdir()
    m = tmp_path / "proj" / "memory"
    ok(tmp_path, "create", str(m), "first.md", NEW)
    assert (m / "first.md").read_bytes() == NEW.encode()


def test_create_refuses_when_the_project_dir_is_missing(tmp_path):
    m = tmp_path / "nope" / "memory"
    refused(tmp_path, "create", str(m), "first.md", NEW)
    assert not (tmp_path / "nope").exists()


def test_create_never_overwrites(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    refused(tmp_path, "create", str(m), "a.md", NEW)
    assert (m / "a.md").read_text() == OLD
    assert backups(tmp_path) == []


def test_create_refuses_a_dangling_symlink_name(tmp_path):
    m = memory(tmp_path)
    os.symlink(tmp_path / "does-not-exist", m / "a.md")
    refused(tmp_path, "create", str(m), "a.md", NEW)
    assert not (tmp_path / "does-not-exist").exists()


# --- delete -------------------------------------------------------------

def test_delete_removes_the_note_and_only_its_index_lines(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "b.md", OLD)
    index = "# Memory\n- [A](a.md) — one\nkeep me\n- [B](b.md) — two\n- [A again](./a.md)\n\ntrailer\n"
    put(m / "MEMORY.md", index)
    result = ok(tmp_path, "delete", str(m), "a.md")
    assert names(m) == ["MEMORY.md", "b.md"]
    assert (m / "MEMORY.md").read_text() == "# Memory\nkeep me\n- [B](b.md) — two\n\ntrailer\n"
    backup = result["backup"]
    assert open(os.path.join(backup, "a.md")).read() == OLD
    assert open(os.path.join(backup, "MEMORY.md")).read() == index


def test_delete_leaves_an_index_without_the_link_alone(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "# Memory\r\n- [B](b.md)\r\n")
    before = (m / "MEMORY.md").stat().st_mtime_ns
    ok(tmp_path, "delete", str(m), "a.md")
    assert (m / "MEMORY.md").read_bytes() == b"# Memory\r\n- [B](b.md)\r\n"
    assert (m / "MEMORY.md").stat().st_mtime_ns == before
    assert names(m) == ["MEMORY.md"]


def test_delete_keeps_crlf_endings(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "# M\r\n- [A](a.md)\r\n- [B](b.md)\r\n")
    ok(tmp_path, "delete", str(m), "a.md")
    assert (m / "MEMORY.md").read_bytes() == b"# M\r\n- [B](b.md)\r\n"


def test_delete_works_without_an_index(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    result = ok(tmp_path, "delete", str(m), "a.md")
    assert names(m) == []
    assert os.listdir(result["backup"]) == ["a.md"]


def test_delete_of_a_missing_note_is_refused(tmp_path):
    m = memory(tmp_path)
    put(m / "MEMORY.md", "- [A](a.md)\n")
    refused(tmp_path, "delete", str(m), "a.md")
    assert (m / "MEMORY.md").read_text() == "- [A](a.md)\n"


# --- backups ------------------------------------------------------------

def test_backups_live_under_the_cache_per_project_and_timestamp(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    result = ok(tmp_path, "save", str(m), "a.md", NEW)
    got = backups(tmp_path)
    assert [str(p) for p in got] == [result["backup"]]
    assert got[0].parent.name == "proj"
    assert re.fullmatch(r"\d{8}T\d{12}Z", got[0].name)


def test_two_operations_make_two_backups(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    ok(tmp_path, "save", str(m), "a.md", NEW)
    ok(tmp_path, "save", str(m), "a.md", OLD)
    assert len(backups(tmp_path)) == 2


def test_a_backup_failure_aborts_and_changes_nothing(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(m / "MEMORY.md", "- [Old](a.md) — old hook\n")
    blocker = tmp_path / "not-a-dir"
    blocker.write_text("x")
    for args in [("save", str(m), "a.md", NEW), ("delete", str(m), "a.md"), ("create", str(m), "n.md", NEW)]:
        code, result = run(tmp_path, *args, cache=blocker)
        assert code != 0 and result["ok"] is False
    assert (m / "a.md").read_text() == OLD
    assert (m / "MEMORY.md").read_text() == "- [Old](a.md) — old hook\n"
    assert names(m) == ["MEMORY.md", "a.md"]


# --- refusals -----------------------------------------------------------

@pytest.mark.parametrize("name", ["../x.md", "sub/x.md", ".", "..", "", "x.txt", "X.MD", "x.md.bak",
                                  "MEMORY.md", "/etc/passwd"])
def test_bad_file_names_are_refused(tmp_path, name):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    put(tmp_path / "proj" / "x.md", "outside")
    for op in ["save", "create", "delete"]:
        args = [op, str(m), name] + ([NEW] if op != "delete" else [])
        code, result = run(tmp_path, *args)
        assert code != 0 and result["ok"] is False, (op, name)
    assert (m / "a.md").read_text() == OLD
    assert (tmp_path / "proj" / "x.md").read_text() == "outside"
    assert not (m / "MEMORY.md").exists()


def test_the_directory_must_be_called_memory(tmp_path):
    d = tmp_path / "proj" / "notes"
    d.mkdir(parents=True)
    put(d / "a.md", OLD)
    refused(tmp_path, "save", str(d), "a.md", NEW)
    refused(tmp_path, "delete", str(d), "a.md")
    assert (d / "a.md").read_text() == OLD


def test_a_symlinked_memory_dir_is_refused(tmp_path):
    real = tmp_path / "elsewhere"
    real.mkdir()
    put(real / "a.md", OLD)
    (tmp_path / "proj").mkdir()
    os.symlink(real, tmp_path / "proj" / "memory")
    refused(tmp_path, "save", str(tmp_path / "proj" / "memory"), "a.md", NEW)
    assert (real / "a.md").read_text() == OLD


def test_a_missing_note_or_memory_dir_cannot_be_saved(tmp_path):
    m = memory(tmp_path)
    refused(tmp_path, "save", str(m), "ghost.md", NEW)
    refused(tmp_path, "save", str(tmp_path / "gone" / "memory"), "a.md", NEW)
    assert names(m) == []


def test_a_symlinked_note_escaping_the_dir_is_refused(tmp_path):
    m = memory(tmp_path)
    outside = tmp_path / "outside.md"
    outside.write_text("secret")
    os.symlink(outside, m / "leak.md")
    refused(tmp_path, "save", str(m), "leak.md", NEW)
    refused(tmp_path, "delete", str(m), "leak.md")
    assert outside.read_text() == "secret"
    assert (m / "leak.md").is_symlink()


def test_a_symlinked_index_escaping_the_dir_is_refused_before_any_change(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    outside = tmp_path / "outside-index.md"
    outside.write_text("secret\n")
    os.symlink(outside, m / "MEMORY.md")
    refused(tmp_path, "save", str(m), "a.md", NEW)
    assert (m / "a.md").read_text() == OLD and outside.read_text() == "secret\n"
    assert backups(tmp_path) == []


def test_oversized_content_is_refused(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    refused(tmp_path, "save", str(m), "a.md", "x" * 65537)
    refused(tmp_path, "save", str(m), "a.md", "é" * 32769)
    refused(tmp_path, "create", str(m), "b.md", "x" * 65537)
    assert (m / "a.md").read_text() == OLD and names(m) == ["a.md"]


def test_undecodable_content_is_refused(tmp_path):
    m = memory(tmp_path)
    put(m / "a.md", OLD)
    refused(tmp_path, "save", str(m), "a.md", "bad \udcff byte")
    assert (m / "a.md").read_text() == OLD


def test_content_with_a_nul_byte_is_refused():
    with pytest.raises(memory_lib.Refused):
        memory_lib.check_content("abc\x00def")
    with pytest.raises(memory_lib.Refused):
        memory_lib.check_content(None)
    assert memory_lib.check_content("fine") == b"fine"


def test_usage_errors_exit_2(tmp_path):
    m = memory(tmp_path)
    for args in [(), ("save",), ("save", str(m)), ("save", str(m), "a.md"), ("create", str(m), "a.md"),
                 ("explode", str(m), "a.md", "x"), ("delete", str(m))]:
        code, result = run(tmp_path, *args)
        assert code == 2 and result["ok"] is False, args


# --- review fixes -------------------------------------------------------

def test_parallel_creates_of_one_name_let_exactly_one_win(tmp_path):
    d = memory(tmp_path)
    env = dict(os.environ, XDG_CACHE_HOME=str(tmp_path / "cache"))
    procs = [subprocess.Popen([sys.executable, SCRIPT, "create", str(d), "same.md", "---\nname: N%d\n---\nb%d\n" % (i, i)],
                              stdout=subprocess.PIPE, text=True, env=env) for i in range(6)]
    results = [json.loads(p.communicate()[0].strip().splitlines()[-1]) for p in procs]
    assert sum(1 for r in results if r["ok"]) == 1
    assert names(d) == ["MEMORY.md", "same.md"]


def test_parallel_creates_of_different_notes_keep_every_index_line(tmp_path):
    d = memory(tmp_path)
    env = dict(os.environ, XDG_CACHE_HOME=str(tmp_path / "cache"))
    procs = [subprocess.Popen([sys.executable, SCRIPT, "create", str(d), "n%d.md" % i, "---\nname: N%d\ndescription: h\n---\nb\n" % i],
                              stdout=subprocess.PIPE, text=True, env=env) for i in range(12)]
    assert all(json.loads(p.communicate()[0].strip().splitlines()[-1])["ok"] for p in procs)
    index = (d / "MEMORY.md").read_text()
    for i in range(12):
        assert "(n%d.md)" % i in index
    assert len(index.splitlines()) == 12


def test_control_characters_in_a_file_name_are_refused_everywhere(tmp_path):
    d = memory(tmp_path)
    put(d / "ok.md", OLD)
    for op in ("save", "create", "delete"):
        for bad in ["a\nb.md", "a\rb.md", "a\tb.md", "a\x1fb.md"]:
            args = [op, str(d), bad] + ([NEW] if op != "delete" else [])
            refused(tmp_path, *args)


def test_create_refuses_names_that_would_break_the_index_link_syntax(tmp_path):
    d = memory(tmp_path)
    for bad in ["a(b).md", "a[b].md", "a)b.md", "a]b.md"]:
        refused(tmp_path, "create", str(d), bad, NEW)
    assert names(d) == []


def test_an_existing_awkward_name_can_still_be_saved_and_deleted(tmp_path):
    d = memory(tmp_path)
    put(d / "a(b).md", OLD)
    ok(tmp_path, "save", str(d), "a(b).md", NEW)
    assert (d / "a(b).md").read_text() == NEW
    ok(tmp_path, "delete", str(d), "a(b).md")
    assert not (d / "a(b).md").exists()


def test_save_with_an_expected_text_refuses_when_the_note_changed_on_disk(tmp_path):
    d = memory(tmp_path)
    note = put(d / "a.md", OLD)
    result = refused(tmp_path, "save", str(d), "a.md", NEW, "something else entirely")
    assert "changed" in result["error"].lower()
    assert note.read_text() == OLD
    ok(tmp_path, "save", str(d), "a.md", NEW, OLD)
    assert note.read_text() == NEW


def test_save_without_an_expected_text_still_works(tmp_path):
    d = memory(tmp_path)
    note = put(d / "a.md", OLD)
    ok(tmp_path, "save", str(d), "a.md", NEW)
    assert note.read_text() == NEW

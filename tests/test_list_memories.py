"""list-memories.py over throwaway Claude project directories."""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(HERE, "list-memories.py")


def run(tmp_path, *args):
    env = dict(os.environ, CLAUDE_PROJECTS_DIR=str(tmp_path / "projects"),
               XDG_CACHE_HOME=str(tmp_path / "cache"))
    proc = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True, env=env)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def listing(tmp_path, root="/work/app"):
    code, result = run(tmp_path, root)
    assert code == 0 and result["ok"] is True, result
    return result


def project(tmp_path, slug):
    d = tmp_path / "projects" / slug
    (d / "memory").mkdir(parents=True, exist_ok=True)
    return d / "memory"


def note(memory, name, text="body\n"):
    (memory / name).write_text(text, encoding="utf-8")


def fm(name=None, description=None, type_=None, nested=True, extra=""):
    lines = ["---"]
    if name is not None:
        lines.append("name: " + name)
    if description is not None:
        lines.append("description: " + description)
    if type_ is not None:
        lines.append(("metadata:\n  type: " if nested else "type: ") + type_)
    if extra:
        lines.append(extra)
    lines.append("---")
    return "\n".join(lines) + "\nbody\n"


def by_file(result):
    return {n["file"]: n for n in result["notes"]}


def test_requires_a_path(tmp_path):
    code, result = run(tmp_path)
    assert code == 2 and result["ok"] is False


def test_the_project_is_found_by_its_slug(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", fm(name="A"))
    result = listing(tmp_path)
    assert result["found"] is True
    assert result["memory_dir"] == str(memory)
    assert [n["file"] for n in result["notes"]] == ["a.md"]


def test_dots_underscores_and_spaces_in_the_path_become_dashes(tmp_path):
    memory = project(tmp_path, "-work-my-app-v2-sub-dir")
    note(memory, "a.md", fm(name="A"))
    result = listing(tmp_path, "/work/my.app_v2/sub dir")
    assert result["found"] is True and result["memory_dir"] == str(memory)


def test_a_transcript_cwd_finds_a_project_the_slug_misses(tmp_path):
    memory = project(tmp_path, "renamed-elsewhere")
    note(memory, "a.md", fm(name="A"))
    (memory.parent / "s1.jsonl").write_text(
        'not json\n{"type": "user"}\n{"cwd": "/work/app", "x": 1}\n', encoding="utf-8")
    other = project(tmp_path, "unrelated")
    (other.parent / "s.jsonl").write_text('{"cwd": "/somewhere/else"}\n', encoding="utf-8")
    result = listing(tmp_path)
    assert result["found"] is True and result["memory_dir"] == str(memory)


def test_a_project_nobody_recorded_is_not_found(tmp_path):
    project(tmp_path, "-other-project")
    assert listing(tmp_path) == {"ok": True, "found": False, "memory_dir": "", "notes": []}


def test_a_missing_projects_root_is_not_found(tmp_path):
    assert listing(tmp_path) == {"ok": True, "found": False, "memory_dir": "", "notes": []}


def test_a_project_without_a_memory_dir_reports_where_it_would_be(tmp_path):
    (tmp_path / "projects" / "-work-app").mkdir(parents=True)
    result = listing(tmp_path)
    assert result["found"] is False
    assert result["memory_dir"] == str(tmp_path / "projects" / "-work-app" / "memory")
    assert result["notes"] == []


def test_a_memory_dir_symlinked_outside_the_projects_root_is_not_found(tmp_path):
    outside = tmp_path / "outside" / "memory"
    outside.mkdir(parents=True)
    note(outside, "leak.md", fm(name="Leak"))
    proj = tmp_path / "projects" / "-work-app"
    proj.mkdir(parents=True)
    os.symlink(outside, proj / "memory")
    result = listing(tmp_path)
    assert result["found"] is False and result["notes"] == []


def test_frontmatter_fields_and_a_top_level_type(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", fm(name="Alpha", description="About alpha", type_="feedback", nested=False))
    n = by_file(listing(tmp_path))["a.md"]
    assert (n["name"], n["description"], n["type"]) == ("Alpha", "About alpha", "feedback")


def test_a_type_nested_under_metadata_is_read(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", fm(name="A", type_="project"))
    assert by_file(listing(tmp_path))["a.md"]["type"] == "project"


def test_a_top_level_type_beats_the_nested_one(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", "---\nname: A\ntype: user\nmetadata:\n  type: project\n---\nbody\n")
    assert by_file(listing(tmp_path))["a.md"]["type"] == "user"


def test_unknown_or_missing_types_are_other(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", fm(name="A", type_="banana"))
    note(memory, "b.md", fm(name="B"))
    note(memory, "c.md", "no frontmatter\n")
    got = by_file(listing(tmp_path))
    assert {got[f]["type"] for f in ["a.md", "b.md", "c.md"]} == {"other"}


def test_type_values_are_case_insensitive(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", fm(name="A", type_="Feedback"))
    assert by_file(listing(tmp_path))["a.md"]["type"] == "feedback"


def test_quotes_around_values_are_stripped(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", "---\nname: \"Quoted name\"\ndescription: 'single quoted'\n---\nbody\n")
    n = by_file(listing(tmp_path))["a.md"]
    assert (n["name"], n["description"]) == ("Quoted name", "single quoted")


def test_malformed_frontmatter_is_ignored_not_fatal(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "unclosed.md", "---\nname: Never closed\ntype: user\nbody\n")
    note(memory, "junk.md", "---\n: :\n\x01\nnot yaml at all\n---\nbody\n")
    note(memory, "mid.md", "text\n---\nname: Not front\n---\n")
    got = by_file(listing(tmp_path))
    assert got["unclosed.md"]["name"] == "unclosed" and got["unclosed.md"]["type"] == "other"
    assert got["mid.md"]["name"] == "mid"
    assert "junk.md" in got


def test_without_frontmatter_the_index_supplies_title_and_hook(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", "plain text\n")
    note(memory, "b.md", "plain text\n")
    note(memory, "c.md", "plain text\n")
    (memory / "MEMORY.md").write_text(
        "# Index\n- [Alpha title](a.md) — the a hook\n- [Beta](./b.md) - dash hook\n- [Gamma](c.md)\n",
        encoding="utf-8")
    got = by_file(listing(tmp_path))
    assert (got["a.md"]["name"], got["a.md"]["description"]) == ("Alpha title", "the a hook")
    assert (got["b.md"]["name"], got["b.md"]["description"]) == ("Beta", "dash hook")
    assert (got["c.md"]["name"], got["c.md"]["description"]) == ("Gamma", "")


def test_frontmatter_wins_over_the_index(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", fm(name="From file", description="file desc"))
    (memory / "MEMORY.md").write_text("- [From index](a.md) — index hook\n", encoding="utf-8")
    n = by_file(listing(tmp_path))["a.md"]
    assert (n["name"], n["description"]) == ("From file", "file desc")


def test_with_neither_the_name_is_the_file_stem(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "lonely_note.md", "text\n")
    n = by_file(listing(tmp_path))["lonely_note.md"]
    assert (n["name"], n["description"], n["indexed"]) == ("lonely_note", "", False)


def test_indexed_reflects_a_link_line_and_normalises_dot_slash(tmp_path):
    memory = project(tmp_path, "-work-app")
    for name in ["a.md", "b.md", "c.md"]:
        note(memory, name, fm(name=name))
    (memory / "MEMORY.md").write_text("- [A](a.md) — x\n- [B](./b.md)\nprose mentioning c.md\n", encoding="utf-8")
    got = by_file(listing(tmp_path))
    assert (got["a.md"]["indexed"], got["b.md"]["indexed"], got["c.md"]["indexed"]) == (True, True, False)


def test_notes_sort_by_type_then_name(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "1.md", fm(name="zed", type_="reference"))
    note(memory, "2.md", fm(name="Beta", type_="user"))
    note(memory, "3.md", fm(name="alpha", type_="user"))
    note(memory, "4.md", fm(name="misc"))
    note(memory, "5.md", fm(name="proj", type_="project"))
    note(memory, "6.md", fm(name="fb", type_="feedback"))
    assert [n["file"] for n in listing(tmp_path)["notes"]] == ["3.md", "2.md", "6.md", "5.md", "1.md", "4.md"]


def test_memory_md_and_non_notes_are_not_listed(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "MEMORY.md", "- [A](a.md)\n")
    note(memory, "memory.md", fm(name="lowercase is a note"))
    note(memory, "a.md", fm(name="A"))
    note(memory, "readme.txt", "x")
    (memory / "sub").mkdir()
    note(memory / "sub", "deep.md", fm(name="deep"))
    assert sorted(n["file"] for n in listing(tmp_path)["notes"]) == ["a.md", "memory.md"]


def test_a_symlink_escaping_the_memory_dir_is_skipped(tmp_path):
    memory = project(tmp_path, "-work-app")
    outside = tmp_path / "outside.md"
    outside.write_text("# secret\n")
    note(memory, "ok.md", fm(name="OK"))
    os.symlink(outside, memory / "leak.md")
    note(memory, "real.md", fm(name="Real"))
    os.symlink(memory / "real.md", memory / "alias.md")
    assert sorted(n["file"] for n in listing(tmp_path)["notes"]) == ["alias.md", "ok.md", "real.md"]


def test_the_list_is_capped_at_500(tmp_path):
    memory = project(tmp_path, "-work-app")
    for i in range(505):
        note(memory, "n%04d.md" % i, "x\n")
    assert len(listing(tmp_path)["notes"]) == 500


def test_size_is_reported_and_binary_or_empty_files_do_not_crash(tmp_path):
    memory = project(tmp_path, "-work-app")
    note(memory, "a.md", "12345")
    (memory / "bin.md").write_bytes(b"\xff\xfe\x00---\x80")
    (memory / "empty.md").write_bytes(b"")
    got = by_file(listing(tmp_path))
    assert got["a.md"]["size"] == 5 and got["empty.md"]["size"] == 0
    assert "bin.md" in got

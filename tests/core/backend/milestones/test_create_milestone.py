"""create-milestone.py: manual mode, `brd add` through a fake brd on a temp PATH."""
import json
import os
import stat
import subprocess
import sys

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..",
                      "core", "backend", "milestones", "create-milestone.py")

FAKE = """#!/usr/bin/env python3
import json, os, sys
log = os.environ["FAKE_BRD_LOG"]
with open(log, "w") as f:
    json.dump({"argv": sys.argv, "cwd": os.getcwd()}, f)
if os.environ.get("FAKE_BRD_FAIL"):
    sys.stderr.write(os.environ["FAKE_BRD_FAIL"] + "\\n")
    sys.exit(3)
if os.environ.get("FAKE_BRD_NESTED"):
    print(json.dumps({"card": {"id": "nested1"}}))
elif os.environ.get("FAKE_BRD_GARBAGE"):
    print("not json")
else:
    print(json.dumps({"id": "abc12345", "title": "x"}))
"""


def setup(tmp_path, with_brd=True):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    if with_brd:
        b = bindir / "brd"
        b.write_text(FAKE)
        b.chmod(b.stat().st_mode | stat.S_IXUSR)
    proj = tmp_path / "proj"
    proj.mkdir()
    return bindir, proj


def run(tmp_path, args, bindir, **env):
    e = {"PATH": str(bindir) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
         "FAKE_BRD_LOG": str(tmp_path / "log.json"), **env}
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True, env=e)
    out = p.stdout.strip().splitlines()
    return p.returncode, (json.loads(out[-1]) if out else None)


def recorded(tmp_path):
    return json.loads((tmp_path / "log.json").read_text())


def test_runs_brd_add_with_title_and_description_in_the_project(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1", "--description", "Goal"], bindir)
    assert code == 0 and res == {"ok": True, "id": "abc12345"}
    rec = recorded(tmp_path)
    assert rec["argv"][1:] == ["add", "--title", "M1", "--description", "Goal"]
    assert os.path.samefile(rec["cwd"], proj)


def test_description_is_omitted_when_empty(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1", "--description", "  "], bindir)
    assert code == 0 and res["ok"] is True
    assert recorded(tmp_path)["argv"][1:] == ["add", "--title", "M1"]


def test_nested_card_id_is_accepted(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1"], bindir, FAKE_BRD_NESTED="1")
    assert code == 0 and res == {"ok": True, "id": "nested1"}


def test_empty_title_is_refused_without_running_brd(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "   "], bindir)
    assert code == 1 and res["ok"] is False
    assert not (tmp_path / "log.json").exists()


def test_missing_brd_is_refused(tmp_path):
    bindir, proj = setup(tmp_path, with_brd=False)
    code, res = run(tmp_path, [str(proj), "--title", "M1"], bindir)
    assert code == 1 and res["ok"] is False and "brd" in res["error"]


def test_missing_project_is_refused(tmp_path):
    bindir, _ = setup(tmp_path)
    code, res = run(tmp_path, [str(tmp_path / "nope"), "--title", "M1"], bindir)
    assert code == 1 and res["ok"] is False
    assert not (tmp_path / "log.json").exists()


def test_brd_failure_reports_its_message(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1"], bindir, FAKE_BRD_FAIL="boom happened")
    assert code == 1 and res["ok"] is False and "boom happened" in res["error"]


def test_unparseable_brd_output_is_an_error(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1"], bindir, FAKE_BRD_GARBAGE="1")
    assert code == 1 and res["ok"] is False


def test_usage_error_exits_2(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj)], bindir)
    assert code == 2 and res["ok"] is False

"""create-milestone.py: manual mode, `brd add` through a fake brd on a temp PATH."""
import json
import os
import shutil
import stat
import subprocess
import sys

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..",
                      "core", "backend", "milestones", "create-milestone.py")

FAKE = """#!/usr/bin/env python3
import json, os, sys
log = os.environ["FAKE_BRD_LOG"]
with open(log, "w") as f:
    json.dump({"argv": sys.argv, "cwd": os.getcwd()}, f)
mode = os.environ.get("FAKE_BRD_MODE", "ok")
if mode == "notfound":
    print(json.dumps({"ok": False, "error": {"type": "ProjectNotFoundError", "message": "no .brd marker found above /x"}}))
    sys.exit(1)
if mode == "usage":
    sys.stderr.write("Usage: brd add [OPTIONS]\\nError: Missing option '--title'.\\n")
    sys.exit(2)
if mode == "garbage":
    print("not json")
    sys.exit(0)
print(json.dumps({"ok": True, "data": {"id": "abc12345-uuid", "title": "x", "description": "", "status": "todo",
                                        "parent_id": None, "blocked_by": [], "children": []}}))
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
    assert code == 0 and res == {"ok": True, "id": "abc12345-uuid"}
    rec = recorded(tmp_path)
    assert rec["argv"][1:] == ["add", "--title", "M1", "--description", "Goal"]
    assert os.path.samefile(rec["cwd"], proj)


def test_description_is_omitted_when_empty(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1", "--description", "  "], bindir)
    assert code == 0 and res["ok"] is True
    assert recorded(tmp_path)["argv"][1:] == ["add", "--title", "M1"]


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


def test_brd_error_object_is_surfaced_as_a_string(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1"], bindir, FAKE_BRD_MODE="notfound")
    assert code == 1
    assert res == {"ok": False, "error": "ProjectNotFoundError: no .brd marker found above /x"}


def test_non_json_usage_failure_reports_stderr(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1"], bindir, FAKE_BRD_MODE="usage")
    assert code == 1 and res["ok"] is False and "Missing option" in res["error"]


def test_unparseable_brd_output_is_an_error(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj), "--title", "M1"], bindir, FAKE_BRD_MODE="garbage")
    assert code == 1 and res["ok"] is False


@pytest.mark.skipif(shutil.which("brd") is None, reason="real brd not installed")
def test_contract_against_the_real_brd(tmp_path):
    """Guards against drift in brd's output shape; fully sandboxed."""
    proj = tmp_path / "proj"
    proj.mkdir()
    env = {**os.environ, "HOME": str(tmp_path / "home"), "XDG_DATA_HOME": str(tmp_path / "data"),
           "XDG_CONFIG_HOME": str(tmp_path / "cfg"), "XDG_STATE_HOME": str(tmp_path / "state")}
    init = subprocess.run(["brd", "init"], cwd=proj, env=env, capture_output=True, text=True)
    assert init.returncode == 0, init.stdout + init.stderr
    p = subprocess.run([sys.executable, SCRIPT, str(proj), "--title", "Real", "--description", "D"],
                       env=env, capture_output=True, text=True)
    res = json.loads(p.stdout.strip().splitlines()[-1])
    assert p.returncode == 0 and res["ok"] is True and res["id"]
    tree = subprocess.run(["brd", "list"], cwd=proj, env=env, capture_output=True, text=True)
    assert res["id"] in tree.stdout


def test_usage_error_exits_2(tmp_path):
    bindir, proj = setup(tmp_path)
    code, res = run(tmp_path, [str(proj)], bindir)
    assert code == 2 and res["ok"] is False

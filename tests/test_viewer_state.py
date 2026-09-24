"""viewer-state.py in a throwaway XDG_STATE_HOME: the real state file is never touched."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "viewer-state.py")


@pytest.fixture
def env(tmp_path):
    return {"HOME": str(tmp_path / "home"), "XDG_STATE_HOME": str(tmp_path / "state"),
            "PATH": os.environ.get("PATH", "")}


def state_file(env):
    return Path(env["XDG_STATE_HOME"]) / "omarchy-project-manager" / "state.json"


def run(env, *args):
    proc = subprocess.run([sys.executable, SCRIPT, *args], env=env, capture_output=True, text=True)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def test_get_with_no_file_is_null(env):
    assert run(env, "get") == (0, {"last_project": None})


@pytest.mark.parametrize("content", ["", "not json", "[1, 2]", '"text"', '{"last_project": 5}', '{"last_project": ""}'])
def test_get_treats_bad_content_as_null(env, content):
    state_file(env).parent.mkdir(parents=True)
    state_file(env).write_text(content)
    assert run(env, "get") == (0, {"last_project": None})


def test_set_then_get_round_trips(env):
    assert run(env, "set-project", "/home/u/my proj") == (0, {"ok": True})
    assert run(env, "get") == (0, {"last_project": "/home/u/my proj"})


def test_set_replaces_the_previous_project(env):
    run(env, "set-project", "/a")
    run(env, "set-project", "/b")
    assert run(env, "get")[1] == {"last_project": "/b"}


def test_set_preserves_other_keys(env):
    state_file(env).parent.mkdir(parents=True)
    state_file(env).write_text(json.dumps({"other": {"x": 1}, "last_project": "/old"}))
    run(env, "set-project", "/new")
    data = json.loads(state_file(env).read_text())
    assert data == {"other": {"x": 1}, "last_project": "/new"}


def test_set_leaves_no_temp_files_behind(env):
    run(env, "set-project", "/a")
    assert [p.name for p in state_file(env).parent.iterdir()] == ["state.json"]


def test_defaults_to_dot_local_state_under_home(env):
    del env["XDG_STATE_HOME"]
    run(env, "set-project", "/a")
    assert (Path(env["HOME"]) / ".local" / "state" / "omarchy-project-manager" / "state.json").is_file()


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores directory permissions")
def test_unwritable_directory_fails_cleanly(env):
    d = state_file(env).parent
    d.mkdir(parents=True)
    d.chmod(0o500)
    try:
        code, result = run(env, "set-project", "/a")
    finally:
        d.chmod(0o700)
    assert code == 1 and result["ok"] is False and result["error"]


@pytest.mark.parametrize("args", [(), ("set-project",), ("set-project", ""), ("bogus",)])
def test_bad_usage_is_rejected(env, args):
    code, result = run(env, *args)
    assert code == 2 and result["ok"] is False


def test_get_falls_back_to_the_state_left_by_the_old_brd_viewer_name(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"last_project": "/home/u/old"}')
    assert run(env, "get") == (0, {"last_project": "/home/u/old"})
    assert run(env, "set-project", "/home/u/new")[0] == 0
    assert run(env, "get") == (0, {"last_project": "/home/u/new"})
    assert json.loads(old.read_text())["last_project"] == "/home/u/old"
    assert state_file(env).is_file()


def test_the_new_state_file_wins_over_the_old_one(env):
    old = Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"
    old.parent.mkdir(parents=True)
    old.write_text('{"last_project": "/home/u/old"}')
    state_file(env).parent.mkdir(parents=True)
    state_file(env).write_text('{"last_project": "/home/u/new"}')
    assert run(env, "get") == (0, {"last_project": "/home/u/new"})

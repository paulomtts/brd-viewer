"""run-setup-milestone.py: validation, agent resolution, spawn, log, cancel/timeout.

Hermetic: a fake `omarchy-default-agent`, a fake agent binary and a fake `brd` live on a
temp PATH; HOME and XDG_STATE_HOME are temp. No real agent is ever started.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "..")
SCRIPT = os.path.join(ROOT, "core", "backend", "milestones", "run-setup-milestone.py")

FAKE_DEFAULT_AGENT = """#!/usr/bin/env python3
import os, sys
name = os.environ.get("FAKE_DEFAULT_AGENT", "claude")
if name == "!fail":
    sys.stderr.write("boom\\n")
    sys.exit(1)
print(name)
"""

# The fake agent records argv/cwd/env, then behaves per FAKE_AGENT_MODE:
#   ok    -> exits 0;  fail -> exits 3
#   hang  -> starts a grandchild (`sleep 300`), records both pids, sleeps forever
FAKE_AGENT = """#!/usr/bin/env python3
import json, os, subprocess, sys, time
rec = {"argv": sys.argv, "cwd": os.getcwd()}
with open(os.environ["FAKE_AGENT_REC"], "w") as f:
    json.dump(rec, f)
sys.stdout.write("agent said hello\\n")
sys.stdout.flush()
mode = os.environ.get("FAKE_AGENT_MODE", "ok")
if mode == "fail":
    sys.stderr.write("agent failed\\n")
    sys.exit(3)
if mode == "hang":
    child = subprocess.Popen(["sleep", "300"])
    with open(os.environ["FAKE_AGENT_PIDS"], "w") as f:
        json.dump({"agent": os.getpid(), "child": child.pid}, f)
    time.sleep(300)
sys.exit(0)
"""


def write_exec(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def world(tmp_path):
    """A temp PATH with fakes, a temp HOME/XDG_STATE_HOME, and a project with a spec."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    write_exec(bindir / "omarchy-default-agent", FAKE_DEFAULT_AGENT)
    write_exec(bindir / "claude", FAKE_AGENT)
    write_exec(bindir / "brd", "#!/bin/sh\nexit 0\n")
    proj = tmp_path / "proj"
    (proj / "docs").mkdir(parents=True)
    spec = proj / "docs" / "spec.md"
    spec.write_text("# A spec\n")
    state = tmp_path / "state"
    home = tmp_path / "home"
    home.mkdir()
    return {"tmp": tmp_path, "bin": bindir, "proj": proj, "spec": spec,
            "state": state, "home": home}


def env_for(world, **extra):
    e = {
        "PATH": str(world["bin"]) + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
        "HOME": str(world["home"]),
        "XDG_STATE_HOME": str(world["state"]),
        "FAKE_AGENT_REC": str(world["tmp"] / "rec.json"),
        "FAKE_AGENT_PIDS": str(world["tmp"] / "pids.json"),
        "OPM_AGENT_TIMEOUT_SECONDS": "20",
    }
    e.update(extra)
    return e


def run(world, args, **extra):
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True,
                       env=env_for(world, **extra), timeout=60)
    lines = p.stdout.strip().splitlines()
    assert len(lines) == 1, p.stdout
    return p.returncode, json.loads(lines[0])


def recorded(world):
    return json.loads((world["tmp"] / "rec.json").read_text())


def logdir(world):
    return world["state"] / "omarchy-project-manager" / "agent-logs"


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def wait_gone(pid, limit=10.0):
    end = time.monotonic() + limit
    while time.monotonic() < end:
        if not alive(pid):
            return True
        time.sleep(0.05)
    return not alive(pid)


# --- validation -------------------------------------------------------------

def test_usage_error_without_two_arguments(world):
    code, res = run(world, [str(world["proj"])])
    assert code == 2
    assert res["error"] == "usage: run-setup-milestone.py <project_root> <spec_path>"
    assert res["ok"] is False


def test_missing_project_folder(world):
    code, res = run(world, [str(world["tmp"] / "nope"), str(world["spec"])])
    assert code == 1 and res["error"] == "Project folder not found."
    assert not (world["tmp"] / "rec.json").exists()


def test_missing_spec_file(world):
    code, res = run(world, [str(world["proj"]), "docs/other.md"])
    assert code == 1 and res["error"] == "Spec file not found."


def test_a_directory_is_not_a_spec(world):
    code, res = run(world, [str(world["proj"]), "docs"])
    assert code == 1 and res["error"] == "Spec file not found."


def test_spec_outside_the_project_is_refused(world):
    outside = world["tmp"] / "outside.md"
    outside.write_text("# elsewhere\n")
    code, res = run(world, [str(world["proj"]), str(outside)])
    assert code == 1 and res["error"] == "The spec file is outside the project."


def test_symlink_escaping_the_project_is_refused(world):
    outside = world["tmp"] / "outside.md"
    outside.write_text("# elsewhere\n")
    link = world["proj"] / "docs" / "link.md"
    os.symlink(outside, link)
    code, res = run(world, [str(world["proj"]), "docs/link.md"])
    assert code == 1 and res["error"] == "The spec file is outside the project."
    assert not (world["tmp"] / "rec.json").exists()


def test_brd_must_be_installed(world):
    os.remove(world["bin"] / "brd")
    code, res = run(world, [str(world["proj"]), str(world["spec"])])
    assert code == 1 and res["error"] == "brd is not installed."


def test_no_default_agent_set(world):
    code, res = run(world, [str(world["proj"]), str(world["spec"])], FAKE_DEFAULT_AGENT="")
    assert code == 1 and res["error"] == "No default agent is set."
    assert res["agent"] == ""


def test_default_agent_command_failing_reads_as_no_agent(world):
    code, res = run(world, [str(world["proj"]), str(world["spec"])], FAKE_DEFAULT_AGENT="!fail")
    assert code == 1 and res["error"] == "No default agent is set."


def test_unsupported_agent(world):
    code, res = run(world, [str(world["proj"]), str(world["spec"])],
                    FAKE_DEFAULT_AGENT="openclaw")
    assert code == 1 and res["error"] == "openclaw has no supported unattended mode."
    assert res["agent"] == "openclaw"


def test_supported_agent_that_is_not_installed(world):
    os.remove(world["bin"] / "claude")
    code, res = run(world, [str(world["proj"]), str(world["spec"])])
    assert code == 1 and res["error"] == "claude is not installed."
    assert res["agent"] == "claude"


# --- the run ----------------------------------------------------------------

def test_success_spawns_the_agent_in_the_project_with_the_whole_prompt(world):
    code, res = run(world, [str(world["proj"]), str(world["spec"])])
    assert code == 0, res
    assert res["ok"] is True and res["agent"] == "claude" and res["exit_code"] == 0
    assert res["error"] == ""
    rec = recorded(world)
    assert os.path.samefile(rec["cwd"], world["proj"])
    argv = rec["argv"]
    assert argv[1:-1] == ["--allowedTools", "Read Glob Grep Bash(brd *)",
                          "--permission-mode", "dontAsk", "--no-session-persistence", "-p"]
    prompt = argv[-1]
    skill = open(os.path.join(ROOT, "core", "backend", "milestones", "setup-milestone.md"),
                 encoding="utf-8").read()
    assert prompt.startswith(skill)
    assert "## This run" in prompt
    assert "docs/spec.md" in prompt
    assert "brd tree" in prompt


def test_the_spec_path_in_the_prompt_is_relative_to_the_project(world):
    run(world, [str(world["proj"]), str(world["spec"])])
    prompt = recorded(world)["argv"][-1]
    assert str(world["proj"]) not in prompt.split("## This run")[1]


def test_a_relative_spec_path_works_too(world):
    code, res = run(world, [str(world["proj"]), "docs/spec.md"])
    assert code == 0 and res["ok"] is True
    assert "docs/spec.md" in recorded(world)["argv"][-1]


def test_a_spec_path_with_spaces_and_a_semicolon_is_passed_through_unchanged(world):
    weird = world["proj"] / "docs" / "a b; rm -rf $HOME.md"
    weird.write_text("# weird\n")
    code, res = run(world, [str(world["proj"]), str(weird)])
    assert code == 0 and res["ok"] is True
    prompt = recorded(world)["argv"][-1]
    assert "docs/a b; rm -rf $HOME.md" in prompt
    assert weird.exists()


def test_the_log_file_and_its_directory_are_private_and_hold_the_output(world):
    code, res = run(world, [str(world["proj"]), str(world["spec"])])
    assert code == 0
    log = res["log"]
    assert log.startswith(str(logdir(world)) + os.sep)
    assert log.endswith("-proj.log")
    assert stat.S_IMODE(os.stat(log).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(logdir(world)).st_mode) == 0o700
    assert "agent said hello" in open(log).read()


def test_the_log_lands_under_home_when_xdg_state_home_is_unset(world):
    e = env_for(world)
    del e["XDG_STATE_HOME"]
    p = subprocess.run([sys.executable, SCRIPT, str(world["proj"]), str(world["spec"])],
                       capture_output=True, text=True, env=e, timeout=60)
    res = json.loads(p.stdout.strip())
    assert p.returncode == 0
    assert res["log"].startswith(str(world["home"] / ".local" / "state"
                                     / "omarchy-project-manager" / "agent-logs") + os.sep)


def test_a_failing_agent_is_reported_with_its_status(world):
    code, res = run(world, [str(world["proj"]), str(world["spec"])], FAKE_AGENT_MODE="fail")
    assert code == 1
    assert res["ok"] is False and res["exit_code"] == 3
    assert res["error"] == "The agent exited with status 3."
    assert "agent failed" in open(res["log"]).read()


# --- cancel and timeout kill the whole process group ------------------------

def start_hanging(world, **extra):
    e = env_for(world, FAKE_AGENT_MODE="hang", **extra)
    p = subprocess.Popen([sys.executable, SCRIPT, str(world["proj"]), str(world["spec"])],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=e)
    pids_file = world["tmp"] / "pids.json"
    end = time.monotonic() + 30
    while time.monotonic() < end and not pids_file.exists():
        time.sleep(0.05)
    assert pids_file.exists(), "the fake agent never started"
    time.sleep(0.2)
    return p, json.loads(pids_file.read_text())


def test_sigterm_kills_the_agent_and_its_grandchild(world):
    proc, pids = start_hanging(world)
    assert alive(pids["agent"]) and alive(pids["child"])
    proc.send_signal(signal.SIGTERM)
    out, _ = proc.communicate(timeout=30)
    res = json.loads(out.strip().splitlines()[-1])
    assert proc.returncode == 1
    assert res["ok"] is False and res["error"] == "The run was cancelled."
    assert wait_gone(pids["agent"]), "the agent survived the cancel"
    assert wait_gone(pids["child"]), "the grandchild survived the cancel"


def test_sigint_kills_the_agent_and_its_grandchild(world):
    proc, pids = start_hanging(world)
    proc.send_signal(signal.SIGINT)
    out, _ = proc.communicate(timeout=30)
    res = json.loads(out.strip().splitlines()[-1])
    assert res["ok"] is False and res["error"] == "The run was cancelled."
    assert wait_gone(pids["agent"]) and wait_gone(pids["child"])


def test_the_timeout_kills_the_agent_and_its_grandchild(world):
    proc, pids = start_hanging(world, OPM_AGENT_TIMEOUT_SECONDS="1")
    out, _ = proc.communicate(timeout=60)
    res = json.loads(out.strip().splitlines()[-1])
    assert proc.returncode == 1
    assert res["ok"] is False
    assert res["error"] == "The agent ran out of time after 1s."
    assert wait_gone(pids["agent"]), "the agent survived the timeout"
    assert wait_gone(pids["child"]), "the grandchild survived the timeout"


def test_the_agent_runs_in_its_own_process_group(world):
    proc, pids = start_hanging(world)
    try:
        assert os.getpgid(pids["agent"]) != os.getpgid(proc.pid)
        assert os.getpgid(pids["agent"]) == os.getpgid(pids["child"])
    finally:
        proc.send_signal(signal.SIGTERM)
        proc.communicate(timeout=30)
        wait_gone(pids["agent"])
        wait_gone(pids["child"])


def test_a_bad_timeout_value_falls_back_to_the_default(world):
    code, res = run(world, [str(world["proj"]), str(world["spec"])],
                    OPM_AGENT_TIMEOUT_SECONDS="not-a-number")
    assert code == 0 and res["ok"] is True


# --- --describe -------------------------------------------------------------

def test_describe_a_supported_installed_agent(world):
    code, res = run(world, ["--describe"])
    assert code == 0
    assert res == {"agent": "claude", "supported": True, "restricted": True,
                   "note": res["note"], "installed": True}
    assert "brd" in res["note"]


def test_describe_an_unsupported_agent(world):
    code, res = run(world, ["--describe"], FAKE_DEFAULT_AGENT="openclaw")
    assert code == 0
    assert res == {"agent": "openclaw", "supported": False, "restricted": False,
                   "note": "", "installed": False}


def test_describe_with_no_default_agent(world):
    code, res = run(world, ["--describe"], FAKE_DEFAULT_AGENT="")
    assert code == 0
    assert res == {"agent": "", "supported": False, "restricted": False,
                   "note": "", "installed": False}


def test_describe_a_supported_agent_that_is_not_installed(world):
    os.remove(world["bin"] / "claude")
    code, res = run(world, ["--describe"])
    assert code == 0
    assert res["agent"] == "claude" and res["supported"] is True and res["installed"] is False


def test_describe_never_starts_an_agent(world):
    run(world, ["--describe"])
    assert not (world["tmp"] / "rec.json").exists()

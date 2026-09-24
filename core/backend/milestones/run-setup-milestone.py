#!/usr/bin/env python3
"""Build a milestone from a spec with the user's default coding agent, unattended.

    run-setup-milestone.py <project_root> <spec_path>
    run-setup-milestone.py --describe

Validates the project and the spec (the spec's real path must be inside the project's
real path, so a symlink cannot escape it), resolves the agent with
`omarchy-default-agent`, assembles the prompt (the setup-milestone prompt plus a
"## This run" section naming the spec relative to the project) and runs the agent
**in its own process group** with the project as the working directory and its output
appended to a private log file.

Everything is an argv array: the prompt is the last argument of the agent's command
and no shell is ever involved, so a spec's text cannot become a command.

Cancel (SIGTERM/SIGINT) and the wall-clock limit (`OPM_AGENT_TIMEOUT_SECONDS`, default
1800) kill the WHOLE process group (TERM, then KILL after 5 s), so no agent — nor
anything it started — is left running.

Prints exactly one JSON line: {"ok", "agent", "log", "exit_code", "error"}.
Exit 0 ok, 1 refused/failed/cancelled, 2 usage error. `--describe` prints
{"agent", "supported", "restricted", "note", "installed"} and exits 0.
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from common.json_line import emit  # noqa: E402
from common.safe_paths import inside  # noqa: E402
from milestones import agents  # noqa: E402

USAGE = "usage: run-setup-milestone.py <project_root> <spec_path>"
PROMPT_FILE = os.path.join(HERE, "setup-milestone.md")
DEFAULT_TIMEOUT = 1800.0
KILL_GRACE = 5.0


def fail(error, agent="", code=1):
    return emit({"ok": False, "agent": agent, "log": "", "exit_code": None,
                 "error": error}, code)


# --- agent resolution -------------------------------------------------------

def default_agent():
    """The name `omarchy-default-agent` prints, or "" when there is none."""
    exe = shutil.which("omarchy-default-agent")
    if exe is None:
        return ""
    try:
        proc = subprocess.run([exe], capture_output=True, text=True,
                              stdin=subprocess.DEVNULL, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip().splitlines()[0].strip() if proc.stdout.strip() else ""


def describe():
    name = default_agent()
    info = agents.describe(name)
    installed = bool(name) and info["supported"] and shutil.which(name) is not None
    return emit({"agent": name, "supported": info["supported"],
                 "restricted": info["restricted"], "note": info["note"],
                 "installed": installed})


# --- prompt -----------------------------------------------------------------

def build_prompt(skill_text, rel_spec):
    return (
        skill_text.rstrip("\n")
        + "\n\n## This run\n\n"
        + "The spec for this milestone is the file `" + rel_spec + "`, relative to the\n"
        + "current directory (the project root). Read it, apply the skill above, and\n"
        + "create the milestone, its stories and its subtasks with `brd` here — `brd`\n"
        + "resolves the project from the current directory, so do not change directory.\n"
        + "Nothing else in the project may be modified: only cards are created.\n"
        + "Finish by printing `brd tree <milestone id>` for the milestone you created.\n"
    )


# --- log --------------------------------------------------------------------

def log_path(root_real):
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state")
    directory = os.path.join(state, "omarchy-project-manager", "agent-logs")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    project = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(root_real)) or "project"
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    return os.path.join(directory, stamp + "-" + project + ".log")


# --- process group ----------------------------------------------------------

def kill_group(proc):
    """TERM the agent's whole process group, then KILL it, so nothing survives."""
    try:
        pgid = os.getpgid(proc.pid)
    except OSError:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except OSError:
            pass
        if sig is signal.SIGKILL:
            break
        try:
            proc.wait(timeout=KILL_GRACE)
        except subprocess.TimeoutExpired:
            pass
    try:
        proc.wait(timeout=KILL_GRACE)
    except subprocess.TimeoutExpired:
        pass


def timeout_seconds():
    raw = os.environ.get("OPM_AGENT_TIMEOUT_SECONDS", "")
    try:
        value = float(raw)
    except ValueError:
        return DEFAULT_TIMEOUT
    return value if value > 0 else DEFAULT_TIMEOUT


def run_agent(argv, root, log):
    """Run the agent to completion. Returns (exit_code, error)."""
    limit = timeout_seconds()
    cancelled = []

    def on_signal(_signum, _frame):
        cancelled.append(True)

    previous = {}
    for sig in (signal.SIGTERM, signal.SIGINT):
        previous[sig] = signal.signal(sig, on_signal)
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.fchmod(fd, 0o600)
        try:
            proc = subprocess.Popen(argv, cwd=root, stdin=subprocess.DEVNULL,
                                    stdout=fd, stderr=subprocess.STDOUT,
                                    start_new_session=True)
        except OSError as e:
            return None, "Could not start " + argv[0] + ": " + str(e)
    finally:
        os.close(fd)
    deadline = time.monotonic() + limit
    try:
        while True:
            try:
                code = proc.wait(timeout=0.2)
            except subprocess.TimeoutExpired:
                code = None
            if code is not None:
                if code == 0:
                    return 0, ""
                return code, "The agent exited with status " + str(code) + "."
            if cancelled:
                kill_group(proc)
                return proc.returncode, "The run was cancelled."
            if time.monotonic() >= deadline:
                kill_group(proc)
                return proc.returncode, ("The agent ran out of time after "
                                         + format_limit(limit) + "s.")
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def format_limit(limit):
    return str(int(limit)) if float(limit).is_integer() else str(limit)


# --- main -------------------------------------------------------------------

def main(argv):
    if argv[:1] == ["--describe"] and len(argv) == 1:
        return describe()
    if len(argv) != 2 or argv[0].startswith("--"):
        return emit({"ok": False, "agent": "", "log": "", "exit_code": None,
                     "error": USAGE}, 2)
    root, spec = argv
    if not os.path.isdir(root):
        return fail("Project folder not found.")
    root_real = os.path.realpath(root)
    spec_real = os.path.realpath(os.path.join(root, spec))
    if not inside(root_real, spec_real):
        return fail("The spec file is outside the project.")
    if not os.path.isfile(spec_real):
        return fail("Spec file not found.")
    if shutil.which("brd") is None:
        return fail("brd is not installed.")
    try:
        with open(PROMPT_FILE, encoding="utf-8") as f:
            skill_text = f.read()
    except OSError:
        return fail("The milestone prompt is missing.")

    name = default_agent()
    if not name:
        return fail("No default agent is set.")
    if not agents.supported(name):
        return fail(name + " has no supported unattended mode.", name)
    if shutil.which(name) is None:
        return fail(name + " is not installed.", name)

    rel_spec = os.path.relpath(spec_real, root_real)
    command = agents.ADAPTERS[name].build(build_prompt(skill_text, rel_spec))
    log = log_path(root_real)
    code, error = run_agent(command, root_real, log)
    ok = error == ""
    return emit({"ok": ok, "agent": name, "log": log, "exit_code": code,
                 "error": error}, 0 if ok else 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

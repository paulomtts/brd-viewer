#!/usr/bin/env python3
"""Build a milestone from a spec with the user's default coding agent, unattended.

    run-setup-milestone.py <project_root> <spec_path>
    run-setup-milestone.py --describe

Validates the project and the spec, resolves the agent with `omarchy-default-agent`,
assembles the prompt (the setup-milestone prompt plus a "## This run" section naming
the spec relative to the project) and runs the agent **in its own process group** with
the project as the working directory and its output appended to a private log file.

Containment: the spec's real path must be inside the project's real path, so a symlink
cannot escape the project. There is deliberately NO file-extension check — any regular
file inside the project may be handed to the agent as the spec.

Everything is an argv array: the prompt is the last argument of the agent's command
and no shell is ever involved, so a spec's text cannot become a command.

Cancel (SIGTERM/SIGINT) and the wall-clock limit (`OPM_AGENT_TIMEOUT_SECONDS`, default
1800) kill the WHOLE process group: SIGTERM, then SIGKILL after a grace period
(`OPM_AGENT_KILL_GRACE_SECONDS`, default 5). Two honest limits: an agent that
double-forks or calls `setsid()` leaves that process group and cannot be reached this
way, and if this runner is itself SIGKILLed it never gets to kill anything, so the
group keeps running.

Prints exactly one JSON line on stdout on EVERY path, including an unexpected failure:
{"ok", "agent", "log", "exit_code", "error"}. Exit 0 ok, 1 refused/failed/cancelled,
2 usage error. `--describe` prints {"agent", "supported", "restricted", "note",
"installed"} and exits 0; there `installed` means only "the binary is on PATH".
"""
import math
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
MAX_TIMEOUT = 24 * 3600.0
KILL_GRACE = 5.0
MAX_KILL_GRACE = 60.0

# What the run knows so far, so a failure can still name the agent and its log.
CONTEXT = {"agent": "", "log": ""}


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
    # `installed` means exactly "the binary is on PATH"; the UI decides what to say
    # from `installed` and `supported` together.
    installed = bool(name) and shutil.which(name) is not None
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

def state_home():
    """XDG_STATE_HOME, but only when it is absolute — the spec says a relative value
    must be ignored (otherwise the log tree would land under whatever the runner's
    working directory happens to be)."""
    state = os.environ.get("XDG_STATE_HOME") or ""
    if not os.path.isabs(state):
        return os.path.join(os.path.expanduser("~"), ".local", "state")
    return state


def log_path(root_real):
    directory = os.path.join(state_home(), "omarchy-project-manager", "agent-logs")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    project = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(root_real)) or "project"
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    return os.path.abspath(os.path.join(directory, stamp + "-" + project + ".log"))


# --- process group ----------------------------------------------------------

def kill_group(proc):
    """TERM the agent's whole process group, then KILL it after the grace period.

    The KILL always goes to the group, so an agent that ignores SIGTERM and anything
    it started die too (unless they left the group themselves; see the module docstring).
    """
    grace = kill_grace_seconds()
    try:
        pgid = os.getpgid(proc.pid)
    except OSError:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except Exception:  # noqa: BLE001 - a failed signal must not skip the next one
            pass
        try:
            proc.wait(timeout=grace)
        except Exception:  # noqa: BLE001 - nor may a failed wait
            pass


def env_seconds(name, default, cap):
    """A sane, positive, finite number of seconds from the environment, else the
    default. Junk, inf/nan and absurd values (over `cap`) all fall back, so a bad
    setting can never make the runner wait forever on a live agent."""
    try:
        value = float(os.environ.get(name, ""))
    except ValueError:
        return default
    if not math.isfinite(value) or value <= 0 or value > cap:
        return default
    return value


def timeout_seconds():
    return env_seconds("OPM_AGENT_TIMEOUT_SECONDS", DEFAULT_TIMEOUT, MAX_TIMEOUT)


def kill_grace_seconds():
    return env_seconds("OPM_AGENT_KILL_GRACE_SECONDS", KILL_GRACE, MAX_KILL_GRACE)


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
    except BaseException:  # noqa: BLE001 - nothing may outlive the agent
        # Anything unexpected in here (or a KeyboardInterrupt) would otherwise leave
        # the agent running while the caller is told the run failed.
        kill_group(proc)
        raise
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
    CONTEXT["agent"] = name

    rel_spec = os.path.relpath(spec_real, root_real)
    command = agents.ADAPTERS[name].build(build_prompt(skill_text, rel_spec))
    log = log_path(root_real)
    CONTEXT["log"] = log
    code, error = run_agent(command, root_real, log)
    ok = error == ""
    return emit({"ok": ok, "agent": name, "log": log, "exit_code": code,
                 "error": error}, 0 if ok else 1)


def guarded(argv):
    """The panel parses stdout for exactly one JSON line, so no path — not even an
    unexpected exception — may end without one. By the time it runs the agent's process
    group has already been killed (see `run_agent`)."""
    CONTEXT["agent"], CONTEXT["log"] = "", ""
    try:
        return main(argv)
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001 - deliberate catch-all
        reason = str(e) or e.__class__.__name__
        return emit({"ok": False, "agent": CONTEXT["agent"], "log": CONTEXT["log"],
                     "exit_code": None,
                     "error": "The milestone run failed: " + reason}, 1)


if __name__ == "__main__":
    sys.exit(guarded(sys.argv[1:]))

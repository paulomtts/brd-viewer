"""install.sh, exercised against fake omarchy/brd/uv binaries in a throwaway
HOME so nothing here can touch the real shell config or install anything."""
import os
import shutil
import stat
import subprocess

import pytest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INSTALL = os.path.join(REPO, "install.sh")
BASH = shutil.which("bash")
PLUGIN_ID = "paulomtts.brd-viewer"


def make_bin(bindir, name, body="exit 0"):
    path = bindir / name
    path.write_text('#!/bin/sh\necho "%s $*" >> "$CALLS"\n%s\n' % (name, body))
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


@pytest.fixture
def env(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    bindir = tmp_path / "bin"
    bindir.mkdir()
    calls = tmp_path / "calls.log"
    calls.write_text("")
    # Only the coreutils install.sh itself uses, so a real omarchy, brd, uv
    # or pipx on the machine running the tests can never be picked up.
    sysbin = tmp_path / "sysbin"
    sysbin.mkdir()
    for tool in ("cat", "dirname", "grep", "ln", "mkdir"):
        (sysbin / tool).symlink_to(shutil.which(tool))
    e = {
        "HOME": str(home),
        "PATH": "%s:%s" % (bindir, sysbin),
        "CALLS": str(calls),
    }
    return {"env": e, "bin": bindir, "home": home, "calls": calls}


def run(env, *args, stdin=subprocess.DEVNULL):
    proc = subprocess.run([BASH, INSTALL, *args], env=env["env"], stdin=stdin,
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def calls(env):
    return env["calls"].read_text().splitlines()


def dest(env):
    return env["home"] / ".config" / "omarchy" / "plugins" / PLUGIN_ID


def with_omarchy(env, enabled=False):
    listing = ("%s   enabled   third-party" % PLUGIN_ID) if enabled else ("%s   disabled   third-party" % PLUGIN_ID)
    make_bin(env["bin"], "omarchy", 'if [ "$1 $2" = "plugin list" ]; then echo "%s"; fi' % listing)
    make_bin(env["bin"], "omarchy-shell")


def test_links_checkout_rescans_and_enables(env):
    with_omarchy(env)
    make_bin(env["bin"], "brd")
    code, out = run(env)
    assert code == 0, out
    assert dest(env).is_symlink() and os.path.realpath(dest(env)) == os.path.realpath(REPO)
    log = calls(env)
    assert any(c.startswith("omarchy-shell shell rescanPlugins") for c in log)
    assert "omarchy plugin enable %s" % PLUGIN_ID in log


def test_does_not_re_enable_an_enabled_plugin(env):
    with_omarchy(env, enabled=True)
    make_bin(env["bin"], "brd")
    code, out = run(env)
    assert code == 0, out
    assert "omarchy plugin enable %s" % PLUGIN_ID not in calls(env)


def test_rerun_is_idempotent(env):
    with_omarchy(env)
    make_bin(env["bin"], "brd")
    assert run(env)[0] == 0
    code, out = run(env)
    assert code == 0, out
    assert os.path.realpath(dest(env)) == os.path.realpath(REPO)


def test_refuses_to_replace_a_different_existing_plugin(env):
    with_omarchy(env)
    make_bin(env["bin"], "brd")
    other = env["home"] / "elsewhere"
    other.mkdir()
    dest(env).parent.mkdir(parents=True)
    dest(env).symlink_to(other)
    code, out = run(env)
    assert code != 0
    assert os.path.realpath(dest(env)) == os.path.realpath(other)
    assert "omarchy plugin enable %s" % PLUGIN_ID not in calls(env)


def test_fails_without_the_omarchy_cli(env):
    # No fake omarchy was installed for this case.
    code, out = run(env)
    assert code != 0
    assert "omarchy" in out.lower()
    assert not dest(env).exists()


def test_with_brd_installs_it_via_uv_when_missing(env):
    with_omarchy(env)
    make_bin(env["bin"], "uv")
    code, out = run(env, "--with-brd")
    assert code == 0, out
    assert any(c.startswith("uv tool install ") and "paulomtts/brd" in c for c in calls(env))


def test_no_brd_skips_install_and_warns(env):
    with_omarchy(env)
    make_bin(env["bin"], "uv")
    code, out = run(env, "--no-brd")
    assert code == 0, out
    assert not any(c.startswith("uv ") for c in calls(env))
    assert "brd" in out and "not installed" in out.lower()


def test_non_interactive_default_does_not_install_brd(env):
    with_omarchy(env)
    make_bin(env["bin"], "uv")
    code, out = run(env)
    assert code == 0, out
    assert not any(c.startswith("uv ") for c in calls(env))


def test_failed_brd_install_still_installs_the_plugin(env):
    # e.g. the brd repo is private and the user has no access.
    with_omarchy(env)
    make_bin(env["bin"], "uv", "exit 1")
    code, out = run(env, "--with-brd")
    assert code == 0, out
    assert dest(env).is_symlink()
    assert "omarchy plugin enable %s" % PLUGIN_ID in calls(env)


def test_with_brd_but_no_installer_tool_warns_and_continues(env):
    with_omarchy(env)
    code, out = run(env, "--with-brd")
    assert code == 0, out
    assert "uv" in out and "pipx" in out
    assert dest(env).is_symlink()


def test_dry_run_changes_nothing(env):
    with_omarchy(env)
    make_bin(env["bin"], "uv")
    code, out = run(env, "--with-brd", "--dry-run")
    assert code == 0, out
    assert not dest(env).exists() and not dest(env).is_symlink()
    log = calls(env)
    assert not any(c.startswith("uv ") for c in log)
    assert "omarchy plugin enable %s" % PLUGIN_ID not in log
    assert "dry-run" in out.lower()


def test_unknown_flag_is_rejected(env):
    with_omarchy(env)
    code, out = run(env, "--bogus")
    assert code != 0
    assert "usage" in out.lower()

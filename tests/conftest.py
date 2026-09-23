import os
import subprocess
import sys

PLUGIN_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PLUGIN_DIR)

import pytest


@pytest.fixture
def run_resolve():
    """Invoke resolve-db-path.py the way Panel.qml does, with a fully
    controlled environment (default: no inherited XDG_DATA_HOME/HOME, so
    tests never depend on the machine they run on)."""
    def run(args, env=None, cwd=None):
        full_env = {}
        if env:
            full_env.update(env)
        proc = subprocess.run(
            [sys.executable, os.path.join(PLUGIN_DIR, "resolve-db-path.py"), *args],
            capture_output=True, text=True, env=full_env, cwd=cwd,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr
    return run

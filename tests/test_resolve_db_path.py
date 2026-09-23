import hashlib
from pathlib import Path


def expected_digest(root_path, cwd=None):
    # Mirrors brd's own paths.project_db_path(): sha256 of the resolved
    # absolute path, independently re-derived here (not imported from brd)
    # so this test still catches a divergence if either side changes.
    resolved = Path(root_path)
    if cwd is not None:
        resolved = Path(cwd) / root_path
    return hashlib.sha256(str(resolved.resolve()).encode()).hexdigest()


def test_uses_xdg_data_home_when_set(run_resolve, tmp_path):
    xdg = tmp_path / "xdg"
    code, out, err = run_resolve(["/home/user/myproject"], env={"XDG_DATA_HOME": str(xdg)})
    assert code == 0
    expected = xdg / "brd" / "projects" / f"{expected_digest('/home/user/myproject')}.db"
    assert out == str(expected)


def test_falls_back_to_home_local_share_when_no_xdg(run_resolve, tmp_path):
    home = tmp_path / "home"
    code, out, err = run_resolve(["/home/user/myproject"], env={"HOME": str(home)})
    assert code == 0
    expected = home / ".local" / "share" / "brd" / "projects" / f"{expected_digest('/home/user/myproject')}.db"
    assert out == str(expected)


def test_relative_and_absolute_paths_that_resolve_the_same_produce_the_same_digest(run_resolve, tmp_path):
    home = tmp_path / "home"
    project = tmp_path / "code" / "myproject"
    project.mkdir(parents=True)

    code_abs, out_abs, _ = run_resolve([str(project)], env={"HOME": str(home)})
    code_rel, out_rel, _ = run_resolve(["myproject"], env={"HOME": str(home)}, cwd=str(tmp_path / "code"))

    assert code_abs == 0 and code_rel == 0
    assert out_abs == out_rel


def test_missing_argv_exits_nonzero_and_prints_nothing(run_resolve, tmp_path):
    code, out, err = run_resolve([], env={"HOME": str(tmp_path)})
    assert code != 0
    assert out == ""


def test_empty_argv_exits_nonzero_and_prints_nothing(run_resolve, tmp_path):
    code, out, err = run_resolve([""], env={"HOME": str(tmp_path)})
    assert code != 0
    assert out == ""


def test_missing_home_and_xdg_exits_nonzero_and_prints_nothing(run_resolve):
    code, out, err = run_resolve(["/home/user/myproject"], env={})
    assert code != 0
    assert out == ""

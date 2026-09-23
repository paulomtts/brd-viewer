# Sidebar, Project Dropdown and Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the brd-viewer panel a left sidebar (project dropdown, Board / Documents navigation, Delete project button), remember the last project across restarts, and add a read-only Markdown Documents section.

**Architecture:** `Panel.qml` keeps all state and the Board/card/delete flows. Two new QML files with explicit properties and signals hold the new UI (`Sidebar.qml`, `DocumentsView.qml`). Anything QML cannot do (write the state file, list Markdown files) is a small Python helper printing one JSON line (`viewer-state.py`, `list-docs.py`). Pure decisions live in `logic.js`. A committed stub harness (`tests/panel/`) compiles the real QML against stubbed Omarchy shell types so `Panel.qml` behaviour is tested before it is changed.

**Tech Stack:** QML (Quickshell), JavaScript (`logic.js`, `.pragma library`), Python 3 + pytest, Bash, Qt's `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-09-23-sidebar-and-documents-design.md`

## Global Constraints

- Card data is never written. The only write the plugin performs is removing a project via the existing `snapshot-and-forget.py` (mandatory snapshot, type-`delete` confirmation). No task may add another `brd` write command.
- QML never writes files; persistence goes through `viewer-state.py`.
- No task runs `brd forget`, `snapshot-and-forget.py`, or `omarchy plugin enable` against the real system. Tests use throwaway temp dirs and fake binaries only.
- Layout: sidebar 200 logical px (`Style.space(200)`), panel width `Style.space(840)`, height cap `Style.space(620)`, still capped to the screen by `fittedContentWidth`.
- State file: `${XDG_STATE_HOME:-~/.local/state}/brd-viewer/state.json`, atomic write (temp file + rename), other keys preserved.
- Documents = root `README.md` plus every `*.md` (case-insensitive) under `docs/`; at most 500 entries (`truncated` flag); documents larger than 1 MB (1048576 bytes) are not displayed; only regular files whose resolved path is inside the resolved project root are listed.
- New QML files may not reference `Panel.qml` ids; they communicate through properties and signals.
- Git identity: every commit uses `git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit ...` and ends with the two trailer lines `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa`. Before finishing a task run `git log -1 --format='%ae|%ce'` and confirm both are `93949169+paulomtts@users.noreply.github.com`. Never push; the controller pushes.
- Work happens on the branch `feature/sidebar` (already created and checked out; the spec is its first commit).

## Review Focus

- The state file is missing, empty, corrupt, or in an unwritable directory: `get` must yield `null`, `set-project` must fail cleanly, and the panel must still open on the first project. (Task 2, Task 3, Task 6)
- The stored project is no longer registered, or the project being viewed is removed (deleted elsewhere or via the sidebar): fall back to the first remaining project, and to an empty state when none remain, never a stale board. (Task 3, Task 5, Task 7)
- Zero projects registered: no crash, sidebar controls disabled, "No projects registered with brd." shown, Delete disabled. (Task 4, Task 5)
- A docs directory containing a symlink that escapes the project, a huge tree, non-UTF-8 or empty files, and paths with spaces. (Task 8, Task 11)
- Keyboard: Escape with the dropdown open closes only the dropdown, not the panel; Ctrl+P / Ctrl+1 / Ctrl+2 do nothing while the delete confirmation is open. (Task 5, Task 7)

---

## File Structure

- `tests/panel/stubs/**`, `tests/panel/run.sh`, `tests/panel/tst_*.qml` — stub harness and Panel-level tests (Tasks 1, 5–7, 11).
- `viewer-state.py`, `tests/test_viewer_state.py` — persistence helper (Task 2).
- `logic.js`, `tests/qml/tst_logic.qml` — pure helpers (Tasks 3, 9).
- `Sidebar.qml`, `tests/panel/tst_sidebar.qml` — sidebar component (Task 4).
- `Panel.qml` — state, wiring, layout (Tasks 5–7, 11).
- `list-docs.py`, `tests/test_list_docs.py` — Documents listing helper (Task 8).
- `DocumentsView.qml`, `tests/panel/tst_documents_view.qml` — Documents list component (Task 10).
- `README.md`, `manifest.json`, spec — documentation (Task 12).

---

### Task 1: Commit the Panel test harness

**Files:**
- Create: `tests/panel/stubs/qs/Commons/qmldir`, `.../Color.qml`, `.../Style.qml`
- Create: `tests/panel/stubs/qs/Ui/qmldir` and one file per stub type (below)
- Create: `tests/panel/stubs/Quickshell/qmldir`, `IpcHandler.qml`, `Io/qmldir`, `Io/FileView.qml`, `Io/Process.qml`, `Io/StdioCollector.qml`
- Create: `tests/panel/run.sh`, `tests/panel/tst_board_flow.qml`, `tests/panel/tst_delete_flow.qml`
- Modify: `run-tests.sh`, `.gitignore`

**Interfaces:**
- Consumes: the current `Panel.qml` and `logic.js` (repo root).
- Produces: `bash tests/panel/run.sh` — copies every `*.qml` and `logic.js` from the repo root plus the stubs into a temp dir, runs each `tests/panel/tst_*.qml` with `qmltestrunner`, exits non-zero on any failing test or on QML warnings matching `TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function` (the known harmless `width' of null` warning is ignored). Later tasks add `tst_*.qml` files and stub properties.

- [ ] **Step 1: Write the stub files**

`tests/panel/stubs/qs/Commons/qmldir`:
```
module qs.Commons
singleton Style 1.0 Style.qml
singleton Color 1.0 Color.qml
```
`tests/panel/stubs/qs/Commons/Color.qml`:
```qml
pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#ddd"
  property color urgent: "#f55"
  property QtObject popups: QtObject { property color background: "#101315"; property color border: "#555" }
}
```
`tests/panel/stubs/qs/Commons/Style.qml`:
```qml
pragma Singleton
import QtQuick
QtObject {
  function space(n) { return n }
  property QtObject font: QtObject { property string family: "sans"; property int body: 14; property int bodySmall: 12; property int caption: 10; property int heading: 18 }
  property QtObject spacing: QtObject { property int md: 8; property int rowPaddingX: 8; property int controlPaddingY: 4 }
}
```
`tests/panel/stubs/qs/Ui/qmldir`:
```
module qs.Ui
Panel 1.0 Panel.qml
BarIconButton 1.0 BarIconButton.qml
KeyboardPanel 1.0 KeyboardPanel.qml
PanelKeyCatcher 1.0 PanelKeyCatcher.qml
CursorSurface 1.0 CursorSurface.qml
Button 1.0 Button.qml
TextField 1.0 TextField.qml
PanelSeparator 1.0 PanelSeparator.qml
PanelSectionHeader 1.0 PanelSectionHeader.qml
```
`Ui/Panel.qml`:
```qml
import QtQuick
Item {
  property string moduleName; property string ipcTarget; property bool manageIpc; property var bar: null
  property bool opened: false
  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
  function switchPanel(d) {}
}
```
`Ui/BarIconButton.qml`:
```qml
import QtQuick
Item { property var bar; property string text; signal pressed(int buttonCode) }
```
`Ui/Button.qml`:
```qml
import QtQuick
Item { property string text; property bool bordered; property color foreground; property string fontFamily; property real fontSize; property real verticalPadding; signal clicked() }
```
`Ui/CursorSurface.qml`:
```qml
import QtQuick
Rectangle { property bool hasCursor; property bool current; property bool bordered; property color foreground; color: "transparent" }
```
`Ui/KeyboardPanel.qml`:
```qml
import QtQuick
Item {
  property Item anchorItem; property var owner; property var bar; property bool open; property bool centerOnBar; property Item focusTarget
  property real contentWidth; property real contentHeight
  function fittedContentWidth(w) { return w }
  function fittedContentHeight(a, b) { return Math.min(a, b) }
  width: 380; height: 560
}
```
`Ui/PanelKeyCatcher.qml`:
```qml
import QtQuick
FocusScope {
  signal activateRequested()
  signal closeRequested()
  signal moveRequested(int dx, int dy)
  signal tabRequested(int direction)
}
```
`Ui/PanelSectionHeader.qml`:
```qml
import QtQuick
Text { property color foreground; property string fontFamily }
```
`Ui/PanelSeparator.qml`:
```qml
import QtQuick
Item { property color foreground }
```
`Ui/TextField.qml`:
```qml
import QtQuick
TextInput { property color foreground; property string placeholderText; width: 100 }
```
`Quickshell/qmldir`:
```
module Quickshell
IpcHandler 1.0 IpcHandler.qml
```
`Quickshell/IpcHandler.qml`:
```qml
import QtQuick
QtObject { property string target }
```
`Quickshell/Io/qmldir`:
```
module Quickshell.Io
Process 1.0 Process.qml
StdioCollector 1.0 StdioCollector.qml
FileView 1.0 FileView.qml
```
`Quickshell/Io/Process.qml`:
```qml
import QtQuick
QtObject { property var command; property bool running; property string workingDirectory; property QtObject stdout; property QtObject stderr; signal exited(int exitCode) }
```
`Quickshell/Io/StdioCollector.qml`:
```qml
import QtQuick
QtObject { property bool waitForEnd; property string text; signal streamFinished() }
```
`Quickshell/Io/FileView.qml`:
```qml
import QtQuick
QtObject {
  property string path; property bool watchChanges; property bool printErrors
  property string stubText: ""
  signal fileChanged()
  signal loaded()
  signal loadFailed(int error)
  function text() { return stubText }
}
```

- [ ] **Step 2: Write `tests/panel/run.sh`**

```bash
#!/usr/bin/env bash
# Compiles the real plugin QML against stubbed Omarchy shell types and runs
# every tests/panel/tst_*.qml with Qt's test runner. Panel.qml cannot run
# headless in the real shell, so this is how its behaviour is tested.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

runner=$(command -v /usr/lib/qt6/bin/qmltestrunner || command -v qmltestrunner)
cp -r "$here/stubs/." "$work/"
mkdir "$work/t"
cp "$repo"/*.qml "$repo/logic.js" "$work/t/"
cp "$here"/tst_*.qml "$work/t/"

status=0
for test in "$work"/t/tst_*.qml; do
  echo "== $(basename "$test")"
  out=$(QT_QPA_PLATFORM=offscreen "$runner" -import "$work" -input "$test" 2>&1) || status=1
  echo "$out" | grep -E "^(FAIL|Totals)|^   Loc" || true
  bad=$(echo "$out" | grep -E "TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function" | grep -v "width' of null" || true)
  if [ -n "$bad" ]; then echo "$bad"; status=1; fi
done
exit $status
```
Run `chmod +x tests/panel/run.sh`.

- [ ] **Step 3: Write the two baseline Panel tests**

`tests/panel/tst_board_flow.qml` (current behaviour: Board, card detail, back restores the cursor; the panel starts on the project list at this point so it selects a project explicitly):
```qml
import QtQuick
import QtTest
TestCase {
  id: testCase
  name: "BoardFlow"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  function card(id, title, status, children, blockedBy) {
    return { id: id, title: title, status: status, description: "d", blocked_by: blockedBy || [], children: children || [] }
  }
  function ids(list) { return list.map(function(x) { return x.id }).join(",") }

  function test_board_and_detail_flow() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.projects = [{ root_path: "/x", name: "proj" }]
    p.selectProject(p.projects[0])
    var t1 = card("t1", "Task1", "blocked", [], ["x1"])
    var t2 = card("t2", "Task2", "done")
    var s1 = card("s1", "Story", "in_progress", [t1, t2])
    var m1 = card("m1", "Milestone", "todo", [s1])
    var x1 = card("x1", "Ex", "done")
    var b1 = card("b1", "Blk", "blocked")
    p.applyTreeData([m1, x1, b1])
    wait(50)
    compare(ids(p.boardCards), "m1,b1,x1")
    p.moveCursor(1); compare(p.cursorIndex, 1)
    p.moveCursor(5); compare(p.cursorIndex, 2)
    p.moveCursor(-1)
    p.activateCursor()
    compare(p.viewMode, "entry"); compare(p.selectedCardId, "b1")
    p.goBack()
    compare(p.viewMode, "board"); compare(p.cursorIndex, 1)
    p.cursorIndex = 0
    p.activateCursor(); compare(p.selectedCardId, "m1")
    p.activateCursor(); compare(p.selectedCardId, "s1")
    compare(p.detailLinkList.map(function(l) { return l.section }).join(","), "parent,child,child")
    p.moveCursor(1); p.activateCursor(); compare(p.selectedCardId, "t1")
    compare(p.detailLinkList.map(function(l) { return l.section + ":" + l.id }).join(","), "parent:s1,blocker:x1")
    p.applyTreeData([x1])
    compare(p.viewMode, "board")
  }
}
```
`tests/panel/tst_delete_flow.qml`:
```qml
import QtQuick
import QtTest
TestCase {
  id: testCase
  name: "DeleteFlow"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  function procByName(p, name) {
    for (var i = 0; i < p.data.length; i++)
      if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }

  function test_delete_flow() {
    var host = createTemporaryObject(hostC, testCase)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    p.opened = true
    p.projects = [{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }]
    wait(50)
    var proc = procByName(p, "deleteProc")
    verify(proc, "deleteProc found (Task 1 gives it objectName deleteProc)")

    p.openDelete(p.projects[1])
    compare(p.deleteTarget.name, "beta")
    compare(p.displayPath("/home/u/b"), "~/b")
    p.confirmText = "delet"; p.performDelete(); compare(p.deleting, false)
    p.cancelDelete(); compare(p.deleteTarget, null)

    p.openDelete(p.projects[0])
    p.confirmText = " Delete "
    p.performDelete()
    compare(p.deleting, true)
    var cmd = proc.command
    compare(cmd[0], "python3")
    verify(String(cmd[1]).endsWith("snapshot-and-forget.py"))
    compare(cmd[2], "/home/u/a"); compare(cmd[3], "alpha")

    p.performDelete(); p.cancelDelete()
    compare(p.deleting, true)

    proc.outText = '{"ok": false, "error": "could not snapshot the project, so it was not removed"}'
    proc.exited(1)
    compare(p.deleting, false)
    verify(p.deleteTarget !== null)
    compare(p.deleteError, "could not snapshot the project, so it was not removed")

    p.confirmText = "delete"; p.performDelete()
    proc.outText = '{"ok": true, "snapshot": "/home/u/Snapshots/brd-viewer/alpha-1"}'
    proc.exited(0)
    compare(p.deleting, false); compare(p.deleteTarget, null)
    compare(p.lastSnapshot, "/home/u/Snapshots/brd-viewer/alpha-1")
  }
}
```

- [ ] **Step 4: Give the existing Processes `objectName`s in `Panel.qml`**

The tests locate Process objects by `objectName`. Add one line to each existing `Process` in `Panel.qml`: `listProc` gets `objectName: "listProc"`, `resolveDbPathProc` gets `objectName: "resolveDbPathProc"`, `treeProc` gets `objectName: "treeProc"`, `deleteProc` gets `objectName: "deleteProc"`, directly after each `id:` line.

- [ ] **Step 5: Run the harness and the whole suite, then hook it into `run-tests.sh`**

Run: `bash tests/panel/run.sh`
Expected: `Totals: 3 passed, 0 failed` for both files, exit 0.

Append to `run-tests.sh` (before the final `qmltestrunner` lines is fine, after them is fine): `bash tests/panel/run.sh`. Append `.superpowers/` and `.claude/` to `.gitignore`.

Run: `./run-tests.sh`
Expected: pytest passes, `logic.js` qmltestrunner passes (36 tests), both harness files pass.

- [ ] **Step 6: Commit**

```bash
git add tests/panel run-tests.sh .gitignore Panel.qml
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add a stub harness for testing Panel.qml and baseline Panel flow tests" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 2: `viewer-state.py`

**Files:**
- Create: `viewer-state.py`
- Create: `tests/test_viewer_state.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `python3 viewer-state.py get` → prints `{"last_project": "<path>"|null}`, exit 0, never raises; `python3 viewer-state.py set-project <root_path>` → prints `{"ok": true}` exit 0, or `{"ok": false, "error": "..."}` exit 1; unknown command or missing/empty path → JSON error, exit 2.

- [ ] **Step 1: Write the failing tests**

```python
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
    return Path(env["XDG_STATE_HOME"]) / "brd-viewer" / "state.json"


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
    assert (Path(env["HOME"]) / ".local" / "state" / "brd-viewer" / "state.json").is_file()


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
```

- [ ] **Step 2: Run to confirm failure**

Run: `python3 -m pytest tests/test_viewer_state.py -q`
Expected: FAIL (script does not exist).

- [ ] **Step 3: Write `viewer-state.py`**

```python
#!/usr/bin/env python3
"""Remembers which brd project the panel was last showing.

    viewer-state.py get
    viewer-state.py set-project <root_path>

State lives in ${XDG_STATE_HOME:-~/.local/state}/brd-viewer/state.json. QML
cannot write files, hence this helper. Prints one JSON line. `get` never fails
(a missing or corrupt file just means no stored project); `set-project` writes
atomically and keeps any other keys already in the file.
"""
import json
import os
import sys
import tempfile


def state_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "brd-viewer", "state.json")


def load():
    try:
        with open(state_path(), "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def emit(payload, code):
    print(json.dumps(payload))
    return code


def cmd_get():
    last = load().get("last_project")
    return emit({"last_project": last if isinstance(last, str) and last else None}, 0)


def cmd_set_project(root_path):
    data = load()
    data["last_project"] = root_path
    path = state_path()
    directory = os.path.dirname(path)
    tmp = None
    try:
        os.makedirs(directory, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".state-", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, path)
    except OSError as e:
        if tmp and os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass
        return emit({"ok": False, "error": str(e)}, 1)
    return emit({"ok": True}, 0)


def main(argv):
    if argv[:1] == ["get"] and len(argv) == 1:
        return cmd_get()
    if argv[:1] == ["set-project"] and len(argv) == 2 and argv[1]:
        return cmd_set_project(argv[1])
    return emit({"ok": False, "error": "usage: viewer-state.py get | set-project <root_path>"}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```
`chmod +x viewer-state.py`.

- [ ] **Step 4: Run to confirm pass**

Run: `python3 -m pytest tests/test_viewer_state.py -q`
Expected: all pass (the unwritable test is skipped when run as root).

- [ ] **Step 5: Commit**

```bash
git add viewer-state.py tests/test_viewer_state.py
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add viewer-state.py to remember the last viewed project" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 3: `logic.js` helpers for project selection

**Files:**
- Modify: `logic.js`, `tests/qml/tst_logic.qml`

**Interfaces:**
- Consumes: `Logic.matchesQuery(text, query)` (exists).
- Produces (all in `logic.js`):
  - `Logic.filterProjects(projects, query)` → array of the projects whose `name` matches `query` (empty query returns all; `projects` may be undefined → `[]`).
  - `Logic.chooseProject(projects, currentPath, storedPath)` → the project object to show, or `null`: the one whose `root_path === currentPath` if registered, else the one matching `storedPath`, else `projects[0]`, else `null`. `currentPath`/`storedPath` may be `""`, `null` or `undefined`.
  - `Logic.parseStateResult(stdout, exitCode)` → the stored `root_path` string, or `null` (non-zero exit, empty/garbled output, missing or non-string `last_project`, empty string). Reads the last non-empty stdout line.

- [ ] **Step 1: Write the failing tests** (append inside the `TestCase` in `tests/qml/tst_logic.qml`, before its closing brace)

```qml
  // ---- project selection ------------------------------------------------

  property var pa: ({ root_path: "/a", name: "alpha" })
  property var pb: ({ root_path: "/b", name: "beta" })
  property var pc: ({ root_path: "/c", name: "gamma" })

  function test_filter_projects() {
    var list = [pa, pb, pc]
    compare(Logic.filterProjects(list, "").length, 3)
    compare(Logic.filterProjects(list, "  ").length, 3)
    compare(Logic.filterProjects(list, "AL").map(function(p) { return p.name }).join(","), "alpha")
    compare(Logic.filterProjects(list, "a").length, 3)
    compare(Logic.filterProjects(list, "zzz").length, 0)
    compare(Logic.filterProjects(undefined, "a").length, 0)
  }

  function test_choose_project_data() {
    return [
      { tag: "current wins", current: "/b", stored: "/c", expect: "/b" },
      { tag: "stored when no current", current: "", stored: "/c", expect: "/c" },
      { tag: "stale current falls to stored", current: "/gone", stored: "/c", expect: "/c" },
      { tag: "stale both fall to first", current: "/gone", stored: "/also-gone", expect: "/a" },
      { tag: "nothing given falls to first", current: undefined, stored: null, expect: "/a" }
    ]
  }

  function test_choose_project(data) {
    var chosen = Logic.chooseProject([pa, pb, pc], data.current, data.stored)
    compare(chosen ? chosen.root_path : null, data.expect)
  }

  function test_choose_project_with_no_projects_is_null() {
    compare(Logic.chooseProject([], "/a", "/a"), null)
    compare(Logic.chooseProject(undefined, "/a", "/a"), null)
  }

  function test_parse_state_result_data() {
    return [
      { tag: "path", out: '{"last_project": "/home/u/p"}\\n', code: 0, expect: "/home/u/p" },
      { tag: "last line wins", out: 'noise\\n{"last_project": "/x"}', code: 0, expect: "/x" },
      { tag: "null", out: '{"last_project": null}', code: 0, expect: null },
      { tag: "empty string", out: '{"last_project": ""}', code: 0, expect: null },
      { tag: "wrong type", out: '{"last_project": 5}', code: 0, expect: null },
      { tag: "nonzero exit", out: '{"last_project": "/x"}', code: 1, expect: null },
      { tag: "garbled", out: "not json", code: 0, expect: null },
      { tag: "empty", out: "", code: 0, expect: null },
      { tag: "undefined", out: undefined, code: 0, expect: null }
    ]
  }

  function test_parse_state_result(data) {
    compare(Logic.parseStateResult(data.out, data.code), data.expect)
  }
```

- [ ] **Step 2: Run to confirm failure**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml`
Expected: FAIL, `Property 'filterProjects' ... is not a function` (and the two others).

- [ ] **Step 3: Implement** (append to `logic.js`)

```js

function filterProjects(projects, query) {
  return (projects || []).filter(function(p) { return matchesQuery(p.name, query) })
}

// Which project the panel should show: the one already on screen if it is
// still registered, else the one remembered from last time, else the first.
function chooseProject(projects, currentPath, storedPath) {
  var list = projects || []
  if (list.length === 0) return null
  function byPath(path) {
    if (!path) return null
    for (var i = 0; i < list.length; i++) if (list[i].root_path === path) return list[i]
    return null
  }
  return byPath(currentPath) || byPath(storedPath) || list[0]
}

// viewer-state.py get: its last stdout line is {"last_project": path|null}.
function parseStateResult(stdout, exitCode) {
  if (exitCode !== 0) return null
  var lines = String(stdout || "").split("\n").filter(function(l) { return l.trim() !== "" })
  if (lines.length === 0) return null
  try {
    var last = JSON.parse(lines[lines.length - 1]).last_project
    return typeof last === "string" && last !== "" ? last : null
  } catch (e) {
    return null
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml`
Expected: all pass (the previous 36 plus the new ones).

- [ ] **Step 5: Commit**

```bash
git add logic.js tests/qml/tst_logic.qml
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add project selection helpers to logic.js" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 4: `Sidebar.qml`

**Files:**
- Create: `Sidebar.qml`, `tests/panel/tst_sidebar.qml`

**Interfaces:**
- Consumes: shell types `CursorSurface`, `Button`, `TextField` (`qs.Ui`), `Color`, `Style` (`qs.Commons`).
- Produces — `Sidebar` (an `Item`; the parent sets its width/height):
  - Properties: `projects` (array, already filtered by the parent), `selectedProject`, `section` (`"board"|"documents"`), `dropdownOpen`, `dropdownQuery`, `dropdownCursor` (int), `canDelete`, `documentsEnabled` (bool, default `true`), `foreground`, `dim`, `urgent`, `fontFamily`; read-only `hasProject`, `filterItem` (the dropdown's filter field, for the parent's focus logic); `implicitHeight` = `Style.space(300)`.
  - Signals: `dropdownToggled()`, `projectChosen(var project)`, `queryEdited(string text)`, `sectionChosen(string section)`, `deleteRequested()`, `cursorHovered(int index)`, `dropdownMove(int delta)`, `dropdownAccept()`, `dropdownCancel()`, `filterKey(var event)` (any key the filter field does not consume, so the parent can handle global shortcuts).
  - Function: `focusFilter()`.
  - `objectName`s for tests: `projectButton`, `navBoard`, `navDocuments`, `deleteButton`, `filterField`, `dropdown`, and rows `projectRow0`, `projectRow1`, ….
  - Nav rows and the Delete button are disabled (dimmed, no click) when there is no `selectedProject`; Documents additionally when `documentsEnabled` is false; Delete additionally when `canDelete` is false.

- [ ] **Step 1: Write the failing test** `tests/panel/tst_sidebar.qml`

```qml
import QtQuick
import QtTest
TestCase {
  id: tc
  name: "Sidebar"
  when: windowShown
  width: 300; height: 500

  Component { id: sbC; Sidebar { width: 200; height: 460 } }
  SignalSpy { id: toggled; signalName: "dropdownToggled" }
  SignalSpy { id: chosen; signalName: "projectChosen" }
  SignalSpy { id: sectionSpy; signalName: "sectionChosen" }
  SignalSpy { id: deleteSpy; signalName: "deleteRequested" }
  SignalSpy { id: querySpy; signalName: "queryEdited" }
  SignalSpy { id: hoverSpy; signalName: "cursorHovered" }
  SignalSpy { id: moveSpy; signalName: "dropdownMove" }
  SignalSpy { id: acceptSpy; signalName: "dropdownAccept" }
  SignalSpy { id: cancelSpy; signalName: "dropdownCancel" }
  SignalSpy { id: keySpy; signalName: "filterKey" }

  property var projects: [{ root_path: "/a", name: "alpha" }, { root_path: "/b", name: "beta" }, { root_path: "/c", name: "gamma" }]

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var r = find(item.children[i], name)
      if (r) return r
    }
    return null
  }
  function click(item) { mouseClick(item, item.width / 2, item.height / 2) }

  function make() {
    var sb = createTemporaryObject(sbC, tc)
    sb.projects = projects
    sb.selectedProject = projects[0]
    sb.canDelete = true
    var spies = [toggled, chosen, sectionSpy, deleteSpy, querySpy, hoverSpy, moveSpy, acceptSpy, cancelSpy, keySpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = sb; spies[i].clear() }
    wait(20)
    return sb
  }

  function test_button_shows_project_and_toggles() {
    var sb = make()
    var btn = find(sb, "projectButton")
    verify(btn, "projectButton")
    click(btn)
    compare(toggled.count, 1)
    sb.selectedProject = null
    compare(sb.hasProject, false)
  }

  function test_dropdown_lists_projects_and_chooses() {
    var sb = make()
    sb.dropdownOpen = true
    wait(20)
    compare(find(sb, "dropdown").visible, true)
    verify(find(sb, "projectRow2"), "three rows")
    verify(!find(sb, "projectRow3"), "no fourth row")
    click(find(sb, "projectRow1"))
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0].root_path, "/b")
  }

  function test_dropdown_is_hidden_when_closed() {
    var sb = make()
    compare(find(sb, "dropdown").visible, false)
  }

  function test_dropdown_shows_an_empty_message() {
    var sb = make()
    sb.projects = []
    sb.dropdownOpen = true
    wait(20)
    verify(!find(sb, "projectRow0"))
  }

  function test_filter_field_emits_query_and_keys() {
    var sb = make()
    sb.dropdownOpen = true
    var f = find(sb, "filterField")
    verify(f)
    f.text = "be"
    compare(querySpy.count, 1)
    compare(querySpy.signalArguments[0][0], "be")
  }

  function test_navigation_rows_emit_sections_and_respect_enabled() {
    var sb = make()
    click(find(sb, "navDocuments"))
    compare(sectionSpy.count, 1)
    compare(sectionSpy.signalArguments[0][0], "documents")
    click(find(sb, "navBoard"))
    compare(sectionSpy.signalArguments[1][0], "board")
    sb.documentsEnabled = false
    click(find(sb, "navDocuments"))
    compare(sectionSpy.count, 2)
    sb.documentsEnabled = true
    sb.selectedProject = null
    click(find(sb, "navBoard"))
    click(find(sb, "navDocuments"))
    compare(sectionSpy.count, 2)
  }

  function test_delete_button_follows_canDelete() {
    var sb = make()
    var b = find(sb, "deleteButton")
    verify(b)
    compare(b.enabled, true)
    b.clicked()
    compare(deleteSpy.count, 1)
    sb.canDelete = false
    compare(b.enabled, false)
    sb.canDelete = true
    sb.selectedProject = null
    compare(b.enabled, false)
  }

  function test_row_hover_reports_the_index() {
    var sb = make()
    sb.dropdownOpen = true
    wait(20)
    var row = find(sb, "projectRow2")
    mouseMove(row, row.width / 2, row.height / 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 2)
  }
}
```
(The stub `TextField` cannot receive real key focus, so the filter field's key handlers are not exercised here; keyboard routing is covered at Panel level in Task 7 and by the manual live check.)

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/panel/run.sh`
Expected: `tst_sidebar.qml` FAILs (`Sidebar` is not a type).

- [ ] **Step 3: Write `Sidebar.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The panel's left column: a project dropdown, the section list, and a Delete
// project button. It renders and emits only; Panel.qml owns every piece of
// state (selection, cursor, delete flow) and passes it in.
Item {
  id: sidebar
  objectName: "sidebar"

  property var projects: []
  property var selectedProject: null
  property string section: "board"
  property bool dropdownOpen: false
  property string dropdownQuery: ""
  property int dropdownCursor: 0
  property bool canDelete: false
  property bool documentsEnabled: true
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal dropdownToggled()
  signal projectChosen(var project)
  signal queryEdited(string text)
  signal sectionChosen(string section)
  signal deleteRequested()
  signal cursorHovered(int index)
  signal dropdownMove(int delta)
  signal dropdownAccept()
  signal dropdownCancel()
  signal filterKey(var event)

  readonly property bool hasProject: !!selectedProject
  readonly property Item filterItem: filterField
  implicitHeight: Style.space(300)

  function focusFilter() { filterField.forceActiveFocus() }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    CursorSurface {
      id: projectButton
      objectName: "projectButton"
      Layout.fillWidth: true
      implicitHeight: buttonRow.implicitHeight + Style.spacing.rowPaddingX * 2
      bordered: true
      hasCursor: buttonArea.containsMouse || sidebar.dropdownOpen
      foreground: sidebar.foreground

      RowLayout {
        id: buttonRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)

        Text {
          Layout.fillWidth: true
          text: sidebar.selectedProject ? sidebar.selectedProject.name : "No project"
          color: sidebar.selectedProject ? sidebar.foreground : sidebar.dim
          font.family: sidebar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          text: sidebar.dropdownOpen ? "▴" : "▾"
          color: sidebar.dim
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        id: buttonArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sidebar.dropdownToggled()
      }
    }

    NavRow { objectName: "navBoard"; label: "Board"; section: "board"; enabled: sidebar.hasProject }
    NavRow { objectName: "navDocuments"; label: "Documents"; section: "documents"; enabled: sidebar.hasProject && sidebar.documentsEnabled }

    Item { Layout.fillHeight: true }

    Button {
      objectName: "deleteButton"
      Layout.fillWidth: true
      text: "Delete project…"
      enabled: sidebar.hasProject && sidebar.canDelete
      opacity: enabled ? 1 : 0.4
      bordered: true
      foreground: sidebar.urgent
      fontFamily: sidebar.fontFamily
      fontSize: Style.font.bodySmall
      verticalPadding: Style.spacing.controlPaddingY
      onClicked: sidebar.deleteRequested()
    }
  }

  // Overlaid on the sidebar, above the nav rows.
  Rectangle {
    id: dropdown
    objectName: "dropdown"
    visible: sidebar.dropdownOpen
    z: 10
    x: 0
    y: projectButton.y + projectButton.height + Style.space(4)
    width: sidebar.width
    height: dropdownColumn.implicitHeight + Style.space(12)
    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.space(6)

    Column {
      id: dropdownColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      spacing: Style.space(6)

      TextField {
        id: filterField
        objectName: "filterField"
        width: parent.width
        foreground: sidebar.foreground
        placeholderText: "Search projects…"
        text: sidebar.dropdownQuery
        onTextChanged: if (text !== sidebar.dropdownQuery) sidebar.queryEdited(text)

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Down) { sidebar.dropdownMove(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up) { sidebar.dropdownMove(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { sidebar.dropdownAccept(); event.accepted = true; return }
          if (event.key === Qt.Key_Escape) { sidebar.dropdownCancel(); event.accepted = true; return }
          sidebar.filterKey(event)
        }
      }

      Text {
        visible: sidebar.projects.length === 0
        width: parent.width
        text: sidebar.dropdownQuery === "" ? "No projects registered." : "No projects match “" + sidebar.dropdownQuery + "”."
        color: sidebar.dim
        font.family: sidebar.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Flickable {
        id: listFlick
        width: parent.width
        height: Math.min(listColumn.implicitHeight, Style.space(240))
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: listColumn
          width: listFlick.width
          spacing: Style.space(2)

          Repeater {
            model: sidebar.projects
            delegate: ProjectItem {}
          }
        }

        function ensureVisible(item) {
          var top = item.y
          var bottom = item.y + item.height
          if (top < contentY) contentY = top
          else if (bottom > contentY + height) contentY = bottom - height
        }
      }
    }
  }

  component NavRow: CursorSurface {
    id: navRow
    property string label: ""
    property string section: ""

    Layout.fillWidth: true
    implicitHeight: navLabel.implicitHeight + Style.spacing.rowPaddingX * 2
    current: sidebar.section === section
    hasCursor: navArea.containsMouse && enabled
    opacity: enabled ? 1 : 0.4
    foreground: sidebar.foreground

    Text {
      id: navLabel
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      text: navRow.label
      color: sidebar.foreground
      font.family: sidebar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: navRow.current
    }

    MouseArea {
      id: navArea
      anchors.fill: parent
      enabled: navRow.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sidebar.sectionChosen(navRow.section)
    }
  }

  component ProjectItem: CursorSurface {
    id: item
    required property var modelData
    required property int index
    objectName: "projectRow" + index

    width: listColumn.width
    implicitHeight: itemLabel.implicitHeight + Style.spacing.rowPaddingX * 2
    hasCursor: sidebar.dropdownCursor === index
    current: !!sidebar.selectedProject && modelData.root_path === sidebar.selectedProject.root_path
    foreground: sidebar.foreground
    onHasCursorChanged: if (hasCursor) listFlick.ensureVisible(item)

    Text {
      id: itemLabel
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      text: item.modelData.name
      color: sidebar.foreground
      font.family: sidebar.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: sidebar.cursorHovered(item.index)
      onClicked: sidebar.projectChosen(item.modelData)
    }
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/panel/run.sh`
Expected: `tst_sidebar.qml` passes and the earlier files still pass, no warnings printed. If a stub gap surfaces (a property real Quickshell has but a stub lacks), add it to the stub, not to `Sidebar.qml`.

- [ ] **Step 5: Commit**

```bash
git add Sidebar.qml tests/panel
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add the Sidebar component" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 5: Panel — sidebar layout, dropdown, and selection replace the project list

**Files:**
- Modify: `Panel.qml`
- Create: `tests/panel/tst_sidebar_nav.qml`
- Modify: `tests/panel/tst_board_flow.qml`, `tests/panel/tst_delete_flow.qml` (small adaptations, below)

**Interfaces:**
- Consumes: `Sidebar` (Task 4); `Logic.filterProjects`, `Logic.chooseProject` (Task 3).
- Produces (functions/properties on the `Panel` root that later tasks and tests rely on):
  - `viewMode`: `"board" | "entry"` (Task 11 adds `"documents" | "document"`); initial value `"board"`; the `"projects"` mode is gone.
  - `dropdownOpen`, `dropdownQuery`, `dropdownCursor`; `filteredProjects` (= `Logic.filterProjects(projects, dropdownQuery)`).
  - `storedProject` (string, default `""`) and `stateLoaded` (bool, default `true` in this task; Task 6 makes it `false` until the state helper answers).
  - `readonly property string section` (`"board"` or `"documents"`), `readonly property bool documentsEnabled` (`false` in this task).
  - `applyProjectsList(list)`, `maybeSelectInitial()`, `clearSelection()`, `chooseProject(project)`, `persistLastProject(path)` (in this task it only sets `storedProject`), `toggleDropdown()`, `closeDropdown()`, `moveDropdown(delta)`, `acceptDropdown()`, `showSection(name)`, `onPanelOpened()`.
  - Removed: `ProjectRow`, `deleteCurrentProject`, the per-row trash button, the Delete-key handler, `openProjects`, the projects `Column`, `searchQuery` use for projects.

- [ ] **Step 1: Write the failing test** `tests/panel/tst_sidebar_nav.qml`

```qml
import QtQuick
import QtTest
TestCase {
  id: tc
  name: "SidebarNav"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var A: ({ root_path: "/home/u/a", name: "alpha" })
  property var B: ({ root_path: "/home/u/b", name: "beta" })
  property var C: ({ root_path: "/home/u/c", name: "gamma" })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    return p
  }
  function names(list) { return list.map(function(x) { return x.name }).join(",") }

  function test_first_project_is_selected_when_the_list_arrives() {
    var p = make(); if (!p) return
    compare(p.viewMode, "board")
    compare(p.selectedProject, null)
    p.applyProjectsList([A, B, C])
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(p.viewMode, "board")
  }

  function test_stored_project_wins_over_the_first() {
    var p = make(); if (!p) return
    p.storedProject = "/home/u/c"
    p.applyProjectsList([A, B, C])
    compare(p.selectedProject.root_path, "/home/u/c")
  }

  function test_current_project_is_kept_when_the_list_refreshes() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B, C])
    p.chooseProject(B)
    p.applyProjectsList([A, B, C])
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_vanished_current_project_falls_back() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B, C])
    p.chooseProject(B)
    p.applyProjectsList([A, C])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_empty_registry_clears_the_selection() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B])
    p.applyTreeData([{ id: "x", title: "X", status: "todo", blocked_by: [], children: [] }])
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(p.cardRoots.length, 0)
    compare(p.viewMode, "board")
    p.showSection("board")
    compare(p.viewMode, "board")
  }

  function test_choose_project_switches_persists_and_closes_the_dropdown() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B, C])
    p.toggleDropdown()
    compare(p.dropdownOpen, true)
    p.chooseProject(C)
    compare(p.dropdownOpen, false)
    compare(p.selectedProject.root_path, "/home/u/c")
    compare(p.storedProject, "/home/u/c")
    compare(p.viewMode, "board")
  }

  function test_dropdown_keyboard() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B, C])
    p.toggleDropdown()
    compare(p.dropdownCursor, 0)              // starts on the current project
    p.moveDropdown(1); compare(p.dropdownCursor, 1)
    p.moveDropdown(9); compare(p.dropdownCursor, 2)
    p.moveDropdown(-9); compare(p.dropdownCursor, 0)
    p.dropdownQuery = "gam"
    compare(names(p.filteredProjects), "gamma")
    p.dropdownCursor = 0
    p.acceptDropdown()
    compare(p.selectedProject.root_path, "/home/u/c")
    compare(p.dropdownOpen, false)
    compare(p.dropdownQuery, "")
  }

  function test_dropdown_opens_on_the_current_project_and_toggles_closed() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B, C])
    p.chooseProject(B)
    p.toggleDropdown()
    compare(p.dropdownCursor, 1)
    p.toggleDropdown()
    compare(p.dropdownOpen, false)
  }

  function test_dropdown_cannot_open_during_delete_confirmation() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B])
    p.openDelete(p.selectedProject)
    p.toggleDropdown()
    compare(p.dropdownOpen, false)
  }

  function test_documents_section_is_unavailable_in_phase_a() {
    var p = make(); if (!p) return
    p.applyProjectsList([A])
    compare(p.documentsEnabled, false)
    p.showSection("documents")
    compare(p.viewMode, "board")
    compare(p.section, "board")
  }

  function test_back_from_the_board_does_nothing_and_from_a_card_returns_to_the_board() {
    var p = make(); if (!p) return
    p.applyProjectsList([A])
    p.applyTreeData([{ id: "m", title: "M", status: "todo", blocked_by: [], children: [] }])
    p.goBack()
    compare(p.viewMode, "board")
    p.cursorIndex = 0; p.activateCursor()
    compare(p.viewMode, "entry")
    p.goBack()
    compare(p.viewMode, "board")
  }

  function test_opening_the_panel_resets_transient_state() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B])
    p.toggleDropdown(); p.dropdownQuery = "x"
    p.opened = false; p.opened = true
    compare(p.dropdownOpen, false); compare(p.dropdownQuery, "")
  }
}
```
Adapt the two baseline tests so they keep passing under the new model:
- `tst_board_flow.qml`: replace `p.projects = [...]` + `p.selectProject(p.projects[0])` with `p.applyProjectsList([{ root_path: "/x", name: "proj" }])` and keep everything else.
- `tst_delete_flow.qml`: replace `p.projects = [...]` with `p.applyProjectsList([{ root_path: "/home/u/a", name: "alpha" }, { root_path: "/home/u/b", name: "beta" }])`; after the successful-delete block add `p.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])` and `compare(p.selectedProject.root_path, "/home/u/b")` (the removed project falls back to the remaining one).

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/panel/run.sh`
Expected: `tst_sidebar_nav.qml` fails (`applyProjectsList` is not a function, etc.).

- [ ] **Step 3: Implement in `Panel.qml`** (edit in place; every function keeps exactly one declaration)

State and helpers (top of the root):
```qml
  property string viewMode: "board"   // "board" | "entry" | "documents" | "document"
  property bool dropdownOpen: false
  property string dropdownQuery: ""
  property int dropdownCursor: 0
  property string storedProject: ""
  property bool stateLoaded: true     // Task 6: false until viewer-state.py answers

  readonly property string section: (viewMode === "documents" || viewMode === "document") ? "documents" : "board"
  readonly property string sectionTitle: section === "documents" ? "Documents" : "Board"
  readonly property bool documentsEnabled: false   // Task 11 turns this on

  readonly property var filteredProjects: Logic.filterProjects(root.projects, root.dropdownQuery)
```
Replace `currentList()`:
```qml
  function currentList() {
    if (root.viewMode === "board") return root.boardCards
    if (root.viewMode === "entry") return root.detailLinkList
    return []
  }
```
Replace `focusForView()`:
```qml
  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.deleteTarget) {
        if (confirmField) confirmField.forceActiveFocus()
      } else if (root.dropdownOpen) {
        if (sidebar) sidebar.focusFilter()
      } else if (root.viewMode === "entry" || root.viewMode === "document") {
        if (keyCatcher) keyCatcher.forceActiveFocus()
      } else if (searchField) {
        searchField.forceActiveFocus()
      }
    })
  }
```
Replace `activateCursor()`:
```qml
  function activateCursor() {
    var list = root.currentList()
    if (root.cursorIndex < 0 || root.cursorIndex >= list.length) return
    root.openCard(list[root.cursorIndex].id)
  }
```
Delete `deleteCurrentProject()`. In `openDelete(project)` add `root.dropdownOpen = false` as its first statement. Replace `openProjects()` and `onOpenedChanged`, `selectProject`, `goBack`, and add the new functions:
```qml
  // The panel was just opened: refresh the registry and drop any half-finished
  // UI state. The project on screen stays selected while it is still registered.
  function onPanelOpened() {
    root.dropdownOpen = false
    root.dropdownQuery = ""
    if (!root.deleting) { root.deleteTarget = null; root.confirmText = ""; root.deleteError = "" }
    root.refreshProjects()
    root.focusForView()
  }
  onOpenedChanged: if (opened) onPanelOpened()

  function applyProjectsList(list) {
    root.projects = list
    root.maybeSelectInitial()
  }

  function maybeSelectInitial() {
    if (!root.stateLoaded) return
    var current = root.selectedProject ? root.selectedProject.root_path : ""
    var chosen = Logic.chooseProject(root.projects, current, root.storedProject)
    if (!chosen) { root.clearSelection(); return }
    if (chosen.root_path !== current) root.selectProject(chosen)
    else root.selectedProject = chosen
  }

  function clearSelection() {
    root.selectedProject = null
    root.watchedDbPath = ""
    root.applyTreeData([])
    root.viewMode = "board"
  }

  function selectProject(project) {
    selectedProject = project
    resetSearch()
    viewMode = "board"
    root.watchedDbPath = ""
    resolveDbPathProc.command = ["python3", root.pluginDir + "resolve-db-path.py", project.root_path]
    resolveDbPathProc.running = false
    resolveDbPathProc.running = true
    fetchBoard()
    focusForView()
  }

  // The user picked a project in the dropdown.
  function chooseProject(project) {
    root.closeDropdown()
    if (!project) return
    root.lastSnapshot = ""
    var current = root.selectedProject ? root.selectedProject.root_path : ""
    if (project.root_path !== current) {
      root.selectProject(project)
      root.persistLastProject(project.root_path)
    }
    root.focusForView()
  }

  function persistLastProject(path) { root.storedProject = path }   // Task 6 also saves it

  function toggleDropdown() {
    if (root.deleteTarget) return
    if (root.dropdownOpen) { root.closeDropdown(); return }
    root.dropdownQuery = ""
    var index = 0
    for (var i = 0; i < root.projects.length; i++)
      if (root.selectedProject && root.projects[i].root_path === root.selectedProject.root_path) index = i
    root.dropdownCursor = index
    root.dropdownOpen = true
    root.focusForView()
  }

  function closeDropdown() {
    if (!root.dropdownOpen) return
    root.dropdownOpen = false
    root.dropdownQuery = ""
    root.focusForView()
  }

  function moveDropdown(delta) {
    var n = root.filteredProjects.length
    if (n === 0) return
    root.dropdownCursor = root.clamp(root.dropdownCursor + delta, 0, n - 1)
  }

  function acceptDropdown() {
    var list = root.filteredProjects
    if (root.dropdownCursor < 0 || root.dropdownCursor >= list.length) return
    root.chooseProject(list[root.dropdownCursor])
  }

  function showSection(name) {
    if (!root.selectedProject || root.deleteTarget) return
    if (name === "documents" && !root.documentsEnabled) return
    if (root.dropdownOpen) root.dropdownOpen = false
    root.resetSearch()
    root.scrollOnCursor = false
    root.viewMode = name === "documents" ? "documents" : "board"
    Qt.callLater(root.scrollToTop)
    root.focusForView()
  }

  function goBack() {
    if (viewMode === "entry") { restoreListView(); return }
  }
```
`selectProject` no longer clears `lastSnapshot` (the post-delete note must survive the automatic reselection); `chooseProject` and `openDelete` clear it. The IPC `refresh()` becomes `function refresh(): string { root.refreshProjects(); return "ok" }`. In `listProc`'s `onStreamFinished` replace the assignment of `root.projects` with `root.applyProjectsList(list)` where `list` is the parsed, name-sorted array. In `deleteProc.onExited`'s success branch keep `root.refreshProjects()` (the arriving list reselects through `maybeSelectInitial`).

Layout: inside `PanelKeyCatcher`, add the sidebar before the `Flickable` and re-anchor the flickable:
```qml
      Sidebar {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(200)
        projects: root.filteredProjects
        selectedProject: root.selectedProject
        section: root.section
        dropdownOpen: root.dropdownOpen
        dropdownQuery: root.dropdownQuery
        dropdownCursor: root.dropdownCursor
        canDelete: !!root.selectedProject && !root.deleting && !root.deleteTarget
        documentsEnabled: root.documentsEnabled
        foreground: root.foreground
        dim: root.dim
        urgent: root.urgent
        fontFamily: root.fontFamily
        onDropdownToggled: root.toggleDropdown()
        onProjectChosen: function(project) { root.chooseProject(project) }
        onQueryEdited: function(text) { root.dropdownQuery = text; root.dropdownCursor = 0 }
        onSectionChosen: function(name) { root.showSection(name) }
        onDeleteRequested: root.openDelete(root.selectedProject)
        onCursorHovered: function(index) { root.dropdownCursor = index }
        onDropdownMove: function(delta) { root.moveDropdown(delta) }
        onDropdownAccept: root.acceptDropdown()
        onDropdownCancel: root.closeDropdown()
      }
```
and on the existing `Flickable { id: panelFlick ... }` replace `anchors.fill: parent` with:
```qml
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
```
`KeyboardPanel`: `contentWidth: panel.fittedContentWidth(Style.space(840))`, `contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, sidebar.implicitHeight), Style.space(620))`, and
`focusTarget: (root.viewMode === "entry" || root.viewMode === "document") ? keyCatcher : (root.deleteTarget ? confirmField : (root.dropdownOpen ? sidebar.filterItem : searchField))`.

Content column edits: header Back text `visible: root.viewMode === "entry" || root.viewMode === "document"`; title text becomes `root.selectedProject ? root.sectionTitle : "brd Viewer"`. `searchField`: `visible: !root.deleteTarget && !!root.selectedProject && (root.viewMode === "board" || root.viewMode === "documents")`, `placeholderText: root.viewMode === "documents" ? "Search documents…" : "Search cards…"`; in its `Keys.onPressed`: Escape → clear the query, else `root.close()`; delete the Left-at-caret-0 Back branch and the whole Delete-key branch. `keyCatcher.onCloseRequested`: `root.deleteTarget ? root.cancelDelete() : (root.dropdownOpen ? root.closeDropdown() : ((root.viewMode === "entry" || root.viewMode === "document") ? root.goBack() : root.close()))`; `onMoveRequested`: `if (dx < 0 && (root.viewMode === "entry" || root.viewMode === "document")) { root.goBack(); return }` and the rest unchanged for `entry`. Confirm block `visible: !!root.deleteTarget` (was `viewMode === "projects" && ...`); snapshot note `visible: !root.deleteTarget && root.lastSnapshot !== ""`. Delete the projects `Column` (the one containing `projectsRepeater`) and the `component ProjectRow`. Add, just before the Board column, an empty state:
```qml
          Text {
            visible: !root.selectedProject && root.loadError === ""
            width: parent.width
            text: "No projects registered with brd."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
```
and make the Board column `visible: root.viewMode === "board" && !!root.selectedProject`.

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/panel/run.sh`
Expected: all harness files pass (`tst_sidebar_nav.qml` 12 tests, plus the adapted baselines), no warnings.
Run: `./run-tests.sh`
Expected: everything passes.

- [ ] **Step 5: Commit**

```bash
git add Panel.qml tests/panel
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Replace the project list with the sidebar and project dropdown" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 6: Panel — remember the last project

**Files:**
- Modify: `Panel.qml`
- Create: `tests/panel/tst_persistence.qml`
- Modify: `tests/panel/tst_sidebar_nav.qml` (start states)

**Interfaces:**
- Consumes: `viewer-state.py` (Task 2), `Logic.parseStateResult` (Task 3), `applyProjectsList` / `maybeSelectInitial` / `persistLastProject` (Task 5).
- Produces: `stateLoaded` starts `false`; `applyStoredState(text, exitCode)`; `persistLastProject(path)` now also runs `viewer-state.py set-project <path>`; Processes with `objectName`s `stateGetProc` and `saveStateProc`.

- [ ] **Step 1: Write the failing test** `tests/panel/tst_persistence.qml`

```qml
import QtQuick
import QtTest
TestCase {
  id: tc
  name: "Persistence"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var A: ({ root_path: "/home/u/a", name: "alpha" })
  property var B: ({ root_path: "/home/u/b", name: "beta" })

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    return p
  }
  function proc(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }

  function test_the_state_is_requested_at_startup() {
    var p = make(); if (!p) return
    var get = proc(p, "stateGetProc")
    verify(get, "stateGetProc exists")
    compare(get.command[0], "python3")
    verify(String(get.command[1]).endsWith("viewer-state.py"))
    compare(get.command[2], "get")
    compare(get.running, true)
  }

  function test_nothing_is_selected_until_the_state_has_answered() {
    var p = make(); if (!p) return
    p.applyProjectsList([A, B])
    compare(p.stateLoaded, false)
    compare(p.selectedProject, null)
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    compare(p.stateLoaded, true)
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_the_state_arriving_first_also_works() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    compare(p.selectedProject, null)
    p.applyProjectsList([A, B])
    compare(p.selectedProject.root_path, "/home/u/b")
  }

  function test_a_stale_stored_project_falls_back_to_the_first() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/gone"}', 0)
    p.applyProjectsList([A, B])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_a_failed_or_corrupt_state_read_means_the_first_project() {
    var p = make(); if (!p) return
    p.applyStoredState("boom", 1)
    p.applyProjectsList([A, B])
    compare(p.selectedProject.root_path, "/home/u/a")
  }

  function test_choosing_a_project_saves_it() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": null}', 0)
    p.applyProjectsList([A, B])
    var save = proc(p, "saveStateProc")
    verify(save, "saveStateProc exists")
    p.chooseProject(B)
    compare(save.command[2], "set-project")
    compare(save.command[3], "/home/u/b")
    compare(save.running, true)
  }

  function test_an_unchanged_selection_is_not_rewritten() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/a"}', 0)
    var save = proc(p, "saveStateProc")
    p.applyProjectsList([A, B])
    compare(save.command, undefined)
    p.chooseProject(A)
    compare(save.command, undefined)
  }

  function test_the_fallback_after_a_removal_is_saved() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    p.applyProjectsList([A, B])
    p.applyProjectsList([A])
    var save = proc(p, "saveStateProc")
    compare(save.command[3], "/home/u/a")
    compare(p.storedProject, "/home/u/a")
  }

  function test_an_empty_registry_keeps_the_stored_choice() {
    var p = make(); if (!p) return
    p.applyStoredState('{"last_project": "/home/u/b"}', 0)
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(p.storedProject, "/home/u/b")
  }
}
```
In `tst_sidebar_nav.qml` add `p.stateLoaded = true` right after `p.opened = true` in `make()` so those tests keep exercising selection alone. In `tst_board_flow.qml` and `tst_delete_flow.qml` add the same line after `p.opened = true`.

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/panel/run.sh`
Expected: `tst_persistence.qml` fails (`stateGetProc` not found, `applyStoredState` not a function).

- [ ] **Step 3: Implement in `Panel.qml`**

Change `property bool stateLoaded: true` to `property bool stateLoaded: false` (drop its "Task 6" comment). Replace the stub `persistLastProject` and extend `maybeSelectInitial`; add `applyStoredState`, the two Processes and the startup request:
```qml
  function applyStoredState(text, exitCode) {
    root.storedProject = Logic.parseStateResult(text, exitCode) || ""
    root.stateLoaded = true
    root.maybeSelectInitial()
  }

  function persistLastProject(path) {
    root.storedProject = path
    saveStateProc.command = ["python3", root.pluginDir + "viewer-state.py", "set-project", path]
    saveStateProc.running = false
    saveStateProc.running = true
  }
```
In `maybeSelectInitial`, after `var chosen = ...` and the empty-list early return, insert before the selection logic:
```qml
    if (chosen.root_path !== root.storedProject) root.persistLastProject(chosen.root_path)
```
Add near the other Processes:
```qml
  Process {
    id: stateGetProc
    objectName: "stateGetProc"
    property string outText: ""
    command: ["python3", root.pluginDir + "viewer-state.py", "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: stateGetProc.outText = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var out = stateGetProc.outText
      stateGetProc.outText = ""
      root.applyStoredState(out, exitCode)
    }
  }

  // A failed save is deliberately silent: it never blocks navigation.
  Process {
    id: saveStateProc
    objectName: "saveStateProc"
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Component.onCompleted: stateGetProc.running = true
```
(If `Panel.qml` already has a `Component.onCompleted`, merge into it.)

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/panel/run.sh` then `./run-tests.sh`
Expected: all pass, no warnings.

- [ ] **Step 5: Commit**

```bash
git add Panel.qml tests/panel
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Remember the last viewed project across restarts" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 7: Panel — shortcuts, Delete project button, and post-delete selection

**Files:**
- Modify: `Panel.qml`
- Create: `tests/panel/tst_shortcuts_delete.qml`

**Interfaces:**
- Consumes: `Sidebar` signals (Task 4), the Panel functions from Tasks 5–6, the existing delete flow (`openDelete`, `performDelete`, `deleteProc`).
- Produces: `handleGlobalKey(event)` → `true` when it handled `Ctrl+P` (toggle dropdown), `Ctrl+1` (Board), `Ctrl+2` (Documents); `false` for everything else, and always `false` while `deleteTarget` is set. `event` needs only `modifiers` and `key`. The filter field, the search field and the key catcher route unconsumed keys through it.

- [ ] **Step 1: Write the failing test** `tests/panel/tst_shortcuts_delete.qml`

```qml
import QtQuick
import QtTest
TestCase {
  id: tc
  name: "ShortcutsAndDelete"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var A: ({ root_path: "/home/u/a", name: "alpha" })
  property var B: ({ root_path: "/home/u/b", name: "beta" })
  function ctrl(key) { return { modifiers: Qt.ControlModifier, key: key, accepted: false } }
  function plain(key) { return { modifiers: Qt.NoModifier, key: key, accepted: false } }

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.stateLoaded = true
    p.applyProjectsList([A, B])
    return p
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function proc(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }

  function test_ctrl_p_toggles_the_dropdown() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), true)
    compare(p.dropdownOpen, true)
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), true)
    compare(p.dropdownOpen, false)
  }

  function test_ctrl_digits_switch_sections() {
    var p = make(); if (!p) return
    p.chooseProject(B)
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), true)
    compare(p.viewMode, "board")
    compare(p.handleGlobalKey(ctrl(Qt.Key_2)), true)      // Documents is not enabled yet
    compare(p.viewMode, "board")
  }

  function test_other_keys_are_not_handled() {
    var p = make(); if (!p) return
    compare(p.handleGlobalKey(plain(Qt.Key_P)), false)
    compare(p.handleGlobalKey(ctrl(Qt.Key_X)), false)
    compare(p.handleGlobalKey(plain(Qt.Key_1)), false)
    compare(p.dropdownOpen, false)
  }

  function test_shortcuts_are_ignored_while_confirming_a_delete() {
    var p = make(); if (!p) return
    p.openDelete(p.selectedProject)
    compare(p.handleGlobalKey(ctrl(Qt.Key_P)), false)
    compare(p.handleGlobalKey(ctrl(Qt.Key_1)), false)
    compare(p.dropdownOpen, false)
  }

  function test_escape_with_the_dropdown_open_closes_only_the_dropdown() {
    var p = make(); if (!p) return
    p.toggleDropdown()
    var sb = find(p, "sidebar")
    verify(sb, "sidebar found")
    sb.dropdownCancel()
    compare(p.dropdownOpen, false)
    compare(p.opened, true)
  }

  function test_the_sidebar_delete_button_starts_the_confirmation_for_the_selected_project() {
    var p = make(); if (!p) return
    p.chooseProject(B)
    var sb = find(p, "sidebar")
    compare(sb.canDelete, true)
    sb.deleteRequested()
    compare(p.deleteTarget.root_path, "/home/u/b")
  }

  function test_delete_is_disabled_without_a_project_or_while_busy() {
    var p = make(); if (!p) return
    var sb = find(p, "sidebar")
    p.openDelete(p.selectedProject)
    compare(sb.canDelete, false)
    p.cancelDelete()
    compare(sb.canDelete, true)
    p.applyProjectsList([])
    compare(sb.canDelete, false)
  }

  function test_after_a_delete_the_first_remaining_project_is_shown_and_saved() {
    var p = make(); if (!p) return
    p.chooseProject(B)
    p.openDelete(p.selectedProject)
    p.confirmText = "delete"
    p.performDelete()
    var del = proc(p, "deleteProc")
    del.outText = '{"ok": true, "snapshot": "/home/u/Snapshots/brd-viewer/beta-1"}'
    del.exited(0)
    compare(p.deleteTarget, null)
    compare(p.lastSnapshot, "/home/u/Snapshots/brd-viewer/beta-1")
    p.applyProjectsList([A])                       // what `brd projects` returns next
    compare(p.selectedProject.root_path, "/home/u/a")
    compare(p.lastSnapshot, "/home/u/Snapshots/brd-viewer/beta-1")   // the note survives the reselection
    compare(proc(p, "saveStateProc").command[3], "/home/u/a")
  }

  function test_deleting_the_last_project_shows_the_empty_state() {
    var p = make(); if (!p) return
    p.applyProjectsList([A])
    p.openDelete(p.selectedProject)
    p.confirmText = "delete"; p.performDelete()
    var del = proc(p, "deleteProc")
    del.outText = '{"ok": true, "snapshot": "/s"}'
    del.exited(0)
    p.applyProjectsList([])
    compare(p.selectedProject, null)
    compare(p.viewMode, "board")
  }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/panel/run.sh`
Expected: the new file fails (`handleGlobalKey` is not a function).

- [ ] **Step 3: Implement in `Panel.qml`**

Add:
```qml
  // Shortcuts that work wherever the caret is. Returns true when it handled the
  // key. Ignored while a delete confirmation is open so a stray Ctrl+P cannot
  // move things underneath it.
  function handleGlobalKey(event) {
    if (!(event.modifiers & Qt.ControlModifier) || root.deleteTarget) return false
    if (event.key === Qt.Key_P) { root.toggleDropdown(); return true }
    if (event.key === Qt.Key_1) { root.showSection("board"); return true }
    if (event.key === Qt.Key_2) { root.showSection("documents"); return true }
    return false
  }

  Item {
    id: globalKeys
    Keys.onPressed: function(event) { if (root.handleGlobalKey(event)) event.accepted = true }
  }
```
Route keys: on `PanelKeyCatcher` (`keyCatcher`) add `Keys.forwardTo: [globalKeys]`; on `searchField` add `Keys.forwardTo: [globalKeys]` (its own `Keys.onPressed` runs first and only accepts the keys it handles); on `Sidebar` add `onFilterKey: function(event) { if (root.handleGlobalKey(event)) event.accepted = true }`. The `Sidebar` already has `onDeleteRequested: root.openDelete(root.selectedProject)` and `canDelete` from Task 5; no further wiring is needed for the delete button.

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/panel/run.sh` then `./run-tests.sh`
Expected: all pass, no warnings.

- [ ] **Step 5: Commit**

```bash
git add Panel.qml tests/panel
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add sidebar shortcuts and move project deletion to the sidebar" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

**Phase A is complete and usable here** (the Documents nav item is disabled until Task 11).

---

### Task 8: `list-docs.py`

**Files:**
- Create: `list-docs.py`, `tests/test_list_docs.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `python3 list-docs.py <root_path>` → one JSON line `{"ok": true, "docs": [{"path", "title", "size"}...], "truncated": bool}` (exit 0), or `{"ok": false, "error": "..."}` (exit 1 for a missing argument → exit 2). `path` is relative with forward slashes; `README.md` first, then case-insensitive path order; at most 500 entries.

- [ ] **Step 1: Write the failing tests**

```python
"""list-docs.py over throwaway project trees."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "list-docs.py")


def run(*args):
    proc = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)
    out = proc.stdout.strip().splitlines()
    return proc.returncode, (json.loads(out[-1]) if out else None)


def write(path, text="# T\n"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def paths(result):
    return [d["path"] for d in result["docs"]]


def test_missing_project_directory_is_an_empty_list(tmp_path):
    code, result = run(str(tmp_path / "nope"))
    assert code == 0 and result == {"ok": True, "docs": [], "truncated": False}


def test_project_without_docs_is_an_empty_list(tmp_path):
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "notes.md").write_text("# not under docs")
    assert run(str(tmp_path))[1]["docs"] == []


def test_readme_comes_first_then_docs_in_case_insensitive_order(tmp_path):
    write(tmp_path / "README.md", "# Readme title\n")
    write(tmp_path / "docs" / "b.md")
    write(tmp_path / "docs" / "A.md")
    write(tmp_path / "docs" / "sub" / "c.md")
    assert paths(run(str(tmp_path))[1]) == ["README.md", "docs/A.md", "docs/b.md", "docs/sub/c.md"]


def test_titles_come_from_the_first_h1_else_the_file_name(tmp_path):
    write(tmp_path / "docs" / "with-title.md", "intro\n\n# The Title\nbody\n")
    write(tmp_path / "docs" / "plain.md", "no heading here\n")
    write(tmp_path / "docs" / "empty-h1.md", "# \nbody\n")
    by_path = {d["path"]: d["title"] for d in run(str(tmp_path))[1]["docs"]}
    assert by_path["docs/with-title.md"] == "The Title"
    assert by_path["docs/plain.md"] == "plain"
    assert by_path["docs/empty-h1.md"] == "empty-h1"


def test_size_is_reported(tmp_path):
    write(tmp_path / "docs" / "a.md", "# T\n12345")
    assert run(str(tmp_path))[1]["docs"][0]["size"] == len("# T\n12345")


def test_extension_is_case_insensitive_and_other_files_are_ignored(tmp_path):
    write(tmp_path / "docs" / "UP.MD")
    write(tmp_path / "docs" / "notes.txt")
    write(tmp_path / "docs" / "img.png", "x")
    assert paths(run(str(tmp_path))[1]) == ["docs/UP.MD"]


def test_hidden_directories_are_skipped(tmp_path):
    write(tmp_path / "docs" / ".secret" / "x.md")
    write(tmp_path / "docs" / "ok.md")
    assert paths(run(str(tmp_path))[1]) == ["docs/ok.md"]


def test_paths_with_spaces_work(tmp_path):
    write(tmp_path / "docs" / "my notes" / "big plan.md")
    assert paths(run(str(tmp_path))[1]) == ["docs/my notes/big plan.md"]


def test_a_symlinked_file_that_escapes_the_project_is_skipped(tmp_path):
    outside = tmp_path / "outside.md"
    outside.write_text("# secret")
    proj = tmp_path / "proj"
    write(proj / "docs" / "ok.md")
    os.symlink(outside, proj / "docs" / "leak.md")
    assert paths(run(str(proj))[1]) == ["docs/ok.md"]


def test_a_symlinked_directory_is_not_followed(tmp_path):
    other = tmp_path / "other"
    write(other / "x.md")
    proj = tmp_path / "proj"
    write(proj / "docs" / "ok.md")
    os.symlink(other, proj / "docs" / "linked")
    assert paths(run(str(proj))[1]) == ["docs/ok.md"]


def test_a_docs_directory_symlinked_outside_is_ignored(tmp_path):
    other = tmp_path / "other"
    write(other / "x.md")
    proj = tmp_path / "proj"
    proj.mkdir()
    os.symlink(other, proj / "docs")
    assert run(str(proj))[1]["docs"] == []


def test_a_symlinked_file_staying_inside_the_project_is_listed(tmp_path):
    proj = tmp_path / "proj"
    write(proj / "docs" / "real.md")
    os.symlink(proj / "docs" / "real.md", proj / "docs" / "alias.md")
    assert paths(run(str(proj))[1]) == ["docs/alias.md", "docs/real.md"]


def test_the_list_is_capped_and_flagged(tmp_path):
    for i in range(505):
        write(tmp_path / "docs" / ("d%04d.md" % i), "x")
    result = run(str(tmp_path))[1]
    assert len(result["docs"]) == 500 and result["truncated"] is True


def test_exactly_the_cap_is_not_truncated(tmp_path):
    for i in range(500):
        write(tmp_path / "docs" / ("d%04d.md" % i), "x")
    result = run(str(tmp_path))[1]
    assert len(result["docs"]) == 500 and result["truncated"] is False


def test_binary_and_empty_files_do_not_crash(tmp_path):
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "bin.md").write_bytes(b"\xff\xfe\x00# nope\x80")
    (tmp_path / "docs" / "empty.md").write_bytes(b"")
    result = run(str(tmp_path))[1]
    assert sorted(paths(result)) == ["docs/bin.md", "docs/empty.md"]


def test_requires_a_path(tmp_path):
    code, result = run()
    assert code == 2 and result["ok"] is False
```

- [ ] **Step 2: Run to confirm failure**

Run: `python3 -m pytest tests/test_list_docs.py -q`
Expected: FAIL (script does not exist).

- [ ] **Step 3: Write `list-docs.py`**

```python
#!/usr/bin/env python3
"""List a brd project's Markdown documents.

    list-docs.py <root_path>

Prints one JSON line: {"ok": true, "docs": [{"path", "title", "size"}, ...],
"truncated": bool} or {"ok": false, "error": "..."}. A document is the root
README.md or any *.md under docs/. Only regular files whose resolved path lies
inside the resolved project root are listed; symlinked directories are never
followed and hidden directories are skipped.
"""
import json
import os
import sys

MAX_ENTRIES = 500
TITLE_SCAN_BYTES = 65536


def emit(payload, code=0):
    print(json.dumps(payload))
    return code


def inside(root_real, path_real):
    return path_real == root_real or path_real.startswith(root_real + os.sep)


def title_of(path, fallback):
    try:
        with open(path, "rb") as f:
            head = f.read(TITLE_SCAN_BYTES)
    except OSError:
        return fallback
    for line in head.decode("utf-8", errors="replace").splitlines():
        if line.startswith("# "):
            text = line[2:].strip()
            if text:
                return text
    return fallback


def candidates(root, root_real):
    found = []
    if os.path.isfile(os.path.join(root, "README.md")):
        found.append("README.md")
    docs = os.path.join(root, "docs")
    if os.path.isdir(docs) and inside(root_real, os.path.realpath(docs)):
        for dirpath, dirnames, filenames in os.walk(docs, followlinks=False):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            for name in filenames:
                if name.lower().endswith(".md"):
                    rel = os.path.relpath(os.path.join(dirpath, name), root)
                    found.append(rel.replace(os.sep, "/"))
    return found


def main(argv):
    if not argv or not argv[0]:
        return emit({"ok": False, "error": "usage: list-docs.py <root_path>"}, 2)
    root = argv[0]
    if not os.path.isdir(root):
        return emit({"ok": True, "docs": [], "truncated": False})
    root_real = os.path.realpath(root)

    docs = []
    for rel in candidates(root, root_real):
        full = os.path.join(root, rel)
        real = os.path.realpath(full)
        if not (os.path.isfile(real) and inside(root_real, real) and os.access(real, os.R_OK)):
            continue
        stem = os.path.splitext(os.path.basename(rel))[0]
        docs.append({"path": rel, "title": title_of(real, stem), "size": os.path.getsize(real)})

    docs.sort(key=lambda d: (d["path"] != "README.md", d["path"].lower()))
    truncated = len(docs) > MAX_ENTRIES
    return emit({"ok": True, "docs": docs[:MAX_ENTRIES], "truncated": truncated})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```
`chmod +x list-docs.py`.

- [ ] **Step 4: Run to confirm pass**

Run: `python3 -m pytest tests/test_list_docs.py -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add list-docs.py tests/test_list_docs.py
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add list-docs.py to list a project's Markdown documents" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 9: `logic.js` helpers for documents

**Files:**
- Modify: `logic.js`, `tests/qml/tst_logic.qml`

**Interfaces:**
- Consumes: `Logic.matchesQuery`.
- Produces:
  - `Logic.filterDocs(docs, query)` → the docs whose `title` or `path` matches `query` (empty query → all; `docs` undefined → `[]`).
  - `Logic.parseDocsResult(stdout, exitCode)` → `{ ok, docs, truncated, error }`: on success `docs` is the array (default `[]`), `truncated` a boolean; any failure yields `ok: false`, `docs: []` and `error` set (the helper's message, or `"Could not list documents."`).
  - `Logic.docAbsolutePath(rootPath, relPath)` → `rootPath` (trailing `/` stripped) + `"/"` + `relPath`.
  - `Logic.MAX_DOC_BYTES` = `1048576` and `Logic.docTooLarge(size)` → `size > MAX_DOC_BYTES`.

- [ ] **Step 1: Write the failing tests** (append inside the `TestCase`)

```qml
  // ---- documents ---------------------------------------------------------

  property var docList: [
    { path: "README.md", title: "Readme", size: 10 },
    { path: "docs/specs/Design.md", title: "Sidebar design", size: 20 },
    { path: "docs/plan.md", title: "Plan", size: 30 }
  ]

  function test_filter_docs_matches_title_and_path() {
    compare(Logic.filterDocs(docList, "").length, 3)
    compare(Logic.filterDocs(docList, "sidebar").map(function(d) { return d.path }).join(","), "docs/specs/Design.md")
    compare(Logic.filterDocs(docList, "DOCS/").length, 2)
    compare(Logic.filterDocs(docList, "zzz").length, 0)
    compare(Logic.filterDocs(undefined, "a").length, 0)
  }

  function test_parse_docs_result_success() {
    var r = Logic.parseDocsResult('{"ok": true, "docs": [{"path": "README.md", "title": "T", "size": 1}], "truncated": true}\n', 0)
    compare(r.ok, true)
    compare(r.docs.length, 1)
    compare(r.truncated, true)
    compare(r.error, "")
  }

  function test_parse_docs_result_failures_carry_a_message() {
    var h = Logic.parseDocsResult('{"ok": false, "error": "nope"}', 1)
    compare(h.ok, false); compare(h.error, "nope"); compare(h.docs.length, 0)
    var g = Logic.parseDocsResult("garbage", 0)
    compare(g.ok, false); compare(g.error, "Could not list documents.")
    compare(Logic.parseDocsResult("", 1).ok, false)
    compare(Logic.parseDocsResult(undefined, 0).ok, false)
    compare(Logic.parseDocsResult('{"ok": true, "docs": []}', 1).ok, false)
  }

  function test_parse_docs_result_defaults() {
    var r = Logic.parseDocsResult('{"ok": true}', 0)
    compare(r.ok, true); compare(r.docs.length, 0); compare(r.truncated, false)
  }

  function test_doc_absolute_path() {
    compare(Logic.docAbsolutePath("/home/u/p", "docs/a b.md"), "/home/u/p/docs/a b.md")
    compare(Logic.docAbsolutePath("/home/u/p/", "README.md"), "/home/u/p/README.md")
  }

  function test_doc_too_large() {
    compare(Logic.MAX_DOC_BYTES, 1048576)
    compare(Logic.docTooLarge(1048576), false)
    compare(Logic.docTooLarge(1048577), true)
    compare(Logic.docTooLarge(0), false)
  }
```

- [ ] **Step 2: Run to confirm failure**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml`
Expected: FAIL (`filterDocs`, `parseDocsResult`, `docAbsolutePath`, `docTooLarge` not functions).

- [ ] **Step 3: Implement** (append to `logic.js`)

```js

var MAX_DOC_BYTES = 1048576

function filterDocs(docs, query) {
  return (docs || []).filter(function(d) {
    return matchesQuery(d.title, query) || matchesQuery(d.path, query)
  })
}

// list-docs.py's last stdout line plus its exit code, as
// { ok, docs, truncated, error }. Anything but a clear success is a failure.
function parseDocsResult(stdout, exitCode) {
  var generic = "Could not list documents."
  var lines = String(stdout || "").split("\n").filter(function(l) { return l.trim() !== "" })
  var payload = null
  if (lines.length > 0) {
    try { payload = JSON.parse(lines[lines.length - 1]) } catch (e) { payload = null }
  }
  if (exitCode === 0 && payload && payload.ok === true)
    return { ok: true, docs: Array.isArray(payload.docs) ? payload.docs : [], truncated: payload.truncated === true, error: "" }
  var message = payload && typeof payload.error === "string" && payload.error !== "" ? payload.error : generic
  return { ok: false, docs: [], truncated: false, error: message }
}

function docAbsolutePath(rootPath, relPath) {
  return String(rootPath).replace(/\/+$/, "") + "/" + relPath
}

function docTooLarge(size) {
  return size > MAX_DOC_BYTES
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add logic.js tests/qml/tst_logic.qml
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add document helpers to logic.js" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 10: `DocumentsView.qml`

**Files:**
- Create: `DocumentsView.qml`, `tests/panel/tst_documents_view.qml`

**Interfaces:**
- Consumes: shell types `CursorSurface` (`qs.Ui`), `Style` (`qs.Commons`).
- Produces — `DocumentsView` (a `Column`; the parent sets its width):
  - Properties: `docs` (array, already filtered by the parent), `query` (string, used for the empty message only), `cursorIndex` (int), `loading` (bool), `error` (string), `truncated` (bool), `scrollOnCursor` (bool), `foreground`, `dim`, `fontFamily`.
  - Signals: `docChosen(string path)`, `hovered(int index)`, `revealRequested(var item)` (emitted when a row gains the cursor while `scrollOnCursor` is true, so the parent can scroll it into view).
  - Messages: loading → "Loading documents…"; `error` → the error text; no docs, no query → "No Markdown documents found in this project."; no docs with a query → "No documents match “<query>”."; `truncated` → a dim note "Showing the first 500 documents."
  - Row `objectName`s: `docRow0`, `docRow1`, …; message `objectName`: `docsMessage`.

- [ ] **Step 1: Write the failing test** `tests/panel/tst_documents_view.qml`

```qml
import QtQuick
import QtTest
TestCase {
  id: tc
  name: "DocumentsView"
  when: windowShown
  width: 400; height: 500

  Component { id: viewC; DocumentsView { width: 360 } }
  SignalSpy { id: chosen; signalName: "docChosen" }
  SignalSpy { id: hoverSpy; signalName: "hovered" }
  SignalSpy { id: revealSpy; signalName: "revealRequested" }

  property var docs: [
    { path: "README.md", title: "Readme", size: 10 },
    { path: "docs/plan.md", title: "Plan", size: 20 }
  ]

  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function make() {
    var v = createTemporaryObject(viewC, tc)
    var spies = [chosen, hoverSpy, revealSpy]
    for (var i = 0; i < spies.length; i++) { spies[i].target = v; spies[i].clear() }
    return v
  }

  function test_rows_render_and_choose_by_path() {
    var v = make()
    v.docs = docs
    wait(20)
    verify(find(v, "docRow1"))
    verify(!find(v, "docRow2"))
    var row = find(v, "docRow1")
    mouseClick(row, row.width / 2, row.height / 2)
    compare(chosen.count, 1)
    compare(chosen.signalArguments[0][0], "docs/plan.md")
  }

  function test_hover_reports_the_index() {
    var v = make()
    v.docs = docs
    wait(20)
    var row = find(v, "docRow1")
    mouseMove(row, row.width / 2, row.height / 2)
    verify(hoverSpy.count >= 1)
    compare(hoverSpy.signalArguments[hoverSpy.count - 1][0], 1)
  }

  function test_cursor_row_requests_a_reveal_only_for_keyboard_moves() {
    var v = make()
    v.docs = docs
    wait(20)
    v.scrollOnCursor = false
    v.cursorIndex = 1
    compare(revealSpy.count, 0)
    v.scrollOnCursor = true
    v.cursorIndex = 0
    compare(revealSpy.count, 1)
  }

  function test_messages() {
    var v = make()
    v.loading = true
    compare(find(v, "docsMessage").text, "Loading documents…")
    v.loading = false
    compare(find(v, "docsMessage").text, "No Markdown documents found in this project.")
    v.query = "zz"
    compare(find(v, "docsMessage").text, "No documents match “zz”.")
    v.error = "boom"
    compare(find(v, "docsMessage").text, "boom")
    v.error = ""
    v.docs = docs
    compare(find(v, "docsMessage").visible, false)
  }

  function test_truncated_note() {
    var v = make()
    v.docs = docs
    v.truncated = true
    compare(find(v, "docsTruncated").visible, true)
    v.truncated = false
    compare(find(v, "docsTruncated").visible, false)
  }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/panel/run.sh`
Expected: `tst_documents_view.qml` fails (`DocumentsView` is not a type).

- [ ] **Step 3: Write `DocumentsView.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The Documents section's list: one row per Markdown file (title, dim path).
// It renders and emits only; Panel.qml owns the list, the cursor and the query.
Column {
  id: view
  objectName: "documentsView"
  spacing: Style.space(6)

  property var docs: []
  property string query: ""
  property int cursorIndex: -1
  property bool loading: false
  property string error: ""
  property bool truncated: false
  property bool scrollOnCursor: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal docChosen(string path)
  signal hovered(int index)
  signal revealRequested(var item)

  Text {
    objectName: "docsMessage"
    visible: text !== ""
    width: parent.width
    text: view.loading ? "Loading documents…"
      : view.error !== "" ? view.error
      : view.docs.length === 0 ? (view.query === "" ? "No Markdown documents found in this project."
        : "No documents match “" + view.query + "”.")
      : ""
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: view.loading || view.error !== "" ? [] : view.docs
    delegate: DocRow {}
  }

  Text {
    objectName: "docsTruncated"
    visible: view.truncated
    width: parent.width
    text: "Showing the first 500 documents."
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
  }

  component DocRow: CursorSurface {
    id: row
    required property var modelData
    required property int index
    objectName: "docRow" + index

    width: view.width
    implicitHeight: rowColumn.implicitHeight + Style.spacing.rowPaddingX
    hasCursor: view.cursorIndex === index
    foreground: view.foreground
    onHasCursorChanged: if (hasCursor && view.scrollOnCursor) view.revealRequested(row)

    Column {
      id: rowColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: row.modelData.title
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: row.modelData.path
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: view.hovered(row.index)
      onClicked: view.docChosen(row.modelData.path)
    }
  }
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/panel/run.sh`
Expected: all harness files pass, no warnings.

- [ ] **Step 5: Commit**

```bash
git add DocumentsView.qml tests/panel
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add the DocumentsView component" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 11: Panel — the Documents section

**Files:**
- Modify: `Panel.qml`
- Create: `tests/panel/tst_documents_flow.qml`

**Interfaces:**
- Consumes: `list-docs.py` (Task 8), `Logic.filterDocs` / `parseDocsResult` / `docAbsolutePath` / `docTooLarge` (Task 9), `DocumentsView` (Task 10), the Panel API from Tasks 5–7.
- Produces: `documentsEnabled` becomes `true`; `viewMode` gains `"documents"` and `"document"`; new state `docs`, `docsError`, `docsLoading`, `docsTruncated`, `selectedDocPath`, `docText`, `docError`, `docTooLargeFlag`; functions `fetchDocs()`, `applyDocsResult(text, exitCode)`, `openDoc(path)`, `restoreDocumentsList()`; `readonly property var filteredDocs`; Process `listDocsProc` (`objectName: "listDocsProc"`); `FileView` `docFile`. `currentList()` returns `filteredDocs` in `documents`; `activateCursor()` opens the highlighted document; `goBack()` from `document` returns to the list with cursor and scroll restored; Up/Down scroll a document; `showSection("documents")` fetches the list.

- [ ] **Step 1: Write the failing test** `tests/panel/tst_documents_flow.qml`

First, update the two earlier tests that assumed Documents was disabled (they are expected to fail once `documentsEnabled` becomes `true`, so change them now and watch them fail for the right reason):
- In `tests/panel/tst_sidebar_nav.qml` delete `test_documents_section_is_unavailable_in_phase_a`.
- In `tests/panel/tst_shortcuts_delete.qml` change `test_ctrl_digits_switch_sections` so that after `Ctrl+2` it expects `compare(p.viewMode, "documents")` and after a following `Ctrl+1` it expects `compare(p.viewMode, "board")`.

```qml
import QtQuick
import QtTest
TestCase {
  id: tc
  name: "DocumentsFlow"
  when: windowShown
  width: 400; height: 700
  Component { id: hostC; Item { width: 400; height: 700 } }

  property var A: ({ root_path: "/home/u/my proj", name: "alpha" })
  property var B: ({ root_path: "/home/u/b", name: "beta" })
  property string LIST: '{"ok": true, "docs": [' +
    '{"path": "README.md", "title": "Readme", "size": 100},' +
    '{"path": "docs/specs/Design Doc.md", "title": "Design", "size": 200},' +
    '{"path": "docs/huge.md", "title": "Huge", "size": 2000000}], "truncated": false}'

  function make() {
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var p = comp.createObject(host)
    p.opened = true
    p.stateLoaded = true
    p.applyProjectsList([A, B])
    return p
  }
  function named(p, name) {
    for (var i = 0; i < p.data.length; i++) if (p.data[i] && p.data[i].objectName === name) return p.data[i]
    return null
  }
  function paths(list) { return list.map(function(d) { return d.path }).join(",") }

  function test_documents_are_enabled_and_fetched_when_the_section_opens() {
    var p = make(); if (!p) return
    compare(p.documentsEnabled, true)
    var proc = named(p, "listDocsProc")
    verify(proc, "listDocsProc")
    p.showSection("documents")
    compare(p.viewMode, "documents")
    compare(p.section, "documents")
    compare(p.docsLoading, true)
    compare(proc.command[0], "python3")
    verify(String(proc.command[1]).endsWith("list-docs.py"))
    compare(proc.command[2], "/home/u/my proj")
    compare(proc.running, true)
  }

  function test_the_result_fills_the_list_and_filtering_works() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    compare(p.docsLoading, false)
    compare(paths(p.docs), "README.md,docs/specs/Design Doc.md,docs/huge.md")
    p.searchQuery = "design"
    compare(paths(p.filteredDocs), "docs/specs/Design Doc.md")
    compare(paths(p.currentList()), "docs/specs/Design Doc.md")
  }

  function test_a_failed_listing_shows_the_error_and_keeps_the_board_usable() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult('{"ok": false, "error": "nope"}', 1)
    compare(p.docsError, "nope")
    compare(p.docs.length, 0)
    p.showSection("board")
    compare(p.viewMode, "board")
  }

  function test_opening_a_document_points_the_file_view_at_its_absolute_path() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    p.cursorIndex = 1
    p.activateCursor()
    compare(p.viewMode, "document")
    compare(p.section, "documents")
    compare(p.selectedDocPath, "docs/specs/Design Doc.md")
    var fv = named(p, "docFile")
    verify(fv, "docFile")
    compare(fv.path, "/home/u/my proj/docs/specs/Design Doc.md")
    compare(fv.watchChanges, true)
    fv.stubText = "# Design\n\nbody"
    fv.loaded()
    compare(p.docText, "# Design\n\nbody")
  }

  function test_a_file_change_reloads_the_text() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    p.cursorIndex = 0; p.activateCursor()
    var fv = named(p, "docFile")
    fv.stubText = "one"; fv.loaded(); compare(p.docText, "one")
    fv.stubText = "two"; fv.loaded(); compare(p.docText, "two")
  }

  function test_a_document_over_one_megabyte_is_not_loaded() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    p.cursorIndex = 2; p.activateCursor()
    compare(p.viewMode, "document")
    compare(p.docTooLargeFlag, true)
    compare(named(p, "docFile").path, "")
  }

  function test_a_read_failure_is_shown_with_back_available() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    p.cursorIndex = 0; p.activateCursor()
    named(p, "docFile").loadFailed(1)
    compare(p.docError, "Could not read this document.")
    p.goBack()
    compare(p.viewMode, "documents")
  }

  function test_back_restores_the_list_position() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    p.cursorIndex = 1
    p.activateCursor()
    p.goBack()
    compare(p.viewMode, "documents")
    compare(p.cursorIndex, 1)
    compare(p.selectedDocPath, "")
  }

  function test_escape_from_the_documents_list_is_left_to_the_close_handler() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.goBack()
    compare(p.viewMode, "documents")
  }

  function test_switching_project_reloads_the_documents_list() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    p.chooseProject(B)
    compare(p.viewMode, "board")
    p.showSection("documents")
    compare(named(p, "listDocsProc").command[2], "/home/u/b")
    compare(p.docs.length, 0)
    compare(p.docsLoading, true)
  }

  function test_a_stale_reply_from_the_previous_project_is_ignored() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.chooseProject(B)
    p.showSection("documents")
    p.applyDocsResult(LIST, 0, "/home/u/my proj")   // the reply for the project we left
    compare(p.docs.length, 0)
    p.applyDocsResult(LIST, 0, "/home/u/b")
    compare(p.docs.length, 3)
  }

  function test_keyboard_scrolls_an_open_document_and_ctrl_1_leaves_it() {
    var p = make(); if (!p) return
    p.showSection("documents")
    p.applyDocsResult(LIST, 0)
    p.cursorIndex = 0; p.activateCursor()
    compare(p.handleGlobalKey({ modifiers: Qt.ControlModifier, key: Qt.Key_1 }), true)
    compare(p.viewMode, "board")
  }
}
```
Note: `applyDocsResult(text, exitCode, rootPath)` takes an optional third argument, the project root the reply belongs to; when given and different from `selectedProject.root_path` the reply is ignored (the `listDocsProc` handler passes the root it was started for).

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/panel/run.sh`
Expected: `tst_documents_flow.qml` fails (`documentsEnabled` is false, `listDocsProc` missing).

- [ ] **Step 3: Implement in `Panel.qml`**

State and derived values:
```qml
  readonly property bool documentsEnabled: true      // replaces the Task 5 `false`

  property var docs: []
  property bool docsLoading: false
  property string docsError: ""
  property bool docsTruncated: false
  property string selectedDocPath: ""
  property string docText: ""
  property string docError: ""
  property bool docTooLargeFlag: false
  property string docsRoot: ""            // the project the list was requested for

  readonly property var filteredDocs: Logic.filterDocs(root.docs, root.searchQuery)
```
Extend `currentList()` with `if (root.viewMode === "documents") return root.filteredDocs`. Replace the tail of `activateCursor()`:
```qml
    if (root.viewMode === "documents") root.openDoc(list[root.cursorIndex].path)
    else root.openCard(list[root.cursorIndex].id)
```
Functions:
```qml
  function fetchDocs() {
    if (!root.selectedProject) return
    root.docsRoot = root.selectedProject.root_path
    root.docs = []
    root.docsError = ""
    root.docsTruncated = false
    root.docsLoading = true
    listDocsProc.command = ["python3", root.pluginDir + "list-docs.py", root.docsRoot]
    listDocsProc.running = false
    listDocsProc.running = true
  }

  function applyDocsResult(text, exitCode, forRoot) {
    if (forRoot !== undefined && (!root.selectedProject || forRoot !== root.selectedProject.root_path)) return
    var result = Logic.parseDocsResult(text, exitCode)
    root.docsLoading = false
    root.docs = result.docs
    root.docsTruncated = result.truncated
    root.docsError = result.ok ? "" : result.error
  }

  function openDoc(path) {
    var entry = null
    for (var i = 0; i < root.docs.length; i++) if (root.docs[i].path === path) entry = root.docs[i]
    if (!entry || !root.selectedProject) return
    root.returnCursor = root.cursorIndex
    root.returnScrollY = panelFlick ? panelFlick.contentY : 0
    root.selectedDocPath = path
    root.docText = ""
    root.docError = ""
    root.docTooLargeFlag = Logic.docTooLarge(entry.size)
    root.viewMode = "document"
    root.scrollOnCursor = false
    root.cursorIndex = 0
    Qt.callLater(root.scrollToTop)
    root.focusForView()
  }

  function restoreDocumentsList() {
    root.selectedDocPath = ""
    root.docText = ""
    root.docError = ""
    root.docTooLargeFlag = false
    root.viewMode = "documents"
    root.scrollOnCursor = false
    root.cursorIndex = root.returnCursor
    Qt.callLater(function() { if (panelFlick) root.scrollBy(root.returnScrollY - panelFlick.contentY) })
    root.focusForView()
  }
```
`goBack()` gains `if (viewMode === "document") { restoreDocumentsList(); return }`. In `showSection(name)` replace its viewMode assignment so entering Documents fetches:
```qml
    root.viewMode = name === "documents" ? "documents" : "board"
    if (name === "documents") root.fetchDocs()
```
and in `selectProject(project)` reset the section state: after `viewMode = "board"` add `root.docs = []; root.docsError = ""; root.docsLoading = false; root.selectedDocPath = ""; root.docText = ""; root.docError = ""; root.docTooLargeFlag = false`. In `clearSelection()` do the same resets.

Process and file view:
```qml
  Process {
    id: listDocsProc
    objectName: "listDocsProc"
    property string outText: ""
    property string forRoot: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: listDocsProc.outText = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var out = listDocsProc.outText
      listDocsProc.outText = ""
      root.applyDocsResult(out, exitCode, root.docsRoot)
    }
  }

  FileView {
    id: docFile
    objectName: "docFile"
    path: root.viewMode === "document" && !root.docTooLargeFlag && root.selectedProject && root.selectedDocPath !== ""
      ? Logic.docAbsolutePath(root.selectedProject.root_path, root.selectedDocPath) : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.docError = ""; root.docText = docFile.text() }
    onLoadFailed: root.docError = "Could not read this document."
  }
```
(Use the same `reload()` idiom the Claude Memory plugin uses for `FileView`; the stub has no `reload`, so guard it in the stub: add `function reload() {}` to `tests/panel/stubs/Quickshell/Io/FileView.qml` in this task.)

Content: add the Documents list and the document view to the content `Column`, after the Board column:
```qml
          DocumentsView {
            visible: root.viewMode === "documents" && !!root.selectedProject
            width: parent.width
            docs: root.filteredDocs
            query: root.searchQuery
            cursorIndex: root.cursorIndex
            loading: root.docsLoading
            error: root.docsError
            truncated: root.docsTruncated
            scrollOnCursor: root.scrollOnCursor
            foreground: root.foreground
            dim: root.dim
            fontFamily: root.fontFamily
            onDocChosen: function(path) { root.openDoc(path) }
            onHovered: function(index) { root.hoverCursor(index) }
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          Column {
            visible: root.viewMode === "document"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: root.selectedDocPath
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            Text {
              visible: root.docTooLargeFlag || root.docError !== ""
              width: parent.width
              text: root.docTooLargeFlag ? "This document is too large to display." : root.docError
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: !root.docTooLargeFlag && root.docError === ""
              width: parent.width
              text: root.docText !== "" ? root.docText : "Loading…"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.MarkdownText
            }
          }
```
Key handling: in `keyCatcher.onMoveRequested` extend the guard so a document scrolls like a link-less card: replace `if (root.viewMode !== "entry") return` with `if (root.viewMode !== "entry" && root.viewMode !== "document") return`; the following `if (dx > 0) { root.activateCursor(); return }` must apply to `entry` only (`if (dx > 0) { if (root.viewMode === "entry") root.activateCursor(); return }`), and the link/scroll branch becomes `if (root.viewMode === "entry" && root.detailLinkList.length > 0) root.moveCursor(dy) else root.scrollBy(dy * Style.space(56))`. `onActivateRequested` stays for `entry` only. In `searchField.Keys.onPressed` the Right-at-end branch already calls `activateCursor()`, which now opens a document from the Documents list.

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/panel/run.sh` then `./run-tests.sh`
Expected: all pass, no warnings.

- [ ] **Step 5: Commit**

```bash
git add Panel.qml tests/panel
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Add the Documents section: list, viewer, and live reload" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

---

### Task 12: Documentation, manifest, and final verification

**Files:**
- Modify: `README.md`, `manifest.json`, `docs/superpowers/specs/2026-09-23-sidebar-and-documents-design.md`

**Interfaces:**
- Consumes: everything above.
- Produces: user-facing docs matching the built behaviour; the spec updated with the interface additions made during implementation.

- [ ] **Step 1: Update `README.md`**

Rewrite the feature list and add a section so it matches the built plugin: the panel is a centered 840-wide popup with a sidebar; the project dropdown (Ctrl+P), the remembered last project (`~/.local/state/brd-viewer/state.json`, `XDG_STATE_HOME` respected); sections Board (Ctrl+1) and Documents (Ctrl+2); Documents lists the project's root `README.md` plus `docs/**/*.md` (500 max, documents over 1 MB are not displayed), rendered as Markdown with live reload; **Delete project…** in the sidebar footer (same type-to-confirm and snapshot as before; remove every mention of the per-row 🗑 button and the Delete key). Add `viewer-state.py` and `list-docs.py` to the description of what the plugin runs. Keep the Install/Keybinding/Uninstall/Development sections.

- [ ] **Step 2: Update `manifest.json` descriptions**

`"description": "Browse brd's local kanban board and each project's Markdown documents, right from the bar."` and `barWidget.description`: `"One bar icon and one panel: pick a project in the sidebar, then browse its board or documents."`. Keep the JSON valid: `python3 -c "import json;json.load(open('manifest.json'))"`.

- [ ] **Step 3: Update the spec**

In `docs/superpowers/specs/2026-09-23-sidebar-and-documents-design.md`: change `Status:` to `implemented`; in the Sidebar section add the signals that were added during design of the component (`dropdownMove(int)`, `dropdownAccept()`, `dropdownCancel()`, `filterKey(var event)`) and the property `documentsEnabled`, and the read-only `filterItem`; in the Documents section note that `applyDocsResult` ignores a reply for a project other than the current one.

- [ ] **Step 4: Full verification**

Run: `./run-tests.sh`
Expected: pytest (including `test_viewer_state.py`, `test_list_docs.py`) passes; `logic.js` qmltestrunner passes; `tests/panel/run.sh` passes every file with no QML warnings.

Then a manual smoke check that needs no shell: `python3 viewer-state.py get` and `python3 list-docs.py "$PWD"` (run from the repo) print single valid JSON lines, and `python3 list-docs.py "$PWD"` lists `README.md` and this plan/spec under `docs/`. Do not run any delete.

- [ ] **Step 5: Commit**

```bash
git add README.md manifest.json docs
git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit -m "Document the sidebar, project memory, and Documents section" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa"
```

Manual live checks for the human after `omarchy-restart-shell` (not part of any task): sidebar layout at 840 wide; dropdown by mouse and keyboard; Ctrl+P / Ctrl+1 / Ctrl+2 not swallowed by Hyprland; documents render; the project you last viewed is shown after restarting the shell.

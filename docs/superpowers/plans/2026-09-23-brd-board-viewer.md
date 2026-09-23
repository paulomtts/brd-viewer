# brd Board Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `paulomtts.brd-viewer`, an Omarchy bar-widget plugin that lets a user pick any `brd`-registered project and browse its cards as a kanban Board or a dependency Tree, read-only.

**Architecture:** A single-file QML panel (`Panel.qml`), styled on the existing `paulomtts.claude-memory` plugin's projects → view → detail navigation shape, reusing that shell's shared components (`Panel`, `BarIconButton`, `KeyboardPanel`, `PanelKeyCatcher`, `CursorSurface`, `Style`, `Color`, `PanelSeparator`, `PanelSectionHeader`). All data comes from shelling out to the `brd` CLI (`brd projects`, `brd tree`) via `Process`/`StdioCollector`, never from reading SQLite directly. A pure `logic.js` module (tree indexing, search filtering, blocked-state checks) holds everything unit-testable, mirroring how the memory plugin keeps its rules out of the panel's bindings. A small Python helper, `resolve-db-path.py`, only computes a project's on-disk DB path (replicating `brd`'s own hashing) so a `FileView` can watch it and trigger refetches — it never opens the database.

**Tech Stack:** QML (Quickshell), JavaScript (`.pragma library` logic module), Python 3 (helper script + pytest), `brd` CLI (must be on `PATH`), `qmltestrunner` for QML unit tests.

**Spec:** `docs/superpowers/specs/2026-09-23-brd-board-viewer-design.md`

## Global Constraints

- Read-only: no task ever calls `brd add`/`update`/`delete`/`block`.
- No direct SQLite access anywhere. All card data comes from `brd`'s own JSON output (`brd projects`, `brd tree`). `resolve-db-path.py` computes a DB file *path* only, and never opens it.
- `brd tree` must be run with the subprocess's `workingDirectory` set to the selected project's `root_path` — `brd` resolves "which project" purely from `cwd`; there is no `--project` flag.
- One `brd tree` fetch per project selection serves both Board and Tree views; switching between them is a pure client-side re-render of the same fetched data, never a refetch.
- Board view renders only top-level cards (`parentId === null` after `indexTree` annotation) as columns' cards.
- Plugin id: `paulomtts.brd-viewer`. `manifest.json`: `kinds: ["bar-widget"]`, `entryPoints.barWidget: "Panel.qml"`, no `schema`/`defaults` (nothing to configure — `brd projects` always reads the one global registry).

## Review Focus

- A card's `blocked_by` lists an id that's since been deleted from the board (dangling reference, e.g. a non-cascading delete) — must render as "(not in this board)" rather than crash on a missing map lookup. (Task 1/2)
- An empty board (project registered but zero cards) — `indexTree([])` and downstream rendering must produce a clean empty state, not a crash on an empty array. (Task 1)
- A card whose own `status` is `"done"` while some descendant is still `"todo"` (or the reverse) — the Board progress badge must count *descendant* statuses only, never conflate them with the card's own status. (Task 1)
- `brd` missing from `PATH`, or `brd tree` exiting non-zero for a selected project (most commonly a `root_path` that no longer exists on disk) — must show inline error text, never a blank or crashed panel. (Task 4, Task 8 — manual verification, no automated harness for `Process` wiring)
- A search query that matches a deeply nested card — Tree view must keep every ancestor of that match visible (not just the match itself), while Board view keeps the matching root card visible even when the match is several levels down. (Task 2)

---

## File Structure

- `manifest.json` — plugin metadata (Task 4).
- `Panel.qml` — all UI state and view rendering (Tasks 4–8, built incrementally).
- `logic.js` — pure tree/search/blocked-state helpers, `.pragma library`, no Quickshell/QML types (Tasks 1–2).
- `resolve-db-path.py` — computes a project's brd DB path for `FileView` watching only (Task 3).
- `tests/qml/tst_logic.qml` — `qmltestrunner` suite for `logic.js` (Tasks 1–2).
- `tests/conftest.py`, `tests/test_resolve_db_path.py` — pytest suite for the Python helper (Task 3).
- `pytest.ini`, `run-tests.sh` — test runner config (Task 9).
- `README.md`, `LICENSE`, `.gitignore` — plugin packaging docs (Task 9).

---

### Task 1: `logic.js` — tree indexing and progress counts

**Files:**
- Create: `logic.js`
- Create: `tests/qml/tst_logic.qml`

**Interfaces:**
- Consumes: nothing (pure module, first task).
- Produces:
  - `Logic.indexTree(roots)` → `{ cardMap: Object<string, card>, rows: Array<{id: string, depth: int}> }`. Walks `roots` (each a card object shaped `{id, title, description, status, blocked_by, created_at, updated_at, children}` as returned by `brd tree`) depth-first, pre-order. Mutates every card object in place, adding `parentId` (`string|null`, `null` for a root card). `rows` lists every card's `id` and `depth` (root = `0`) in the same depth-first order. `cardMap` is a flat `id -> card` lookup covering every card in the whole forest.
  - `Logic.subtreeCounts(card)` → `{done: int, total: int}`. Counts every *descendant* of `card` (not `card` itself): `total` is the descendant count, `done` is how many of those have `status === "done"`.

- [ ] **Step 1: Write the failing tests**

```qml
// tests/qml/tst_logic.qml
import QtQuick
import QtTest
import "../../logic.js" as Logic

TestCase {
  name: "BrdViewerLogic"

  function makeCard(id, status, children, blockedBy) {
    return {
      id: id, title: id, description: "", status: status,
      blocked_by: blockedBy || [], created_at: "", updated_at: "",
      children: children || []
    }
  }

  function test_index_tree_on_empty_forest() {
    var result = Logic.indexTree([])
    compare(Object.keys(result.cardMap).length, 0)
    compare(result.rows.length, 0)
  }

  function test_index_tree_builds_flat_map_and_depth_first_rows() {
    var leaf = makeCard("c2", "todo")
    var mid = makeCard("c1", "todo", [leaf])
    var root = makeCard("root", "todo", [mid])
    var result = Logic.indexTree([root])

    compare(Object.keys(result.cardMap).length, 3)
    compare(result.cardMap["c2"].id, "c2")
    compare(result.rows.length, 3)
    compare(result.rows[0].id, "root")
    compare(result.rows[0].depth, 0)
    compare(result.rows[1].id, "c1")
    compare(result.rows[1].depth, 1)
    compare(result.rows[2].id, "c2")
    compare(result.rows[2].depth, 2)
  }

  function test_index_tree_annotates_parent_id() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "todo", [child])
    var result = Logic.indexTree([root])
    compare(result.cardMap["root"].parentId, null)
    compare(result.cardMap["child"].parentId, "root")
  }

  function test_index_tree_handles_multiple_roots() {
    var result = Logic.indexTree([makeCard("a", "todo"), makeCard("b", "todo")])
    compare(result.rows.length, 2)
    compare(result.cardMap["a"].parentId, null)
    compare(result.cardMap["b"].parentId, null)
  }

  function test_subtree_counts_on_childless_card() {
    var counts = Logic.subtreeCounts(makeCard("solo", "todo"))
    compare(counts.done, 0)
    compare(counts.total, 0)
  }

  // A card's own status must never be folded into its descendant count --
  // the parent here is "done" but every descendant is still "todo".
  function test_subtree_counts_ignores_own_status_counts_descendants_only() {
    var child = makeCard("child", "todo")
    var root = makeCard("root", "done", [child])
    var counts = Logic.subtreeCounts(root)
    compare(counts.done, 0)
    compare(counts.total, 1)
  }

  function test_subtree_counts_counts_nested_descendants_recursively() {
    var grandchild1 = makeCard("g1", "done")
    var grandchild2 = makeCard("g2", "todo")
    var child = makeCard("child", "in_progress", [grandchild1, grandchild2])
    var root = makeCard("root", "todo", [child])
    var counts = Logic.subtreeCounts(root)
    compare(counts.total, 3)
    compare(counts.done, 1)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml`
Expected: FAIL — `logic.js` does not exist yet (import error), or `Logic.indexTree`/`Logic.subtreeCounts` undefined.

- [ ] **Step 3: Write minimal implementation**

```js
// logic.js
.pragma library

// Card shape, as returned by `brd tree`:
// {id, title, description, status, blocked_by, created_at, updated_at, children}
// indexTree() additionally injects `parentId` onto every card it visits.

// Walks the forest depth-first, pre-order. Mutates every card in place to
// add parentId (null for a root), and returns a flat id -> card lookup
// plus the visiting order (id + depth) so a Tree view can render without
// re-walking the structure itself.
function indexTree(roots) {
  var cardMap = {}
  var rows = []

  function visit(card, parentId, depth) {
    card.parentId = parentId
    cardMap[card.id] = card
    rows.push({ id: card.id, depth: depth })
    ;(card.children || []).forEach(function(child) {
      visit(child, card.id, depth + 1)
    })
  }

  ;(roots || []).forEach(function(root) { visit(root, null, 0) })
  return { cardMap: cardMap, rows: rows }
}

// Descendant-only progress: card's own status never counts, so a "done"
// parent with still-open children doesn't read as complete.
function subtreeCounts(card) {
  var done = 0
  var total = 0

  function visit(node) {
    ;(node.children || []).forEach(function(child) {
      total += 1
      if (child.status === "done") done += 1
      visit(child)
    })
  }

  visit(card)
  return { done: done, total: total }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml`
Expected: PASS — all 7 tests green.

- [ ] **Step 5: Commit**

```bash
git add logic.js tests/qml/tst_logic.qml
git commit -m "Add logic.js tree indexing and subtree progress counts"
```

---

### Task 2: `logic.js` — search filtering and blocked-state checks

**Files:**
- Modify: `logic.js`
- Modify: `tests/qml/tst_logic.qml`

**Interfaces:**
- Consumes: `card` objects shaped as in Task 1; `cardMap` as produced by `Logic.indexTree()`.
- Produces:
  - `Logic.matchesQuery(text, query)` → `bool`. Case-insensitive substring match; an empty/whitespace-only `query` matches everything.
  - `Logic.subtreeMatches(card, query)` → `bool`. `true` if `card`'s own title matches, or any descendant's title matches. Used both for Board's root-card visibility and Tree's per-row visibility (a non-matching ancestor of a match stays visible because it "contains" that match).
  - `Logic.isBlocked(card, cardMap)` → `bool`. `true` if `card.blocked_by` is non-empty and at least one listed blocker is either missing from `cardMap` (dangling reference — treated conservatively as still blocking, since its completion can't be verified) or has `status !== "done"`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/qml/tst_logic.qml`, inside the `TestCase` block (before the final closing `}`):

```qml
  // ---- search --------------------------------------------------------

  function test_matches_query_is_case_insensitive_substring() {
    compare(Logic.matchesQuery("Write the Parser", "parser"), true)
    compare(Logic.matchesQuery("Write the Parser", "PARSER"), true)
    compare(Logic.matchesQuery("Write the Parser", "xyz"), false)
  }

  function test_matches_query_empty_query_matches_everything() {
    compare(Logic.matchesQuery("anything", ""), true)
    compare(Logic.matchesQuery("anything", "   "), true)
  }

  function test_subtree_matches_on_own_title() {
    var card = makeCard("root", "todo")
    card.title = "Fix the parser"
    compare(Logic.subtreeMatches(card, "parser"), true)
    compare(Logic.subtreeMatches(card, "nope"), false)
  }

  // Keeping ancestors of a match visible: a non-matching root whose
  // grandchild matches must still report true.
  function test_subtree_matches_true_for_ancestor_of_a_nested_match() {
    var grandchild = makeCard("g", "todo")
    grandchild.title = "Deep task about parsers"
    var child = makeCard("c", "todo", [grandchild])
    child.title = "Middle"
    var root = makeCard("root", "todo", [child])
    root.title = "Top"
    compare(Logic.subtreeMatches(root, "parsers"), true)
    compare(Logic.subtreeMatches(child, "parsers"), true)
  }

  function test_subtree_matches_false_when_nothing_in_subtree_matches() {
    var child = makeCard("c", "todo")
    child.title = "Unrelated"
    var root = makeCard("root", "todo", [child])
    root.title = "Also unrelated"
    compare(Logic.subtreeMatches(root, "parsers"), false)
  }

  // ---- blocked state ---------------------------------------------------

  function test_is_blocked_false_with_no_blockers() {
    var card = makeCard("c", "todo", [], [])
    compare(Logic.isBlocked(card, {}), false)
  }

  function test_is_blocked_true_when_a_blocker_is_not_done() {
    var blocker = makeCard("b1", "in_progress")
    var card = makeCard("c", "todo", [], ["b1"])
    var map = Logic.indexTree([blocker]).cardMap
    compare(Logic.isBlocked(card, map), true)
  }

  function test_is_blocked_false_when_every_blocker_is_done() {
    var blocker = makeCard("b1", "done")
    var card = makeCard("c", "todo", [], ["b1"])
    var map = Logic.indexTree([blocker]).cardMap
    compare(Logic.isBlocked(card, map), false)
  }

  // Dangling blocked_by reference (blocker deleted from the board):
  // treated as still-blocking, not silently ignored.
  function test_is_blocked_true_when_a_blocker_id_is_missing_from_the_map() {
    var card = makeCard("c", "todo", [], ["ghost"])
    compare(Logic.isBlocked(card, {}), true)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml`
Expected: FAIL — `Logic.matchesQuery`/`subtreeMatches`/`isBlocked` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `logic.js`:

```js
function matchesQuery(text, query) {
  var q = String(query || "").trim().toLowerCase()
  return q === "" || String(text || "").toLowerCase().indexOf(q) >= 0
}

// True if `card` itself matches, or any descendant does -- so an ancestor
// of a match stays visible even though it doesn't match on its own title.
function subtreeMatches(card, query) {
  if (matchesQuery(card.title, query)) return true
  return (card.children || []).some(function(child) { return subtreeMatches(child, query) })
}

// A missing blocker (id not in cardMap -- e.g. deleted without --cascade
// cleaning up the reference) is treated as still-blocking: its completion
// can't be verified, so it's conservatively not "done".
function isBlocked(card, cardMap) {
  return (card.blocked_by || []).some(function(id) {
    var blocker = cardMap[id]
    return !blocker || blocker.status !== "done"
  })
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml`
Expected: PASS — all tests green (7 from Task 1 + 9 new).

- [ ] **Step 5: Commit**

```bash
git add logic.js tests/qml/tst_logic.qml
git commit -m "Add logic.js search filtering and blocked-state checks"
```

---

### Task 3: `resolve-db-path.py`

**Files:**
- Create: `resolve-db-path.py`
- Create: `tests/conftest.py`
- Create: `tests/test_resolve_db_path.py`
- Create: `pytest.ini`

**Interfaces:**
- Consumes: nothing (standalone script).
- Produces: a CLI contract Task 8 relies on — `python3 resolve-db-path.py <root_path>` prints exactly one line (the absolute DB path) and exits `0` on success; prints nothing and exits non-zero (`1`) if `root_path` is missing/empty, or if neither `$XDG_DATA_HOME` nor `$HOME` is set.

- [ ] **Step 1: Write `pytest.ini` and the test fixtures**

```ini
# pytest.ini
[pytest]
testpaths = tests
```

```python
# tests/conftest.py
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
```

- [ ] **Step 2: Write the failing tests**

```python
# tests/test_resolve_db_path.py
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `python3 -m pytest tests/test_resolve_db_path.py -v`
Expected: FAIL — `resolve-db-path.py` does not exist yet (all invocations error/exit non-zero with no matching output).

- [ ] **Step 4: Write minimal implementation**

```python
#!/usr/bin/env python3
"""Print the on-disk path of a brd project's SQLite database, without
touching it.

Replicates brd's own paths.project_db_path() hashing -- sha256 of the
project's resolved absolute path -- purely so Panel.qml can watch that
path for changes and know when to re-fetch `brd tree`. This script never
opens or reads the database; see brd/src/brd/paths.py for the original.
"""
import hashlib
import os
import sys
from pathlib import Path


def project_db_path(root_path):
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        base = Path(xdg)
    elif os.environ.get("HOME"):
        base = Path(os.environ["HOME"]) / ".local" / "share"
    else:
        return None
    digest = hashlib.sha256(str(Path(root_path).resolve()).encode()).hexdigest()
    return base / "brd" / "projects" / f"{digest}.db"


def main():
    if len(sys.argv) != 2 or sys.argv[1] == "":
        return 1
    path = project_db_path(sys.argv[1])
    if path is None:
        return 1
    print(str(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `python3 -m pytest tests/test_resolve_db_path.py -v`
Expected: PASS — all 6 tests green.

- [ ] **Step 6: Commit**

```bash
git add resolve-db-path.py tests/conftest.py tests/test_resolve_db_path.py pytest.ini
git commit -m "Add resolve-db-path.py for watching a brd project's DB file"
```

---

### Task 4: Plugin scaffold and Projects view

**Files:**
- Create: `manifest.json`
- Create: `Panel.qml`

**Interfaces:**
- Consumes: nothing new (Projects view doesn't need `logic.js` yet — that starts in Task 5).
- Produces: `root.viewMode` (`"projects" | "board" | "tree" | "entry"`, starts at `"projects"`), `root.projects` (`Array<{root_path: string, name: string}>`), `root.selectedProject` (`{root_path: string, name: string}|null`) — later tasks read this to know which project's board is loaded, `root.loadError` (`string`) — later tasks reuse this same property for their own load failures.

- [ ] **Step 1: Write `manifest.json`**

```json
{
  "schemaVersion": 1,
  "id": "paulomtts.brd-viewer",
  "name": "brd Viewer",
  "version": "1.0.0",
  "author": "paulomtts",
  "license": "MIT",
  "description": "Browse brd's local kanban board per project, as a Board or a Tree, right from the bar.",
  "kinds": ["bar-widget"],
  "activation": "on-demand",
  "entryPoints": {
    "barWidget": "Panel.qml"
  },
  "barWidget": {
    "displayName": "brd Viewer",
    "description": "One bar icon and one panel: pick a project, view its board or tree.",
    "category": "Productivity",
    "aliases": ["brd", "brd-viewer", "board"],
    "allowMultiple": false
  }
}
```

- [ ] **Step 2: Write the Projects-view `Panel.qml` skeleton**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "logic.js" as Logic

// Browses brd's local kanban board (`brd projects` / `brd tree`), per
// project: pick a project, then view its cards as a Board or a Tree.
// Read-only -- nothing here ever calls brd add/update/delete/block.
Panel {
  id: root
  moduleName: "paulomtts.brd-viewer"
  ipcTarget: "paulomtts.brd-viewer"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  property string viewMode: "projects" // "projects" | "board" | "tree" | "entry"
  property var projects: []            // [{ root_path, name }]
  property var selectedProject: null   // { root_path, name } | null
  property string loadError: ""

  property string searchQuery: ""
  property int cursorIndex: 0

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  readonly property var filteredProjects: root.projects.filter(function(p) {
    return Logic.matchesQuery(p.name, root.searchQuery)
  })

  function currentList() {
    if (root.viewMode === "projects") return root.filteredProjects
    return []
  }

  function focusForView() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (searchField) searchField.forceActiveFocus()
    })
  }

  function resetSearch() {
    searchQuery = ""
    cursorIndex = 0
  }

  function moveCursor(delta) {
    var list = root.currentList()
    if (list.length === 0) return
    root.cursorIndex = root.clamp(root.cursorIndex + delta, 0, list.length - 1)
  }

  function hoverCursor(index) {
    root.cursorIndex = index
  }

  function activateCursor() {
    var list = root.currentList()
    if (root.cursorIndex < 0 || root.cursorIndex >= list.length) return
    if (root.viewMode === "projects") root.selectProject(list[root.cursorIndex])
  }

  function refreshProjects() {
    loadError = ""
    listProc.running = false
    listProc.running = true
  }

  function openProjects() {
    viewMode = "projects"
    selectedProject = null
    resetSearch()
    refreshProjects()
    focusForView()
  }

  function selectProject(project) {
    selectedProject = project
    resetSearch()
    // Task 5 wires the brd tree fetch and switches viewMode to "board".
  }

  function goBack() {
    openProjects()
  }

  onOpenedChanged: if (opened) openProjects()

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.openProjects(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🗂️"
    onPressed: function(buttonCode) { root.toggle() }
  }

  // `brd projects` reads the global registry directly -- no cwd
  // dependency, unlike `brd tree` in Task 5.
  Process {
    id: listProc
    command: ["brd", "projects"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          root.projects = (parsed.data || []).map(function(p) {
            return { root_path: p.root_path, name: p.name }
          }).sort(function(a, b) { return a.name.localeCompare(b.name) })
        } catch (e) {
          root.loadError = "Could not parse brd's project list."
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.projects.length === 0)
        root.loadError = "Could not list brd projects (is brd installed and on PATH?)."
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          RowLayout {
            width: parent.width
            spacing: Style.spacing.md

            Text {
              Layout.fillWidth: true
              text: "brd Viewer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideMiddle
            }
          }

          TextField {
            id: searchField
            visible: root.viewMode === "projects"
            width: parent.width
            foreground: root.foreground
            placeholderText: "Search projects…"
            text: root.searchQuery

            onTextChanged: {
              root.searchQuery = text
              root.cursorIndex = 0
            }

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.searchQuery !== "") { root.searchQuery = "" }
                else root.close()
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_Down) { root.moveCursor(1); event.accepted = true; return }
              if (event.key === Qt.Key_Up) { root.moveCursor(-1); event.accepted = true; return }
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activateCursor(); event.accepted = true; return
              }
              if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
                event.accepted = true
                return
              }
            }
          }

          Text {
            visible: root.loadError !== ""
            width: parent.width
            text: root.loadError
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.viewMode === "projects"
            width: parent.width
            spacing: Style.space(6)

            Text {
              visible: root.projects.length === 0 && root.loadError === ""
              width: parent.width
              text: "No projects registered with brd."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.projects.length > 0 && root.filteredProjects.length === 0
              width: parent.width
              text: "No projects match “" + root.searchQuery + "”."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              id: projectsRepeater
              model: root.filteredProjects

              ProjectRow {
                required property var modelData
                required property int index
                width: parent.width
                rowIndex: index
                label: modelData.name
                onActivated: root.selectProject(modelData)
              }
            }
          }
        }
      }
    }
  }

  component ProjectRow: CursorSurface {
    id: projectRow
    property int rowIndex: 0
    property string label: ""
    signal activated()

    hasCursor: root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: projectRowLayout.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: projectRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)

      Text {
        Layout.fillWidth: true
        text: projectRow.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hoverCursor(projectRow.rowIndex)
      onClicked: projectRow.activated()
    }
  }
}
```

- [ ] **Step 3: Manual verification (no automated harness for Process/panel wiring — matches the existing memory plugin's own testing boundary)**

1. Register at least two test projects: `cd /tmp && mkdir -p brdv-a brdv-b && (cd brdv-a && brd init) && (cd brdv-b && brd init)`.
2. Symlink the plugin into place: `ln -s "$(pwd)" ~/.config/omarchy/plugins/paulomtts.brd-viewer` (from the repo root).
3. Rescan and enable: `omarchy-shell shell rescanPlugins && omarchy plugin enable paulomtts.brd-viewer`.
4. Click the 🗂️ bar icon. Confirm the panel opens showing "brd Viewer" and both `brdv-a`/`brdv-b` (plus any other already-registered projects) sorted by name.
5. Type into the search field; confirm the list filters live and the "No projects match…" message appears for a query with no hits.
6. Use Up/Down to move the highlighted row, Enter to activate (no-op for now — Task 5 wires the next view); confirm the highlight follows both keyboard and mouse hover.
7. Temporarily rename `brd` off `PATH` (e.g. `PATH=/usr/bin omarchy-shell ...` in a scratch shell) and reopen the panel; confirm the "Could not list brd projects…" message appears instead of a blank list.
8. Clean up: `brd forget /tmp/brdv-a && brd forget /tmp/brdv-b && rm -rf /tmp/brdv-a /tmp/brdv-b`.

- [ ] **Step 4: Commit**

```bash
git add manifest.json Panel.qml
git commit -m "Add plugin scaffold and Projects view"
```

---

### Task 5: `brd tree` fetch and Board view

**Files:**
- Modify: `Panel.qml`

**Interfaces:**
- Consumes: `Logic.indexTree(roots)`, `Logic.subtreeCounts(card)`, `Logic.subtreeMatches(card, query)` (Task 1–2); `root.selectedProject`, `root.viewMode`, `root.loadError`, `root.searchQuery`, `Logic.matchesQuery` (Task 4).
- Produces: `root.cardRoots` (`Array<card>`, the raw top-level nodes from the last successful `brd tree` fetch), `root.cardMap` (`Object<string, card>`, from `Logic.indexTree`), `root.treeRows` (`Array<{id, depth}>`, from `Logic.indexTree`, consumed by Task 6), `root.fetchBoard()` (re-runs `brd tree` for `root.selectedProject` — also called by Task 8's refresh button/live-watch), `root.openCard(id)` (function later tasks — Task 7 — call to enter card detail; stubbed here as a no-op comment marker since detail doesn't exist until Task 7).

- [ ] **Step 1: Wire the fetch and Board rendering**

Replace `selectProject()` and add the fetch/Board pieces in `Panel.qml`:

```qml
  property var cardRoots: []   // top-level cards from the last brd tree fetch
  property var cardMap: ({})   // id -> card, from Logic.indexTree
  property var treeRows: []    // [{id, depth}], from Logic.indexTree
  readonly property var statuses: ["todo", "in_progress", "done"]

  function selectProject(project) {
    selectedProject = project
    resetSearch()
    viewMode = "board"
    fetchBoard()
    focusForView()
  }

  function fetchBoard() {
    if (!root.selectedProject) return
    loadError = ""
    treeProc.workingDirectory = root.selectedProject.root_path
    treeProc.running = false
    treeProc.running = true
  }

  function applyTreeData(roots) {
    root.cardRoots = roots
    var indexed = Logic.indexTree(roots)
    root.cardMap = indexed.cardMap
    root.treeRows = indexed.rows
  }

  readonly property var visibleBoardRoots: root.cardRoots.filter(function(c) {
    return Logic.subtreeMatches(c, root.searchQuery)
  })

  function boardColumn(status) {
    return root.visibleBoardRoots.filter(function(c) { return c.status === status })
  }

  function statusLabel(status) {
    if (status === "todo") return "Todo"
    if (status === "in_progress") return "In Progress"
    return "Done"
  }

  function openCard(id) {
    // Task 7 implements card detail; this is the single entry point every
    // Board/Tree row calls, so Task 7 only has to fill this function in.
  }
```

```qml
  Process {
    id: treeProc
    command: ["brd", "tree"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          root.applyTreeData(parsed.data || [])
        } catch (e) {
          root.loadError = "Could not load the board for this project."
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.applyTreeData([])
        root.loadError = "Could not load the board for this project."
      }
    }
  }
```

Add the Board column UI inside `column` (after the Projects `Column`, guarded by `root.viewMode === "board"`), and update the header row and search field's `visible`/`placeholderText` bindings to cover `"board"`/`"tree"` too:

```qml
          RowLayout {
            width: parent.width
            spacing: Style.spacing.md

            Text {
              visible: root.viewMode !== "projects"
              text: "‹ Back"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.goBack() }
            }

            Text {
              Layout.fillWidth: true
              text: root.viewMode === "projects" ? "brd Viewer"
                : root.selectedProject ? root.selectedProject.name : "brd Viewer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideMiddle
            }

            Button {
              visible: root.viewMode === "board" || root.viewMode === "tree"
              text: root.viewMode === "board" ? "Tree ›" : "‹ Board"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.viewMode = (root.viewMode === "board" ? "tree" : "board")
            }
          }
```

```qml
          TextField {
            id: searchField
            visible: root.viewMode === "projects" || root.viewMode === "board" || root.viewMode === "tree"
            width: parent.width
            foreground: root.foreground
            placeholderText: root.viewMode === "projects" ? "Search projects…" : "Search cards…"
            text: root.searchQuery
            // (onTextChanged / Keys.onPressed unchanged from Task 4)
          }
```

```qml
          Column {
            visible: root.viewMode === "board"
            width: parent.width
            spacing: Style.space(10)

            Text {
              visible: root.cardRoots.length === 0 && root.loadError === ""
              width: parent.width
              text: "This project's board is empty."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.statuses

              Column {
                required property string modelData
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: root.statusLabel(modelData) + " (" + root.boardColumn(modelData).length + ")"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: root.boardColumn(modelData)

                  BoardCard {
                    required property var modelData
                    width: parent.width
                    title: modelData.title
                    progress: Logic.subtreeCounts(modelData)
                    onActivated: root.openCard(modelData.id)
                  }
                }
              }
            }
          }
```

```qml
  component BoardCard: Rectangle {
    id: boardCard
    property string title: ""
    property var progress: ({ done: 0, total: 0 })
    signal activated()

    color: "transparent"
    border.color: Qt.darker(root.foreground, 2.0)
    border.width: 1
    radius: Style.space(4)
    implicitHeight: cardLayout.implicitHeight + Style.space(16)

    ColumnLayout {
      id: cardLayout
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(4)

      Text {
        Layout.fillWidth: true
        text: boardCard.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Text {
        visible: boardCard.progress.total > 0
        text: boardCard.progress.done + "/" + boardCard.progress.total + " done"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: boardCard.activated()
    }
  }
```

- [ ] **Step 2: Manual verification**

1. In `/tmp/brdv-a` (re-created if cleaned up in Task 4): `brd init`, then `brd add --title "Story A"`, capture its id, `brd add --title "Subtask A1" --parent <id-of-Story-A>` (if `brd add` supports `--parent`; otherwise use `brd update <subtask-id> --parent <id>` after creating both as top-level, per `brd --help`), and `brd update <id-of-Story-A> --status in_progress`.
2. Reopen the panel, select the project; confirm it lands on Board view with "Story A" showing in the "In Progress" column with a "0/1 done" (or similar) badge reflecting its one subtask.
3. Confirm the empty-board message appears for a freshly-`brd init`'d project with zero cards.
4. Type a search query matching only a nested subtask's title; confirm its root card ("Story A") stays visible in Board view.
5. Click the "Tree ›" toggle button; confirm `viewMode` becomes `"tree"` (Task 6 renders it; for now, confirm no crash and the Board `Column`'s `visible` correctly turns off).
6. Point `selectedProject.root_path` at a directory that doesn't exist (temporarily rename it) and reselect; confirm "Could not load the board for this project." appears instead of a stale/blank board.

- [ ] **Step 3: Commit**

```bash
git add Panel.qml
git commit -m "Add brd tree fetch and Board view"
```

---

### Task 6: Tree view

**Files:**
- Modify: `Panel.qml`

**Interfaces:**
- Consumes: `root.treeRows`, `root.cardMap` (Task 5); `Logic.subtreeMatches`, `Logic.isBlocked` (Task 1–2); `root.openCard` (Task 5, filled in by Task 7).
- Produces: `root.visibleTreeRows` (`Array<{id, depth}>`, filtered by search) — read by Task 8's refresh logic to know whether the current selection is still visible after a refetch.

- [ ] **Step 1: Wire Tree rendering and its own keyboard cursor**

`currentList()` needs a Tree branch so the shared Up/Down/Enter handling in the search field covers it too:

```qml
  function currentList() {
    if (root.viewMode === "projects") return root.filteredProjects
    if (root.viewMode === "tree") return root.visibleTreeRows
    return []
  }

  readonly property var visibleTreeRows: root.treeRows.filter(function(row) {
    return Logic.subtreeMatches(root.cardMap[row.id], root.searchQuery)
  })

  function activateCursor() {
    var list = root.currentList()
    if (root.cursorIndex < 0 || root.cursorIndex >= list.length) return
    if (root.viewMode === "projects") root.selectProject(list[root.cursorIndex])
    else if (root.viewMode === "tree") root.openCard(list[root.cursorIndex].id)
  }
```

Reset `cursorIndex` to `0` whenever `viewMode` changes to `"tree"` (the toggle button from Task 5):

```qml
            Button {
              visible: root.viewMode === "board" || root.viewMode === "tree"
              text: root.viewMode === "board" ? "Tree ›" : "‹ Board"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                root.viewMode = (root.viewMode === "board" ? "tree" : "board")
                root.cursorIndex = 0
              }
            }
```

Add the Tree `Column` after the Board `Column`:

```qml
          Column {
            visible: root.viewMode === "tree"
            width: parent.width
            spacing: Style.space(2)

            Text {
              visible: root.treeRows.length === 0 && root.loadError === ""
              width: parent.width
              text: "This project's board is empty."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.treeRows.length > 0 && root.visibleTreeRows.length === 0
              width: parent.width
              text: "No cards match “" + root.searchQuery + "”."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              id: treeRepeater
              model: root.visibleTreeRows

              TreeRow {
                required property var modelData
                required property int index
                width: parent.width
                rowIndex: index
                depth: modelData.depth
                card: root.cardMap[modelData.id]
                blocked: Logic.isBlocked(root.cardMap[modelData.id], root.cardMap)
                onActivated: root.openCard(modelData.id)
              }
            }
          }
```

```qml
  component TreeRow: CursorSurface {
    id: treeRow
    property int rowIndex: 0
    property int depth: 0
    property var card: null
    property bool blocked: false
    signal activated()

    hasCursor: root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: treeRowLayout.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: treeRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10) + treeRow.depth * Style.space(16)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Text {
        visible: treeRow.blocked
        text: "⛔"
        font.pixelSize: Style.font.body
      }

      Text {
        Layout.fillWidth: true
        text: treeRow.card ? treeRow.card.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: treeRow.card ? "[" + treeRow.card.status + "]" : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hoverCursor(treeRow.rowIndex)
      onClicked: treeRow.activated()
    }
  }
```

- [ ] **Step 2: Manual verification**

1. With the same `/tmp/brdv-a` project from Task 5 (Story A → Subtask A1), open the panel, select the project, click "Tree ›".
2. Confirm "Story A" and "Subtask A1" both render, with "Subtask A1" indented one level under "Story A", each showing its status.
3. Add a second subtask, `brd add --title "Subtask A2" --blocked-by <id-of-A1>` (or `--parent`, per whatever `brd add --help` shows for blocking — see `brd add --help` output first), refresh (click "‹ Board" then "Tree ›" again to force a fresh fetch via `selectProject`, or wait for Task 8's live refresh), confirm "Subtask A2" shows a ⛔ marker while A1 isn't done, and the marker disappears after `brd update <A1-id> --status done`.
4. Use Up/Down/Enter on the Tree rows; confirm the keyboard cursor and mouse-hover highlight agree, and Enter on a row is a no-op for now (Task 7 wires it).
5. Type a search query matching only "Subtask A1"; confirm "Story A" (its ancestor) stays visible and any unrelated sibling row disappears.

- [ ] **Step 3: Commit**

```bash
git add Panel.qml
git commit -m "Add Tree view"
```

---

### Task 7: Card detail view

**Files:**
- Modify: `Panel.qml`

**Interfaces:**
- Consumes: `root.cardMap`, `root.openCard(id)` stub (Task 5); `root.viewMode` (Task 4).
- Produces: `root.selectedCardId` (`string`, the card currently shown in detail), `root.detailReturnView` (`"board"|"tree"`, remembers which view to return to on Back).

- [ ] **Step 1: Fill in `openCard()` and add the detail view**

```qml
  property string selectedCardId: ""
  property string detailReturnView: "board"

  function openCard(id) {
    if (!root.cardMap[id]) return
    if (root.viewMode === "board" || root.viewMode === "tree") root.detailReturnView = root.viewMode
    selectedCardId = id
    viewMode = "entry"
    focusForView()
  }
```

`goBack()` must return to `detailReturnView` from detail, and to Projects from Board/Tree (already true today, but now needs the extra branch):

```qml
  function goBack() {
    if (viewMode === "entry") { viewMode = root.detailReturnView; return }
    openProjects()
  }
```

Add a resolver used by the detail view for blocked-by/children rows, and the detail `Column`:

```qml
  function resolvedCard(id) {
    var card = root.cardMap[id]
    return card ? { id: id, title: card.title, status: card.status, inBoard: true }
                : { id: id, title: id, status: "", inBoard: false }
  }
```

```qml
          Column {
            id: detailCard
            visible: root.viewMode === "entry" && root.cardMap[root.selectedCardId]
            width: parent.width
            spacing: Style.space(10)

            readonly property var card: root.cardMap[root.selectedCardId]

            Text {
              visible: detailCard.card && detailCard.card.parentId
              text: "↑ " + (detailCard.card && detailCard.card.parentId ? root.resolvedCard(detailCard.card.parentId).title : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openCard(detailCard.card.parentId)
              }
            }

            Text {
              width: parent.width
              text: detailCard.card ? detailCard.card.title : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              text: detailCard.card ? "[" + detailCard.card.status + "]" : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            PanelSeparator { foreground: root.foreground }

            Text {
              width: parent.width
              text: (detailCard.card && detailCard.card.description) ? detailCard.card.description : "No description."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.MarkdownText
            }

            PanelSectionHeader {
              visible: detailCard.card && detailCard.card.blocked_by && detailCard.card.blocked_by.length > 0
              text: "BLOCKED BY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: (detailCard.card && detailCard.card.blocked_by) ? detailCard.card.blocked_by : []

              DetailLink {
                required property string modelData
                width: parent.width
                resolved: root.resolvedCard(modelData)
                onActivated: resolved.inBoard ? root.openCard(modelData) : undefined
              }
            }

            PanelSectionHeader {
              visible: detailCard.card && detailCard.card.children && detailCard.card.children.length > 0
              text: "CHILDREN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: (detailCard.card && detailCard.card.children) ? detailCard.card.children : []

              DetailLink {
                required property var modelData
                width: parent.width
                resolved: root.resolvedCard(modelData.id)
                onActivated: root.openCard(modelData.id)
              }
            }
          }
```

```qml
  component DetailLink: RowLayout {
    property var resolved: ({ title: "", status: "", inBoard: true })
    signal activated()

    Text {
      Layout.fillWidth: true
      text: resolved.title + (resolved.inBoard ? "" : " (not in this board)")
      color: resolved.inBoard ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      visible: resolved.inBoard
      text: "[" + resolved.status + "]"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: resolved.inBoard ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: parent.activated()
    }
  }
```

- [ ] **Step 2: Manual verification**

1. From Tree view (Task 6's `/tmp/brdv-a` setup), click "Subtask A2" (the one `--blocked-by A1`); confirm the detail view shows its title, status, description ("No description." if none was set), and a "BLOCKED BY" section listing "Subtask A1" with its status, clickable.
2. Click "Subtask A1" from that list; confirm it navigates to A1's detail, showing a parent breadcrumb ("↑ Story A") if A1 has a parent, and a "CHILDREN" section if applicable.
3. Click the breadcrumb; confirm it jumps to "Story A"'s detail, showing a "CHILDREN" section listing both subtasks.
4. Click Back; confirm it returns to whichever of Board/Tree was active before entering detail (test both: enter detail from Board once, from Tree once).
5. `brd update <A1-id> --blocked-by <some-id-you-then-delete-with-cascade>` is awkward to stage directly (brd may not expose removing a specific blocker easily) — instead, manually verify the dangling-reference path by inspecting `root.resolvedCard()`'s behavior: temporarily add a card, note its id, `brd delete <id>` it, then if any other card still lists it in `blocked_by`, confirm that entry renders as "(not in this board)" rather than crashing the panel.

- [ ] **Step 3: Commit**

```bash
git add Panel.qml
git commit -m "Add card detail view"
```

---

### Task 8: Live refresh and remaining error handling

**Files:**
- Modify: `Panel.qml`

**Interfaces:**
- Consumes: `resolve-db-path.py` (Task 3), `root.fetchBoard()` (Task 5).
- Produces: nothing consumed by a later task (final feature task).

- [ ] **Step 1: Wire the DB-path resolver and watch it**

```qml
  property string watchedDbPath: ""

  Process {
    id: resolveDbPathProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        root.watchedDbPath = path
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.watchedDbPath = ""
    }
  }
```

Extend `fetchBoard()` to also (re-)resolve the watch path whenever a project is (re)selected — not on every refetch, only when `selectedProject` changes, since the path is stable for a given project:

```qml
  function selectProject(project) {
    selectedProject = project
    resetSearch()
    viewMode = "board"
    resolveDbPathProc.command = ["python3", root.pluginDir + "resolve-db-path.py", project.root_path]
    resolveDbPathProc.running = false
    resolveDbPathProc.running = true
    fetchBoard()
    focusForView()
  }
```

Add the watcher and the manual-refresh button:

```qml
  FileView {
    id: dbFile
    path: root.watchedDbPath !== "" ? root.watchedDbPath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: root.fetchBoard()
  }
```

```qml
            Text {
              visible: root.viewMode === "board" || root.viewMode === "tree"
              text: "⟳"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.fetchBoard() }
            }
```

(Place this `Text` in the same header `RowLayout` as the Board/Tree toggle button from Task 5, before it.)

`fetchBoard()` also needs to gracefully preserve the current selection where possible — after a refetch, if `root.selectedCardId` is still a key in the freshly rebuilt `root.cardMap`, stay on the detail view; otherwise fall back to `detailReturnView`:

```qml
  function fetchBoard() {
    if (!root.selectedProject) return
    loadError = ""
    treeProc.workingDirectory = root.selectedProject.root_path
    treeProc.running = false
    treeProc.running = true
  }
```

Update `applyTreeData()` (from Task 5) to run this reconciliation after every fetch:

```qml
  function applyTreeData(roots) {
    root.cardRoots = roots
    var indexed = Logic.indexTree(roots)
    root.cardMap = indexed.cardMap
    root.treeRows = indexed.rows
    if (root.viewMode === "entry" && !root.cardMap[root.selectedCardId])
      root.viewMode = root.detailReturnView
  }
```

- [ ] **Step 2: Manual verification**

1. Reopen the panel on `/tmp/brdv-a`, land on Board view. In a separate terminal, `cd /tmp/brdv-a && brd update <Story-A-id> --status done`. Confirm the panel's Board view updates within a couple seconds without any manual action (the DB file watch firing `fetchBoard()`).
2. Click the ⟳ refresh icon immediately after a `brd update` from a terminal; confirm it updates at least as fast as the watcher (sanity check that manual refresh still works independently).
3. While viewing a card's detail, run `brd delete <that-card-id> --cascade` from a terminal; confirm the panel falls back to Board/Tree (whichever was active before) rather than showing a detail view for a card that no longer exists.
4. Rename `/tmp/brdv-a` to `/tmp/brdv-a-moved` on disk (without telling brd), then click the ⟳ refresh; confirm "Could not load the board for this project." appears (the `brd tree` subprocess's `workingDirectory` no longer exists) rather than a stale board or a crash. Rename it back and refresh again to confirm recovery.
5. Confirm a project whose `resolve-db-path.py` run fails (e.g. temporarily `unset HOME` isn't practical mid-session — instead, verify by reading the code path: `resolveDbPathProc`'s `onExited` sets `watchedDbPath = ""`, and `FileView.path: ""` is a no-op, so this degrades to "manual refresh only" without visible error — confirm no error text appears in this case, per spec).

- [ ] **Step 3: Commit**

```bash
git add Panel.qml
git commit -m "Add live refresh via DB-path watching and manual refresh"
```

---

### Task 9: Packaging and docs

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `run-tests.sh`

**Interfaces:**
- Consumes: nothing (documentation/tooling only).
- Produces: nothing (final task).

- [ ] **Step 1: Write `run-tests.sh`**

```bash
#!/usr/bin/env bash
# Both suites: pytest for resolve-db-path.py, Qt's own qmltestrunner for
# logic.js (the panel's rules, on the same engine the panel runs on).
set -euo pipefail
cd "$(dirname "$0")"

python3 -m pytest tests

qmltestrunner=$(command -v /usr/lib/qt6/bin/qmltestrunner || command -v qmltestrunner)
QT_QPA_PLATFORM=offscreen "$qmltestrunner" -input tests/qml
```

```bash
chmod +x run-tests.sh
```

- [ ] **Step 2: Run the full suite once to confirm both pass together**

Run: `./run-tests.sh`
Expected: PASS — pytest (6 tests) and qmltestrunner (16 tests) both green.

- [ ] **Step 3: Write `.gitignore`**

```
__pycache__/
*.pyc
.pytest_cache/
```

- [ ] **Step 4: Write `LICENSE`**

Use the MIT license text (matches `manifest.json`'s `"license": "MIT"`), with the copyright line `Copyright (c) 2026 paulomtts`.

- [ ] **Step 5: Write `README.md`**

```markdown
# omarchy-brd-viewer

An [Omarchy](https://omarchy.org/) shell plugin that visualizes a
[`brd`](https://github.com/paulomtts/brd) project's board — its cards,
their kanban status, and their dependency/hierarchy structure — read-only,
right from the bar.

## Features

- **Projects list** — every project `brd` already has registered
  (`brd projects`), searchable.
- **Board view** — top-level cards in three columns (Todo / In Progress /
  Done), each showing a done/total progress badge for its subtasks.
- **Tree view** — the full nested hierarchy, indented, with a ⛔ marker on
  any card still blocked by an unfinished dependency.
- **Card detail** — full description, parent breadcrumb, and clickable
  blocked-by/children lists, resolving ids to titles.
- **Live refresh** — watches the selected project's `brd` database file
  and re-fetches automatically when it changes on disk (e.g. an agent
  updates the board while the panel is open), plus a manual refresh
  button.
- Full keyboard navigation in Projects and Tree views (Up/Down/Enter,
  Escape, Tab to switch bar panels); Board view is mouse-first.
- Entirely read-only: no card is ever created, edited, or deleted from
  the panel.

## Install

```bash
git clone https://github.com/paulomtts/omarchy-brd-viewer.git \
  ~/.config/omarchy/plugins/paulomtts.brd-viewer
omarchy-shell shell rescanPlugins
omarchy plugin enable paulomtts.brd-viewer
```

Requires `brd` on `PATH`. See <https://github.com/paulomtts/brd>.

## Uninstall

```bash
omarchy plugin disable paulomtts.brd-viewer
rm -rf ~/.config/omarchy/plugins/paulomtts.brd-viewer
```

## Development

```bash
./run-tests.sh
```

See `docs/superpowers/specs/2026-09-23-brd-board-viewer-design.md` for
the full design.
```

- [ ] **Step 6: Commit**

```bash
git add README.md LICENSE .gitignore run-tests.sh
git commit -m "Add README, LICENSE, .gitignore, and run-tests.sh"
```

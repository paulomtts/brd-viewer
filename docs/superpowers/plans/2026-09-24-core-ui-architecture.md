# Core / UI Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the plugin into a `core/` (domain rules, Python backends, non-visual stores) and a `ui/` (shell, screens, components) with an enforced one-way dependency rule and no duplicated helpers, without changing behaviour.

**Architecture:** One `App` object composes non-visual stores (`core/stores`) that own state and call the Python helpers through a shared `HelperRunner`; `ui/Panel.qml` creates `App` and hands it to screens built from shared components. Pure rules live in `core/domain/*.js`; shared Python code in `core/backend/common`. An architecture test enforces the layer rule, the shell-type name-clash list and the no-duplicate-helper check.

**Tech Stack:** QML (Qt 6, Quickshell, Quickshell.Io), `.pragma library` JavaScript, Python 3, pytest, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-09-24-core-ui-architecture-design.md` (read it first; this plan implements it, and where the two differ the spec wins).

## Global Constraints

- **No behaviour change.** No user-visible change; helper scripts keep their exact JSON contracts; plugin id `paulomtts.omarchy-project-manager`, data folders, shortcuts and labels unchanged.
- **Green at every commit, checked by exit code.** `bash tests/run.sh` (after Task 1; `./run-tests.sh` before) must exit 0. Never judge a run by grepping filtered output: read the exit status (`echo $?`) and the `FAIL`/warning lines. (An earlier mistake: a suite exiting 1 was missed because output was filtered.)
- **No shims, no re-exports, no compatibility aliases.** When a thing moves, every caller is updated in the same commit.
- **Keep member names verbatim when moving state out of `Panel.qml`** (`memoryEditing` stays `memoryEditing`, now on the store). Renames are out of scope.
- **Commits:** `git -c user.name="Paulo" -c user.email="93949169+paulomtts@users.noreply.github.com" commit` with trailers `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01SeNkLbHVkWcK9KVEzjeoFa`. Verify identity with `git log -1 --format='%an <%ae>'` before any push. Never push in this plan; the branch is `refactor/core-ui`.
- **QML pitfalls (all bit us before):** property names cannot start uppercase; `Layout.ignore` does not exist in Qt 6; a `MouseArea` directly inside a Layout warns; a `TestCase` needs `visible: true` for mouse tests; `\\n` in a QML string is a literal backslash-n; a Flickable's `children` hides reparented items (test finders recurse `contentItem`); a `Loader`-supplied `modelData` must not be declared `required`.
- **Name clashes:** no local QML file may share a base name with a type in the shell's `qs.Ui` (`/usr/share/omarchy/shell/Ui/*.qml`) or in `QtQuick.Controls` (`Label`, `Button`, `TextField`, `TextArea`, `Dialog`, `Popup`, `Frame`, `Pane`, `Page`, `Switch`, `Slider`, ...). The shell then loads *its* type, which is what broke `ConfirmDialog`. Use `ThemedText` (not `Label`) and `ActionButton` (not `Button`).
- **Panel entry point:** the shell loads the manifest's `entryPoints.barWidget`; it may live in a subfolder (`ui/Panel.qml`) but must not escape the plugin folder or be reached through a symlink inside the plugin.
- **Live check after structural tasks (2, 5, 6, 12, 13, 14):** `bash tests/live-check.sh` (created in Task 1) restarts the shell and fails on any `Plugin widget ... failed` journal line. Run it only when the plugin folder is `~/Code/omarchy-project-manager` and the plugin is enabled.

## Review Focus

1. **Relative imports that only fail in the real shell.** Directory imports (`import "../components" as C`) and `.import "../domain/x.js" as X` resolve relative to the importing file. The harness mirrors the repo layout so it catches most; `live-check.sh` catches the rest. Each structural task ends with it.
2. **Races lost while moving into `HelperRunner`.** A late exit from a previous project or an older run must never apply. The existing per-run-process tests (`test_a_late_exit_from_the_previous_project_is_ignored`, `test_a_stale_exit_after_the_newer_run_finished_keeps_the_good_list`, the memories/tag equivalents) must move to `HelperRunner`/store tests unchanged in meaning.
3. **Shell-type name clashes** for every new component name (see Global Constraints); Task 3 makes this a test.
4. **Helper script paths** used by `Panel.qml`, `install.sh`, tests and the README after the move to `core/backend/<domain>/`, and helpers' own imports of `common` (they run as `python3 <abs path>` with an arbitrary cwd).
5. **Unsaved-edit and modal guarantees** (dirty memory draft blocks section/project switch; modals block global shortcuts and take focus) surviving the move into `MemoriesStore`/`ProjectDeleteStore` and `Shortcuts.qml`.

---

## File Structure (target)

See the spec's Layout section for the full tree. Files this plan creates:

`tests/run.sh`, `tests/live-check.sh`, `tests/stubs/**` (moved), `tests/helpers/*`, `tests/architecture/test_layers.py`,
`core/backend/common/{__init__,json_line,safe_paths,atomic_write,frontmatter}.py`,
`core/domain/{projects,board,graph,documents,memories,taxonomy,results}.js`,
`core/stores/{App,NavigationStore,HelperRunner,FilterState,ProjectStore,ProjectDeleteStore,BoardStore,GraphStore,DocumentsStore,MemoriesStore}.qml`,
`ui/Panel.qml`, `ui/Shortcuts.qml`, `ui/theme/Theme.qml`,
`ui/components/{Badge,Chip,ChipRow,ModalCard,ActionButton,ThemedText,TextAreaBox,ListRow,ListStatus,FilterableList,Sidebar,TagPicker,TypedConfirmDialog,NewMemoryDialog,MemoryNoteView}.qml`,
`ui/screens/{BoardScreen,CardDetailScreen,GraphScreen,DocumentsScreen,DocumentScreen,MemoriesScreen,MemoryNoteScreen}.qml`,
`vendor/canvas/**` (moved from `canvas/`), `docs/architecture.md`.

---

### Task 1: Test harness that mirrors the repo layout, plus the live check

**Files:**
- Create: `tests/run.sh`, `tests/live-check.sh`, `tests/helpers/find.js`, `tests/helpers/README.md`
- Move: `tests/panel/stubs` → `tests/stubs`
- Modify: `run-tests.sh` (delegate), `tests/panel/run.sh` (delete), every `tests/panel/tst_*.qml` (component paths)
- Move: `tests/panel` → `tests/ui`, `tests/qml` → `tests/core/domain`

**Interfaces:**
- Produces: `bash tests/run.sh [path-filter]` — runs pytest (`tests/`), then every `tests/**/tst_*.qml` with the repo mirrored under a temp dir so relative imports match the real layout; exits non-zero on a failing test **or** on any harness-flagged warning (`TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function`, with the existing `width' of null` teardown exception).
- Produces: `tests/helpers/find.js` — `.pragma library`; `find(item, name)` (recurses `children`, `data`, `contentItem`), used by QML tests via `.import "../helpers/find.js" as H` (path relative to the test file).

- [ ] **Step 1: Record the baseline.** Run `./run-tests.sh; echo exit=$?`. Expected `exit=0`; note the pytest count (currently 168) and the per-file QML totals in `docs/superpowers/.baseline.txt` (not committed; used to compare counts after each task).

- [ ] **Step 2: Write `tests/run.sh`.**

```bash
#!/usr/bin/env bash
# Runs everything: pytest, then every QML test against the REAL repo files,
# mirrored into a temp dir so relative imports resolve exactly as in the plugin.
# Usage: tests/run.sh [substring-filter-for-qml-test-paths]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
cd "$repo"
filter="${1:-}"

python3 -m pytest tests -q

runner=$(command -v /usr/lib/qt6/bin/qmltestrunner || command -v qmltestrunner)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/repo"
tar --exclude=.git --exclude=__pycache__ --exclude=.pytest_cache --exclude=.superpowers -cf - . | tar -xf - -C "$work/repo"

status=0
while IFS= read -r test; do
  case "$test" in *"$filter"*) ;; *) continue ;; esac
  echo "== ${test#$repo/}"
  out=$(QT_QPA_PLATFORM=offscreen "$runner" -import "$work/repo/tests/stubs" -input "$work/repo/${test#$repo/}" 2>&1) || status=1
  echo "$out" | grep -E "^(FAIL|Totals)|^   Loc" || true
  bad=$(echo "$out" | grep -E "TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function" | grep -v "width' of null" || true)
  if [ -n "$bad" ]; then echo "$bad"; status=1; fi
done < <(find "$repo/tests" -name 'tst_*.qml' | sort)
exit $status
```

- [ ] **Step 3: Write `tests/live-check.sh`.**

```bash
#!/usr/bin/env bash
# Restarts the shell and fails if the plugin did not load. Needs the real shell.
set -euo pipefail
plugin="paulomtts.omarchy-project-manager"
omarchy-restart-shell >/dev/null 2>&1
sleep 8
omarchy-shell shell toggle "$plugin" >/dev/null 2>&1 || true
sleep 1
omarchy-shell shell toggle "$plugin" >/dev/null 2>&1 || true
bad=$(journalctl --user --since "-40sec" 2>/dev/null | grep -E "Plugin widget $plugin failed|summon: no live bar widget for: $plugin" || true)
if [ -n "$bad" ]; then echo "$bad"; exit 1; fi
echo "live check ok"
```

- [ ] **Step 4: Write `tests/helpers/find.js`.**

```js
.pragma library

// Depth-first search for an item by objectName through visual children, data
// and Flickable content. Returns null when absent.
function find(item, name) {
  if (!item) return null
  if (item.objectName === name) return item
  var lists = [item.children, item.data, item.contentItem ? [item.contentItem] : null]
  for (var l = 0; l < lists.length; l++) {
    var kids = lists[l] || []
    for (var i = 0; i < kids.length; i++) {
      var found = find(kids[i], name)
      if (found) return found
    }
  }
  return null
}
```

- [ ] **Step 5: Move files.** `git mv tests/panel/stubs tests/stubs; git mv tests/panel tests/ui; git mv tests/qml tests/core-domain-tmp && mkdir -p tests/core && git mv tests/core-domain-tmp tests/core/domain; git rm tests/ui/run.sh`.

- [ ] **Step 6: Point QML tests at the real layout.** In every `tests/ui/tst_*.qml` and `tests/core/domain/tst_logic.qml`: `Qt.createComponent("Panel.qml")` → `Qt.createComponent("../../Panel.qml")`; add `import "../.."` (directory import of the repo root) after the other imports wherever a view type (`DocumentsView`, `Sidebar`, ...) is used by name; `import "../../logic.js" as Logic` in `tst_logic.qml` (already relative to `tests/qml`: change to `"../../../logic.js"`). Local `find()` helpers stay for now (replaced in Task 12 when components move).

- [ ] **Step 7: Replace `run-tests.sh` body** with `exec bash "$(dirname "$0")/tests/run.sh" "$@"`.

- [ ] **Step 8: Run and compare.** `bash tests/run.sh; echo exit=$?` → `exit=0`, same pytest count and same per-file QML totals as the baseline.

- [ ] **Step 9: Commit** `Tests: one runner that mirrors the repo layout; live-check script; helpers dir`.

---

### Task 2: Spike — can a store own `Process`/`FileView` children? (harness and real shell)

**Files:**
- Create: `core/stores/SpikeStore.qml` (deleted at the end of the task), `tests/stubs/Quickshell/Scope.qml`, `tests/core/stores/tst_spike.qml` (deleted at the end)
- Modify: `docs/superpowers/specs/2026-09-24-core-ui-architecture-design.md` (record the outcome)

**Interfaces:** Produces a decision: stores' root type is `Scope` (preferred) or `QtObject` + `Component.createObject`.

- [ ] **Step 1: Write a minimal store.**

```qml
// core/stores/SpikeStore.qml
import Quickshell
import Quickshell.Io

Scope {
  id: store
  property string out: ""
  Process {
    id: proc
    command: ["python3", "-c", "print('ok')"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: store.out = String(text || "").trim() }
  }
  function run() { proc.running = true }
}
```

- [ ] **Step 2: Add the harness stub** `tests/stubs/Quickshell/Scope.qml`: `import QtQuick\nItem {}` and register `Scope 1.0 Scope.qml` in `tests/stubs/Quickshell/qmldir`. Write `tests/core/stores/tst_spike.qml` that creates `SpikeStore`, asserts `store.out === ""`, calls `run()`, and asserts the stub `Process.running` is true. Run `bash tests/run.sh spike` → expect PASS.

- [ ] **Step 3: Real-shell check.** Temporarily instantiate the spike from `Panel.qml` (`import "core/stores" as Core` and `Core.SpikeStore { id: spike }` under the root, plus `Component.onCompleted: spike.run()`), run `bash tests/live-check.sh`, then verify `journalctl --user --since "-1min" | grep -i spike` shows no error. Record whether it loaded.

- [ ] **Step 3b: If Scope fails in the real shell**, retry with `QtObject { property Process proc: Process {...} }` and record which works. If neither works, stores create their `Process` with `Component.createObject(store)` (already used for per-run processes); adjust the spec and this plan's `Scope` mentions to that.

- [ ] **Step 4: Revert the Panel edit, delete `SpikeStore.qml` and `tst_spike.qml`, keep the `Scope` stub.** Update the spec's risk paragraph with the outcome (one sentence).

- [ ] **Step 5: Commit** `Spike: confirm stores can own Process/FileView children`.

---

### Task 3: Architecture test (permissive) and duplicate detector

**Files:**
- Create: `tests/architecture/test_layers.py`

**Interfaces:** Produces `pytest tests/architecture` — checks: (a) import rules for `core/` and `ui/` (strict once those folders exist; today it only asserts what exists), (b) no local QML base name equals a shell `qs.Ui` or `QtQuick.Controls` type, (c) no duplicated helper definitions across non-test Python and QML/JS.

- [ ] **Step 1: Write the test.**

```python
"""Layer rule, shell-type name clashes, and duplicated-helper detection."""
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SHELL_UI = Path("/usr/share/omarchy/shell/Ui")
CONTROLS = {"Button", "Label", "TextField", "TextArea", "Dialog", "Popup", "Frame", "Pane", "Page",
            "Switch", "Slider", "ScrollBar", "ScrollView", "CheckBox", "ComboBox", "Menu", "Drawer",
            "GroupBox", "ToolTip", "ToolBar", "TabBar", "Tumbler", "SpinBox", "RadioButton", "Control"}
# Fallback so the test also works where the shell is not installed.
SHELL_FALLBACK = {"BarIconButton", "BarIndicator", "BarWidget", "BorderOverlay", "BorderSurface", "ButtonGroup",
                  "Button", "ConfirmDialog", "CursorSurface", "Dropdown", "KeyboardPanel", "MultiSelect",
                  "NumberField", "OpticalGlyph", "PanelActionButton", "PanelController", "PanelHero",
                  "PanelKeyCatcher", "PanelSectionHeader", "PanelSeparator", "PanelSlider", "PanelToolTip",
                  "PluginBarApi", "PointerMoveGate", "PopupCard", "ScreenMoveRemap", "SearchableDropdown",
                  "SpeedTestOverlay", "TextField", "Toggle", "ToggleSwitch", "WidgetButton"}
# The manifest entry point must be called Panel.qml, which the shell also has; that one clash is known and works.
ALLOWED_CLASH = {"Panel"}

SOURCE_DIRS = ["core", "ui", "vendor"]


def source_files(*suffixes):
    files = []
    for top in SOURCE_DIRS:
        for path in (ROOT / top).rglob("*") if (ROOT / top).exists() else []:
            if path.suffix in suffixes and "__pycache__" not in path.parts:
                files.append(path)
    # today's flat layout
    for path in ROOT.glob("*"):
        if path.is_file() and path.suffix in suffixes:
            files.append(path)
    return files


def shell_type_names():
    names = {p.stem for p in SHELL_UI.glob("*.qml")} if SHELL_UI.exists() else set()
    return names | SHELL_FALLBACK | CONTROLS


def test_no_local_qml_type_shares_a_name_with_a_shell_or_controls_type():
    clashes = sorted(p.name for p in source_files(".qml")
                     if p.stem in shell_type_names() and p.stem not in ALLOWED_CLASH)
    assert clashes == []


IMPORT_RE = re.compile(r'^\s*(?:\.?import)\s+(?:"([^"]+)"|([\w.]+))', re.M)

CORE_DOMAIN_FORBIDDEN = re.compile(r"^\s*import\s+(Qt|Quickshell|qs\.)", re.M)
CORE_STORES_FORBIDDEN = re.compile(r"^\s*import\s+(QtQuick|qs\.Ui|qs\.Commons)", re.M)


def test_core_never_imports_anything_visual():
    for path in source_files(".js", ".qml"):
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text()
        if rel.startswith("core/domain/"):
            assert not CORE_DOMAIN_FORBIDDEN.search(text), rel
            assert '.qml' not in " ".join(m[0] for m in IMPORT_RE.findall(text)), rel
        if rel.startswith("core/stores/"):
            assert not CORE_STORES_FORBIDDEN.search(text), rel
            for target in (m[0] for m in IMPORT_RE.findall(text) if m[0]):
                assert not target.lstrip("./").startswith(("ui/", "vendor/canvas/Canvas")), (rel, target)
        if rel.startswith("core/backend/"):
            assert path.suffix != ".qml", rel


DUPLICATED_PY = ["def emit(", "def inside(", "def write_atomic(", "def split_frontmatter(", "def frontmatter_of("]


def test_shared_python_helpers_are_defined_once():
    seen = {}
    for path in source_files(".py"):
        text = path.read_text()
        for needle in DUPLICATED_PY:
            if needle in text:
                seen.setdefault(needle, []).append(path.relative_to(ROOT).as_posix())
    # STRICT_AFTER_TASK_5: while helpers are still being ported this only records the state.
    if (ROOT / "core" / "backend" / "common").exists():
        assert all(len(v) == 1 for v in seen.values()), seen
```

- [ ] **Step 2: Run** `python3 -m pytest tests/architecture -q` → expect PASS on today's tree (the clash test passes because `TypedConfirmDialog` was already renamed; the duplicate test is inert until `core/backend/common` exists).
- [ ] **Step 3: Commit** `Tests: architecture test (name clashes, layer rule, duplicate helpers)`.

---

### Task 4: `core/backend/common` shared Python modules

**Files:**
- Create: `core/backend/common/{__init__,json_line,safe_paths,atomic_write,frontmatter}.py`, `tests/core/backend/common/test_{json_line,safe_paths,atomic_write,frontmatter}.py`

**Interfaces (Produces):**
- `json_line.emit(payload, code=0) -> int`: prints `json.dumps(payload)` on one line, returns `code`.
- `safe_paths.inside(root_real, path_real) -> bool`; `safe_paths.contained_file(root, rel) -> str|None` (real path of a regular file inside `root`, else None).
- `atomic_write.write_atomic(real_path, data: bytes, mode=None)` (existing file keeps its mode; new gets `mode` or 0o644) and `atomic_write.write_new(real_path, data, mode=0o644)` (raises `FileExistsError` if the name exists; content complete before the name appears).
- `frontmatter.split(text) -> (front_lines, body_lines)` and `frontmatter.value(front_lines, key) -> str|None` (case-insensitive key, quotes and trailing `# comment` stripped) and `frontmatter.set_key(text, key, value|None) -> str` (preserving newline style; `None` removes the key and drops an emptied block).

- [ ] **Step 1: Write the four test files first** (RED). Port the cases already covered in `tests/test_list_docs.py` (frontmatter fences, quotes, comments, unclosed block), `tests/test_set_doc_tag.py` (replace/append/remove/CRLF/emptied-block behaviour) and `tests/test_memory_op.py` (atomic write keeps mode, no temp files left, `write_new` loses a race with `FileExistsError`). Example for `test_json_line.py`:

```python
import io, json, sys
from contextlib import redirect_stdout
sys.path.insert(0, __file__.rsplit("/tests/", 1)[0] + "/core/backend")
from common import json_line


def test_emit_prints_one_json_line_and_returns_the_code():
    buf = io.StringIO()
    with redirect_stdout(buf):
        assert json_line.emit({"ok": True}, 3) == 3
    assert buf.getvalue() == '{"ok": true}\n'
    assert json.loads(buf.getvalue()) == {"ok": True}
```

- [ ] **Step 2: Run** `python3 -m pytest tests/core/backend/common -q` → expect import errors / failures (RED).
- [ ] **Step 3: Implement the modules** by moving (not copying) the existing implementations: `emit` from `list-docs.py`; `inside` from `list-docs.py`/`set-doc-tag.py`/`memory_lib.py`; `write_atomic` and `write_new` from `memory_lib.py`; the frontmatter fence detection from `list-docs.py::split_frontmatter`, the `tag:` line logic generalised to `value`/`set_key` from `set-doc-tag.py::edit` and `list-docs.py::tag_of`. Keep every behaviour the old tests assert. Files start with `import json, os, ...` only (stdlib).
- [ ] **Step 4: Run** the new tests → PASS. Old helpers are untouched in this task, so the whole suite stays green: `bash tests/run.sh; echo exit=$?` → 0.
- [ ] **Step 5: Commit** `Backend: shared common modules (json line, safe paths, atomic write, frontmatter)`.

---

### Task 5: Move the helpers into `core/backend/<domain>/` and port them onto `common`

Three commits (projects, documents, memories) in this order.

**Files (per domain):**
- Move + edit: `resolve-db-path.py`, `viewer-state.py`, `snapshot-and-forget.py` → `core/backend/projects/`; `list-docs.py`, `set-doc-tag.py` → `core/backend/documents/`; `list-memories.py`, `memory-op.py`, `memory_lib.py` → `core/backend/memories/`.
- Move tests: `tests/test_<script>.py` → `tests/core/backend/<domain>/test_<script>.py`; update `SCRIPT`/`HERE` path constants and the `conftest.py` `PLUGIN_DIR` usage.
- Modify: `Panel.qml` (every `root.pluginDir + "<script>.py"` → `root.pluginDir + "core/backend/<domain>/<script>.py"`), `install.sh` (only if it references a script), `README.md`, `tests/test_install.py` if it does.

**Interfaces:** Each script still prints the same one JSON line. Scripts import the shared modules with:

```python
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common import json_line, safe_paths, atomic_write, frontmatter  # noqa: E402
```

- [ ] **Step 1 (per domain): move with `git mv`**, fix test path constants, run `bash tests/run.sh; echo exit=$?` → 0 (paths only; nothing ported yet).
- [ ] **Step 2 (per domain): port onto `common`.** Replace each local `emit`, `inside`, atomic write, frontmatter parsing with the shared function; delete the local copy. `viewer-state.py` uses `atomic_write.write_atomic` (its temp+`os.replace` block). `list-docs.py` and `set-doc-tag.py` use `frontmatter`. `memory_lib.py` keeps only memory-specific code (slugs, index lines, filename checks) and imports `write_atomic`/`write_new`/`inside`/`frontmatter` from `common`; its own `frontmatter_of` becomes a thin call to `frontmatter.split` + `frontmatter.value`, keeping `metadata:` nested-type handling local.
- [ ] **Step 3 (per domain): update `Panel.qml` script paths** with one edit per script; there is exactly one occurrence each (verify with `grep -n '\.py"' Panel.qml`).
- [ ] **Step 4 (per domain): verify** `bash tests/run.sh; echo exit=$?` → 0, pytest count equals baseline plus the Task 4 additions, and `python3 -m pytest tests/architecture -q` passes (after the memories commit the duplicate-helper test is strict and must pass).
- [ ] **Step 5 (after the last domain): `bash tests/live-check.sh`** → `live check ok`.
- [ ] **Step 6: Commit** each domain: `Backend: move <domain> helpers to core/backend/<domain> and port onto common`.

---

### Task 6: Domain layer — `results.js`, `taxonomy.js`, split `logic.js`, vendor the canvas

**Files:**
- Create: `core/domain/{results,taxonomy,projects,board,graph,documents,memories}.js`
- Move: `canvas/` → `vendor/canvas/`
- Delete: `logic.js`
- Move + split: `tests/core/domain/tst_logic.qml` → one `tst_<module>.qml` per domain file
- Modify: every `import "logic.js" as Logic` site (Panel and the views) and `GraphView.qml`'s `import "canvas" as Local` → `import "vendor/canvas" as Local`

**Interfaces (Produces):**
- `results.js`: `parseJsonLine(stdout, exitCode, generic, requireOk=true) -> {ok, data, error}` — last non-empty stdout line parsed as JSON; `ok` is true only when `exitCode === 0`, the payload is an object, and (if `requireOk`) `payload.ok === true`; `error` is `payload.error` when a non-empty string, else `generic`.
- `taxonomy.js`: `makeTaxonomy(items) -> {ids, label(id), color(id, fallback), counts(list, key), filter(list, key, id), items}`. `counts` returns `[{id,label,count}]` for count > 0 in declaration order; `filter` with an empty/undefined id returns the list unchanged; `label` of an unknown id is `""`; `color` of an unknown id (or an item without a colour) is `fallback`.
- `documents.js` exports the existing document functions, now built on taxonomy (`DOC_TYPES = makeTaxonomy([...])`; `docCategoryLabel = DOC_TYPES.label`, etc.); `memories.js` likewise with `MEMORY_TYPES`. Function **names and return shapes of every existing exported function are unchanged.**

- [ ] **Step 1: Function → module map** (drives every caller edit):

| module | functions/values |
|---|---|
| `projects.js` | `filterProjects`, `chooseProject`, `parseStateResult`, `isDeleteConfirmed`, `parseDeleteResult` |
| `board.js` | `indexTree`, `subtreeCounts`, `subtreeMatches`, `matchesQuery`, `statusColor`, `kindLabel`, `effectiveStatus`, `boardOrder`, `detailLinks` |
| `graph.js` | `graphModel`, `graphMove`, `GRAPH_NODE_W`, `GRAPH_NODE_H` (imports `../../vendor/canvas/layout.js` and `board.js` for `subtreeCounts`) |
| `documents.js` | `filterDocs`, `parseDocsResult`, `docAbsolutePath`, `docTooLarge`, `MAX_DOC_BYTES`, `DOC_CATEGORIES`, `docCategoryLabel`, `docCategoryColor`, `filterDocsByCategory`, `docCategoryCounts`, `stripFrontmatter`, `parseTagResult` |
| `memories.js` | `MEMORY_TYPES`, `memoryTypeLabel`, `memoryTypeColor`, `filterMemoriesByType`, `memoryTypeCounts`, `filterMemories`, `parseMemoriesResult`, `parseMemoryOpResult`, `memoryAbsolutePath`, `newMemoryFile`, `yamlValue`, `composeMemory` |

- [ ] **Step 2: Write the new tests first (RED):** `tests/core/domain/tst_results.qml` (last-line parsing, exit code non-zero, `ok:false` with error, missing error → generic, garbage, `requireOk=false` for the state helper) and `tst_taxonomy.qml` (label/color/counts order and zero-omission/filter with empty id/unknown ids). Each imports the module with `import "../../../core/domain/results.js" as Results`.
- [ ] **Step 3: Create `results.js` and `taxonomy.js`; run the two tests → PASS.**
- [ ] **Step 4: Create the five domain files** by moving the functions per the map. Rebuild the six parsers on `Results.parseJsonLine` keeping return shapes (`parseDeleteResult` → `{ok, snapshot, error}`, `parseDocsResult` → `{ok, docs, truncated, error}`, etc.); rebuild the two type sets on `Taxonomy`. Each file starts with `.pragma library` and imports only siblings and (`graph.js`) the vendored `layout.js`. `git mv canvas vendor/canvas`.
- [ ] **Step 5: Split the tests.** Move each `test_*` function from `tst_logic.qml` into the `tst_<module>.qml` for its module (same bodies; import the module as `Logic`-equivalent alias per file, e.g. `import "../../../core/domain/memories.js" as Memories` and replace `Logic.memoryTypeLabel` with `Memories.memoryTypeLabel`). The union of test names must equal the old file's; verify with `grep -h "function test_" tests/core/domain/*.qml | sort | wc -l` ≥ the old count from the baseline plus the new tests.
- [ ] **Step 6: Re-point callers.** Run this one-off (do not commit it):

```python
# scratch/repoint.py — rewrites Logic.<fn>( uses and imports per the map above
import re, sys, pathlib
MAP = {  # fill from the Step 1 table
  "Projects": ["filterProjects","chooseProject","parseStateResult","isDeleteConfirmed","parseDeleteResult"],
  "Board": ["indexTree","subtreeCounts","subtreeMatches","matchesQuery","statusColor","kindLabel","effectiveStatus","boardOrder","detailLinks"],
  "Graph": ["graphModel","graphMove","GRAPH_NODE_W","GRAPH_NODE_H"],
  "Documents": ["filterDocs","parseDocsResult","docAbsolutePath","docTooLarge","MAX_DOC_BYTES","DOC_CATEGORIES","docCategoryLabel","docCategoryColor","filterDocsByCategory","docCategoryCounts","stripFrontmatter","parseTagResult"],
  "Memories": ["MEMORY_TYPES","memoryTypeLabel","memoryTypeColor","filterMemoriesByType","memoryTypeCounts","filterMemories","parseMemoriesResult","parseMemoryOpResult","memoryAbsolutePath","newMemoryFile","yamlValue","composeMemory"],
}
OWNER = {fn: mod for mod, fns in MAP.items() for fn in fns}
for path in map(pathlib.Path, sys.argv[1:]):
    text = path.read_text()
    used = set()
    def sub(m):
        mod = OWNER[m.group(1)]; used.add(mod); return mod + "." + m.group(1)
    text = re.sub(r"\bLogic\.(\w+)", sub, text)
    imports = "".join('import "core/domain/%s.js" as %s\n' % (m.lower(), m) for m in sorted(used))
    text = text.replace('import "logic.js" as Logic\n', imports)
    path.write_text(text)
```

Run it over `Panel.qml *.qml` (root files), then check `grep -rn 'Logic\.' --include=*.qml . | grep -v tests` is empty. Adjust the `import` prefix per file location (root files use `core/domain/…`; tests use relative `../../…`).
- [ ] **Step 7:** `git rm logic.js`; fix `GraphView.qml` import of the canvas; update `tests/architecture` nothing.
- [ ] **Step 8: Verify.** `bash tests/run.sh; echo exit=$?` → 0 with no `TypeError`/`ReferenceError`; `python3 -m pytest tests/architecture -q` passes; `bash tests/live-check.sh` → ok.
- [ ] **Step 9: Commit** `Domain: split logic.js into core/domain modules; shared results/taxonomy; vendor the canvas`.

---

### Task 7: Store foundations — `HelperRunner`, `FilterState`, `NavigationStore`, `App`

**Files:**
- Create: `core/stores/{HelperRunner,FilterState,NavigationStore,App}.qml`, `tests/core/stores/tst_{helper_runner,filter_state,navigation_store}.qml`, `tests/stubs/Quickshell/Io/*` additions if needed
- Modify: `Panel.qml` (instantiate `App`; move navigation state onto `app.nav`)

**Interfaces (Produces):**

```qml
// core/stores/HelperRunner.qml — one helper script, latest run wins.
import Quickshell
import Quickshell.Io
import "../domain/results.js" as Results

Scope {
  id: runner
  property string script: ""            // absolute path
  property string generic: "Something went wrong."
  property bool requireOk: true
  property bool busy: false
  property string guard: ""             // a result is applied only if this still equals the guard at launch
  property int seq: 0
  property var current: null
  signal finished(var result, string launchedGuard)   // result = Results.parseJsonLine(...)
  function run(args) {                  // args: string[]; stops the previous run
    if (current) current.running = false
    seq += 1
    busy = true
    var proc = procC.createObject(runner, { launchSeq: seq, launchGuard: guard })
    proc.command = ["python3", script].concat(args || [])
    current = proc
    proc.running = true
  }
  function cancel() { seq += 1; if (current) current.running = false; busy = false }
  Component {
    id: procC
    Process {
      id: p
      property int launchSeq: 0
      property string launchGuard: ""
      property string outText: ""
      stdout: StdioCollector { waitForEnd: true; onStreamFinished: p.outText = String(text || "") }
      stderr: StdioCollector { waitForEnd: true }
      onExited: function(exitCode) {
        if (p.launchSeq === runner.seq && p.launchGuard === runner.guard) {
          runner.busy = false
          runner.finished(Results.parseJsonLine(p.outText, exitCode, runner.generic, runner.requireOk), p.launchGuard)
        }
        p.destroy()
      }
    }
  }
}
```

```qml
// core/stores/FilterState.qml — one active filter value.
import QtQml
QtObject {
  property string active: ""
  signal toggled()
  function toggle(id) { active = active === id ? "" : id; toggled() }
  function clear() { active = "" }
}
```

`NavigationStore` members (moved verbatim from `Panel.qml`): `viewMode`, `section`, `sectionTitle`, `searchQuery`, `cursorIndex`, `scrollOnCursor`, `returnCursor`, `returnMode`, `returnScrollY`, `lastKeyMoveMs`, `dropdownOpen`, `dropdownQuery`, `dropdownCursor`; functions `resetSearch()`, `moveCursor(delta, count)` (sets `scrollOnCursor = true`, stamps `lastKeyMoveMs`, clamps), `hoverCursor(index)` (ignored within 300 ms of a key move), `pushReturn(scrollY)` / `popReturn()` (returns `{mode, cursor, scrollY}`), `toggleDropdown()`, `closeDropdown()`, `moveDropdown(delta, count)`. Scroll mechanics (`scrollToTop`, `scrollItemIntoView`, `scrollBy`, `revealTarget`) stay in `ui`. `App.qml`: `property string backendDir`; children `nav: NavigationStore {}`; more stores are added by later tasks.

- [ ] **Step 1: Tests first (RED).**
  - `tst_helper_runner.qml`: (a) `run(["x"])` sets `busy` and the stub `Process.command` to `["python3", script, "x"]`; (b) the newest run's exit emits `finished` with the parsed result; (c) **stale**: run A, run B, then A exits → no `finished`; B exits → one; (d) **stale after the newer finished**: run A, run B, B exits, then A exits → still exactly one `finished`; (e) **guard**: change `guard` after launch, then exit → no `finished`; (f) `cancel()` then exit → no `finished`. Drive exits by calling `proc.exited(code)` after setting `proc.outText`.
  - `tst_filter_state.qml`: toggle sets, toggling again clears, `toggled` emitted each time, `clear()`.
  - `tst_navigation_store.qml`: port the cursor/hover tests from `tests/ui/tst_documents_flow.qml` (`test_hover_caused_by_keyboard_scrolling_does_not_steal_the_cursor`), the section/sectionTitle derivations, dropdown movement clamping, and `pushReturn`/`popReturn` round trip.
- [ ] **Step 2: Run** `bash tests/run.sh stores` → RED.
- [ ] **Step 3: Implement the three files and `App.qml`**; keep `Panel.qml` behaviour by binding: in `Panel.qml` add `Core.App { id: app; backendDir: root.pluginDir + "core/backend/" }` and replace each moved member reference with `app.nav.<member>` (a sed over `Panel.qml` from the member list; `viewMode` alone has many references, so replace `root.viewMode` → `app.nav.viewMode` and bare `viewMode` uses inside `Panel.qml` functions by hand). `currentList()` stays in `Panel.qml` until Task 13 (it reads other stores).
- [ ] **Step 4: Migrate tests.** `tests/ui/tst_*.qml` references like `p.viewMode`, `p.cursorIndex`, `p.searchQuery`, `p.dropdownOpen` become `p.app.nav.<member>` (a `sed` over `tests/ui`). The Panel exposes `readonly property var app` for tests.
- [ ] **Step 5: Verify** `bash tests/run.sh; echo exit=$?` → 0; `bash tests/live-check.sh` → ok.
- [ ] **Step 6: Commit** `Stores: HelperRunner, FilterState, NavigationStore and App skeleton`.

---

### Task 8: `ProjectStore` and `ProjectDeleteStore`

**Files:**
- Create: `core/stores/{ProjectStore,ProjectDeleteStore}.qml`, `tests/core/stores/tst_{project_store,project_delete_store}.qml`
- Modify: `core/stores/App.qml`, `Panel.qml`; migrate `tests/ui/tst_{persistence,delete_flow,shortcuts_delete,sidebar_nav}.qml`

**Moves from `Panel.qml` (names verbatim):**
- `ProjectStore`: `projects`, `selectedProject`, `loadError`, `storedProject`, `stateLoaded`, `stateReadOk`, `watchedDbPath`, `filteredProjects` (derived from `nav.dropdownQuery` via a `dropdownQuery` property set by `App`), `applyProjectsList`, `maybeSelectInitial`, `clearSelection`, `selectProject`, `chooseProject`, `applyStoredState`, `persistLastProject`, `refreshProjects`, `onPanelOpened`; its helpers: `HelperRunner` for `brd projects` is **not** used (that is a direct `Process` running `brd`; keep it a `Process`), `HelperRunner` for `viewer-state.py get`, the 2 s state watchdog `Timer`, the `viewer-state.py set-project` and `resolve-db-path.py` processes.
- `ProjectDeleteStore`: `deleteTarget`, `confirmText`, `deleting`, `deleteError`, `lastSnapshot`, `openDelete`, `cancelDelete`, `performDelete`, and the `deleteProc`.
- Cross-store wiring in `App.qml`: `projects.dropdownQuery: nav.dropdownQuery`; `deleter.projects: projects`; a project change (`projects.selectedProjectChanged`) calls `nav.viewMode = "board"; nav.resetSearch()` and each domain store's `reset()` (added as later tasks land; for now `Panel.qml`'s `selectProject` keeps calling `resetMemories()` and the docs reset on the Panel).

- [ ] **Step 1: Tests first (RED).** Port with unchanged meaning: every test in `tst_persistence.qml` (initial project choice, `stateReadOk` gating, watchdog, late reply ignored, zero projects), `tst_delete_flow.qml`, and the delete parts of `tst_shortcuts_delete.qml` to store tests that drive stub `Process` objects directly (`app.projects`, `app.deleter`). `tst_sidebar_nav.qml` keeps Panel-level wiring tests.
- [ ] **Step 2: Run** the ported tests → RED (stores absent).
- [ ] **Step 3: Implement the two stores** by moving the code (cut from `Panel.qml`, paste into the store, replace `root.` with the store id, keep logic identical). Panel keeps only UI reads: `app.projects.selectedProject` etc.
- [ ] **Step 4: Re-point `Panel.qml` and the remaining `tests/ui` files** with a member-list `sed` (e.g. `p.selectedProject` → `p.app.projects.selectedProject`).
- [ ] **Step 5: Verify** `bash tests/run.sh; echo exit=$?` → 0; `python3 -m pytest tests/architecture -q`; `bash tests/live-check.sh`.
- [ ] **Step 6: Commit** `Stores: ProjectStore and ProjectDeleteStore`.

---

### Task 9: `BoardStore` and `GraphStore`

**Files:**
- Create: `core/stores/{BoardStore,GraphStore}.qml`, `tests/core/stores/tst_{board_store,graph_store}.qml`
- Modify: `App.qml`, `Panel.qml`; migrate `tests/ui/tst_{board_flow,graph_flow}.qml`

**Moves (verbatim):**
- `BoardStore`: `cardRoots`, `cardMap`, `statuses`, `selectedCardId`, `visibleBoardRoots`, `boardCards`, `detailLinkList`, `fetchBoard`, `applyTreeData`, `boardColumn`, `boardIndexOf`, `linkIndex`, `statusText`, `statusLabel`, `resolvedCard`, the `treeProc` and the `dbFile` `FileView` (watches `projects.watchedDbPath`, reload debounce as today). `openCard`/`restoreListView` move to `NavigationStore` + `BoardStore`: `BoardStore.openCard(id)` sets `selectedCardId` and returns whether it opened; `Panel`/`Shortcuts` call `nav.pushReturn(...)` and set the mode (the scroll position is a UI value passed in).
- `GraphStore`: `graph` (`Graph.graphModel(board.cardRoots)`), `graphCursor`, `moveGraph(direction)`, `activateGraphNode()` (returns the selected id or `""`; opening the card is the screen's job). Centering the view (`graphView.centerOn`) stays in UI: `GraphScreen` reacts to `graphCursorChanged`.

- [ ] **Step 1: Tests first (RED):** port `tst_board_flow.qml` and `tst_graph_flow.qml` cases (arrow keys along the chain, unknown selection recovers to first, project switch clears the cursor, the model updates when `cardRoots` changes) to store tests.
- [ ] **Step 2: Run** → RED. **Step 3: Implement** by moving code. **Step 4: Re-point** `Panel.qml` and `tests/ui`. **Step 5: Verify** as Task 8 (`tests/run.sh`, architecture, live check). **Step 6: Commit** `Stores: BoardStore and GraphStore`.

---

### Task 10: `DocumentsStore`

**Files:**
- Create: `core/stores/DocumentsStore.qml`, `tests/core/stores/tst_documents_store.qml`
- Modify: `App.qml`, `Panel.qml`; migrate `tests/ui/tst_documents_flow.qml`

**Moves (verbatim):** `docs`, `docsLoading`, `docsError`, `docsTruncated`, `selectedDocPath`, `docText`, `docError`, `docTooLargeFlag`, `docTagBusy`, `docTagError`, `selectedDocCategory`, `filteredDocs`, `fetchDocs`, `applyDocsResult`, `openDoc` (data part: sets `selectedDocPath`, clears text/errors, computes `docTooLargeFlag`; return position handled by `nav.pushReturn`), `restoreDocumentsList` (data part), `setDocTag`, `applyDocTagResult`, `toggleDocCategory` → **now** `category: FilterState {}` (`docCategory` becomes `category.active`; `toggleDocCategory(id)` = `category.toggle(id)` plus cursor reset via `category.onToggled`), the `docFile` `FileView`, and the two processes, which become two `HelperRunner`s (`lister` with guard = selected project root, `tagger`). `reset()` clears everything (called on project change).

- [ ] **Step 1: Tests first (RED):** every test from `tst_documents_flow.qml` that concerns state (fetch, result, filter+search, category toggle, doc-tag command line `["python3", ".../set-doc-tag.py", root, path, id]`, tag result refreshes the list, failed tag error, one change at a time, stale exits ignored (the four `test_a_*_exit_*` cases), too-large document not loaded, live reload text, read failure while in list does not set an error) — bodies unchanged apart from the `p.` → store access.
- [ ] **Step 2–6:** RED → implement by moving → re-point `Panel.qml`/`tests/ui` → verify → commit `Stores: DocumentsStore`.

---

### Task 11: `MemoriesStore`

**Files:**
- Create: `core/stores/MemoriesStore.qml`, `tests/core/stores/tst_memories_store.qml`
- Modify: `App.qml`, `Panel.qml`; migrate `tests/ui/tst_memories_flow.qml`

**Moves (verbatim):** all `memor*`/`newMemory*`/`pendingMemoryOpen` state listed in Panel lines 551–571 of the pre-refactor file, `memoryTypes`, `filteredMemories`, `canCreateMemory`, `selectedMemoryEntry`, `resetMemories` (renamed `reset` is **not** done; keep the name), `fetchMemories`, `applyMemoriesResult`, `toggleMemoryType` (→ `type: FilterState {}`), `openMemory` (data part), `restoreMemoriesList` (data part), `setMemoryText`, `startMemoryEdit`, `cancelMemoryEdit`, `memoryEscape`, `runMemoryOp`, `saveMemory`, `openNewMemory`, `cancelNewMemory`, `createMemory`, `requestMemoryDelete`, `cancelMemoryDelete`, `performMemoryDelete`, `applyMemoryOpResult`, the `memoryFile` `FileView`, and the processes: `lister` (`HelperRunner`, guard = project root) and `operator` (`HelperRunner`, one at a time; `memoryBusy` = `operator.busy`; `op`, `forFile`, `forRoot` recorded at `run` time on the store).
- The "dirty draft blocks switching" rule moves to `projects.chooseProject` via a `blocked` predicate property set by `App` (`projects.switchBlockedReason: memories.dirtyReason`), and to `Shortcuts`/`showSection` via the same predicate.

- [ ] **Step 1: Tests first (RED):** every test in `tst_memories_flow.qml` that is about state: fetch/list, type filter + search, open/back cursor restore (nav), editing save command line with `expected` argument, failed save keeps draft, Escape semantics, create composes file and opens it afterwards, late list does not pull you into a note, failed refresh keeps the folder, create never reuses a file name, failed create keeps dialog, canCreate, delete flow, dirty project-switch block, modal focus (this one stays a UI test).
- [ ] **Step 2–6:** RED → implement by moving → re-point → verify → commit `Stores: MemoriesStore`.

---

### Task 12: Shared UI components

Each component gets a test in `tests/ui/components/tst_<name>.qml`, is written test-first, and **replaces its duplicates in the same commit**. Components live in `ui/components/`; until Task 13 moves the rest, the views (still in the repo root) import them with `import "ui/components" as UI`.

**Files (Create):** `ui/components/{ThemedText,Badge,Chip,ChipRow,ActionButton,ModalCard,TextAreaBox,ListRow,ListStatus,FilterableList}.qml`, `ui/theme/Theme.qml`, matching tests.

**Interfaces (Produces):**
- `Theme.qml` (`pragma Singleton` is **not** used; plain object created once by `Panel` and passed as `theme`): `foreground`, `dim`, `urgent`, `fontFamily`, plus `bodySize`, `captionSize`, `headingSize` from `Style.font`.
- `ThemedText { property var theme; property string variant: "body" /* body|caption|heading|dim */ }`.
- `Badge { property string text; property color tint; property var theme }` — the pill (alpha-0.18 fill, tint text).
- `Chip { property string text; property color tint; property bool active; property bool busy; property var theme; signal clicked() }` — pill with border; `active` = filled+bold; ignores clicks when `busy`.
- `ChipRow { property var model /* [{id,label,count?,tint}] */; property string active; property bool busy; property var theme; signal chosen(string id) }` — `Flow` of `Chip`s; chip text is `label + (count !== undefined ? " " + count : "")`; objectName pattern `chip<id>`.
- `ActionButton { property string text; property string tone: "normal" /* normal|danger */; property var theme }` — wraps `qs.Ui` `Button` with the six shared style properties; emits `clicked()`; `enabled` dims it (`opacity 0.5`).
- `ModalCard { property bool shown; property bool dismissable: true; property real maxWidth; default property alias content: column.data; signal dismissed() }` — full-size item with the 0.55-black backdrop, click-outside → `dismissed()` when `dismissable`, card with `Color.popups.background/border`, click-inside swallowed. `TypedConfirmDialog` and `NewMemoryDialog` are rebuilt on it and the delete-project modal in `Panel.qml` is **replaced by a `TypedConfirmDialog`** driven by `app.deleter`.
- `TextAreaBox { property string text; property string placeholder; property real minHeight; property var theme; signal edited(string text); signal escapePressed(); signal submitRequested() }` — the bordered `TextArea` (Ctrl+Enter/Ctrl+S → `submitRequested`).
- `ListRow` — `CursorSurface` wrapper: `property int index; property int cursorIndex; property bool scrollOnCursor; signal hovered(int index); signal activated(); signal revealRequested(var item); default property alias content`.
- `ListStatus { property bool loading; property string error; property bool empty; property string emptyText; property string filteredText }` — one `Text` with the precedence loading > error > empty(filtered or plain); objectName `listStatus`.
- `FilterableList { property var model; property var chips; property string activeChip; property bool loading; property string error; property string emptyText; property string filteredText; property Component rowDelegate; ... signals chipToggled(string id), rowChosen(var entry), hovered(int), revealRequested(var item) }` — chips + status + rows.

- [ ] **Step 1 (per component): write its test (RED)**, e.g. `tst_chip.qml` (renders text, `active` bold, click emits, busy suppresses), `tst_chip_row.qml` (count suffix, active marker, `chosen` id, hidden when model empty), `tst_list_status.qml` (precedence and texts identical to today's `docsMessage`/`memoriesMessage`), `tst_modal_card.qml` (backdrop dismiss, card click swallowed, non-dismissable), `tst_badge.qml`, `tst_action_button.qml`, `tst_text_area_box.qml`, `tst_list_row.qml`, `tst_filterable_list.qml`. Use `tests/helpers/find.js`.
- [ ] **Step 2: implement the component**, run its test → PASS.
- [ ] **Step 3: replace duplicates** in the same commit:
  - `DocumentsView.qml`, `MemoriesView.qml`: rebuilt on `FilterableList` + `ListRow` + `Badge` + `ChipRow` (their public properties and signals stay for now; existing view tests must pass unchanged, including object names such as `docChip<id>` → provided through `ChipRow` `chipPrefix` property, and `docRowBadge<i>`, `memoryRowBadge<i>`, `docsMessage`/`memoriesMessage` → `ListStatus` `objectName` property set by the caller).
  - `TagPicker.qml`: `ChipRow`; `NewMemoryDialog.qml`: `ModalCard` + `ChipRow` + `TextAreaBox` + `ActionButton`; `TypedConfirmDialog.qml`: `ModalCard` + `ActionButton`; `MemoryNoteView.qml`: `Badge`, `TextAreaBox`, `ActionButton`; `Panel.qml` delete-project modal deleted and replaced by `TypedConfirmDialog` bound to `app.deleter` (the existing `deleteModal`/`deleteBackdrop`/`deleteCard`/`confirmField` object names used by `tst_delete_flow.qml` are provided through the dialog's `objectName` properties, or the tests are updated to the dialog's names with the same assertions).
  - Every `Text { color: root.foreground; font.family: ...; font.pixelSize: ... }` in the views and `Panel.qml` → `ThemedText`.
- [ ] **Step 4: grep proof** that the duplicates are gone: `grep -rn "radius: height / 2" --include=*.qml ui vendor . | grep -v "components/Badge.qml\|components/Chip.qml"` and `grep -rn "Qt.rgba(0, 0, 0, 0.55)" --include=*.qml . | grep -v ModalCard` both return nothing; `grep -rn "bordered: true" --include=*.qml . | grep -v ActionButton` returns nothing.
- [ ] **Step 5: Verify** `bash tests/run.sh; echo exit=$?` → 0; architecture; `bash tests/live-check.sh`.
- [ ] **Step 6: Commit** one commit per component group: (Badge, Chip, ChipRow), (ModalCard + dialogs + delete modal), (ActionButton), (ThemedText/Theme), (TextAreaBox), (ListRow, ListStatus, FilterableList).

---

### Task 13: `ui/` — screens, `Shortcuts`, slim `Panel`, move files, flip the entry point

**Files:**
- Create: `ui/Panel.qml` (from the root `Panel.qml`), `ui/Shortcuts.qml`, `ui/screens/*.qml`
- Move: `Sidebar.qml`, `TagPicker.qml`, `TypedConfirmDialog.qml`, `NewMemoryDialog.qml`, `MemoryNoteView.qml` → `ui/components/`; `DocumentsView.qml`, `MemoriesView.qml`, `GraphView.qml` become the bodies of `DocumentsScreen.qml`, `MemoriesScreen.qml`, `GraphScreen.qml`
- Modify: `manifest.json` (`"barWidget": "ui/Panel.qml"`), tests (component paths), `install.sh` if it references the entry point, `README.md`

**Interfaces:**
- `ui/Shortcuts.qml`: `Item { property var app; property var actions; function handleGlobalKey(event) -> bool; function closeRequested() }`; contains exactly today's `handleGlobalKey` (Ctrl+P/1/2/3/4/N/E, modal and dirty-draft guards) and the Escape ordering chain from `keyCatcher.onCloseRequested`; every branch calls store functions or `actions.<name>()` for UI-only effects (`focusForView`, `scrollToTop`).
- Screens take `property var app` and `property var theme`, bind to store properties and call store functions; they own the presentation-only state (`focusItem` targets, scroll reveal). `ui/Panel.qml` holds: the bar icon, `KeyboardPanel`/`PanelKeyCatcher`, `Sidebar`, the fixed toolbar, the `Flickable` hosting the active screen, the modals, `focusItem`, scroll helpers, and the theme; target under about 400 lines.
- The old root-level `*.qml`/`Panel.qml` are gone; `ui/Panel.qml` keeps `moduleName`/`ipcTarget` unchanged.

- [ ] **Step 1: Write tests first (RED)** for the new pieces: `tests/ui/tst_shortcuts.qml` (Ctrl+1..4 map to sections, Ctrl+N only in the memories list, Ctrl+E only in a note, all Ctrl shortcuts blocked while any modal or `deleteTarget` is open, the dirty-draft block), one screen test per screen asserting it renders from a fake `app` (build the fake with the real stores via `App`, feeding stub results — no bespoke mocks).
- [ ] **Step 2: Move and re-import.** `git mv` the files; fix relative imports (`import "../components" as C`, `import "../../core/stores" as Core`, `import "../../vendor/canvas" as Canvas`); update `tests/ui/*.qml` component paths (`Qt.createComponent("../../ui/Panel.qml")`, `import "../../ui/screens"` etc.).
- [ ] **Step 3: Extract screens** from `Panel.qml`'s `Flickable` content column one screen at a time, each commit-sized: Board, CardDetail, Graph, Documents, Document, Memories, MemoryNote. Each extraction keeps behaviour and object names (`documentsView`, `memoriesView`, `memoryNoteView`, `graphView`, `tagPicker`) so existing tests need only path updates.
- [ ] **Step 4: Extract `Shortcuts.qml`**, leaving `Panel.qml` to forward `Keys.onPressed`/`onCloseRequested`/`onMoveRequested` to it.
- [ ] **Step 5: Flip the manifest** entry point; `omarchy plugin validate .` → exit 0; **do not** touch the symlink (it links the folder).
- [ ] **Step 6: Verify** `bash tests/run.sh; echo exit=$?` → 0; `wc -l ui/Panel.qml` under ~400; `bash tests/live-check.sh` → ok.
- [ ] **Step 7: Commit** per extraction step, final: `UI: move to ui/, screens, Shortcuts, manifest entry point ui/Panel.qml`.

---

### Task 14: Enforce, document, clean up

**Files:**
- Modify: `tests/architecture/test_layers.py` (strict), `README.md`, `docs/superpowers/specs/2026-09-24-core-ui-architecture-design.md` (status → implemented)
- Create: `docs/architecture.md`
- Delete: any leftover empty dirs, `docs/superpowers/.baseline.txt`

- [ ] **Step 1: Make the architecture test strict:** remove the "today's flat layout" scan (`ROOT.glob("*")`), require `core/`, `ui/`, `vendor/` to exist, and assert that **no `.qml`, `.js` or `.py` source file remains at the repo root** except `install.sh`.
- [ ] **Step 2: Prove the guarantees** (each is a test that already exists; list them in the commit message): layer rule, name clashes, duplicate helpers, and the grep checks from Task 12 Step 4.
- [ ] **Step 3: Write `docs/architecture.md`** (one page: the layer table from the spec, the store list with one line each, the rule "reuse before writing a second copy" with the component/helper names, how to add a screen/store/helper script, how to run tests and the live check) and rewrite the README "Layout"/"Tests" sections to match.
- [ ] **Step 4: Final verification.** `bash tests/run.sh; echo exit=$?` → 0; `python3 -m pytest tests/architecture -q`; `bash tests/live-check.sh`; then the manual smoke checklist (done by the user or by driving the shell): open the panel; visit Board, Graph, Documents, Memories; open a card and go back; tag a document; edit and save a memory note; create and delete one; delete-project dialog opens and Escape cancels; keyboard shortcuts Ctrl+P/1/2/3/4; shell journal shows no plugin errors.
- [ ] **Step 5: Commit** `Enforce the layer rule; architecture docs`.
- [ ] **Step 6: Finish the branch** with superpowers:finishing-a-development-branch (merge locally / PR / keep) — the user decides; do not push.

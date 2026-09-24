# Architecture

One rule: **`ui/` may use `core/`; `core/` never imports anything visual.**
`tests/architecture/test_layers.py` enforces it (allowlists, not denylists).
Design background: `docs/superpowers/specs/2026-09-24-core-ui-architecture-design.md`.

## Layers

| layer | may import | must not import |
|---|---|---|
| `core/domain/*.js` | other `core/domain` files, `vendor/canvas/*.js` (`.pragma library`, `.import "x.js" as X` only) | any QML, `Qt*`, `Quickshell*`, `qs.*` |
| `core/backend/**` | Python stdlib, `core/backend/common` | any QML |
| `core/stores/*.qml` | `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/*.js` | `QtQuick*`, `qs.*`, `ui/`, `vendor/`, sibling directories |
| `ui/**` | everything in `core/`, `qs.Ui`, `qs.Commons`, `QtQuick*`, `vendor/canvas` | `ui/screens/**` must not import `core/stores` (they receive `app`) |
| `vendor/**` | its own files, `qs.*`, `QtQuick*` | `core/`, `ui/` |

Repo root holds no `.qml`/`.js`/`.py` except `install.sh`. `ui/Panel.qml` is the
manifest entry point.

## Stores (`core/stores`)

- `App.qml` composes the stores below and wires them by explicit properties.
- `HelperRunner.qml` runs one helper script: latest run wins, stale-exit guard; emits raw stdout, stores parse it.
- `FilterState.qml` one active filter with toggle and cursor reset.
- `NavigationStore.qml` view mode, section, push/pop return positions, cursor, search, dropdown.
- `ProjectStore.qml` registry, selection, remembered project, DB watch path.
- `ProjectDeleteStore.qml` delete-project confirm/snapshot flow.
- `BoardStore.qml` cards, index, selection, board order; owns the DB `FileView`.
- `GraphStore.qml` graph model from the board, graph cursor and movement.
- `DocumentsStore.qml` listing, category filter, open document, tagging.
- `MemoriesStore.qml` listing, type filter, open/edit/create/delete a note.

Other `ui/` pieces: `Navigator.qml` (screen switching), `Shortcuts.qml` (key
events to store calls), `theme/Theme.qml` (colours and fonts from the shell).

## Shared components (`ui/components`) - reuse before writing a second copy

`ThemedText` (text), `ActionButton` (bordered button), `Badge` (pill),
`Chip` and `ChipRow` (filter chips), `ModalCard` (dimmed backdrop and card),
`TypedConfirmDialog`, `ListRow` (hover / keyboard cursor / reveal),
`ListStatus` (loading/error/empty), `FilterableList`, `TextAreaBox`,
`TagPicker`, `NewMemoryDialog`, `Sidebar`, and the views
`DocumentsView`, `MemoriesView`, `MemoryNoteView`, `GraphView`.
Domain helpers: `taxonomy.js` (typed labels), `results.js` (one JSON line +
exit code), `text.js` (`matchesQuery`); Python: `core/backend/common`
(`json_line`, `safe_paths`, `atomic_write`, `frontmatter`).

When a thing is needed a second time it becomes shared **before** the second
use is written. The architecture test fails on a second copy of: the modal
backdrop `Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`,
`font.family:`, `CursorSurface {`, and of `emit`/`inside`/`write_atomic`/
`split_frontmatter`/`frontmatter_of` in Python. It also rejects component
names that clash with shell (`qs.Ui`) or QtQuick/Controls types: the shell
would load its own type instead of ours.

## How to add

- **A screen**: `ui/screens/XScreen.qml` with `property var app`; use only shared
  components and `app` (never import `core/stores`); register it in `Navigator.qml`;
  add a test under `tests/ui/`.
- **A store**: `core/stores/XStore.qml` importing only `QtQml`/`Quickshell`/
  `Quickshell.Io` and `../domain/x.js`; run helpers through `HelperRunner`;
  compose it in `App.qml`; test headless under `tests/core/stores/`.
- **A helper script**: `core/backend/<domain>/name.py`, one JSON line on stdout,
  `sys.path` insert of its parent for `common`, no duplicated helpers; pytest
  under `tests/core/backend/<domain>/`; call it via `backendDir` from a store.

## Tests

- `bash tests/run.sh [filter]` - pytest, then every QML test against a mirror of the repo (`./run-tests.sh` delegates to it).
- `python3 -m pytest tests/architecture -q` - layer and duplication rules only.
- `bash tests/live-check.sh` - restarts the real shell and fails on plugin load errors in the journal (needs the desktop session).

## Documented exceptions

- `Panel.qml` shares a name with a shell type: it is loaded by manifest path.
- `vendor/canvas/Canvas.qml`: always used qualified.
- Panel-detail tone pill (`CardDetailScreen`) uses `radius: height / 2` itself, not `Badge`.
- `BoardCard` (BoardScreen) and Sidebar's project button, `NavRow`, `ProjectItem` use `CursorSurface` directly (and `bordered: true` for the two bordered ones).
- `Badge`, `Chip`, `TextAreaBox` set `font.family` on the primitive they own.

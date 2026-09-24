# Architecture

One rule: **`ui/` may use `core/`; `core/` never imports anything visual.**
`tests/architecture/test_layers.py` enforces it (allowlists, not denylists).
Design background: `docs/superpowers/specs/2026-09-24-core-ui-architecture-design.md`.

## Layers

| layer | may import | must not import |
|---|---|---|
| `core/domain/*.js` | other `core/domain` files, `vendor/canvas/*.js` (`.pragma library`, `.import "x.js" as X` only) | any QML, `Qt*`, `Quickshell*`, `qs.*` |
| `core/backend/**` | Python stdlib, `core/backend/common` | any QML |
| `core/*` | only `domain/`, `backend/`, `stores/` (no loose files); `backend/` has no `.js`/`.qml` | |
| `core/stores/*.qml` | `QtQml`, `Quickshell`, `Quickshell.Io`, `../domain/*.js` | `QtQuick*`, `qs.*`, `ui/`, `vendor/`, sibling directories |
| `ui/**` | everything in `core/`, `qs.Ui`, `qs.Commons`, `QtQuick*`, `vendor/canvas` | `ui/screens/**` and `ui/components/**` must not import `core/stores` (they receive `app`/props); only `Panel`, `Shortcuts`, `Navigator` may |
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
- `BoardStore.qml` cards, index, selection, board order, the issue map (`brd issue list`; an old brd without issues is just an empty map); owns the DB `FileView` and the 250ms `watchTimer` that debounces it, so a burst of writes costs one tree+issue+export fetch (`fetchBoard()` itself -- Refresh, a project switch -- stays immediate).
- `GraphStore.qml` the two graph models from the board (card roots and issue
  map, for each node's open-issue count): the milestone graph and the story
  graph (`graph.js`'s `graphModel` / `storyGraphModel`). `graphView`
  ("milestone", the default, or "story") picks which one `currentNodes` /
  `currentEdges` / `currentGroups` -- and so the canvas, the arrow keys and
  Enter -- work on; `setGraphView` refuses anything else, so one of the two
  chips is always active, and keeps the selection on a node of the new view.
  Nothing resets it, so the choice is remembered for the session and survives a
  project switch (the cursor still clears with the project). Plus the graph
  cursor and its movement.
- `DocumentsStore.qml` listing, category filter, open document, tagging, plus
  brd's registered documents (`brd doc list`, fetched only when the section
  opens because it syncs -- writes -- every backup; re-entering the section you
  are already in does not run it again, and a `source_path` that leaves the
  project -- absolute, or with a `..` segment -- is dropped). `mergedDocs` matches the
  listing and the registrations on the path relative to the project root; a
  registration whose file is gone stays in the list as `missing: true`. A failed
  listing leaves the registrations already shown in place.
- `ExtrasStore.qml` the read-only extras from one `brd export`: comments by
  entity, EXPLICIT refs both ways (the export's `refs[]` carry only the refs
  written with `--ref`; the origin `"link"` refs a `[[wikilink]]` creates are
  reported per entity by `brd show`/`brd issue list`, which this store does not
  read), and the rich issue list (body, close reason, comment
  count, and the cards an issue blocks, derived from the export's nested card
  tree because an exported issue carries no `blocks` of its own). Fetched with
  the board through `BoardStore.refetched()`, and any failure -- an old brd
  without `export`, a crash, garbage -- is simply empty extras, never an error.
  It never feeds the board: the blocker rows and the graph keep reading
  `BoardStore.issueMap` (`brd issue list`).
- `MemoriesStore.qml` listing, type filter, open/edit/create/delete a note.
- `MilestoneStore.qml` the New-milestone dialog and the one agent job
  (`idle -> running -> done|failed`): two `HelperRunner`s, both
  `run-setup-milestone.py` -- the run itself, and `--describe`, which the
  dialog asks for once per project as it opens. It never reaches for the board: `App` hands it `cardCount` and
  routes its `boardRefreshRequested()` to `board.fetchBoard()`. The spec
  runner's guard is the project the JOB is for, not the selected one, so a run
  that outlives a project switch is still recorded truthfully; `jobVisible`
  decides whose panel shows it.

Other `ui/` pieces: `Navigator.qml` (screen switching), `Shortcuts.qml` (key
events to store calls; Ctrl+1..5 follow the sidebar's order: Board, Graph,
Documents, Memories, Issues), `theme/Theme.qml` (colours and fonts from the shell).

Not every process goes through `HelperRunner`: `listProc` (`brd projects`), `treeProc` (`brd tree`), `issueProc` (`brd issue list`), `exportProc` (`brd export`), `brdDocsProc` (`brd doc list`), `saveStateProc`, `resolveDbPathProc` and `deleteProc` stay plain `Process` objects because they run the `brd` CLI or are fire-and-forget/single-owner with their own exit handling. `HelperRunner.run()` SIGTERMs a previous run of the same helper instead of letting it finish and dropping its reply (reachable for list-docs/list-memories refetches, and a set-doc-tag started in another project mid-flight); helpers write atomically, so at worst a stray `docs/.tmp-*` remains.

## Shared components (`ui/components`) - reuse before writing a second copy

`ThemedText` (text), `ActionButton` (bordered button), `Badge` (pill),
`Breadcrumbs` (the toolbar's location trail; `Navigator.crumbs` builds the list
and `Navigator.activateCrumb(index)` acts on a click, so the component stays
presentational),
`Chip` and `ChipRow` (filter chips), `CommentList` (the read-only brd comments
of one entity, used by the card detail and the issue detail),
`ModalCard` (dimmed backdrop and card),
`TypedConfirmDialog`, `ListRow` (hover / keyboard cursor / reveal),
`ListStatus` (loading/error/empty), `FilterableList`, `TextAreaBox`,
`TagPicker`, `NewMemoryDialog`, `NewMilestoneDialog` (the from-spec modal),
`MilestoneJobIndicator` (the toolbar strip while a milestone job runs, and its
result), `StatusPips` (one status circle per subtask on a story node, the
overflow as a `+N`; its single pulse animation runs only while the row is
visible AND holds an in-progress pip, so an idle graph animates nothing),
`Sidebar`, and the views
`DocumentsView`, `MemoriesView`, `MemoryNoteView`, `GraphView`.
`Sidebar`'s five nav rows (Board, Graph, Documents, Memories, Issues) each lead with an
icon glyph drawn in the theme's font; `tests/architecture/test_icon_glyphs.py`
checks every glyph literal in `ui/` and `vendor/` against the installed Nerd
Fonts, because a glyph the font does not have renders as an empty box.
`ui/screens/DocumentsToolbar.qml` is the Documents half of the panel's fixed
toolbar - the category chips of the list, and the path and type picker of an
open document - so only the document body scrolls.
Domain helpers: `taxonomy.js` (typed labels), `results.js` (one JSON line +
exit code), `text.js` (`matchesQuery`), `milestones.js` (the two helper
parsers, `agentMessage`, `formatElapsed`, the spec-list ordering and filter),
`brd-extras.js` (the `brd export` and `brd doc list` parsers, the issue
ordering/filtering and its wording, and `relativeTime` for a comment's age; the
export's `documents[]` carry every registered file's full content and are
dropped unread), and `documents.js`'s `mergeRegistered` / `brdStateLabel` for
brd's registrations;
Python: `core/backend/common`
(`json_line`, `safe_paths`, `atomic_write`, `frontmatter`).
`core/backend/milestones/` is the New-milestone backend:
`setup-milestone.md` (the prompt the agent is given),
`agents.py` (one adapter per coding agent: the exact argv, whether the run can
be restricted, and the `--help` lines that justify it) and
`run-setup-milestone.py`, which resolves the default agent through
`omarchy-default-agent`, spawns it in its own session (argv only, never a
shell), enforces `OPM_AGENT_TIMEOUT_SECONDS` (default 1800), kills the whole
process group on cancel or timeout, and logs to
`${XDG_STATE_HOME:-~/.local/state}/omarchy-project-manager/agent-logs/`
(dir `0700`, file `0600`). Only `claude` runs restricted (read plus
`Bash(brd *)`); every other agent runs with full auto-approval, which the
dialog states before the run starts.

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
- `python3 -m pytest tests/contract -q` - runs the installed `brd` in a throwaway
  project (its own `HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME` under a tmp dir, so no
  real board is read or written) and fails when brd's JSON shape drifts from what
  `core/domain/brd-extras.js` parses; skipped when `brd` is absent.
- `bash tests/live-check.sh` - restarts the real shell and fails on plugin load errors in the journal (needs the desktop session).

## Documented exceptions

- `Panel.qml` shares a name with a shell type: it is loaded by manifest path.
- `vendor/canvas/Canvas.qml`: always used qualified.
- Panel-detail tone pill (`CardDetailScreen`) uses `radius: height / 2` itself, not `Badge`.
- `StatusPips` uses `radius: height / 2` too: a subtask pip is a small circle
  carrying no text, so neither `Badge` nor `Chip` fits.
- `GraphView`'s story boxes are an Item INSIDE the vendored canvas with `z: -1`,
  mirroring its camera (`panX`/`panY`/`zoom`): the canvas draws nodes and edges
  only, and the boxes must paint behind them. `fitAll()` frames the nodes, so a
  box's own padding can sit just outside the frame at high zoom.
- `BoardCard` (BoardScreen) and Sidebar's project button, `NavRow`, `ProjectItem` use `CursorSurface` directly (and `bordered: true` for the two bordered ones).
- `TextAreaBox` sets `font.family` itself: it is a `Controls.TextArea`, not a `Text`, so it cannot be a `ThemedText`.
